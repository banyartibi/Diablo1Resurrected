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

# --- Native Options panel (Music / Sound / Gamma / Speed sliders) ---
const OPT_VOLUME_MIN := -1600   # D1 volume units: -1600 = mute, 0 = max
const OPT_VOLUME_MAX := 0
const OPT_GAMMA_MIN := 30       # vanilla gamma slider range (percent)
const OPT_GAMMA_MAX := 100
const OPT_SPEED_MIN := 20       # ticks per second
const OPT_SPEED_MAX := 50

var _options_panel: Control     # full-rect input blocker hosting the options UI
var _opt_music_slider: HSlider
var _opt_sound_slider: HSlider
var _opt_gamma_slider: HSlider
var _opt_speed_slider: HSlider
var _opt_music_value: Label
var _opt_sound_value: Label
var _opt_gamma_value: Label
var _opt_speed_value: Label
var _options_open := false
var _options_closing := false   # waiting for D1 to leave its own options screen (flow B)
var _closing_frames := 0
var _options_refreshing := false

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

	# --- Native Options panel (Music/Sound/Gamma/Speed), hidden until opened ---
	_options_panel = Control.new()
	_options_panel.name = "OptionsPanel"
	_options_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_options_panel.mouse_filter = Control.MOUSE_FILTER_STOP  # swallow all mouse input over the screen
	_options_panel.visible = false

	var opt_box := PanelContainer.new()
	opt_box.name = "OptBox"
	opt_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	opt_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	opt_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	opt_box.mouse_filter = Control.MOUSE_FILTER_STOP

	var opt_margin := MarginContainer.new()
	opt_margin.add_theme_constant_override("margin_left", 28)
	opt_margin.add_theme_constant_override("margin_right", 28)
	opt_margin.add_theme_constant_override("margin_top", 22)
	opt_margin.add_theme_constant_override("margin_bottom", 22)
	opt_margin.mouse_filter = Control.MOUSE_FILTER_PASS

	var opt_vbox := VBoxContainer.new()
	opt_vbox.name = "OptVBox"
	opt_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt_vbox.add_theme_constant_override("v_separation", 14)
	opt_vbox.mouse_filter = Control.MOUSE_FILTER_PASS

	var opt_title := Label.new()
	opt_title.name = "OptionsTitle"
	opt_title.text = "Options"
	opt_title.custom_minimum_size = Vector2(400, 36)
	opt_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	opt_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	opt_title.mouse_filter = Control.MOUSE_FILTER_PASS
	opt_title.add_theme_stylebox_override("normal", title_style)
	opt_title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45, 1.0))
	opt_title.add_theme_font_size_override("font_size", 24)
	opt_vbox.add_child(opt_title)

	var opt_hint := Label.new()
	opt_hint.name = "OptionsHint"
	opt_hint.text = "Changes apply immediately - Close with Esc"
	opt_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	opt_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	opt_hint.add_theme_color_override("font_color", Color(0.75, 0.70, 0.60, 0.9))
	opt_hint.add_theme_font_size_override("font_size", 13)
	opt_vbox.add_child(opt_hint)

	var music_row := _add_option_row(opt_vbox, "Music", 0, 100)
	_opt_music_slider = music_row.get_node("Slider")
	_opt_music_value = music_row.get_node("ValueLabel")
	_opt_music_slider.value_changed.connect(_on_opt_music_changed)

	var sound_row := _add_option_row(opt_vbox, "Sound", 0, 100)
	_opt_sound_slider = sound_row.get_node("Slider")
	_opt_sound_value = sound_row.get_node("ValueLabel")
	_opt_sound_slider.value_changed.connect(_on_opt_sound_changed)

	var gamma_row := _add_option_row(opt_vbox, "Gamma", OPT_GAMMA_MIN, OPT_GAMMA_MAX)
	_opt_gamma_slider = gamma_row.get_node("Slider")
	_opt_gamma_value = gamma_row.get_node("ValueLabel")
	_opt_gamma_slider.value_changed.connect(_on_opt_gamma_changed)

	var speed_row := _add_option_row(opt_vbox, "Speed", OPT_SPEED_MIN, OPT_SPEED_MAX)
	_opt_speed_slider = speed_row.get_node("Slider")
	_opt_speed_value = speed_row.get_node("ValueLabel")
	_opt_speed_slider.value_changed.connect(_on_opt_speed_changed)

	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "Close [Esc]"
	close_btn.custom_minimum_size = Vector2(240, 38)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_stylebox_override("normal", _button_normal_box())
	close_btn.add_theme_stylebox_override("hover", _button_hover_box())
	close_btn.add_theme_stylebox_override("pressed", _button_hover_box())
	close_btn.add_theme_color_override("font_color", Color(0.92, 0.88, 0.80, 1.0))
	close_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.50, 1.0))
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.pressed.connect(_on_opt_close_pressed)
	opt_vbox.add_child(close_btn)

	opt_margin.add_child(opt_vbox)
	opt_box.add_child(opt_margin)
	_options_panel.add_child(opt_box)

	var opt_bg := StyleBoxFlat.new()
	opt_bg.bg_color = Color(0.05, 0.05, 0.08, 0.96)
	opt_bg.border_color = Color(0.65, 0.50, 0.22, 1.0)
	opt_bg.border_width_left = 2
	opt_bg.border_width_top = 2
	opt_bg.border_width_right = 2
	opt_bg.border_width_bottom = 2
	opt_bg.corner_radius_top_left = 6
	opt_bg.corner_radius_top_right = 6
	opt_bg.corner_radius_bottom_right = 6
	opt_bg.corner_radius_bottom_left = 6
	opt_bg.shadow_color = Color(0, 0, 0, 0.85)
	opt_bg.shadow_size = 16
	opt_box.add_theme_stylebox_override("panel", opt_bg)

	add_child(_options_panel)

func _on_qtext_dismiss_pressed() -> void:
	if diablo_bridge and diablo_bridge.has_method("dismiss_qtext"):
		diablo_bridge.dismiss_qtext()

func _on_item_pressed(idx: int) -> void:
	if diablo_bridge and diablo_bridge.has_method("activate_modal_item"):
		diablo_bridge.activate_modal_item(idx)

func _on_item_hovered(idx: int) -> void:
	if diablo_bridge and diablo_bridge.has_method("select_modal_item"):
		diablo_bridge.select_modal_item(idx)

# --- Native Options panel (Music/Sound/Gamma/Speed sliders) ---

func _on_options_row_pressed(idx: int) -> void:
	# Mouse flow: align D1's selection with this row, then open the native panel.
	if diablo_bridge and diablo_bridge.has_method("select_modal_item"):
		diablo_bridge.select_modal_item(idx)
	_open_options_panel()

func _on_opt_close_pressed() -> void:
	_close_options_panel()

func _open_options_panel() -> void:
	if _options_open or _options_closing:
		return
	_refresh_option_values()
	_options_open = true
	_options_closing = false
	_closing_frames = 0
	visible = true
	_panel.visible = false
	_options_panel.visible = true

func _close_options_panel() -> void:
	if not (_options_open or _options_closing):
		return
	var items: Array = diablo_bridge.get_current_menu_items() if diablo_bridge and diablo_bridge.has_method("get_current_menu_items") else []
	var prev_idx := -1
	for i in range(items.size()):
		if str(items[i].get("text", "")) == "Previous Menu":
			prev_idx = i
			break
	if prev_idx >= 0:
		# Keyboard flow: D1 is on its own options screen. Ask it to go back and
		# keep the panel visible until the menu actually switches (async engine thread).
		if diablo_bridge.has_method("activate_modal_item"):
			diablo_bridge.activate_modal_item(prev_idx)
		_options_open = false
		_options_closing = true
		_closing_frames = 0
	else:
		_finalize_options_close()

func _finalize_options_close() -> void:
	_options_open = false
	_options_closing = false
	_closing_frames = 0
	if _options_panel != null:
		_options_panel.visible = false
	if _panel != null:
		_panel.visible = true

func _reset_options_state() -> void:
	_options_open = false
	_options_closing = false
	_closing_frames = 0
	_options_refreshing = false
	if _options_panel != null:
		_options_panel.visible = false
	if _panel != null:
		_panel.visible = true

func _items_contain(items: Array, text: String) -> bool:
	for d in items:
		if str(d.get("text", "")) == text:
			return true
	return false

# --- Slider helpers (D1 volume units <-> percent display) ---

func _pct_to_vol(pct: int) -> int:
	var v := OPT_VOLUME_MIN + pct * 16
	return clampi(v, OPT_VOLUME_MIN, OPT_VOLUME_MAX)

func _vol_to_pct(vol: int) -> float:
	return clampf((vol - OPT_VOLUME_MIN) / 16.0, 0.0, 100.0)

func _volume_label(pct: int) -> String:
	return "Off" if pct <= 0 else "%d%%" % pct

func _speed_label(rate: int) -> String:
	if rate >= 50:
		return "%d - Fastest" % rate
	elif rate >= 40:
		return "%d - Faster" % rate
	elif rate >= 30:
		return "%d - Fast" % rate
	return "%d - Normal" % rate

func _refresh_option_values() -> void:
	if not diablo_bridge:
		return
	_options_refreshing = true
	var mv := OPT_VOLUME_MIN
	var sv := OPT_VOLUME_MIN
	var g := (OPT_GAMMA_MIN + OPT_GAMMA_MAX) / 2
	var s := OPT_SPEED_MIN
	if diablo_bridge.has_method("get_music_volume"):
		mv = int(diablo_bridge.get_music_volume())
	if diablo_bridge.has_method("get_sound_volume"):
		sv = int(diablo_bridge.get_sound_volume())
	if diablo_bridge.has_method("get_gamma"):
		g = clampi(int(diablo_bridge.get_gamma()), OPT_GAMMA_MIN, OPT_GAMMA_MAX)
	if diablo_bridge.has_method("get_speed"):
		s = clampi(int(diablo_bridge.get_speed()), OPT_SPEED_MIN, OPT_SPEED_MAX)

	var mp := int(round(_vol_to_pct(mv)))
	var sp := int(round(_vol_to_pct(sv)))
	_opt_music_slider.value = float(mp)
	_opt_music_value.text = _volume_label(mp)
	_opt_sound_slider.value = float(sp)
	_opt_sound_value.text = _volume_label(sp)
	_opt_gamma_slider.value = float(g)
	_opt_gamma_value.text = "%d%%" % g
	_opt_speed_slider.value = float(s)
	_opt_speed_value.text = _speed_label(s)
	_options_refreshing = false

func _on_opt_music_changed(v: float) -> void:
	if _options_refreshing:
		return
	var pct := int(round(v))
	_opt_music_value.text = _volume_label(pct)
	if diablo_bridge and diablo_bridge.has_method("set_music_volume"):
		diablo_bridge.set_music_volume(_pct_to_vol(pct))

func _on_opt_sound_changed(v: float) -> void:
	if _options_refreshing:
		return
	var pct := int(round(v))
	_opt_sound_value.text = _volume_label(pct)
	if diablo_bridge and diablo_bridge.has_method("set_sound_volume"):
		diablo_bridge.set_sound_volume(_pct_to_vol(pct))

func _on_opt_gamma_changed(v: float) -> void:
	if _options_refreshing:
		return
	var g := int(round(v))
	_opt_gamma_value.text = "%d%%" % g
	if diablo_bridge and diablo_bridge.has_method("set_gamma"):
		diablo_bridge.set_gamma(g)

func _on_opt_speed_changed(v: float) -> void:
	if _options_refreshing:
		return
	var s := int(round(v))
	_opt_speed_value.text = _speed_label(s)
	if diablo_bridge and diablo_bridge.has_method("set_speed"):
		diablo_bridge.set_speed(s)

func _add_option_row(parent: Control, text: String, min_v: float, max_v: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "OptionRow"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("h_separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_PASS

	var lbl := Label.new()
	lbl.name = "Label"
	lbl.text = text
	lbl.custom_minimum_size = Vector2(130, 0)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.name = "Slider"
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = 1.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_NONE
	row.add_child(slider)

	var val := Label.new()
	val.name = "ValueLabel"
	val.custom_minimum_size = Vector2(110, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	val.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55, 1.0))
	row.add_child(val)

	parent.add_child(row)
	return row

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

				if text == "Options":
					# Intercept D1's Options row -> open the native slider panel.
					btn.pressed.connect(_on_options_row_pressed.bind(item_idx))
				else:
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
		_reset_options_state()
		return

	var active: bool = diablo_bridge.is_modal_active()
	if not active:
		visible = false
		current_type = -1
		last_item_count = -1
		last_sel = -2
		last_qtext_active = false
		_reset_options_state()
		return

	var is_qtext: bool = diablo_bridge.is_qtext_active() if diablo_bridge.has_method("is_qtext_active") else false

	if is_qtext:
		# Quest narrative speech dialogue
		_reset_options_state()
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
		_reset_options_state()
		return

	# --- Native Options panel state machine (Music/Sound/Gamma/Speed) ---
	var has_prev_menu := _items_contain(items, "Previous Menu")

	if _options_closing:
		# Waiting for D1 to leave its own options screen after "Previous Menu" activation.
		_closing_frames += 1
		if not has_prev_menu or _closing_frames > 60:
			_finalize_options_close()
		return

	if _options_open:
		visible = true
		_panel.visible = false
		_options_panel.visible = true
		return

	if mtype == 1 and has_prev_menu:
		# D1 switched to its own options screen (keyboard flow) -> open native panel.
		_open_options_panel()
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
		if _options_open or _options_closing:
			# Swallow every key while the options panel is open/closing so D1's menu
			# (and e.g. "Quit Game") can't be triggered by accident.
			get_viewport().set_input_as_handled()
			if event.keycode == KEY_ESCAPE:
				_close_options_panel()
			return
		if diablo_bridge and diablo_bridge.has_method("is_qtext_active") and diablo_bridge.is_qtext_active():
			if event.keycode == KEY_SPACE or event.keycode == KEY_ESCAPE or event.keycode == KEY_ENTER:
				_on_qtext_dismiss_pressed()
				get_viewport().set_input_as_handled()
