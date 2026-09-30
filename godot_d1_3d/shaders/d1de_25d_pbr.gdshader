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

	// Isometric diamond edge distance for seamless tile boundaries:
	// In 2:1 isometric UVs, (abs(UV.x - 0.5) + abs(UV.y - 0.5)) * 2.0 equals 1.0 exactly at the diamond perimeter.
	float diamond_dist = 1.0 - 2.0 * (abs(UV.x - 0.5) + abs(UV.y - 0.5));
	float edge_fade = is_floor ? clamp(diamond_dist * 10.0, 0.0, 1.0) : clamp(min(UV.x, 1.0 - UV.x) * 20.0, 0.0, 1.0);

	vec2 final_uv = UV;
	if (relief_mode >= 3 && edge_fade > 0.01) {
		// Parallax Occlusion Mapping (POM)
		// Isometric view vector (~35 deg slant towards South/down)
		vec2 view_dir = vec2(0.0, 0.45);
		// Scale height smoothly to 0 at the boundary so adjacent tiles never disconnect
		float h_scale = (relief_mode == 4 ? 0.010 : 0.005) * bump_scale * edge_fade;

		const int pom_steps = 6;
		float step_size = 1.0 / float(pom_steps);
		vec2 step_delta = view_dir * (h_scale / float(pom_steps));

		vec2 curr_uv = UV;
		float curr_depth = 0.0;
		float curr_height = 1.0 - dot(texture(TEXTURE, curr_uv).rgb, vec3(0.299, 0.587, 0.114));

		for (int i = 0; i < pom_steps; i++) {
			if (curr_depth >= curr_height) {
				break;
			}
			vec2 next_uv = curr_uv + step_delta;
			// Guard against POM raymarching outside the tile diamond
			if (texture(TEXTURE, next_uv).a < 0.10) {
				break;
			}
			curr_uv = next_uv;
			curr_depth += step_size;
			curr_height = 1.0 - dot(texture(TEXTURE, curr_uv).rgb, vec3(0.299, 0.587, 0.114));
		}
		final_uv = curr_uv;
	}

	// A tile is in the floor row if it is a 1-row tile OR if this fragment is in the bottom 32 world pixels of a multi-row piece
	bool in_floor_row = is_floor || (v_world_pos.y >= (v_foot_pos.y - 32.5));

	vec4 tex = texture(TEXTURE, final_uv);
	if (tex.a < 0.05) {
		discard;
	}

	// Direct straight alpha RGB (textures have clean Voronoi color dilation into 0-alpha margins)
	vec3 base_rgb = tex.rgb;

	// For floor rows: use per-pixel world_pos for seamless continuous lightmap interpolation.
	// For upper walls: anchor lighting to the base tile center (v_foot_pos - (0, 16)).
	vec2 sample_pos = in_floor_row ? v_world_pos : (v_foot_pos - vec2(0.0, 16.0));

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

	// Floor rows are 100% solid stone (1.0) so ground never leaks black background gaps;
	// Upper walls preserve natural texture alpha:
	float final_a = in_floor_row ? 1.0 : (tex.a * effective_a);

	if (is_town) {
		// Town in Diablo 1 is full clean daylight / ambient lighting:
		vec3 daylight = vec3(1.65, 1.60, 1.48);

		// Dynamic River Water Flow Simulation (Tristram river)
		// Tristram water occurs on ground rows (in_floor_row) and has authentic slate-blue/cyan tones:
		bool is_water = in_floor_row && (base_rgb.b > base_rgb.r * 1.15 && base_rgb.b > 0.05 && base_rgb.b > base_rgb.g * 0.88 && base_rgb.r < 0.22);
		if (is_water) {
			vec2 flow_dir = vec2(-0.7, 0.7); // Tristram river flow direction (NE to SW)
			vec2 river_flow = (flow_dir * sin(TIME * 2.0 + (v_world_pos.x + v_world_pos.y) * 0.03) +
			                   vec2(-flow_dir.y, flow_dir.x) * cos(TIME * 1.6 + (v_world_pos.x - v_world_pos.y) * 0.04)) * (0.016 * edge_fade);

			vec4 flow_tex = texture(TEXTURE, UV + river_flow);
			if (flow_tex.a > 0.10) {
				base_rgb = flow_tex.rgb;
			}

			// Gentle sun glint ripple and caustic wave on the water surface
			float wave1 = sin(dot(v_world_pos, vec2(0.05, 0.04)) - TIME * 2.5);
			float wave2 = cos(dot(v_world_pos, vec2(-0.04, 0.06)) + TIME * 2.0);
			float wave3 = sin(dot(v_world_pos, vec2(0.08, -0.06)) - TIME * 3.0);
			float caustic = clamp(wave1 * 0.4 + wave2 * 0.4 + wave3 * 0.2 + 0.35, 0.0, 1.0);
			float shimmer = pow(caustic, 2.5);
			vec3 water_shimmer = vec3(0.08, 0.16, 0.28) * shimmer;
			base_rgb += water_shimmer * edge_fade;
		}

		if (relief_mode > 0) {
			float mult = 0.35;
			if (relief_mode == 2) mult = 0.65;
			else if (relief_mode == 3) mult = 1.0;
			else if (relief_mode == 4) mult = 1.5;

			if (is_water) {
				float w1 = sin(dot(v_world_pos, vec2(0.05, 0.04)) - TIME * 2.5);
				float w2 = cos(dot(v_world_pos, vec2(-0.04, 0.06)) + TIME * 2.0);
				NORMAL = normalize(vec3(vec2(w1, w2) * 0.45 * mult * edge_fade, 1.0));
			} else if (length(NORMAL.xy) > 0.001) {
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

		// Dynamic Liquid Simulation (Hell blood/lava + Caves molten magma)
		// Caves magma: bright orange/yellow (r > 0.24, r > b * 1.7, g > b * 0.75)
		// Hell magma/blood river: intense deep crimson (r > 0.20, r > g * 1.30, r > b * 1.30)
		bool is_caves_lava = (base_rgb.r > 0.24 && base_rgb.r > base_rgb.b * 1.7 && base_rgb.g > base_rgb.b * 0.75);
		bool is_hell_lava = (base_rgb.r > 0.20 && base_rgb.r > base_rgb.g * 1.30 && base_rgb.r > base_rgb.b * 1.30);
		bool is_lava = in_floor_row && (is_caves_lava || is_hell_lava);
		if (is_lava) {
			// Continuous fluid displacement: fade to 0 at perimeter so adjacent tiles stay seamless
			vec2 lava_flow = vec2(
				sin(v_world_pos.y * 0.05 + TIME * 2.2) + cos(v_world_pos.x * 0.04 + TIME * 1.5),
				cos(v_world_pos.x * 0.04 + TIME * 1.8) + sin(v_world_pos.y * 0.04 + TIME * 2.0)
			) * (0.016 * edge_fade);

			vec4 flow_tex = texture(TEXTURE, UV + lava_flow);
			if (flow_tex.a > 0.10) {
				base_rgb = flow_tex.rgb;
			}

			// Magma heat wave cycling across the entire lake
			float wave1 = sin(dot(v_world_pos, vec2(0.05, 0.04)) - TIME * 2.8) * 0.5 + 0.5;
			float wave2 = cos(dot(v_world_pos, vec2(-0.04, 0.05)) + TIME * 2.2) * 0.5 + 0.5;
			float wave3 = sin(dot(v_world_pos, vec2(0.03, -0.06)) - TIME * 1.8) * 0.5 + 0.5;
			float heat_cycle = clamp(wave1 * 0.5 + wave2 * 0.3 + wave3 * 0.2, 0.0, 1.0);

			vec3 cool_lava = is_hell_lava ? vec3(0.70, 0.06, 0.02) : vec3(0.85, 0.20, 0.02);
			vec3 hot_lava  = is_hell_lava ? vec3(1.15, 0.25, 0.05) : vec3(1.18, 0.58, 0.06);
			vec3 sear_lava = is_hell_lava ? vec3(1.45, 0.55, 0.15) : vec3(1.40, 1.02, 0.30);
			vec3 heat_color = (heat_cycle < 0.5) ? mix(cool_lava, hot_lava, heat_cycle * 2.0) : mix(hot_lava, sear_lava, (heat_cycle - 0.5) * 2.0);

			base_rgb = mix(base_rgb, base_rgb * heat_color, 0.65);
			lit_tint = max(lit_tint, is_hell_lava ? vec3(1.35, 0.65, 0.50) : vec3(1.25, 0.95, 0.70));
		}

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
				// Real-time procedural Sobel normal for levels without pre-baked PBR
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

		// PBR Physical Material Properties from ORM (CanvasTexture.specular_texture)
		// SPECULAR_SHININESS.r = Ambient Occlusion (AO)
		// SPECULAR_SHININESS.g = Roughness
		// SPECULAR_SHININESS.b = Metallic
		vec4 orm = SPECULAR_SHININESS;
		float ao = (orm.r > 0.02) ? orm.r : 1.0;
		float roughness = (orm.g > 0.02) ? clamp(orm.g, 0.10, 1.0) : 0.85;
		float metallic = orm.b;

		// Wet Floor & PBR Specular Highlights
		vec3 pbr_specular = vec3(0.0);
		bool is_floor = (TEXTURE_PIXEL_SIZE.x / TEXTURE_PIXEL_SIZE.y <= 0.55);
		if (wet_floor && is_floor) {
			// Microfacet specular GGX approximation
			vec3 half_vector = normalize(vec3(-ldir.xy * 0.5, 0.85));
			float NdotH = clamp(dot(NORMAL, half_vector), 0.0, 1.0);
			float NdotL = clamp(dot(NORMAL, ldir), 0.0, 1.0);

			float alpha_rough = roughness * roughness;
			float d_denom = (NdotH * NdotH * (alpha_rough * alpha_rough - 1.0) + 1.0);
			float D = (alpha_rough * alpha_rough) / max(3.14159 * d_denom * d_denom, 0.001);

			vec3 f0 = mix(vec3(0.04), COLOR.rgb, metallic);
			vec3 F = f0 + (vec3(1.0) - f0) * pow(clamp(1.0 - dot(half_vector, ldir), 0.0, 1.0), 5.0);

			pbr_specular = (D * F * 0.35) * light_color * NdotL * specular_gloss;
		}

		// Dynamic normal-map surface bump perturbation + warm torch diffuse (modulated by AO) + PBR specular
		vec3 relief_perturbation = COLOR.rgb * ((relief_factor - 1.0) * 0.4);
		vec3 torch_diffuse = COLOR.rgb * light_color * (0.70 * ao);
		LIGHT = vec4((relief_perturbation + torch_diffuse + pbr_specular) * attenuation, COLOR.a);
	} else {
		LIGHT = vec4(0.0);
	}
}
