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
	// In Diablo 1: Floor tiles have aspect ratio 2:1 (height / width = 0.5).
	// In world space, the floor diamond exists within [v_foot_pos.y - 32.5, v_foot_pos.y].
	// Walls and scenery sit strictly above the floor base (v_world_pos.y < v_foot_pos.y - 32.5).
	bool is_floor = (v_world_pos.y >= (v_foot_pos.y - 32.5));

	vec4 tex = texture(TEXTURE, UV);
	if (tex.a <= 0.05) {
		discard;
	}

	// Mathematically cancel out hardware bilinear black-fringe bleed on transparent edges:
	vec3 rgb = tex.rgb / max(tex.a, 0.01);

	// For floors: use per-pixel world_pos for seamless continuous lightmap interpolation.
	// For walls: anchor lighting to the base tile center (v_foot_pos - (0, 16)).
	vec2 sample_pos = is_floor ? v_world_pos : (v_foot_pos - vec2(0.0, 16.0));

	// Convert isometric world coordinates (wx, wy) -> tile grid coordinates (tx, ty):
	// wx = (tx - ty) * 32.0
	// wy = (tx + ty) * 16.0
	// tx = wx / 64.0 + wy / 32.0
	// ty = wy / 32.0 - wx / 64.0
	vec2 tile_coord = vec2(sample_pos.x / 64.0 + sample_pos.y / 32.0, sample_pos.y / 32.0 - sample_pos.x / 64.0);
	vec2 uv_light = (tile_coord + vec2(0.5, 0.5)) / 112.0;

	float l = texture(light_map, clamp(uv_light, vec2(0.0), vec2(1.0))).r;

	// For tall walls: the bottom 32 world pixels is the floor diamond base.
	// In Diablo 1, the floor base is ALWAYS 100% solid, only the upper wall itself becomes transparent!
	// Using world space coordinates ensures resolution-independence (exact in both 1996 and 4X HD).
	float effective_a = COLOR.a;
	if (v_world_pos.y >= (v_foot_pos.y - 32.0)) {
		effective_a = 1.0;
	}

	// Floor tiles are ALWAYS 100% solid opaque (final_a = 1.0) to eliminate seam leaks.
	// Walls preserve their natural texture alpha (tex.a) modulated by effective_a so there are NEVER square quad boxes:
	float final_a = is_floor ? 1.0 : (tex.a * effective_a);

	if (is_town) {
		// Tristram authentic cool twilight ambient (warm lit areas blend in seamlessly)
		vec3 town_color = mix(vec3(0.68, 0.70, 0.74), vec3(0.96, 0.96, 0.98), l);
		COLOR = vec4(rgb * town_color, final_a);
	} else {
		// Deep atmospheric crypt ambient: tiles in darkness are minimally visible at ~2.8% visibility (97.2% darkness)
		// Allows the player to see tile layout and dungeon architecture in deep shadow without harsh black cutoffs
		vec3 dungeon_ambient = vec3(0.026, 0.028, 0.036);
		const float AMB_THRESH = 0.055; // Threshold where shadow ambient (14 / 255) starts blooming to torch light

		vec3 lit_tint;
		if (l <= AMB_THRESH) {
			lit_tint = dungeon_ambient;
		} else {
			// Room interior: smoothly transition from deep shadow ambient to warm torch lighting
			float torch_factor = clamp((l - AMB_THRESH) / (1.0 - AMB_THRESH), 0.0, 1.0);
			float factor = torch_factor * torch_factor * (3.0 - 2.0 * torch_factor);
			lit_tint = mix(dungeon_ambient, light_tint, factor);
		}

		vec3 lit = rgb * lit_tint;
		COLOR = vec4(lit, final_a);
	}
}

void light() {
	float attenuation = LIGHT_COLOR.a;
	if (COLOR.a > 0.01 && attenuation > 0.0001 && !is_town) {
		vec3 light_color = LIGHT_COLOR.rgb * LIGHT_ENERGY;
		// Smooth dynamic point lighting without harsh normal-map seam discontinuities
		LIGHT = vec4(COLOR.rgb * light_color * attenuation, COLOR.a);
	} else {
		LIGHT = vec4(0.0);
	}
}
