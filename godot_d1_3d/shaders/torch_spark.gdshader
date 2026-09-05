shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);
}

void fragment() {
	float dist = length(UV - vec2(0.5));
	if (dist > 0.5) {
		discard;
	}
	float glow = exp(-dist * 14.0);
	float life = clamp(COLOR.a, 0.0, 1.0);
	ALBEDO = vec3(1.8, 1.1, 0.25) * life;
	ALPHA = life * glow;
}
