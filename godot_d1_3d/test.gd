@tool
extends SceneTree

func _init():
	print("Hello from Godot 4.7.2 headless!")
	var f = FileAccess.open("/dev/shm/d1_godot_frame", FileAccess.READ)
	if f:
		var magic = f.get_32()
		print("Found shm file, magic: 0x%X" % magic)
	else:
		print("No shm file yet (normal before game launches)")
	quit()
