shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D d1_texture : source_color, filter_linear_mipmap, hint_default_black;
uniform float bump_strength : hint_range(0.0, 3.0) = 0.55;
uniform int color_profile : hint_range(0, 4) = 2;   // 0: Vanilla, 1: Dark Gothic, 2: Hellish Crimson (Default), 3: Crypt Cyan, 4: Noir
uniform int upscaler_mode : hint_range(0, 4) = 2;   // 0: AMD FSR CAS, 1: Anime4K Edge, 2: Anime4K Thin Lines (Default), 3: 8K Spline, 4: Native
uniform int relief_mode : hint_range(0, 4) = 3;     // 0: Off, 1: Subtle, 2: Balanced, 3: Deep 3D (Default), 4: Extreme
uniform float cas_sharpness : hint_range(0.0, 2.0) = 0.95;
uniform float playfield_zoom : hint_range(1.0, 2.5) = 1.0; // Zooms playfield ONLY, HUD stays pinned!
uniform bool engine_torches = true;                  // Engine-rendered procedural 3D flames & HDR glow
uniform bool wet_floor = true;                       // Wet cobblestone PBR reflections & specular gloss

// Comprehensive Torch, Fire & Magic Glow Detection (Yellow core, orange body, red edges, lightning)
bool is_fire_or_magic(vec3 col) {
    // Warm fire / torch / brazier / lava
    bool is_warm_fire = (col.r > 0.40 && col.g > 0.15 && col.b < 0.38 && col.r >= col.g * 0.90 && col.r > col.b * 1.5);
    // Extreme bright magic light (spells, lightning, holy shrines, gold)
    bool is_magic = (col.r > 0.82 && col.g > 0.82 && col.b > 0.55);
    return is_warm_fire || is_magic;
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

// Refined, Softer Color Grading Curves
vec3 apply_color_grading(vec3 c, int profile) {
    if (profile == 0) {
        return c; // Vanilla 1996 Classic
    }

    if (profile == 1) {
        // Dark Gothic (OLED) - Very gentle filmic curve, shadow details fully preserved
        vec3 x = max(vec3(0.0), c - 0.001);
        vec3 graded = (x * (4.2 * x + 0.35)) / (x * (4.2 * x + 1.2) + 0.04);
        graded.r = pow(graded.r, 0.98) * 1.02;
        graded.b = pow(graded.b, 1.02) * 0.97;
        return clamp(graded, 0.0, 1.0);
    } else if (profile == 2) {
        // Hellish Crimson (Default) - Warm, rich, dark dungeon ambiance
        vec3 graded = c;
        graded.r = pow(graded.r, 0.94) * 1.06;
        graded.g = pow(graded.g, 1.04) * 0.94;
        graded.b = pow(graded.b, 1.08) * 0.88;
        return clamp(graded, 0.0, 1.0);
    } else if (profile == 3) {
        // Crypt Cyan - Muted eerie chill, subtle cool tint
        vec3 graded = c;
        graded.r = pow(graded.r, 1.06) * 0.92;
        graded.g = pow(graded.g, 0.99) * 1.02;
        graded.b = pow(graded.b, 0.95) * 1.06;
        return clamp(graded, 0.0, 1.0);
    } else if (profile == 4) {
        // Desaturated Noir - Smooth filmic grayscale without harsh clipping
        float l = dot(c, vec3(0.299, 0.587, 0.114));
        vec3 graded = mix(vec3(l), c, 0.42);
        graded = pow(graded, vec3(1.05));
        return clamp(graded, 0.0, 1.0);
    }

    return c;
}

void fragment() {
    vec2 texel_size = vec2(1.0) / vec2(textureSize(d1_texture, 0));

    // Compute sample UV: Playfield zooms, but HUD stays 100% fixed at the bottom!
    vec2 sample_uv = UV;
    float hud_boundary = 0.898; // HUD is the bottom ~10% (144 / 1440 = 0.10)

    if (playfield_zoom > 1.001 && UV.y < hud_boundary) {
        vec2 playfield_center = vec2(0.5, hud_boundary * 0.5);
        vec2 zoomed_uv = playfield_center + (UV - playfield_center) / playfield_zoom;
        if (zoomed_uv.y < hud_boundary && zoomed_uv.x >= 0.0 && zoomed_uv.x <= 1.0 && zoomed_uv.y >= 0.0) {
            sample_uv = zoomed_uv;
        }
    }

    vec3 raw_pixel = texture(d1_texture, sample_uv).bgr;

    // Apply selected Upscaler
    vec3 base_color;
    if (upscaler_mode == 0) {
        // AMD FidelityFX CAS (Default)
        base_color = apply_fsr_cas(d1_texture, sample_uv, texel_size);
    } else if (upscaler_mode == 1) {
        // Anime4K / Neural Spatial CNN Edge Push
        base_color = sample_neural_edge_push(d1_texture, sample_uv, texel_size);
    } else if (upscaler_mode == 2) {
        // Anime4K Ultra Thin Lines & Vector Contours
        base_color = sample_anime4k_thin_lines(d1_texture, sample_uv, texel_size);
    } else if (upscaler_mode == 3) {
        // 8K Catmull-Rom Bicubic Spline
        base_color = sample_catmull_rom_8k(d1_texture, sample_uv, texel_size);
    } else {
        // Native 1:1 Pixel-Art
        base_color = raw_pixel;
    }

    // Check if this pixel is part of a torch flame, fire or magic glow
    // (Checked across entire playfield, excluding only bottom HUD)
    bool is_flame = engine_torches && (sample_uv.y < hud_boundary) && is_fire_or_magic(raw_pixel);

    if (is_flame) {
        // Re-draw flame dynamically with procedural engine fire & intense HDR emission!
        vec3 engine_flame = render_engine_flame(sample_uv, raw_pixel, TIME);
        ALBEDO = clamp(engine_flame, 0.0, 1.0);
        EMISSION = engine_flame * 3.5; // Blazing HDR Glow into Godot Forward+ Bloom!
        ROUGHNESS = 0.1;
    } else {
        // Normal game world vs HUD:
        if (sample_uv.y >= hud_boundary) {
            // HUD Area: 100% UNTOUCHED, pure original 1996 colors!
            ALBEDO = base_color;
        } else {
            // Playfield: Apply tuned atmospheric color grading!
            ALBEDO = apply_color_grading(base_color, color_profile);
        }
        EMISSION = vec3(0.0);
    }

    // 3D Normal Mapping & Emboss Relief
    float gx = 0.0;
    float gy = 0.0;
    if (relief_mode > 0 && !is_flame) {
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
        float mult = 0.6;
        if (relief_mode == 2) mult = 1.3;
        else if (relief_mode == 3) mult = 2.2;
        else if (relief_mode == 4) mult = 3.2;

        float strength = bump_strength * mult;
        vec3 normal_tangent = normalize(vec3(-gx * strength, -gy * strength, 1.0));
        NORMAL = (VIEW_MATRIX * vec4(normal_tangent, 0.0)).xyz;
    }

    // Wet Cobblestone PBR Specular & Roughness (Gentle, natural damp stone gloss)
    if (wet_floor && sample_uv.y < hud_boundary) {
        float edge_val = clamp(length(vec2(gx, gy)) * 1.5, 0.0, 1.0);
        // Natural damp cobblestone: soft specular gloss in crevices, no mirror reflection
        ROUGHNESS = mix(0.45, 0.78, edge_val);
        SPECULAR = mix(0.18, 0.05, edge_val);
    } else {
        ROUGHNESS = 0.88;
        SPECULAR = 0.02;
    }

    METALLIC = 0.0;
}
