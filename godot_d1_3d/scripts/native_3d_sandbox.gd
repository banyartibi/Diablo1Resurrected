extends Node3D

# ==============================================================================
# Native Godot 3D Diablo Sandbox (Lépcső 2 / Step 2: 3D Billboard Sprites & PBR)
# Authentic animated Diablo 1 character and monster sprites rendered as 3D
# Billboard Sprites (Sprite3D) with real-time lighting, plus gothic PBR stone
# materials for procedural 3D dungeon geometry.
# ==============================================================================

var diablo_bridge = null
var main_receiver = null
var is_sandbox_active: bool = false

# Camera & Smooth Tracking
var camera: Camera3D = null
var camera_target: Vector3 = Vector3.ZERO
var camera_distance: float = 13.0
var camera_pitch: float = 50.0       # Pitch angle in degrees (Default: 50°, range: 25° - 75°)
var camera_yaw: float = 0.0          # Yaw angle in degrees (Isometric orbit: Q/E or MMB drag)
var is_orbiting: bool = false
var last_mouse_pos: Vector2 = Vector2.ZERO

# Dungeon Procedural MultiMeshes
var floor_mmi: MultiMeshInstance3D
var wall_mmi: MultiMeshInstance3D
var door_mmi: MultiMeshInstance3D
var dungeon_built: bool = false
var last_solidity_hash: int = 0
var last_check_timer: float = 0.0

# Player Entity (3D Billboard Sprite)
var player_root: Node3D
var player_sprite: Sprite3D
var player_texture: ImageTexture = null
var last_player_frame: int = -1
var last_player_dir: int = -1
var player_lantern: OmniLight3D
var player_ring: MeshInstance3D
var player_arrow: MeshInstance3D
var player_target_pos: Vector3 = Vector3.ZERO

# Monster Entities (3D Billboard Sprites)
var monsters_root: Node3D
var monster_instances: Dictionary = {}    # id (int) -> Node3D
var monster_textures: Dictionary = {}     # id (int) -> ImageTexture
var monster_last_frame: Dictionary = {}   # id (int) -> int
var last_gamma_value: int = -1  # bridge gamma; on change -> invalidate palette-baked sprites
var monster_last_dir: Dictionary = {}     # id (int) -> int

# Waypoint / Click Feedback
var click_marker: MeshInstance3D
var click_fade: float = 0.0

# Coordinate Math Constant
const TILE_SCALE: float = 0.75

# Time accumulator for organic lighting
var time_accum: float = 0.0

func _ready():
	setup_scene_nodes()
	set_process(false)

func setup_scene_nodes():
	# 1. Environment & Ambient Lighting
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.015, 0.02, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.38, 0.45, 1.0)
	env.ambient_light_energy = 0.40
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.3
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.025
	env.volumetric_fog_albedo = Color(0.2, 0.25, 0.35, 1.0)

	var we = WorldEnvironment.new()
	we.name = "SandboxWorldEnv"
	we.environment = env
	add_child(we)

	# 2. Subtle Gothic Sun / Key Light
	var dir_light = DirectionalLight3D.new()
	dir_light.name = "GothicMoonlight"
	dir_light.transform = Transform3D(Basis().rotated(Vector3.UP, deg_to_rad(-35.0)).rotated(Vector3.RIGHT, deg_to_rad(-65.0)), Vector3(0, 10, 0))
	dir_light.light_color = Color(0.65, 0.75, 0.95, 1.0)
	dir_light.light_energy = 0.25
	dir_light.shadow_enabled = true
	add_child(dir_light)

	# 3. Procedural MultiMeshes for Dungeon Geometry with PBR stone relief
	setup_dungeon_multimeshes()

	# 4. Player Entity with authentic animated 3D Billboard Sprite
	setup_player_entity()

	# 5. Monsters Container
	monsters_root = Node3D.new()
	monsters_root.name = "MonstersRoot"
	add_child(monsters_root)

	# 6. Click Waypoint Marker
	setup_click_marker()

	# 7. Sandbox Camera
	if not camera:
		camera = get_node_or_null("Camera3D")
	if not camera:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		camera.fov = 50.0
		add_child(camera)

func setup_dungeon_multimeshes():
	# Floor MultiMesh (Andezite flagstones with procedural relief)
	floor_mmi = MultiMeshInstance3D.new()
	floor_mmi.name = "FloorMultiMesh"
	var floor_mm = MultiMesh.new()
	floor_mm.transform_format = MultiMesh.TRANSFORM_3D
	var floor_box = BoxMesh.new()
	floor_box.size = Vector3(1.06, 0.10, 1.06)

	var floor_noise = FastNoiseLite.new()
	floor_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	floor_noise.frequency = 0.09
	floor_noise.cellular_distance_function = FastNoiseLite.DISTANCE_MANHATTAN
	var floor_tex = NoiseTexture2D.new()
	floor_tex.width = 256
	floor_tex.height = 256
	floor_tex.as_normal_map = true
	floor_tex.bump_strength = 6.0
	floor_tex.noise = floor_noise

	var floor_mat = StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.24, 0.22, 0.20)
	floor_mat.roughness = 0.65
	floor_mat.metallic = 0.08
	floor_mat.normal_enabled = true
	floor_mat.normal_scale = 0.75
	floor_mat.normal_texture = floor_tex
	floor_box.material = floor_mat
	floor_mm.mesh = floor_box
	floor_mmi.multimesh = floor_mm
	add_child(floor_mmi)

	# Wall MultiMesh (Ancient subterranean basalt masonry)
	wall_mmi = MultiMeshInstance3D.new()
	wall_mmi.name = "WallMultiMesh"
	var wall_mm = MultiMesh.new()
	wall_mm.transform_format = MultiMesh.TRANSFORM_3D
	var wall_box = BoxMesh.new()
	wall_box.size = Vector3(1.06, 2.2, 1.06)

	var wall_noise = FastNoiseLite.new()
	wall_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	wall_noise.frequency = 0.06
	var wall_tex = NoiseTexture2D.new()
	wall_tex.width = 256
	wall_tex.height = 256
	wall_tex.as_normal_map = true
	wall_tex.bump_strength = 8.0
	wall_tex.noise = wall_noise

	var wall_mat = StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.36, 0.30, 0.26)
	wall_mat.roughness = 0.85
	wall_mat.metallic = 0.02
	wall_mat.normal_enabled = true
	wall_mat.normal_scale = 1.0
	wall_mat.normal_texture = wall_tex
	wall_box.material = wall_mat
	wall_mm.mesh = wall_box
	wall_mmi.multimesh = wall_mm
	add_child(wall_mmi)

	# Door / Archway MultiMesh (Carved stone with aged bronze trim)
	door_mmi = MultiMeshInstance3D.new()
	door_mmi.name = "DoorMultiMesh"
	var door_mm = MultiMesh.new()
	door_mm.transform_format = MultiMesh.TRANSFORM_3D
	var door_box = BoxMesh.new()
	door_box.size = Vector3(1.06, 2.0, 0.35)
	var door_mat = StandardMaterial3D.new()
	door_mat.albedo_color = Color(0.48, 0.36, 0.22)
	door_mat.roughness = 0.5
	door_mat.metallic = 0.25
	door_box.material = door_mat
	door_mm.mesh = door_box
	door_mmi.multimesh = door_mm
	add_child(door_mmi)

func setup_player_entity():
	player_root = Node3D.new()
	player_root.name = "PlayerEntity"
	add_child(player_root)

	# Hero 3D Billboard Sprite (Authentic Animated Diablo Pixel Art)
	player_sprite = Sprite3D.new()
	player_sprite.name = "PlayerSprite3D"
	player_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	player_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	player_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	player_sprite.shaded = true
	player_sprite.pixel_size = 0.016
	player_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	player_root.add_child(player_sprite)

	# Rune Ring at Feet
	player_ring = MeshInstance3D.new()
	var ring_torus = TorusMesh.new()
	ring_torus.inner_radius = 0.44
	ring_torus.outer_radius = 0.52
	ring_torus.rings = 16
	ring_torus.ring_segments = 8
	player_ring.mesh = ring_torus
	player_ring.position.y = 0.03
	var ring_mat = StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(1.0, 0.85, 0.4, 0.85)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	player_ring.material_override = ring_mat
	player_root.add_child(player_ring)

	# Warm Torch Light
	player_lantern = OmniLight3D.new()
	player_lantern.name = "HeroLantern"
	player_lantern.position = Vector3(0, 1.45, 0)
	player_lantern.light_color = Color(1.0, 0.74, 0.42)
	player_lantern.light_energy = 1.40
	player_lantern.omni_range = 7.5
	player_lantern.omni_attenuation = 1.4
	player_lantern.shadow_enabled = true
	player_root.add_child(player_lantern)

	# Direction Indicator (Subtle Forward Arrow)
	player_arrow = MeshInstance3D.new()
	var arrow_mesh = PrismMesh.new()
	arrow_mesh.size = Vector3(0.24, 0.35, 0.06)
	player_arrow.mesh = arrow_mesh
	player_arrow.rotation_degrees = Vector3(-90, 0, 0)
	player_arrow.position = Vector3(0, 0.04, 0.70)
	var arrow_mat = StandardMaterial3D.new()
	arrow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arrow_mat.albedo_color = Color(1.0, 0.8, 0.2, 0.7)
	arrow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	player_arrow.material_override = arrow_mat
	player_root.add_child(player_arrow)

func setup_click_marker():
	click_marker = MeshInstance3D.new()
	click_marker.name = "ClickMarker"
	var marker_torus = TorusMesh.new()
	marker_torus.inner_radius = 0.32
	marker_torus.outer_radius = 0.40
	click_marker.mesh = marker_torus
	click_marker.position.y = 0.03
	var marker_mat = StandardMaterial3D.new()
	marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_mat.albedo_color = Color(0.9, 0.75, 0.2, 0.0)
	marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	click_marker.material_override = marker_mat
	click_marker.visible = false
	add_child(click_marker)

# --- Coordinate Conversion Utilities ---
func tile_to_world_3d(tx: float, ty: float) -> Vector3:
	return Vector3((tx - ty) * TILE_SCALE, 0.0, (tx + ty) * TILE_SCALE)

func world_3d_to_tile(pos: Vector3) -> Vector2:
	var tx = (pos.z + pos.x) / (2.0 * TILE_SCALE)
	var ty = (pos.z - pos.x) / (2.0 * TILE_SCALE)
	return Vector2(tx, ty)

# --- Activation & Lifecycle ---
func activate():
	is_sandbox_active = true
	visible = true
	set_process(true)
	if camera:
		camera.make_current()
	rebuild_dungeon_if_needed(true)
	snap_camera_to_player()
	print("[Native 3D Sandbox] Activated! Real-time 3D camera, Billboard Sprites and geometry live.")

func deactivate():
	is_sandbox_active = false
	visible = false
	set_process(false)
	print("[Native 3D Sandbox] Deactivated. Classic 2.5D view restored.")

func snap_camera_to_player():
	if not diablo_bridge:
		return
	var p_data = diablo_bridge.get_player_continuous_pos()
	var px = p_data.get("pos_x", 25.0)
	var py = p_data.get("pos_y", 25.0)
	camera_target = tile_to_world_3d(px, py)
	update_camera_transform()

func _process(delta: float):
	if not is_sandbox_active or not diablo_bridge:
		return
	if diablo_bridge.has_method("is_level_loading") and diablo_bridge.is_level_loading():
		return

	# Gamma changed (options slider) -> palette-baked sprite textures are stale. Force a re-fetch with the new
	# palette so the whole scene brightens/darkens like legacy mode. We poll the gamma VALUE (not the raw palette
	# version, which also ticks every frame for animated lava in cave/crypt levels).
	if diablo_bridge.has_method("get_gamma"):
		var cur_gamma = diablo_bridge.get_gamma()
		if cur_gamma != last_gamma_value:
			last_gamma_value = cur_gamma
			player_texture = null
			last_player_frame = -1
			last_player_dir = -1
			monster_textures.clear()
			monster_last_frame.clear()

	time_accum += delta
	last_check_timer += delta

	# Check and rebuild dungeon if map changes (every 1.5 seconds)
	if last_check_timer >= 1.5:
		last_check_timer = 0.0
		rebuild_dungeon_if_needed(false)

	# Update Player
	update_player_entity(delta)

	# Update Monsters
	update_monster_entities(delta)

	# Update Camera Smooth Follow
	update_camera_tracking(delta)

	# Update Click Marker Fade
	if click_fade > 0.0:
		click_fade -= delta * 2.5
		if click_fade <= 0.0:
			click_marker.visible = false
		else:
			var mat = click_marker.material_override as StandardMaterial3D
			if mat:
				mat.albedo_color.a = click_fade

func rebuild_dungeon_if_needed(force: bool = false):
	if not diablo_bridge or not diablo_bridge.has_method("get_dungeon_solidity_grid"):
		return
	if diablo_bridge.has_method("is_level_loading") and diablo_bridge.is_level_loading():
		return

	var solidity: PackedByteArray = diablo_bridge.get_dungeon_solidity_grid()
	if solidity.size() < 112 * 112:
		return

	var h = hash(solidity)
	if not force and dungeon_built and h == last_solidity_hash:
		return

	last_solidity_hash = h
	dungeon_built = true

	# Count instances
	var floor_count = 0
	var wall_count = 0
	var door_count = 0

	for i in range(112 * 112):
		var val = solidity[i]
		if val == 1:
			floor_count += 1
		elif val == 2:
			wall_count += 1
			floor_count += 1
		elif val == 3:
			door_count += 1
			floor_count += 1

	var floor_mm = floor_mmi.multimesh
	var wall_mm = wall_mmi.multimesh
	var door_mm = door_mmi.multimesh

	floor_mm.instance_count = floor_count
	wall_mm.instance_count = wall_count
	door_mm.instance_count = door_count

	var f_idx = 0
	var w_idx = 0
	var d_idx = 0

	var basis_45 = Basis().rotated(Vector3.UP, deg_to_rad(45.0))

	for y in range(112):
		for x in range(112):
			var val = solidity[y * 112 + x]
			if val == 0:
				continue

			var wpos = tile_to_world_3d(float(x), float(y))

			# Floor
			var f_tf = Transform3D(basis_45, Vector3(wpos.x, -0.05, wpos.z))
			floor_mm.set_instance_transform(f_idx, f_tf)
			f_idx += 1

			if val == 2:
				# Wall
				var w_tf = Transform3D(basis_45, Vector3(wpos.x, 1.1, wpos.z))
				wall_mm.set_instance_transform(w_idx, w_tf)
				w_idx += 1
			elif val == 3:
				# Door / Arch
				var d_tf = Transform3D(basis_45, Vector3(wpos.x, 1.0, wpos.z))
				door_mm.set_instance_transform(d_idx, d_tf)
				d_idx += 1

	print("[Native 3D Sandbox] Rebuilt 3D dungeon: %d floors, %d walls, %d doors" % [floor_count, wall_count, door_count])

func update_player_entity(delta: float):
	var p_data = diablo_bridge.get_player_continuous_pos()
	var px = p_data.get("pos_x", 25.0)
	var py = p_data.get("pos_y", 25.0)
	var dir = p_data.get("dir", 0)
	var anim_frame = p_data.get("anim_frame", -1)

	player_target_pos = tile_to_world_3d(px, py)
	player_root.position = player_root.position.lerp(player_target_pos, delta * 14.0)

	# Rotation of direction indicator arrow
	var target_rot_y = float(dir) * 45.0
	player_arrow.rotation_degrees.y = float(dir) * 45.0

	# Fetch & update authentic animated player 3D billboard sprite
	if diablo_bridge and diablo_bridge.has_method("get_player_sprite_data"):
		if anim_frame != last_player_frame or dir != last_player_dir or player_texture == null:
			last_player_frame = anim_frame
			last_player_dir = dir
			var s_data: Dictionary = diablo_bridge.get_player_sprite_data()
			var sw = s_data.get("width", 0)
			var sh = s_data.get("height", 0)
			var rgba: PackedByteArray = s_data.get("rgba", PackedByteArray())
			if sw > 0 and sh > 0 and rgba.size() == sw * sh * 4:
				var img = Image.create_from_data(sw, sh, false, Image.FORMAT_RGBA8, rgba)
				if player_texture == null or player_texture.get_width() != sw or player_texture.get_height() != sh:
					player_texture = ImageTexture.create_from_image(img)
					player_sprite.texture = player_texture
				else:
					player_texture.update(img)
				player_sprite.offset = Vector2(0, float(sh) * 0.5)

	# Lantern flicker
	if player_lantern:
		var flicker = 1.35 + 0.12 * sin(time_accum * 6.5) * cos(time_accum * 3.3)
		player_lantern.light_energy = flicker

	# Rune Ring pulse
	if player_ring:
		player_ring.rotation_degrees.y += delta * 30.0

func update_monster_entities(delta: float):
	if not diablo_bridge or not diablo_bridge.has_method("get_active_monsters_data"):
		return

	var monsters: Array = diablo_bridge.get_active_monsters_data()
	var seen_ids: Dictionary = {}

	for m in monsters:
		var m_id = m.get("id", -1)
		var is_alive = m.get("is_alive", true)
		if m_id < 0 or not is_alive:
			continue

		seen_ids[m_id] = true
		var node = get_or_create_monster_node(m_id)
		node.visible = true

		var mx = m.get("pos_x", 0.0)
		var my = m.get("pos_y", 0.0)
		var dir = m.get("dir", 0)
		var anim_frame = m.get("anim_frame", -1)
		var hp = m.get("hp", 1)
		var max_hp = max(1, m.get("max_hp", 1))
		var m_name = m.get("name", "Monster")

		var target_pos = tile_to_world_3d(mx, my)
		node.position = node.position.lerp(target_pos, delta * 12.0)

		# Update animated monster 3D billboard sprite
		var m_sprite = node.get_node_or_null("MonsterSprite3D") as Sprite3D
		var last_f = monster_last_frame.get(m_id, -999)
		var last_d = monster_last_dir.get(m_id, -999)
		var cur_tex: ImageTexture = monster_textures.get(m_id, null)

		if diablo_bridge and diablo_bridge.has_method("get_monster_sprite_data"):
			if anim_frame != last_f or dir != last_d or cur_tex == null:
				monster_last_frame[m_id] = anim_frame
				monster_last_dir[m_id] = dir
				var ms_data: Dictionary = diablo_bridge.get_monster_sprite_data(m_id)
				var mw = ms_data.get("width", 0)
				var mh = ms_data.get("height", 0)
				var m_rgba: PackedByteArray = ms_data.get("rgba", PackedByteArray())
				if mw > 0 and mh > 0 and m_rgba.size() == mw * mh * 4:
					var m_img = Image.create_from_data(mw, mh, false, Image.FORMAT_RGBA8, m_rgba)
					if cur_tex == null or cur_tex.get_width() != mw or cur_tex.get_height() != mh:
						cur_tex = ImageTexture.create_from_image(m_img)
						monster_textures[m_id] = cur_tex
						if m_sprite:
							m_sprite.texture = cur_tex
					else:
						cur_tex.update(m_img)
					if m_sprite:
						m_sprite.offset = Vector2(0, float(mh) * 0.5)

					# Dynamically adjust HP bar and name height to sit above monster head
					var hp_y = float(mh) * 0.016 + 0.15
					var name_y = hp_y + 0.22
					var hp_r = node.get_node_or_null("HPRoot")
					if hp_r:
						hp_r.position.y = hp_y
					var n_lbl = node.get_node_or_null("NameLabel")
					if n_lbl:
						n_lbl.position.y = name_y

		# Update HP Bar
		var hp_bar = node.get_node_or_null("HPRoot/HPBar") as MeshInstance3D
		if hp_bar:
			var ratio = clamp(float(hp) / float(max_hp), 0.0, 1.0)
			hp_bar.scale.x = max(0.01, ratio)
			var fg_mat = hp_bar.material_override as StandardMaterial3D
			if fg_mat:
				# Green -> Yellow -> Red gradient
				if ratio > 0.5:
					fg_mat.albedo_color = Color(0.2, 0.85, 0.25).lerp(Color(0.9, 0.8, 0.1), (1.0 - ratio) * 2.0)
				else:
					fg_mat.albedo_color = Color(0.9, 0.8, 0.1).lerp(Color(0.9, 0.15, 0.15), (0.5 - ratio) * 2.0)

		# Update Label
		var label = node.get_node_or_null("NameLabel") as Label3D
		if label:
			label.text = "%s [%d/%d]" % [m_name, hp, max_hp]

	# Hide / clean up monsters not present in active list
	for id in monster_instances.keys():
		if not seen_ids.has(id):
			monster_instances[id].visible = false

func get_or_create_monster_node(m_id: int) -> Node3D:
	if monster_instances.has(m_id):
		return monster_instances[m_id]

	var node = Node3D.new()
	node.name = "Monster_%d" % m_id

	# 3D Billboard Sprite for Monster
	var sprite = Sprite3D.new()
	sprite.name = "MonsterSprite3D"
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.shaded = true
	sprite.pixel_size = 0.016
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	node.add_child(sprite)

	# Name Label3D
	var label = Label3D.new()
	label.name = "NameLabel"
	label.position = Vector3(0, 1.85, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 17
	label.modulate = Color(1.0, 0.90, 0.55)
	label.outline_render_priority = 1
	label.outline_size = 4
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
	node.add_child(label)

	# 3D HP Bar
	var hp_root = Node3D.new()
	hp_root.name = "HPRoot"
	hp_root.position = Vector3(0, 1.60, 0)

	var hp_bg = MeshInstance3D.new()
	var q_bg = QuadMesh.new()
	q_bg.size = Vector2(0.82, 0.08)
	hp_bg.mesh = q_bg
	var bg_mat = StandardMaterial3D.new()
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.albedo_color = Color(0.08, 0.08, 0.08, 0.85)
	bg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bg_mat.no_depth_test = true
	hp_bg.material_override = bg_mat
	hp_root.add_child(hp_bg)

	var hp_fg = MeshInstance3D.new()
	var q_fg = QuadMesh.new()
	q_fg.size = Vector2(0.80, 0.06)
	hp_fg.mesh = q_fg
	hp_fg.name = "HPBar"
	var fg_mat = StandardMaterial3D.new()
	fg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fg_mat.albedo_color = Color(0.85, 0.15, 0.15, 0.95)
	fg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fg_mat.no_depth_test = true
	hp_fg.material_override = fg_mat
	hp_root.add_child(hp_fg)

	node.add_child(hp_root)
	monsters_root.add_child(node)
	monster_instances[m_id] = node
	return node

func update_camera_tracking(delta: float):
	if not camera:
		return

	# Smooth exponential dampening towards player
	camera_target = camera_target.lerp(player_target_pos, delta * 7.5)
	update_camera_transform()

func update_camera_transform():
	if not camera:
		return

	var rot_yaw = Basis().rotated(Vector3.UP, deg_to_rad(camera_yaw))
	var rot_pitch = Basis().rotated(Vector3.RIGHT, deg_to_rad(-camera_pitch))
	var cam_rot = rot_yaw * rot_pitch
	var cam_offset = cam_rot * Vector3(0, 0, camera_distance)

	camera.position = camera_target + cam_offset
	camera.look_at(camera_target + Vector3(0, 0.75, 0), Vector3.UP)

# --- 3D Input & Navigation Handling ---
func handle_input(event: InputEvent) -> bool:
	if not is_sandbox_active:
		return false

	# If the game is not actively in a dungeon/game session (e.g. main menu, hero select, character create),
	# do NOT intercept input with 3D raycasting! Pass through to classic UI!
	if diablo_bridge and diablo_bridge.has_method("is_game_running") and not diablo_bridge.is_game_running():
		return false

	# When a modal menu, store, or dialog is active, pass input through to screen-space UI
	if diablo_bridge and diablo_bridge.has_method("is_modal_active") and diablo_bridge.is_modal_active():
		return false

	# Camera Tilt / Pitch Controls (PageUp / PageDown)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_PAGEUP:
			camera_pitch = clamp(camera_pitch + 5.0, 25.0, 75.0)
			if main_receiver:
				main_receiver.show_osd("[3D Camera] Tilt/Pitch: %.0f°" % camera_pitch, 1.2)
			return true
		elif event.keycode == KEY_PAGEDOWN:
			camera_pitch = clamp(camera_pitch - 5.0, 25.0, 75.0)
			if main_receiver:
				main_receiver.show_osd("[3D Camera] Tilt/Pitch: %.0f°" % camera_pitch, 1.2)
			return true
		elif event.keycode == KEY_Q:
			camera_yaw = fposmod(camera_yaw - 15.0, 360.0)
			if main_receiver:
				main_receiver.show_osd("[3D Camera] Yaw Rotate Left: %.0f°" % camera_yaw, 1.2)
			return true
		elif event.keycode == KEY_E:
			camera_yaw = fposmod(camera_yaw + 15.0, 360.0)
			if main_receiver:
				main_receiver.show_osd("[3D Camera] Yaw Rotate Right: %.0f°" % camera_yaw, 1.2)
			return true
		elif event.keycode == KEY_HOME or event.keycode == KEY_R:
			camera_pitch = 50.0
			camera_yaw = 0.0
			camera_distance = 13.0
			if main_receiver:
				main_receiver.show_osd("[3D Camera] Reset to Default (50° Pitch, 0° Yaw)", 1.2)
			return true

	# Mouse Orbit (Middle Click Drag)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			is_orbiting = event.pressed
			last_mouse_pos = event.position
			return true
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera_distance = clamp(camera_distance - 1.0, 6.0, 22.0)
			if main_receiver:
				main_receiver.show_osd("[3D Camera] Distance: %.1fm" % camera_distance, 1.0)
			return true
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera_distance = clamp(camera_distance + 1.0, 6.0, 22.0)
			if main_receiver:
				main_receiver.show_osd("[3D Camera] Distance: %.1fm" % camera_distance, 1.0)
			return true

	if event is InputEventMouseMotion and is_orbiting:
		var delta_pos = event.position - last_mouse_pos
		last_mouse_pos = event.position
		camera_yaw = fposmod(camera_yaw - delta_pos.x * 0.4, 360.0)
		camera_pitch = clamp(camera_pitch + delta_pos.y * 0.3, 25.0, 75.0)
		return true

	# 3D Click-to-Move Raycast Navigation
	if event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
		var mouse_pos = event.position
		var ray_origin = camera.project_ray_origin(mouse_pos)
		var ray_dir = camera.project_ray_normal(mouse_pos)
		var ground_plane = Plane(Vector3.UP, 0.0)
		var hit = ground_plane.intersects_ray(ray_origin, ray_dir)

		if hit != null:
			var target_tile = world_3d_to_tile(hit)
			var target_tx = clamp(int(round(target_tile.x)), 0, 111)
			var target_ty = clamp(int(round(target_tile.y)), 0, 111)

			# Spawn glowing 3D click feedback ring
			if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				click_marker.position = Vector3(hit.x, 0.04, hit.z)
				click_marker.visible = true
				click_fade = 0.85
				var mat = click_marker.material_override as StandardMaterial3D
				if mat:
					mat.albedo_color.a = click_fade

			# Route click to Diablo engine via screen offset relative to player
			if diablo_bridge:
				var p_data = diablo_bridge.get_player_continuous_pos()
				var p_tx = p_data.get("tile_x", 25)
				var p_ty = p_data.get("tile_y", 25)

				var dtx = target_tx - p_tx
				var dty = target_ty - p_ty

				# Diablo screen projection conversion
				var screen_dx = (dtx - dty) * 32.0
				var screen_dy = (dtx + dty) * 16.0

				var d1_w = diablo_bridge.get_frame_width() if diablo_bridge.has_method("get_frame_width") else 2560
				var d1_h = diablo_bridge.get_frame_height() if diablo_bridge.has_method("get_frame_height") else 1440

				var screen_x = int(d1_w * 0.5 + screen_dx)
				var screen_y = int(d1_h * 0.5 + screen_dy)

				var btn = 1 if event.button_index == MOUSE_BUTTON_LEFT else 3
				var state = 1 if event.pressed else 0
				diablo_bridge.send_input(2, btn, state, screen_x, screen_y)
				return true

	return false
