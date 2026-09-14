extends Control
class_name D1SettingsDialog

signal closed()
signal settings_saved()

var diablo_bridge: Node = null
var current_category_id: int = 0
var categories: Array = []
var active_cat_btn: Button = null
var is_hungarian: bool = false

@onready var title_label: Label = %TitleLabel
@onready var category_vbox: VBoxContainer = %CategoryVBox
@onready var entries_vbox: VBoxContainer = %EntriesVBox
@onready var desc_label: Label = %DescriptionLabel
@onready var status_label: Label = %StatusLabel
@onready var close_btn: Button = %CloseBtn
@onready var close_x_btn: Button = %CloseXBtn

func set_bridge(bridge: Node) -> void:
	diablo_bridge = bridge
	if diablo_bridge and diablo_bridge.has_method("get_language_code"):
		var code = diablo_bridge.get_language_code().to_lower()
		apply_localization(code.begins_with("hu"))
	refresh_categories()

func apply_localization(is_hu: bool) -> void:
	is_hungarian = is_hu
	if not is_node_ready():
		return
	if title_label:
		title_label.text = "BEÁLLÍTÁSOK" if is_hungarian else "DEVILUTIONX SETTINGS"
	if close_btn:
		close_btn.text = "MENTÉS & BEZÁRÁS" if is_hungarian else "SAVE & CLOSE"
	if desc_label and (desc_label.text.is_empty() or desc_label.text.contains("kategóriát") or desc_label.text.contains("category")):
		desc_label.text = "Válassz ki egy kategóriát az opciók testreszabásához." if is_hungarian else "Select a category on the left to customize options."
	if status_label:
		status_label.text = "A beállítások automatikusan mentésre kerülnek a diablo.ini fájlba." if is_hungarian else "Settings are automatically saved to diablo.ini."

func _ready() -> void:
	if close_btn:
		close_btn.pressed.connect(_on_close_pressed)
	if close_x_btn:
		close_x_btn.pressed.connect(_on_close_pressed)
	apply_localization(is_hungarian)
	if diablo_bridge and category_vbox and category_vbox.get_child_count() == 0:
		refresh_categories()

func _on_close_pressed() -> void:
	if diablo_bridge and diablo_bridge.has_method("save_settings"):
		diablo_bridge.save_settings()
	hide()
	settings_saved.emit()
	closed.emit()

func refresh_categories() -> void:
	if not category_vbox:
		return
	for c in category_vbox.get_children():
		c.queue_free()

	if not diablo_bridge or not diablo_bridge.has_method("get_settings_categories"):
		return

	categories = diablo_bridge.get_settings_categories()
	var first_valid_cat = -1
	for cat in categories:
		var cat_id = int(cat.get("id", 0))
		var cat_name = str(cat.get("name", ""))
		var entries = diablo_bridge.get_settings_entries(cat_id)
		if entries.is_empty():
			continue

		if first_valid_cat == -1:
			first_valid_cat = cat_id

		var btn = Button.new()
		btn.text = "  " + cat_name
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 42)
		btn.add_theme_font_size_override("font_size", 15)
		btn.set_meta("cat_id", cat_id)
		btn.pressed.connect(func(): _select_category(cat_id, btn))
		btn.mouse_entered.connect(func():
			if desc_label:
				desc_label.text = str(cat.get("description", ""))
		)
		category_vbox.add_child(btn)

	if first_valid_cat != -1:
		var first_btn = category_vbox.get_child(0) as Button if category_vbox.get_child_count() > 0 else null
		_select_category(first_valid_cat, first_btn)

func _select_category(cat_id: int, btn: Button = null) -> void:
	current_category_id = cat_id
	active_cat_btn = btn

	for i in range(category_vbox.get_child_count()):
		var b = category_vbox.get_child(i) as Button
		if b:
			var is_active = (b == btn)
			b.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35, 1.0) if is_active else Color(0.8, 0.8, 0.8, 1.0))

	_populate_entries(cat_id)

func _populate_entries(cat_id: int) -> void:
	if not entries_vbox:
		return
	for c in entries_vbox.get_children():
		c.queue_free()

	if not diablo_bridge or not diablo_bridge.has_method("get_settings_entries"):
		return

	var entries = diablo_bridge.get_settings_entries(cat_id)
	for entry in entries:
		var entry_id = int(entry.get("id", 0))
		var name_str = str(entry.get("name", ""))
		var desc_str = str(entry.get("description", ""))
		var entry_type = int(entry.get("type", 0)) # 0: Bool, 1: List, 2: Key, 3: Pad
		var val_str = str(entry.get("value_str", ""))
		var bool_val = bool(entry.get("bool_val", false))
		var list_opts = entry.get("list_options", [])
		var list_idx = int(entry.get("list_index", 0))

		var panel = PanelContainer.new()
		panel.custom_minimum_size = Vector2(0, 44)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.08, 0.08, 0.10, 0.75)
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_right = 4
		style.corner_radius_bottom_left = 4
		style.content_margin_left = 12
		style.content_margin_right = 12
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		panel.add_theme_stylebox_override("panel", style)

		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 16)
		panel.add_child(row)

		var name_lbl = Label.new()
		name_lbl.text = name_str
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.6, 1.0))
		name_lbl.add_theme_font_size_override("font_size", 15)
		row.add_child(name_lbl)

		if entry_type == 0: # Boolean
			var chk = CheckBox.new()
			var on_text = " BE" if is_hungarian else " ON"
			var off_text = " KI" if is_hungarian else " OFF"
			chk.text = on_text if bool_val else off_text
			chk.button_pressed = bool_val
			chk.toggled.connect(func(pressed):
				chk.text = ( " BE" if is_hungarian else " ON" ) if pressed else ( " KI" if is_hungarian else " OFF" )
				if diablo_bridge and diablo_bridge.has_method("set_setting_bool"):
					diablo_bridge.set_setting_bool(cat_id, entry_id, pressed)
				if status_label:
					var state_label = ("BE" if is_hungarian else "ON") if pressed else ("KI" if is_hungarian else "OFF")
					var fmt = "Módosítva: %s -> %s" if is_hungarian else "Changed: %s -> %s"
					status_label.text = fmt % [name_str, state_label]
			)
			chk.mouse_entered.connect(func():
				if desc_label: desc_label.text = desc_str
			)
			row.add_child(chk)
		elif entry_type == 1: # List
			var opt_btn = OptionButton.new()
			opt_btn.custom_minimum_size = Vector2(260, 36)
			for o_idx in range(list_opts.size()):
				opt_btn.add_item(str(list_opts[o_idx]), o_idx)
			if list_idx >= 0 and list_idx < list_opts.size():
				opt_btn.selected = list_idx
			opt_btn.item_selected.connect(func(sel_idx):
				if diablo_bridge and diablo_bridge.has_method("set_setting_list"):
					diablo_bridge.set_setting_list(cat_id, entry_id, sel_idx)
				if status_label:
					var opt_name = list_opts[sel_idx] if sel_idx < list_opts.size() else str(sel_idx)
					var fmt = "Módosítva: %s -> %s" if is_hungarian else "Changed: %s -> %s"
					status_label.text = fmt % [name_str, opt_name]
				var lower_name = name_str.to_lower()
				if lower_name.contains("mód") or lower_name.contains("mode") or lower_name.contains("nyelv") or lower_name.contains("lang"):
					refresh_categories()
			)
			opt_btn.mouse_entered.connect(func():
				if desc_label: desc_label.text = desc_str
			)
			row.add_child(opt_btn)
		else: # Key / Pad mapping
			var val_lbl = Label.new()
			val_lbl.text = "[ " + val_str + " ]" if not val_str.is_empty() else "[ - ]"
			val_lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0, 1.0))
			val_lbl.add_theme_font_size_override("font_size", 14)
			row.add_child(val_lbl)

		panel.mouse_entered.connect(func():
			if desc_label: desc_label.text = desc_str
		)
		entries_vbox.add_child(panel)
