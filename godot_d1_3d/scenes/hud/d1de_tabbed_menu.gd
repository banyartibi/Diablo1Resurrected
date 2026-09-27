extends Control

var diablo_bridge = null
var current_tab: int = 1 # Default: Inventory (0=Char, 1=Inv, 2=Spells, 3=Quests)

@onready var tab_char: Button = find_child("TabChar", true, false)
@onready var tab_inv: Button = find_child("TabInv", true, false)
@onready var tab_spell: Button = find_child("TabSpell", true, false)
@onready var tab_quest: Button = find_child("TabQuest", true, false)
@onready var close_btn: Button = find_child("CloseBtn", true, false)

@onready var char_panel: Control = $MainMargin/MainVBox/ViewsContainer/CharacterPanel
@onready var inv_panel: Control = $MainMargin/MainVBox/ViewsContainer/InventoryPanel
@onready var spellbook_panel: Control = $MainMargin/MainVBox/ViewsContainer/SpellbookPanel
@onready var quest_panel: Control = $MainMargin/MainVBox/ViewsContainer/QuestLogPanel


var tab_buttons: Array[Button] = []
var panel_views: Array[Control] = []

const FONT_EXOCET = preload("res://assets/fonts/Exocet.ttf")
const TEX_TAB_ACTIVE = preload("res://assets/hud/gothic_tab_active.png")
const TEX_TAB_INACTIVE = preload("res://assets/hud/gothic_tab_inactive.png")
const TEX_TAB_HOVER = preload("res://assets/hud/gothic_tab_hover.png")
const TEX_BTN_CLOSE = preload("res://assets/hud/gothic_btn_close.png")
const TEX_BTN_CLOSE_HOVER = preload("res://assets/hud/gothic_btn_close_hover.png")

# Styles for tabs
var style_active: StyleBoxTexture
var style_inactive: StyleBoxTexture
var style_hover: StyleBoxTexture
var style_close_normal: StyleBoxTexture
var style_close_hover: StyleBoxTexture

func _ensure_initialized():
	if not style_active:
		_init_styles()
	if panel_views.is_empty():
		if not tab_char: tab_char = find_child("TabChar", true, false)
		if not tab_inv: tab_inv = find_child("TabInv", true, false)
		if not tab_spell: tab_spell = find_child("TabSpell", true, false)
		if not tab_quest: tab_quest = find_child("TabQuest", true, false)
		if not close_btn: close_btn = find_child("CloseBtn", true, false)
		if not char_panel: char_panel = get_node_or_null("MainMargin/MainVBox/ViewsContainer/CharacterPanel")
		if not inv_panel: inv_panel = get_node_or_null("MainMargin/MainVBox/ViewsContainer/InventoryPanel")
		if not spellbook_panel: spellbook_panel = get_node_or_null("MainMargin/MainVBox/ViewsContainer/SpellbookPanel")
		if not quest_panel: quest_panel = get_node_or_null("MainMargin/MainVBox/ViewsContainer/QuestLogPanel")
		tab_buttons = [tab_char, tab_inv, tab_spell, tab_quest]
		panel_views = [char_panel, inv_panel, spellbook_panel, quest_panel]

func _ready():
	_init_styles()
	_ensure_initialized()

	for i in range(tab_buttons.size()):
		var btn = tab_buttons[i]
		if btn and not btn.pressed.is_connected(func(): pass):
			btn.focus_mode = Control.FOCUS_NONE
			var idx = i
			btn.pressed.connect(func():
				switch_tab(idx)
			)

	if close_btn:
		close_btn.focus_mode = Control.FOCUS_NONE
		close_btn.add_theme_stylebox_override("normal", style_close_normal)
		close_btn.add_theme_stylebox_override("hover", style_close_hover)
		close_btn.add_theme_stylebox_override("pressed", style_close_hover)
		close_btn.pressed.connect(func():
			close_menu()
		)

	_refresh_tab_display()
	_propagate_bridge()

func _init_styles():
	style_active = StyleBoxTexture.new()
	style_active.texture = TEX_TAB_ACTIVE
	style_active.texture_margin_left = 10
	style_active.texture_margin_top = 10
	style_active.texture_margin_right = 10
	style_active.texture_margin_bottom = 10
	style_active.modulate_color = Color(1.0, 0.94, 0.75, 1.0)

	style_inactive = StyleBoxTexture.new()
	style_inactive.texture = TEX_TAB_INACTIVE
	style_inactive.texture_margin_left = 10
	style_inactive.texture_margin_top = 10
	style_inactive.texture_margin_right = 10
	style_inactive.texture_margin_bottom = 10
	style_inactive.modulate_color = Color(0.85, 0.82, 0.78, 0.85)

	style_hover = StyleBoxTexture.new()
	style_hover.texture = TEX_TAB_HOVER
	style_hover.texture_margin_left = 10
	style_hover.texture_margin_top = 10
	style_hover.texture_margin_right = 10
	style_hover.texture_margin_bottom = 10

	style_close_normal = StyleBoxTexture.new()
	style_close_normal.texture = TEX_BTN_CLOSE
	style_close_normal.texture_margin_left = 6
	style_close_normal.texture_margin_top = 6
	style_close_normal.texture_margin_right = 6
	style_close_normal.texture_margin_bottom = 6

	style_close_hover = StyleBoxTexture.new()
	style_close_hover.texture = TEX_BTN_CLOSE_HOVER
	style_close_hover.texture_margin_left = 6
	style_close_hover.texture_margin_top = 6
	style_close_hover.texture_margin_right = 6
	style_close_hover.texture_margin_bottom = 6

func set_bridge(bridge):
	diablo_bridge = bridge
	_propagate_bridge()

func _propagate_bridge():
	if not diablo_bridge:
		return
	if not is_inside_tree():
		return

	_ensure_initialized()

	if char_panel and char_panel.has_method("set_bridge"):
		char_panel.set_bridge(diablo_bridge)
	if inv_panel and inv_panel.has_method("set_bridge"):
		inv_panel.set_bridge(diablo_bridge)
	if spellbook_panel and spellbook_panel.has_method("set_bridge"):
		spellbook_panel.set_bridge(diablo_bridge)
	if quest_panel and quest_panel.has_method("set_bridge"):
		quest_panel.set_bridge(diablo_bridge)



func open_tab(tab_idx: int):
	_ensure_initialized()
	if tab_idx < 0 or tab_idx >= panel_views.size():
		return
	visible = true
	current_tab = tab_idx
	_refresh_tab_display()

	if diablo_bridge and diablo_bridge.has_method("set_active_ui_panel"):
		diablo_bridge.set_active_ui_panel(current_tab)

	update_active_view()

func switch_tab(tab_idx: int):
	open_tab(tab_idx)

func toggle_tab(tab_idx: int):
	if not visible:
		open_tab(tab_idx)
	elif current_tab == tab_idx:
		close_menu()
	else:
		switch_tab(tab_idx)

func close_menu():
	if diablo_bridge and diablo_bridge.has_method("get_cursor_id"):
		var cid = diablo_bridge.get_cursor_id()
		if cid > 1 and cid < 12 and diablo_bridge.has_method("cancel_targeting_cursor"):
			diablo_bridge.cancel_targeting_cursor()
	visible = false
	if diablo_bridge and diablo_bridge.has_method("close_all_ui_panels"):
		diablo_bridge.close_all_ui_panels()

func is_menu_open() -> bool:
	return visible

func get_current_tab() -> int:
	return current_tab

func _refresh_tab_display():
	for i in range(tab_buttons.size()):
		var btn = tab_buttons[i]
		var panel = panel_views[i] if i < panel_views.size() else null
		var is_cur = (i == current_tab)

		if btn:
			btn.add_theme_font_override("font", FONT_EXOCET)
			btn.add_theme_font_size_override("font_size", 11)
			if is_cur:
				btn.add_theme_stylebox_override("normal", style_active)
				btn.add_theme_stylebox_override("hover", style_active)
				btn.add_theme_stylebox_override("pressed", style_active)
				btn.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35, 1.0))
			else:
				btn.add_theme_stylebox_override("normal", style_inactive)
				btn.add_theme_stylebox_override("hover", style_hover)
				btn.add_theme_stylebox_override("pressed", style_hover)
				btn.add_theme_color_override("font_color", Color(0.72, 0.68, 0.60, 0.9))

		if panel:
			panel.visible = is_cur

func update_active_view():
	match current_tab:
		0:
			if char_panel and char_panel.has_method("update_stats"):
				char_panel.update_stats()
		1:
			if inv_panel and inv_panel.has_method("update_inventory"):
				inv_panel.update_inventory()
		2:
			if spellbook_panel and spellbook_panel.has_method("update_spellbook"):
				spellbook_panel.update_spellbook()
		3:
			if quest_panel and quest_panel.has_method("update_quests"):
				quest_panel.update_quests()

func check_and_update():
	if not visible:
		return
	match current_tab:
		0:
			if char_panel and char_panel.has_method("update_stats"):
				char_panel.update_stats()
		1:
			if inv_panel and inv_panel.has_method("check_and_update"):
				inv_panel.check_and_update()
			elif inv_panel and inv_panel.has_method("update_inventory"):
				inv_panel.update_inventory()
		2:
			if spellbook_panel and spellbook_panel.has_method("check_and_update"):
				spellbook_panel.check_and_update()
			elif spellbook_panel and spellbook_panel.has_method("update_spellbook"):
				spellbook_panel.update_spellbook()
		3:
			if quest_panel and quest_panel.has_method("check_and_update"):
				quest_panel.check_and_update()
			elif quest_panel and quest_panel.has_method("update_quests"):
				quest_panel.update_quests()
