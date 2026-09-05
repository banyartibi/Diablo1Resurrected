shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

void fragment() {
	vec2 uv = abs(UV - vec2(0.5));
	float d = uv.x * 2.5 + uv.y * 1.2;
	if (d > 0.48) {
		discard;
	}
	float edge = smoothstep(0.48, 0.38, d);

	// Aged ivory / ancient bone color with facet variation
	vec3 bone_base = vec3(0.88, 0.85, 0.74);
	vec3 bone_shade = vec3(0.65, 0.60, 0.50);
	vec3 col = mix(bone_base, bone_shade, (UV.x + UV.y) * 0.5);

	ALBEDO = col;
	ALPHA = COLOR.a * edge;
	ROUGHNESS = 0.55;
	SPECULAR = 0.25;
	METALLIC = 0.0;
}
