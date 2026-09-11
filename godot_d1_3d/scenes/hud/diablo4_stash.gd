extends Control

var diablo_bridge = null

# Quality border & text colors (matching Diablo IV Modern HUD)
const COLOR_NORMAL = Color(0.75, 0.70, 0.60, 1.0)
const COLOR_MAGIC = Color(0.35, 0.60, 1.0, 1.0)
const COLOR_UNIQUE = Color(1.0, 0.82, 0.25, 1.0)
const COLOR_UNUSABLE = Color(1.0, 0.35, 0.35, 1.0)

# Cell dimensions for 10x10 stash grid (24px cell + 1px gap = 25px step)
const CELL_SIZE = 24.0
const CELL_GAP = 1.0
const CELL_STEP = CELL_SIZE + CELL_GAP # 25.0

# Node references
@onready var page_label: Label = find_child("PageLabel", true, false)
@onready var prev_10_btn: Button = find_child("Prev10Btn", true, false)
@onready var prev_btn: Button = find_child("PrevBtn", true, false)
@onready var next_btn: Button = find_child("NextBtn", true, false)
@onready var next_10_btn: Button = find_child("Next10Btn", true, false)
@onready var gold_label: Label = find_child("GoldLabel", true, false)
@onready var withdraw_gold_btn: Button = find_child("WithdrawGoldBtn", true, false)
@onready var close_btn: Button = find_child("CloseBtn", true, false)
@onready var grid_cells: GridContainer = find_child("GridCells", true, false)
@onready var items_overlay: Control = find_child("ItemsOverlay", true, false)

# Dedicated Item Tooltip
@onready var tooltip: PanelContainer = $Tooltip
@onready var tooltip_title: Label = $Tooltip/Margin/VBox/TitleLabel
@onready var tooltip_divider: ColorRect = $Tooltip/Margin/VBox/Divider
@onready var tooltip_stats: Label = $Tooltip/Margin/VBox/StatsLabel

var hovered_item_data = null
var last_inventory_version: int = -1
var last_stash_page: int = -1

func _ready():
	if close_btn:
		close_btn.pressed.connect(func():
			if diablo_bridge and diablo_bridge.has_method("close_stash"):
				diablo_bridge.close_stash()
			visible = false
		)

	if prev_10_btn:
		prev_10_btn.pressed.connect(func():
			if diablo_bridge and diablo_bridge.has_method("stash_change_page"):
				diablo_bridge.stash_change_page(-10)
				update_stash()
		)
	if prev_btn:
		prev_btn.pressed.connect(func():
			if diablo_bridge and diablo_bridge.has_method("stash_change_page"):
				diablo_bridge.stash_change_page(-1)
				update_stash()
		)
	if next_btn:
		next_btn.pressed.connect(func():
			if diablo_bridge and diablo_bridge.has_method("stash_change_page"):
				diablo_bridge.stash_change_page(1)
				update_stash()
		)
	if next_10_btn:
		next_10_btn.pressed.connect(func():
			if diablo_bridge and diablo_bridge.has_method("stash_change_page"):
				diablo_bridge.stash_change_page(10)
				update_stash()
		)

	if withdraw_gold_btn:
		withdraw_gold_btn.pressed.connect(func():
			if diablo_bridge and diablo_bridge.has_method("get_stash_info") and diablo_bridge.has_method("stash_withdraw_gold"):
				var info: Dictionary = diablo_bridge.get_stash_info()
				var g = int(info.get("gold", 0))
				if g > 0:
					diablo_bridge.stash_withdraw_gold(g)
					update_stash()
		)

	_init_stash_cells()
	if tooltip:
		tooltip.visible = false

func set_bridge(bridge):
	diablo_bridge = bridge
	update_stash()

func _init_stash_cells():
	if not grid_cells:
		return
	for child in grid_cells.get_children():
		child.queue_free()

	for i in range(100):
		var cell = Panel.new()
		cell.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		var cell_style = StyleBoxFlat.new()
		cell_style.bg_color = Color(0.08, 0.07, 0.09, 0.85)
		cell_style.border_color = Color(0.25, 0.20, 0.16, 0.6)
		cell_style.border_width_left = 1
		cell_style.border_width_top = 1
		cell_style.border_width_right = 1
		cell_style.border_width_bottom = 1
		cell_style.corner_radius_top_left = 1
		cell_style.corner_radius_top_right = 1
		cell_style.corner_radius_bottom_right = 1
		cell_style.corner_radius_bottom_left = 1
		cell.add_theme_stylebox_override("panel", cell_style)

		var cell_idx = i
		cell.gui_input.connect(func(event: InputEvent):
			_on_stash_cell_gui_input(cell_idx, event)
		)
		grid_cells.add_child(cell)

func check_and_update():
	if not diablo_bridge:
		return
	var ver = 0
	if diablo_bridge.has_method("get_inventory_version"):
		ver = diablo_bridge.get_inventory_version()

	var cur_page = -1
	if diablo_bridge.has_method("get_stash_info"):
		var info = diablo_bridge.get_stash_info()
		cur_page = int(info.get("page", 1))

	if ver != last_inventory_version or cur_page != last_stash_page:
		update_stash()

func update_stash():
	if not diablo_bridge:
		return
	if diablo_bridge.has_method("get_inventory_version"):
		last_inventory_version = diablo_bridge.get_inventory_version()

	# 1. Update Page & Gold Info
	if diablo_bridge.has_method("get_stash_info"):
		var info: Dictionary = diablo_bridge.get_stash_info()
		var p = int(info.get("page", 1))
		var total = int(info.get("total_pages", 100))
		var gold = int(info.get("gold", 0))
		last_stash_page = p

		if page_label:
			page_label.text = "Page %d / %d" % [p, total]
		if gold_label:
			gold_label.text = "Stash Gold: %s" % _format_number(gold)
		if withdraw_gold_btn:
			withdraw_gold_btn.disabled = (gold <= 0)

	# 2. Update Stash Items
	_update_stash_items()

func _update_stash_items():
	if not diablo_bridge or not diablo_bridge.has_method("get_stash_items"):
		return
	if not items_overlay:
		return

	# Clear previous overlay item controls
	for c in items_overlay.get_children():
		c.queue_free()

	var stash_items = diablo_bridge.get_stash_items()
	for it in stash_items:
		var cell_x = it.get("cell_x", 0)
		var cell_y = it.get("cell_y", 0)
		var cell_w = it.get("cell_w", 1)
		var cell_h = it.get("cell_h", 1)
		var curs_id = it.get("curs_id", 0)
		var quality = it.get("quality", 0)
		var can_use = it.get("can_use", true)
		var cell_idx = it.get("slot_id", cell_y * 10 + cell_x)

		var pos_x = float(cell_x) * CELL_STEP
		var pos_y = float(cell_y) * CELL_STEP
		var size_w = float(cell_w) * CELL_STEP - CELL_GAP
		var size_h = float(cell_h) * CELL_STEP - CELL_GAP

		var item_ctrl = Control.new()
		item_ctrl.position = Vector2(pos_x, pos_y)
		item_ctrl.size = Vector2(size_w, size_h)
		item_ctrl.custom_minimum_size = Vector2(size_w, size_h)
		item_ctrl.mouse_filter = Control.MOUSE_FILTER_STOP
		item_ctrl.set_meta("item_data", it)

		# Backdrop panel
		var panel = Panel.new()
		panel.set_anchors_preset(PRESET_FULL_RECT)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.10, 0.14, 0.88)
		var bcol = COLOR_NORMAL
		if quality == 1: bcol = COLOR_MAGIC
		elif quality == 2: bcol = COLOR_UNIQUE
		if not can_use:
			bcol = COLOR_UNUSABLE
			sb.bg_color = Color(0.25, 0.06, 0.06, 0.90)

		sb.border_color = bcol
		sb.border_width_left = 1
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.corner_radius_top_left = 2
		sb.corner_radius_top_right = 2
		sb.corner_radius_bottom_right = 2
		sb.corner_radius_bottom_left = 2
		panel.add_theme_stylebox_override("panel", sb)
		item_ctrl.add_child(panel)

		# Item Sprite Texture
		var tex_rect = TextureRect.new()
		tex_rect.set_anchors_preset(PRESET_FULL_RECT)
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tex = diablo_bridge.get_item_texture(curs_id) if diablo_bridge.has_method("get_item_texture") else null
		if tex:
			tex_rect.texture = tex
		if not can_use:
			tex_rect.modulate = COLOR_UNUSABLE
		item_ctrl.add_child(tex_rect)

		# Input handling
		item_ctrl.gui_input.connect(func(event: InputEvent):
			_on_stash_item_gui_input(cell_idx, event)
		)
		item_ctrl.mouse_entered.connect(func():
			_show_item_tooltip(it, item_ctrl.global_position)
		)
		item_ctrl.mouse_exited.connect(func():
			_on_item_mouse_exited()
		)

		items_overlay.add_child(item_ctrl)

func _on_stash_cell_gui_input(cell_idx: int, event: InputEvent):
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	var mb = event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if diablo_bridge and diablo_bridge.has_method("click_stash_slot"):
			diablo_bridge.click_stash_slot(cell_idx, mb.shift_pressed, mb.ctrl_pressed)
			update_stash()
			_on_item_mouse_exited()

func _on_stash_item_gui_input(cell_idx: int, event: InputEvent):
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	var mb = event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if diablo_bridge and diablo_bridge.has_method("click_stash_slot"):
			diablo_bridge.click_stash_slot(cell_idx, mb.shift_pressed, mb.ctrl_pressed)
			update_stash()
			_on_item_mouse_exited()

func _show_item_tooltip(item_data: Dictionary, global_item_pos: Vector2):
	if not tooltip or not item_data:
		return
	hovered_item_data = item_data

	var iname = item_data.get("name", "")
	var stats = item_data.get("stats", "")
	var quality = item_data.get("quality", 0)
	var can_use = item_data.get("can_use", true)

	tooltip_title.text = iname
	var title_col = COLOR_NORMAL
	if quality == 1: title_col = COLOR_MAGIC
	elif quality == 2: title_col = COLOR_UNIQUE
	if not can_use:
		title_col = COLOR_UNUSABLE
	tooltip_title.add_theme_color_override("font_color", title_col)

	tooltip_stats.text = stats
	tooltip.visible = true

	# Position tooltip relative to stash panel
	var tooltip_w = tooltip.size.x if tooltip.size.x > 0 else 210.0
	var pos_x = global_item_pos.x + CELL_STEP * 2.0
	var pos_y = global_item_pos.y

	var vp_size = get_viewport_rect().size
	if pos_x + tooltip_w > vp_size.x - 20:
		pos_x = global_item_pos.x - tooltip_w - 10
	if pos_y + tooltip.size.y > vp_size.y - 20:
		pos_y = vp_size.y - tooltip.size.y - 20
	if pos_y < 20:
		pos_y = 20

	tooltip.global_position = Vector2(pos_x, pos_y)

func _on_item_mouse_exited():
	hovered_item_data = null
	if tooltip:
		tooltip.visible = false

func _format_number(n: int) -> String:
	var s := str(n)
	var res := ""
	var cnt := 0
	for i in range(s.length() - 1, -1, -1):
		res = s[i] + res
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			res = "," + res
	return res
