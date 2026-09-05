extends Control

var diablo_bridge = null

# Equipment slot indices (matching DevilutionX inv_body_loc)
const EQUIP_HEAD = 0
const EQUIP_RING_LEFT = 1
const EQUIP_RING_RIGHT = 2
const EQUIP_AMULET = 3
const EQUIP_HAND_LEFT = 4
const EQUIP_HAND_RIGHT = 5
const EQUIP_CHEST = 6

# Quality border & text colors
const COLOR_NORMAL = Color(0.75, 0.70, 0.60, 1.0)
const COLOR_MAGIC = Color(0.35, 0.60, 1.0, 1.0)
const COLOR_UNIQUE = Color(1.0, 0.82, 0.25, 1.0)
const COLOR_UNUSABLE = Color(1.0, 0.35, 0.35, 1.0)

# Cell dimensions for backpack grid
const CELL_SIZE = 24.0
const CELL_GAP = 1.0
const CELL_STEP = CELL_SIZE + CELL_GAP # 25.0

# Node references
@onready var gold_label: Label = $Content/VBox/HeaderRow/GoldLabel
@onready var close_btn: Button = find_child("CloseBtn", true, false)

# Paperdoll slots
@onready var slot_head: Control = find_child("HeadSlot", true, false)
@onready var slot_amulet: Control = find_child("AmuletSlot", true, false)
@onready var slot_hand_left: Control = find_child("HandLeftSlot", true, false)
@onready var slot_chest: Control = find_child("ChestSlot", true, false)
@onready var slot_hand_right: Control = find_child("HandRightSlot", true, false)
@onready var slot_ring_left: Control = find_child("RingLeftSlot", true, false)
@onready var slot_ring_right: Control = find_child("RingRightSlot", true, false)

# Backpack nodes
@onready var grid_cells: GridContainer = find_child("GridCells", true, false)
@onready var items_overlay: Control = find_child("ItemsOverlay", true, false)

# Dedicated Item Tooltip
@onready var tooltip: PanelContainer = $Tooltip
@onready var tooltip_title: Label = $Tooltip/Margin/VBox/TitleLabel
@onready var tooltip_divider: ColorRect = $Tooltip/Margin/VBox/Divider
@onready var tooltip_stats: Label = $Tooltip/Margin/VBox/StatsLabel

var equip_slots_map: Dictionary = {}
var hovered_item_data = null
var last_inventory_version: int = -1

func _ready():
	equip_slots_map = {
		EQUIP_HEAD: slot_head,
		EQUIP_RING_LEFT: slot_ring_left,
		EQUIP_RING_RIGHT: slot_ring_right,
		EQUIP_AMULET: slot_amulet,
		EQUIP_HAND_LEFT: slot_hand_left,
		EQUIP_HAND_RIGHT: slot_hand_right,
		EQUIP_CHEST: slot_chest,
	}

	if close_btn:
		close_btn.pressed.connect(func():
			if diablo_bridge and diablo_bridge.has_method("toggle_inventory"):
				diablo_bridge.toggle_inventory()
			visible = false
		)

	_init_equipment_slots()
	_init_backpack_cells()
	if tooltip:
		tooltip.visible = false

func set_bridge(bridge):
	diablo_bridge = bridge
	update_inventory()

func _init_equipment_slots():
	for slot_idx in equip_slots_map:
		var slot_node: Control = equip_slots_map[slot_idx]
		if slot_node:
			slot_node.mouse_filter = Control.MOUSE_FILTER_STOP
			slot_node.gui_input.connect(func(event: InputEvent):
				_on_equip_slot_gui_input(slot_idx, event)
			)
			slot_node.mouse_entered.connect(func():
				_on_equip_slot_mouse_entered(slot_idx)
			)
			slot_node.mouse_exited.connect(func():
				_on_item_mouse_exited()
			)

func _init_backpack_cells():
	if not grid_cells:
		return
	for child in grid_cells.get_children():
		child.queue_free()

	for i in range(40):
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
			_on_backpack_cell_gui_input(cell_idx, event)
		)
		grid_cells.add_child(cell)

func check_and_update():
	if not diablo_bridge:
		return
	var ver = 0
	if diablo_bridge.has_method("get_inventory_version"):
		ver = diablo_bridge.get_inventory_version()
	if ver != last_inventory_version:
		update_inventory()

func update_inventory():
	if not diablo_bridge:
		return
	if diablo_bridge.has_method("get_inventory_version"):
		last_inventory_version = diablo_bridge.get_inventory_version()

	# 1. Update Gold readout
	if gold_label and diablo_bridge.has_method("get_player_gold"):
		var gold = diablo_bridge.get_player_gold()
		gold_label.text = "Gold: %s" % _format_number(gold)

	# 2. Update Equipment Paperdoll
	_update_equipment()

	# 3. Update Backpack Items
	_update_backpack()

func _update_equipment():
	if not diablo_bridge or not diablo_bridge.has_method("get_player_equipment"):
		return

	var eq_items = diablo_bridge.get_player_equipment()
	var equipped_by_slot = {}
	for it in eq_items:
		var s = it.get("slot_id", -1)
		if s >= 0:
			equipped_by_slot[s] = it

	for slot_idx in equip_slots_map:
		var slot_node: Control = equip_slots_map[slot_idx]
		if not slot_node:
			continue

		var icon_rect: TextureRect = slot_node.get_node_or_null("Icon")
		var border_panel: Panel = slot_node.get_node_or_null("Border")
		var placeholder: Label = slot_node.get_node_or_null("Placeholder")

		if slot_idx in equipped_by_slot:
			var item = equipped_by_slot[slot_idx]
			slot_node.set_meta("item_data", item)

			var curs_id = item.get("curs_id", 0)
			var tex = diablo_bridge.get_item_texture(curs_id) if diablo_bridge.has_method("get_item_texture") else null
			if icon_rect:
				icon_rect.texture = tex
				icon_rect.visible = (tex != null)
				if not item.get("can_use", true):
					icon_rect.modulate = COLOR_UNUSABLE
				else:
					icon_rect.modulate = Color.WHITE

			if placeholder:
				placeholder.visible = false

			if border_panel:
				var q = item.get("quality", 0)
				var bcol = COLOR_NORMAL
				if q == 1: bcol = COLOR_MAGIC
				elif q == 2: bcol = COLOR_UNIQUE
				if not item.get("can_use", true):
					bcol = COLOR_UNUSABLE
				_set_slot_border_color(border_panel, bcol)
		else:
			slot_node.remove_meta("item_data")
			if icon_rect:
				icon_rect.texture = null
				icon_rect.visible = false
			if placeholder:
				placeholder.visible = true
			if border_panel:
				_set_slot_border_color(border_panel, Color(0.35, 0.28, 0.20, 0.5))

func _update_backpack():
	if not diablo_bridge or not diablo_bridge.has_method("get_player_backpack"):
		return
	if not items_overlay:
		return

	# Clear previous overlay item controls
	for c in items_overlay.get_children():
		c.queue_free()

	var bp_items = diablo_bridge.get_player_backpack()
	for it in bp_items:
		var cell_x = it.get("cell_x", 0)
		var cell_y = it.get("cell_y", 0)
		var cell_w = it.get("cell_w", 1)
		var cell_h = it.get("cell_h", 1)
		var curs_id = it.get("curs_id", 0)
		var quality = it.get("quality", 0)
		var can_use = it.get("can_use", true)
		var cell_idx = it.get("slot_id", cell_y * 10 + cell_x)
		var inv_list_idx = it.get("inv_list_index", -1)

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
			_on_backpack_item_gui_input(cell_idx, inv_list_idx, event)
		)
		item_ctrl.mouse_entered.connect(func():
			_show_item_tooltip(it, item_ctrl.global_position)
		)
		item_ctrl.mouse_exited.connect(func():
			_on_item_mouse_exited()
		)

		items_overlay.add_child(item_ctrl)

func _set_slot_border_color(panel: Panel, col: Color):
	if not panel: return
	var sb = panel.get_theme_stylebox("panel")
	if sb is StyleBoxFlat:
		var dupe = sb.duplicate()
		dupe.border_color = col
		panel.add_theme_stylebox_override("panel", dupe)

func _on_equip_slot_gui_input(slot_idx: int, event: InputEvent):
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	var mb = event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if diablo_bridge and diablo_bridge.has_method("click_inventory_slot"):
			diablo_bridge.click_inventory_slot(0, slot_idx, mb.shift_pressed, mb.ctrl_pressed)
			update_inventory()
			_on_item_mouse_exited()
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		if diablo_bridge and diablo_bridge.has_method("use_inventory_slot"):
			diablo_bridge.use_inventory_slot(0, slot_idx)
			update_inventory()
			_on_item_mouse_exited()

func _on_backpack_cell_gui_input(cell_idx: int, event: InputEvent):
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	var mb = event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if diablo_bridge and diablo_bridge.has_method("click_inventory_slot"):
			diablo_bridge.click_inventory_slot(1, cell_idx, mb.shift_pressed, mb.ctrl_pressed)
			update_inventory()
			_on_item_mouse_exited()
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		if diablo_bridge and diablo_bridge.has_method("use_inventory_slot"):
			diablo_bridge.use_inventory_slot(1, cell_idx)
			update_inventory()
			_on_item_mouse_exited()

func _on_backpack_item_gui_input(cell_idx: int, inv_list_idx: int, event: InputEvent):
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	var mb = event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if diablo_bridge and diablo_bridge.has_method("click_inventory_slot"):
			diablo_bridge.click_inventory_slot(1, cell_idx, mb.shift_pressed, mb.ctrl_pressed)
			update_inventory()
			_on_item_mouse_exited()
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		if diablo_bridge and diablo_bridge.has_method("use_inventory_slot"):
			var idx_to_use = inv_list_idx if inv_list_idx >= 0 else cell_idx
			diablo_bridge.use_inventory_slot(1, idx_to_use)
			update_inventory()
			_on_item_mouse_exited()

func _on_equip_slot_mouse_entered(slot_idx: int):
	var slot_node: Control = equip_slots_map.get(slot_idx)
	if slot_node and slot_node.has_meta("item_data"):
		var it = slot_node.get_meta("item_data")
		_show_item_tooltip(it, slot_node.global_position)

func _show_item_tooltip(item: Dictionary, global_pos: Vector2):
	hovered_item_data = item
	if not tooltip:
		return

	var iname = item.get("name", "")
	var stats = item.get("stats", "")
	var quality = item.get("quality", 0)
	var can_use = item.get("can_use", true)

	if iname.strip_edges() == "":
		tooltip.visible = false
		return

	tooltip_title.text = iname
	var title_col = COLOR_NORMAL
	if quality == 1: title_col = COLOR_MAGIC
	elif quality == 2: title_col = COLOR_UNIQUE
	if not can_use:
		title_col = COLOR_UNUSABLE
	tooltip_title.add_theme_color_override("font_color", title_col)

	var has_stats = (stats.strip_edges() != "")
	tooltip_stats.text = stats
	tooltip_stats.visible = has_stats
	if tooltip_divider:
		tooltip_divider.visible = has_stats
		tooltip_divider.color = Color(title_col.r, title_col.g, title_col.b, 0.6)

	tooltip.visible = true
	tooltip.reset_size()

	# Position tooltip to the left of the inventory panel
	var tt_w = tooltip.size.x
	var tt_h = tooltip.size.y
	var panel_global_x = global_position.x
	var target_x = panel_global_x - tt_w - 12.0
	var target_y = clampf(global_pos.y - tt_h * 0.3, 20.0, get_viewport_rect().size.y - tt_h - 20.0)
	if target_x < 10.0:
		target_x = 10.0
	tooltip.global_position = Vector2(target_x, target_y)

func _on_item_mouse_exited():
	hovered_item_data = null
	if tooltip:
		tooltip.visible = false

func _format_number(n: int) -> String:
	if n <= 0: return "0"
	var s = str(n)
	var res = ""
	var cnt = 0
	for i in range(s.length() - 1, -1, -1):
		res = s[i] + res
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			res = "," + res
	return res
