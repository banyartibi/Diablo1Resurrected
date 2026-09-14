shader_type canvas_item;

uniform vec4 fire_tint : source_color = vec4(1.0, 0.6, 0.2, 1.0);
uniform vec4 moon_tint : source_color = vec4(0.3, 0.45, 0.7, 1.0);
uniform float fire_intensity : hint_range(0.0, 2.0) = 0.55;
uniform float moon_intensity : hint_range(0.0, 2.0) = 0.30;
uniform float breathing_amplitude : hint_range(0.0, 0.05) = 0.008;
uniform float breathing_speed : hint_range(0.1, 4.0) = 1.6;
uniform float fire_side : hint_range(-1.0, 1.0) = 1.0; // 1.0 = fire on right, -1.0 = fire on left

void vertex() {
	// Subtle breathing idle animation
	float breath = sin(TIME * breathing_speed) * breathing_amplitude;
	VERTEX.y += (1.0 - UV.y) * breath * 15.0;
}

void fragment() {
	vec4 base_tex = texture(TEXTURE, UV);
	if (base_tex.a < 0.02) {
		discard;
	}
	
	// Campfire light origin: dynamic depending on fire_side
	float fire_x = mix(0.15, 0.85, clamp(fire_side * 0.5 + 0.5, 0.0, 1.0));
	vec2 fire_origin = vec2(fire_x, 0.95);
	float fire_dist = length(UV - fire_origin);
	float fire_factor = exp(-fire_dist * 2.0) * fire_intensity;
	float fire_flicker = 0.88 + 0.12 * sin(TIME * 7.3) * cos(TIME * 4.1);
	fire_factor *= fire_flicker;
	
	// Moonlight rim from opposite side
	float moon_x = 1.0 - fire_x;
	vec2 moon_origin = vec2(moon_x, 0.10);
	float moon_dist = length(UV - moon_origin);
	float moon_factor = exp(-moon_dist * 2.2) * moon_intensity;
	
	vec3 lit_color = base_tex.rgb;
	lit_color += fire_tint.rgb * fire_factor * base_tex.rgb * 1.5;
	lit_color += moon_tint.rgb * moon_factor * 0.35;
	
	COLOR = vec4(lit_color, base_tex.a);
}
