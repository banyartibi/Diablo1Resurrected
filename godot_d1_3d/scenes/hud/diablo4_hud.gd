extends CanvasLayer

@export var bridge_receiver: Node3D = null

# Node references
@onready var life_globe: ColorRect = $Root/HBox/LifeContainer/LifeGlobe
@onready var life_label: Label = $Root/HBox/LifeContainer/LifeLabel
@onready var life_tooltip: Control = $Root/HBox/LifeContainer/LifeTooltipArea

@onready var mana_globe: ColorRect = $Root/HBox/ManaContainer/ManaGlobe
@onready var mana_label: Label = $Root/HBox/ManaContainer/ManaLabel
@onready var mana_tooltip: Control = $Root/HBox/ManaContainer/ManaTooltipArea

# Action Bar
@onready var action_bar: Control = $Root/HBox/CenterPanel/ActionBar
@onready var potion_slots: Array[Control] = [
	$Root/HBox/CenterPanel/ActionBar/Potion1,
	$Root/HBox/CenterPanel/ActionBar/Potion2,
	$Root/HBox/CenterPanel/ActionBar/Potion3,
	$Root/HBox/CenterPanel/ActionBar/Potion4,
	$Root/HBox/CenterPanel/ActionBar/Potion5,
	$Root/HBox/CenterPanel/ActionBar/Potion6,
	$Root/HBox/CenterPanel/ActionBar/Potion7,
	$Root/HBox/CenterPanel/ActionBar/Potion8
]
@onready var secondary_slot: Control = $Root/HBox/CenterPanel/ActionBar/SecondarySlot
@onready var secondary_icon: TextureRect = $Root/HBox/CenterPanel/ActionBar/SecondarySlot/Icon

# XP & Level
@onready var xp_bar: ProgressBar = $Root/HBox/CenterPanel/XPContainer/XPBar
@onready var level_label: Label = $Root/HBox/CenterPanel/XPContainer/LevelLabel
@onready var gold_label: Label = $Root/HBox/CenterPanel/XPContainer/GoldLabel

var diablo_bridge = null
var current_spell_id: int = -1
var current_spell_type: int = -1

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
	0: "Spell",
	1: "Scroll",
	2: "Staff",
	3: "Skill"
}

const SPELL_TYPE_COLORS = {
	0: Color(0.2, 0.65, 1.8, 1.0),   # Arcane Cyan/Blue
	1: Color(1.8, 1.4, 0.25, 1.0),   # Ancient Gold
	2: Color(1.8, 0.55, 0.1, 1.0),   # Fiery Orange
	3: Color(1.2, 1.25, 1.4, 1.0)    # Silver Steel
}

func _ready():
	if life_globe and life_globe.material is ShaderMaterial:
		life_mat = life_globe.material as ShaderMaterial
	if mana_globe and mana_globe.material is ShaderMaterial:
		mana_mat = mana_globe.material as ShaderMaterial
	if secondary_slot and secondary_slot.material is ShaderMaterial:
		secondary_slot_mat = secondary_slot.material as ShaderMaterial

	setup_button_events()

func set_bridge(bridge):
	diablo_bridge = bridge

func setup_button_events():
	# Potion 1-8 clicks
	for i in range(potion_slots.size()):
		var slot = potion_slots[i]
		var idx = i + 1
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				use_belt_slot(idx)
		)

	# RMB secondary slot click (opens spell list/speedbook)
	if secondary_slot:
		secondary_slot.mouse_filter = Control.MOUSE_FILTER_STOP
		secondary_slot.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
				toggle_speedbook()
		)

	# Quick utility buttons
	var btn_char = $Root/HBox/CenterPanel/UtilityButtons/BtnChar
	var btn_inv = $Root/HBox/CenterPanel/UtilityButtons/BtnInv
	var btn_quest = $Root/HBox/CenterPanel/UtilityButtons/BtnQuest
	var btn_map = $Root/HBox/CenterPanel/UtilityButtons/BtnMap
	var btn_menu = $Root/HBox/CenterPanel/UtilityButtons/BtnMenu

	if btn_char:
		btn_char.mouse_filter = Control.MOUSE_FILTER_STOP
		btn_char.pressed.connect(func(): send_key(KEY_C))
	if btn_inv:
		btn_inv.mouse_filter = Control.MOUSE_FILTER_STOP
		btn_inv.pressed.connect(func(): send_key(KEY_I))
	if btn_quest:
		btn_quest.mouse_filter = Control.MOUSE_FILTER_STOP
		btn_quest.pressed.connect(func(): send_key(KEY_Q))
	if btn_map:
		btn_map.mouse_filter = Control.MOUSE_FILTER_STOP
		btn_map.pressed.connect(func(): send_key(KEY_TAB))
	if btn_menu:
		btn_menu.mouse_filter = Control.MOUSE_FILTER_STOP
		btn_menu.pressed.connect(func(): send_key(KEY_ESCAPE))

func use_belt_slot(slot_idx: int):
	if not diablo_bridge:
		return
	var key = KEY_1 + (slot_idx - 1)
	send_key(key)

func toggle_speedbook():
	if not diablo_bridge:
		return
	send_key(KEY_S)

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
		return

	if diablo_bridge.has_method("is_game_running") and not diablo_bridge.is_game_running():
		$Root.visible = false
		return

	$Root.visible = true

	update_health_and_mana(delta)
	update_xp_and_level()
	update_secondary_spell()
	update_belt_potions()

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
	var spell_id = diablo_bridge.get_player_spell()
	var spell_type = diablo_bridge.get_player_spell_type()

	if spell_id != current_spell_id or spell_type != current_spell_type:
		current_spell_id = spell_id
		current_spell_type = spell_type

		var tex = diablo_bridge.get_spell_icon_texture(spell_id, spell_type)
		if secondary_icon:
			secondary_icon.texture = tex

		if spell_id <= 0:
			if secondary_slot_mat:
				secondary_slot_mat.set_shader_parameter("is_active", false)
			if secondary_slot:
				secondary_slot.tooltip_text = "Select Skill / Spell\nClick or press 'S' to open spellbook."
			return

		var spell_name = SPELL_NAMES.get(spell_id, "Spell #%d" % spell_id)
		var type_name = SPELL_TYPE_NAMES.get(spell_type, "Skill")
		var glow_col = SPELL_TYPE_COLORS.get(spell_type, Color(0.8, 0.8, 0.8, 1.0))

		if secondary_slot_mat:
			secondary_slot_mat.set_shader_parameter("glow_color", glow_col)
			secondary_slot_mat.set_shader_parameter("is_active", true)

		if secondary_slot:
			secondary_slot.tooltip_text = "%s (%s)\nClick or press 'S' to change active spell." % [spell_name, type_name]

func update_belt_potions():
	var belt = diablo_bridge.get_belt_items()
	for i in range(min(potion_slots.size(), belt.size())):
		var item = belt[i]
		var slot = potion_slots[i]
		var type = item.get("type", 0)
		var count = item.get("count", 0)

		var icon = slot.get_node_or_null("PotionIcon") as ColorRect
		var count_lbl = slot.get_node_or_null("CountLabel") as Label

		if icon and icon.material is ShaderMaterial:
			var mat = icon.material as ShaderMaterial
			mat.set_shader_parameter("potion_type", type)

		if count_lbl:
			if count > 1:
				count_lbl.text = str(count)
				count_lbl.visible = true
			else:
				count_lbl.text = ""
				count_lbl.visible = false

		var tip = ""
		match type:
			1: tip = "Potion of Healing (Belt %d)\nRestores health." % (i + 1)
			2: tip = "Potion of Full Healing (Belt %d)\nCompletely restores health." % (i + 1)
			3: tip = "Potion of Mana (Belt %d)\nRestores mana." % (i + 1)
			4: tip = "Potion of Full Mana (Belt %d)\nCompletely restores mana." % (i + 1)
			5: tip = "Potion of Rejuvenation (Belt %d)\nRestores both health and mana." % (i + 1)
			6: tip = "Potion of Full Rejuvenation (Belt %d)\nCompletely restores health and mana." % (i + 1)
			7: tip = "Elixir (Belt %d)" % (i + 1)
			_: tip = "Empty Belt Slot %d" % (i + 1)
		slot.tooltip_text = tip

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
