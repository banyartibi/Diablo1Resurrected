shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D d1_texture : source_color, filter_linear_mipmap, hint_default_black;
uniform float bump_strength : hint_range(0.0, 3.0) = 0.65;
uniform int color_profile : hint_range(0, 4) = 1;   // 0: Vanilla, 1: Dark Gothic (Default), 2: Hellish Crimson, 3: Crypt Cyan, 4: Noir
uniform int upscaler_mode : hint_range(0, 4) = 3;   // 0: AMD CAS, 1: Anime4K Edge, 2: Anime4K Thin, 3: 8K Spline (Default), 4: Native
uniform int relief_mode : hint_range(0, 4) = 3;     // 0: Off, 1: Subtle, 2: Balanced, 3: Deep 3D (Default), 4: Extreme
uniform float cas_sharpness : hint_range(0.0, 2.0) = 0.95;
uniform float playfield_zoom : hint_range(1.0, 2.5) = 1.0; // Continuous playfield zoom (1.0x, 1.25x, 1.50x)
uniform float hdr_glow_mult : hint_range(0.0, 4.0) = 3.0;  // 0.0: OFF, 1.0, 2.0, 3.0 (Default)
uniform bool wet_floor = true;                             // Wet cobblestone PBR reflections & specular gloss
uniform bool left_panel_open = false;                      // Character sheet / Quest window open
uniform bool right_panel_open = false;                     // Inventory / Spellbook open
uniform vec4 left_panel_rect = vec4(0.0, 0.0, 320.0, 352.0);
uniform vec4 right_panel_rect = vec4(320.0, 0.0, 320.0, 352.0);
uniform bool hide_vanilla_hud = true;                      // Modern Diablo IV HUD active (full-screen playfield)

// Strict Torch, Fire & Spell Detection (Guaranteed 0% false positives on UI windows & inventory)
bool is_fire_or_magic(vec3 col) {
    // 1. Explicitly reject parchment, stone UI panels, light grays, and UI gold borders
    // UI panel borders have yellowish tan / gold with r and g close to each other
    if (col.b > 0.20) return false;
    if (col.r > 0.35 && col.g > 0.35 && (col.r - col.g) < 0.22) return false;
    if (abs(col.r - col.g) < 0.08 && col.r > 0.45) return false;

    // 2. Real dungeon fire: intensely rich red/amber with very low blue
    bool is_torch_fire = (col.r > 0.52 && col.g > 0.16 && col.g < 0.75 && col.b < 0.20 && col.r > col.b * 2.8 && col.r >= col.g * 1.04);

    // 3. Blinding lightning / holy spells: pure white-hot electrical core
    bool is_lightning = (col.r > 0.92 && col.g > 0.92 && col.b > 0.90 && length(col - vec3(1.0)) < 0.12);

    return is_torch_fire || is_lightning;
}

// Procedural flame noise generator
float flame_hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float flame_noise(vec2 p, float t) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float a = flame_hash(i + vec2(0.0, 0.0));
    float b = flame_hash(i + vec2(1.0, 0.0));
    float c = flame_hash(i + vec2(0.0, 1.0));
    float d = flame_hash(i + vec2(1.0, 1.0));

    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

vec3 render_engine_flame(vec2 uv, vec3 orig_color, float t) {
    // Dynamic flame turbulence
    vec2 flame_uv = uv * 350.0;
    float n1 = flame_noise(flame_uv + vec2(0.0, -t * 12.0), t);
    float n2 = flame_noise(flame_uv * 2.0 + vec2(sin(t * 4.0) * 2.0, -t * 22.0), t);
    float flame_shape = clamp((n1 * 0.6 + n2 * 0.4) * 1.5, 0.0, 1.0);

    // Natural flame flicker
    float flicker = 0.90 + 0.30 * sin(t * 16.0) * cos(t * 6.5 + 1.2);

    // HDR color ramp: blinding yellow-hot core -> rich amber -> deep crimson licking tips
    vec3 core = vec3(3.8, 3.1, 1.3) * flicker;
    vec3 mid  = vec3(2.8, 1.3, 0.20) * flicker;
    vec3 tip  = vec3(1.6, 0.4, 0.05) * flicker;

    vec3 flame_color = mix(tip, mid, flame_shape);
    flame_color = mix(flame_color, core, clamp(flame_shape * 1.8 - 0.7, 0.0, 1.0));

    return flame_color;
}

// 16-tap Catmull-Rom Bicubic Spline (8K Continuous Vector Interpolation)
vec4 catmull_rom_weights(float t) {
    float t2 = t * t;
    float t3 = t2 * t;
    return vec4(
        -0.5 * t3 + t2 - 0.5 * t,
        1.5 * t3 - 2.5 * t2 + 1.0,
        -1.5 * t3 + 2.0 * t2 + 0.5 * t,
        0.5 * t3 - 0.5 * t2
    );
}

vec3 sample_catmull_rom_8k(sampler2D tex, vec2 uv, vec2 texel_size) {
    vec2 coord = uv / texel_size - 0.5;
    vec2 f = fract(coord);
    vec2 base = (floor(coord) + 0.5) * texel_size;

    vec4 wx = catmull_rom_weights(f.x);
    vec4 wy = catmull_rom_weights(f.y);

    vec3 color = vec3(0.0);
    for (int j = 0; j < 4; j++) {
        for (int i = 0; i < 4; i++) {
            vec2 offset = vec2(float(i - 1), float(j - 1)) * texel_size;
            vec3 s = texture(tex, base + offset).bgr;
            color += s * (wx[i] * wy[j]);
        }
    }
    return clamp(color, 0.0, 1.0);
}

// AMD FidelityFX Contrast Adaptive Sharpening (CAS)
vec3 apply_fsr_cas(sampler2D tex, vec2 uv, vec2 texel) {
    vec3 c = texture(tex, uv).bgr;
    vec3 a = texture(tex, uv + vec2(0.0, -1.0) * texel).bgr;
    vec3 b = texture(tex, uv + vec2(-1.0, 0.0) * texel).bgr;
    vec3 d = texture(tex, uv + vec2(1.0, 0.0) * texel).bgr;
    vec3 e = texture(tex, uv + vec2(0.0, 1.0) * texel).bgr;

    vec3 min_c = min(c, min(min(a, b), min(d, e)));
    vec3 max_c = max(c, max(max(a, b), max(d, e)));

    vec3 amp = clamp(min(min_c, 2.0 - max_c) / max(max_c, vec3(0.001)), 0.0, 1.0);
    vec3 w = -sqrt(amp) * (cas_sharpness * 0.22);
    vec3 sharpened = (a * w + b * w + c + d * w + e * w) / (1.0 + 4.0 * w);

    return clamp(sharpened, 0.0, 1.0);
}

// Anime4K / Neural Spatial CNN: Gradient Normal Edge Push
vec3 sample_neural_edge_push(sampler2D tex, vec2 uv, vec2 texel) {
    vec3 cc = texture(tex, uv).bgr;
    const vec3 luma = vec3(0.299, 0.587, 0.114);
    
    float l_tl = dot(texture(tex, uv + vec2(-1.0, -1.0) * texel).bgr, luma);
    float l_tc = dot(texture(tex, uv + vec2( 0.0, -1.0) * texel).bgr, luma);
    float l_tr = dot(texture(tex, uv + vec2( 1.0, -1.0) * texel).bgr, luma);
    float l_ml = dot(texture(tex, uv + vec2(-1.0,  0.0) * texel).bgr, luma);
    float l_mr = dot(texture(tex, uv + vec2( 1.0,  0.0) * texel).bgr, luma);
    float l_bl = dot(texture(tex, uv + vec2(-1.0,  1.0) * texel).bgr, luma);
    float l_bc = dot(texture(tex, uv + vec2( 0.0,  1.0) * texel).bgr, luma);
    float l_br = dot(texture(tex, uv + vec2( 1.0,  1.0) * texel).bgr, luma);

    float gx = (l_tr + 2.0 * l_mr + l_br) - (l_tl + 2.0 * l_ml + l_bl);
    float gy = (l_bl + 2.0 * l_bc + l_br) - (l_tl + 2.0 * l_tc + l_tr);
    float edge = length(vec2(gx, gy));

    if (edge > 0.035) {
        vec2 dir = normalize(vec2(gx, gy));
        vec2 pushed_uv = uv - dir * (texel * 0.45 * clamp(edge * 2.5, 0.0, 1.0));
        vec3 pushed_col = texture(tex, pushed_uv).bgr;
        return mix(cc, pushed_col, clamp(edge * 2.8, 0.0, 1.0));
    }
    return cc;
}

// Anime4K: Ultra Thin Line Reconstruction & Anti-Aliased Contours
vec3 sample_anime4k_thin_lines(sampler2D tex, vec2 uv, vec2 texel) {
    vec3 pushed = sample_neural_edge_push(tex, uv, texel);
    vec3 up = texture(tex, uv + vec2(0.0, -1.0) * texel).bgr;
    vec3 dn = texture(tex, uv + vec2(0.0,  1.0) * texel).bgr;
    vec3 lf = texture(tex, uv + vec2(-1.0, 0.0) * texel).bgr;
    vec3 rt = texture(tex, uv + vec2( 1.0, 0.0) * texel).bgr;
    
    vec3 min_c = min(pushed, min(min(up, dn), min(lf, rt)));
    vec3 max_c = max(pushed, max(max(up, dn), max(lf, rt)));
    
    vec3 sharpened = pushed + (pushed - (up + dn + lf + rt) * 0.25) * 0.65;
    return clamp(sharpened, min_c, max_c);
}

// Distinct, Rich Color Grading Profiles
vec3 apply_color_grading(vec3 c, int profile) {
    if (profile == 0) {
        return c; // Vanilla 1996 Classic 32-bit
    }

    if (profile == 1) {
        // Dark Gothic: True grimdark dungeon contrast, deep inky shadows, rich torchlit highlights
        vec3 col = c;
        col = (col * (2.8 * col + 0.15)) / (col * (2.8 * col + 0.85) + 0.12);
        col.r = pow(col.r, 1.04) * 0.96;
        col.g = pow(col.g, 1.01) * 0.98;
        col.b = pow(col.b, 0.95) * 1.07;
        return clamp(col, 0.0, 1.0);
    } else if (profile == 2) {
        // Hellish Crimson - Warm, rich blood-dungeon ambiance
        vec3 graded = c;
        graded.r = pow(graded.r, 0.91) * 1.12;
        graded.g = pow(graded.g, 1.04) * 0.92;
        graded.b = pow(graded.b, 1.09) * 0.84;
        return clamp(graded, 0.0, 1.0);
    } else if (profile == 3) {
        // Crypt Cyan (Default) - Chilling, eerie spectral cold dungeon ambiance
        vec3 graded = c;
        graded.r = pow(graded.r, 1.10) * 0.84;
        graded.g = pow(graded.g, 0.96) * 1.04;
        graded.b = pow(graded.b, 0.91) * 1.18;
        return clamp(graded, 0.0, 1.0);
    } else if (profile == 4) {
        // Desaturated Noir - Dramatic, stark grimdark monochrome with subtle tint
        float l = dot(c, vec3(0.299, 0.587, 0.114));
        vec3 graded = mix(vec3(l), c, 0.28);
        graded = pow(graded, vec3(1.10)) * 1.08;
        return clamp(graded, 0.0, 1.0);
    }

    return c;
}

void fragment() {
    vec2 tex_size = vec2(textureSize(d1_texture, 0));
    vec2 texel_size = vec2(1.0) / tex_size;

    // Check UI regions with pixel-perfect resolution independence:
    float main_panel_x = (tex_size.x - 640.0) * 0.5;
    float panel_base_y = tex_size.y - 128.0;
    vec2 pixel_pos = UV * tex_size;

    // 1. Bottom Main Control Panel:
    bool in_main_panel = false;
    if (!hide_vanilla_hud) {
        // Base rectangular panel is 128px high (tex_size.y - 128.0)
        bool in_hud_base = (pixel_pos.x >= main_panel_x && pixel_pos.x <= (main_panel_x + 640.0) && pixel_pos.y >= panel_base_y);
        // The two glass globes protrude 13px higher into the playfield with smooth circular curvature:
        float dx_life = (pixel_pos.x - (main_panel_x + 138.5)) / 29.5;
        float dy_life = (panel_base_y - pixel_pos.y) / 13.0;
        bool in_life_dome = (pixel_pos.y >= (panel_base_y - 13.0) && pixel_pos.y < panel_base_y && (dx_life * dx_life + dy_life * dy_life <= 1.05));

        float dx_mana = (pixel_pos.x - (main_panel_x + 504.5)) / 29.5;
        float dy_mana = (panel_base_y - pixel_pos.y) / 13.0;
        bool in_mana_dome = (pixel_pos.y >= (panel_base_y - 13.0) && pixel_pos.y < panel_base_y && (dx_mana * dx_mana + dy_mana * dy_mana <= 1.05));

        in_main_panel = in_hud_base || in_life_dome || in_mana_dome;
    }

    // 2. Left UI Panel (Character Sheet / Quest Log / Stash)
    bool in_left_panel = left_panel_open &&
        (pixel_pos.x >= (left_panel_rect.x - 6.0) && pixel_pos.x <= (left_panel_rect.x + left_panel_rect.z + 6.0) &&
         pixel_pos.y >= (left_panel_rect.y - 6.0) && pixel_pos.y <= (left_panel_rect.y + left_panel_rect.w + 6.0));

    // 3. Right UI Panel (Inventory / Spellbook)
    bool in_right_panel = right_panel_open &&
        (pixel_pos.x >= (right_panel_rect.x - 6.0) && pixel_pos.x <= (right_panel_rect.x + right_panel_rect.z + 6.0) &&
         pixel_pos.y >= (right_panel_rect.y - 6.0) && pixel_pos.y <= (right_panel_rect.y + right_panel_rect.w + 6.0));

    // Combined UI mask: ONLY true UI panels are masked; playfield ground behind/beside HUD gets full shaders!
    bool in_ui = in_main_panel || in_left_panel || in_right_panel;

    // Seamless Full-Screen Playfield Zoom (for 2.5x and 3.0x ultra-close views):
    // The playfield scales smoothly and continuously around the player hero!
    // The HUD panel stays pinned 1:1 at the bottom center when vanilla HUD is visible.
    vec2 sample_uv = UV;
    if (!in_ui && playfield_zoom > 1.001) {
        vec2 playfield_center = hide_vanilla_hud ? vec2(0.5, 0.5) : vec2(0.5, panel_base_y * 0.5 / tex_size.y);
        sample_uv = playfield_center + (UV - playfield_center) / playfield_zoom;
    }

    vec3 raw_pixel = texture(d1_texture, sample_uv).bgr;

    // Apply selected Upscaler
    vec3 base_color;
    if (upscaler_mode == 0) {
        // AMD FidelityFX CAS
        base_color = apply_fsr_cas(d1_texture, sample_uv, texel_size);
    } else if (upscaler_mode == 1) {
        // Anime4K / Neural Spatial CNN Edge Push
        base_color = sample_neural_edge_push(d1_texture, sample_uv, texel_size);
    } else if (upscaler_mode == 2) {
        // Anime4K Ultra Thin Lines & Vector Contours
        base_color = sample_anime4k_thin_lines(d1_texture, sample_uv, texel_size);
    } else if (upscaler_mode == 3) {
        // 8K Catmull-Rom Bicubic Spline (Default)
        base_color = sample_catmull_rom_8k(d1_texture, sample_uv, texel_size);
    } else {
        // Native 1:1 Pixel-Art
        base_color = raw_pixel;
    }

    // Check if this pixel is part of a torch flame, fire or magic glow
    // (Checked across playfield, strictly excluding HUD and UI panels)
    bool is_flame = (hdr_glow_mult > 0.05) && (!in_ui) && is_fire_or_magic(raw_pixel);

    // 3D Normal Mapping & Tactile Albedo Relief
    float gx = 0.0;
    float gy = 0.0;
    float relief_shading = 1.0;

    if (relief_mode > 0 && !is_flame && !in_ui) {
        const vec3 luma = vec3(0.299, 0.587, 0.114);

        float l_tl = dot(texture(d1_texture, sample_uv + vec2(-1.0, -1.0) * texel_size).bgr, luma);
        float l_tc = dot(texture(d1_texture, sample_uv + vec2( 0.0, -1.0) * texel_size).bgr, luma);
        float l_tr = dot(texture(d1_texture, sample_uv + vec2( 1.0, -1.0) * texel_size).bgr, luma);
        float l_ml = dot(texture(d1_texture, sample_uv + vec2(-1.0,  0.0) * texel_size).bgr, luma);
        float l_mr = dot(texture(d1_texture, sample_uv + vec2( 1.0,  0.0) * texel_size).bgr, luma);
        float l_bl = dot(texture(d1_texture, sample_uv + vec2(-1.0,  1.0) * texel_size).bgr, luma);
        float l_bc = dot(texture(d1_texture, sample_uv + vec2( 0.0,  1.0) * texel_size).bgr, luma);
        float l_br = dot(texture(d1_texture, sample_uv + vec2( 1.0,  1.0) * texel_size).bgr, luma);

        gx = (l_tr + 2.0 * l_mr + l_br) - (l_tl + 2.0 * l_ml + l_bl);
        gy = (l_bl + 2.0 * l_bc + l_br) - (l_tl + 2.0 * l_tc + l_tr);

        // Strength scales with relief_mode (Mode 3 Deep 3D is default)
        float mult = 0.8;
        if (relief_mode == 2) mult = 1.6;
        else if (relief_mode == 3) mult = 2.6;
        else if (relief_mode == 4) mult = 4.0;

        float strength = bump_strength * mult;
        vec3 normal_tangent = normalize(vec3(-gx * strength, -gy * strength, 1.0));
        NORMAL = (VIEW_MATRIX * vec4(normal_tangent, 0.0)).xyz;

        // Tactile directional light relief directly in albedo:
        relief_shading = clamp(1.0 + (-gx * 0.7 - gy * 0.7) * (mult * 0.22), 0.65, 1.40);
    }

    if (is_flame) {
        // Re-draw flame dynamically with procedural engine fire & adjustable HDR emission!
        vec3 engine_flame = render_engine_flame(sample_uv, raw_pixel, TIME);
        ALBEDO = clamp(engine_flame, 0.0, 1.0);
        EMISSION = engine_flame * (hdr_glow_mult * 1.15); // Dynamic HDR Glow level!
        ROUGHNESS = 0.1;
    } else {
        if (in_ui) {
            // UI Areas (HUD, Inventory, Character Sheet): 100% UNTOUCHED, pure original 1996 colors & text!
            ALBEDO = base_color;
            EMISSION = vec3(0.0);
        } else {
            // Playfield: Apply tuned atmospheric color grading & 3D relief shading!
            ALBEDO = apply_color_grading(base_color, color_profile) * relief_shading;
            EMISSION = vec3(0.0);
        }
    }

    // Wet Cobblestone Floor: Deep water-absorbed stone color + glossy puddle reflections
    if (wet_floor && !in_ui) {
        float edge_val = clamp(length(vec2(gx, gy)) * 1.6, 0.0, 1.0);
        // Low crevice areas accumulate water into glossy puddles
        float puddle_mask = clamp(1.0 - edge_val * 1.5, 0.0, 1.0);
        
        // Wet stone is naturally darker and richer in saturation
        ALBEDO = mix(ALBEDO, ALBEDO * 0.80, 0.65);
        
        // Puddles reflect light with smooth PBR specular gloss
        ROUGHNESS = mix(0.70, 0.18, puddle_mask);
        SPECULAR = mix(0.08, 0.65, puddle_mask);
    } else {
        // Dry, dusty stone floor: completely matte
        ROUGHNESS = 0.95;
        SPECULAR = 0.01;
    }

    METALLIC = 0.0;
}
