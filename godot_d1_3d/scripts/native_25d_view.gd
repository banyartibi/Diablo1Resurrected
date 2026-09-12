extends Node2D

# Native Godot 2.5D View
# Directly renders authentic Diablo 1 level pieces, characters, and monsters
# with 144Hz smooth camera, Godot 2D Y-sorting, and dynamic PointLight2D lighting.

var diablo_bridge = null
var is_active: bool = false

# Nodes
var camera: Camera2D = null
var world_root: Node2D = null
var player_node: Node2D = null
var player_sprite: Sprite2D = null
var player_light: PointLight2D = null
var player_shadow: Sprite2D = null
var shadow_texture: ImageTexture = null
var canvas_modulate: CanvasModulate = null
var shared_radial_light_texture: GradientTexture2D = null

# State tracking
var last_level_idx: int = -999
var pending_dungeon_rebuild: bool = false
var last_gamma_value: int = -1  # bridge gamma; on change -> invalidate all palette-baked textures
var tile_sprites: Dictionary = {} # Vector2i -> Sprite2D
var special_sprites: Dictionary = {} # Vector2i -> Sprite2D (Arches, Doorways, Column Tops)
var last_visible_tiles: Dictionary = {} # Vector2i -> bool (track visible tiles for efficient culling)
var last_player_frame: int = -999
var last_player_dir: int = -999
var player_texture: ImageTexture = null

# Monster tracking
var monster_nodes: Dictionary = {} # int -> Node2D
var monster_textures: Dictionary = {} # int -> ImageTexture
var monster_last_frame: Dictionary = {}
var monster_last_dir: Dictionary = {}

# Milestone 4: Dungeon Objects (Torches, Barrels, Chests, Shrines)
var object_sprites: Dictionary = {} # int (id) -> Sprite2D
var object_textures: Dictionary = {} # String ("type_frame") -> ImageTexture

# Milestone 4: Dropped Items (Loot with name labels)
var item_nodes: Dictionary = {} # int (id) -> Node2D
var item_textures: Dictionary = {} # int (id) -> ImageTexture

# Milestone 4: Corpses (Fallen monsters & skeletons)
var corpse_sprites: Dictionary = {} # Vector2i -> Sprite2D
var corpse_textures: Dictionary = {} # String ("corpseIdx_dir") -> ImageTexture

# Missiles & Spell Projectiles
var missile_nodes: Dictionary = {} # int (id) -> Node2D
var missile_textures: Dictionary = {} # String ("type_frame") -> ImageTexture
var last_player_mode: int = -999

# Torch light pool
var torch_lights: Array = []

# Realistic 2.5D Shadows & Lighting
var realistic_shadow_shader = preload("res://shaders/realistic_25d_shadow.gdshader")
var player_shadow_material: ShaderMaterial = null
var current_player_shadow_skew: Vector2 = Vector2(0.28, 0.42)
var current_player_shadow_length: float = 0.9
var current_player_shadow_opacity: float = 0.52
# Toggle for static wall occluders (false: prevents 2D shadow rays from projecting black cuts onto floor)
var enable_wall_occluders: bool = false
var pbr_texture_cache: Dictionary = {} # piece_id -> CanvasTexture
var pbr_special_cache: Dictionary = {} # special_id -> CanvasTexture
var pbr_occluders_cache: Dictionary = {} # String -> Dictionary (points, type)
var tile_occluders: Dictionary = {} # Vector2i -> LightOccluder2D
var monster_shadow_materials: Dictionary = {} # int -> ShaderMaterial

# Continuous 2.5D GPU Isometric Lightmap & Shared Tile PBR Material
var d2r_pbr_shader = preload("res://shaders/d2r_25d_pbr.gdshader")
var dungeon_tile_material: ShaderMaterial = null
var light_image: Image = null
var light_map_texture: ImageTexture = null

# Smooth Camera & Movement
var player_target_pos: Vector2 = Vector2.ZERO
var time_accum: float = 0.0

# Zoom Steps
var zoom_levels = [0.75, 1.0, 1.25, 1.5, 2.0, 2.5]
var current_zoom_idx: int = 3 # Default: 1.5x

# D1 Resolution (for input mapping)
var d1_width: int = 2560
var d1_height: int = 1440

func _ready():
	visible = false
	set_process(false)
	setup_scene_hierarchy()

func setup_scene_hierarchy():
	# 2D World Root with Y-sorting and pixel-perfect nearest-neighbor filtering
	world_root = Node2D.new()
	world_root.name = "WorldRoot"
	world_root.y_sort_enabled = true
	world_root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(world_root)
	load_pbr_occluders()

	# Atmospheric Gothic Crypt Canvas Modulate (Pure 1.0 ambient so dLight controls contrast cleanly)
	canvas_modulate = CanvasModulate.new()
	canvas_modulate.name = "CryptModulate"
	canvas_modulate.color = Color(1.0, 1.0, 1.0)
	add_child(canvas_modulate)

	# Continuous GPU Isometric Lightmap & Shared Tile PBR Material
	light_image = Image.create(112, 112, false, Image.FORMAT_R8)
	light_image.fill(Color(0, 0, 0, 1))
	light_map_texture = ImageTexture.create_from_image(light_image)
	dungeon_tile_material = ShaderMaterial.new()
	dungeon_tile_material.shader = d2r_pbr_shader
	dungeon_tile_material.set_shader_parameter("light_map", light_map_texture)
	dungeon_tile_material.set_shader_parameter("is_town", false)

	# Smooth 144Hz Camera2D
	camera = Camera2D.new()
	camera.name = "Camera2D"
	camera.position_smoothing_enabled = false
	var z = zoom_levels[current_zoom_idx]
	camera.zoom = Vector2(z, z)
	add_child(camera)

	# Player Entity (participates in Y-sorting under world_root)
	setup_player_node()

func get_or_create_shadow_texture() -> ImageTexture:
	if shadow_texture != null:
		return shadow_texture
	var sw = 36
	var sh = 18
	var img = Image.create(sw, sh, false, Image.FORMAT_RGBA8)
	var cx = float(sw) * 0.5
	var cy = float(sh) * 0.5
	var rx = cx - 1.0
	var ry = cy - 1.0
	for y in range(sh):
		for x in range(sw):
			var nx = (float(x) + 0.5 - cx) / rx
			var ny = (float(y) + 0.5 - cy) / ry
			var dist_sq = nx * nx + ny * ny
			if dist_sq < 1.0:
				var alpha = clampf((1.0 - sqrt(dist_sq)) * 1.5, 0.0, 1.0)
				img.set_pixel(x, y, Color(0.0, 0.0, 0.0, alpha * 0.55))
			else:
				img.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
	shadow_texture = ImageTexture.create_from_image(img)
	return shadow_texture

func setup_player_node():
	player_node = Node2D.new()
	player_node.name = "PlayerEntity"
	player_node.z_index = 0
	world_root.add_child(player_node)

	# Realistic 2.5D Directional Silhouette Shadow
	player_shadow_material = ShaderMaterial.new()
	player_shadow_material.shader = realistic_shadow_shader
	player_shadow_material.set_shader_parameter("shadow_skew", current_player_shadow_skew * current_player_shadow_length)
	player_shadow_material.set_shader_parameter("shadow_color", Color(0.0, 0.0, 0.0, current_player_shadow_opacity))
	player_shadow_material.set_shader_parameter("shadow_blur", 2.0)
	player_shadow_material.set_shader_parameter("contact_fade", 0.35)

	player_shadow = Sprite2D.new()
	player_shadow.name = "PlayerShadow"
	player_shadow.material = player_shadow_material
	player_shadow.centered = true
	player_shadow.position = Vector2.ZERO
	player_shadow.z_index = -1
	player_shadow.visible = false
	player_node.add_child(player_shadow)

	# Hero Sprite2D (authentic animated Diablo 1 pixel art)
	player_sprite = Sprite2D.new()
	player_sprite.name = "PlayerSprite"
	player_sprite.centered = true
	player_node.add_child(player_sprite)

	# Hero Torch Light with PCF13 Soft Penumbra Shadows
	shared_radial_light_texture = create_radial_light_texture(512)
	player_light = PointLight2D.new()
	player_light.name = "HeroTorchLight"
	player_light.texture = shared_radial_light_texture
	player_light.texture_scale = 2.4
	player_light.color = Color(1.0, 0.90, 0.78)
	player_light.energy = 0.35
	player_light.enabled = true
	player_light.position = Vector2(0, -16)
	player_light.shadow_enabled = enable_wall_occluders
	player_light.shadow_filter = Light2D.SHADOW_FILTER_PCF13
	player_light.shadow_filter_smooth = 4.5
	player_light.shadow_color = Color(0.0, 0.0, 0.0, 0.38)
	player_node.add_child(player_light)

func create_radial_light_texture(size: int) -> GradientTexture2D:
	var grad = Gradient.new()
	grad.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex = GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.96, 0.5)
	tex.width = size
	tex.height = size
	return tex

func activate():
	is_active = true
	visible = true
	set_process(true)
	if camera:
		camera.make_current()
	if tile_sprites.is_empty():
		pending_dungeon_rebuild = true
	print("[Native 2.5D View] Activated (144Hz Smooth Camera, Y-Sorted Sprites, PointLight2D)")

func deactivate():
	is_active = false
	visible = false
	set_process(false)
	print("[Native 2.5D View] Deactivated")

func _process(delta: float):
	if not is_active or diablo_bridge == null:
		return

	# Check level change
	if diablo_bridge.has_method("get_current_level"):
		var cur_lvl = diablo_bridge.get_current_level()
		if cur_lvl != last_level_idx:
			last_level_idx = cur_lvl
			pending_dungeon_rebuild = true

	# Gamma changed (options slider) -> palette-baked textures are stale. Invalidate all of them so the
	# whole scene re-renders with the new palette, matching legacy behaviour where gamma affects the entire
	# image. We poll the gamma VALUE (not the raw palette version), because that counter also ticks every frame
	# for animated lava/glow in cave/crypt levels and would force a full rebuild per frame there.
	if diablo_bridge.has_method("get_gamma"):
		var cur_gamma = diablo_bridge.get_gamma()
		if cur_gamma != last_gamma_value:
			last_gamma_value = cur_gamma
			pending_dungeon_rebuild = true
			player_texture = null
			last_player_frame = -999
			last_player_dir = -999
			last_player_mode = -999
			monster_textures.clear()
			monster_last_frame.clear()
			monster_last_dir.clear()
			object_textures.clear()
			item_textures.clear()
			corpse_textures.clear()
			missile_textures.clear()

	if tile_sprites.is_empty():
		pending_dungeon_rebuild = true

	# During level transitions, DevilutionX is tearing down and rebuilding memory.
	# Freeze rendering updates until the new level is 100% ready to eliminate race conditions.
	if diablo_bridge.has_method("is_level_loading") and diablo_bridge.is_level_loading():
		return

	if pending_dungeon_rebuild:
		var grid = diablo_bridge.get_dungeon_grid() if diablo_bridge.has_method("get_dungeon_grid") else PackedInt32Array()
		if grid.size() >= 112 * 112:
			var can_fetch = false
			for piece_id in grid:
				if piece_id >= 0:
					var test_tex = diablo_bridge.get_dungeon_piece_texture(piece_id)
					if test_tex != null:
						can_fetch = true
						break
			if can_fetch:
				if diablo_bridge.has_method("clear_dungeon_piece_cache"):
					diablo_bridge.clear_dungeon_piece_cache()
				rebuild_dungeon_tiles()
				pending_dungeon_rebuild = false

	time_accum += delta

	update_player(delta)
	update_monsters(delta)
	update_torches()
	update_objects()
	update_corpses()
	update_ground_items()
	update_missiles()
	update_lighting_and_transparency()

# --- PBR Asset & Linear Wall Occluder Pipeline ---

func load_pbr_occluders():
	var occ_file = "res://assets/dungeon_pbr/occluders.json"
	if FileAccess.file_exists(occ_file):
		var f = FileAccess.open(occ_file, FileAccess.READ)
		if f:
			var json_text = f.get_as_text()
			f.close()
			var json = JSON.new()
			if json.parse(json_text) == OK and typeof(json.data) == TYPE_DICTIONARY:
				pbr_occluders_cache = json.data
				print("[Native 2.5D View] Loaded %d PBR linear wall occluders" % pbr_occluders_cache.size())

func get_pbr_or_base_texture(piece_id: int) -> Texture2D:
	if pbr_texture_cache.has(piece_id):
		return pbr_texture_cache[piece_id]

	var alb_path = "res://assets/dungeon_pbr/albedo/piece_%d.png" % piece_id
	var norm_path = "res://assets/dungeon_pbr/normal/piece_%d_n.png" % piece_id
	var spec_path = "res://assets/dungeon_pbr/specular/piece_%d_s.png" % piece_id

	if FileAccess.file_exists(alb_path) and FileAccess.file_exists(norm_path):
		var alb_img = Image.load_from_file(ProjectSettings.globalize_path(alb_path))
		var norm_img = Image.load_from_file(ProjectSettings.globalize_path(norm_path))
		if alb_img and not alb_img.is_empty() and norm_img and not norm_img.is_empty():
			var ct = CanvasTexture.new()
			ct.diffuse_texture = ImageTexture.create_from_image(alb_img)
			ct.normal_texture = ImageTexture.create_from_image(norm_img)
			if FileAccess.file_exists(spec_path):
				var spec_img = Image.load_from_file(ProjectSettings.globalize_path(spec_path))
				if spec_img and not spec_img.is_empty():
					ct.specular_texture = ImageTexture.create_from_image(spec_img)
					ct.specular_shininess = 0.35
					ct.specular_color = Color(0.75, 0.65, 0.50)
			ct.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			pbr_texture_cache[piece_id] = ct
			return ct

	# Fallback to vanilla engine texture
	if diablo_bridge and diablo_bridge.has_method("get_dungeon_piece_texture"):
		var base_tex = diablo_bridge.get_dungeon_piece_texture(piece_id)
		if base_tex == null and last_level_idx == 0 and piece_id == 0:
			base_tex = diablo_bridge.get_dungeon_piece_texture(426)
		return base_tex
	return null

func get_pbr_or_base_special_texture(special_id: int) -> Texture2D:
	if pbr_special_cache.has(special_id):
		return pbr_special_cache[special_id]

	var alb_path = "res://assets/dungeon_pbr/albedo/special_%d.png" % special_id
	var norm_path = "res://assets/dungeon_pbr/normal/special_%d_n.png" % special_id
	var spec_path = "res://assets/dungeon_pbr/specular/special_%d_s.png" % special_id

	if FileAccess.file_exists(alb_path) and FileAccess.file_exists(norm_path):
		var alb_img = Image.load_from_file(ProjectSettings.globalize_path(alb_path))
		var norm_img = Image.load_from_file(ProjectSettings.globalize_path(norm_path))
		if alb_img and not alb_img.is_empty() and norm_img and not norm_img.is_empty():
			var ct = CanvasTexture.new()
			ct.diffuse_texture = ImageTexture.create_from_image(alb_img)
			ct.normal_texture = ImageTexture.create_from_image(norm_img)
			if FileAccess.file_exists(spec_path):
				var spec_img = Image.load_from_file(ProjectSettings.globalize_path(spec_path))
				if spec_img and not spec_img.is_empty():
					ct.specular_texture = ImageTexture.create_from_image(spec_img)
					ct.specular_shininess = 0.35
					ct.specular_color = Color(0.75, 0.65, 0.50)
			ct.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			pbr_special_cache[special_id] = ct
			return ct

	if diablo_bridge and diablo_bridge.has_method("get_special_cel_texture"):
		return diablo_bridge.get_special_cel_texture(special_id)
	return null

func ensure_pbr_assets_for_level(grid: PackedInt32Array, special_grid: PackedInt32Array):
	var missing_count = 0
	var raw_dir = "res://assets/dungeon_pbr/raw"
	var alb_dir = "res://assets/dungeon_pbr/albedo"

	var needed_pieces: Dictionary = {}
	for idx in range(grid.size()):
		var pid = grid[idx]
		if pid >= 0:
			needed_pieces[pid] = true

	for pid in needed_pieces.keys():
		var alb_file = "%s/piece_%d.png" % [alb_dir, pid]
		if not FileAccess.file_exists(alb_file):
			var raw_file = "%s/piece_%d.png" % [raw_dir, pid]
			if not FileAccess.file_exists(raw_file):
				if diablo_bridge and diablo_bridge.has_method("get_dungeon_piece_texture"):
					var rtex = diablo_bridge.get_dungeon_piece_texture(pid)
					if rtex:
						var rimg = rtex.get_image()
						if rimg and not rimg.is_empty():
							rimg.save_png(ProjectSettings.globalize_path(raw_file))
							missing_count += 1

	for idx in range(special_grid.size()):
		var sid = special_grid[idx]
		if sid > 0:
			var alb_file = "%s/special_%d.png" % [alb_dir, sid]
			if not FileAccess.file_exists(alb_file):
				var raw_file = "%s/special_%d.png" % [raw_dir, sid]
				if not FileAccess.file_exists(raw_file):
					if diablo_bridge and diablo_bridge.has_method("get_special_cel_texture"):
						var stex = diablo_bridge.get_special_cel_texture(sid)
						if stex:
							var simg = stex.get_image()
							if simg and not simg.is_empty():
								simg.save_png(ProjectSettings.globalize_path(raw_file))
								missing_count += 1

	if missing_count > 0:
		print("[Native 2.5D View] Exported %d new raw dungeon tiles. Running PBR pipeline..." % missing_count)
		var output = []
		var py_path = ProjectSettings.globalize_path("res://../tools/generate_pbr_maps.py")
		var raw_global = ProjectSettings.globalize_path(raw_dir)
		var out_global = ProjectSettings.globalize_path("res://assets/dungeon_pbr")
		var exit_code = OS.execute("python3", [py_path, "--raw-dir", raw_global, "--out-dir", out_global], output, true)
		print("[Native 2.5D View] PBR pipeline completed with code %d" % exit_code)
		load_pbr_occluders()

func rebuild_dungeon_tiles():
	if not diablo_bridge or not diablo_bridge.has_method("get_dungeon_grid"):
		return

	var grid = diablo_bridge.get_dungeon_grid()
	if grid.size() < 112 * 112:
		return

	# Clear previous tile sprites
	for pos_key in tile_sprites:
		var spr = tile_sprites[pos_key]
		if is_instance_valid(spr):
			spr.queue_free()
	tile_sprites.clear()
	last_visible_tiles.clear()
	pbr_texture_cache.clear()
	pbr_special_cache.clear()

	# Clear previous tile occluders
	for occ in tile_occluders.values():
		if is_instance_valid(occ):
			occ.queue_free()
	tile_occluders.clear()

	# Clear previous special cel sprites (arches / column tops)
	for pos_key in special_sprites:
		var spr = special_sprites[pos_key]
		if is_instance_valid(spr):
			spr.queue_free()
	special_sprites.clear()

	# Clear previous objects
	for o_id in object_sprites:
		var spr = object_sprites[o_id]
		if is_instance_valid(spr):
			spr.queue_free()
	object_sprites.clear()
	object_textures.clear()

	# Clear previous ground items
	for i_id in item_nodes:
		var node = item_nodes[i_id]
		if is_instance_valid(node):
			node.queue_free()
	item_nodes.clear()
	item_textures.clear()

	# Clear previous corpses
	for pos_key in corpse_sprites:
		var spr = corpse_sprites[pos_key]
		if is_instance_valid(spr):
			spr.queue_free()
	corpse_sprites.clear()
	corpse_textures.clear()

	# Clear previous missiles
	for m_id in missile_nodes:
		var node = missile_nodes[m_id]
		if is_instance_valid(node):
			node.queue_free()
	missile_nodes.clear()
	missile_textures.clear()

	# Clear previous monsters / NPCs
	for m_id in monster_nodes:
		var node = monster_nodes[m_id]
		if is_instance_valid(node):
			node.queue_free()
	monster_nodes.clear()
	monster_textures.clear()
	monster_last_frame.clear()
	monster_last_dir.clear()
	monster_shadow_materials.clear()

	player_texture = null
	last_player_frame = -999
	last_player_dir = -999
	last_player_mode = -999

	var special_grid = PackedInt32Array()
	if diablo_bridge.has_method("get_dungeon_special_grid"):
		special_grid = diablo_bridge.get_dungeon_special_grid()

	var solidity_grid = PackedByteArray()
	if diablo_bridge.has_method("get_dungeon_solidity_grid"):
		solidity_grid = diablo_bridge.get_dungeon_solidity_grid()

	ensure_pbr_assets_for_level(grid, special_grid)

	var count = 0
	var special_count = 0
	for y in range(112):
		for x in range(112):
			var idx = y * 112 + x
			var piece_id = grid[idx]
			var special_id = special_grid[idx] if idx < special_grid.size() else 0
			# Y-sort depth key = bottom vertex of the tile diamond (position.y), matching vanilla D1's
			# depth ordering: sprites are sorted by their feet position, tiles by their south point.
			var tile_pos = Vector2(float(x - y) * 32.0, float(x + y) * 16.0 + 16.0)

			# 1. Base Dungeon Piece (Floor & Walls) - PBR Normal Mapped & Delighted
			if piece_id >= 0:
				var tex: Texture2D = get_pbr_or_base_texture(piece_id)
				if tex != null:
					var spr = Sprite2D.new()
					spr.texture = tex
					spr.material = dungeon_tile_material
					spr.centered = false
					var h = tex.get_height()
					spr.position = tile_pos
					spr.offset = Vector2(-32.0, -float(h))
					# Initialize hidden in deep gothic darkness / fog of war
					spr.self_modulate = Color(1.0, 1.0, 1.0)
					spr.visible = false
					if h <= 32:
						spr.z_index = -2
					else:
						spr.z_index = 0
					world_root.add_child(spr)
					tile_sprites[Vector2i(x, y)] = spr
					count += 1

			# 2. Milestone 1: Special CELs (Archways, Column Tops, Doorways) - PBR
			if special_id > 0:
				var arch_tex: Texture2D = get_pbr_or_base_special_texture(special_id)
				if arch_tex != null:
					var arch_spr = Sprite2D.new()
					arch_spr.texture = arch_tex
					arch_spr.material = dungeon_tile_material
					arch_spr.centered = false
					var ah = arch_tex.get_height()
					arch_spr.position = tile_pos
					arch_spr.offset = Vector2(-32.0, -float(ah))
					# Initialize hidden in deep gothic darkness / fog of war
					arch_spr.self_modulate = Color(1.0, 1.0, 1.0)
					arch_spr.visible = false
					arch_spr.z_index = 0 # Y-sorted with walls!
					world_root.add_child(arch_spr)
					special_sprites[Vector2i(x, y)] = arch_spr
					special_count += 1

			# 3. Environment Wall & Pillar Linear Spine Occluders (PCF13)
			if enable_wall_occluders and idx < solidity_grid.size() and solidity_grid[idx] == 2:
				var occ_key = "piece_%d" % piece_id
				var occ_data = pbr_occluders_cache.get(occ_key, null)
				if occ_data and occ_data.get("type", "none") != "none":
					var pts = occ_data.get("points", [])
					if pts.size() >= 2:
						var occ = LightOccluder2D.new()
						var occ_poly = OccluderPolygon2D.new()
						var p_arr = PackedVector2Array()
						for pt in pts:
							p_arr.append(Vector2(float(pt[0]), float(pt[1])))
						occ_poly.polygon = p_arr
						occ_poly.cull_mode = OccluderPolygon2D.CULL_DISABLED
						occ.occluder = occ_poly
						occ.position = tile_pos
						occ.visible = false
						world_root.add_child(occ)
						tile_occluders[Vector2i(x, y)] = occ

	print("[Native 2.5D View] Rebuilt %d dungeon tiles and %d special archways/column tops" % [count, special_count])

func update_lighting_and_transparency():
	if not diablo_bridge:
		return

	var light_grid: PackedByteArray = PackedByteArray()
	if diablo_bridge.has_method("get_dungeon_light_grid"):
		light_grid = diablo_bridge.get_dungeon_light_grid()

	var trans_grid: PackedByteArray = PackedByteArray()
	if diablo_bridge.has_method("get_dungeon_trans_grid"):
		trans_grid = diablo_bridge.get_dungeon_trans_grid()

	var trans_mask: PackedByteArray = PackedByteArray()
	if diablo_bridge.has_method("get_dungeon_trans_mask"):
		trans_mask = diablo_bridge.get_dungeon_trans_mask()

	var trans_list: PackedByteArray = PackedByteArray()
	if diablo_bridge.has_method("get_trans_list"):
		trans_list = diablo_bridge.get_trans_list()

	var special_grid: PackedInt32Array = PackedInt32Array()
	if diablo_bridge.has_method("get_dungeon_special_grid"):
		special_grid = diablo_bridge.get_dungeon_special_grid()

	var has_light = (light_grid.size() >= 112 * 112)
	var has_trans = (trans_grid.size() >= 112 * 112 and trans_list.size() >= 256)
	var has_trans_mask = (trans_mask.size() >= 112 * 112)

	var p_pos = diablo_bridge.get_player_continuous_pos() if diablo_bridge.has_method("get_player_continuous_pos") else {}
	var p_tx = int(p_pos.get("pos_x", 25.0))
	var p_ty = int(p_pos.get("pos_y", 25.0))

	var z = camera.zoom.x if camera else 1.0
	var rad_x = int(clamp(60.0 / z, 44.0, 80.0))
	var rad_y = int(clamp(50.0 / z, 36.0, 70.0))
	var min_x = max(0, p_tx - rad_x)
	var max_x = min(111, p_tx + rad_x)
	var min_y = max(0, p_ty - rad_y)
	var max_y = min(111, p_ty + rad_y)

	var new_active_keys: Dictionary = {}

	var is_town = (last_level_idx == 0)
	if dungeon_tile_material:
		dungeon_tile_material.set_shader_parameter("is_town", is_town)

	# Milestone 2: Continuous GPU Bilinear Lightmap Update (0.01ms update, silky-smooth pixel lighting)
	if has_light and light_image and light_map_texture:
		var light_bytes = PackedByteArray()
		light_bytes.resize(112 * 112)
		for i in range(112 * 112):
			var l_val = light_grid[i]
			if l_val >= 15:
				light_bytes[i] = 0
			else:
				var factor = clampf((15.0 - float(l_val)) / 15.0, 0.0, 1.0)
				light_bytes[i] = int(factor * 255.0)
		light_image.set_data(112, 112, false, Image.FORMAT_R8, light_bytes)
		light_map_texture.update(light_image)

	for ty in range(min_y, max_y + 1):
		for tx in range(min_x, max_x + 1):
			var pos_key = Vector2i(tx, ty)
			var spr = tile_sprites.get(pos_key, null)
			var arch_spr = special_sprites.get(pos_key, null)
			if spr == null and arch_spr == null:
				continue

			var idx = ty * 112 + tx
			new_active_keys[pos_key] = true

			var raw_l = float(light_grid[idx]) if has_light else 0.0
			var min_front_l = 15.0
			if tx < 111: min_front_l = min(min_front_l, float(light_grid[idx + 1]))
			if ty < 111: min_front_l = min(min_front_l, float(light_grid[idx + 112]))

			# Milestone 3: Authentic Front-Wall Transparency (TransList + TileProperties::Transparent)
			# Only tiles that have the Diablo 1 Transparent flag (front walls/doors) become transparent!
			# Sarcophagi, statues, back walls, altars and floors (height <= 32) remain 100% solid!
			var alpha_val = 1.0
			if has_trans:
				var t_id = trans_grid[idx]
				if t_id > 0 and t_id < trans_list.size() and trans_list[t_id] == 1:
					alpha_val = 0.38 # Transparent front wall!

			var is_wall = (spr and spr.texture and spr.texture.get_height() > 32)
			var can_be_trans = has_trans_mask and (trans_mask[idx] == 1)
			var is_lit = (raw_l < 14.5 or min_front_l < 14.5 or is_town)

			if spr:
				spr.visible = true
				spr.self_modulate = Color(1.0, 1.0, 1.0)
				# Front walls only fade when in player vision/lit; in the dark, walls stay solid!
				if is_wall and can_be_trans and is_lit and alpha_val < 1.0:
					spr.modulate.a = alpha_val
				else:
					spr.modulate.a = 1.0

			if arch_spr:
				var sid = special_grid[idx] if idx < special_grid.size() else 0
				arch_spr.visible = true
				arch_spr.self_modulate = Color(1.0, 1.0, 1.0)
				var can_arch_be_trans = (has_trans_mask and trans_mask[idx] == 1) or (sid == 7 or sid == 8)
				if can_arch_be_trans and is_lit and alpha_val < 1.0:
					arch_spr.modulate.a = alpha_val
				else:
					arch_spr.modulate.a = 1.0

			if enable_wall_occluders:
				var occ = tile_occluders.get(pos_key, null)
				if occ:
					# Deactivate occluder when front wall is faded transparently so hero has no ghost shadow
					occ.visible = (alpha_val > 0.8)

	# Hide tiles that moved outside viewport or active range
	for prev_key in last_visible_tiles:
		if not new_active_keys.has(prev_key):
			var old_spr = tile_sprites.get(prev_key, null)
			if old_spr: old_spr.visible = false
			var old_arch = special_sprites.get(prev_key, null)
			if old_arch: old_arch.visible = false
			if enable_wall_occluders:
				var old_occ = tile_occluders.get(prev_key, null)
				if old_occ: old_occ.visible = false
	last_visible_tiles = new_active_keys

func calculate_shadow_skew_for_position(world_pos: Vector2) -> Dictionary:
	var result = {
		"skew": Vector2(0.24, 0.42),
		"length": 0.85,
		"opacity": 0.52
	}
	if not diablo_bridge or not diablo_bridge.has_method("get_active_lights"):
		return result

	var lights: Array = diablo_bridge.get_active_lights()
	var best_dist: float = 999999.0
	var best_light_pos: Vector2 = Vector2.ZERO
	var found_env_light: bool = false

	# Check active environmental and spell lights (torches, braziers, fireballs at index 1..N)
	for i in range(1, lights.size()):
		var l_info = lights[i]
		var tx = float(l_info.get("tile_x", 0))
		var ty = float(l_info.get("tile_y", 0))
		var lp = Vector2((tx - ty) * 32.0, (tx + ty) * 16.0 - 10.0)
		var d = world_pos.distance_to(lp)
		var rad_px = float(l_info.get("radius", 6)) * 42.0
		if d < rad_px and d < best_dist:
			best_dist = d
			best_light_pos = lp
			found_env_light = true

	if found_env_light:
		var delta = world_pos - best_light_pos
		var d = max(16.0, delta.length())
		var dir = delta / d
		# Shadow casts away from light
		# Horizontal skew up to +/- 0.85
		var sx = clampf(dir.x * 0.75, -0.85, 0.85)
		# Vertical skew compressed for 2:1 isometric ground plane
		var sy = clampf(dir.y * 0.45, -0.65, 0.65)
		# Prevent slit degeneration if light is exactly lateral
		if abs(sy) < 0.20:
			sy = 0.20 if sy >= 0.0 else -0.20

		var slen = clampf(0.65 + (d / 180.0) * 0.60, 0.60, 1.40)
		var sop = clampf(0.60 * (1.0 - (d / 380.0)), 0.25, 0.60)
		result["skew"] = Vector2(sx, sy)
		result["length"] = slen
		result["opacity"] = sop
	else:
		# Ambient / hero torch held in hand (slightly in front/right)
		result["skew"] = Vector2(0.24, 0.42)
		result["length"] = 0.85
		result["opacity"] = 0.50

	return result

func update_player(delta: float):
	if not diablo_bridge or not diablo_bridge.has_method("get_player_continuous_pos"):
		return

	var p_data = diablo_bridge.get_player_continuous_pos()
	var px = p_data.get("pos_x", 25.0)
	var py = p_data.get("pos_y", 25.0)
	var dir = p_data.get("dir", 0)
	var anim_frame = p_data.get("anim_frame", -1)
	var mode = p_data.get("mode", 0)

	# Target position in isometric coordinates
	# Y-sort depth key = hero's feet (position.y), matching vanilla D1's depth ordering:
	# the sprite is sorted by its feet position, not its origin.
	player_target_pos = Vector2(float(px - py) * 32.0, float(px + py) * 16.0 + 20.0)
	if player_node.position == Vector2.ZERO or player_node.position.distance_to(player_target_pos) > 200.0:
		player_node.position = player_target_pos
	else:
		player_node.position = player_node.position.lerp(player_target_pos, delta * 24.0)

	# Smooth camera follow with integer rounding to eliminate sub-pixel tile seams
	if camera:
		camera.position = camera.position.lerp(player_node.position, delta * 20.0).round()

	# Update animated player sprite (updates on frame, dir, or mode changes like attack/cast)
	if diablo_bridge.has_method("get_player_sprite_data"):
		if anim_frame != last_player_frame or dir != last_player_dir or mode != last_player_mode or player_texture == null:
			last_player_frame = anim_frame
			last_player_dir = dir
			last_player_mode = mode
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
				# Sprite center sits at position.y (feet); offset keeps visual position identical to before
				player_sprite.offset = Vector2(0, -float(sh) * 0.5)

	# Dynamic 2.5D Directional Silhouette Shadow & Torch Lighting
	if player_texture and player_shadow:
		player_shadow.texture = player_texture
		player_shadow.offset = player_sprite.offset
		player_shadow.visible = true

	var s_info = calculate_shadow_skew_for_position(player_node.position)
	current_player_shadow_skew = current_player_shadow_skew.lerp(s_info["skew"], delta * 12.0)
	current_player_shadow_length = lerpf(current_player_shadow_length, s_info["length"], delta * 12.0)
	current_player_shadow_opacity = lerpf(current_player_shadow_opacity, s_info["opacity"], delta * 12.0)

	if player_shadow_material:
		player_shadow_material.set_shader_parameter("shadow_skew", current_player_shadow_skew * current_player_shadow_length)
		player_shadow_material.set_shader_parameter("shadow_color", Color(0.0, 0.0, 0.0, current_player_shadow_opacity))

	if player_light and player_light.enabled:
		var p_flicker = 1.0 + 0.05 * sin(time_accum * 11.7) * cos(time_accum * 6.3)
		player_light.energy = 0.35 * p_flicker

	# Authentic per-tile lighting on player
	var p_light_grid = diablo_bridge.get_dungeon_light_grid() if diablo_bridge.has_method("get_dungeon_light_grid") else PackedByteArray()
	var p_tile_idx = clamp(int(py), 0, 111) * 112 + clamp(int(px), 0, 111)
	var is_town = (last_level_idx == 0)
	if is_town:
		var p_light = p_light_grid[p_tile_idx] if p_light_grid.size() >= 112 * 112 else 0
		var bright = clamp(1.0 - float(p_light) / 15.0, 0.0, 1.0)
		player_sprite.self_modulate = Color(0.55, 0.58, 0.65).lerp(Color(1.0, 1.0, 1.0), bright)
	elif p_light_grid.size() >= 112 * 112:
		var p_light = p_light_grid[p_tile_idx]
		var p_norm = clamp(1.0 - float(p_light) / 14.5, 0.0, 1.0)
		var p_bright = pow(p_norm, 1.8)
		player_sprite.self_modulate = Color(1.0, 0.96, 0.92) * max(0.12, p_bright)

func update_monsters(delta: float):
	if not diablo_bridge or not diablo_bridge.has_method("get_active_monsters_data"):
		return

	var monsters: Array = diablo_bridge.get_active_monsters_data()
	var seen_ids: Dictionary = {}

	for m in monsters:
		var m_id = m.get("id", -1)
		var is_alive = m.get("is_alive", true)
		var is_visible = m.get("is_visible", true)
		if m_id < 0 or not is_alive or not is_visible:
			if monster_nodes.has(m_id) and is_instance_valid(monster_nodes[m_id]):
				monster_nodes[m_id].visible = false
			continue

		seen_ids[m_id] = true
		var is_new = not monster_nodes.has(m_id)
		var node = get_or_create_monster_node(m_id)

		var mx = m.get("pos_x", 0.0)
		var my = m.get("pos_y", 0.0)
		var dir = m.get("dir", 0)
		var anim_frame = m.get("anim_frame", -1)

		# Y-sort depth key = monster's feet (position.y), matching vanilla D1's depth ordering
		var target_pos = Vector2(float(mx - my) * 32.0, float(mx + my) * 16.0 + 20.0)
		if is_new or node.position == Vector2.ZERO or node.position.distance_to(target_pos) > 200.0:
			node.position = target_pos
		else:
			node.position = node.position.lerp(target_pos, delta * 18.0)

		# Update monster sprite
		var m_sprite = node.get_node_or_null("Sprite") as Sprite2D
		var last_f = monster_last_frame.get(m_id, -999)
		var last_d = monster_last_dir.get(m_id, -999)
		var cur_tex: ImageTexture = monster_textures.get(m_id, null)

		if diablo_bridge.has_method("get_monster_sprite_data"):
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
						m_sprite.offset = Vector2(0, -float(mh) * 0.5)

		# Milestone 2: Per-Tile Authentic Lighting on Monsters, Ground Shadows & Fog of War
		var light_grid = diablo_bridge.get_dungeon_light_grid() if diablo_bridge.has_method("get_dungeon_light_grid") else PackedByteArray()
		var m_tx = clamp(int(mx), 0, 111)
		var m_ty = clamp(int(my), 0, 111)
		var m_idx = m_ty * 112 + m_tx
		var is_town = (last_level_idx == 0)
		var m_shadow = node.get_node_or_null("Shadow") as Sprite2D
		if m_shadow and cur_tex:
			m_shadow.texture = cur_tex
			if m_sprite:
				m_shadow.offset = m_sprite.offset
			m_shadow.position = Vector2.ZERO
			m_shadow.z_index = -1
			m_shadow.visible = node.visible

			var m_mat: ShaderMaterial = monster_shadow_materials.get(m_id, null)
			if m_mat == null:
				m_mat = ShaderMaterial.new()
				m_mat.shader = realistic_shadow_shader
				m_mat.set_shader_parameter("shadow_blur", 2.0)
				m_mat.set_shader_parameter("contact_fade", 0.35)
				monster_shadow_materials[m_id] = m_mat
				m_shadow.material = m_mat

			var ms_info = calculate_shadow_skew_for_position(node.position)
			var m_bright = 1.0
			if not is_town and light_grid.size() >= 112 * 112:
				var m_norm = clamp(1.0 - float(light_grid[m_idx]) / 14.5, 0.0, 1.0)
				m_bright = pow(m_norm, 1.8)
			m_mat.set_shader_parameter("shadow_skew", ms_info["skew"] * ms_info["length"])
			m_mat.set_shader_parameter("shadow_color", Color(0.0, 0.0, 0.0, ms_info["opacity"] * clampf(m_bright * 1.2, 0.2, 0.85)))

		if is_town:
			var m_light = light_grid[m_idx] if light_grid.size() >= 112 * 112 else 0
			var bright = clamp(1.0 - float(m_light) / 15.0, 0.0, 1.0)
			if m_sprite:
				m_sprite.self_modulate = Color(0.70, 0.72, 0.78).lerp(Color(1.0, 0.96, 0.90), bright * 0.55)
			node.visible = true
		elif light_grid.size() >= 112 * 112:
			var m_light = light_grid[m_idx]
			if m_light >= 15:
				node.visible = false
				continue
			var m_norm = clamp(1.0 - float(m_light) / 14.5, 0.0, 1.0)
			var m_bright = pow(m_norm, 1.8)
			if m_sprite:
				m_sprite.self_modulate = Color(1.0, 0.96, 0.92) * max(0.12, m_bright)
			node.visible = true
		else:
			node.visible = true

	# Hide monsters that are no longer active
	for m_id in monster_nodes:
		if not seen_ids.has(m_id):
			monster_nodes[m_id].visible = false
			if monster_shadow_materials.has(m_id):
				monster_shadow_materials.erase(m_id)

func get_or_create_monster_node(m_id: int) -> Node2D:
	if monster_nodes.has(m_id) and is_instance_valid(monster_nodes[m_id]):
		return monster_nodes[m_id]

	var m_root = Node2D.new()
	m_root.name = "Monster_%d" % m_id
	m_root.z_index = 0
	world_root.add_child(m_root)

	var shadow = Sprite2D.new()
	shadow.name = "Shadow"
	shadow.centered = true
	shadow.position = Vector2.ZERO
	shadow.z_index = -1
	m_root.add_child(shadow)

	var spr = Sprite2D.new()
	spr.name = "Sprite"
	spr.centered = true
	m_root.add_child(spr)

	monster_nodes[m_id] = m_root
	return m_root

func update_torches():
	if not diablo_bridge or not diablo_bridge.has_method("get_active_lights"):
		return

	var lights = diablo_bridge.get_active_lights()
	var needed = lights.size()

	# Expand torch light pool if needed
	while torch_lights.size() < needed:
		var pl = PointLight2D.new()
		pl.texture = shared_radial_light_texture if shared_radial_light_texture else create_radial_light_texture(512)
		pl.texture_scale = 1.4
		pl.shadow_enabled = enable_wall_occluders
		pl.shadow_filter = Light2D.SHADOW_FILTER_PCF13
		pl.shadow_filter_smooth = 4.5
		pl.shadow_color = Color(0.0, 0.0, 0.0, 0.38)
		world_root.add_child(pl)
		torch_lights.append(pl)

	var light_grid = diablo_bridge.get_dungeon_light_grid() if diablo_bridge.has_method("get_dungeon_light_grid") else PackedByteArray()
	var p_pos = diablo_bridge.get_player_continuous_pos() if diablo_bridge.has_method("get_player_continuous_pos") else {}
	var p_tx = float(p_pos.get("pos_x", 25.0))
	var p_ty = float(p_pos.get("pos_y", 25.0))
	var is_town = (last_level_idx == 0)

	# Index 0 is the hero torch; environmental lights are 1..N
	for i in range(torch_lights.size()):
		var pl: PointLight2D = torch_lights[i]
		if i < lights.size() and i > 0: # Environmental lights (wall torches, fireballs)
			var info = lights[i]
			var l_type = info.get("type", 1)
			var tx = float(info.get("tile_x", 0))
			var ty = float(info.get("tile_y", 0))
			var t_idx = clamp(int(ty), 0, 111) * 112 + clamp(int(tx), 0, 111)

			var is_torch_lit = true
			if not is_town and light_grid.size() >= 112 * 112:
				if light_grid[t_idx] >= 15:
					is_torch_lit = false

			var p_dist = Vector2(tx, ty).distance_to(Vector2(p_tx, p_ty))
			if not is_torch_lit or p_dist > 22.0:
				pl.visible = false
				continue

			var l_pos = Vector2((tx - ty) * 32.0, (tx + ty) * 16.0 - 10.0)
			pl.position = l_pos
			pl.visible = true

			var phase = float(i) * 1.83
			var t_flicker = 1.0 + 0.10 * sin(time_accum * 13.1 + phase) * cos(time_accum * 7.9 + phase * 2.0)
			var rad = float(info.get("radius", 6))

			if l_type == 1: # Wall torch / brazier
				pl.color = Color(1.0, 0.72, 0.35)
				pl.energy = 0.85 * t_flicker
				pl.texture_scale = clampf(rad * 0.22, 1.0, 2.2)
			elif l_type == 2: # Spell / missile (Fireball, flame)
				pl.color = Color(1.0, 0.88, 0.50)
				pl.energy = 1.25 * t_flicker
				pl.texture_scale = clampf(rad * 0.26, 1.2, 2.5)
			else:
				pl.color = Color(0.95, 0.70, 0.40)
				pl.energy = 0.70
				pl.texture_scale = 1.3
		else:
			pl.visible = false

# Milestone 4: Dungeon Objects (Animated Torches, Barrels, Chests, Shrines)
func update_objects():
	if not diablo_bridge or not diablo_bridge.has_method("get_active_objects"):
		return

	var objects: Array = diablo_bridge.get_active_objects()
	var seen_ids: Dictionary = {}

	var light_grid = diablo_bridge.get_dungeon_light_grid() if diablo_bridge.has_method("get_dungeon_light_grid") else PackedByteArray()
	var has_light = (light_grid.size() >= 112 * 112)

	# Camera-visible tile window around the hero, using the same math as update_lighting_and_transparency().
	# Without this cull every door/chest/barrel/arches anywhere in the level renders on screen.
	var p_pos = diablo_bridge.get_player_continuous_pos() if diablo_bridge.has_method("get_player_continuous_pos") else {}
	var ppx = float(p_pos.get("pos_x", 25.0))
	var ppy = float(p_pos.get("pos_y", 25.0))
	var cam_z = camera.zoom.x if camera else 1.0
	var rad_x = int(clamp(60.0 / cam_z, 44.0, 80.0))
	var rad_y = int(clamp(50.0 / cam_z, 36.0, 70.0))
	var min_x = int(clamp(int(ppx) - rad_x, 0, 111))
	var max_x = int(clamp(int(ppx) + rad_x, 0, 111))
	var min_y = int(clamp(int(ppy) - rad_y, 0, 111))
	var max_y = int(clamp(int(ppy) + rad_y, 0, 111))

	for obj in objects:
		var o_id = obj.get("id", -1)
		if o_id < 0:
			continue
		seen_ids[o_id] = true

		var tx = obj.get("tile_x", 0)
		var ty = obj.get("tile_y", 0)

		# Cull anything outside the visible tile window (doors, chests, barrels, arches...).
		if tx < min_x or tx > max_x or ty < min_y or ty > max_y:
			var old_spr = object_sprites.get(o_id, null)
			if old_spr:
				old_spr.visible = false
			continue

		seen_ids[o_id] = true
		var o_type = obj.get("type", 0)
		var anim_frame = obj.get("anim_frame", 1)
		var pre_flag = obj.get("pre_flag", false)

		var spr: Sprite2D = object_sprites.get(o_id, null)
		if spr == null:
			spr = Sprite2D.new()
			spr.name = "Object_%d" % o_id
			spr.centered = false
			world_root.add_child(spr)
			object_sprites[o_id] = spr

		# Y-sort depth key = object's bottom vertex (position.y), matching vanilla D1's depth ordering
		var tile_pos = Vector2(float(tx - ty) * 32.0, float(tx + ty) * 16.0 + (19.0 if not pre_flag else 16.0))
		spr.position = tile_pos
		spr.z_index = 0

		# Texture caching by (type, anim_frame)
		var cache_key = "%d_%d" % [o_type, anim_frame]
		var tex: ImageTexture = object_textures.get(cache_key, null)
		if tex == null and diablo_bridge.has_method("get_object_sprite_data"):
			var s_data = diablo_bridge.get_object_sprite_data(o_id)
			var sw = s_data.get("width", 0)
			var sh = s_data.get("height", 0)
			var rgba = s_data.get("rgba", PackedByteArray())
			if sw > 0 and sh > 0 and rgba.size() == sw * sh * 4:
				var img = Image.create_from_data(sw, sh, false, Image.FORMAT_RGBA8, rgba)
				tex = ImageTexture.create_from_image(img)
				object_textures[cache_key] = tex

		if tex:
			spr.texture = tex
			spr.offset = Vector2(-float(tex.get_width()) * 0.5, -float(tex.get_height()) - (2.0 if not pre_flag else 0.0))

		# Authentic per-tile lighting (Objects in Diablo 1 are NEVER transparent!)
		spr.modulate.a = 1.0

		var tile_idx = clamp(ty, 0, 111) * 112 + clamp(tx, 0, 111)
		var is_door = (o_type == 1 or o_type == 2 or o_type == 42 or o_type == 43 or o_type == 74 or o_type == 75 or o_type == 105 or o_type == 106)
		var is_flame = (o_type == 0 or o_type == 3 or o_type == 8 or o_type == 9 or o_type == 10 or o_type == 44 or o_type == 45 or o_type == 46 or o_type == 47 or o_type == 65 or o_type == 87 or o_type == 104)
		var is_sarc = (o_type == 48 or o_type == 108)
		var is_town = (last_level_idx == 0)

		if is_town:
			var light_val = light_grid[tile_idx] if has_light else 0
			var bright = clamp(1.0 - float(light_val) / 15.0, 0.0, 1.0)
			spr.self_modulate = Color(0.70, 0.72, 0.78).lerp(Color(1.0, 0.96, 0.90), bright * 0.55)
			spr.visible = true
		elif has_light:
			var light_val = light_grid[tile_idx]
			if is_door:
				# Doors sit in doorways between rooms: check adjacent floor tiles to see if doorway is illuminated
				if tx > 0 and light_grid[tile_idx - 1] < light_val:
					light_val = light_grid[tile_idx - 1]
				if tx < 111 and light_grid[tile_idx + 1] < light_val:
					light_val = light_grid[tile_idx + 1]
				if ty > 0 and light_grid[tile_idx - 112] < light_val:
					light_val = light_grid[tile_idx - 112]
				if ty < 111 and light_grid[tile_idx + 112] < light_val:
					light_val = light_grid[tile_idx + 112]
			elif is_sarc:
				# Sarcophagi are 2-tile objects occupying (tx, ty) and (tx, ty - 1)
				if ty > 0 and light_grid[tile_idx - 112] < light_val:
					light_val = light_grid[tile_idx - 112]

			if light_val >= 15 and not is_flame:
				spr.visible = false
			else:
				var o_norm = clamp(1.0 - float(light_val) / 14.5, 0.0, 1.0)
				var o_factor = pow(o_norm, 1.8)
				if is_flame:
					o_factor = max(0.85, o_factor)
				spr.self_modulate = Color(0.040, 0.042, 0.055).lerp(Color(1.0, 0.96, 0.92), max(0.08, o_factor))
				spr.visible = true
		else:
			spr.visible = true

	for o_id in object_sprites:
		if not seen_ids.has(o_id):
			object_sprites[o_id].visible = false

# Milestone 4: Ground Items & Loot with Authentic Labels
func update_ground_items():
	if not diablo_bridge or not diablo_bridge.has_method("get_active_items"):
		return

	var items: Array = diablo_bridge.get_active_items()
	var seen_ids: Dictionary = {}

	var light_grid = diablo_bridge.get_dungeon_light_grid() if diablo_bridge.has_method("get_dungeon_light_grid") else PackedByteArray()
	var has_light = (light_grid.size() >= 112 * 112)

	for item in items:
		var i_id = item.get("id", -1)
		if i_id < 0:
			continue
		seen_ids[i_id] = true

		var tx = item.get("tile_x", 0)
		var ty = item.get("tile_y", 0)
		var quality = item.get("quality", 0)
		var iname = item.get("name", "")

		var node: Node2D = item_nodes.get(i_id, null)
		if node == null:
			node = Node2D.new()
			node.name = "GroundItem_%d" % i_id
			node.z_index = 0 # Y-sorted dungeon entity
			world_root.add_child(node)

			var spr = Sprite2D.new()
			spr.name = "Sprite"
			spr.centered = false
			node.add_child(spr)

			# Authentic Diablo loot name label
			var lbl = Label.new()
			lbl.name = "Label"
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lbl.add_theme_font_size_override("font_size", 11)
			lbl.z_as_relative = false
			lbl.z_index = 20

			var style = StyleBoxFlat.new()
			style.bg_color = Color(0.0, 0.0, 0.0, 0.75)
			style.corner_radius_top_left = 3
			style.corner_radius_top_right = 3
			style.corner_radius_bottom_left = 3
			style.corner_radius_bottom_right = 3
			style.content_margin_left = 6.0
			style.content_margin_right = 6.0
			style.content_margin_top = 2.0
			style.content_margin_bottom = 2.0
			lbl.add_theme_stylebox_override("normal", style)
			node.add_child(lbl)

			item_nodes[i_id] = node

		var is_item_lit = true
		if has_light and last_level_idx != 0:
			var i_tile_idx = clamp(ty, 0, 111) * 112 + clamp(tx, 0, 111)
			if light_grid[i_tile_idx] >= 15:
				is_item_lit = false
		node.visible = is_item_lit
		var tile_pos = Vector2(float(tx - ty) * 32.0, float(tx + ty) * 16.0 + 16.0)
		node.position = tile_pos

		var spr = node.get_node_or_null("Sprite") as Sprite2D
		var curs_id = item.get("curs_id", 0)
		var anim_frame = item.get("anim_frame", 0)
		var cache_key = "%d_%d" % [curs_id, anim_frame]
		var tex: ImageTexture = item_textures.get(cache_key, null)
		if tex == null:
			tex = item_textures.get(curs_id, null)
		if (tex == null or anim_frame > 0) and diablo_bridge.has_method("get_ground_item_sprite_data"):
			var s_data = diablo_bridge.get_ground_item_sprite_data(i_id)
			var sw = s_data.get("width", 0)
			var sh = s_data.get("height", 0)
			var rgba = s_data.get("rgba", PackedByteArray())
			if sw > 0 and sh > 0 and rgba.size() == sw * sh * 4:
				var img = Image.create_from_data(sw, sh, false, Image.FORMAT_RGBA8, rgba)
				tex = ImageTexture.create_from_image(img)
				item_textures[cache_key] = tex
				item_textures[curs_id] = tex

		if tex and spr:
			spr.texture = tex
			spr.offset = Vector2(-float(tex.get_width()) * 0.5, -float(tex.get_height()))

		# Lighting & Fog of War
		var tile_idx = clamp(ty, 0, 111) * 112 + clamp(tx, 0, 111)
		var is_town = (last_level_idx == 0)
		if spr:
			if is_town:
				var light_val = light_grid[tile_idx] if has_light else 0
				var bright = clamp(1.0 - float(light_val) / 15.0, 0.0, 1.0)
				spr.self_modulate = Color(0.70, 0.72, 0.78).lerp(Color(1.0, 0.96, 0.90), bright * 0.55)
				node.visible = true
			elif has_light:
				var light_val = light_grid[tile_idx]
				if light_val >= 15:
					node.visible = false
				else:
					var brightness = pow(clamp(1.0 - float(light_val) / 14.5, 0.0, 1.0), 1.8)
					spr.self_modulate = Color(0.040, 0.042, 0.055).lerp(Color(1.0, 0.96, 0.92), max(0.12, brightness))
					node.visible = true
			else:
				node.visible = true

		# Ground item label
		var lbl = node.get_node_or_null("Label") as Label
		if lbl and iname != "":
			lbl.text = iname
			if quality == 1:
				lbl.modulate = Color(0.40, 0.65, 1.0) # Magic Blue
			elif quality == 2:
				lbl.modulate = Color(1.0, 0.88, 0.35) # Unique Gold
			else:
				lbl.modulate = Color(0.95, 0.95, 0.95) # Normal White
			lbl.reset_size()
			var sz = lbl.get_combined_minimum_size()

			# Anchor the label directly above the floor diamond and ground item sprite (matching DevilutionX Mode 0)
			lbl.position = Vector2(-sz.x * 0.5, -32.0 - sz.y)
			lbl.z_as_relative = false
			lbl.z_index = 20
			var show_labels = diablo_bridge.is_item_label_highlight_enabled() if diablo_bridge.has_method("is_item_label_highlight_enabled") else true
			lbl.visible = show_labels

	for i_id in item_nodes:
		if not seen_ids.has(i_id):
			item_nodes[i_id].visible = false

# Milestone 4: Corpses & Fallen Monsters on the Floor
func update_corpses():
	if not diablo_bridge or not diablo_bridge.has_method("get_active_corpses"):
		return

	var corpses: Array = diablo_bridge.get_active_corpses()
	var seen_keys: Dictionary = {}

	var light_grid: PackedByteArray = PackedByteArray()
	if diablo_bridge.has_method("get_dungeon_light_grid"):
		light_grid = diablo_bridge.get_dungeon_light_grid()
	var has_light = (light_grid.size() >= 112 * 112)

	for c in corpses:
		var tx = c.get("tile_x", 0)
		var ty = c.get("tile_y", 0)
		var corpse_idx = c.get("corpse_idx", 0)
		var dir = c.get("dir", 0)

		var pos_key = Vector2i(tx, ty)
		seen_keys[pos_key] = true

		var spr: Sprite2D = corpse_sprites.get(pos_key, null)
		if spr == null:
			spr = Sprite2D.new()
			spr.name = "Corpse_%d_%d" % [tx, ty]
			spr.centered = false
			spr.z_index = -1
			world_root.add_child(spr)
			corpse_sprites[pos_key] = spr

		# Lighting & Fog of War
		var tile_idx = clamp(ty, 0, 111) * 112 + clamp(tx, 0, 111)
		var is_town = (last_level_idx == 0)
		if is_town:
			var light_val = light_grid[tile_idx] if has_light else 0
			var bright = clamp(1.0 - float(light_val) / 15.0, 0.0, 1.0)
			spr.self_modulate = Color(0.70, 0.72, 0.78).lerp(Color(1.0, 0.96, 0.90), bright * 0.55)
			spr.visible = true
		elif has_light:
			var light_val = light_grid[tile_idx]
			if light_val >= 15:
				spr.visible = false
			else:
				var brightness = pow(clamp(1.0 - float(light_val) / 14.5, 0.0, 1.0), 1.8)
				spr.self_modulate = Color(0.04, 0.07, 0.11).lerp(Color(1.0, 0.96, 0.92), max(0.12, brightness))
				spr.visible = true
		else:
			spr.visible = true
		var tile_pos = Vector2(float(tx - ty) * 32.0, float(tx + ty) * 16.0 + 16.0)
		spr.position = tile_pos

		var cache_key = "%d_%d" % [corpse_idx, dir]
		var tex: ImageTexture = corpse_textures.get(cache_key, null)
		if tex == null and diablo_bridge.has_method("get_corpse_sprite_data"):
			var s_data = diablo_bridge.get_corpse_sprite_data(corpse_idx, dir)
			var sw = s_data.get("width", 0)
			var sh = s_data.get("height", 0)
			var rgba = s_data.get("rgba", PackedByteArray())
			if sw > 0 and sh > 0 and rgba.size() == sw * sh * 4:
				var img = Image.create_from_data(sw, sh, false, Image.FORMAT_RGBA8, rgba)
				tex = ImageTexture.create_from_image(img)
				corpse_textures[cache_key] = tex

		if tex:
			spr.texture = tex
			spr.offset = Vector2(-float(tex.get_width()) * 0.5, -float(tex.get_height()))

	for k in corpse_sprites:
		if not seen_keys.has(k):
			corpse_sprites[k].visible = false

# Projectiles & Spells (Arrows, Firebolts, Fireballs, Lightning, Holy Bolts)
func update_missiles():
	if not diablo_bridge or not diablo_bridge.has_method("get_active_missiles"):
		return

	var missiles: Array = diablo_bridge.get_active_missiles()
	var seen_ids: Dictionary = {}

	var light_grid: PackedByteArray = PackedByteArray()
	if diablo_bridge.has_method("get_dungeon_light_grid"):
		light_grid = diablo_bridge.get_dungeon_light_grid()
	var has_light = (light_grid.size() >= 112 * 112)

	for m in missiles:
		var m_id = m.get("id", -1)
		if m_id < 0:
			continue
		seen_ids[m_id] = true

		var m_type = m.get("type", 0)
		var m_dir = m.get("dir", 0)
		var px = m.get("pos_x", 0.0)
		var py = m.get("pos_y", 0.0)
		var m_tx = m.get("tile_x", 0)
		var m_ty = m.get("tile_y", 0)
		var anim_frame = m.get("anim_frame", 0)
		var light_flag = m.get("light_flag", false)
		var pre_flag = m.get("pre_flag", false)

		var node: Node2D = missile_nodes.get(m_id, null)
		if node == null:
			node = Node2D.new()
			node.name = "Missile_%d" % m_id
			world_root.add_child(node)

			var spr = Sprite2D.new()
			spr.name = "Sprite"
			spr.centered = false
			node.add_child(spr)

			missile_nodes[m_id] = node

		node.z_index = 0
		# Y-sort depth key = missile's bottom vertex (position.y), matching vanilla D1's depth ordering
		node.position = Vector2(px, py + 16.0)

		var spr = node.get_node_or_null("Sprite") as Sprite2D

		# Lighting: glowing spell missiles (fireball, firebolt, lightning) stay fully lit
		# Non-glowing missiles (arrows) sample the dungeon light grid
		if spr:
			if light_flag:
				spr.self_modulate = Color(1.0, 1.0, 1.0)
			elif has_light:
				var tile_idx = clamp(m_ty, 0, 111) * 112 + clamp(m_tx, 0, 111)
				var l_val = light_grid[tile_idx]
				if l_val >= 15:
					node.visible = false
					continue
				var brightness = pow(clamp(1.0 - float(l_val) / 14.5, 0.0, 1.0), 1.8)
				spr.self_modulate = Color(0.04, 0.07, 0.11).lerp(Color(1.0, 0.96, 0.92), brightness)

		node.visible = true

		# Texture caching by (type, dir, anim_frame)
		var cache_key = "%d_%d_%d" % [m_type, m_dir, anim_frame]
		var tex: ImageTexture = missile_textures.get(cache_key, null)
		if tex == null and diablo_bridge.has_method("get_missile_sprite_data"):
			var s_data = diablo_bridge.get_missile_sprite_data(m_id)
			var sw = s_data.get("width", 0)
			var sh = s_data.get("height", 0)
			var rgba = s_data.get("rgba", PackedByteArray())
			if sw > 0 and sh > 0 and rgba.size() == sw * sh * 4:
				var img = Image.create_from_data(sw, sh, false, Image.FORMAT_RGBA8, rgba)
				tex = ImageTexture.create_from_image(img)
				missile_textures[cache_key] = tex

		if spr and tex:
			spr.texture = tex
			spr.offset = Vector2(-float(tex.get_width()) * 0.5, -float(tex.get_height()))

	# Hide inactive missiles
	for m_id in missile_nodes:
		if not seen_ids.has(m_id):
			missile_nodes[m_id].visible = false

func get_world_mouse_position(screen_pos: Vector2) -> Vector2:
	var vp_size = get_viewport().get_visible_rect().size
	var cam_pos = camera.position if camera else Vector2.ZERO
	var cam_z = camera.zoom.x if camera else 1.0
	return (screen_pos - vp_size * 0.5) / cam_z + cam_pos

func handle_input(event: InputEvent) -> bool:
	if not is_active:
		return false

	# If the game is not actively in a dungeon/game session (e.g. main menu, hero select, character create),
	# do NOT intercept input with world-space raycasting! Pass through to classic UI!
	if diablo_bridge and diablo_bridge.has_method("is_game_running") and not diablo_bridge.is_game_running():
		return false

	# When a modal menu, store, or dialog is active, pass input through to screen-space UI
	if diablo_bridge and diablo_bridge.has_method("is_modal_active") and diablo_bridge.is_modal_active():
		return false

	# Mouse Wheel Zoom
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if current_zoom_idx < zoom_levels.size() - 1:
				current_zoom_idx += 1
				var z = zoom_levels[current_zoom_idx]
				camera.zoom = Vector2(z, z)
			return true
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if current_zoom_idx > 0:
				current_zoom_idx -= 1
				var z = zoom_levels[current_zoom_idx]
				camera.zoom = Vector2(z, z)
			return true

	# Mouse Click & Motion Conversion
	if event is InputEventMouseButton:
		var d1_pos = Vector2i.ZERO
		if diablo_bridge and diablo_bridge.has_method("map_world_to_screen"):
			var mouse_world = get_world_mouse_position(event.position)
			d1_pos = diablo_bridge.map_world_to_screen(mouse_world)
		else:
			var d1_w = diablo_bridge.get_frame_width() if (diablo_bridge and diablo_bridge.has_method("get_frame_width")) else 640
			var d1_h = diablo_bridge.get_frame_height() if (diablo_bridge and diablo_bridge.has_method("get_frame_height")) else 480
			var vp_size = get_viewport().get_visible_rect().size
			var norm_x = event.position.x / float(vp_size.x)
			var norm_y = event.position.y / float(vp_size.y)
			d1_pos = Vector2i(clampi(int(norm_x * float(d1_w)), 0, d1_w - 1), clampi(int(norm_y * float(d1_h)), 0, d1_h - 1))

		var btn = 1
		if event.button_index == MOUSE_BUTTON_RIGHT:
			btn = 3
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			btn = 2
		var state = 1 if event.pressed else 0

		if diablo_bridge and diablo_bridge.has_method("send_input"):
			diablo_bridge.send_input(2, btn, state, d1_pos.x, d1_pos.y)
		return true

	elif event is InputEventMouseMotion:
		var d1_pos = Vector2i.ZERO
		if diablo_bridge and diablo_bridge.has_method("map_world_to_screen"):
			var mouse_world = get_world_mouse_position(event.position)
			d1_pos = diablo_bridge.map_world_to_screen(mouse_world)
		else:
			var d1_w = diablo_bridge.get_frame_width() if (diablo_bridge and diablo_bridge.has_method("get_frame_width")) else 640
			var d1_h = diablo_bridge.get_frame_height() if (diablo_bridge and diablo_bridge.has_method("get_frame_height")) else 480
			var vp_size = get_viewport().get_visible_rect().size
			var norm_x = event.position.x / float(vp_size.x)
			var norm_y = event.position.y / float(vp_size.y)
			d1_pos = Vector2i(clampi(int(norm_x * float(d1_w)), 0, d1_w - 1), clampi(int(norm_y * float(d1_h)), 0, d1_h - 1))

		if diablo_bridge and diablo_bridge.has_method("send_input"):
			diablo_bridge.send_input(1, 0, 0, d1_pos.x, d1_pos.y)
		return true

	return false
