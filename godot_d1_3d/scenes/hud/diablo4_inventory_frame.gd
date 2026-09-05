extends Control

var diablo_bridge = null

@onready var close_btn: Button = get_node_or_null("BottomFrame/CloseBtn")

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if close_btn:
		close_btn.pressed.connect(func():
			if diablo_bridge and diablo_bridge.has_method("toggle_inventory"):
				diablo_bridge.toggle_inventory()
			visible = false
		)

func set_bridge(bridge):
	diablo_bridge = bridge
