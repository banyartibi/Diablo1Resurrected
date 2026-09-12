shader_type canvas_item;
render_mode blend_mix;

// Continuous 2.5D GPU Isometric Lightmap & PBR Surface Shader
// Eliminates discrete tile-by-tile checkerboards and blocky cube shadows
// Bilinear hardware GPU filtering interpolates light smoothly across every pixel

uniform sampler2D light_map : filter_linear, repeat_disable;
uniform vec3 light_tint = vec3(1.0, 0.95, 0.88);
uniform float bump_scale : hint_range(0.0, 3.0) = 1.0;
uniform float specular_gloss : hint_range(0.0, 2.0) = 0.50;
uniform bool is_town = false;

varying vec2 v_world_pos;
varying vec2 v_foot_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	v_foot_pos = MODEL_MATRIX[3].xy;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a <= 0.01) {
		discard;
	}

	// In Diablo 1: Floor height is 32. Walls have height > 32 (64, 96, 128).
	// For floors (TEXTURE_PIXEL_SIZE.y >= 0.030): use per-pixel world_pos for continuous floor lighting.
	// For walls: anchor lighting to the foot of the wall (v_foot_pos - (0, 16)) so walls are lit naturally from their center base.
	vec2 sample_pos = (TEXTURE_PIXEL_SIZE.y >= 0.030) ? v_world_pos : (v_foot_pos - vec2(0.0, 16.0));

	// Convert isometric world coordinates (wx, wy) -> tile grid coordinates (tx, ty):
	// wx = (tx - ty) * 32.0
	// wy = (tx + ty) * 16.0
	// tx = wx / 64.0 + wy / 32.0
	// ty = wy / 32.0 - wx / 64.0
	vec2 tile_coord = vec2(sample_pos.x / 64.0 + sample_pos.y / 32.0, sample_pos.y / 32.0 - sample_pos.x / 64.0);
	vec2 uv_light = (tile_coord + vec2(0.5, 0.5)) / 112.0;

	float l = texture(light_map, clamp(uv_light, vec2(0.0), vec2(1.0))).r;

	// For tall walls (height > 32): bottom 32px is the floor diamond base.
	// In Diablo 1, the floor base is ALWAYS 100% solid, only the upper wall becomes transparent!
	float effective_a = COLOR.a;
	if (TEXTURE_PIXEL_SIZE.y < 0.030 && UV.y >= (1.0 - 32.0 * TEXTURE_PIXEL_SIZE.y)) {
		effective_a = 1.0;
	}

	if (is_town) {
		// Tristram daylight/moonlight: cool shadows, warm lit areas
		vec3 town_color = mix(vec3(0.55, 0.58, 0.65), vec3(1.0, 1.0, 1.0), l);
		COLOR = vec4(tex.rgb * town_color, tex.a * effective_a);
	} else {
		// Dungeon: Modern Atmospheric Gothic Shading
		// Deep midnight crypt ambient for shadow areas (faint, moody ~4% visibility so tiles connect seamlessly)
		vec3 dungeon_ambient = vec3(0.040, 0.042, 0.055);

		// Continuous Hermite smoothstep curve for authentic gothic falloff
		float factor = l * l * (3.0 - 2.0 * l);

		// In deep shadow (factor < 0.05), keep walls solid to prevent ghost cutouts
		float final_a = mix(1.0, effective_a, clamp(factor * 10.0, 0.0, 1.0));

		vec3 lit_tint = mix(dungeon_ambient, light_tint, factor);
		vec3 lit = tex.rgb * lit_tint;
		COLOR = vec4(lit, tex.a * final_a);
	}
}

void light() {
	float attenuation = LIGHT_COLOR.a;
	if (COLOR.a > 0.01 && attenuation > 0.0001) {
		vec3 n = NORMAL;
		vec3 l = normalize(vec3(LIGHT_DIRECTION.xy, 0.5));
		float diff = max(0.0, dot(n, l));

		vec3 v = vec3(0.0, 0.0, 1.0);
		vec3 h = normalize(l + v);
		float spec = pow(max(0.0, dot(n, h)), 16.0) * specular_gloss;

		vec3 light_color = LIGHT_COLOR.rgb * LIGHT_ENERGY;
		// Subtle dynamic bump & specular highlight on top of the continuous ambient lightmap,
		// smoothly attenuated by the radial falloff of the light texture (zero rectangular edges!)
		LIGHT = vec4((COLOR.rgb * diff * 0.20 + light_color * spec) * light_color * attenuation, COLOR.a);
	} else {
		LIGHT = vec4(0.0);
	}
}
