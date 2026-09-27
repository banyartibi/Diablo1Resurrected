// 2D Canvas Item version of blood_particle.gdshader (Mode 1 Native Godot 2.5D VFX)
// Teardrop droplet shape: rounded front, tapered tail along Y
shader_type canvas_item;

void fragment() {
	vec2 p = UV - vec2(0.5, 0.5);
	float r = length(vec2(p.x * 1.6, p.y + p.x * p.x * 0.4));
	if (r > 0.48) {
		discard;
	}

	float alpha_edge = smoothstep(0.48, 0.30, r);

	// Deep arterial gothic blood palette: visceral, rich, coagulated crimson
	vec3 dark_blood = vec3(0.35, 0.015, 0.02);
	vec3 rich_blood = vec3(0.65, 0.035, 0.045);
	vec3 col = mix(rich_blood, dark_blood, smoothstep(0.10, 0.46, r));

	COLOR = vec4(col, COLOR.a * alpha_edge);
}
