#pragma once
#include <cstdint>
#include <cstddef>
#include <atomic>
#include <vector>
#include <SDL.h>
#include "engine/point.hpp"
#include "engine/direction.hpp"

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

struct D1EngineData {
	uint32_t frameId = 0;
	int width = 2560;
	int height = 1440;
	int playerTileX = 25;
	int playerTileY = 25;
	float playerNormX = 0.5f;
	float playerNormY = 0.52f;
	int playerHp = 100;
	int playerMaxHp = 100;
	int playerMana = 50;
	int playerMaxMana = 50;
	int playerGold = 0;
	int playerClass = 0;
	int currentLevel = 0;
	int dungeonType = 0;
	bool leftPanelOpen = false;
	bool rightPanelOpen = false;
	bool isGameRunning = false;
	int playerLevel = 1;
	int playerExp = 0;
	int playerNextExp = 0;
	int playerSpell = 0;
	int playerSpellType = 0;
	int beltTypes[8] = { 0 };
	int beltCounts[8] = { 0 };
	char beltNames[8][64] = { { 0 } };
	int leftPanelX = 0;
	int leftPanelY = 0;
	int leftPanelW = 320;
	int leftPanelH = 352;
	int rightPanelX = 0;
	int rightPanelY = 0;
	int rightPanelW = 320;
	int rightPanelH = 352;
	bool isSpeedbookOpen = false;
	int speedbookX = 0;
	int speedbookY = 0;
	int speedbookW = 0;
	int speedbookH = 0;
	bool hasHoverInfo = false;
	char hoverItemName[128] = { 0 };
	char hoverItemStats[512] = { 0 };
	int hoverItemQuality = 0;
	bool isInventoryHover = false;
	int hoverMouseX = 0;
	int hoverMouseY = 0;
	int zoomMode = 2; // 0=1.0x, 1=1.5x, 2=2.0x, 3=2.5x, 4=3.0x
};

struct AvailableSpellItem {
	int id = 0;
	int type = 0;
	char name[64] = { 0 };
	int manaCost = 0;
	char hotkey[16] = { 0 };
};

extern D1EngineData g_D1EngineData;
extern bool gbHideVanillaHUD;
void SetVanillaHUDHidden(bool hidden);
std::vector<uint8_t> GetSpellIconRgba(int spellId, int spellType);
std::vector<AvailableSpellItem> GetAvailableSpells();
void SelectSpell(int spellId, int spellType);
void UseBeltSlot(int slotIndex);
void ClickBeltSlot(int slotIndex);

void InitGodotBridge(int width, int height);
void ExportGodotFrame(const SDL_Surface *surface);
void PollGodotBridgeInput();
void CleanupGodotBridge();

void StartDevilutionXThread(const char *basePath);
void PushDevilutionXInput(uint32_t type, uint32_t code, uint32_t state, int32_t x, int32_t y);
bool CopyD1FrameBytes(uint8_t *dest, size_t maxBytes, uint32_t *outFrameId, int *outW, int *outH);
void CopyD1DungeonGrid(int32_t *dest, size_t maxTiles);

extern std::atomic<bool> g_D1EngineQuitRequested;
extern std::atomic<bool> g_DiabloThreadRunning;
bool IsDevilutionXRunning();
bool IsDevilutionXQuitRequested();
void RequestDevilutionXQuit();

// Native Godot Audio Interception
struct D1AudioEvent {
	enum Type : uint32_t {
		MUSIC_PLAY = 1,
		MUSIC_STOP = 2,
		SFX_PLAY = 3,
		STREAM_PLAY = 4,
		STREAM_STOP = 5,
	} type;
	char path[128];
	int32_t volume;
	int32_t pan;
	int32_t tileX;
	int32_t tileY;
	bool hasPos;
};

void PushDevilutionXAudioEvent(D1AudioEvent::Type type, const char *path, int32_t volume = 0, int32_t pan = 0, int32_t tileX = 0, int32_t tileY = 0, bool hasPos = false);
size_t PopDevilutionXAudioEvents(D1AudioEvent *outEvents, size_t maxEvents);
std::vector<uint8_t> LoadDevilutionXAsset(const char *path);

// Native Godot 3D Lighting & Shadows
struct D1EngineLight {
	float normX = 0.5f;
	float normY = 0.5f;
	float radius = 5.0f;
	int type = 0; // 0: Player Torch, 1: Wall Torch / Brazier, 2: Missile / Spell, 3: Monster / Ambient
	int tileX = 0;
	int tileY = 0;
};

struct D1WallOccluder {
	float normX = 0.0f;
	float normY = 0.0f;
};

// Native Godot 3D GPUParticles Visual Events
struct D1VisualEvent {
	uint32_t type = 0; // 1: Blood Splatter, 2: Bone Shards, 3: Fireball Explosion, 4: Hit Sparks
	float normX = 0.5f;
	float normY = 0.5f;
	float dirX = 0.0f;
	float dirY = -1.0f;
	float intensity = 1.0f;
};

void PushVisualEvent(uint32_t type, Point tile, Displacement offset, Direction dir, float intensity = 1.0f);
std::vector<D1EngineLight> GetActiveEngineLights();
std::vector<D1WallOccluder> GetActiveWallOccluders();
std::vector<D1VisualEvent> DrainVisualEvents();

struct D1ItemIconRgba {
	int width = 0;
	int height = 0;
	std::vector<uint8_t> rgba;
};
D1ItemIconRgba GetBeltItemIconRgba(int slotIndex);

// Native Godot Diablo IV Character Sheet & Quest Log
struct D1CharacterInfo {
	char name[32] = { 0 };
	int playerClass = 0;
	int level = 1;
	int exp = 0;
	int nextExp = 0;
	int gold = 0;

	int strBase = 0;
	int strNow = 0;
	int strMax = 0;

	int magBase = 0;
	int magNow = 0;
	int magMax = 0;

	int dexBase = 0;
	int dexNow = 0;
	int dexMax = 0;

	int vitBase = 0;
	int vitNow = 0;
	int vitMax = 0;

	int statPts = 0;

	int hp = 0;
	int maxHp = 0;
	int mana = 0;
	int maxMana = 0;

	int armor = 0;
	int toHit = 0;
	int dmgMin = 0;
	int dmgMax = 0;

	int resMagic = 0;
	int resFire = 0;
	int resLightning = 0;
};

D1CharacterInfo GetCharacterInfo();
void AddAttributePoint(int attrIdx);
bool IsCharacterSheetOpen();
void ToggleCharacterSheet();

struct D1QuestEntry {
	int idx = 0;
	char name[64] = { 0 };
	bool isFinished = false;
};

std::vector<D1QuestEntry> GetQuestsInfo();
void SelectQuest(int questIdx);
bool IsQuestLogOpen();
void ToggleQuestLog();

} // namespace devilution

