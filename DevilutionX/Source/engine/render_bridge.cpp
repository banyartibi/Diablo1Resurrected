#include "engine/render_bridge.hpp"
#include "engine/render/scrollrt.h"
#include "engine/render/clx_render.hpp"
#include "engine/dx.h"
#include "engine/backbuffer_state.hpp"

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
#include "engine.h"
#include "engine/assets.hpp"
#include "panels/spell_icons.hpp"
#include "utils/language.h"
#include "engine/palette.h"
#include "engine/surface.hpp"
#include "items.h"
#include "quests.h"
#include "minitext.h"
#include "inv.h"
#include "qol/stash.h"
#include "msg.h"
#include "cursor.h"
#include "sound.h"
#include "effects.h"
#include "lighting.h"
#include "objects.h"
#include "objdat.h"
#include <cmath>

namespace devilution {

bool gbGodotBridgeActive = true;
bool gbHideVanillaHUD = false;
D1EngineData g_D1EngineData;

void SetVanillaHUDHidden(bool hidden)
{
	gbHideVanillaHUD = hidden;
	CalculatePanelAreas();
}

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
			g_D1EngineData.playerLevel = MyPlayer->_pLevel;
			g_D1EngineData.playerExp = MyPlayer->_pExperience;
			g_D1EngineData.playerNextExp = MyPlayer->_pNextExper;
			g_D1EngineData.playerSpell = static_cast<int>(MyPlayer->_pRSpell);
			g_D1EngineData.playerSpellType = static_cast<int>(MyPlayer->_pRSplType);

			for (size_t i = 0; i < 8; ++i) {
				if (i < sizeof(MyPlayer->SpdList) / sizeof(MyPlayer->SpdList[0]) && !MyPlayer->SpdList[i].isEmpty()) {
					const Item &item = MyPlayer->SpdList[i];
					int type = 11;
					if (item._iMiscId == IMISC_HEAL) type = 1;
					else if (item._iMiscId == IMISC_FULLHEAL) type = 2;
					else if (item._iMiscId == IMISC_MANA) type = 3;
					else if (item._iMiscId == IMISC_FULLMANA) type = 4;
					else if (item._iMiscId == IMISC_REJUV) type = 5;
					else if (item._iMiscId == IMISC_FULLREJUV) type = 6;
					else if (item._iMiscId > IMISC_OILFIRST && item._iMiscId < IMISC_OILLAST) type = 9;
					else if (item.isScroll()) type = 8;
					else if (item.isRune()) type = 10;
					else if (item._iMiscId == IMISC_ELIXSTR || item._iMiscId == IMISC_ELIXMAG || item._iMiscId == IMISC_ELIXDEX || item._iMiscId == IMISC_ELIXVIT) type = 7;
					g_D1EngineData.beltTypes[i] = type;
					g_D1EngineData.beltCounts[i] = 1;
					std::strncpy(g_D1EngineData.beltNames[i], item._iIName, 63);
					g_D1EngineData.beltNames[i][63] = '\0';
				} else {
					g_D1EngineData.beltTypes[i] = 0;
					g_D1EngineData.beltCounts[i] = 0;
					g_D1EngineData.beltNames[i][0] = '\0';
				}
			}
		}

		g_D1EngineData.currentLevel = currlevel;
		g_D1EngineData.dungeonType = leveltype;
		g_D1EngineData.leftPanelOpen = IsLeftPanelOpen();
		g_D1EngineData.rightPanelOpen = IsRightPanelOpen();
		const Rectangle &lp = GetLeftPanel();
		g_D1EngineData.leftPanelX = lp.position.x;
		g_D1EngineData.leftPanelY = lp.position.y;
		g_D1EngineData.leftPanelW = lp.size.width;
		g_D1EngineData.leftPanelH = lp.size.height;

		const Rectangle &rp = GetRightPanel();
		g_D1EngineData.rightPanelX = rp.position.x;
		g_D1EngineData.rightPanelY = rp.position.y;
		g_D1EngineData.rightPanelW = rp.size.width;
		g_D1EngineData.rightPanelH = rp.size.height;

		g_D1EngineData.isSpeedbookOpen = spselflag;
		if (spselflag) {
			const Rectangle &mp = GetMainPanel();
			g_D1EngineData.speedbookX = mp.position.x;
			g_D1EngineData.speedbookY = mp.position.y - 320;
			g_D1EngineData.speedbookW = 640;
			g_D1EngineData.speedbookH = 320 + mp.size.height;
		} else {
			g_D1EngineData.speedbookX = 0;
			g_D1EngineData.speedbookY = 0;
			g_D1EngineData.speedbookW = 0;
			g_D1EngineData.speedbookH = 0;
		}

		// Export Hover Item Info
		if (!InfoString.empty() && gbRunGame) {
			g_D1EngineData.hasHoverInfo = true;
			string_view fullInfo = InfoString.str();
			size_t firstNl = fullInfo.find('\n');
			if (firstNl != string_view::npos) {
				string_view nameStr = fullInfo.substr(0, firstNl);
				string_view statsStr = fullInfo.substr(firstNl + 1);
				std::strncpy(g_D1EngineData.hoverItemName, nameStr.data(), std::min(sizeof(g_D1EngineData.hoverItemName) - 1, nameStr.size()));
				g_D1EngineData.hoverItemName[std::min(sizeof(g_D1EngineData.hoverItemName) - 1, nameStr.size())] = '\0';
				std::strncpy(g_D1EngineData.hoverItemStats, statsStr.data(), std::min(sizeof(g_D1EngineData.hoverItemStats) - 1, statsStr.size()));
				g_D1EngineData.hoverItemStats[std::min(sizeof(g_D1EngineData.hoverItemStats) - 1, statsStr.size())] = '\0';
			} else {
				std::strncpy(g_D1EngineData.hoverItemName, fullInfo.data(), std::min(sizeof(g_D1EngineData.hoverItemName) - 1, fullInfo.size()));
				g_D1EngineData.hoverItemName[std::min(sizeof(g_D1EngineData.hoverItemName) - 1, fullInfo.size())] = '\0';
				g_D1EngineData.hoverItemStats[0] = '\0';
			}

			if (HasAnyOf(InfoColor, UiFlags::ColorBlue))
				g_D1EngineData.hoverItemQuality = 1;
			else if (HasAnyOf(InfoColor, UiFlags::ColorWhitegold))
				g_D1EngineData.hoverItemQuality = 2;
			else if (HasAnyOf(InfoColor, UiFlags::ColorRed))
				g_D1EngineData.hoverItemQuality = 3;
			else
				g_D1EngineData.hoverItemQuality = 0;

			g_D1EngineData.hoverMouseX = MousePosition.x;
			g_D1EngineData.hoverMouseY = MousePosition.y;

			const Rectangle &rpRect = GetRightPanel();
			g_D1EngineData.isInventoryHover = IsRightPanelOpen() &&
				(MousePosition.x >= rpRect.position.x && MousePosition.x <= rpRect.position.x + rpRect.size.width &&
				 MousePosition.y >= rpRect.position.y && MousePosition.y <= rpRect.position.y + rpRect.size.height);
		} else {
			g_D1EngineData.hasHoverInfo = false;
			g_D1EngineData.hoverItemName[0] = '\0';
			g_D1EngineData.hoverItemStats[0] = '\0';
			g_D1EngineData.hoverItemQuality = 0;
			g_D1EngineData.isInventoryHover = false;
		}

		g_D1EngineData.isGameRunning = gbRunGame;
		g_D1EngineData.zoomMode = static_cast<int>(CurrentZoomMode);

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
		hdr->zoomMode = static_cast<int32_t>(CurrentZoomMode) + 1;
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
				SDL_Keycode sym = static_cast<SDL_Keycode>(msg.code != 0 ? msg.code : msg.x);
				ev.key.keysym.sym = sym;
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

void UseBeltSlot(int slotIndex)
{
	if (!gbRunGame || MyPlayer == nullptr)
		return;
	if (slotIndex < 0 || slotIndex >= 8)
		return;
	Player &myPlayer = *MyPlayer;
	if (!myPlayer.SpdList[slotIndex].isEmpty() && myPlayer.SpdList[slotIndex]._itype != ItemType::Gold) {
		UseInvItem(INVITEM_BELT_FIRST + slotIndex);
	}
}

void ClickBeltSlot(int slotIndex)
{
	if (!gbRunGame || MyPlayer == nullptr)
		return;
	if (slotIndex < 0 || slotIndex >= 8)
		return;
	Player &player = *MyPlayer;
	if (player._pmode > PM_WALK_SIDEWAYS)
		return;

	if (player.HoldItem.isEmpty()) {
		// Pick up item from belt onto cursor
		Item &beltItem = player.SpdList[slotIndex];
		if (!beltItem.isEmpty()) {
			player.HoldItem = beltItem;
			player.RemoveSpdBarItem(slotIndex);
			PlaySFX(IS_IGRAB);
			NewCursor(player.HoldItem);
			NetSendCmdChBeltItem(false, slotIndex);
		}
	} else {
		// Place held item into belt slot or swap
		if (CanBePlacedOnBelt(player.HoldItem)) {
			if (player.SpdList[slotIndex].isEmpty()) {
				player.SpdList[slotIndex] = player.HoldItem.pop();
			} else {
				std::swap(player.SpdList[slotIndex], player.HoldItem);
			}
			PlaySFX(ItemInvSnds[ItemCAnimTbl[player.SpdList[slotIndex]._iCurs]]);
			NewCursor(player.HoldItem);
			NetSendCmdChBeltItem(false, slotIndex);
		}
	}
	CalcPlrInv(player, true);
}

std::vector<uint8_t> GetSpellIconRgba(int spellId, int spellType)
{
	if (!gbRunGame || spellId <= 0 || spellId > static_cast<int>(SpellID::LAST))
		return {};

	// orig_palette holds the un-faded master palette loaded from town/dungeon data
	const auto &pal = orig_palette;
	bool paletteReady = false;
	for (int i = 16; i < 256; ++i) {
		if (pal[i].r > 40 || pal[i].g > 40 || pal[i].b > 40) {
			paletteReady = true;
			break;
		}
	}
	if (!paletteReady)
		return {};

	if (!HasLargeSpellIcons()) {
		LoadLargeSpellIcons();
		if (!HasLargeSpellIcons())
			return {};
	}

	OwnedSurface surface(56, 56);
	std::memset(surface.begin(), 0, surface.pitch() * surface.h());

	SpellType st = static_cast<SpellType>(spellType);
	if (st == SpellType::Invalid || static_cast<int>(st) < 0 || static_cast<int>(st) > 3) {
		st = SpellType::Spell;
	}
	SetSpellTrans(st);
	DrawLargeSpellIcon(surface, { 0, 55 }, static_cast<SpellID>(spellId));

	bool hasPixels = false;
	std::vector<uint8_t> rgba(56 * 56 * 4, 0);
	for (int y = 0; y < 56; ++y) {
		const uint8_t *src = surface.at(0, y);
		uint8_t *dst = rgba.data() + (y * 56 * 4);
		for (int x = 0; x < 56; ++x) {
			uint8_t idx = src[x];
			if (idx != 0) {
				SDL_Color c = pal[idx];
				if (c.r > 30 || c.g > 30 || c.b > 30) {
					hasPixels = true;
				}
				dst[x * 4 + 0] = c.r;
				dst[x * 4 + 1] = c.g;
				dst[x * 4 + 2] = c.b;
				dst[x * 4 + 3] = 255;
			}
		}
	}
	if (!hasPixels)
		return {};

	return rgba;
}

D1ItemIconRgba GetBeltItemIconRgba(int slotIndex)
{
	if (!gbRunGame || MyPlayer == nullptr || slotIndex < 0 || slotIndex >= 8)
		return {};

	if (MyPlayer->SpdList[slotIndex].isEmpty())
		return {};

	const Item &item = MyPlayer->SpdList[slotIndex];
	int cursId = item._iCurs + CURSOR_FIRSTITEM;
	const ClxSprite sprite = GetInvItemSprite(cursId);
	int w = sprite.width();
	int h = sprite.height();
	if (w <= 0 || h <= 0 || w > 64 || h > 64)
		return {};

	OwnedSurface surface(w, h);
	std::memset(surface.begin(), 0, surface.pitch() * surface.h());

	ClxDraw(surface, { 0, h - 1 }, sprite);

	const auto &pal = orig_palette;
	D1ItemIconRgba res;
	res.width = w;
	res.height = h;
	res.rgba.resize(w * h * 4, 0);

	bool hasPixels = false;
	for (int y = 0; y < h; ++y) {
		const uint8_t *src = surface.at(0, y);
		uint8_t *dst = res.rgba.data() + (y * w * 4);
		for (int x = 0; x < w; ++x) {
			uint8_t idx = src[x];
			if (idx != 0) {
				SDL_Color c = pal[idx];
				hasPixels = true;
				dst[x * 4 + 0] = c.r;
				dst[x * 4 + 1] = c.g;
				dst[x * 4 + 2] = c.b;
				dst[x * 4 + 3] = 255;
			}
		}
	}
	if (!hasPixels)
		return {};

	return res;
}

std::vector<AvailableSpellItem> GetAvailableSpells()
{
	if (!gbRunGame || MyPlayer == nullptr)
		return {};

	std::vector<AvailableSpellItem> result;
	Player &myPlayer = *MyPlayer;

	for (auto i : enum_values<SpellType>()) {
		uint64_t mask = 0;
		switch (static_cast<SpellType>(i)) {
		case SpellType::Skill:
			mask = myPlayer._pAblSpells;
			break;
		case SpellType::Spell:
			mask = myPlayer._pMemSpells;
			break;
		case SpellType::Scroll:
			mask = myPlayer._pScrlSpells;
			break;
		case SpellType::Charges:
			mask = myPlayer._pISpells;
			break;
		default:
			continue;
		}

		int8_t j = static_cast<int8_t>(SpellID::Firebolt);
		for (uint64_t spl = 1; j < MAX_SPELLS; spl <<= 1, j++) {
			if ((mask & spl) == 0)
				continue;
			SpellID splId = static_cast<SpellID>(j);
			AvailableSpellItem item;
			item.id = static_cast<int>(splId);
			item.type = static_cast<int>(i);
			string_view name = pgettext("spell", GetSpellData(splId).sNameText);
			std::strncpy(item.name, name.data(), std::min(sizeof(item.name) - 1, name.size()));
			item.name[std::min(sizeof(item.name) - 1, name.size())] = '\0';
			if (static_cast<SpellType>(i) == SpellType::Spell) {
				item.manaCost = GetManaAmount(myPlayer, splId) >> 6;
			} else {
				item.manaCost = 0;
			}

			for (size_t t = 0; t < NumHotkeys; t++) {
				if (myPlayer._pSplHotKey[t] == splId && myPlayer._pSplTHotKey[t] == static_cast<SpellType>(i)) {
					std::snprintf(item.hotkey, sizeof(item.hotkey), "F%zu", t + 5);
					break;
				}
			}

			result.push_back(item);
		}
	}
	return result;
}

void SelectSpell(int spellId, int spellType)
{
	if (!gbRunGame || MyPlayer == nullptr)
		return;
	MyPlayer->_pRSpell = static_cast<SpellID>(spellId);
	MyPlayer->_pRSplType = static_cast<SpellType>(spellType);
	spselflag = false;
	RedrawEverything();
}

static std::mutex g_VisualEventMutex;
static std::vector<D1VisualEvent> g_VisualEventQueue;

static bool IsTorchOrFireObject(int objType)
{
	switch (objType) {
	case OBJ_TORCHL:
	case OBJ_TORCHR:
	case OBJ_TORCHL2:
	case OBJ_TORCHR2:
	case OBJ_L1LIGHT:
	case OBJ_SKFIRE:
	case OBJ_CANDLE1:
	case OBJ_CANDLE2:
	case OBJ_CANDLEO:
	case OBJ_BOOKCANDLE:
	case OBJ_STORYCANDLE:
	case OBJ_L5CANDLE:
	case OBJ_BCROSS:
	case OBJ_TBCROSS:
	case OBJ_FLAMEHOLE:
		return true;
	default:
		return false;
	}
}

void PushVisualEvent(uint32_t type, Point tile, Displacement offset, Direction dir, float intensity)
{
	Point screenPos = TileToScreenCoords(tile, offset);
	int yOffset = 22;
	if (CurrentZoomMode == ZoomMode::Balanced_1_5x) yOffset = 33;
	else if (CurrentZoomMode == ZoomMode::Zoomed_2x) yOffset = 44;
	else if (CurrentZoomMode == ZoomMode::UltraClose_2_5x) yOffset = 55;
	else if (CurrentZoomMode == ZoomMode::MacroClose_3x) yOffset = 66;
	screenPos.y -= yOffset;

	float normX = (gnScreenWidth > 0) ? (static_cast<float>(screenPos.x) / static_cast<float>(gnScreenWidth)) : 0.5f;
	float normY = (gnScreenHeight > 0) ? (static_cast<float>(screenPos.y) / static_cast<float>(gnScreenHeight)) : 0.5f;

	Displacement dirDisp = Displacement(dir);
	float len = std::sqrt(static_cast<float>(dirDisp.deltaX * dirDisp.deltaX + dirDisp.deltaY * dirDisp.deltaY));
	float dx = 0.0f;
	float dy = -1.0f;
	if (len > 0.001f) {
		dx = static_cast<float>(dirDisp.deltaX) / len;
		dy = static_cast<float>(dirDisp.deltaY) / len;
	}

	D1VisualEvent ev;
	ev.type = type;
	ev.normX = normX;
	ev.normY = normY;
	ev.dirX = dx;
	ev.dirY = dy;
	ev.intensity = intensity;

	std::lock_guard<std::mutex> lock(g_VisualEventMutex);
	if (g_VisualEventQueue.size() < 64) {
		g_VisualEventQueue.push_back(ev);
	}
}

std::vector<D1VisualEvent> DrainVisualEvents()
{
	std::vector<D1VisualEvent> result;
	std::lock_guard<std::mutex> lock(g_VisualEventMutex);
	result.swap(g_VisualEventQueue);
	return result;
}

std::vector<D1EngineLight> GetActiveEngineLights()
{
	std::vector<D1EngineLight> lights;
	if (MyPlayer == nullptr || gnScreenWidth <= 0 || gnScreenHeight <= 0)
		return lights;

	// 1. Hero Torch (Type 0)
	{
		D1EngineLight heroLight;
		heroLight.normX = g_D1EngineData.playerNormX;
		heroLight.normY = g_D1EngineData.playerNormY;
		heroLight.radius = static_cast<float>(MyPlayer->_pLightRad);
		heroLight.type = 0; // Hero Torch
		heroLight.tileX = MyPlayer->position.tile.x;
		heroLight.tileY = MyPlayer->position.tile.y;
		lights.push_back(heroLight);
	}

	// 2. Static Dungeon Torches, Braziers & Candles (Type 1)
	for (int i = 0; i < ActiveObjectCount; ++i) {
		const Object &obj = Objects[ActiveObjects[i]];
		if (!IsTorchOrFireObject(obj._otype))
			continue;

		Point screenPos = TileToScreenCoords(obj.position);
		int yOffset = 22;
		if (obj._otype == OBJ_TORCHL || obj._otype == OBJ_TORCHR || obj._otype == OBJ_TORCHL2 || obj._otype == OBJ_TORCHR2) {
			yOffset = 28;
		} else if (obj._otype == OBJ_SKFIRE || obj._otype == OBJ_L1LIGHT) {
			yOffset = 24;
		}

		if (CurrentZoomMode == ZoomMode::Balanced_1_5x) yOffset = (yOffset * 3) / 2;
		else if (CurrentZoomMode == ZoomMode::Zoomed_2x) yOffset *= 2;
		else if (CurrentZoomMode == ZoomMode::UltraClose_2_5x) yOffset = (yOffset * 5) / 2;
		else if (CurrentZoomMode == ZoomMode::MacroClose_3x) yOffset *= 3;
		screenPos.y -= yOffset;

		float normX = static_cast<float>(screenPos.x) / static_cast<float>(gnScreenWidth);
		float normY = static_cast<float>(screenPos.y) / static_cast<float>(gnScreenHeight);

		if (normX < -0.2f || normX > 1.2f || normY < -0.2f || normY > 1.2f)
			continue;

		float rad = 8.0f;
		if (obj._otype == OBJ_L1LIGHT || obj._otype == OBJ_SKFIRE) rad = 7.0f;
		else if (obj._otype == OBJ_CANDLE1 || obj._otype == OBJ_CANDLE2 || obj._otype == OBJ_CANDLEO || obj._otype == OBJ_BOOKCANDLE || obj._otype == OBJ_STORYCANDLE || obj._otype == OBJ_L5CANDLE) rad = 4.0f;

		D1EngineLight el;
		el.normX = normX;
		el.normY = normY;
		el.radius = rad;
		el.tileX = obj.position.x;
		el.tileY = obj.position.y;
		el.type = 1;
		lights.push_back(el);

		if (lights.size() >= 16)
			break;
	}

	// 3. Dynamic Engine Lights (Missiles, Spells, Special Lights) (Type 2)
	for (int i = 0; i < ActiveLightCount; ++i) {
		int lid = ActiveLights[i];
		if (lid < 0 || lid >= MAXLIGHTS) continue;
		const Light &light = Lights[lid];
		if (light.isInvalid) continue;

		// Skip hero torch
		if (lid == MyPlayer->lightId) continue;
		if (light.position.tile == MyPlayer->position.tile) continue;

		Point screenPos = TileToScreenCoords(light.position.tile, light.position.offset);
		float normX = static_cast<float>(screenPos.x) / static_cast<float>(gnScreenWidth);
		float normY = static_cast<float>(screenPos.y) / static_cast<float>(gnScreenHeight);

		if (normX < -0.25f || normX > 1.25f || normY < -0.25f || normY > 1.25f)
			continue;

		D1EngineLight el;
		el.normX = normX;
		el.normY = normY;
		el.radius = static_cast<float>(light.radius);
		el.tileX = light.position.tile.x;
		el.tileY = light.position.tile.y;
		el.type = 2; // Missile/Spell
		lights.push_back(el);

		if (lights.size() >= 24)
			break;
	}

	return lights;
}

std::vector<D1WallOccluder> GetActiveWallOccluders()
{
	std::vector<D1WallOccluder> occluders;
	if (MyPlayer == nullptr || gnScreenWidth <= 0 || gnScreenHeight <= 0)
		return occluders;

	auto lights = GetActiveEngineLights();
	bool visited[112][112] = { false };

	for (const auto &light : lights) {
		int startX = std::max(0, light.tileX - 6);
		int endX = std::min(111, light.tileX + 6);
		int startY = std::max(0, light.tileY - 6);
		int endY = std::min(111, light.tileY + 6);

		for (int y = startY; y <= endY; ++y) {
			for (int x = startX; x <= endX; ++x) {
				if (visited[x][y]) continue;
				visited[x][y] = true;

				if (TileHasAny(dPiece[x][y], TileProperties::BlockLight)) {
					Point screenPos = TileToScreenCoords(Point{ x, y });
					int yOffset = 16;
					if (CurrentZoomMode == ZoomMode::Balanced_1_5x) yOffset = 24;
					else if (CurrentZoomMode == ZoomMode::Zoomed_2x) yOffset = 32;
					else if (CurrentZoomMode == ZoomMode::UltraClose_2_5x) yOffset = 40;
					else if (CurrentZoomMode == ZoomMode::MacroClose_3x) yOffset = 48;
					screenPos.y -= yOffset;

					float normX = static_cast<float>(screenPos.x) / static_cast<float>(gnScreenWidth);
					float normY = static_cast<float>(screenPos.y) / static_cast<float>(gnScreenHeight);
					if (normX >= -0.1f && normX <= 1.1f && normY >= -0.1f && normY <= 1.1f) {
						occluders.push_back(D1WallOccluder{ normX, normY });
						if (occluders.size() >= 64)
							return occluders;
					}
				}
			}
		}
	}
	return occluders;
}

D1CharacterInfo GetCharacterInfo()
{
	D1CharacterInfo info;
	if (MyPlayer == nullptr)
		return info;

	Player &p = *MyPlayer;
	std::strncpy(info.name, p._pName, sizeof(info.name) - 1);
	info.playerClass = static_cast<int>(p._pClass);
	info.level = p._pLevel;
	info.exp = p._pExperience;
	info.nextExp = p._pNextExper;
	info.gold = p._pGold;

	info.strBase = p._pBaseStr;
	info.strNow = p._pStrength;
	info.strMax = p.GetMaximumAttributeValue(CharacterAttribute::Strength);

	info.magBase = p._pBaseMag;
	info.magNow = p._pMagic;
	info.magMax = p.GetMaximumAttributeValue(CharacterAttribute::Magic);

	info.dexBase = p._pBaseDex;
	info.dexNow = p._pDexterity;
	info.dexMax = p.GetMaximumAttributeValue(CharacterAttribute::Dexterity);

	info.vitBase = p._pBaseVit;
	info.vitNow = p._pVitality;
	info.vitMax = p.GetMaximumAttributeValue(CharacterAttribute::Vitality);

	info.statPts = p._pStatPts;

	info.hp = p._pHitPoints >> 6;
	info.maxHp = p._pMaxHP >> 6;
	info.mana = p._pMana >> 6;
	info.maxMana = p._pMaxMana >> 6;

	info.armor = p.GetArmor() + p._pLevel * 2;
	info.toHit = (p.InvBody[INVLOC_HAND_LEFT]._itype == ItemType::Bow) ? p.GetRangedToHit() : p.GetMeleeToHit();

	int damageMod = p._pIBonusDamMod;
	if (p.InvBody[INVLOC_HAND_LEFT]._itype == ItemType::Bow && p._pClass != HeroClass::Rogue) {
		damageMod += p._pDamageMod / 2;
	} else {
		damageMod += p._pDamageMod;
	}
	info.dmgMin = p._pIMinDam + p._pIBonusDam * p._pIMinDam / 100 + damageMod;
	info.dmgMax = p._pIMaxDam + p._pIBonusDam * p._pIMaxDam / 100 + damageMod;

	info.resMagic = p._pMagResist;
	info.resFire = p._pFireResist;
	info.resLightning = p._pLghtResist;

	return info;
}

void AddAttributePoint(int attrIdx)
{
	if (MyPlayer == nullptr || MyPlayer->_pStatPts <= 0)
		return;

	CharacterAttribute attr = static_cast<CharacterAttribute>(attrIdx);
	if (MyPlayer->GetBaseAttributeValue(attr) >= MyPlayer->GetMaximumAttributeValue(attr))
		return;

	switch (attr) {
	case CharacterAttribute::Strength:
		NetSendCmdParam1(true, CMD_ADDSTR, 1);
		MyPlayer->_pStatPts -= 1;
		break;
	case CharacterAttribute::Magic:
		NetSendCmdParam1(true, CMD_ADDMAG, 1);
		MyPlayer->_pStatPts -= 1;
		break;
	case CharacterAttribute::Dexterity:
		NetSendCmdParam1(true, CMD_ADDDEX, 1);
		MyPlayer->_pStatPts -= 1;
		break;
	case CharacterAttribute::Vitality:
		NetSendCmdParam1(true, CMD_ADDVIT, 1);
		MyPlayer->_pStatPts -= 1;
		break;
	}
}

bool IsCharacterSheetOpen()
{
	return chrflag;
}

void ToggleCharacterSheet()
{
	PlaySFX(IS_TITLEMOV);
	chrflag = !chrflag;
	if (chrflag && QuestLogIsOpen)
		QuestLogIsOpen = false;
}

bool IsQuestLogOpen()
{
	return QuestLogIsOpen;
}

void ToggleQuestLog()
{
	PlaySFX(IS_TITLEMOV);
	QuestLogIsOpen = !QuestLogIsOpen;
	if (QuestLogIsOpen) {
		if (chrflag) chrflag = false;
		StartQuestlog();
	}
}

bool IsInventoryOpen()
{
	return invflag;
}

void ToggleInventory()
{
	PlaySFX(IS_TITLEMOV);
	sbookflag = false;
	CloseGoldWithdraw();
	CloseStash();
	invflag = !invflag;
	if (DropGoldFlag) {
		CloseGoldDrop();
	}
}

std::vector<D1QuestEntry> GetQuestsInfo()
{
	std::vector<D1QuestEntry> list;
	// 1. Active quests with log flag
	for (const auto &quest : Quests) {
		if (quest._qactive == QUEST_ACTIVE && quest._qlog) {
			D1QuestEntry qe;
			qe.idx = quest._qidx;
			std::string_view sv = _(QuestsData[quest._qidx]._qlstr);
			size_t len = std::min(sv.size(), sizeof(qe.name) - 1);
			std::memcpy(qe.name, sv.data(), len);
			qe.name[len] = '\0';
			qe.isFinished = false;
			list.push_back(qe);
		}
	}
	// 2. Finished quests
	for (const auto &quest : Quests) {
		if (quest._qactive == QUEST_DONE || quest._qactive == QUEST_HIVE_DONE) {
			D1QuestEntry qe;
			qe.idx = quest._qidx;
			std::string_view sv = _(QuestsData[quest._qidx]._qlstr);
			size_t len = std::min(sv.size(), sizeof(qe.name) - 1);
			std::memcpy(qe.name, sv.data(), len);
			qe.name[len] = '\0';
			qe.isFinished = true;
			list.push_back(qe);
		}
	}
	return list;
}

void SelectQuest(int questIdx)
{
	if (questIdx >= 0 && questIdx < MAXQUESTS) {
		InitQTextMsg(Quests[questIdx]._qmsg);
		PlaySFX(IS_TITLSLCT);
		QuestLogIsOpen = false;
	}
}

} // namespace devilution

