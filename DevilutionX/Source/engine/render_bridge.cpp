#include "engine/render_bridge.hpp"
#include "engine/render/scrollrt.h"
#include "engine/dx.h"

#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <cstring>
#include <mutex>
#include <vector>
#include <thread>
#include <atomic>

#include "control.h"
#include "player.h"
#include "levels/gendung.h"
#include "diablo.h"
#include "utils/paths.h"
#include "engine/assets.hpp"

namespace devilution {

bool gbGodotBridgeActive = true;
D1EngineData g_D1EngineData;

namespace {
int g_ShmFd = -1;
void *g_ShmMapped = nullptr;
size_t g_ShmTotalSize = 0;
uint32_t g_BridgeFrameCount = 0;

std::mutex g_D1FrameMutex;
std::vector<uint8_t> g_D1InternalFrame;

std::mutex g_DirectInputMutex;
std::vector<D1InputMsg> g_DirectInputQueue;

std::thread g_DiabloThread;
} // namespace

std::atomic<bool> g_DiabloThreadRunning{false};
std::atomic<bool> g_D1EngineQuitRequested{false};

void InitGodotBridge(int width, int height)
{
	size_t payloadSize = static_cast<size_t>(width) * height * 4;
	size_t reqSize = sizeof(D1BridgeHeader) + payloadSize;

	if (g_ShmMapped != nullptr && g_ShmTotalSize == reqSize)
		return;

	CleanupGodotBridge();

	g_ShmTotalSize = reqSize;
	g_ShmFd = open("/dev/shm/d1_godot_frame", O_RDWR | O_CREAT, 0666);
	if (g_ShmFd >= 0) {
		if (ftruncate(g_ShmFd, reqSize) == 0) {
			g_ShmMapped = mmap(nullptr, reqSize, PROT_READ | PROT_WRITE, MAP_SHARED, g_ShmFd, 0);
		}
	}
}

void ExportGodotFrame(const SDL_Surface *surface)
{
	if (!gbGodotBridgeActive || surface == nullptr || surface->pixels == nullptr || surface->w <= 0 || surface->h <= 0)
		return;

	const SDL_Surface *srcSurface = surface;
	SDL_Surface *converted = nullptr;

	if (surface->format == nullptr || surface->format->BytesPerPixel != 4) {
		converted = SDL_ConvertSurfaceFormat(const_cast<SDL_Surface *>(surface), SDL_PIXELFORMAT_ARGB8888, 0);
		if (converted != nullptr && converted->pixels != nullptr) {
			srcSurface = converted;
		} else {
			if (converted != nullptr) SDL_FreeSurface(converted);
			return;
		}
	}

	// 1. Update In-Process Direct Engine Data (Zero IPC!)
	{
		std::lock_guard<std::mutex> lock(g_D1FrameMutex);
		g_BridgeFrameCount++;
		g_D1EngineData.frameId = g_BridgeFrameCount;
		g_D1EngineData.width = srcSurface->w;
		g_D1EngineData.height = srcSurface->h;
		g_D1EngineData.playerNormX = 0.50f;
		g_D1EngineData.playerNormY = 0.52f;

		if (MyPlayer != nullptr) {
			g_D1EngineData.playerTileX = MyPlayer->position.tile.x;
			g_D1EngineData.playerTileY = MyPlayer->position.tile.y;
			g_D1EngineData.playerHp = MyPlayer->_pHitPoints >> 6;
			g_D1EngineData.playerMaxHp = MyPlayer->_pMaxHP >> 6;
			g_D1EngineData.playerMana = MyPlayer->_pMana >> 6;
			g_D1EngineData.playerMaxMana = MyPlayer->_pMaxMana >> 6;
			g_D1EngineData.playerGold = MyPlayer->_pGold;
			g_D1EngineData.playerClass = static_cast<int>(MyPlayer->_pClass);
		}

		g_D1EngineData.currentLevel = currlevel;
		g_D1EngineData.dungeonType = leveltype;
		g_D1EngineData.leftPanelOpen = IsLeftPanelOpen();
		g_D1EngineData.rightPanelOpen = IsRightPanelOpen();

		size_t reqBytes = static_cast<size_t>(srcSurface->w) * srcSurface->h * 4;
		if (g_D1InternalFrame.size() != reqBytes) {
			g_D1InternalFrame.resize(reqBytes);
		}
		std::memcpy(g_D1InternalFrame.data(), srcSurface->pixels, reqBytes);
	}

	// 2. Also write to POSIX SHM for backward compatibility
	InitGodotBridge(srcSurface->w, srcSurface->h);
	if (g_ShmMapped != nullptr) {
		D1BridgeHeader *hdr = static_cast<D1BridgeHeader *>(g_ShmMapped);
		hdr->magic = 0x44315242; // "D1RB"
		hdr->version = 1;
		hdr->width = srcSurface->w;
		hdr->height = srcSurface->h;
		hdr->pitch = srcSurface->pitch;
		hdr->frameId = g_BridgeFrameCount;
		hdr->timestamp = SDL_GetTicks();
		hdr->playerNormX = 0.50f;
		hdr->playerNormY = 0.52f;
		hdr->zoomMode = (CurrentZoomMode == ZoomMode::Zoomed_2x) ? 3 : (CurrentZoomMode == ZoomMode::Balanced_1_5x ? 2 : 1);
		hdr->torchCount = 0;

		// Export UI Panel States (Character sheet, Inventory, Quest log, Spellbook)
		hdr->torches[0].normX = g_D1EngineData.leftPanelOpen ? 1.0f : 0.0f;
		hdr->torches[0].normY = g_D1EngineData.rightPanelOpen ? 1.0f : 0.0f;

		// Copy pixels directly to shared memory
		uint8_t *dstPixels = static_cast<uint8_t *>(g_ShmMapped) + sizeof(D1BridgeHeader);
		std::memcpy(dstPixels, srcSurface->pixels, srcSurface->w * srcSurface->h * 4);

		hdr->readyFlag = 1;
	}

	if (converted != nullptr) {
		SDL_FreeSurface(converted);
	}
}

void PollGodotBridgeInput()
{
	// 1. Process in-process GDExtension direct input queue
	{
		std::lock_guard<std::mutex> lock(g_DirectInputMutex);
		for (const auto &msg : g_DirectInputQueue) {
			SDL_Event ev {};
			if (msg.type == 1) { // Mouse Motion
				ev.type = SDL_MOUSEMOTION;
				ev.motion.x = msg.x;
				ev.motion.y = msg.y;
				SDL_PushEvent(&ev);
			} else if (msg.type == 2) { // Mouse Button
				ev.type = (msg.state != 0) ? SDL_MOUSEBUTTONDOWN : SDL_MOUSEBUTTONUP;
				ev.button.state = (msg.state != 0) ? SDL_PRESSED : SDL_RELEASED;
				ev.button.button = (msg.code == 1) ? SDL_BUTTON_LEFT : ((msg.code == 2) ? SDL_BUTTON_MIDDLE : SDL_BUTTON_RIGHT);
				ev.button.x = msg.x;
				ev.button.y = msg.y;
				SDL_PushEvent(&ev);
			} else if (msg.type == 3) { // Key
				ev.type = (msg.state != 0) ? SDL_KEYDOWN : SDL_KEYUP;
				ev.key.state = (msg.state != 0) ? SDL_PRESSED : SDL_RELEASED;
				if (msg.state != 0 && msg.x >= 32 && msg.x < 127) {
					ev.key.keysym.sym = static_cast<SDL_Keycode>(msg.x);
				} else {
					ev.key.keysym.sym = static_cast<SDL_Keycode>(msg.code);
				}
				SDL_PushEvent(&ev);
			} else if (msg.type == 4) { // Zoom In
				ZoomInMode();
			} else if (msg.type == 5) { // Zoom Out
				ZoomOutMode();
			}
		}
		g_DirectInputQueue.clear();
	}

	// 2. Process external SHM input ringbuffer (if running with external frontend)
	if (g_ShmMapped != nullptr) {
		D1BridgeHeader *hdr = static_cast<D1BridgeHeader *>(g_ShmMapped);
		if (hdr->magic == 0x44315242) {
			while (hdr->inputReadIdx < hdr->inputWriteIdx) {
				const D1InputMsg &msg = hdr->inputQueue[hdr->inputReadIdx % D1_INPUT_RING_SIZE];
				hdr->inputReadIdx++;

				SDL_Event ev {};
				if (msg.type == 1) { // Mouse Motion
					ev.type = SDL_MOUSEMOTION;
					ev.motion.x = msg.x;
					ev.motion.y = msg.y;
					SDL_PushEvent(&ev);
				} else if (msg.type == 2) { // Mouse Button
					ev.type = (msg.state != 0) ? SDL_MOUSEBUTTONDOWN : SDL_MOUSEBUTTONUP;
					ev.button.state = (msg.state != 0) ? SDL_PRESSED : SDL_RELEASED;
					ev.button.button = (msg.code == 1) ? SDL_BUTTON_LEFT : ((msg.code == 2) ? SDL_BUTTON_MIDDLE : SDL_BUTTON_RIGHT);
					ev.button.x = msg.x;
					ev.button.y = msg.y;
					SDL_PushEvent(&ev);
				} else if (msg.type == 3) { // Key
					ev.type = (msg.state != 0) ? SDL_KEYDOWN : SDL_KEYUP;
					ev.key.state = (msg.state != 0) ? SDL_PRESSED : SDL_RELEASED;
					if (msg.state != 0 && msg.x >= 32 && msg.x < 127) {
						ev.key.keysym.sym = static_cast<SDL_Keycode>(msg.x);
					} else {
						ev.key.keysym.sym = static_cast<SDL_Keycode>(msg.code);
					}
					SDL_PushEvent(&ev);
				} else if (msg.type == 4) { // Zoom In
					ZoomInMode();
				} else if (msg.type == 5) { // Zoom Out
					ZoomOutMode();
				}
			}
		}
	}
}

void StartDevilutionXThread(const char *basePath)
{
	if (g_DiabloThreadRunning)
		return;

	g_DiabloThreadRunning = true;
	setenv("D1_MINIMIZE_WINDOW", "1", 1);

	static std::string s_BasePath = (basePath != nullptr && basePath[0] != '\0')
		? basePath
		: "/home/biti/.local/share/diasurgical/devilution";

	g_DiabloThread = std::thread([]() {
		char arg0[] = "devilutionx";
		char arg1[] = "--data-dir";
		std::vector<char> arg2(s_BasePath.begin(), s_BasePath.end());
		arg2.push_back('\0');
		char arg3[] = "--config-dir";
		std::vector<char> arg4(s_BasePath.begin(), s_BasePath.end());
		arg4.push_back('\0');
		char arg5[] = "--hellfire";

		char *argv[] = { arg0, arg1, arg2.data(), arg3, arg4.data(), arg5, nullptr };
		int argc = 6;

		const char *envA = std::getenv("D1_ASSETS_DIR");
		if (envA != nullptr && envA[0] != '\0') {
			devilution::paths::SetAssetsPath(envA);
		} else {
			devilution::paths::SetAssetsPath("/home/biti/antigravity/magical-bell/assets/");
		}
		devilution::DiabloMain(argc, argv);
		g_DiabloThreadRunning = false;
	});
	g_DiabloThread.detach();
}

void PushDevilutionXInput(uint32_t type, uint32_t code, uint32_t state, int32_t x, int32_t y)
{
	std::lock_guard<std::mutex> lock(g_DirectInputMutex);
	g_DirectInputQueue.push_back({ type, code, state, x, y });
}

bool CopyD1FrameBytes(uint8_t *dest, size_t maxBytes, uint32_t *outFrameId, int *outW, int *outH)
{
	std::lock_guard<std::mutex> lock(g_D1FrameMutex);
	if (g_D1InternalFrame.empty() || dest == nullptr)
		return false;

	size_t toCopy = std::min(maxBytes, g_D1InternalFrame.size());
	std::memcpy(dest, g_D1InternalFrame.data(), toCopy);

	if (outFrameId) *outFrameId = g_D1EngineData.frameId;
	if (outW) *outW = g_D1EngineData.width;
	if (outH) *outH = g_D1EngineData.height;

	return true;
}

void CopyD1DungeonGrid(int32_t *dest, size_t maxTiles)
{
	if (dest == nullptr) return;
	size_t count = std::min<size_t>(maxTiles, 112 * 112);
	for (size_t y = 0; y < 112; ++y) {
		for (size_t x = 0; x < 112; ++x) {
			size_t idx = y * 112 + x;
			if (idx < count) {
				dest[idx] = static_cast<int32_t>(dPiece[x][y]);
			}
		}
	}
}

void CleanupGodotBridge()
{
	if (g_ShmMapped != nullptr && g_ShmTotalSize > 0) {
		D1BridgeHeader *hdr = static_cast<D1BridgeHeader *>(g_ShmMapped);
		hdr->magic = 0xDEADBEEF;
		munmap(g_ShmMapped, g_ShmTotalSize);
		g_ShmMapped = nullptr;
	}
	if (g_ShmFd >= 0) {
		close(g_ShmFd);
		g_ShmFd = -1;
	}
	shm_unlink("/dev/shm/d1_godot_frame");
	g_ShmTotalSize = 0;
}

bool IsDevilutionXRunning()
{
	return g_DiabloThreadRunning.load();
}

bool IsDevilutionXQuitRequested()
{
	return g_D1EngineQuitRequested.load();
}

void RequestDevilutionXQuit()
{
	g_D1EngineQuitRequested = true;
	g_DiabloThreadRunning = false;
}

namespace {
std::mutex g_AudioEventMutex;
std::vector<D1AudioEvent> g_AudioEventQueue;
} // namespace

void PushDevilutionXAudioEvent(D1AudioEvent::Type type, const char *path, int32_t volume, int32_t pan, int32_t tileX, int32_t tileY, bool hasPos)
{
	std::lock_guard<std::mutex> lock(g_AudioEventMutex);
	D1AudioEvent ev;
	ev.type = type;
	ev.path[0] = '\0';
	if (path != nullptr) {
		std::strncpy(ev.path, path, sizeof(ev.path) - 1);
		ev.path[sizeof(ev.path) - 1] = '\0';
	}
	ev.volume = volume;
	ev.pan = pan;
	ev.tileX = tileX;
	ev.tileY = tileY;
	ev.hasPos = hasPos;
	g_AudioEventQueue.push_back(ev);
}

size_t PopDevilutionXAudioEvents(D1AudioEvent *outEvents, size_t maxEvents)
{
	std::lock_guard<std::mutex> lock(g_AudioEventMutex);
	if (outEvents == nullptr || maxEvents == 0 || g_AudioEventQueue.empty())
		return 0;
	size_t count = std::min(maxEvents, g_AudioEventQueue.size());
	for (size_t i = 0; i < count; ++i) {
		outEvents[i] = g_AudioEventQueue[i];
	}
	g_AudioEventQueue.erase(g_AudioEventQueue.begin(), g_AudioEventQueue.begin() + count);
	return count;
}

std::vector<uint8_t> LoadDevilutionXAsset(const char *path)
{
	if (path == nullptr || path[0] == '\0')
		return {};

	AssetRef ref = FindAsset(path);
	if (!ref.ok())
		return {};

	size_t sz = ref.size();
	if (sz == 0)
		return {};

	AssetHandle handle = OpenAsset(std::move(ref), /*threadsafe=*/true);
	if (!handle.ok())
		return {};

	std::vector<uint8_t> buffer(sz);
	if (!handle.read(buffer.data(), sz))
		return {};

	return buffer;
}

} // namespace devilution

