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
	float glow = exp(-dist * 8.0);
	ALBEDO = vec3(2.5, 1.6, 0.4);
	ALPHA = COLOR.a * glow;
}
