extends Control

var diablo_bridge = null

@onready var close_btn: Button = $Content/VBox/HeaderRow/CloseBtn
@onready var quest_list: VBoxContainer = $Content/VBox/Scroll/QuestList
@onready var empty_label: Label = $Content/VBox/EmptyLabel

func _ready():
	if close_btn:
		close_btn.pressed.connect(func():
			if diablo_bridge and diablo_bridge.has_method("toggle_quest_log"):
				diablo_bridge.toggle_quest_log()
			visible = false
		)

func set_bridge(bridge):
	diablo_bridge = bridge

func update_quests():
	if not diablo_bridge or not diablo_bridge.has_method("get_quests_info"):
		return

	if not quest_list:
		return

	for child in quest_list.get_children():
		child.queue_free()

	var quests = diablo_bridge.get_quests_info()
	if quests.is_empty():
		if empty_label:
			empty_label.visible = true
		return

	if empty_label:
		empty_label.visible = false

	for q in quests:
		var q_id: int = q.get("id", 0)
		var q_name: String = q.get("name", "Unknown Quest")
		var q_lvl: int = q.get("level", 0)
		var q_state: int = q.get("state", 2)
		var is_done = (q_state == 3)

		var card = Button.new()
		card.focus_mode = Control.FOCUS_NONE
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.custom_minimum_size = Vector2(0, 48)

		var sb_normal = StyleBoxFlat.new()
		sb_normal.bg_color = Color(0.08, 0.07, 0.09, 0.85) if not is_done else Color(0.05, 0.05, 0.06, 0.6)
		sb_normal.border_color = Color(0.45, 0.38, 0.22, 0.7) if not is_done else Color(0.25, 0.25, 0.25, 0.4)
		sb_normal.set_border_width_all(1)
		sb_normal.set_corner_radius_all(3)

		var sb_hover = StyleBoxFlat.new()
		sb_hover.bg_color = Color(0.14, 0.12, 0.16, 0.95)
		sb_hover.border_color = Color(0.85, 0.7, 0.3, 0.9)
		sb_hover.set_border_width_all(1)
		sb_hover.set_corner_radius_all(3)

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
		title_lbl.add_theme_font_size_override("font_size", 12)
		if is_done:
			title_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.8))
		else:
			title_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45, 1.0))
		text_vbox.add_child(title_lbl)

		var sub_lbl = Label.new()
		sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sub_lbl.add_theme_font_size_override("font_size", 10)
		if q_lvl > 0:
			sub_lbl.text = "Dungeon Level %d" % q_lvl
		else:
			sub_lbl.text = "Tristram"
		sub_lbl.add_theme_color_override("font_color", Color(0.65, 0.6, 0.52, 0.8))
		text_vbox.add_child(sub_lbl)

		var status_badge = Label.new()
		status_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
		)

		quest_list.add_child(card)
