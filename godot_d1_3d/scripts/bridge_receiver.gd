extends Node3D

@export var mesh_instance: MeshInstance3D
@export var hero_light: OmniLight3D
@export var camera: Camera3D
@export var world_env: WorldEnvironment

var image_texture: ImageTexture
var shader_material: ShaderMaterial
var last_frame_id: int = -1
var time_accum: float = 0.0
var had_connected: bool = false

var d1_width: int = 2560
var d1_height: int = 1440

# User Requested Defaults:
var vsync_enabled: bool = true          # Default: ON (Smooth 144Hz Monitor Sync)
var show_fps: bool = true               # Default: ON (Immediate performance readout)
var current_fog_mode: int = 1           # Default: 1 = Crypt Mist (Subtle Dungeon Atmosphere)
var current_color_profile: int = 2      # Default: 2 = Hellish Crimson (Warm Blood-Amber, HUD bypassed)
var current_upscaler_mode: int = 2      # Default: 2 = Anime4K Ultra Thin Lines & Vector Contours
var current_relief_mode: int = 3        # Default: 3 = Deep 3D Embossed Contour & Normal Relief
var engine_torches: bool = true         # Default: ON (Comprehensive 3.5x HDR Glow & Fire)
var hero_light_enabled: bool = true     # Default: ON (Soft Natural Dungeon Torchlight, No Ugly Rectangles!)
var wet_floor: bool = true              # Default: ON (Wet Cobblestone PBR Reflections, Soft Specular)
var playfield_zoom: float = 1.0

var current_zoom_step: int = 1          # Default: 1.5x (Balanced View)
var zoom_step_names = [
	"1.0x (Normál / Széles Látószög)",
	"1.5x (Köztes / Arany Középút)",
	"2.0x (Közeli / Zoomed)",
	"2.5x (Ultra Közeli / Ultra Close)",
	"3.0x (Epikus Makró / Macro Close)"
]

var player_target_pos: Vector2 = Vector2.ZERO

var upscaler_names = [
	"Upscaler [F7]: AMD FidelityFX CAS Super-Resolution",
	"Upscaler [F7]: Anime4K / Neural Spatial CNN (Edge Reconstruction)",
	"Upscaler [F7]: Anime4K Ultra Thin Lines & Vector Contours (Default)",
	"Upscaler [F7]: 8K Catmull-Rom Bicubic Spline (Continuous Curves)",
	"Upscaler [F7]: Native 1:1 Direct Retro Pixel-Art"
]

var color_names = [
	"Vanilla (1996 Classic 32-bit - HUD Untouched)",
	"Dark Gothic (Refined Gentle OLED Shadow)",
	"Hellish Crimson (Warm Blood-Amber - Default)",
	"Crypt Cyan (Gothic Cold Chill)",
	"Desaturated Noir (Grimdark Film)"
]

var fog_names = [
	"Atmospheric Fog: OFF",
	"Atmospheric Fog: Crypt Mist (Subtle Dungeon Pára - Default)",
	"Atmospheric Fog: Dense Drift (Hellfire Smoke)"
]

var relief_names = [
	"3D Surface Relief [F11]: OFF",
	"3D Surface Relief [F11]: Mode 1 (Subtle 3D)",
	"3D Surface Relief [F11]: Mode 2 (Balanced 3D Emboss)",
	"3D Surface Relief [F11]: Mode 3 (Deep 3D Embossed Relief - Default)",
	"3D Surface Relief [F11]: Mode 4 (Extreme Sculpted 3D Relief)"
]

var osd_label: Label
var osd_timer: float = 0.0
var fps_label: Label
var fps_timer: float = 0.0
var frame_counter: int = 0
var current_fps: int = 0

func _ready():
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	DisplayServer.window_move_to_foreground()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED)
	
	if not hero_light:
		hero_light = get_node_or_null("HeroTorchLight")
	
	# Solid Flat 2D Viewport setup (pure clean fullscreen)
	if mesh_instance:
		mesh_instance.rotation_degrees = Vector3.ZERO
		mesh_instance.position = Vector3.ZERO
		if mesh_instance.material_override:
			shader_material = mesh_instance.material_override as ShaderMaterial
			update_shader_params()
			
	if camera:
		camera.fov = 60.0
		camera.position = Vector3(0, 0, 7.8)
		camera.rotation_degrees = Vector3.ZERO
		
	setup_osd()
	apply_upscaler_mode()
	update_fog_mode()
	update_torch_light()
	
	show_osd("Diablo 1 Resurrected | Crimson + Anime4K + Crypt Mist Active | F4: V-Sync | F6: Torchlight", 4.0)
	print("[Godot-D1 Bridge] Receiver initialized with user defaults. Anime4K, Crimson, Crypt Mist & Deep 3D active.")

func setup_osd():
	var canvas = CanvasLayer.new()
	canvas.layer = 100
	add_child(canvas)
	
	osd_label = Label.new()
	osd_label.position = Vector2(40, 40)
	osd_label.add_theme_font_size_override("font_size", 22)
	osd_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 1.0))
	osd_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	osd_label.add_theme_constant_override("shadow_offset_x", 2)
	osd_label.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(osd_label)
	
	fps_label = Label.new()
	fps_label.position = Vector2(40, 75)
	fps_label.add_theme_font_size_override("font_size", 18)
	fps_label.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0, 0.85))
	fps_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	fps_label.visible = show_fps
	canvas.add_child(fps_label)

func update_torch_light():
	if hero_light:
		hero_light.visible = hero_light_enabled
		hero_light.light_color = Color(1.0, 0.74, 0.40, 1.0) # Warm gothic amber
		hero_light.light_energy = 0.55
		hero_light.light_specular = 0.12 # Soft natural glint, no blinding white hotspot
		hero_light.omni_range = 9.5
		hero_light.omni_attenuation = 1.8

func show_osd(text: String, duration: float = 2.5):
	if osd_label:
		osd_label.text = text
		osd_timer = duration

func apply_zoom_step(old_step: int, new_step: int):
	# Camera FOV stays 60.0 ALWAYS! The HUD stays 100% visible and pinned!
	if camera:
		camera.fov = 60.0
		
	if new_step == 0:
		# 1.0x Normal
		playfield_zoom = 1.0
		if old_step > 0:
			send_input_to_d1(5, 0, 0, 0, 0) # D1 ZoomOutMode (1.5x -> 1.0x)
	elif new_step == 1:
		# 1.5x Balanced
		playfield_zoom = 1.0
		if old_step == 0:
			send_input_to_d1(4, 0, 0, 0, 0) # D1 ZoomInMode (1.0x -> 1.5x)
		elif old_step >= 2:
			send_input_to_d1(5, 0, 0, 0, 0) # D1 ZoomOutMode (2.0x -> 1.5x)
	elif new_step == 2:
		# 2.0x Zoomed Close
		playfield_zoom = 1.0
		if old_step <= 1:
			send_input_to_d1(4, 0, 0, 0, 0) # D1 ZoomInMode (1.5x -> 2.0x)
	elif new_step == 3:
		# 2.5x Ultra Close (D1 2.0x + 1.25x playfield zoom, HUD remains 100% visible!)
		if old_step <= 1:
			send_input_to_d1(4, 0, 0, 0, 0)
		playfield_zoom = 1.25
	elif new_step == 4:
		# 3.0x Epic Macro (D1 2.0x + 1.50x playfield zoom, HUD remains 100% visible!)
		if old_step <= 1:
			send_input_to_d1(4, 0, 0, 0, 0)
		playfield_zoom = 1.50
		
	update_shader_params()
	show_osd("[Zoom] " + zoom_step_names[new_step], 1.2)

func apply_upscaler_mode():
	var vp = get_viewport()
	if not vp: return
	
	if current_upscaler_mode == 0:
		# AMD FidelityFX CAS Super-Resolution
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		vp.scaling_3d_scale = 1.0
		vp.fsr_sharpness = 1.2
	elif current_upscaler_mode in [1, 2]:
		# Anime4K Neural Edge / Ultra Thin Lines (Default)
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = 1.0
	elif current_upscaler_mode == 3:
		# 8K Catmull-Rom Bicubic Spline
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
		vp.scaling_3d_scale = 1.0
		vp.fsr_sharpness = 1.0
	elif current_upscaler_mode == 4:
		# Native 1:1 Direct Pixel-Art
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = 1.0
		
	update_shader_params()

func update_shader_params():
	if shader_material:
		shader_material.set_shader_parameter("color_profile", current_color_profile)
		shader_material.set_shader_parameter("upscaler_mode", current_upscaler_mode)
		shader_material.set_shader_parameter("relief_mode", current_relief_mode)
		shader_material.set_shader_parameter("engine_torches", engine_torches)
		shader_material.set_shader_parameter("wet_floor", wet_floor)
		shader_material.set_shader_parameter("playfield_zoom", playfield_zoom)

func update_fog_mode():
	if world_env and world_env.environment:
		var env = world_env.environment
		if current_fog_mode == 0:
			env.volumetric_fog_enabled = false
		elif current_fog_mode == 1:
			# Crypt Mist (Subtle atmospheric dungeon pára - Default)
			env.volumetric_fog_enabled = true
			env.volumetric_fog_density = 0.016
			env.volumetric_fog_emission = Color(0.02, 0.02, 0.02, 1)
			env.volumetric_fog_emission_energy = 0.22
		elif current_fog_mode == 2:
			# Dense Drift (Hellfire Smoke)
			env.volumetric_fog_enabled = true
			env.volumetric_fog_density = 0.038
			env.volumetric_fog_emission = Color(0.06, 0.03, 0.015, 1)
			env.volumetric_fog_emission_energy = 0.35

func _process(delta: float):
	time_accum += delta
	frame_counter += 1
	fps_timer += delta
	
	if hero_light and hero_light_enabled:
		# Organic soft torch breathing flicker
		var flicker = 0.55 + 0.08 * sin(time_accum * 4.8) * cos(time_accum * 2.3)
		hero_light.light_energy = flicker
		# Keep light gently centered on the playfield
		hero_light.position = Vector3(0.0, 0.3, 2.8)
	
	if fps_timer >= 1.0:
		current_fps = frame_counter
		frame_counter = 0
		fps_timer = 0.0
		if fps_label and fps_label.visible:
			fps_label.text = "Godot 4.7.2 Forward+ Vulkan: %d FPS (RX 6800 XT)" % current_fps
	
	if osd_timer > 0.0:
		osd_timer -= delta
		if osd_timer <= 0.0 and osd_label:
			osd_label.text = ""
			
	if not FileAccess.file_exists("/dev/shm/d1_godot_frame"):
		if had_connected:
			get_tree().quit()
		return
		
	var file = FileAccess.open("/dev/shm/d1_godot_frame", FileAccess.READ)
	if not file:
		if had_connected:
			get_tree().quit()
		return
		
	var magic = file.get_32()
	if magic == 0xDEADBEEF or magic == 0:
		get_tree().quit()
		return
		
	if magic != 0x44315242: # "D1RB"
		return
		
	had_connected = true
		
	var _version = file.get_32()
	d1_width = file.get_32()
	d1_height = file.get_32()
	var _pitch = file.get_32()
	var frame_id = file.get_32()
	var _timestamp = file.get_32()
	var px = file.get_float()
	var py = file.get_float()
	var _zoom_mode = file.get_32()
	var _torch_count = file.get_32()
	
	if px > 0.0 or py > 0.0:
		player_target_pos = Vector2((px / 112.0 - 0.5) * 8.0, (py / 112.0 - 0.5) * -4.5)
	
	# Skip to payload at 4096 bytes (4KB aligned page)
	file.seek(4096)
	
	if frame_id != last_frame_id:
		last_frame_id = frame_id
		var pixel_bytes = file.get_buffer(d1_width * d1_height * 4)
		if pixel_bytes.size() == d1_width * d1_height * 4:
			update_frame_texture(d1_width, d1_height, pixel_bytes)

func update_frame_texture(w: int, h: int, bytes: PackedByteArray):
	var img = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, bytes)
	if not img:
		return
		
	if not image_texture or image_texture.get_width() != w or image_texture.get_height() != h:
		image_texture = ImageTexture.create_from_image(img)
		if shader_material:
			shader_material.set_shader_parameter("d1_texture", image_texture)
	else:
		image_texture.update(img)

func get_game_mouse_pos(screen_pos: Vector2, vp_size: Vector2) -> Vector2i:
	var norm_x = screen_pos.x / vp_size.x
	var norm_y = screen_pos.y / vp_size.y
	
	var hud_boundary = 0.898
	var mapped_x = norm_x
	var mapped_y = norm_y
	
	if playfield_zoom > 1.001 and norm_y < hud_boundary:
		var center_x = 0.5
		var center_y = hud_boundary * 0.5
		mapped_x = center_x + (norm_x - center_x) / playfield_zoom
		mapped_y = center_y + (norm_y - center_y) / playfield_zoom
		
	return Vector2i(int(mapped_x * d1_width), int(mapped_y * d1_height))

func _input(event: InputEvent):
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_F4:
			vsync_enabled = !vsync_enabled
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED)
			show_osd("[F4] V-Sync: " + ("ON (Screen Refresh Rate Limit)" if vsync_enabled else "OFF (Uncapped Max FPS)"))
			return
		elif event.keycode == KEY_F5:
			engine_torches = !engine_torches
			update_shader_params()
			show_osd("[F5] Engine 3D Torches & HDR Glow: " + ("ENABLED (3.5x HDR Bloom)" if engine_torches else "DISABLED"))
			return
		elif event.keycode == KEY_F6:
			hero_light_enabled = !hero_light_enabled
			update_torch_light()
			show_osd("[F6] Dungeon Soft Torchlight: " + ("ENABLED (Warm Candlelight)" if hero_light_enabled else "DISABLED"))
			return
		elif event.keycode == KEY_F7:
			current_upscaler_mode = (current_upscaler_mode + 1) % upscaler_names.size()
			apply_upscaler_mode()
			show_osd(upscaler_names[current_upscaler_mode])
			return
		elif event.keycode == KEY_F8:
			show_fps = !show_fps
			if fps_label:
				fps_label.visible = show_fps
			show_osd("[F8] FPS Display: " + ("ON" if show_fps else "OFF"))
			return
		elif event.keycode == KEY_F9:
			current_fog_mode = (current_fog_mode + 1) % 3
			update_fog_mode()
			show_osd("[F9] " + fog_names[current_fog_mode])
			return
		elif event.keycode == KEY_F10:
			current_color_profile = (current_color_profile + 1) % color_names.size()
			update_shader_params()
			show_osd("[F10] Color Profile: " + color_names[current_color_profile])
			return
		elif event.keycode == KEY_F11:
			current_relief_mode = (current_relief_mode + 1) % relief_names.size()
			update_shader_params()
			show_osd(relief_names[current_relief_mode])
			return
		elif event.keycode == KEY_F12:
			wet_floor = !wet_floor
			update_shader_params()
			show_osd("[F12] Dungeon Floor: " + ("Wet & Reflective Cobblestone (PBR Specular ON)" if wet_floor else "Dry Stone Surface (OFF)"))
			return

	if not FileAccess.file_exists("/dev/shm/d1_godot_frame"):
		return
		
	var vp_size = get_viewport().get_visible_rect().size
	if vp_size.x <= 0 or vp_size.y <= 0:
		return
		
	if event is InputEventMouseMotion:
		var mpos = get_game_mouse_pos(event.position, vp_size)
		send_input_to_d1(1, 0, 0, mpos.x, mpos.y)
	elif event is InputEventMouseButton:
		# 5-Step Bidirectional in-game Zoom (1.0x, 1.5x, 2.0x, 2.5x, 3.0x)
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			if current_zoom_step < 4:
				var old_s = current_zoom_step
				current_zoom_step += 1
				apply_zoom_step(old_s, current_zoom_step)
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if current_zoom_step > 0:
				var old_s = current_zoom_step
				current_zoom_step -= 1
				apply_zoom_step(old_s, current_zoom_step)
			return
			
		var mpos = get_game_mouse_pos(event.position, vp_size)
		var btn = 1
		if event.button_index == MOUSE_BUTTON_RIGHT:
			btn = 3
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			btn = 2
		var state = 1 if event.pressed else 0
		send_input_to_d1(2, btn, state, mpos.x, mpos.y)
	elif event is InputEventKey:
		var key = get_sdl_key(event.keycode)
		var state = 1 if event.pressed else 0
		send_input_to_d1(3, key, state, 0, 0)

func send_input_to_d1(msg_type: int, code: int, state: int, x: int, y: int):
	var file = FileAccess.open("/dev/shm/d1_godot_frame", FileAccess.READ_WRITE)
	if not file:
		return
		
	file.seek(304)
	var write_idx = file.get_32()
	
	var slot_offset = 312 + (write_idx % 128) * 20
	file.seek(slot_offset)
	file.store_32(msg_type)
	file.store_32(code)
	file.store_32(state)
	file.store_32(x)
	file.store_32(y)
	
	file.seek(304)
	file.store_32(write_idx + 1)
	file.flush()

func get_sdl_key(keycode: int) -> int:
	if keycode == KEY_ESCAPE: return 27
	if keycode == KEY_ENTER: return 13
	if keycode == KEY_SPACE: return 32
	if keycode == KEY_TAB: return 9
	if keycode == KEY_BACKSPACE: return 8
	if keycode >= KEY_0 and keycode <= KEY_9: return keycode
	if keycode >= KEY_A and keycode <= KEY_Z: return keycode + 32
	if keycode >= KEY_F1 and keycode <= KEY_F12: return 1073741882 + (keycode - KEY_F1)
	if keycode == KEY_SHIFT: return 1073742049
	if keycode == KEY_CTRL: return 1073742048
	if keycode == KEY_ALT: return 1073742050
	if keycode == KEY_UP: return 1073741906
	if keycode == KEY_DOWN: return 1073741905
	if keycode == KEY_LEFT: return 1073741904
	if keycode == KEY_RIGHT: return 1073741903
	if keycode == KEY_PAGEUP: return 1073741899
	if keycode == KEY_PAGEDOWN: return 1073741902
	if keycode == KEY_HOME: return 1073741898
	if keycode == KEY_END: return 1073741901
	return keycode
