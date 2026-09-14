shader_type canvas_item;
render_mode blend_add;

uniform vec4 color_core : source_color = vec4(1.0, 0.95, 0.80, 1.0);
uniform vec4 color_inner : source_color = vec4(1.0, 0.65, 0.15, 1.0);
uniform vec4 color_mid : source_color = vec4(0.95, 0.32, 0.03, 1.0);
uniform vec4 color_outer : source_color = vec4(0.65, 0.08, 0.01, 1.0);

uniform float flame_speed : hint_range(0.5, 4.0) = 1.9;
uniform float flame_scale : hint_range(1.0, 10.0) = 4.5;
uniform float flame_width : hint_range(0.2, 1.5) = 0.55;
uniform float intensity : hint_range(0.5, 3.0) = 1.35;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 rot = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8));
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = rot * p * 2.1 + vec2(0.35, 0.65);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	
	// Boundary fade on all 4 sides to guarantee absolutely zero box edges
	float edge_fade_x = smoothstep(0.0, 0.22, uv.x) * smoothstep(1.0, 0.78, uv.x);
	float edge_fade_y = smoothstep(0.0, 0.25, uv.y) * smoothstep(1.0, 0.88, uv.y);
	float edge_mask = edge_fade_x * edge_fade_y;
	if (edge_mask <= 0.001) {
		discard;
	}

	// Dynamic crackling flicker
	float flicker = 0.90 + 0.10 * sin(TIME * 21.0) + 0.06 * sin(TIME * 11.3) + 0.04 * cos(TIME * 37.0);

	// Tapered flame cone: wider at log base, narrower at top
	float shape_w = flame_width * mix(0.12, 0.48, pow(clamp(uv.y, 0.0, 1.0), 0.85));
	float dist_from_center = abs(uv.x - 0.5);
	float shape_cone = exp(-pow(dist_from_center / max(0.01, shape_w), 2.0));

	// Multi-octave domain warping for twisting, leaping flames
	vec2 warp_uv = uv * vec2(flame_scale * 0.8, flame_scale * 1.1);
	warp_uv.y -= TIME * flame_speed * 0.75;
	float warp_x = fbm(warp_uv) - 0.5;

	// Primary rising flame tongues
	vec2 main_uv = uv * vec2(flame_scale, flame_scale * 1.4);
	main_uv.y -= TIME * flame_speed;
	main_uv.x += warp_x * 0.75;
	float n1 = fbm(main_uv);

	// Secondary rapid lick tongues
	vec2 sec_uv = uv * vec2(flame_scale * 1.5, flame_scale * 1.9);
	sec_uv.y -= TIME * (flame_speed * 1.4);
	sec_uv.x -= warp_x * 0.4;
	float n2 = fbm(sec_uv + vec2(3.1, 7.7));

	float flame_noise = mix(n1, n2, 0.35);

	// Flame field is strictly bound to the cone and edge mask
	float flame = shape_cone * (0.45 + flame_noise * 1.1) * edge_mask * flicker * intensity;
	flame = clamp(flame, 0.0, 1.6);

	// Thermal color mapping:
	// Core hot glow -> vivid golden inner -> rich orange mid -> crimson licking tips
	vec3 col = vec3(0.0);
	if (flame > 1.1) {
		float t = clamp((flame - 1.1) / 0.4, 0.0, 1.0);
		col = mix(color_inner.rgb, color_core.rgb, t);
	} else if (flame > 0.65) {
		float t = clamp((flame - 0.65) / 0.45, 0.0, 1.0);
		col = mix(color_mid.rgb, color_inner.rgb, t);
	} else if (flame > 0.25) {
		float t = clamp((flame - 0.25) / 0.40, 0.0, 1.0);
		col = mix(color_outer.rgb, color_mid.rgb, t);
	} else if (flame > 0.05) {
		float t = clamp((flame - 0.05) / 0.20, 0.0, 1.0);
		col = mix(vec3(0.0), color_outer.rgb, t);
	}

	float alpha = clamp(flame * 1.2, 0.0, 1.0);
	COLOR = vec4(col, alpha);
}
