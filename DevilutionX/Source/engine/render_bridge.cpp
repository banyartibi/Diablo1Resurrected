#include "engine/render_bridge.hpp"
#include "engine/render/scrollrt.h"
#include "engine/dx.h"

#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <cstring>

namespace devilution {

bool gbGodotBridgeActive = true;

namespace {
int g_ShmFd = -1;
void *g_ShmMapped = nullptr;
size_t g_ShmTotalSize = 0;
uint32_t g_BridgeFrameCount = 0;
} // namespace

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
	if (!gbGodotBridgeActive || surface == nullptr || surface->pixels == nullptr)
		return;

	InitGodotBridge(surface->w, surface->h);

	if (g_ShmMapped == nullptr)
		return;

	D1BridgeHeader *hdr = static_cast<D1BridgeHeader *>(g_ShmMapped);
	hdr->magic = 0x44315242; // "D1RB"
	hdr->version = 1;
	hdr->width = surface->w;
	hdr->height = surface->h;
	hdr->pitch = surface->pitch;
	hdr->frameId = ++g_BridgeFrameCount;
	hdr->timestamp = SDL_GetTicks();
	hdr->playerNormX = 0.50f;
	hdr->playerNormY = 0.52f;
	hdr->zoomMode = (CurrentZoomMode == ZoomMode::Zoomed_2x) ? 3 : (CurrentZoomMode == ZoomMode::Balanced_1_5x ? 2 : 1);
	hdr->torchCount = 0;

	// Copy pixels directly to shared memory
	uint8_t *dstPixels = static_cast<uint8_t *>(g_ShmMapped) + sizeof(D1BridgeHeader);
	std::memcpy(dstPixels, surface->pixels, surface->w * surface->h * 4);

	hdr->readyFlag = 1;
}

void PollGodotBridgeInput()
{
	if (!gbGodotBridgeActive || g_ShmMapped == nullptr)
		return;

	D1BridgeHeader *hdr = static_cast<D1BridgeHeader *>(g_ShmMapped);
	if (hdr->magic != 0x44315242)
		return;

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
			ev.key.keysym.sym = static_cast<SDL_Keycode>(msg.code);
			SDL_PushEvent(&ev);
		} else if (msg.type == 4) { // Zoom In
			ZoomInMode();
		} else if (msg.type == 5) { // Zoom Out
			ZoomOutMode();
		}
	}
}

void CleanupGodotBridge()
{
	if (g_ShmMapped != nullptr && g_ShmTotalSize > 0) {
		D1BridgeHeader *hdr = static_cast<D1BridgeHeader *>(g_ShmMapped);
		hdr->magic = 0xDEADBEEF; // Signal to Godot that DevilutionX has terminated!
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

} // namespace devilution
