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
var current_color_profile: int = 0 # Default: 0 = Vanilla (1996 Classic)
var current_relief_mode: int = 2   # Default: 2 = AMD FSR CAS Sharpness / Deep 3D
var current_fog_mode: int = 2      # Default: 2 = Dense Drift (Hellfire Smoke)
var vsync_enabled: bool = false    # Default: OFF (Uncapped Max FPS)
var show_fps: bool = false         # Default: OFF
var current_upscaler_mode: int = 1 # 1 = AMD FSR CAS Sharpness
var engine_torches: bool = true    # Default: ON (Procedural 3D flames & HDR glow)

var current_zoom_step: int = 1     # 0: 1.0x, 1: 1.5x, 2: 2.0x, 3: 2.5x, 4: 3.0x
var zoom_step_names = [
	"1.0x (Normál / Széles)",
	"1.5x (Köztes / Arany Középút)",
	"2.0x (Közeli / Zoomed)",
	"2.5x (Ultra Közeli / Ultra Close)",
	"3.0x (Epikus Részlet / Macro Close)"
]

# Godot 4.7 New AreaLight3D Node
var area_light: AreaLight3D
var area_light_enabled: bool = true

var upscaler_names = [
	"Upscaler [F7]: 8K Catmull-Rom Spline (Continuous Curves)",
	"Upscaler [F7]: AMD FidelityFX CAS Super-Resolution (Sharpness Boost)",
	"Upscaler [F7]: 3D Embossed Contour & Normal Relief",
	"Upscaler [F7]: Native 1:1 Direct Pixel-Art"
]

var color_names = [
	"Vanilla (1996 Classic 32-bit)",
	"Dark Gothic (OLED Black & Warm Embers)",
	"Hellish Crimson (Blood Moon)",
	"Crypt Cyan (Spectral Cold)",
	"Desaturated Noir (Grimdark)"
]

var fog_names = [
	"Atmospheric Fog: OFF",
	"Atmospheric Fog: Crypt Mist (Subtle Air Fog)",
	"Atmospheric Fog: Dense Drift (Hellfire Smoke)"
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
	setup_area_light()
	apply_upscaler_mode()
	update_fog_mode()
	
	show_osd("Godot 4.7 AreaLight3D Active | Scroll: Bidirectional Zoom | F3: Area Light | F4: V-Sync", 4.0)
	print("[Godot-D1 Bridge] Receiver initialized. AreaLight3D & Dense Drift active.")

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
	fps_label.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0, 0.8))
	fps_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	fps_label.visible = false
	canvas.add_child(fps_label)

func setup_area_light():
	area_light = AreaLight3D.new()
	area_light.name = "GothicAreaLight"
	area_light.light_color = Color(1.0, 0.72, 0.38, 1.0) # Warm gothic amber/torchlight
	area_light.light_energy = 1.35
	area_light.light_volumetric_fog_energy = 0.90 # Illuminates the dense smoke with soft rectangular beam!
	area_light.area_size = Vector2(8.0, 3.5)
	area_light.area_range = 14.0
	area_light.position = Vector3(0.0, 1.8, 3.2)
	area_light.rotation_degrees = Vector3(-25.0, 0.0, 0.0)
	add_child(area_light)

func show_osd(text: String, duration: float = 2.5):
	if osd_label:
		osd_label.text = text
func apply_zoom_step(old_step: int, new_step: int):
	if not camera: return
	
	if new_step == 0:
		# 1.0x Normal
		camera.fov = 60.0
		if old_step > 0:
			send_input_to_d1(5, 0, 0, 0, 0) # D1 ZoomOutMode (1.5x -> 1.0x)
	elif new_step == 1:
		# 1.5x Balanced
		camera.fov = 60.0
		if old_step == 0:
			send_input_to_d1(4, 0, 0, 0, 0) # D1 ZoomInMode (1.0x -> 1.5x)
		elif old_step >= 2:
			send_input_to_d1(5, 0, 0, 0, 0) # D1 ZoomOutMode (2.0x -> 1.5x)
	elif new_step == 2:
		# 2.0x Zoomed Close
		camera.fov = 60.0
		if old_step <= 1:
			send_input_to_d1(4, 0, 0, 0, 0) # D1 ZoomInMode (1.5x -> 2.0x)
	elif new_step == 3:
		# 2.5x Ultra Close (D1 2.0x + Godot 1.25x optical)
		if old_step <= 1:
			send_input_to_d1(4, 0, 0, 0, 0)
		camera.fov = 48.0
	elif new_step == 4:
		# 3.0x Epic Macro (D1 2.0x + Godot 1.50x optical)
		if old_step <= 1:
			send_input_to_d1(4, 0, 0, 0, 0)
		camera.fov = 40.0
		
	show_osd("[Zoom] " + zoom_step_names[new_step], 1.2)

func apply_upscaler_mode():
	var vp = get_viewport()
	if not vp: return
	
	if current_upscaler_mode == 0:
		# 8K Catmull-Rom Bicubic Spline + FSR 2.2 Native AA
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
		vp.scaling_3d_scale = 1.0
		vp.fsr_sharpness = 1.0
		current_relief_mode = 1
	elif current_upscaler_mode == 1:
		# AMD FSR CAS Sharpness Boost (Default)
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		vp.scaling_3d_scale = 1.0
		vp.fsr_sharpness = 1.2
		current_relief_mode = 2
	elif current_upscaler_mode == 2:
		# 3D Normal Relief
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
		vp.scaling_3d_scale = 1.0
		current_relief_mode = 3
	elif current_upscaler_mode == 3:
		# Native 1:1 Pixel-Art
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = 1.0
		current_relief_mode = 0
		
	update_shader_params()

func update_shader_params():
	if shader_material:
		shader_material.set_shader_parameter("color_profile", current_color_profile)
		shader_material.set_shader_parameter("relief_mode", current_relief_mode)
		shader_material.set_shader_parameter("engine_torches", engine_torches)

func update_fog_mode():
	if world_env and world_env.environment:
		var env = world_env.environment
		if current_fog_mode == 0:
			env.volumetric_fog_enabled = false
		elif current_fog_mode == 1:
			env.volumetric_fog_enabled = true
			env.volumetric_fog_density = 0.015
			env.volumetric_fog_emission = Color(0.02, 0.02, 0.02, 1)
			env.volumetric_fog_emission_energy = 0.2
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
	
	if area_light and area_light_enabled:
		var flicker = 1.30 + 0.14 * sin(time_accum * 4.5) * cos(time_accum * 2.2)
		area_light.light_energy = flicker
	
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
	var _player_x = file.get_float()
	var _player_y = file.get_float()
	var _zoom_mode = file.get_32()
	var _torch_count = file.get_32()
	
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

func _input(event: InputEvent):
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_F3:
			area_light_enabled = !area_light_enabled
			if area_light:
				area_light.visible = area_light_enabled
			show_osd("[F3] Godot 4.7 AreaLight3D: " + ("ENABLED (Soft Atmospheric Light Shafts)" if area_light_enabled else "DISABLED"))
			return
		elif event.keycode == KEY_F4:
			vsync_enabled = !vsync_enabled
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED)
			show_osd("[F4] V-Sync: " + ("ON (Screen Refresh Rate Limit)" if vsync_enabled else "OFF (Uncapped Max FPS)"))
			return
		elif event.keycode == KEY_F5:
			engine_torches = !engine_torches
			update_shader_params()
			show_osd("[F5] Engine 3D Torches & HDR Glow: " + ("ENABLED" if engine_torches else "DISABLED"))
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
			current_relief_mode = (current_relief_mode + 1) % 4
			update_shader_params()
			show_osd("[F11] 3D Surface Relief: Mode " + str(current_relief_mode))
			return

	if not FileAccess.file_exists("/dev/shm/d1_godot_frame"):
		return
		
	var vp_size = get_viewport().get_visible_rect().size
	if vp_size.x <= 0 or vp_size.y <= 0:
		return
		
	if event is InputEventMouseMotion:
		var mx = int((event.position.x / vp_size.x) * d1_width)
		var my = int((event.position.y / vp_size.y) * d1_height)
		send_input_to_d1(1, 0, 0, mx, my)
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
			
		var mx = int((event.position.x / vp_size.x) * d1_width)
		var my = int((event.position.y / vp_size.y) * d1_height)
		var btn = 1
		if event.button_index == MOUSE_BUTTON_RIGHT:
			btn = 3
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			btn = 2
		var state = 1 if event.pressed else 0
		send_input_to_d1(2, btn, state, mx, my)
	elif event is InputEventKey:
		var key = get_sdl_key(event.keycode)
		var state = 1 if event.pressed else 0
		send_input_to_d1(3, key, state, 0, 0)

func send_input_to_d1(msg_type: int, code: int, state: int, x: int, y: int):
	var file = FileAccess.open("/dev/shm/d1_godot_frame", FileAccess.READ_WRITE)
	if not file:
		return
		
	# Offset 304: inputWriteIdx (4 bytes), 308: inputReadIdx (4 bytes)
	file.seek(304)
	var write_idx = file.get_32()
	
	# Slot in ring buffer: 312 + (write_idx % 128) * 20
	var slot_offset = 312 + (write_idx % 128) * 20
	file.seek(slot_offset)
	file.store_32(msg_type)
	file.store_32(code)
	file.store_32(state)
	file.store_32(x)
	file.store_32(y)
	
	# Increment inputWriteIdx
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
	# Navigation & Arrow keys for menus and dialogs
	if keycode == KEY_UP: return 1073741906
	if keycode == KEY_DOWN: return 1073741905
	if keycode == KEY_LEFT: return 1073741904
	if keycode == KEY_RIGHT: return 1073741903
	if keycode == KEY_PAGEUP: return 1073741899
	if keycode == KEY_PAGEDOWN: return 1073741902
	if keycode == KEY_HOME: return 1073741898
	if keycode == KEY_END: return 1073741901
	return keycode
