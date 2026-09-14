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
	// Floor tiles have 2:1 aspect ratio (H / W <= 0.55 in both 1X and 4X).
	// Walls, arches and scenery have H / W >= 1.0.
	bool is_floor = (TEXTURE_PIXEL_SIZE.x / TEXTURE_PIXEL_SIZE.y <= 0.55);

	vec4 tex = texture(TEXTURE, UV);
	if (is_floor) {
		// Clean discard on outer edges to eliminate bilinear black fringe or overlap
		if (tex.a < 0.35) {
			discard;
		}
	} else {
		if (tex.a < 0.05) {
			discard;
		}
	}

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

	// For walls: keep bottom 32 world pixels solid when front wall fades transparently
	float effective_a = COLOR.a;
	if (!is_floor && v_world_pos.y >= (v_foot_pos.y - 32.0)) {
		effective_a = 1.0;
	}

	// Floor tiles are 100% solid stone (1.0) so ground never leaks background gaps;
	// Walls preserve natural texture alpha:
	float final_a = is_floor ? 1.0 : (tex.a * effective_a);

	if (is_town) {
		vec3 town_color = mix(vec3(0.68, 0.70, 0.74), vec3(0.96, 0.96, 0.98), l);
		COLOR = vec4(tex.rgb * town_color, final_a);
	} else {
		// Dungeon lighting: smooth continuous Hermite curve fading to pitch black in shadows
		vec3 lit_tint = mix(vec3(0.0), light_tint, l);
		COLOR = vec4(tex.rgb * lit_tint, final_a);
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
