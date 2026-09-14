extends Control
class_name D1CharacterSelect

signal hero_focused(class_id: int)
signal play_requested(save_num: int, difficulty: int, load_saved: bool)
signal create_hero_requested()
signal back_requested()

var diablo_bridge: Node = null
var hero_list: Array = []
var selected_index: int = -1
var selected_difficulty: int = 0 # 0 = Normal, 1 = Nightmare, 2 = Hell
var is_hungarian: bool = false

@onready var title_label: Label = %TitleLabel
@onready var hero_vbox: VBoxContainer = %HeroVBox
@onready var hero_name_label: Label = %SelectedHeroName
@onready var hero_class_level: Label = %SelectedHeroClassLevel

@onready var attributes_title: Label = %AttributesTitle
@onready var str_label: Label = %StrLabel
@onready var mag_label: Label = %MagLabel
@onready var dex_label: Label = %DexLabel
@onready var vit_label: Label = %VitLabel

@onready var stat_str_val: Label = %StatStrVal
@onready var stat_mag_val: Label = %StatMagVal
@onready var stat_dex_val: Label = %StatDexVal
@onready var stat_vit_val: Label = %StatVitVal

@onready var stat_str_bar: ProgressBar = %StatStrBar
@onready var stat_mag_bar: ProgressBar = %StatMagBar
@onready var stat_dex_bar: ProgressBar = %StatDexBar
@onready var stat_vit_bar: ProgressBar = %StatVitBar

@onready var difficulty_title: Label = %DifficultyTitle
@onready var diff_normal_btn: Button = %DiffNormalBtn
@onready var diff_nightmare_btn: Button = %DiffNightmareBtn
@onready var diff_hell_btn: Button = %DiffHellBtn

@onready var play_button: Button = %PlayButton
@onready var delete_button: Button = %DeleteButton
@onready var create_button: Button = %CreateButton
@onready var back_button: Button = %BackButton

@onready var delete_confirm_dialog: ConfirmationDialog = %DeleteConfirmDialog

const CLASS_NAMES_HU = ["Harcos", "Íjásznő", "Varázsló", "Szerzetes", "Bárd", "Barbár"]
const CLASS_NAMES_EN = ["Warrior", "Rogue", "Sorcerer", "Monk", "Bard", "Barbarian"]

func get_localized_class_name(class_id: int) -> String:
	var list = CLASS_NAMES_HU if is_hungarian else CLASS_NAMES_EN
	if class_id >= 0 and class_id < list.size():
		return list[class_id]
	return "Hero" if not is_hungarian else "Hős"

func set_bridge(bridge: Node) -> void:
	diablo_bridge = bridge
	if diablo_bridge and diablo_bridge.has_method("get_language_code"):
		var code = diablo_bridge.get_language_code().to_lower()
		apply_localization(code.begins_with("hu"))

func apply_localization(is_hu: bool) -> void:
	is_hungarian = is_hu
	if not is_node_ready():
		return
	if title_label:
		title_label.text = "HŐS VÁLASZTÁS" if is_hungarian else "SELECT HERO"
	if attributes_title:
		attributes_title.text = "TULAJDONSÁGOK" if is_hungarian else "ATTRIBUTES"
	if str_label:
		str_label.text = "Erő:" if is_hungarian else "Strength:"
	if mag_label:
		mag_label.text = "Mágia:" if is_hungarian else "Magic:"
	if dex_label:
		dex_label.text = "Ügyesség:" if is_hungarian else "Dexterity:"
	if vit_label:
		vit_label.text = "Vitalitás:" if is_hungarian else "Vitality:"
	if difficulty_title:
		difficulty_title.text = "NEHÉZSÉG" if is_hungarian else "DIFFICULTY"
	if play_button:
		play_button.text = "⚔ BELÉPÉS SANCTUARYBE ⚔" if is_hungarian else "⚔ ENTER SANCTUARY ⚔"
	if create_button:
		create_button.text = "+ ÚJ HŐS" if is_hungarian else "+ NEW HERO"
	if delete_button:
		delete_button.text = "TÖRLÉS" if is_hungarian else "DELETE"
	if back_button:
		back_button.text = "VISSZA" if is_hungarian else "BACK"
	if diff_normal_btn:
		diff_normal_btn.text = "Normál" if is_hungarian else "Normal"
	if diff_nightmare_btn:
		diff_nightmare_btn.text = "Rémálom" if is_hungarian else "Nightmare"
	if diff_hell_btn:
		diff_hell_btn.text = "Pokol" if is_hungarian else "Hell"
	if delete_confirm_dialog:
		delete_confirm_dialog.title = "Hős Törlése" if is_hungarian else "Delete Hero"
		delete_confirm_dialog.ok_button_text = "Igen, Törlöm" if is_hungarian else "Yes, Delete"
		delete_confirm_dialog.cancel_button_text = "Mégsem" if is_hungarian else "Cancel"

	if not hero_list.is_empty() and selected_index >= 0:
		select_hero(selected_index)
	elif hero_list.is_empty():
		if hero_name_label: hero_name_label.text = "Nincs mentett hős" if is_hungarian else "No Hero Found"
		if hero_class_level: hero_class_level.text = "Hozz létre egy új karaktert!" if is_hungarian else "Create a new hero to begin!"

func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	create_button.pressed.connect(_on_create_pressed)
	delete_button.pressed.connect(_on_delete_pressed)
	back_button.pressed.connect(_on_back_pressed)
	diff_normal_btn.pressed.connect(func(): _set_difficulty(0))
	diff_nightmare_btn.pressed.connect(func(): _set_difficulty(1))
	diff_hell_btn.pressed.connect(func(): _set_difficulty(2))
	delete_confirm_dialog.confirmed.connect(_on_delete_confirmed)
	_set_difficulty(0)
	apply_localization(is_hungarian)

func _create_hero_card_style(is_selected: bool) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	if is_selected:
		s.bg_color = Color(0.24, 0.14, 0.05, 0.92)
		s.border_color = Color(1.0, 0.84, 0.32, 1.0)
		s.border_width_left = 2
		s.border_width_top = 2
		s.border_width_right = 2
		s.border_width_bottom = 2
	else:
		s.bg_color = Color(0.08, 0.07, 0.10, 0.80)
		s.border_color = Color(0.50, 0.42, 0.22, 0.6)
		s.border_width_left = 1
		s.border_width_top = 1
		s.border_width_right = 1
		s.border_width_bottom = 1
	s.corner_radius_top_left = 4
	s.corner_radius_top_right = 4
	s.corner_radius_bottom_right = 4
	s.corner_radius_bottom_left = 4
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s

func refresh_hero_list() -> void:
	for c in hero_vbox.get_children():
		hero_vbox.remove_child(c)
		c.queue_free()
	hero_list.clear()

	var raw_heroes: Array = []
	if diablo_bridge and diablo_bridge.has_method("get_hero_list"):
		for attempt in range(15):
			if diablo_bridge.has_method("get_menu_mode") and diablo_bridge.get_menu_mode() == 2:
				raw_heroes = diablo_bridge.get_hero_list()
				break
			OS.delay_msec(20)
		if raw_heroes.is_empty() and diablo_bridge.has_method("get_hero_list"):
			raw_heroes = diablo_bridge.get_hero_list()

	for h in raw_heroes:
		var c_id = int(h.get("class_id", 0))
		if diablo_bridge and diablo_bridge.has_method("is_class_allowed"):
			if not diablo_bridge.is_class_allowed(c_id):
				continue
		hero_list.append(h)

	if hero_list.is_empty():
		selected_index = -1
		play_button.disabled = true
		delete_button.disabled = true
		hero_name_label.text = "Nincs mentett hős" if is_hungarian else "No Hero Found"
		hero_class_level.text = "Hozz létre egy új karaktert!" if is_hungarian else "Create a new hero to begin!"
		stat_str_val.text = "--"
		stat_mag_val.text = "--"
		stat_dex_val.text = "--"
		stat_vit_val.text = "--"
		if stat_str_bar: stat_str_bar.value = 0
		if stat_mag_bar: stat_mag_bar.value = 0
		if stat_dex_bar: stat_dex_bar.value = 0
		if stat_vit_bar: stat_vit_bar.value = 0
		hero_focused.emit(-1)
		return

	for i in range(hero_list.size()):
		var h = hero_list[i]
		var c_id = int(h.get("class_id", 0))
		var c_name = get_localized_class_name(c_id)
		var lvl = int(h.get("level", 1))
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(0, 52)
		if is_hungarian:
			btn.text = "%s - %d. szint %s" % [h.get("name", "Unknown"), lvl, c_name]
		else:
			btn.text = "%s - Level %d %s" % [h.get("name", "Unknown"), lvl, c_name]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 16)
		btn.add_theme_stylebox_override("normal", _create_hero_card_style(false))
		btn.add_theme_stylebox_override("hover", _create_hero_card_style(true))
		btn.add_theme_stylebox_override("pressed", _create_hero_card_style(true))
		btn.add_theme_color_override("font_color", Color(0.85, 0.85, 0.88, 1.0))
		btn.pressed.connect(func(): select_hero(i))
		hero_vbox.add_child(btn)

	# Auto-select the first hero
	select_hero(0)

func select_hero(idx: int) -> void:
	if idx < 0 or idx >= hero_list.size():
		return
	selected_index = idx
	var h = hero_list[idx]
	var c_id = int(h.get("class_id", 0))
	var c_name = get_localized_class_name(c_id)
	var lvl = int(h.get("level", 1))

	hero_name_label.text = h.get("name", "Unknown")
	if is_hungarian:
		hero_class_level.text = "%d. szint %s" % [lvl, c_name]
	else:
		hero_class_level.text = "Level %d %s" % [lvl, c_name]

	var s_str = int(h.get("strength", 0))
	var s_mag = int(h.get("magic", 0))
	var s_dex = int(h.get("dexterity", 0))
	var s_vit = int(h.get("vitality", 0))

	stat_str_val.text = str(s_str)
	stat_mag_val.text = str(s_mag)
	stat_dex_val.text = str(s_dex)
	stat_vit_val.text = str(s_vit)

	if stat_str_bar: stat_str_bar.value = s_str
	if stat_mag_bar: stat_mag_bar.value = s_mag
	if stat_dex_bar: stat_dex_bar.value = s_dex
	if stat_vit_bar: stat_vit_bar.value = s_vit

	play_button.disabled = false
	delete_button.disabled = false

	# Highlight active button
	for i in range(hero_vbox.get_child_count()):
		var b = hero_vbox.get_child(i) as Button
		if b:
			var is_sel = (i == idx)
			b.add_theme_stylebox_override("normal", _create_hero_card_style(is_sel))
			if is_sel:
				b.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6, 1.0))
			else:
				b.add_theme_color_override("font_color", Color(0.85, 0.85, 0.88, 1.0))

	hero_focused.emit(c_id)

func _set_difficulty(diff: int) -> void:
	selected_difficulty = diff
	diff_normal_btn.button_pressed = (diff == 0)
	diff_nightmare_btn.button_pressed = (diff == 1)
	diff_hell_btn.button_pressed = (diff == 2)

func _on_play_pressed() -> void:
	if selected_index < 0 or selected_index >= hero_list.size():
		return
	var h = hero_list[selected_index]
	var save_num = h.get("save_num", 0)
	var has_saved = h.get("has_saved", false)
	play_requested.emit(save_num, selected_difficulty, has_saved)

func _on_create_pressed() -> void:
	create_hero_requested.emit()

func _on_delete_pressed() -> void:
	if selected_index < 0 or selected_index >= hero_list.size():
		return
	var h = hero_list[selected_index]
	if is_hungarian:
		delete_confirm_dialog.dialog_text = "Biztosan törölni szeretnéd a(z) %s nevű hőst? Ez a művelet visszavonhatatlan!" % h.get("name", "Unknown")
	else:
		delete_confirm_dialog.dialog_text = "Are you sure you want to delete %s? This action cannot be undone!" % h.get("name", "Unknown")
	delete_confirm_dialog.popup_centered()

func _on_delete_confirmed() -> void:
	if selected_index < 0 or selected_index >= hero_list.size():
		return
	var h = hero_list[selected_index]
	if diablo_bridge and diablo_bridge.has_method("delete_hero"):
		diablo_bridge.delete_hero(h.get("save_num", 0))
	refresh_hero_list()

func _on_back_pressed() -> void:
	back_requested.emit()
