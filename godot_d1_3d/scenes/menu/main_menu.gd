extends Control

signal game_launched(save_num: int, difficulty: int, load_saved: bool)

enum MenuState { MAIN_MENU, CHARACTER_SELECT, CHARACTER_CREATE }
var current_state: int = MenuState.MAIN_MENU

var diablo_bridge: Node = null
var is_hungarian: bool = false
var is_hellfire_mode: bool = true

@onready var campfire_scene: Node = %CampfireScene
@onready var main_buttons_panel: Control = %MainButtonsPanel
@onready var character_select: Node = %CharacterSelect
@onready var character_create: Node = %CharacterCreate
@onready var settings_dialog: Node = %SettingsDialog

@onready var logo_texture: TextureRect = %LogoTexture
@onready var btn_single_player: Button = %BtnSinglePlayer
@onready var btn_multiplayer: Button = %BtnMultiplayer
@onready var btn_settings: Button = %BtnSettings
@onready var btn_credits: Button = %BtnCredits
@onready var btn_exit: Button = %BtnExit

static func load_img_texture(res_path: String) -> ImageTexture:
	var global = ProjectSettings.globalize_path(res_path)
	if FileAccess.file_exists(global):
		var img = Image.load_from_file(global)
		if img and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null

func _update_logo() -> void:
	if not logo_texture:
		return
	if is_hellfire_mode:
		logo_texture.texture = load_img_texture("res://assets/menu/hellfire_logo.png")
	else:
		logo_texture.texture = load_img_texture("res://assets/menu/diablo_logo.png")

func apply_localization(is_hu: bool) -> void:
	is_hungarian = is_hu
	if not is_node_ready():
		return
	if btn_single_player:
		btn_single_player.text = "EGYJÁTÉKOS MÓD" if is_hungarian else "SINGLE PLAYER"
	if btn_multiplayer:
		btn_multiplayer.text = "TÖBBJÁTÉKOS MÓD" if is_hungarian else "MULTIPLAYER"
	if btn_settings:
		btn_settings.text = "JÁTÉK BEÁLLÍTÁSOK" if is_hungarian else "GAME SETTINGS"
	if btn_credits:
		btn_credits.text = "KÉSZÍTŐK" if is_hungarian else "CREDITS"
	if btn_exit:
		btn_exit.text = "KILÉPÉS" if is_hungarian else "EXIT GAME"

	if character_select and character_select.has_method("apply_localization"):
		character_select.apply_localization(is_hungarian)
	if character_create and character_create.has_method("apply_localization"):
		character_create.apply_localization(is_hungarian)
	if settings_dialog and settings_dialog.has_method("apply_localization"):
		settings_dialog.apply_localization(is_hungarian)

func set_bridge(bridge: Node) -> void:
	diablo_bridge = bridge

	if diablo_bridge and diablo_bridge.has_method("is_hellfire"):
		is_hellfire_mode = diablo_bridge.is_hellfire()
	_update_logo()

	var lang_code = ""
	if diablo_bridge and diablo_bridge.has_method("get_language_code"):
		lang_code = diablo_bridge.get_language_code().to_lower()
	apply_localization(lang_code.begins_with("hu"))

	if character_select and character_select.has_method("set_bridge"):
		character_select.set_bridge(diablo_bridge)
	if character_create and character_create.has_method("set_bridge"):
		character_create.set_bridge(diablo_bridge)
	if settings_dialog and settings_dialog.has_method("set_bridge"):
		settings_dialog.set_bridge(diablo_bridge)

func _ready() -> void:
	_update_logo()

	# Diagnosztika: null-e valamelyik gomb?
	print("[MainMenu] _ready: btn_single_player=%s btn_multiplayer=%s btn_settings=%s btn_credits=%s btn_exit=%s" % [
		btn_single_player != null, btn_multiplayer != null, btn_settings != null,
		btn_credits != null, btn_exit != null])

	if btn_single_player:
		btn_single_player.pressed.connect(_on_single_player_pressed)
	if btn_multiplayer:
		btn_multiplayer.pressed.connect(_on_multiplayer_pressed)
	if btn_settings:
		btn_settings.pressed.connect(_on_settings_pressed)
	if btn_credits:
		btn_credits.pressed.connect(_on_credits_pressed)
	if btn_exit:
		btn_exit.pressed.connect(_on_exit_pressed)

	if character_select:
		character_select.connect("hero_focused", _on_hero_focused)
		character_select.connect("play_requested", _on_play_requested)
		character_select.connect("create_hero_requested", _on_create_hero_requested)
		character_select.connect("back_requested", _on_select_back_pressed)

	if character_create:
		character_create.connect("class_focused", _on_hero_focused)
		character_create.connect("hero_created", _on_hero_created_done)
		character_create.connect("cancelled", _on_create_cancelled)

	if settings_dialog and settings_dialog.has_signal("settings_saved"):
		settings_dialog.connect("settings_saved", _on_settings_saved)

	apply_localization(is_hungarian)
	_apply_state(MenuState.MAIN_MENU)

func _on_settings_saved() -> void:
	if diablo_bridge and diablo_bridge.has_method("is_hellfire"):
		is_hellfire_mode = diablo_bridge.is_hellfire()
		_update_logo()
	if diablo_bridge and diablo_bridge.has_method("get_language_code"):
		var code = diablo_bridge.get_language_code().to_lower()
		apply_localization(code.begins_with("hu"))
	if character_create and character_create.has_method("update_available_classes"):
		character_create.update_available_classes()
	if character_select and character_select.has_method("refresh_hero_list"):
		character_select.refresh_hero_list()

func _apply_state(state: int) -> void:
	current_state = state
	main_buttons_panel.visible = (state == MenuState.MAIN_MENU)
	character_select.visible = (state == MenuState.CHARACTER_SELECT)
	character_create.visible = (state == MenuState.CHARACTER_CREATE)

	if state == MenuState.MAIN_MENU:
		if diablo_bridge and diablo_bridge.has_method("is_hellfire"):
			is_hellfire_mode = diablo_bridge.is_hellfire()
			_update_logo()
		if diablo_bridge and diablo_bridge.has_method("get_language_code"):
			var code = diablo_bridge.get_language_code().to_lower()
			apply_localization(code.begins_with("hu"))

	if campfire_scene:
		if campfire_scene.has_method("set_menu_state"):
			campfire_scene.set_menu_state(state)
		elif campfire_scene.has_method("focus_side"):
			campfire_scene.focus_side(state == MenuState.CHARACTER_CREATE)

	if state == MenuState.CHARACTER_SELECT:
		if character_select and character_select.has_method("refresh_hero_list"):
			character_select.refresh_hero_list()
	elif state == MenuState.CHARACTER_CREATE:
		if character_create and character_create.has_method("update_available_classes"):
			character_create.update_available_classes()

func _on_single_player_pressed() -> void:
	if not diablo_bridge:
		return
	if diablo_bridge.has_method("menu_select_single_player"):
		diablo_bridge.menu_select_single_player()
	_apply_state(MenuState.CHARACTER_SELECT)

func _on_settings_pressed() -> void:
	if settings_dialog:
		settings_dialog.show()
		if settings_dialog.has_method("refresh_categories"):
			settings_dialog.refresh_categories()

func _on_exit_pressed() -> void:
	if diablo_bridge and diablo_bridge.has_method("menu_exit_game"):
		diablo_bridge.menu_exit_game()
	get_tree().quit()

func _on_hero_focused(class_id: int) -> void:
	if campfire_scene and campfire_scene.has_method("set_hero_class"):
		campfire_scene.set_hero_class(class_id)

func _on_play_requested(save_num: int, difficulty: int, load_saved: bool) -> void:
	if diablo_bridge and diablo_bridge.has_method("launch_hero_game"):
		diablo_bridge.launch_hero_game(save_num, difficulty, load_saved)
	game_launched.emit(save_num, difficulty, load_saved)
	hide()

func _on_create_hero_requested() -> void:
	_apply_state(MenuState.CHARACTER_CREATE)

func _on_select_back_pressed() -> void:
	if diablo_bridge and diablo_bridge.has_method("cancel_hero_select"):
		diablo_bridge.cancel_hero_select()
	_apply_state(MenuState.MAIN_MENU)

func _on_hero_created_done(_save_num: int) -> void:
	_apply_state(MenuState.CHARACTER_SELECT)

func _on_create_cancelled() -> void:
	_apply_state(MenuState.CHARACTER_SELECT)

func _on_multiplayer_pressed() -> void:
	if diablo_bridge and diablo_bridge.has_method("menu_select_multiplayer"):
		diablo_bridge.menu_select_multiplayer()
		# Megjelenítjük a hős-választó UI-t – az engine a bridge-en keresztül vár rá
		_apply_state(MenuState.CHARACTER_SELECT)

func _on_credits_pressed() -> void:
	if diablo_bridge and diablo_bridge.has_method("menu_show_credits"):
		diablo_bridge.menu_show_credits()
	# Natív Godot credits popup (az SDL credits képernyő bridge módban ki van hagyva)
	var dlg = AcceptDialog.new()
	dlg.title = "Készítők" if is_hungarian else "Credits"
	dlg.dialog_text = (
		"DIABLO 1 RESURRECTED\n\n" +
		("Fejlesztő: biti\nMotor: Godot 4.7 + DevilutionX\n\nKöszönet a DevilutionX csapatnak\naz eredeti Diablo engine\nnyílt forráskódú újraírásáért."
		if is_hungarian else
		"Developer: biti\nEngine: Godot 4.7 + DevilutionX\n\nSpecial Thanks to the DevilutionX team\nfor the open-source reimplementation\nof the original Diablo engine.")
	)
	dlg.confirmed.connect(func(): dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered()
