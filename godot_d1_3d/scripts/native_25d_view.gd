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
var player_arrow: Line2D = null
var canvas_modulate: CanvasModulate = null

# State tracking
var last_level_idx: int = -999
var tile_sprites: Dictionary = {} # Vector2i -> Sprite2D
var last_player_frame: int = -999
var last_player_dir: int = -999
var player_texture: ImageTexture = null

# Monster tracking
var monster_nodes: Dictionary = {} # int -> Node2D
var monster_textures: Dictionary = {} # int -> ImageTexture
var monster_last_frame: Dictionary = {}
var monster_last_dir: Dictionary = {}

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
	# 2D World Root with Y-sorting
	world_root = Node2D.new()
	world_root.name = "WorldRoot"
	world_root.y_sort_enabled = true
	add_child(world_root)

	# Atmospheric Gothic Crypt Canvas Modulate
	canvas_modulate = CanvasModulate.new()
	canvas_modulate.name = "CryptModulate"
	canvas_modulate.color = Color(0.12, 0.12, 0.16)
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

func setup_player_node():
	player_node = Node2D.new()
	player_node.name = "PlayerEntity"
	player_node.z_index = 0
	world_root.add_child(player_node)

	# Hero Sprite2D (authentic animated Diablo 1 pixel art)
	player_sprite = Sprite2D.new()
	player_sprite.name = "PlayerSprite"
	player_sprite.centered = true
	player_node.add_child(player_sprite)

	# Hero Facing Direction Arrow
	player_arrow = Line2D.new()
	player_arrow.name = "HeroArrow"
	player_arrow.points = PackedVector2Array([Vector2.ZERO, Vector2(0, 24)])
	player_arrow.width = 2.5
	player_arrow.default_color = Color(1.0, 0.85, 0.25, 0.65)
	player_node.add_child(player_arrow)

	# Hero Torch Light (PointLight2D with soft radial falloff)
	player_light = PointLight2D.new()
	player_light.name = "HeroTorchLight"
	player_light.texture = create_radial_light_texture(512)
	player_light.texture_scale = 2.4
	player_light.color = Color(1.0, 0.74, 0.42) # Warm candlelight/torch
	player_light.energy = 1.35
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

	time_accum += delta

	# Check level change
	if diablo_bridge.has_method("get_current_level"):
		var cur_lvl = diablo_bridge.get_current_level()
		if cur_lvl != last_level_idx:
			last_level_idx = cur_lvl
			if diablo_bridge.has_method("clear_dungeon_piece_cache"):
				diablo_bridge.clear_dungeon_piece_cache()
			rebuild_dungeon_tiles()

	update_player(delta)
	update_monsters(delta)
	update_torches()

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

	var count = 0
	for y in range(112):
		for x in range(112):
			var piece_id = grid[y * 112 + x]
			if piece_id <= 0:
				continue

			var tex: Texture2D = null
			if diablo_bridge.has_method("get_dungeon_piece_texture"):
				tex = diablo_bridge.get_dungeon_piece_texture(piece_id)
			if tex == null:
				continue

			var spr = Sprite2D.new()
			spr.texture = tex
			spr.centered = false
			var h = tex.get_height()

			# Isometric tile diamond position
			var tile_pos = Vector2(float(x - y) * 32.0, float(x + y) * 16.0)
			spr.position = tile_pos

			# Bottom 32px floor diamond centered at tile_pos:
			# X: -32px, Y: 16px - height
			spr.offset = Vector2(-32.0, 16.0 - float(h))

			# Flat floors (height == 32) stay underneath everything (z_index = -1)
			# Wall / pillar pieces (height > 32) Y-sort with player and monsters at z_index = 0
			if h <= 32:
				spr.z_index = -1
			else:
				spr.z_index = 0

			world_root.add_child(spr)
			tile_sprites[Vector2i(x, y)] = spr
			count += 1

	print("[Native 2.5D View] Rebuilt %d dungeon tiles" % count)

func update_player(delta: float):
	if not diablo_bridge or not diablo_bridge.has_method("get_player_continuous_pos"):
		return

	var p_data = diablo_bridge.get_player_continuous_pos()
	var px = p_data.get("pos_x", 25.0)
	var py = p_data.get("pos_y", 25.0)
	var dir = p_data.get("dir", 0)
	var anim_frame = p_data.get("anim_frame", -1)

	# Target position in isometric coordinates
	player_target_pos = Vector2(float(px - py) * 32.0, float(px + py) * 16.0)
	player_node.position = player_node.position.lerp(player_target_pos, delta * 14.0)

	# Smooth camera follow
	if camera:
		camera.position = camera.position.lerp(player_node.position, delta * 12.0)

	# Facing arrow direction (Diablo 1 uses 8 directions: 0 = S, 1 = SW, 2 = W, etc.)
	# In isometric space, angle = dir * 45 deg - 90 deg
	var angle_rad = float(dir) * (PI / 4.0) - (PI / 2.0)
	player_arrow.rotation = angle_rad

	# Torch light breathing flicker
	if player_light:
		var flicker = 1.30 + 0.08 * sin(time_accum * 5.4) * cos(time_accum * 2.8)
		player_light.energy = flicker

	# Update animated player sprite
	if diablo_bridge.has_method("get_player_sprite_data"):
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
				# Offset so player feet rest precisely in the center of the diamond
				player_sprite.offset = Vector2(0, -float(sh) * 0.5 + 16.0)

func update_monsters(delta: float):
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

		var target_pos = Vector2(float(mx - my) * 32.0, float(mx + my) * 16.0)
		node.position = node.position.lerp(target_pos, delta * 12.0)

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

					# Adjust overhead HP bar height
					var hp_bar = node.get_node_or_null("HPBar") as ProgressBar
					if hp_bar:
						hp_bar.position.y = -float(mh) - 8.0

		# Update HP Bar value & gradient
		var hp_bar = node.get_node_or_null("HPBar") as ProgressBar
		if hp_bar:
			hp_bar.max_value = max_hp
			hp_bar.value = hp

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

	var spr = Sprite2D.new()
	spr.name = "Sprite"
	spr.centered = true
	m_root.add_child(spr)

	var hp_bar = ProgressBar.new()
	hp_bar.name = "HPBar"
	hp_bar.size = Vector2(36, 4)
	hp_bar.position = Vector2(-18, -48)
	hp_bar.show_percentage = false
	m_root.add_child(hp_bar)

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
		pl.texture_scale = 1.8
		pl.color = Color(1.0, 0.65, 0.28)
		pl.energy = 1.2
		world_root.add_child(pl)
		torch_lights.append(pl)

	for i in range(torch_lights.size()):
		if i < needed:
			var l = lights[i]
			var tx = l.get("tile_x", 0)
			var ty = l.get("tile_y", 0)
			var pl: PointLight2D = torch_lights[i]
			pl.visible = true
			pl.position = Vector2(float(tx - ty) * 32.0, float(tx + ty) * 16.0)
			var flicker = 1.15 + 0.12 * sin(time_accum * 4.8 + float(i))
			pl.energy = flicker
		else:
			torch_lights[i].visible = false

func handle_input(event: InputEvent) -> bool:
	if not is_active:
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
		var delta_world = get_global_mouse_position() - player_node.position
		var d1_x = int(float(d1_width) * 0.5 + delta_world.x)
		var d1_y = int(float(d1_height) * 0.5 + delta_world.y)
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
		var delta_world = get_global_mouse_position() - player_node.position
		var d1_x = int(float(d1_width) * 0.5 + delta_world.x)
		var d1_y = int(float(d1_height) * 0.5 + delta_world.y)
		if diablo_bridge and diablo_bridge.has_method("send_input"):
			diablo_bridge.send_input(1, 0, 0, d1_x, d1_y)
		return true

	return false
