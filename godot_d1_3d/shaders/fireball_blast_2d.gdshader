// 2D Canvas Item version of fireball_blast.gdshader (Mode 1 Native Godot 2.5D VFX)
// Organic flame tongues with fractal turbulence, plasma core -> ember edges
shader_type canvas_item;

float flame_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float flame_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = flame_hash(i + vec2(0.0, 0.0));
	float b = flame_hash(i + vec2(1.0, 0.0));
	float c = flame_hash(i + vec2(0.0, 1.0));
	float d = flame_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.y), f.y);
}

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float raw_dist = length(uv);
	if (raw_dist > 0.52) {
		discard;
	}

	// Dynamic flame turbulence & fractal noise distortion
	float n1 = flame_noise(uv * 7.5 + vec2(0.0, -TIME * 3.0));
	float n2 = flame_noise(uv * 14.0 + vec2(TIME * 1.5, -TIME * 4.0));
	float turbulent_noise = n1 * 0.65 + n2 * 0.35;

	// Distort distance boundary into organic licking flame tongues
	float distorted_dist = raw_dist + (turbulent_noise - 0.45) * 0.28;
	if (distorted_dist > 0.5) {
		discard;
	}

	// Organic flame erosion based on particle lifetime (COLOR.a)
	float life = clamp(COLOR.a, 0.0, 1.0);
	float heat = smoothstep(0.50 * life + 0.02, 0.02, distorted_dist);
	float core = pow(heat, 3.2) * life;
	float mid  = pow(heat, 1.6);

	// Next-gen HDR temperature gradient: white-hot plasma -> amber -> deep crimson licking edges
	vec3 deep_ember = vec3(0.9, 0.15, 0.02);
	vec3 hot_orange = vec3(2.2, 0.95, 0.12);
	vec3 plasma_core = vec3(3.6, 3.2, 1.8);

	vec3 fire_color = mix(deep_ember, hot_orange, mid);
	fire_color = mix(fire_color, plasma_core, core);

	COLOR = vec4(fire_color, heat * life * 0.85);
}
