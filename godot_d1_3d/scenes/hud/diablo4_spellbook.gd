extends Control

var diablo_bridge = null

const TEX_TAB_ACTIVE = preload("res://assets/hud/gothic_tab_active.png")
const TEX_TAB_INACTIVE = preload("res://assets/hud/gothic_tab_inactive.png")
const TEX_TAB_HOVER = preload("res://assets/hud/gothic_tab_hover.png")
const TEX_SLOT_FRAME = preload("res://assets/hud/slot_frame.png")
const FONT_EXOCET = preload("res://assets/fonts/Exocet.ttf")

# Node references
@onready var close_btn: Button = find_child("CloseBtn", true, false)
@onready var entries_vbox: VBoxContainer = find_child("EntriesVBox", true, false)
@onready var tabs_hbox: HBoxContainer = find_child("TabsHBox", true, false)

var last_page: int = -1
var last_inv_version: int = -1

func _ready():
	_apply_exocet_font(self)
	if close_btn:
		close_btn.pressed.connect(func():
			if diablo_bridge and diablo_bridge.has_method("toggle_spell_book"):
				diablo_bridge.toggle_spell_book()
			visible = false
		)

	_init_tabs()

func _apply_exocet_font(node: Node):
	if node is Label:
		node.add_theme_font_override("font", FONT_EXOCET)
	elif node is Button:
		node.add_theme_font_override("font", FONT_EXOCET)
	for child in node.get_children():
		_apply_exocet_font(child)

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
		btn.add_theme_font_override("font", FONT_EXOCET)
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
	var cur_page = 0
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
				var active_sb = StyleBoxTexture.new()
				active_sb.texture = TEX_TAB_ACTIVE
				active_sb.texture_margin_left = 8
				active_sb.texture_margin_top = 8
				active_sb.texture_margin_right = 8
				active_sb.texture_margin_bottom = 8
				btn.add_theme_stylebox_override("normal", active_sb)
				btn.add_theme_stylebox_override("hover", active_sb)
				btn.add_theme_stylebox_override("pressed", active_sb)
			else:
				btn.add_theme_color_override("font_color", Color(0.70, 0.65, 0.55, 1.0))
				var normal_sb = StyleBoxTexture.new()
				normal_sb.texture = TEX_TAB_INACTIVE
				normal_sb.texture_margin_left = 8
				normal_sb.texture_margin_top = 8
				normal_sb.texture_margin_right = 8
				normal_sb.texture_margin_bottom = 8
				var hover_sb = StyleBoxTexture.new()
				hover_sb.texture = TEX_TAB_HOVER
				hover_sb.texture_margin_left = 8
				hover_sb.texture_margin_top = 8
				hover_sb.texture_margin_right = 8
				hover_sb.texture_margin_bottom = 8
				btn.add_theme_stylebox_override("normal", normal_sb)
				btn.add_theme_stylebox_override("hover", hover_sb)
				btn.add_theme_stylebox_override("pressed", hover_sb)

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
		empty_lbl.add_theme_font_override("font", FONT_EXOCET)
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
		btn.custom_minimum_size = Vector2(0, 48)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_filter = Control.MOUSE_FILTER_STOP

		var sb = StyleBoxTexture.new()
		sb.texture_margin_left = 10
		sb.texture_margin_top = 10
		sb.texture_margin_right = 10
		sb.texture_margin_bottom = 10

		var hover_sb = StyleBoxTexture.new()
		hover_sb.texture = TEX_TAB_HOVER
		hover_sb.texture_margin_left = 10
		hover_sb.texture_margin_top = 10
		hover_sb.texture_margin_right = 10
		hover_sb.texture_margin_bottom = 10

		if is_equipped:
			sb.texture = TEX_TAB_ACTIVE
		else:
			sb.texture = TEX_TAB_INACTIVE

		btn.add_theme_stylebox_override("normal", sb)
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
		var hr_path = "res://assets/skills/%d.png" % spell_id
		if FileAccess.file_exists(hr_path):
			var img = Image.load_from_file(ProjectSettings.globalize_path(hr_path))
			if img != null:
				icon_rect.texture = ImageTexture.create_from_image(img)
			elif diablo_bridge and diablo_bridge.has_method("get_spell_icon_texture"):
				icon_rect.texture = diablo_bridge.get_spell_icon_texture(spell_id, spell_type)
		elif diablo_bridge and diablo_bridge.has_method("get_spell_icon_texture"):
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
		name_lbl.add_theme_font_override("font", FONT_EXOCET)
		name_lbl.add_theme_font_size_override("font_size", 12)
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
		type_lbl.add_theme_font_override("font", FONT_EXOCET)
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
			mana_lbl.add_theme_font_override("font", FONT_EXOCET)
			mana_lbl.add_theme_font_size_override("font_size", 11)
			mana_lbl.add_theme_color_override("font_color", Color(0.40, 0.65, 1.0, 1.0))
			mana_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			right_vbox.add_child(mana_lbl)

		if not detail.is_empty():
			var detail_lbl = Label.new()
			detail_lbl.text = detail
			detail_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			detail_lbl.add_theme_font_override("font", FONT_EXOCET)
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
