#ifndef DIABLO_BRIDGE_H
#define DIABLO_BRIDGE_H

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/audio_stream_wav.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace godot {

class DiabloBridge : public Node {
	GDCLASS(DiabloBridge, Node)

private:
	bool engine_started = false;

protected:
	static void _bind_methods();

public:
	DiabloBridge();
	~DiabloBridge();

	// Engine Lifecycle
	bool init_engine(const String &mpq_dir);
	void step_tick();
	bool is_engine_ready() const;
	bool is_engine_running() const;
	bool is_quit_requested() const;
	void quit_engine();

	// Real-Time Direct Memory Access (Zero IPC, pure C++ memory pointers!)
	Vector2i get_player_tile_pos() const;
	Vector2 get_player_norm_pos() const;
	int get_player_hp() const;
	int get_player_max_hp() const;
	int get_player_mana() const;
	int get_player_max_mana() const;
	int get_player_gold() const;
	int get_player_class() const;
	int get_current_level() const;
	int get_dungeon_type() const;
	bool is_left_panel_open() const;
	bool is_right_panel_open() const;
	int get_player_level() const;
	int get_player_xp() const;
	int get_player_next_xp() const;
	int get_player_spell() const;
	int get_player_spell_type() const;
	Array get_belt_items() const;
	void set_vanilla_hud_hidden(bool hidden);
	bool is_vanilla_hud_hidden() const;
	bool is_game_running() const;
	Ref<ImageTexture> get_spell_icon_texture(int spell_id, int spell_type);

	// Direct 112x112 Dungeon Grid Access for Godot TileMap / GridMap
	PackedInt32Array get_dungeon_grid() const;
	int get_dungeon_tile(int x, int y) const;

	// Direct Input Routing (In-memory C++ event dispatch, no SHM!)
	void send_input(int type, int code, int state, int x, int y);
	void send_key_event(int keycode, bool pressed);

	// Direct Video Frame Access (In-memory blit directly to Godot Image)
	PackedByteArray get_frame_bytes();
	int get_frame_width() const;
	int get_frame_height() const;
	int get_frame_id() const;
	bool update_image_texture(Ref<ImageTexture> p_texture);

	// Audio & Asset Interception
	Array poll_audio_events();
	PackedByteArray get_asset_bytes(const String &path);
	Ref<AudioStreamWAV> load_wav_stream(const String &path, bool loop = false);
};

} // namespace godot

#endif // DIABLO_BRIDGE_H
