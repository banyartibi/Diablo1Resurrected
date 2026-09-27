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
uniform int relief_mode : hint_range(0, 4) = 0; // 0: Off, 1: Subtle, 2: Balanced, 3: Deep 3D, 4: Extreme
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

	// De-premultiply RGB for ALL tile types where texture alpha is meaningful (floor diamonds AND wall/arche sprites): eliminates bilinear black fringe/gaps
	vec3 base_rgb = (tex.a > 0.01) ? (tex.rgb / max(tex.a, 0.02)) : tex.rgb;

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
		// Town in Diablo 1 is full clean daylight / ambient lighting:
		vec3 daylight = vec3(1.65, 1.60, 1.48);

		if (relief_mode > 0) {
			float mult = 0.35;
			if (relief_mode == 2) mult = 0.65;
			else if (relief_mode == 3) mult = 1.0;
			else if (relief_mode == 4) mult = 1.5;

			if (length(NORMAL.xy) > 0.001) {
				NORMAL = normalize(vec3(NORMAL.xy * mult * bump_scale, NORMAL.z));
			} else {
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

				float strength = 1.2 * mult * bump_scale;
				NORMAL = normalize(vec3(-gx * strength, -gy * strength, 1.0));
			}

			// Directional sunlight relief modulation across Tristram roofs, grass and cobbles
			vec3 sun_dir = normalize(vec3(-0.35, -0.55, 0.75));
			float sun_diff = dot(NORMAL, sun_dir);
			vec3 sun_tint = daylight * (0.88 + 0.12 * sun_diff);
			COLOR = vec4(base_rgb * sun_tint, final_a);
		} else {
			NORMAL = vec3(0.0, 0.0, 1.0);
			COLOR = vec4(base_rgb * daylight, final_a);
		}
	} else {
		// Dungeon lighting: smooth continuous Hermite curve with minimum ambient visibility
		float min_amb = 0.06;
		vec3 lit_tint = mix(vec3(min_amb), light_tint, l);
		COLOR = vec4(base_rgb * lit_tint, final_a);

		if (relief_mode > 0) {
			float mult = 0.35;
			if (relief_mode == 2) mult = 0.65;
			else if (relief_mode == 3) mult = 1.0;
			else if (relief_mode == 4) mult = 1.5;

			if (length(NORMAL.xy) > 0.001) {
				// Smoothly scale high-resolution pre-baked normal map from CanvasTexture
				NORMAL = normalize(vec3(NORMAL.xy * mult * bump_scale, NORMAL.z));
			} else {
				// Real-time procedural Sobel normal for levels without pre-baked PBR (Lv8 Catacombs, etc.)
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

				float strength = 1.2 * mult * bump_scale;
				NORMAL = normalize(vec3(-gx * strength, -gy * strength, 1.0));
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
		if (relief_mode > 0 && length(NORMAL.xy) > 0.001) {
			relief_factor = clamp(dot(NORMAL.xy, ldir.xy) * 0.35 + 1.0, 0.70, 1.30);
		}

		// Wet Floor specular highlights on flat stone surfaces
		vec3 wet_specular = vec3(0.0);
		bool is_floor = (TEXTURE_PIXEL_SIZE.x / TEXTURE_PIXEL_SIZE.y <= 0.55);
		if (wet_floor && is_floor) {
			float flatness = clamp(1.0 - length(NORMAL.xy) * 2.5, 0.0, 1.0);
			float spec_angle = clamp(dot(normalize(vec3(-ldir.xy * 0.6, 0.8)), NORMAL), 0.0, 1.0);
			float spec = pow(spec_angle, 14.0) * flatness * 0.35 * specular_gloss;
			wet_specular = light_color * spec * attenuation;
		}

		// Dynamic normal-map surface bump perturbation + warm torch diffuse + wet floor specular
		vec3 relief_perturbation = COLOR.rgb * ((relief_factor - 1.0) * 0.4);
		vec3 torch_diffuse = COLOR.rgb * light_color * 0.70;
		LIGHT = vec4((relief_perturbation + torch_diffuse + wet_specular) * attenuation, COLOR.a);
	} else {
		LIGHT = vec4(0.0);
	}
}
