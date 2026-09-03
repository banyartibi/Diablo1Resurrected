#pragma once
#include <cstdint>
#include <cstddef>
#include <SDL.h>

namespace devilution {

#pragma pack(push, 1)
struct D1BridgeTorch {
	float normX;
	float normY;
	float intensity;
	float pad;
};

struct D1InputMsg {
	uint32_t type;  // 1 = MOUSE_MOTION, 2 = MOUSE_BUTTON, 3 = KEY
	uint32_t code;  // 1 = Left, 2 = Middle, 3 = Right, or SDL keycode
	uint32_t state; // 1 = pressed/down, 0 = released/up
	int32_t x;
	int32_t y;
};

constexpr size_t D1_INPUT_RING_SIZE = 128;

struct D1BridgeHeader {
	uint32_t magic;      // 0x44315242 ("D1RB")
	uint32_t version;    // 1
	uint32_t width;
	uint32_t height;
	uint32_t pitch;
	uint32_t frameId;
	uint32_t timestamp;  // SDL_GetTicks()
	float playerNormX;   // Hero screen position (0.0..1.0)
	float playerNormY;   // Hero screen position (0.0..1.0)
	int32_t zoomMode;    // 1 = 1.0x, 2 = 1.5x, 3 = 2.0x
	uint32_t torchCount;
	D1BridgeTorch torches[16];
	uint32_t readyFlag;  // 1 = new frame written

	// Bidirectional Input Queue (Written by Godot 4, Read by DevilutionX)
	uint32_t inputWriteIdx;
	uint32_t inputReadIdx;
	D1InputMsg inputQueue[D1_INPUT_RING_SIZE];

	uint8_t reserved[4096 - (44 + 256 + 4 + 8 + 128 * sizeof(D1InputMsg))];
};
#pragma pack(pop)

static_assert(sizeof(D1BridgeHeader) == 4096, "D1BridgeHeader must be exactly 4096 bytes");

extern bool gbGodotBridgeActive;

void InitGodotBridge(int width, int height);
void ExportGodotFrame(const SDL_Surface *surface);
void PollGodotBridgeInput();
void CleanupGodotBridge();

} // namespace devilution
