extends GPUParticles2D

func _ready() -> void:
	one_shot = true
	emitting = true
	restart()
	var duration: float = lifetime / maxf(speed_scale, 0.01) + 0.5
	get_tree().create_timer(duration).timeout.connect(queue_free)
