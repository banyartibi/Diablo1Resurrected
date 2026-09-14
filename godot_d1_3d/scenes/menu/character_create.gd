extends Control
class_name D1CharacterCreate

signal class_focused(class_id: int)
signal hero_created(save_num: int)
signal cancelled()

var diablo_bridge: Node = null
var selected_class: int = 0
var is_hungarian: bool = false
var available_classes: Array[int] = [0, 1, 2, 3, 4, 5]

@onready var title_label: Label = %TitleLabel
@onready var stats_title: Label = %StatsTitle
@onready var str_header_lbl: Label = %StrHeaderLbl
@onready var mag_header_lbl: Label = %MagHeaderLbl
@onready var dex_header_lbl: Label = %DexHeaderLbl
@onready var vit_header_lbl: Label = %VitHeaderLbl

@onready var class_buttons_container: HBoxContainer = %ClassButtonsContainer
@onready var class_name_label: Label = %ClassNameLabel
@onready var class_role_label: Label = %ClassRoleLabel
@onready var class_lore_label: Label = %ClassLoreLabel
@onready var class_perk_label: Label = %ClassPerkLabel

@onready var stat_str_bar: ProgressBar = %StatStrBar
@onready var stat_mag_bar: ProgressBar = %StatMagBar
@onready var stat_dex_bar: ProgressBar = %StatDexBar
@onready var stat_vit_bar: ProgressBar = %StatVitBar

@onready var stat_str_lbl: Label = %StatStrLbl
@onready var stat_mag_lbl: Label = %StatMagLbl
@onready var stat_dex_lbl: Label = %StatDexLbl
@onready var stat_vit_lbl: Label = %StatVitLbl

@onready var name_input: LineEdit = %NameInput
@onready var random_name_btn: Button = %RandomNameBtn
@onready var create_btn: Button = %CreateBtn
@onready var cancel_btn: Button = %CancelBtn
@onready var error_label: Label = %ErrorLabel

const CLASS_DATA_HU = [
	{
		"name": "Harcos",
		"role": "Nehézvértezetű közelharcos mester",
		"lore": "Aidan, Khanduras hercege, visszatért a keleti hadjáratból, hogy szembeszálljon a Tristram alatti sötétséggel. A legmagasabb fizikai erővel és védelemmel rendelkezik.",
		"perk": "Egyedi Képesség: Fegyverjavítás a vadonban Griswold műhelye nélkül."
	},
	{
		"name": "Íjásznő",
		"role": "Lopakodó távolsági lövész & mesterlövész",
		"lore": "A Vak Szem Nővériségének halálos íjásza. Villámgyors mozgásával és páratlan pontosságával már messziről elpusztítja a démoni seregeket.",
		"perk": "Egyedi Képesség: Csapdák Hatástalanítása a kincsesládákról és szarkofágokról."
	},
	{
		"name": "Varázsló",
		"role": "A pusztító elemi mágia beavatottja",
		"lore": "A Vizjerei mágusszövetség Keletről érkezett tudósa. A fizikai harcban törékeny, de félelmetes arkánum, tűz és villámvarázslatai hegyeket mozgatnak meg.",
		"perk": "Egyedi Képesség: Varázsbotok Újratöltése saját manából."
	},
	{
		"name": "Szerzetes",
		"role": "Fegyelmezett harcművész és botforgató",
		"lore": "A Hellfire aszkéta vándora. Könnyű páncélzatban, kétkezes bottal vagy pusztakezes harcművészettel küzd halálos hatékonysággal.",
		"perk": "Egyedi Képesség: Körkörös Botcsapás egyszerre több ellenséget talál el."
	},
	{
		"name": "Bárd",
		"role": "Kétkezes vívó és sokoldalú mágiahasználó",
		"lore": "Ravasz utazó dalnok és bajvívó. Képes egyszerre két karddal küzdeni és mágikus tekercseket forgatni.",
		"perk": "Egyedi Képesség: Kétkezes Kardforgatás & Tárgyazonosítás Cain segítsége nélkül."
	},
	{
		"name": "Barbár",
		"role": "Az Arreat-hegy vad és félelmetes fia",
		"lore": "A fagyos északi vadonok gigantikus harcosa. Brutális fizikai ereje lehetővé teszi a kétkezes fegyverek egy kézzel való forgatását.",
		"perk": "Egyedi Képesség: Féktelen Düh & Kétkezes Fegyverek egy kézzel forgatása."
	}
]

const CLASS_DATA_EN = [
	{
		"name": "Warrior",
		"role": "Heavy-armored Melee Champion",
		"lore": "Aidan, Prince of Khanduras, returns from eastern wars to confront the rising darkness beneath Tristram. Boasts peerless physical strength and resilience.",
		"perk": "Unique Skill: Item Repair in the field without needing Griswold's forge."
	},
	{
		"name": "Rogue",
		"role": "Stealth Marksman & Scout",
		"lore": "A master archer of the Sisterhood of the Sightless Eye. Her blinding speed and pinpoint precision eradicate demonic hordes from afar.",
		"perk": "Unique Skill: Disarm Traps on treasure chests, barrels, and sarcophagi."
	},
	{
		"name": "Sorcerer",
		"role": "Master of Destructive Elements",
		"lore": "A scholar of the ancient Vizjerei mage clan. Fragile in close combat, but commands cataclysmic fire, lightning, and arcane devastation.",
		"perk": "Unique Skill: Recharge Staffs directly from internal mana."
	},
	{
		"name": "Monk",
		"role": "Disciplined Martial Artist",
		"lore": "An ascetic traveler disciplined in staff defense and barehand combat. Fights lightly armored with lethal martial precision.",
		"perk": "Unique Skill: Staff Sweep cleaves multiple surrounding demons in one blow."
	},
	{
		"name": "Bard",
		"role": "Dual-Wielding Agile Spellsword",
		"lore": "A versatile rover skilled with twin blades and arcane lore. Capable of dual-wielding swords and casting utility enchantments.",
		"perk": "Unique Skill: Dual-Wield Swords & Identify magical relics without Deckard Cain."
	},
	{
		"name": "Barbarian",
		"role": "Fierce Juggernaut of Mount Arreat",
		"lore": "A mighty warrior from the northern wastes. Savage fury and colossal strength grant him the power to swing two-handed weapons in one hand.",
		"perk": "Unique Skill: Berserk Rage & One-Handed Greatweapon Mastery."
	}
]

func set_bridge(bridge: Node) -> void:
	diablo_bridge = bridge
	update_available_classes()
	if diablo_bridge and diablo_bridge.has_method("get_language_code"):
		var code = diablo_bridge.get_language_code().to_lower()
		apply_localization(code.begins_with("hu"))
	else:
		_setup_class_buttons()
		select_class(selected_class)

func update_available_classes() -> void:
	available_classes.clear()
	for c_id in range(6):
		if diablo_bridge and diablo_bridge.has_method("is_class_allowed"):
			if diablo_bridge.is_class_allowed(c_id):
				available_classes.append(c_id)
		else:
			var is_hf = diablo_bridge.is_hellfire() if (diablo_bridge and diablo_bridge.has_method("is_hellfire")) else true
			if c_id < 3 or is_hf:
				available_classes.append(c_id)

	if not available_classes.has(selected_class):
		selected_class = available_classes[0] if not available_classes.is_empty() else 0

	_setup_class_buttons()
	select_class(selected_class)

func apply_localization(is_hu: bool) -> void:
	is_hungarian = is_hu
	if not is_node_ready():
		return
	if title_label:
		title_label.text = "ÚJ HŐS LÉTREHOZÁSA" if is_hungarian else "CREATE NEW HERO"
	if stats_title:
		stats_title.text = "TULAJDONSÁGOK" if is_hungarian else "ATTRIBUTES"
	if str_header_lbl:
		str_header_lbl.text = "Erő" if is_hungarian else "Strength"
	if mag_header_lbl:
		mag_header_lbl.text = "Mágia" if is_hungarian else "Magic"
	if dex_header_lbl:
		dex_header_lbl.text = "Ügyesség" if is_hungarian else "Dexterity"
	if vit_header_lbl:
		vit_header_lbl.text = "Vitalitás" if is_hungarian else "Vitality"
	if name_input:
		name_input.placeholder_text = "Add meg a hős nevét..." if is_hungarian else "Enter hero name..."
	if random_name_btn:
		random_name_btn.text = "🎲 Véletlen" if is_hungarian else "🎲 Random"
	if create_btn:
		create_btn.text = "LÉTREHOZÁS" if is_hungarian else "CREATE"
	if cancel_btn:
		cancel_btn.text = "MÉGSEM" if is_hungarian else "CANCEL"

	_setup_class_buttons()
	select_class(selected_class)

func _ready() -> void:
	random_name_btn.pressed.connect(_on_random_name_pressed)
	create_btn.pressed.connect(_on_create_pressed)
	cancel_btn.pressed.connect(_on_cancel_pressed)
	error_label.text = ""
	apply_localization(is_hungarian)

func _setup_class_buttons() -> void:
	if not class_buttons_container:
		return
	for c in class_buttons_container.get_children():
		class_buttons_container.remove_child(c)
		c.queue_free()

	var data_list = CLASS_DATA_HU if is_hungarian else CLASS_DATA_EN
	for class_idx in available_classes:
		if class_idx < 0 or class_idx >= data_list.size():
			continue
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(130, 46)
		btn.text = data_list[class_idx]["name"]
		btn.add_theme_font_size_override("font_size", 15)
		btn.set_meta("class_id", class_idx)
		btn.pressed.connect(func(): select_class(class_idx))
		class_buttons_container.add_child(btn)

func select_class(class_id: int) -> void:
	var valid_idx = 0
	if available_classes.has(class_id):
		valid_idx = class_id
	elif not available_classes.is_empty():
		valid_idx = available_classes[0]

	selected_class = valid_idx
	var data_list = CLASS_DATA_HU if is_hungarian else CLASS_DATA_EN
	if selected_class >= 0 and selected_class < data_list.size():
		var data = data_list[selected_class]
		if class_name_label:
			class_name_label.text = data["name"]
		if class_role_label:
			class_role_label.text = data["role"]
		if class_lore_label:
			class_lore_label.text = data["lore"]
		if class_perk_label:
			class_perk_label.text = data["perk"]

	# Highlight active button
	if class_buttons_container:
		for btn in class_buttons_container.get_children():
			if btn is Button:
				var btn_class = btn.get_meta("class_id", -1)
				if btn_class == selected_class:
					btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
				else:
					btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))

	# Update stats
	var stats = { "strength": 20, "magic": 10, "dexterity": 20, "vitality": 20 }
	if diablo_bridge and diablo_bridge.has_method("get_class_base_stats"):
		stats = diablo_bridge.get_class_base_stats(selected_class)

	var s_str = int(stats.get("strength", 20))
	var s_mag = int(stats.get("magic", 10))
	var s_dex = int(stats.get("dexterity", 20))
	var s_vit = int(stats.get("vitality", 20))

	if stat_str_bar: stat_str_bar.value = s_str
	if stat_mag_bar: stat_mag_bar.value = s_mag
	if stat_dex_bar: stat_dex_bar.value = s_dex
	if stat_vit_bar: stat_vit_bar.value = s_vit

	if stat_str_lbl: stat_str_lbl.text = str(s_str)
	if stat_mag_lbl: stat_mag_lbl.text = str(s_mag)
	if stat_dex_lbl: stat_dex_lbl.text = str(s_dex)
	if stat_vit_lbl: stat_vit_lbl.text = str(s_vit)

	if name_input and name_input.text.is_empty():
		_generate_name()

	class_focused.emit(selected_class)

func _generate_name() -> void:
	var n = "Hero" if not is_hungarian else "Hős"
	if diablo_bridge and diablo_bridge.has_method("get_random_hero_name"):
		n = diablo_bridge.get_random_hero_name(selected_class)
	if name_input:
		name_input.text = n

func _on_random_name_pressed() -> void:
	_generate_name()

func _on_create_pressed() -> void:
	if error_label:
		error_label.text = ""
	var h_name = name_input.text.strip_edges() if name_input else ""
	if h_name.is_empty():
		if error_label:
			error_label.text = "Kérlek adj meg egy nevet a hősnek!" if is_hungarian else "Please enter a name for your hero!"
		return
	if h_name.length() > 15:
		if error_label:
			error_label.text = "A név nem lehet hosszabb 15 karakternél!" if is_hungarian else "The hero name cannot exceed 15 characters!"
		return

	if diablo_bridge and diablo_bridge.has_method("create_hero"):
		var ok = diablo_bridge.create_hero(h_name, selected_class)
		if ok:
			hero_created.emit(0)
		else:
			if error_label:
				error_label.text = "Hiba történt a hős mentésekor!" if is_hungarian else "Failed to create hero!"
	else:
		hero_created.emit(0)

func _on_cancel_pressed() -> void:
	cancelled.emit()
