extends Control

var diablo_bridge = null
var _last_quests_sig: String = ""

const TEX_TAB_ACTIVE = preload("res://assets/hud/gothic_tab_active.png")
const TEX_TAB_INACTIVE = preload("res://assets/hud/gothic_tab_inactive.png")
const TEX_TAB_HOVER = preload("res://assets/hud/gothic_tab_hover.png")
const FONT_EXOCET = preload("res://assets/fonts/Exocet.ttf")

@onready var close_btn: Button = find_child("CloseBtn", true, false)
@onready var quest_list: VBoxContainer = $Content/VBox/Scroll/QuestList
@onready var empty_label: Label = $Content/VBox/EmptyLabel

func _ready():
	_apply_exocet_font(self)
	if close_btn:
		close_btn.pressed.connect(func():
			if diablo_bridge and diablo_bridge.has_method("toggle_quest_log"):
				diablo_bridge.toggle_quest_log()
			visible = false
		)

func _apply_exocet_font(node: Node):
	if node is Label:
		node.add_theme_font_override("font", FONT_EXOCET)
	elif node is Button:
		node.add_theme_font_override("font", FONT_EXOCET)
	for child in node.get_children():
		_apply_exocet_font(child)

func set_bridge(bridge):
	diablo_bridge = bridge

func check_and_update():
	if not diablo_bridge or not diablo_bridge.has_method("get_quests_info"):
		return
	var quests = diablo_bridge.get_quests_info()
	var sig := _compute_quests_signature(quests)
	if sig != _last_quests_sig:
		_last_quests_sig = sig
		_populate_quests(quests)

func _compute_quests_signature(quests: Array) -> String:
	var parts: Array[String] = []
	for q in quests:
		var q_id: int = q.get("id", q.get("idx", 0))
		var state: int = q.get("state", 0)
		var is_done: bool = q.get("is_finished", false) or q.get("isFinished", false) or (state == 3)
		var q_name: String = q.get("name", "")
		parts.append("%d:%d:%d:%s" % [q_id, state, 1 if is_done else 0, q_name])
	return "|".join(parts)

func update_quests():
	if not diablo_bridge or not diablo_bridge.has_method("get_quests_info"):
		return
	var quests = diablo_bridge.get_quests_info()
	_last_quests_sig = _compute_quests_signature(quests)
	_populate_quests(quests)

func _populate_quests(quests: Array):
	if not quest_list:
		return

	for child in quest_list.get_children():
		child.queue_free()

	if quests.is_empty():
		if empty_label:
			empty_label.visible = true
		return

	if empty_label:
		empty_label.visible = false

	for q in quests:
		var q_id: int = q.get("id", q.get("idx", 0))
		var q_name: String = q.get("name", "Unknown Quest")
		var q_lvl: int = q.get("level", 0)
		var is_done: bool = q.get("is_finished", false) or q.get("isFinished", false) or (q.get("state", 2) == 3)

		var card = Button.new()
		card.focus_mode = Control.FOCUS_NONE
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.custom_minimum_size = Vector2(0, 48)

		var sb_normal = StyleBoxTexture.new()
		sb_normal.texture = TEX_TAB_INACTIVE
		sb_normal.texture_margin_left = 10
		sb_normal.texture_margin_top = 10
		sb_normal.texture_margin_right = 10
		sb_normal.texture_margin_bottom = 10
		if is_done:
			sb_normal.modulate_color = Color(0.65, 0.65, 0.65, 0.7)

		var sb_hover = StyleBoxTexture.new()
		sb_hover.texture = TEX_TAB_HOVER
		sb_hover.texture_margin_left = 10
		sb_hover.texture_margin_top = 10
		sb_hover.texture_margin_right = 10
		sb_hover.texture_margin_bottom = 10

		card.add_theme_stylebox_override("normal", sb_normal)
		card.add_theme_stylebox_override("hover", sb_hover)
		card.add_theme_stylebox_override("pressed", sb_hover)
		card.add_theme_stylebox_override("focus", sb_normal)

		var margin = MarginContainer.new()
		margin.anchors_preset = Control.PRESET_FULL_RECT
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.add_theme_constant_override("margin_left", 10)
		margin.add_theme_constant_override("margin_right", 10)
		margin.add_theme_constant_override("margin_top", 6)
		margin.add_theme_constant_override("margin_bottom", 6)
		card.add_child(margin)

		var row = HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.add_child(row)

		var text_vbox = VBoxContainer.new()
		text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text_vbox.add_theme_constant_override("separation", 2)
		row.add_child(text_vbox)

		var title_lbl = Label.new()
		title_lbl.text = q_name
		title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_lbl.add_theme_font_override("font", FONT_EXOCET)
		title_lbl.add_theme_font_size_override("font_size", 12)
		if is_done:
			title_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.8))
		else:
			title_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45, 1.0))
		text_vbox.add_child(title_lbl)

		var sub_lbl = Label.new()
		sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sub_lbl.add_theme_font_override("font", FONT_EXOCET)
		sub_lbl.add_theme_font_size_override("font_size", 10)
		if q_lvl > 0:
			sub_lbl.text = "Dungeon Level %d" % q_lvl
		else:
			sub_lbl.text = "Tristram"
		sub_lbl.add_theme_color_override("font_color", Color(0.65, 0.6, 0.52, 0.8))
		text_vbox.add_child(sub_lbl)

		var status_badge = Label.new()
		status_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		status_badge.add_theme_font_override("font", FONT_EXOCET)
		status_badge.add_theme_font_size_override("font_size", 10)
		if is_done:
			status_badge.text = "Completed"
			status_badge.add_theme_color_override("font_color", Color(0.45, 0.65, 0.55, 0.9))
		else:
			status_badge.text = "Active"
			status_badge.add_theme_color_override("font_color", Color(1.0, 0.75, 0.25, 1.0))
		row.add_child(status_badge)

		card.pressed.connect(func():
			if diablo_bridge and diablo_bridge.has_method("select_quest"):
				diablo_bridge.select_quest(q_id)
			var tab_menu = find_parent("TabbedMenu")
			if tab_menu:
				tab_menu.visible = false
		)

		quest_list.add_child(card)
