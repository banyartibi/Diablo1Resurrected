extends Control

@onready var bg_rect: TextureRect = $BackgroundPlate
@onready var campfire_flames: ColorRect = $CampfireFlames
@onready var hero_display: TextureRect = $HeroDisplay
@onready var embers_rect: ColorRect = $EmbersPlume

var class_textures: Array[ImageTexture] = []

static func load_img_texture(res_path: String) -> ImageTexture:
	var global = ProjectSettings.globalize_path(res_path)
	if FileAccess.file_exists(global):
		var img = Image.load_from_file(global)
		if img and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null

func _ready() -> void:
	if bg_rect and not bg_rect.texture:
		bg_rect.texture = load_img_texture("res://assets/menu/campfire_bg.png")

	var paths = [
		"res://assets/menu/hero_warrior.png",
		"res://assets/menu/hero_rogue.png",
		"res://assets/menu/hero_sorcerer.png",
		"res://assets/menu/hero_monk.png",
		"res://assets/menu/hero_bard.png",
		"res://assets/menu/hero_barbarian.png"
	]
	for p in paths:
		class_textures.append(load_img_texture(p))

	# By default on main menu, hero is hidden
	if hero_display:
		hero_display.visible = false

func set_hero_class(class_id: int) -> void:
	if class_id < 0 or class_id >= class_textures.size():
		if hero_display:
			hero_display.visible = false
		return
	if class_textures.is_empty():
		return
	if hero_display:
		hero_display.visible = true
	var c = clampi(class_id, 0, class_textures.size() - 1)
	if hero_display and class_textures[c] != null:
		hero_display.texture = class_textures[c]
		var tween = create_tween()
		hero_display.scale = Vector2(0.96, 0.96)
		tween.tween_property(hero_display, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# menu_mode: 0 = MAIN_MENU, 1 = CHARACTER_SELECT, 2 = CHARACTER_CREATE
func set_menu_state(state: int) -> void:
	if not hero_display:
		return
	
	if state == 0: # MAIN_MENU
		hero_display.visible = false
		return
	
	hero_display.visible = true
	var mat = hero_display.material as ShaderMaterial
	
	if state == 1 or state == 2: # CHARACTER_SELECT or CHARACTER_CREATE
		# Standing on the open cobblestone road on the right (as circled by user):
		# anchor_left = 0.52, anchor_right = 0.77
		# fire is on the hero's left (viewer's left)
		var tween = create_tween().set_parallel(true)
		tween.tween_property(hero_display, "anchor_left", 0.52, 0.35).set_trans(Tween.TRANS_SINE)
		tween.tween_property(hero_display, "anchor_right", 0.77, 0.35).set_trans(Tween.TRANS_SINE)
		tween.tween_property(hero_display, "anchor_top", 0.20, 0.35).set_trans(Tween.TRANS_SINE)
		tween.tween_property(hero_display, "anchor_bottom", 0.94, 0.35).set_trans(Tween.TRANS_SINE)
		if mat:
			mat.set_shader_parameter("fire_side", -1.0)

# Backward compatibility with focus_side
func focus_side(is_character_create: bool) -> void:
	set_menu_state(2 if is_character_create else 1)
