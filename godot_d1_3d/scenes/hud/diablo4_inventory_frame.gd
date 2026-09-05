extends Control

var diablo_bridge = null

@onready var close_btn: Button = find_child("CloseBtn", true, false)

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if close_btn:
		close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		close_btn.pressed.connect(func():
			if diablo_bridge and diablo_bridge.has_method("toggle_inventory"):
				diablo_bridge.toggle_inventory()
			visible = false
		)

func set_bridge(bridge):
	diablo_bridge = bridge
