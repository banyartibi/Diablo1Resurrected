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
	vec2 uv = UV - vec2(0.5);
	float dist = length(uv);
	if (dist > 0.5) {
		discard;
	}

	float heat = smoothstep(0.5, 0.05, dist);
	float core = pow(heat, 3.0);
	float mid  = pow(heat, 1.4);

	vec3 fire_color = mix(vec3(1.6, 0.35, 0.04), vec3(3.0, 1.6, 0.18), mid);
	fire_color = mix(fire_color, vec3(4.2, 3.8, 2.0), core);

	ALBEDO = fire_color;
	ALPHA = COLOR.a * heat;
}
