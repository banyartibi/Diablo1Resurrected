extends Control
## Native Godot modal overlay for D1 menus (pause/gamemenu, NPC dialog/store,
## death-restart, quest narrative speech).
##
## Interactive Control nodes:
## - Non-selectable rows (e.g. "The Town Elder", "Would you like to:") are rendered as Labels.
## - Selectable rows (e.g. "Talk to Cain", "Identify an item", "Say goodbye") are rendered as
##   interactive Buttons connected to diablo_bridge.activate_modal_item(idx).
## - When quest speech / narrative text (qtextflag) is active, renders the narrative text with a Continue button.

var diablo_bridge = null
var current_type := -1
var row_controls: Array = []
var last_item_count := -1
var last_sel := -2
var last_qtext_active := false
var last_qtext_line_count := -1

var _panel: PanelContainer
var _title_label: Label
var _rows_container: VBoxContainer
var _qtext_container: VBoxContainer
var _qtext_label: Label
var _qtext_button: Button

func set_bridge(b) -> void:
	diablo_bridge = b

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_panel = PanelContainer.new()
	_panel.name = "ModalPanel"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	margin.mouse_filter = Control.MOUSE_FILTER_PASS

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("v_separation", 14)
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS

	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.custom_minimum_size = Vector2(400, 36)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(_title_label)

	# Container for standard menu / store items
	_rows_container = VBoxContainer.new()
	_rows_container.name = "Rows"
	_rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_container.add_theme_constant_override("v_separation", 8)
	_rows_container.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(_rows_container)

	# Container for speech narrative text (qtextflag)
	_qtext_container = VBoxContainer.new()
	_qtext_container.name = "QTextContainer"
	_qtext_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_qtext_container.add_theme_constant_override("v_separation", 14)
	_qtext_container.visible = false
	_qtext_container.mouse_filter = Control.MOUSE_FILTER_PASS

	_qtext_label = Label.new()
	_qtext_label.name = "QTextLabel"
	_qtext_label.custom_minimum_size = Vector2(480, 160)
	_qtext_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_qtext_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_qtext_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_qtext_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.55, 1.0))
	_qtext_label.add_theme_font_size_override("font_size", 16)
	_qtext_container.add_child(_qtext_label)

	_qtext_button = Button.new()
	_qtext_button.name = "QTextButton"
	_qtext_button.text = "Continue [Space / Esc]"
	_qtext_button.custom_minimum_size = Vector2(240, 38)
	_qtext_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_qtext_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_qtext_button.pressed.connect(_on_qtext_dismiss_pressed)
	_qtext_container.add_child(_qtext_button)

	vbox.add_child(_qtext_container)

	margin.add_child(vbox)
	_panel.add_child(margin)
	add_child(_panel)

	# Gothic panel styling
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.05, 0.08, 0.96)
	bg.border_color = Color(0.65, 0.50, 0.22, 1.0)
	bg.border_width_left = 2
	bg.border_width_top = 2
	bg.border_width_right = 2
	bg.border_width_bottom = 2
	bg.corner_radius_top_left = 6
	bg.corner_radius_top_right = 6
	bg.corner_radius_bottom_right = 6
	bg.corner_radius_bottom_left = 6
	bg.shadow_color = Color(0, 0, 0, 0.85)
	bg.shadow_size = 16
	_panel.add_theme_stylebox_override("panel", bg)

	var title_style := StyleBoxFlat.new()
	title_style.bg_color = Color(0.18, 0.13, 0.06, 0.95)
	title_style.border_color = Color(0.85, 0.68, 0.25, 0.8)
	title_style.border_width_bottom = 1
	title_style.content_margin_top = 6
	title_style.content_margin_bottom = 6
	_title_label.add_theme_stylebox_override("normal", title_style)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45, 1.0))
	_title_label.add_theme_font_size_override("font_size", 24)

func _on_qtext_dismiss_pressed() -> void:
	if diablo_bridge and diablo_bridge.has_method("dismiss_qtext"):
		diablo_bridge.dismiss_qtext()

func _on_item_pressed(idx: int) -> void:
	if diablo_bridge and diablo_bridge.has_method("activate_modal_item"):
		diablo_bridge.activate_modal_item(idx)

func _on_item_hovered(idx: int) -> void:
	if diablo_bridge and diablo_bridge.has_method("select_modal_item"):
		diablo_bridge.select_modal_item(idx)

func _build_rows(_mtype_arg: int, items: Array, sel: int) -> void:
	for c in row_controls:
		c.queue_free()
	row_controls.clear()

	var visible_idx := 0
	for d in items:
		var item_idx = visible_idx
		visible_idx += 1

		var text = str(d.get("text", ""))
		var enabled = bool(d.get("enabled", true))
		var selectable = bool(d.get("selectable", true))

		if not selectable:
			# Non-selectable header or prompt (e.g. "The Town Elder", "Would you like to:")
			var lbl := Label.new()
			lbl.name = "HeaderLabel"
			lbl.text = text
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.add_theme_color_override("font_color", Color(0.80, 0.75, 0.65, 0.9))
			lbl.add_theme_font_size_override("font_size", 14)
			_rows_container.add_child(lbl)
			row_controls.append(lbl)
		else:
			# Interactive menu option button
			var btn := Button.new()
			btn.name = "MenuItem_%d" % item_idx
			btn.text = text
			btn.custom_minimum_size = Vector2(380, 42)
			btn.mouse_filter = Control.MOUSE_FILTER_STOP
			btn.focus_mode = Control.FOCUS_NONE

			var normal_sb := _button_normal_box()
			var hover_sb := _button_hover_box()

			if not enabled:
				btn.disabled = true
				btn.add_theme_color_override("font_color", Color(0.42, 0.42, 0.45, 1.0))
				btn.add_theme_color_override("font_disabled_color", Color(0.35, 0.35, 0.38, 1.0))
			else:
				btn.add_theme_stylebox_override("normal", normal_sb)
				btn.add_theme_stylebox_override("hover", hover_sb)
				btn.add_theme_stylebox_override("pressed", hover_sb)
				btn.add_theme_color_override("font_color", Color(0.92, 0.88, 0.80, 1.0))
				btn.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.50, 1.0))
				btn.add_theme_font_size_override("font_size", 16)

				if item_idx == sel:
					btn.add_theme_stylebox_override("normal", _button_selected_box())
					btn.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45, 1.0))

				btn.pressed.connect(_on_item_pressed.bind(item_idx))
				btn.mouse_entered.connect(_on_item_hovered.bind(item_idx))

			_rows_container.add_child(btn)
			row_controls.append(btn)

func _button_normal_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.09, 0.12, 0.92)
	sb.border_color = Color(0.45, 0.36, 0.22, 0.8)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_right = 4
	sb.corner_radius_bottom_left = 4
	return sb

func _button_hover_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.24, 0.18, 0.08, 0.96)
	sb.border_color = Color(1.0, 0.82, 0.30, 1.0)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_right = 4
	sb.corner_radius_bottom_left = 4
	return sb

func _button_selected_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.28, 0.20, 0.07, 0.95)
	sb.border_color = Color(1.0, 0.85, 0.35, 1.0)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_right = 4
	sb.corner_radius_bottom_left = 4
	return sb

func _set_title(t: int, is_qtext: bool) -> void:
	if is_qtext:
		var title = diablo_bridge.get_qtext_title() if diablo_bridge and diablo_bridge.has_method("get_qtext_title") else ""
		_title_label.text = title if not title.is_empty() else "Dialogue"
		return

	match t:
		1: _title_label.text = "Game Menu"
		2:
			var talker = diablo_bridge.get_qtext_title() if diablo_bridge and diablo_bridge.has_method("get_qtext_title") else ""
			_title_label.text = talker if not talker.is_empty() else "Dialog"
		_: _title_label.text = ""

# Drive visibility + refresh each frame from D1's modal state
func _process(_delta: float) -> void:
	if not diablo_bridge or not diablo_bridge.has_method("is_modal_active"):
		visible = false
		return

	var active: bool = diablo_bridge.is_modal_active()
	if not active:
		visible = false
		current_type = -1
		last_item_count = -1
		last_sel = -2
		last_qtext_active = false
		return

	var is_qtext: bool = diablo_bridge.is_qtext_active() if diablo_bridge.has_method("is_qtext_active") else false

	if is_qtext:
		# Quest narrative speech dialogue
		visible = true
		_rows_container.visible = false
		_qtext_container.visible = true

		var qlines: Array = diablo_bridge.get_qtext_lines() if diablo_bridge.has_method("get_qtext_lines") else []
		if not last_qtext_active or qlines.size() != last_qtext_line_count:
			last_qtext_active = true
			last_qtext_line_count = qlines.size()
			_set_title(2, true)
			_qtext_label.text = "\n".join(qlines)
		return

	# Regular menu / dialogue list
	_qtext_container.visible = false
	_rows_container.visible = true
	last_qtext_active = false

	var mtype: int = diablo_bridge.get_modal_type() if diablo_bridge.has_method("get_modal_type") else 0
	var items: Array = diablo_bridge.get_current_menu_items() if diablo_bridge.has_method("get_current_menu_items") else []
	var item_count := items.size()

	if item_count == 0:
		visible = false
		current_type = -1
		last_item_count = -1
		last_sel = -2
		return

	visible = true

	var sel := -1
	if diablo_bridge.has_method("get_modal_selection_index"):
		sel = diablo_bridge.get_modal_selection_index()

	if mtype != current_type or item_count != last_item_count or sel != last_sel:
		current_type = mtype
		last_item_count = item_count
		last_sel = sel
		_set_title(mtype, false)
		_build_rows(mtype, items, sel)

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if diablo_bridge and diablo_bridge.has_method("is_qtext_active") and diablo_bridge.is_qtext_active():
			if event.keycode == KEY_SPACE or event.keycode == KEY_ESCAPE or event.keycode == KEY_ENTER:
				_on_qtext_dismiss_pressed()
				get_viewport().set_input_as_handled()
