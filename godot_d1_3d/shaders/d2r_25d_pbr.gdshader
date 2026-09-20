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
uniform int relief_mode : hint_range(0, 4) = 3; // 0: Off, 1: Subtle, 2: Balanced, 3: Deep 3D, 4: Extreme
uniform bool wet_floor = true; // Wet cobblestone PBR reflections & specular gloss

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
	if (tex.a < 0.02) {
		discard;
	}

	// Un-premultiply RGB on floor tiles near the diamond boundary to eliminate bilinear black fringe/gaps
	vec3 base_rgb = (is_floor && tex.a > 0.01) ? (tex.rgb / max(tex.a, 0.02)) : tex.rgb;

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
		COLOR = vec4(base_rgb * town_color, final_a);
		NORMAL = vec3(0.0, 0.0, 1.0);
	} else {
		// Dungeon lighting: smooth continuous Hermite curve fading to pitch black in shadows
		vec3 lit_tint = mix(vec3(0.0), light_tint, l);
		COLOR = vec4(base_rgb * lit_tint, final_a);

		if (relief_mode > 0) {
			float mult = 0.35;
			if (relief_mode == 2) mult = 0.65;
			else if (relief_mode == 3) mult = 1.0;
			else if (relief_mode == 4) mult = 1.5;

			if (length(NORMAL.xy) > 0.001) {
				// We already have a high-resolution pre-baked normal map from CanvasTexture!
				// Scale XY bump relief smoothly; do NOT run Sobel across diamond transparency.
				NORMAL = normalize(vec3(NORMAL.xy * mult * bump_scale, NORMAL.z));
			} else if (!is_floor) {
				// Walls/columns: compute Sobel gradient from texture luma
				vec2 texel = TEXTURE_PIXEL_SIZE;
				const vec3 luma = vec3(0.299, 0.587, 0.114);
				float l_tl = dot(texture(TEXTURE, UV + vec2(-1.0, -1.0) * texel).rgb, luma);
				float l_tc = dot(texture(TEXTURE, UV + vec2( 0.0, -1.0) * texel).rgb, luma);
				float l_tr = dot(texture(TEXTURE, UV + vec2( 1.0, -1.0) * texel).rgb, luma);
				float l_ml = dot(texture(TEXTURE, UV + vec2(-1.0,  0.0) * texel).rgb, luma);
				float l_mr = dot(texture(TEXTURE, UV + vec2( 1.0,  0.0) * texel).rgb, luma);
				float l_bl = dot(texture(TEXTURE, UV + vec2(-1.0,  1.0) * texel).rgb, luma);
				float l_bc = dot(texture(TEXTURE, UV + vec2( 0.0,  1.0) * texel).rgb, luma);
				float l_br = dot(texture(TEXTURE, UV + vec2( 1.0,  1.0) * texel).rgb, luma);

				float gx = (l_tr + 2.0 * l_mr + l_br) - (l_tl + 2.0 * l_ml + l_bl);
				float gy = (l_bl + 2.0 * l_bc + l_br) - (l_tl + 2.0 * l_tc + l_tr);

				NORMAL = normalize(vec3(-gx * mult * bump_scale, -gy * mult * bump_scale, 1.0));
			} else {
				// Floor tiles fallback without baked normal map:
				// Clamp neighbor samples outside diamond to center luma to prevent border cliffs
				vec2 texel = TEXTURE_PIXEL_SIZE;
				const vec3 luma = vec3(0.299, 0.587, 0.114);
				float l_c = dot(base_rgb, luma);
				vec4 s_tl = texture(TEXTURE, UV + vec2(-1.0, -1.0) * texel);
				vec4 s_tc = texture(TEXTURE, UV + vec2( 0.0, -1.0) * texel);
				vec4 s_tr = texture(TEXTURE, UV + vec2( 1.0, -1.0) * texel);
				vec4 s_ml = texture(TEXTURE, UV + vec2(-1.0,  0.0) * texel);
				vec4 s_mr = texture(TEXTURE, UV + vec2( 1.0,  0.0) * texel);
				vec4 s_bl = texture(TEXTURE, UV + vec2(-1.0,  1.0) * texel);
				vec4 s_bc = texture(TEXTURE, UV + vec2( 0.0,  1.0) * texel);
				vec4 s_br = texture(TEXTURE, UV + vec2( 1.0,  1.0) * texel);

				float l_tl = (s_tl.a > 0.1) ? dot(s_tl.rgb, luma) : l_c;
				float l_tc = (s_tc.a > 0.1) ? dot(s_tc.rgb, luma) : l_c;
				float l_tr = (s_tr.a > 0.1) ? dot(s_tr.rgb, luma) : l_c;
				float l_ml = (s_ml.a > 0.1) ? dot(s_ml.rgb, luma) : l_c;
				float l_mr = (s_mr.a > 0.1) ? dot(s_mr.rgb, luma) : l_c;
				float l_bl = (s_bl.a > 0.1) ? dot(s_bl.rgb, luma) : l_c;
				float l_bc = (s_bc.a > 0.1) ? dot(s_bc.rgb, luma) : l_c;
				float l_br = (s_br.a > 0.1) ? dot(s_br.rgb, luma) : l_c;

				float gx = (l_tr + 2.0 * l_mr + l_br) - (l_tl + 2.0 * l_ml + l_bl);
				float gy = (l_bl + 2.0 * l_bc + l_br) - (l_tl + 2.0 * l_tc + l_tr);

				NORMAL = normalize(vec3(-gx * mult * bump_scale, -gy * mult * bump_scale, 1.0));
			}
		} else {
			NORMAL = vec3(0.0, 0.0, 1.0);
		}
	}
}

void light() {
	float attenuation = LIGHT_COLOR.a;
	if (COLOR.a > 0.01 && attenuation > 0.0001 && !is_town) {
		vec3 light_color = LIGHT_COLOR.rgb * LIGHT_ENERGY;

		// 3D Surface Relief bump modulation
		float relief_factor = 1.0;
		vec3 ldir = (length(LIGHT_DIRECTION) > 0.001) ? normalize(LIGHT_DIRECTION) : vec3(0.0, 1.0, 0.0);
		if (relief_mode > 0) {
			relief_factor = clamp(dot(NORMAL.xy, ldir.xy) * 0.35 + 0.90, 0.65, 1.25);
		}

		// Wet Floor specular highlights on flat stone surfaces
		vec3 wet_specular = vec3(0.0);
		bool is_floor = (TEXTURE_PIXEL_SIZE.x / TEXTURE_PIXEL_SIZE.y <= 0.55);
		if (wet_floor && is_floor) {
			float flatness = clamp(1.0 - length(NORMAL.xy) * 2.5, 0.0, 1.0);
			float spec_angle = clamp(dot(normalize(vec3(-ldir.xy * 0.6, 0.8)), NORMAL), 0.0, 1.0);
			float spec = pow(spec_angle, 14.0) * flatness * 0.40 * specular_gloss;
			wet_specular = light_color * spec * attenuation;
		}

		LIGHT = vec4(COLOR.rgb * light_color * attenuation * relief_factor + wet_specular, COLOR.a);
	} else {
		LIGHT = vec4(0.0);
	}
}
