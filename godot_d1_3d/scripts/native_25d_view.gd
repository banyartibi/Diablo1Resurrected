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

# State tracking
var last_level_idx: int = -999
var pending_dungeon_rebuild: bool = false
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

	# Atmospheric Gothic Crypt Canvas Modulate (Pure 1.0 ambient so dLight controls contrast cleanly)
	canvas_modulate = CanvasModulate.new()
	canvas_modulate.name = "CryptModulate"
	canvas_modulate.color = Color(1.0, 1.0, 1.0)
	add_child(canvas_modulate)

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

	# Ground Blob Shadow (beneath hero sprite, above floor)
	player_shadow = Sprite2D.new()
	player_shadow.name = "PlayerShadow"
	player_shadow.texture = get_or_create_shadow_texture()
	player_shadow.centered = true
	player_shadow.position = Vector2(0, 12)
	player_shadow.z_index = 0
	player_node.add_child(player_shadow)

	# Hero Sprite2D (authentic animated Diablo 1 pixel art)
	player_sprite = Sprite2D.new()
	player_sprite.name = "PlayerSprite"
	player_sprite.centered = true
	player_node.add_child(player_sprite)

	# Hero Torch Light (Disabled by default to preserve authentic dLight contrast)
	player_light = PointLight2D.new()
	player_light.name = "HeroTorchLight"
	player_light.texture = create_radial_light_texture(512)
	player_light.texture_scale = 1.35
	player_light.color = Color(1.0, 0.90, 0.75)
	player_light.energy = 0.0
	player_light.enabled = false
	player_light.position = Vector2(0, -16)
	player_node.add_child(player_light)

func create_radial_light_texture(size: int) -> GradientTexture2D:
	var grad = Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex = GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = size
	tex.height = size
	return tex

func activate():
	is_active = true
	visible = true
	set_process(true)
	if camera:
		camera.make_current()
	rebuild_dungeon_tiles()
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

	# During level transitions, DevilutionX is tearing down and rebuilding memory.
	# Freeze rendering updates until the new level is 100% ready to eliminate race conditions.
	if diablo_bridge.has_method("is_level_loading") and diablo_bridge.is_level_loading():
		return

	if pending_dungeon_rebuild:
		var grid = diablo_bridge.get_dungeon_grid() if diablo_bridge.has_method("get_dungeon_grid") else PackedInt32Array()
		if grid.size() >= 112 * 112:
			var can_fetch = false
			for piece_id in grid:
				if piece_id > 0:
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
	update_ground_items()
	update_corpses()
	update_missiles()
	update_lighting_and_transparency()

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

	var special_grid = PackedInt32Array()
	if diablo_bridge.has_method("get_dungeon_special_grid"):
		special_grid = diablo_bridge.get_dungeon_special_grid()

	var count = 0
	var special_count = 0
	for y in range(112):
		for x in range(112):
			var idx = y * 112 + x
			var piece_id = grid[idx]
			var special_id = special_grid[idx] if idx < special_grid.size() else 0
			var tile_pos = Vector2(float(x - y) * 32.0, float(x + y) * 16.0)

			# 1. Base Dungeon Piece (Floor & Walls)
			if piece_id > 0:
				var tex: Texture2D = null
				if diablo_bridge.has_method("get_dungeon_piece_texture"):
					tex = diablo_bridge.get_dungeon_piece_texture(piece_id)
				if tex != null:
					var spr = Sprite2D.new()
					spr.texture = tex
					spr.centered = false
					var h = tex.get_height()
					spr.position = tile_pos
					spr.offset = Vector2(-32.0, 16.0 - float(h))
					# Initialize hidden in deep gothic darkness / fog of war
					spr.self_modulate = Color(0.0, 0.0, 0.0)
					spr.visible = false
					if h <= 32:
						spr.z_index = -1
					else:
						spr.z_index = 0
					world_root.add_child(spr)
					tile_sprites[Vector2i(x, y)] = spr
					count += 1

			# 2. Milestone 1: Special CELs (Archways, Column Tops, Doorways)
			if special_id > 0 and diablo_bridge.has_method("get_special_cel_texture"):
				var arch_tex: Texture2D = diablo_bridge.get_special_cel_texture(special_id)
				if arch_tex != null:
					var arch_spr = Sprite2D.new()
					arch_spr.texture = arch_tex
					arch_spr.centered = false
					var ah = arch_tex.get_height()
					arch_spr.position = tile_pos
					arch_spr.offset = Vector2(-32.0, 16.0 - float(ah))
					# Initialize hidden in deep gothic darkness / fog of war
					arch_spr.self_modulate = Color(0.0, 0.0, 0.0)
					arch_spr.visible = false
					arch_spr.z_index = 0 # Y-sorted with walls!
					world_root.add_child(arch_spr)
					special_sprites[Vector2i(x, y)] = arch_spr
					special_count += 1

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

	var has_light = (light_grid.size() >= 112 * 112)
	var has_trans = (trans_grid.size() >= 112 * 112 and trans_list.size() >= 256)
	var has_trans_mask = (trans_mask.size() >= 112 * 112)

	var p_pos = diablo_bridge.get_player_continuous_pos() if diablo_bridge.has_method("get_player_continuous_pos") else {}
	var p_tx = int(p_pos.get("pos_x", 25.0))
	var p_ty = int(p_pos.get("pos_y", 25.0))

	var z = camera.zoom.x if camera else 1.0
	var rad_x = int(clamp(36.0 / z, 24.0, 64.0))
	var rad_y = int(clamp(28.0 / z, 18.0, 56.0))
	var min_x = max(0, p_tx - rad_x)
	var max_x = min(111, p_tx + rad_x)
	var min_y = max(0, p_ty - rad_y)
	var max_y = min(111, p_ty + rad_y)

	var new_active_keys: Dictionary = {}

	for ty in range(min_y, max_y + 1):
		for tx in range(min_x, max_x + 1):
			var pos_key = Vector2i(tx, ty)
			var spr = tile_sprites.get(pos_key, null)
			var arch_spr = special_sprites.get(pos_key, null)
			if spr == null and arch_spr == null:
				continue

			var idx = ty * 112 + tx

			new_active_keys[pos_key] = true

			# Milestone 2: Per-Tile Authentic Lighting & Atmosphere
			var light_val = light_grid[idx] if has_light else 0
			var is_town = (last_level_idx == 0)
			var tile_mod: Color

			if is_town:
				# Tristram peaceful moonlight with subtle warm glows near braziers/torches
				var bright = clamp(1.0 - float(light_val) / 15.0, 0.0, 1.0)
				tile_mod = Color(0.70, 0.72, 0.78).lerp(Color(1.0, 0.96, 0.90), bright * 0.55)
			else:
				# Crypt / Dungeon atmospheric depth - never completely vanish into missing black voids
				if light_val < 15:
					var norm = clamp(1.0 - float(light_val) / 14.5, 0.0, 1.0)
					var factor = max(0.08, pow(norm, 1.8))
					tile_mod = Color(1.0, 0.94, 0.88) * factor
				else:
					tile_mod = Color(0.04, 0.04, 0.06)

			# Milestone 3: Authentic Front-Wall Transparency (TransList + TileProperties::Transparent)
			# Only tiles that have the Diablo 1 Transparent flag (front walls/doors) become transparent!
			# Sarcophagi, statues, back walls, altars and floors (height <= 32) remain 100% solid!
			var alpha_val = 1.0
			if has_trans:
				var t_id = trans_grid[idx]
				if t_id > 0 and t_id < trans_list.size() and trans_list[t_id] == 1:
					alpha_val = 0.38 # Transparent front wall!

			if spr:
				spr.visible = true
				spr.self_modulate = tile_mod
				var is_wall = (spr.texture and spr.texture.get_height() > 32)
				var can_be_trans = has_trans_mask and (trans_mask[idx] == 1)
				if is_wall and can_be_trans:
					spr.modulate.a = alpha_val
				else:
					spr.modulate.a = 1.0

			if arch_spr:
				arch_spr.visible = true
				arch_spr.self_modulate = tile_mod
				arch_spr.modulate.a = alpha_val

	# Hide tiles that moved outside viewport or active range
	for prev_key in last_visible_tiles:
		if not new_active_keys.has(prev_key):
			var old_spr = tile_sprites.get(prev_key, null)
			if old_spr: old_spr.visible = false
			var old_arch = special_sprites.get(prev_key, null)
			if old_arch: old_arch.visible = false
	last_visible_tiles = new_active_keys

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
	player_target_pos = Vector2(float(px - py) * 32.0, float(px + py) * 16.0)
	if player_node.position == Vector2.ZERO or player_node.position.distance_to(player_target_pos) > 200.0:
		player_node.position = player_target_pos
	else:
		player_node.position = player_node.position.lerp(player_target_pos, delta * 18.0)

	# Smooth camera follow with integer rounding to eliminate sub-pixel tile seams
	if camera:
		camera.position = camera.position.lerp(player_node.position, delta * 14.0).round()

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
				# Offset so player feet rest precisely in the center of the diamond
				player_sprite.offset = Vector2(0, -float(sh) * 0.5 + 16.0)

	# Authentic per-tile lighting on player & blob ground shadow
	var p_light_grid = diablo_bridge.get_dungeon_light_grid() if diablo_bridge.has_method("get_dungeon_light_grid") else PackedByteArray()
	var p_tile_idx = clamp(int(py), 0, 111) * 112 + clamp(int(px), 0, 111)
	var is_town = (last_level_idx == 0)
	if is_town:
		var p_light = p_light_grid[p_tile_idx] if p_light_grid.size() >= 112 * 112 else 0
		var bright = clamp(1.0 - float(p_light) / 15.0, 0.0, 1.0)
		player_sprite.self_modulate = Color(0.70, 0.72, 0.78).lerp(Color(1.0, 0.96, 0.90), bright * 0.55)
		if player_shadow:
			player_shadow.self_modulate = Color(1.0, 1.0, 1.0, 0.60)
	elif p_light_grid.size() >= 112 * 112:
		var p_light = p_light_grid[p_tile_idx]
		var p_norm = clamp(1.0 - float(p_light) / 14.5, 0.0, 1.0)
		var p_bright = pow(p_norm, 1.8)
		player_sprite.self_modulate = Color(1.0, 0.96, 0.92) * max(0.12, p_bright)
		if player_shadow:
			player_shadow.self_modulate = Color(1.0, 1.0, 1.0, clampf(p_bright * 0.7, 0.15, 0.65))

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

		var target_pos = Vector2(float(mx - my) * 32.0, float(mx + my) * 16.0)
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
						m_sprite.offset = Vector2(0, -float(mh) * 0.5 + 16.0)

		# Milestone 2: Per-Tile Authentic Lighting on Monsters, Ground Shadows & Fog of War
		var light_grid = diablo_bridge.get_dungeon_light_grid() if diablo_bridge.has_method("get_dungeon_light_grid") else PackedByteArray()
		var m_tx = clamp(int(mx), 0, 111)
		var m_ty = clamp(int(my), 0, 111)
		var m_idx = m_ty * 112 + m_tx
		var is_town = (last_level_idx == 0)
		var m_shadow = node.get_node_or_null("Shadow") as Sprite2D
		if is_town:
			var m_light = light_grid[m_idx] if light_grid.size() >= 112 * 112 else 0
			var bright = clamp(1.0 - float(m_light) / 15.0, 0.0, 1.0)
			if m_sprite:
				m_sprite.self_modulate = Color(0.70, 0.72, 0.78).lerp(Color(1.0, 0.96, 0.90), bright * 0.55)
			if m_shadow:
				m_shadow.self_modulate = Color(1.0, 1.0, 1.0, 0.55)
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
			if m_shadow:
				m_shadow.self_modulate = Color(1.0, 1.0, 1.0, clampf(m_bright * 0.7, 0.15, 0.65))
			node.visible = true
		else:
			node.visible = true

	# Hide monsters that are no longer active
	for m_id in monster_nodes:
		if not seen_ids.has(m_id):
			monster_nodes[m_id].visible = false

func get_or_create_monster_node(m_id: int) -> Node2D:
	if monster_nodes.has(m_id) and is_instance_valid(monster_nodes[m_id]):
		return monster_nodes[m_id]

	var m_root = Node2D.new()
	m_root.name = "Monster_%d" % m_id
	m_root.z_index = 0
	world_root.add_child(m_root)

	var shadow = Sprite2D.new()
	shadow.name = "Shadow"
	shadow.texture = get_or_create_shadow_texture()
	shadow.centered = true
	shadow.position = Vector2(0, 12)
	shadow.z_index = 0
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
		pl.texture = create_radial_light_texture(384)
		pl.texture_scale = 1.2
		pl.color = Color(1.0, 0.70, 0.35)
		pl.energy = 0.65
		world_root.add_child(pl)
		torch_lights.append(pl)

	for i in range(torch_lights.size()):
		torch_lights[i].visible = false

# Milestone 4: Dungeon Objects (Animated Torches, Barrels, Chests, Shrines)
func update_objects():
	if not diablo_bridge or not diablo_bridge.has_method("get_active_objects"):
		return

	var objects: Array = diablo_bridge.get_active_objects()
	var seen_ids: Dictionary = {}

	var light_grid = diablo_bridge.get_dungeon_light_grid() if diablo_bridge.has_method("get_dungeon_light_grid") else PackedByteArray()
	var has_light = (light_grid.size() >= 112 * 112)

	for obj in objects:
		var o_id = obj.get("id", -1)
		if o_id < 0:
			continue
		seen_ids[o_id] = true

		var tx = obj.get("tile_x", 0)
		var ty = obj.get("tile_y", 0)
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

		spr.visible = true
		var tile_pos = Vector2(float(tx - ty) * 32.0, float(tx + ty) * 16.0)
		spr.position = tile_pos
		spr.z_index = -1 if pre_flag else 0

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
			spr.offset = Vector2(-float(tex.get_width()) * 0.5, 16.0 - float(tex.get_height()))

		# Authentic per-tile lighting (Objects in Diablo 1 are NEVER transparent!)
		spr.modulate.a = 1.0

		var tile_idx = clamp(ty, 0, 111) * 112 + clamp(tx, 0, 111)
		var is_torch = (o_type == 1 or o_type == 2 or o_type == 3 or o_type == 4 or o_type == 6 or o_type == 7 or o_type == 8 or o_type == 9)
		var is_town = (last_level_idx == 0)
		if is_town:
			var light_val = light_grid[tile_idx] if has_light else 0
			var bright = clamp(1.0 - float(light_val) / 15.0, 0.0, 1.0)
			spr.self_modulate = Color(0.70, 0.72, 0.78).lerp(Color(1.0, 0.96, 0.90), bright * 0.55)
			spr.visible = true
		elif has_light:
			var light_val = light_grid[tile_idx]
			if light_val >= 15 and not is_torch:
				spr.self_modulate = Color(0.04, 0.04, 0.06)
				spr.visible = true
			else:
				var o_norm = clamp(1.0 - float(light_val) / 14.5, 0.0, 1.0)
				var o_factor = pow(o_norm, 1.8)
				if is_torch:
					o_factor = max(0.85, o_factor)
				spr.self_modulate = Color(1.0, 0.96, 0.92) * max(0.08, o_factor)
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
			node.z_index = -1 # Ground level
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

		node.visible = true
		var tile_pos = Vector2(float(tx - ty) * 32.0, float(tx + ty) * 16.0)
		node.position = tile_pos

		var spr = node.get_node_or_null("Sprite") as Sprite2D
		var tex: ImageTexture = item_textures.get(i_id, null)
		if tex == null and diablo_bridge.has_method("get_ground_item_sprite_data"):
			var s_data = diablo_bridge.get_ground_item_sprite_data(i_id)
			var sw = s_data.get("width", 0)
			var sh = s_data.get("height", 0)
			var rgba = s_data.get("rgba", PackedByteArray())
			if sw > 0 and sh > 0 and rgba.size() == sw * sh * 4:
				var img = Image.create_from_data(sw, sh, false, Image.FORMAT_RGBA8, rgba)
				tex = ImageTexture.create_from_image(img)
				item_textures[i_id] = tex

		if tex and spr:
			spr.texture = tex
			spr.offset = Vector2(-float(tex.get_width()) * 0.5, 16.0 - float(tex.get_height()))

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
					continue
				node.visible = true
				var brightness = pow(clamp(1.0 - float(light_val) / 14.5, 0.0, 1.0), 1.8)
				spr.self_modulate = Color(0.04, 0.07, 0.11).lerp(Color(1.0, 0.96, 0.92), max(0.12, brightness))
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
			var lbl_w = lbl.get_combined_minimum_size().x
			var h_off = float(tex.get_height()) if tex else 24.0
			lbl.position = Vector2(-lbl_w * 0.5, 16.0 - h_off - 14.0)

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
			spr.z_index = -1 # Floor level
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
				spr.self_modulate = Color(0.04, 0.04, 0.06)
				spr.visible = true
			else:
				var brightness = pow(clamp(1.0 - float(light_val) / 14.5, 0.0, 1.0), 1.8)
				spr.self_modulate = Color(0.04, 0.07, 0.11).lerp(Color(1.0, 0.96, 0.92), max(0.12, brightness))
				spr.visible = true
		else:
			spr.visible = true
		var tile_pos = Vector2(float(tx - ty) * 32.0, float(tx + ty) * 16.0)
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
			spr.offset = Vector2(-float(tex.get_width()) * 0.5, 16.0 - float(tex.get_height()))

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
		node.position = Vector2(px, py)

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
			spr.offset = Vector2(-float(tex.get_width()) * 0.5, 16.0 - float(tex.get_height()))

	# Hide inactive missiles
	for m_id in missile_nodes:
		if not seen_ids.has(m_id):
			missile_nodes[m_id].visible = false

func handle_input(event: InputEvent) -> bool:
	if not is_active:
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
		var mouse_world = get_global_mouse_position()
		var d1_coords = diablo_bridge.map_world_to_screen(mouse_world) if diablo_bridge and diablo_bridge.has_method("map_world_to_screen") else Vector2i(int(float(d1_width) * 0.5 + (mouse_world.x - player_node.position.x)), int(float(d1_height) * 0.5 + (mouse_world.y - player_node.position.y)))
		var d1_x = d1_coords.x
		var d1_y = d1_coords.y
		var btn = 1
		if event.button_index == MOUSE_BUTTON_RIGHT:
			btn = 3
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			btn = 2
		var state = 1 if event.pressed else 0
		if diablo_bridge and diablo_bridge.has_method("send_input"):
			diablo_bridge.send_input(2, btn, state, d1_x, d1_y)
		return true

	elif event is InputEventMouseMotion:
		var mouse_world = get_global_mouse_position()
		var d1_coords = diablo_bridge.map_world_to_screen(mouse_world) if diablo_bridge and diablo_bridge.has_method("map_world_to_screen") else Vector2i(int(float(d1_width) * 0.5 + (mouse_world.x - player_node.position.x)), int(float(d1_height) * 0.5 + (mouse_world.y - player_node.position.y)))
		var d1_x = d1_coords.x
		var d1_y = d1_coords.y
		if diablo_bridge and diablo_bridge.has_method("send_input"):
			diablo_bridge.send_input(1, 0, 0, d1_x, d1_y)
		return true

	return false
