shader_type canvas_item;

uniform vec4 ember_color_core : source_color = vec4(1.0, 0.9, 0.4, 1.0);
uniform vec4 ember_color_edge : source_color = vec4(1.0, 0.35, 0.05, 0.8);
uniform float density : hint_range(5.0, 60.0) = 28.0;
uniform float speed : hint_range(0.1, 2.0) = 0.55;
uniform float turbulence : hint_range(0.1, 3.0) = 1.2;

uniform float fire_origin_x : hint_range(0.0, 1.0) = 0.38;
uniform float fire_spread : hint_range(0.05, 1.0) = 0.22;

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

void fragment() {
	vec2 uv = UV;
	float t = TIME * speed;
	vec3 final_color = vec3(0.0);
	float total_alpha = 0.0;

	// Cone plume mask: embers rise from fire pit and spread upward
	float plume_w = fire_spread * (0.45 + (1.0 - uv.y) * 1.4);
	float plume_mask = exp(-pow((uv.x - fire_origin_x) / max(0.01, plume_w), 2.0));
	float height_mask = smoothstep(0.85, 0.68, uv.y) * smoothstep(0.02, 0.25, uv.y);
	float mask = plume_mask * height_mask;

	// Layered embers drifting upwards with turbulent wave motion
	for (int layer = 0; layer < 3; layer++) {
		float scale = density * (1.0 + float(layer) * 0.7);
		float layer_speed = (0.7 + float(layer) * 0.3) * speed;
		vec2 layer_uv = uv * vec2(scale, scale * 0.5);
		layer_uv.y += TIME * layer_speed;
		layer_uv.x += sin(layer_uv.y * 0.5 + TIME * turbulence) * 0.4;

		vec2 cell_id = floor(layer_uv);
		vec2 cell_uv = fract(layer_uv);

		float rnd = hash(cell_id + float(layer) * 17.13);
		if (rnd > 0.35) {
			vec2 spark_pos = vec2(
				0.2 + 0.6 * hash(cell_id + vec2(1.1, 2.2)),
				0.2 + 0.6 * hash(cell_id + vec2(3.3, 4.4))
			);
			float d = length(cell_uv - spark_pos);
			float spark_size = (0.04 + 0.06 * rnd) * (1.0 - uv.y * 0.5);
			float spark = smoothstep(spark_size, 0.0, d);

			// Flicker modulation
			float flicker = 0.7 + 0.3 * sin(TIME * (10.0 + rnd * 15.0) + rnd * 6.28);
			float spark_intensity = spark * flicker * mask;

			vec3 col = mix(ember_color_edge.rgb, ember_color_core.rgb, spark);
			final_color += col * spark_intensity * (0.8 + 0.4 * float(layer));
			total_alpha += spark_intensity;
		}
	}

	COLOR = vec4(final_color, clamp(total_alpha, 0.0, 0.95));
}
