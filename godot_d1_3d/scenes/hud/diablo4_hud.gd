extends CanvasLayer

@export var bridge_receiver: Node3D = null

# Node references
@onready var life_globe: ColorRect = $Root/HBox/LifeContainer/LifeGlobe
@onready var life_label: Label = $Root/HBox/LifeContainer/LifeLabel
@onready var life_tooltip: Control = $Root/HBox/LifeContainer/LifeTooltipArea

@onready var mana_globe: ColorRect = $Root/HBox/ManaContainer/ManaGlobe
@onready var mana_label: Label = $Root/HBox/ManaContainer/ManaLabel
@onready var mana_tooltip: Control = $Root/HBox/ManaContainer/ManaTooltipArea

const TEX_HEAL = preload("res://assets/hud/potion_heal.png")
const TEX_MANA = preload("res://assets/hud/potion_mana.png")
const TEX_REJUV = preload("res://assets/hud/potion_rejuv.png")
const TEX_SCROLL = preload("res://assets/hud/scroll.png")
const TEX_OIL = preload("res://assets/hud/potion_oil.png")

# Action Bar
@onready var action_bar: Control = $Root/HBox/CenterPanel/VBox/ActionBar
@onready var potion_slots: Array[Control] = [
	$Root/HBox/CenterPanel/VBox/ActionBar/Potion1,
	$Root/HBox/CenterPanel/VBox/ActionBar/Potion2,
	$Root/HBox/CenterPanel/VBox/ActionBar/Potion3,
	$Root/HBox/CenterPanel/VBox/ActionBar/Potion4,
	$Root/HBox/CenterPanel/VBox/ActionBar/Potion5,
	$Root/HBox/CenterPanel/VBox/ActionBar/Potion6,
	$Root/HBox/CenterPanel/VBox/ActionBar/Potion7,
	$Root/HBox/CenterPanel/VBox/ActionBar/Potion8
]
@onready var secondary_slot: Control = $Root/HBox/CenterPanel/VBox/ActionBar/SecondarySlot
@onready var secondary_icon: TextureRect = $Root/HBox/CenterPanel/VBox/ActionBar/SecondarySlot/Icon

# XP & Level
@onready var xp_bar: ProgressBar = $Root/HBox/CenterPanel/VBox/XPContainer/XPBar
@onready var level_label: Label = $Root/HBox/CenterPanel/VBox/XPContainer/LevelLabel
@onready var gold_label: Label = $Root/HBox/CenterPanel/VBox/XPContainer/GoldLabel

# Item Tooltip Popup
@onready var item_tooltip: PanelContainer = $ItemTooltip
@onready var item_title_label: Label = $ItemTooltip/Margin/VBox/TitleLabel
@onready var item_divider: ColorRect = $ItemTooltip/Margin/VBox/Divider
@onready var item_stats_label: Label = $ItemTooltip/Margin/VBox/StatsLabel

# Skill Selector (Speedbook Ribbon)
@onready var skill_selector: PanelContainer = $SkillSelector
@onready var skill_list: HBoxContainer = $SkillSelector/Margin/SkillList

var diablo_bridge = null
var current_spell_id: int = -1
var current_spell_type: int = -1
var is_speedbook_showing: bool = false
var spell_icon_cache: Dictionary = {}
var tooltip_style: StyleBoxFlat

const QUALITY_TITLE_COLORS = {
	0: Color(0.92, 0.90, 0.85, 1.0),   # Normal: Crisp Silver/Bone
	1: Color(0.38, 0.68, 1.0, 1.0),    # Magic: Arcane Sky Blue
	2: Color(1.0, 0.84, 0.30, 1.0),    # Unique: Radiance Gold
	3: Color(1.0, 0.32, 0.32, 1.0)     # Unmet requirements / Red
}

const QUALITY_BORDER_COLORS = {
	0: Color(0.55, 0.52, 0.45, 0.9),   # Normal: Weathered Stone Gray
	1: Color(0.22, 0.52, 0.95, 0.95),  # Magic: Arcane Azure Glow
	2: Color(0.92, 0.74, 0.25, 1.0),   # Unique: Ornate Imperial Gold
	3: Color(0.92, 0.22, 0.22, 0.95)   # Unmet requirements / Crimson Warning
}

# Cache materials
var life_mat: ShaderMaterial
var mana_mat: ShaderMaterial
var secondary_slot_mat: ShaderMaterial

# Smooth display values
var display_hp: float = 100.0
var display_mana: float = 50.0

const SPELL_NAMES = {
	0: "Attack / Skill",
	1: "Firebolt",
	2: "Healing",
	3: "Lightning",
	4: "Flash",
	5: "Identify",
	6: "Fire Wall",
	7: "Town Portal",
	8: "Stone Curse",
	9: "Infravision",
	10: "Phasing",
	11: "Mana Shield",
	12: "Fireball",
	13: "Guardian",
	14: "Chain Lightning",
	15: "Flame Wave",
	16: "Doom Serpents",
	17: "Blood Ritual",
	18: "Nova",
	19: "Invisibility",
	20: "Inferno",
	21: "Golem",
	22: "Rage",
	23: "Teleport",
	24: "Apocalypse",
	25: "Etherealize",
	26: "Item Repair",
	27: "Staff Recharge",
	28: "Trap Disarm",
	29: "Elemental",
	30: "Charged Bolt",
	31: "Holy Bolt",
	32: "Resurrect",
	33: "Telekinesis",
	34: "Heal Other",
	35: "Blood Star",
	36: "Bone Spirit",
	37: "Mana",
	38: "Magi",
	39: "Jester",
	40: "Lightning Wall",
	41: "Immolation",
	42: "Warp",
	43: "Reflect",
	44: "Berserk",
	45: "Ring of Fire",
	46: "Search",
	47: "Rune of Fire",
	48: "Rune of Light",
	49: "Rune of Nova",
	50: "Rune of Immolation",
	51: "Rune of Stone"
}

const SPELL_TYPE_NAMES = {
	0: "Skill",
	1: "Spell",
	2: "Scroll",
	3: "Staff / Charges"
}

const SPELL_TYPE_COLORS = {
	0: Color(1.2, 1.25, 1.4, 1.0),   # Skill: Silver Steel / Golden
	1: Color(0.2, 0.65, 1.8, 1.0),   # Spell: Arcane Cyan/Blue
	2: Color(1.8, 1.4, 0.25, 1.0),   # Scroll: Ancient Gold
	3: Color(1.8, 0.55, 0.1, 1.0)    # Charges: Fiery Orange
}

func _ready():
	if life_globe and life_globe.material is ShaderMaterial:
		life_mat = life_globe.material as ShaderMaterial
	if mana_globe and mana_globe.material is ShaderMaterial:
		mana_mat = mana_globe.material as ShaderMaterial
	if secondary_slot and secondary_slot.material is ShaderMaterial:
		secondary_slot_mat = secondary_slot.material as ShaderMaterial

	if item_tooltip:
		var base_sb = item_tooltip.get_theme_stylebox("panel")
		if base_sb is StyleBoxFlat:
			tooltip_style = base_sb.duplicate()
			item_tooltip.add_theme_stylebox_override("panel", tooltip_style)

	# Disable all keyboard focus grabbing on HUD elements so TAB key always toggles automap!
	_disable_focus_recursive(self)

	setup_button_events()

func _disable_focus_recursive(node: Node):
	if node is Control:
		node.focus_mode = Control.FOCUS_NONE
	for child in node.get_children():
		_disable_focus_recursive(child)

func set_bridge(bridge):
	diablo_bridge = bridge

func setup_button_events():
	# Potion 1-8 clicks
	for i in range(potion_slots.size()):
		var slot = potion_slots[i]
		var idx = i
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed:
				if event.button_index == MOUSE_BUTTON_LEFT:
					# Left click: pick up / place / swap item (megfog és odébb rakhat)
					if diablo_bridge and diablo_bridge.has_method("click_belt_slot"):
						diablo_bridge.click_belt_slot(idx)
				elif event.button_index == MOUSE_BUTTON_RIGHT:
					# Right click: use item (jobb egér = use)
					if diablo_bridge and diablo_bridge.has_method("use_belt_slot"):
						diablo_bridge.use_belt_slot(idx)
					else:
						use_belt_slot(idx + 1)
		)

	# RMB secondary slot click (opens native skill selector)
	if secondary_slot:
		secondary_slot.mouse_filter = Control.MOUSE_FILTER_STOP
		secondary_slot.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
				toggle_speedbook()
		)

	# Quick utility buttons
	var btn_char = $Root/HBox/CenterPanel/VBox/UtilityButtons/BtnChar
	var btn_inv = $Root/HBox/CenterPanel/VBox/UtilityButtons/BtnInv
	var btn_quest = $Root/HBox/CenterPanel/VBox/UtilityButtons/BtnQuest
	var btn_map = $Root/HBox/CenterPanel/VBox/UtilityButtons/BtnMap
	var btn_menu = $Root/HBox/CenterPanel/VBox/UtilityButtons/BtnMenu

	if btn_char:
		btn_char.focus_mode = Control.FOCUS_NONE
		btn_char.mouse_filter = Control.MOUSE_FILTER_STOP
		btn_char.pressed.connect(func(): send_key(KEY_C))
	if btn_inv:
		btn_inv.focus_mode = Control.FOCUS_NONE
		btn_inv.mouse_filter = Control.MOUSE_FILTER_STOP
		btn_inv.pressed.connect(func(): send_key(KEY_I))
	if btn_quest:
		btn_quest.focus_mode = Control.FOCUS_NONE
		btn_quest.mouse_filter = Control.MOUSE_FILTER_STOP
		btn_quest.pressed.connect(func(): send_key(KEY_Q))
	if btn_map:
		btn_map.focus_mode = Control.FOCUS_NONE
		btn_map.mouse_filter = Control.MOUSE_FILTER_STOP
		btn_map.pressed.connect(func(): send_key(KEY_TAB))
	if btn_menu:
		btn_menu.focus_mode = Control.FOCUS_NONE
		btn_menu.mouse_filter = Control.MOUSE_FILTER_STOP
		btn_menu.pressed.connect(func(): send_key(KEY_ESCAPE))

func use_belt_slot(slot_idx: int):
	if not diablo_bridge:
		return
	if diablo_bridge.has_method("use_belt_slot"):
		diablo_bridge.use_belt_slot(slot_idx - 1)
	else:
		var key = KEY_1 + (slot_idx - 1)
		send_key(key)

func _input(event: InputEvent):
	if not visible:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_S:
			toggle_speedbook()
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == KEY_ESCAPE and is_speedbook_showing:
			close_speedbook()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton and event.pressed and is_speedbook_showing:
		if skill_selector and skill_selector.visible:
			if not skill_selector.get_global_rect().has_point(event.position):
				if not secondary_slot.get_global_rect().has_point(event.position):
					close_speedbook()

func get_cached_spell_icon(spell_id: int, spell_type: int) -> Texture2D:
	var key = "%d_%d" % [spell_id, spell_type]
	if spell_icon_cache.has(key) and spell_icon_cache[key] != null:
		return spell_icon_cache[key]

	if diablo_bridge and diablo_bridge.has_method("get_spell_icon_texture"):
		var tex = diablo_bridge.get_spell_icon_texture(spell_id, spell_type)
		if tex != null:
			spell_icon_cache[key] = tex
			return tex
	return null

func toggle_speedbook():
	if is_speedbook_showing:
		close_speedbook()
	else:
		open_speedbook()

func open_speedbook():
	if not diablo_bridge:
		return
	is_speedbook_showing = true
	populate_speedbook()
	if skill_selector:
		skill_selector.visible = true
		skill_selector.reset_size()

func close_speedbook():
	is_speedbook_showing = false
	if skill_selector:
		skill_selector.visible = false

func populate_speedbook():
	if not skill_list:
		return
	for child in skill_list.get_children():
		child.queue_free()

	if not diablo_bridge or not diablo_bridge.has_method("get_available_spells"):
		return

	var spells = diablo_bridge.get_available_spells()
	if spells.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "No skills or spells available"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_color_override("font_color", Color(0.7, 0.65, 0.6))
		empty_lbl.add_theme_font_size_override("font_size", 11)
		empty_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		skill_list.add_child(empty_lbl)
		return

	for spell_info in spells:
		var s_id: int = spell_info.get("id", 0)
		var s_type: int = spell_info.get("type", 0)
		var s_name: String = spell_info.get("name", "Spell")
		var mana: int = spell_info.get("mana_cost", 0)
		var hotkey: String = spell_info.get("hotkey", "")

		var btn = Button.new()
		btn.custom_minimum_size = Vector2(44, 44)
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_filter = Control.MOUSE_FILTER_STOP

		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.07, 0.10, 0.95)
		sb.set_corner_radius_all(3)
		var is_current = (s_id == current_spell_id and s_type == current_spell_type)
		if is_current:
			sb.border_color = Color(1.0, 0.88, 0.35, 1.0)
			sb.border_width_left = 2
			sb.border_width_top = 2
			sb.border_width_right = 2
			sb.border_width_bottom = 2
		else:
			var border_c = SPELL_TYPE_COLORS.get(s_type, Color(0.45, 0.4, 0.3, 0.8))
			sb.border_color = Color(border_c.r * 0.75, border_c.g * 0.75, border_c.b * 0.75, 0.85)
			sb.border_width_left = 1
			sb.border_width_top = 1
			sb.border_width_right = 1
			sb.border_width_bottom = 1

		btn.add_theme_stylebox_override("normal", sb)

		var sb_hover = sb.duplicate()
		sb_hover.border_color = Color(1.0, 0.95, 0.6, 1.0)
		btn.add_theme_stylebox_override("hover", sb_hover)

		# Icon
		var icon_tex = get_cached_spell_icon(s_id, s_type)
		if icon_tex != null:
			var tex_rect = TextureRect.new()
			tex_rect.texture = icon_tex
			tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex_rect.custom_minimum_size = Vector2(38, 38)
			tex_rect.anchors_preset = Control.PRESET_FULL_RECT
			tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(tex_rect)

		# Hotkey badge
		if hotkey != "":
			var hk_lbl = Label.new()
			hk_lbl.text = hotkey
			hk_lbl.add_theme_font_size_override("font_size", 9)
			hk_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.4, 1.0))
			hk_lbl.position = Vector2(3, 1)
			hk_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(hk_lbl)

		var type_str = SPELL_TYPE_NAMES.get(s_type, "Skill")
		var tip = "%s (%s)" % [s_name, type_str]
		if s_type == 1 and mana > 0:
			tip += "\nMana Cost: %d" % mana
		if hotkey != "":
			tip += "\nHotkey: %s" % hotkey
		btn.tooltip_text = tip

		btn.pressed.connect(func():
			if diablo_bridge and diablo_bridge.has_method("select_spell"):
				diablo_bridge.select_spell(s_id, s_type)
			close_speedbook()
			update_secondary_spell()
		)

		skill_list.add_child(btn)

func get_sdl_key(keycode: int) -> int:
	if keycode == KEY_ESCAPE: return 27
	if keycode == KEY_ENTER: return 13
	if keycode == KEY_SPACE: return 32
	if keycode == KEY_TAB: return 9
	if keycode == KEY_BACKSPACE: return 8
	if keycode >= KEY_0 and keycode <= KEY_9: return keycode
	if keycode >= KEY_A and keycode <= KEY_Z: return keycode + 32
	return keycode

func send_key(keycode: int):
	if not diablo_bridge:
		return
	var sdl_key = get_sdl_key(keycode)
	if diablo_bridge.has_method("send_key_event"):
		diablo_bridge.send_key_event(sdl_key, true)
		get_tree().create_timer(0.06).timeout.connect(func():
			if diablo_bridge and diablo_bridge.has_method("send_key_event"):
				diablo_bridge.send_key_event(sdl_key, false)
		)
	elif diablo_bridge.has_method("send_input"):
		diablo_bridge.send_input(3, sdl_key, 1, sdl_key, 0)
		get_tree().create_timer(0.06).timeout.connect(func():
			if diablo_bridge and diablo_bridge.has_method("send_input"):
				diablo_bridge.send_input(3, sdl_key, 0, sdl_key, 0)
		)

func _process(delta: float):
	if not diablo_bridge or not diablo_bridge.has_method("is_engine_ready") or not diablo_bridge.is_engine_ready():
		$Root.visible = false
		if item_tooltip: item_tooltip.visible = false
		if skill_selector: skill_selector.visible = false
		return

	if diablo_bridge.has_method("is_game_running") and not diablo_bridge.is_game_running():
		$Root.visible = false
		if item_tooltip: item_tooltip.visible = false
		if skill_selector: skill_selector.visible = false
		return

	$Root.visible = true

	update_health_and_mana(delta)
	update_xp_and_level()
	update_secondary_spell()
	update_belt_potions()
	update_item_tooltip()

func update_health_and_mana(delta: float):
	var hp = diablo_bridge.get_player_hp()
	var max_hp = diablo_bridge.get_player_max_hp()
	var mana = diablo_bridge.get_player_mana()
	var max_mana = diablo_bridge.get_player_max_mana()

	if max_hp <= 0: max_hp = 1
	if max_mana <= 0: max_mana = 1

	# Smooth lerp
	display_hp = lerpf(display_hp, float(hp), clamp(delta * 12.0, 0.0, 1.0))
	display_mana = lerpf(display_mana, float(mana), clamp(delta * 12.0, 0.0, 1.0))

	var hp_ratio = clamp(display_hp / float(max_hp), 0.0, 1.0)
	var mana_ratio = clamp(display_mana / float(max_mana), 0.0, 1.0)

	if life_mat:
		life_mat.set_shader_parameter("fill_amount", hp_ratio)
	if mana_mat:
		mana_mat.set_shader_parameter("fill_amount", mana_ratio)

	if life_label:
		life_label.text = "%d / %d" % [int(round(display_hp)), max_hp]
	if mana_label:
		mana_label.text = "%d / %d" % [int(round(display_mana)), max_mana]

	if life_tooltip:
		life_tooltip.tooltip_text = "Life: %d / %d\nRight click or press potion 1-4 to heal." % [hp, max_hp]
	if mana_tooltip:
		mana_tooltip.tooltip_text = "Mana: %d / %d\nRight click or press potion 1-4 to restore mana." % [mana, max_mana]

func update_xp_and_level():
	var lvl = diablo_bridge.get_player_level()
	var xp = diablo_bridge.get_player_xp()
	var next_xp = diablo_bridge.get_player_next_xp()
	var gold = diablo_bridge.get_player_gold()

	if level_label:
		level_label.text = "Lv %d" % lvl

	if gold_label:
		gold_label.text = "%s G" % format_number(gold)

	if xp_bar:
		var ratio = 0.0
		if next_xp > 0:
			ratio = clamp(float(xp) / float(next_xp), 0.0, 1.0)
		xp_bar.value = ratio * 100.0
		xp_bar.tooltip_text = "Experience: %s / %s (%d%%)" % [format_number(xp), format_number(next_xp), int(ratio * 100.0)]

func update_secondary_spell():
	if not diablo_bridge:
		return
	var spell_id = diablo_bridge.get_player_spell()
	var spell_type = diablo_bridge.get_player_spell_type()

	if spell_id <= 0:
		current_spell_id = spell_id
		current_spell_type = spell_type
		if secondary_icon:
			secondary_icon.texture = null
			secondary_icon.visible = false
		if secondary_slot:
			secondary_slot.tooltip_text = "Select Skill / Spell [S]\nClick or press 'S' to open Speedbook."
		return

	# If spell changed OR if secondary_icon doesn't have a valid texture yet:
	if spell_id != current_spell_id or spell_type != current_spell_type or (secondary_icon and secondary_icon.texture == null):
		var tex = get_cached_spell_icon(spell_id, spell_type)
		if tex != null:
			current_spell_id = spell_id
			current_spell_type = spell_type
			if secondary_icon:
				secondary_icon.texture = tex
				secondary_icon.visible = true

			var spell_name = SPELL_NAMES.get(spell_id, "Spell #%d" % spell_id)
			var type_name = SPELL_TYPE_NAMES.get(spell_type, "Skill")

			if secondary_slot:
				secondary_slot.tooltip_text = "%s (%s) [RMB]\nClick or press 'S' to change active spell." % [spell_name, type_name]
		else:
			# Palette not ready yet: do not show a black box!
			if secondary_icon and current_spell_id <= 0:
				secondary_icon.texture = null
				secondary_icon.visible = false

func update_belt_potions():
	var belt = diablo_bridge.get_belt_items()
	for i in range(min(potion_slots.size(), belt.size())):
		var item = belt[i]
		var slot = potion_slots[i]
		var type = item.get("type", 0)
		var count = item.get("count", 0)
		var item_name = item.get("name", "")

		var icon = slot.get_node_or_null("ItemIcon") as TextureRect
		var count_lbl = slot.get_node_or_null("CountLabel") as Label

		if icon:
			match type:
				1, 2:
					icon.texture = TEX_HEAL
					icon.visible = true
				3, 4:
					icon.texture = TEX_MANA
					icon.visible = true
				5, 6:
					icon.texture = TEX_REJUV
					icon.visible = true
				8:
					icon.texture = TEX_SCROLL
					icon.visible = true
				9:
					icon.texture = TEX_OIL
					icon.visible = true
				7:
					icon.texture = TEX_REJUV
					icon.visible = true
				_:
					icon.texture = null
					icon.visible = false

		if count_lbl:
			if count > 1:
				count_lbl.text = "x%d" % count
				count_lbl.visible = true
			else:
				count_lbl.text = ""
				count_lbl.visible = false

		var tip = ""
		if item_name != "":
			var action_str = "Drink potion"
			if type == 8: action_str = "Cast scroll"
			elif type == 9: action_str = "Use oil"
			elif type == 7: action_str = "Drink elixir"
			tip = "%s (Belt %d) [Key %d]\n[LMB] Pick up / Move\n[RMB] %s" % [item_name, i + 1, i + 1, action_str]
		else:
			match type:
				1: tip = "Potion of Healing (Belt %d) [Key %d]\n[LMB] Pick up / Move\n[RMB] Drink potion" % [i + 1, i + 1]
				2: tip = "Potion of Full Healing (Belt %d) [Key %d]\n[LMB] Pick up / Move\n[RMB] Drink potion" % [i + 1, i + 1]
				3: tip = "Potion of Mana (Belt %d) [Key %d]\n[LMB] Pick up / Move\n[RMB] Drink potion" % [i + 1, i + 1]
				4: tip = "Potion of Full Mana (Belt %d) [Key %d]\n[LMB] Pick up / Move\n[RMB] Drink potion" % [i + 1, i + 1]
				5: tip = "Potion of Rejuvenation (Belt %d) [Key %d]\n[LMB] Pick up / Move\n[RMB] Drink potion" % [i + 1, i + 1]
				6: tip = "Potion of Full Rejuvenation (Belt %d) [Key %d]\n[LMB] Pick up / Move\n[RMB] Drink potion" % [i + 1, i + 1]
				7: tip = "Elixir (Belt %d) [Key %d]\n[LMB] Pick up / Move\n[RMB] Drink elixir" % [i + 1, i + 1]
				8: tip = "Scroll (Belt %d) [Key %d]\n[LMB] Pick up / Move\n[RMB] Cast scroll" % [i + 1, i + 1]
				9: tip = "Oil (Belt %d) [Key %d]\n[LMB] Pick up / Move\n[RMB] Use oil" % [i + 1, i + 1]
				_: tip = "Empty Belt Slot %d\n[LMB] Place item from cursor" % (i + 1)
		slot.tooltip_text = tip

func format_item_stats(raw_stats: String) -> String:
	if raw_stats.strip_edges() == "":
		return ""
	var lines = raw_stats.split("\n")
	var result_lines: Array[String] = []
	for l in lines:
		var line = l.strip_edges()
		if line.is_empty():
			continue
		var parts = line.split("  ")
		for part in parts:
			var p = part.strip_edges()
			if p.is_empty():
				continue
			if " Dur: " in p:
				var idx = p.find(" Dur: ")
				var p1 = p.substr(0, idx).strip_edges()
				var p2 = p.substr(idx + 1).strip_edges()
				if not p1.is_empty(): result_lines.append(p1)
				if not p2.is_empty(): result_lines.append(p2)
			elif " Indestructible" in p:
				var idx = p.find(" Indestructible")
				var p1 = p.substr(0, idx).strip_edges()
				var p2 = p.substr(idx + 1).strip_edges()
				if not p1.is_empty(): result_lines.append(p1)
				if not p2.is_empty(): result_lines.append(p2)
			elif " Charges: " in p:
				var idx = p.find(" Charges: ")
				var p1 = p.substr(0, idx).strip_edges()
				var p2 = p.substr(idx + 1).strip_edges()
				if not p1.is_empty(): result_lines.append(p1)
				if not p2.is_empty(): result_lines.append(p2)
			else:
				result_lines.append(p)

	return "\n".join(result_lines)

func update_item_tooltip():
	if not diablo_bridge or not diablo_bridge.has_method("has_hover_item"):
		if item_tooltip and item_tooltip.visible:
			item_tooltip.visible = false
		return

	if not diablo_bridge.has_hover_item():
		if item_tooltip and item_tooltip.visible:
			item_tooltip.visible = false
		return

	var info = diablo_bridge.get_hover_item_info()
	var item_name: String = info.get("name", "")
	if item_name.strip_edges() == "":
		if item_tooltip and item_tooltip.visible:
			item_tooltip.visible = false
		return

	var raw_stats: String = info.get("stats", "")
	var stats: String = format_item_stats(raw_stats)
	var quality: int = info.get("quality", 0)
	var is_inv: bool = info.get("is_inventory", false)
	var mouse_pos: Vector2i = info.get("mouse_pos", Vector2i.ZERO)

	item_title_label.text = item_name
	item_stats_label.text = stats
	var has_stats = (stats != "")
	item_stats_label.visible = has_stats
	if item_divider:
		item_divider.visible = has_stats

	var title_col = QUALITY_TITLE_COLORS.get(quality, QUALITY_TITLE_COLORS[0])
	var border_col = QUALITY_BORDER_COLORS.get(quality, QUALITY_BORDER_COLORS[0])
	item_title_label.add_theme_color_override("font_color", title_col)
	if tooltip_style:
		tooltip_style.border_color = border_col
		if item_divider:
			item_divider.color = Color(border_col.r, border_col.g, border_col.b, 0.6)

	item_tooltip.visible = true
	item_tooltip.reset_size()

	var vp_size = get_viewport().get_visible_rect().size
	var d1_w = float(diablo_bridge.get_frame_width())
	var d1_h = float(diablo_bridge.get_frame_height())
	if d1_w <= 0: d1_w = 640.0
	if d1_h <= 0: d1_h = 480.0

	var scale_x = vp_size.x / d1_w
	var scale_y = vp_size.y / d1_h

	var tooltip_w = item_tooltip.size.x
	var tooltip_h = item_tooltip.size.y

	var target_pos = Vector2.ZERO
	if is_inv:
		# Classic D1 inventory is on the right 320px: place card cleanly to the left of the window
		var inv_left_x = (d1_w - 320.0) * scale_x
		target_pos.x = inv_left_x - tooltip_w - 14.0
		target_pos.y = clampf(float(mouse_pos.y) * scale_y - tooltip_h * 0.35, 20.0, vp_size.y - tooltip_h - 20.0)
		if target_pos.x < 10.0:
			target_pos.x = 10.0
	else:
		# Ground / Belt hover: next to mouse cursor
		target_pos.x = float(mouse_pos.x) * scale_x + 18.0
		target_pos.y = float(mouse_pos.y) * scale_y + 12.0
		if target_pos.x + tooltip_w > vp_size.x - 10.0:
			target_pos.x = float(mouse_pos.x) * scale_x - tooltip_w - 14.0
		if target_pos.y + tooltip_h > vp_size.y - 10.0:
			target_pos.y = vp_size.y - tooltip_h - 10.0
		if target_pos.x < 10.0: target_pos.x = 10.0
		if target_pos.y < 10.0: target_pos.y = 10.0

	item_tooltip.position = target_pos

func format_number(n: int) -> String:
	if n <= 0: return "0"
	var s = str(n)
	var result = ""
	var cnt = 0
	for i in range(s.length() - 1, -1, -1):
		result = s[i] + result
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			result = "," + result
	return result
