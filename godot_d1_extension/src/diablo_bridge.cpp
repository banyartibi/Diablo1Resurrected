#include "diablo_bridge.h"

#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/classes/image.hpp>

#include "engine/render_bridge.hpp"

using namespace godot;

void DiabloBridge::_bind_methods() {
	ClassDB::bind_method(D_METHOD("init_engine", "mpq_dir"), &DiabloBridge::init_engine);
	ClassDB::bind_method(D_METHOD("step_tick"), &DiabloBridge::step_tick);
	ClassDB::bind_method(D_METHOD("is_engine_ready"), &DiabloBridge::is_engine_ready);
	ClassDB::bind_method(D_METHOD("is_engine_running"), &DiabloBridge::is_engine_running);
	ClassDB::bind_method(D_METHOD("is_quit_requested"), &DiabloBridge::is_quit_requested);
	ClassDB::bind_method(D_METHOD("quit_engine"), &DiabloBridge::quit_engine);

	// Player Stats & Status
	ClassDB::bind_method(D_METHOD("get_player_tile_pos"), &DiabloBridge::get_player_tile_pos);
	ClassDB::bind_method(D_METHOD("get_player_norm_pos"), &DiabloBridge::get_player_norm_pos);
	ClassDB::bind_method(D_METHOD("get_player_hp"), &DiabloBridge::get_player_hp);
	ClassDB::bind_method(D_METHOD("get_player_max_hp"), &DiabloBridge::get_player_max_hp);
	ClassDB::bind_method(D_METHOD("get_player_mana"), &DiabloBridge::get_player_mana);
	ClassDB::bind_method(D_METHOD("get_player_max_mana"), &DiabloBridge::get_player_max_mana);
	ClassDB::bind_method(D_METHOD("get_player_gold"), &DiabloBridge::get_player_gold);
	ClassDB::bind_method(D_METHOD("get_player_class"), &DiabloBridge::get_player_class);
	ClassDB::bind_method(D_METHOD("get_current_level"), &DiabloBridge::get_current_level);
	ClassDB::bind_method(D_METHOD("get_dungeon_type"), &DiabloBridge::get_dungeon_type);
	ClassDB::bind_method(D_METHOD("is_left_panel_open"), &DiabloBridge::is_left_panel_open);
	ClassDB::bind_method(D_METHOD("is_right_panel_open"), &DiabloBridge::is_right_panel_open);
	ClassDB::bind_method(D_METHOD("get_player_level"), &DiabloBridge::get_player_level);
	ClassDB::bind_method(D_METHOD("get_player_xp"), &DiabloBridge::get_player_xp);
	ClassDB::bind_method(D_METHOD("get_player_next_xp"), &DiabloBridge::get_player_next_xp);
	ClassDB::bind_method(D_METHOD("get_player_spell"), &DiabloBridge::get_player_spell);
	ClassDB::bind_method(D_METHOD("get_player_spell_type"), &DiabloBridge::get_player_spell_type);
	ClassDB::bind_method(D_METHOD("get_belt_items"), &DiabloBridge::get_belt_items);
	ClassDB::bind_method(D_METHOD("set_vanilla_hud_hidden", "hidden"), &DiabloBridge::set_vanilla_hud_hidden);
	ClassDB::bind_method(D_METHOD("is_vanilla_hud_hidden"), &DiabloBridge::is_vanilla_hud_hidden);
	ClassDB::bind_method(D_METHOD("is_game_running"), &DiabloBridge::is_game_running);
	ClassDB::bind_method(D_METHOD("get_spell_icon_texture", "spell_id", "spell_type"), &DiabloBridge::get_spell_icon_texture);

	// 112x112 Dungeon Grid
	ClassDB::bind_method(D_METHOD("get_dungeon_grid"), &DiabloBridge::get_dungeon_grid);
	ClassDB::bind_method(D_METHOD("get_dungeon_tile", "x", "y"), &DiabloBridge::get_dungeon_tile);

	// Direct Input
	ClassDB::bind_method(D_METHOD("send_input", "type", "code", "state", "x", "y"), &DiabloBridge::send_input);

	// Video Frame Blitting
	ClassDB::bind_method(D_METHOD("get_frame_bytes"), &DiabloBridge::get_frame_bytes);
	ClassDB::bind_method(D_METHOD("get_frame_width"), &DiabloBridge::get_frame_width);
	ClassDB::bind_method(D_METHOD("get_frame_height"), &DiabloBridge::get_frame_height);
	ClassDB::bind_method(D_METHOD("get_frame_id"), &DiabloBridge::get_frame_id);
	ClassDB::bind_method(D_METHOD("update_image_texture", "texture"), &DiabloBridge::update_image_texture);

	// Audio & Asset Interception
	ClassDB::bind_method(D_METHOD("poll_audio_events"), &DiabloBridge::poll_audio_events);
	ClassDB::bind_method(D_METHOD("get_asset_bytes", "path"), &DiabloBridge::get_asset_bytes);
	ClassDB::bind_method(D_METHOD("load_wav_stream", "path", "loop"), &DiabloBridge::load_wav_stream, DEFVAL(false));
}

DiabloBridge::DiabloBridge() {
}

DiabloBridge::~DiabloBridge() {
}

bool DiabloBridge::init_engine(const String &mpq_dir) {
	if (engine_started) {
		return true;
	}

	UtilityFunctions::print("[DiabloBridge] Starting embedded DevilutionX core with MPQ dir: ", mpq_dir);
	devilution::StartDevilutionXThread(mpq_dir.utf8().get_data());
	engine_started = true;
	return true;
}

void DiabloBridge::step_tick() {
	// Engine tick is driven asynchronously by internal DevilutionX thread,
	// step_tick() can be used to synchronize or signal state updates if needed.
}

bool DiabloBridge::is_engine_ready() const {
	return devilution::g_D1EngineData.frameId > 0;
}

bool DiabloBridge::is_engine_running() const {
	return devilution::IsDevilutionXRunning();
}

bool DiabloBridge::is_quit_requested() const {
	return devilution::IsDevilutionXQuitRequested();
}

void DiabloBridge::quit_engine() {
	devilution::RequestDevilutionXQuit();
}

Vector2i DiabloBridge::get_player_tile_pos() const {
	return Vector2i(devilution::g_D1EngineData.playerTileX, devilution::g_D1EngineData.playerTileY);
}

Vector2 DiabloBridge::get_player_norm_pos() const {
	return Vector2(devilution::g_D1EngineData.playerNormX, devilution::g_D1EngineData.playerNormY);
}

int DiabloBridge::get_player_hp() const {
	return devilution::g_D1EngineData.playerHp;
}

int DiabloBridge::get_player_max_hp() const {
	return devilution::g_D1EngineData.playerMaxHp;
}

int DiabloBridge::get_player_mana() const {
	return devilution::g_D1EngineData.playerMana;
}

int DiabloBridge::get_player_max_mana() const {
	return devilution::g_D1EngineData.playerMaxMana;
}

int DiabloBridge::get_player_gold() const {
	return devilution::g_D1EngineData.playerGold;
}

int DiabloBridge::get_player_class() const {
	return devilution::g_D1EngineData.playerClass;
}

int DiabloBridge::get_current_level() const {
	return devilution::g_D1EngineData.currentLevel;
}

int DiabloBridge::get_dungeon_type() const {
	return devilution::g_D1EngineData.dungeonType;
}

bool DiabloBridge::is_left_panel_open() const {
	return devilution::g_D1EngineData.leftPanelOpen;
}

bool DiabloBridge::is_right_panel_open() const {
	return devilution::g_D1EngineData.rightPanelOpen;
}

int DiabloBridge::get_player_level() const {
	return devilution::g_D1EngineData.playerLevel;
}

int DiabloBridge::get_player_xp() const {
	return devilution::g_D1EngineData.playerExp;
}

int DiabloBridge::get_player_next_xp() const {
	return devilution::g_D1EngineData.playerNextExp;
}

int DiabloBridge::get_player_spell() const {
	return devilution::g_D1EngineData.playerSpell;
}

int DiabloBridge::get_player_spell_type() const {
	return devilution::g_D1EngineData.playerSpellType;
}

Array DiabloBridge::get_belt_items() const {
	Array items;
	for (int i = 0; i < 8; ++i) {
		Dictionary d;
		d["slot"] = i;
		d["type"] = devilution::g_D1EngineData.beltTypes[i];
		d["count"] = devilution::g_D1EngineData.beltCounts[i];
		items.push_back(d);
	}
	return items;
}

void DiabloBridge::set_vanilla_hud_hidden(bool hidden) {
	devilution::SetVanillaHUDHidden(hidden);
}

bool DiabloBridge::is_vanilla_hud_hidden() const {
	return devilution::gbHideVanillaHUD;
}

bool DiabloBridge::is_game_running() const {
	return devilution::g_D1EngineData.isGameRunning;
}

Ref<ImageTexture> DiabloBridge::get_spell_icon_texture(int spell_id, int spell_type) {
	std::vector<uint8_t> rgba = devilution::GetSpellIconRgba(spell_id, spell_type);
	if (rgba.empty())
		return Ref<ImageTexture>();

	PackedByteArray pba;
	pba.resize(rgba.size());
	std::memcpy(pba.ptrw(), rgba.data(), rgba.size());

	Ref<Image> img = Image::create_from_data(56, 56, false, Image::FORMAT_RGBA8, pba);
	if (img.is_null())
		return Ref<ImageTexture>();

	return ImageTexture::create_from_image(img);
}

PackedInt32Array DiabloBridge::get_dungeon_grid() const {
	PackedInt32Array grid;
	grid.resize(112 * 112);
	int32_t *w = grid.ptrw();
	devilution::CopyD1DungeonGrid(w, 112 * 112);
	return grid;
}

int DiabloBridge::get_dungeon_tile(int x, int y) const {
	if (x < 0 || x >= 112 || y < 0 || y >= 112) {
		return 0;
	}
	// Direct access can also be queried from grid
	int32_t temp[112 * 112];
	devilution::CopyD1DungeonGrid(temp, 112 * 112);
	return temp[y * 112 + x];
}

void DiabloBridge::send_input(int type, int code, int state, int x, int y) {
	devilution::PushDevilutionXInput(static_cast<uint32_t>(type),
									 static_cast<uint32_t>(code),
									 static_cast<uint32_t>(state),
									 static_cast<int32_t>(x),
									 static_cast<int32_t>(y));
}

PackedByteArray DiabloBridge::get_frame_bytes() {
	PackedByteArray arr;
	int w = devilution::g_D1EngineData.width;
	int h = devilution::g_D1EngineData.height;
	if (w <= 0 || h <= 0) return arr;

	size_t reqSize = static_cast<size_t>(w) * h * 4;
	arr.resize(reqSize);
	uint8_t *dest = arr.ptrw();

	uint32_t outId = 0;
	int outW = 0, outH = 0;
	if (!devilution::CopyD1FrameBytes(dest, reqSize, &outId, &outW, &outH)) {
		arr.clear();
	}
	return arr;
}

int DiabloBridge::get_frame_width() const {
	return devilution::g_D1EngineData.width;
}

int DiabloBridge::get_frame_height() const {
	return devilution::g_D1EngineData.height;
}

int DiabloBridge::get_frame_id() const {
	return devilution::g_D1EngineData.frameId;
}

bool DiabloBridge::update_image_texture(Ref<ImageTexture> p_texture) {
	if (p_texture.is_null()) {
		return false;
	}

	int w = devilution::g_D1EngineData.width;
	int h = devilution::g_D1EngineData.height;
	if (w <= 0 || h <= 0) {
		return false;
	}

	PackedByteArray buffer;
	size_t reqSize = static_cast<size_t>(w) * h * 4;
	buffer.resize(reqSize);
	uint8_t *dest = buffer.ptrw();

	uint32_t outId = 0;
	int outW = 0, outH = 0;
	if (!devilution::CopyD1FrameBytes(dest, reqSize, &outId, &outW, &outH)) {
		return false;
	}

	Ref<Image> img = Image::create_from_data(outW, outH, false, Image::FORMAT_RGBA8, buffer);
	if (img.is_null() || img->is_empty()) {
		return false;
	}

	p_texture->set_image(img);
	return true;
}

Array DiabloBridge::poll_audio_events() {
	devilution::D1AudioEvent events[64];
	size_t count = devilution::PopDevilutionXAudioEvents(events, 64);
	Array result;
	for (size_t i = 0; i < count; ++i) {
		Dictionary d;
		d["type"] = (int)events[i].type; // 1 = MUSIC_PLAY, 2 = MUSIC_STOP, 3 = SFX_PLAY
		d["path"] = String(events[i].path);
		d["volume"] = events[i].volume;
		d["pan"] = events[i].pan;
		d["tile_x"] = events[i].tileX;
		d["tile_y"] = events[i].tileY;
		d["has_pos"] = events[i].hasPos;
		result.push_back(d);
	}
	return result;
}

PackedByteArray DiabloBridge::get_asset_bytes(const String &path) {
	CharString cs = path.utf8();
	std::vector<uint8_t> bytes = devilution::LoadDevilutionXAsset(cs.get_data());
	PackedByteArray pba;
	if (!bytes.empty()) {
		pba.resize(bytes.size());
		std::memcpy(pba.ptrw(), bytes.data(), bytes.size());
	}
	return pba;
}

Ref<AudioStreamWAV> DiabloBridge::load_wav_stream(const String &path, bool loop) {
	PackedByteArray pba = get_asset_bytes(path);
	if (pba.is_empty()) {
		return Ref<AudioStreamWAV>();
	}

	Ref<AudioStreamWAV> stream = AudioStreamWAV::load_from_buffer(pba);
	if (stream.is_valid() && loop) {
		int bytes_per_sample = (stream->get_format() == AudioStreamWAV::FORMAT_16_BITS) ? 2 : 1;
		int channels = stream->is_stereo() ? 2 : 1;
		int frame_size = bytes_per_sample * channels;
		int total_frames = (frame_size > 0) ? (stream->get_data().size() / frame_size) : 0;
		stream->set_loop_mode(AudioStreamWAV::LOOP_FORWARD);
		stream->set_loop_begin(0);
		stream->set_loop_end(total_frames);
	}
	return stream;
}
