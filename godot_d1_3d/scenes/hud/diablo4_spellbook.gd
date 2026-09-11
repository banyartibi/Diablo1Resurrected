extends Control

var diablo_bridge = null

# Node references
@onready var close_btn: Button = find_child("CloseBtn", true, false)
@onready var entries_vbox: VBoxContainer = find_child("EntriesVBox", true, false)
@onready var tabs_hbox: HBoxContainer = find_child("TabsHBox", true, false)

var last_page: int = -1
var last_inv_version: int = -1

func _ready():
	if close_btn:
		close_btn.pressed.connect(func():
			if diablo_bridge and diablo_bridge.has_method("toggle_spell_book"):
				diablo_bridge.toggle_spell_book()
			visible = false
		)

	_init_tabs()

func set_bridge(bridge):
	diablo_bridge = bridge
	update_spellbook()

func _init_tabs():
	if not tabs_hbox:
		return
	for i in range(5):
		var btn = Button.new()
		btn.text = "%d" % (i + 1)
		btn.custom_minimum_size = Vector2(36, 28)
		btn.focus_mode = Control.FOCUS_NONE
		var tab_idx = i
		btn.pressed.connect(func():
			if diablo_bridge and diablo_bridge.has_method("set_spell_book_page"):
				diablo_bridge.set_spell_book_page(tab_idx)
				update_spellbook()
		)
		tabs_hbox.add_child(btn)

func check_and_update():
	if not diablo_bridge:
		return
	var cur_page = -1
	if diablo_bridge.has_method("get_spell_book_page"):
		cur_page = diablo_bridge.get_spell_book_page()

	var ver = 0
	if diablo_bridge.has_method("get_inventory_version"):
		ver = diablo_bridge.get_inventory_version()

	if cur_page != last_page or ver != last_inv_version:
		update_spellbook()

func update_spellbook():
	if not diablo_bridge:
		return

	var cur_page = 0
	if diablo_bridge.has_method("get_spell_book_page"):
		cur_page = diablo_bridge.get_spell_book_page()
		last_page = cur_page

	if diablo_bridge.has_method("get_inventory_version"):
		last_inv_version = diablo_bridge.get_inventory_version()

	# 1. Update tab styling
	if tabs_hbox:
		var tab_buttons = tabs_hbox.get_children()
		for i in range(tab_buttons.size()):
			var btn: Button = tab_buttons[i]
			if i == cur_page:
				btn.add_theme_color_override("font_color", Color(1.0, 0.88, 0.40, 1.0))
				var active_sb = StyleBoxFlat.new()
				active_sb.bg_color = Color(0.24, 0.18, 0.08, 0.95)
				active_sb.border_color = Color(1.0, 0.82, 0.30, 1.0)
				active_sb.border_width_left = 2
				active_sb.border_width_top = 2
				active_sb.border_width_right = 2
				active_sb.border_width_bottom = 2
				active_sb.corner_radius_top_left = 3
				active_sb.corner_radius_top_right = 3
				active_sb.corner_radius_bottom_right = 3
				active_sb.corner_radius_bottom_left = 3
				btn.add_theme_stylebox_override("normal", active_sb)
			else:
				btn.add_theme_color_override("font_color", Color(0.70, 0.65, 0.55, 1.0))
				var normal_sb = StyleBoxFlat.new()
				normal_sb.bg_color = Color(0.10, 0.09, 0.12, 0.85)
				normal_sb.border_color = Color(0.40, 0.32, 0.20, 0.6)
				normal_sb.border_width_left = 1
				normal_sb.border_width_top = 1
				normal_sb.border_width_right = 1
				normal_sb.border_width_bottom = 1
				normal_sb.corner_radius_top_left = 3
				normal_sb.corner_radius_top_right = 3
				normal_sb.corner_radius_bottom_right = 3
				normal_sb.corner_radius_bottom_left = 3
				btn.add_theme_stylebox_override("normal", normal_sb)

	# 2. Update Spell Entries
	if not entries_vbox or not diablo_bridge.has_method("get_spell_book_entries"):
		return

	for child in entries_vbox.get_children():
		child.queue_free()

	var entries: Array = diablo_bridge.get_spell_book_entries()
	if entries.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "No spells memorized on this page."
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_color_override("font_color", Color(0.55, 0.50, 0.45, 1.0))
		empty_lbl.add_theme_font_size_override("font_size", 13)
		entries_vbox.add_child(empty_lbl)
		return

	for e in entries:
		var spell_id = int(e.get("spell_id", 0))
		var spell_type = int(e.get("spell_type", 0))
		var sname = str(e.get("name", ""))
		var type_text = str(e.get("type_text", ""))
		var mana = int(e.get("mana", 0))
		var detail = str(e.get("detail", ""))
		var is_equipped = bool(e.get("is_equipped", false))
		var can_cast = bool(e.get("can_cast", true))

		var btn = Button.new()
		btn.custom_minimum_size = Vector2(310, 42)
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_filter = Control.MOUSE_FILTER_STOP

		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.10, 0.08, 0.12, 0.90)
		sb.border_width_left = 1
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.corner_radius_top_left = 3
		sb.corner_radius_top_right = 3
		sb.corner_radius_bottom_right = 3
		sb.corner_radius_bottom_left = 3

		if is_equipped:
			sb.border_color = Color(1.0, 0.84, 0.25, 1.0)
			sb.bg_color = Color(0.20, 0.16, 0.07, 0.95)
		elif not can_cast:
			sb.border_color = Color(0.5, 0.2, 0.2, 0.7)
		else:
			sb.border_color = Color(0.40, 0.32, 0.20, 0.7)

		btn.add_theme_stylebox_override("normal", sb)

		var hover_sb = sb.duplicate()
		hover_sb.border_color = Color(1.0, 0.88, 0.4, 1.0)
		hover_sb.bg_color = Color(0.22, 0.18, 0.10, 0.95)
		btn.add_theme_stylebox_override("hover", hover_sb)
		btn.add_theme_stylebox_override("pressed", hover_sb)

		# Content HBox
		var hbox = HBoxContainer.new()
		hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hbox.offset_left = 8
		hbox.offset_right = -8
		hbox.offset_top = 4
		hbox.offset_bottom = -4
		hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_theme_constant_override("h_separation", 8)

		# Spell Icon
		var icon_rect = TextureRect.new()
		icon_rect.custom_minimum_size = Vector2(32, 32)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if diablo_bridge and diablo_bridge.has_method("get_spell_icon_texture"):
			icon_rect.texture = diablo_bridge.get_spell_icon_texture(spell_id, spell_type)
		if not can_cast:
			icon_rect.modulate = Color(0.9, 0.35, 0.35, 1.0)
		hbox.add_child(icon_rect)

		# Left text VBox (Name + Type/Level)
		var left_vbox = VBoxContainer.new()
		left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		left_vbox.add_theme_constant_override("v_separation", 1)

		var name_lbl = Label.new()
		name_lbl.text = sname
		name_lbl.add_theme_font_size_override("font_size", 13)
		if is_equipped:
			name_lbl.text = "%s  ✓" % sname
			name_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35, 1.0))
		elif not can_cast:
			name_lbl.add_theme_color_override("font_color", Color(0.8, 0.4, 0.4, 1.0))
		else:
			name_lbl.add_theme_color_override("font_color", Color(0.92, 0.88, 0.80, 1.0))
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		left_vbox.add_child(name_lbl)

		var type_lbl = Label.new()
		type_lbl.text = type_text
		type_lbl.add_theme_font_size_override("font_size", 10)
		type_lbl.add_theme_color_override("font_color", Color(0.65, 0.60, 0.52, 1.0))
		type_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		left_vbox.add_child(type_lbl)

		hbox.add_child(left_vbox)

		# Right text VBox (Mana + Detail)
		var right_vbox = VBoxContainer.new()
		right_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		right_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		right_vbox.add_theme_constant_override("v_separation", 1)

		if mana > 0:
			var mana_lbl = Label.new()
			mana_lbl.text = "%d Mana" % mana
			mana_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			mana_lbl.add_theme_font_size_override("font_size", 11)
			mana_lbl.add_theme_color_override("font_color", Color(0.40, 0.65, 1.0, 1.0))
			mana_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			right_vbox.add_child(mana_lbl)

		if not detail.is_empty():
			var detail_lbl = Label.new()
			detail_lbl.text = detail
			detail_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			detail_lbl.add_theme_font_size_override("font_size", 10)
			detail_lbl.add_theme_color_override("font_color", Color(0.85, 0.45, 0.45, 1.0) if not can_cast else Color(0.65, 0.60, 0.55, 1.0))
			detail_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			right_vbox.add_child(detail_lbl)

		hbox.add_child(right_vbox)
		btn.add_child(hbox)

		btn.pressed.connect(func():
			if diablo_bridge and diablo_bridge.has_method("select_spell_book_entry"):
				diablo_bridge.select_spell_book_entry(spell_id, spell_type)
				update_spellbook()
		)

		entries_vbox.add_child(btn)
