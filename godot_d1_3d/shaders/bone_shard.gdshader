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
	vec2 uv = abs(UV - vec2(0.5));
	float d = uv.x * 2.2 + uv.y * 1.1;
	if (d > 0.5) {
		discard;
	}
	float edge = smoothstep(0.5, 0.44, d);

	vec3 bone_base = vec3(0.92, 0.88, 0.76);
	vec3 bone_facet = mix(bone_base, bone_base * 0.72, (UV.x + UV.y) * 0.5);

	ALBEDO = bone_facet;
	ALPHA = COLOR.a * edge;
}
