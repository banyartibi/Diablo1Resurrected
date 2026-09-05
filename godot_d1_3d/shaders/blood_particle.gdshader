shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

void fragment() {
	// Teardrop droplet shape: rounded front, tapered tail along Y
	vec2 p = UV - vec2(0.5, 0.5);
	float r = length(vec2(p.x * 1.6, p.y + p.x * p.x * 0.4));
	if (r > 0.48) {
		discard;
	}

	float alpha_edge = smoothstep(0.48, 0.30, r);

	// Deep arterial gothic blood palette: thick, dark, coagulated crimson
	vec3 dark_blood = vec3(0.18, 0.008, 0.012);
	vec3 rich_blood = vec3(0.32, 0.02, 0.025);
	vec3 col = mix(rich_blood, dark_blood, smoothstep(0.15, 0.45, r));

	ALBEDO = col;
	ALPHA = COLOR.a * alpha_edge;
	ROUGHNESS = 0.22;
	SPECULAR = 0.45;
	METALLIC = 0.0;
}
