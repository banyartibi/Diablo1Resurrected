extends GPUParticles3D

func _ready() -> void:
	emitting = false
	one_shot = true
	restart()
	emitting = true
	var timer = get_tree().create_timer(lifetime + 0.35)
	timer.timeout.connect(queue_free)
