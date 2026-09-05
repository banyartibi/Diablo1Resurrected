shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

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

	float edge = smoothstep(0.48, 0.20, dist);
	float glint = smoothstep(0.14, 0.0, length(uv - vec2(-0.12, -0.12)));

	vec3 base_blood = vec3(0.55, 0.015, 0.025);
	vec3 deep_edge = vec3(0.22, 0.005, 0.01);
	vec3 blood_col = mix(base_blood, deep_edge, smoothstep(0.18, 0.48, dist));
	blood_col = mix(blood_col, vec3(1.0, 0.55, 0.55), glint * 0.7);

	ALBEDO = blood_col;
	ALPHA = COLOR.a * edge;
}
