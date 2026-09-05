extends PanelContainer

var diablo_bridge = null

# Node references
@onready var name_label: Label = $Margin/VBox/HeaderRow/TitleVBox/NameLabel
@onready var class_level_label: Label = $Margin/VBox/HeaderRow/TitleVBox/ClassLevelLabel
@onready var gold_label: Label = $Margin/VBox/HeaderRow/GoldLabel
@onready var close_btn: Button = $Margin/VBox/HeaderRow/CloseBtn

@onready var level_up_banner: PanelContainer = $Margin/VBox/LevelUpBanner
@onready var level_up_banner_label: Label = $Margin/VBox/LevelUpBanner/Margin/Label

@onready var exp_label: Label = $Margin/VBox/ExpPointsRow/ExpLabel
@onready var stat_points_label: Label = $Margin/VBox/ExpPointsRow/StatPointsLabel

@onready var str_val_label: Label = $Margin/VBox/AttributesCard/Margin/VBox/StrRow/ValueLabel
@onready var add_str_btn: Button = $Margin/VBox/AttributesCard/Margin/VBox/StrRow/AddBtn

@onready var mag_val_label: Label = $Margin/VBox/AttributesCard/Margin/VBox/MagRow/ValueLabel
@onready var add_mag_btn: Button = $Margin/VBox/AttributesCard/Margin/VBox/MagRow/AddBtn

@onready var dex_val_label: Label = $Margin/VBox/AttributesCard/Margin/VBox/DexRow/ValueLabel
@onready var add_dex_btn: Button = $Margin/VBox/AttributesCard/Margin/VBox/DexRow/AddBtn

@onready var vit_val_label: Label = $Margin/VBox/AttributesCard/Margin/VBox/VitRow/ValueLabel
@onready var add_vit_btn: Button = $Margin/VBox/AttributesCard/Margin/VBox/VitRow/AddBtn

@onready var dmg_val_label: Label = $Margin/VBox/CombatCard/Margin/VBox/DmgRow/ValueLabel
@onready var to_hit_val_label: Label = $Margin/VBox/CombatCard/Margin/VBox/ToHitRow/ValueLabel
@onready var armor_val_label: Label = $Margin/VBox/CombatCard/Margin/VBox/ArmorRow/ValueLabel

@onready var res_magic_val_label: Label = $Margin/VBox/ResistVitalsCard/Margin/VBox/ResRow1/ResMagicLabel
@onready var res_fire_val_label: Label = $Margin/VBox/ResistVitalsCard/Margin/VBox/ResRow1/ResFireLabel
@onready var res_lightning_val_label: Label = $Margin/VBox/ResistVitalsCard/Margin/VBox/ResRow2/ResLightningLabel

@onready var life_val_label: Label = $Margin/VBox/ResistVitalsCard/Margin/VBox/VitalsRow/LifeLabel
@onready var mana_val_label: Label = $Margin/VBox/ResistVitalsCard/Margin/VBox/VitalsRow/ManaLabel

const CLASS_NAMES = {
	0: "Warrior",
	1: "Rogue",
	2: "Sorcerer",
	3: "Monk",
	4: "Bard",
	5: "Barbarian"
}

func _ready():
	if close_btn:
		close_btn.pressed.connect(func():
			if diablo_bridge and diablo_bridge.has_method("toggle_character_sheet"):
				diablo_bridge.toggle_character_sheet()
			visible = false
		)

	if add_str_btn:
		add_str_btn.pressed.connect(func(): _allocate_stat(0))
	if add_mag_btn:
		add_mag_btn.pressed.connect(func(): _allocate_stat(1))
	if add_dex_btn:
		add_dex_btn.pressed.connect(func(): _allocate_stat(2))
	if add_vit_btn:
		add_vit_btn.pressed.connect(func(): _allocate_stat(3))

func _process(_delta: float):
	if level_up_banner and level_up_banner.visible:
		var pulse = 0.75 + 0.35 * sin(Time.get_ticks_msec() * 0.007)
		level_up_banner.modulate = Color(1.0 + pulse * 0.4, 0.85 + pulse * 0.4, 0.2 + pulse * 0.3, 1.0)

func set_bridge(bridge):
	diablo_bridge = bridge

func _allocate_stat(attr_idx: int):
	if diablo_bridge and diablo_bridge.has_method("add_attribute_point"):
		diablo_bridge.add_attribute_point(attr_idx)
		update_stats()

func update_stats():
	if not diablo_bridge or not diablo_bridge.has_method("get_character_info"):
		return

	var info = diablo_bridge.get_character_info()
	if info.is_empty():
		return

	var c_name = info.get("name", "Hero")
	var c_class_id = info.get("class", 0)
	var c_class_name = CLASS_NAMES.get(c_class_id, "Adventurer")
	var c_level = info.get("level", 1)
	var c_gold = info.get("gold", 0)
	var c_exp = info.get("exp", 0)
	var c_next_exp = info.get("next_exp", 0)
	var stat_pts = info.get("stat_pts", 0)

	if name_label: name_label.text = c_name
	if class_level_label: class_level_label.text = "Level %d %s" % [c_level, c_class_name]
	if gold_label: gold_label.text = "Gold: %s" % _format_number(c_gold)
	if exp_label: exp_label.text = "XP: %s / %s" % [_format_number(c_exp), _format_number(c_next_exp)]

	# Level Up Banner & Stat Points
	if level_up_banner:
		level_up_banner.visible = (stat_pts > 0)
		if stat_pts > 0 and level_up_banner_label:
			level_up_banner_label.text = "★ LEVEL UP! %d STAT POINTS TO ALLOCATE ★" % stat_pts

	if stat_points_label:
		if stat_pts > 0:
			stat_points_label.text = "Points: %d" % stat_pts
			stat_points_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.2, 1.0))
			stat_points_label.visible = true
		else:
			stat_points_label.visible = false

	# Attributes
	var str_base = info.get("str_base", 0)
	var str_now = info.get("str_now", 0)
	var str_max = info.get("str_max", 0)
	if str_val_label:
		str_val_label.text = "%d (%d)" % [str_now, str_base]
		_color_stat_label(str_val_label, str_now, str_base, str_max)
	if add_str_btn:
		add_str_btn.visible = (stat_pts > 0 and str_base < str_max)

	var mag_base = info.get("mag_base", 0)
	var mag_now = info.get("mag_now", 0)
	var mag_max = info.get("mag_max", 0)
	if mag_val_label:
		mag_val_label.text = "%d (%d)" % [mag_now, mag_base]
		_color_stat_label(mag_val_label, mag_now, mag_base, mag_max)
	if add_mag_btn:
		add_mag_btn.visible = (stat_pts > 0 and mag_base < mag_max)

	var dex_base = info.get("dex_base", 0)
	var dex_now = info.get("dex_now", 0)
	var dex_max = info.get("dex_max", 0)
	if dex_val_label:
		dex_val_label.text = "%d (%d)" % [dex_now, dex_base]
		_color_stat_label(dex_val_label, dex_now, dex_base, dex_max)
	if add_dex_btn:
		add_dex_btn.visible = (stat_pts > 0 and dex_base < dex_max)

	var vit_base = info.get("vit_base", 0)
	var vit_now = info.get("vit_now", 0)
	var vit_max = info.get("vit_max", 0)
	if vit_val_label:
		vit_val_label.text = "%d (%d)" % [vit_now, vit_base]
		_color_stat_label(vit_val_label, vit_now, vit_base, vit_max)
	if add_vit_btn:
		add_vit_btn.visible = (stat_pts > 0 and vit_base < vit_max)

	# Combat
	var dmg_min = info.get("dmg_min", 0)
	var dmg_max = info.get("dmg_max", 0)
	if dmg_val_label: dmg_val_label.text = "%d - %d" % [dmg_min, dmg_max]

	var to_hit = info.get("to_hit", 0)
	if to_hit_val_label: to_hit_val_label.text = "%d%%" % to_hit

	var armor = info.get("armor", 0)
	if armor_val_label: armor_val_label.text = "%d" % armor

	# Resistances
	var res_magic = info.get("res_magic", 0)
	var res_fire = info.get("res_fire", 0)
	var res_lgt = info.get("res_lightning", 0)

	if res_magic_val_label: res_magic_val_label.text = "Magic: %d%%" % res_magic
	if res_fire_val_label: res_fire_val_label.text = "Fire: %d%%" % res_fire
	if res_lightning_val_label: res_lightning_val_label.text = "Lightning: %d%%" % res_lgt

	# Vitals
	var hp = info.get("hp", 0)
	var max_hp = info.get("max_hp", 0)
	var mana = info.get("mana", 0)
	var max_mana = info.get("max_mana", 0)

	if life_val_label: life_val_label.text = "Life: %d / %d" % [hp, max_hp]
	if mana_val_label: mana_val_label.text = "Mana: %d / %d" % [mana, max_mana]

func _color_stat_label(lbl: Label, now_val: int, base_val: int, max_val: int):
	if base_val >= max_val and max_val > 0:
		lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35, 1.0))
	elif now_val > base_val:
		lbl.add_theme_color_override("font_color", Color(0.4, 0.75, 1.0, 1.0))
	elif now_val < base_val:
		lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35, 1.0))
	else:
		lbl.add_theme_color_override("font_color", Color(0.92, 0.90, 0.85, 1.0))

func _format_number(n: int) -> String:
	var s = str(abs(n))
	var res = ""
	var cnt = 0
	for i in range(s.length() - 1, -1, -1):
		res = s[i] + res
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			res = "," + res
	if n < 0:
		res = "-" + res
	return res
