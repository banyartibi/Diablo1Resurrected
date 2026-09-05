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

	// Deep arterial gothic blood palette: glistening, rich, coagulated crimson
	vec3 dark_blood = vec3(0.22, 0.010, 0.015);
	vec3 rich_blood = vec3(0.48, 0.028, 0.038);
	vec3 col = mix(rich_blood, dark_blood, smoothstep(0.12, 0.46, r));

	// Subtle wet liquid fresnel glint to catch torchlight against dark dungeon cobblestones
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);

	ALBEDO = col + vec3(0.10, 0.015, 0.02) * fresnel;
	ALPHA = COLOR.a * alpha_edge;
	ROUGHNESS = 0.14;
	SPECULAR = 0.70;
	METALLIC = 0.0;
}
