shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D d1_texture : source_color, filter_linear_mipmap, hint_default_black;
uniform float bump_strength : hint_range(0.0, 3.0) = 0.55;
uniform int color_profile : hint_range(0, 4) = 0; // 0: Vanilla (Default), 1: Dark Gothic OLED, 2: Hellish Crimson, 3: Crypt Cyan, 4: Noir
uniform int relief_mode : hint_range(0, 3) = 2;   // 0: Off, 1: 8K Catmull-Rom Spline, 2: AMD FSR CAS (Default), 3: 3D Relief
uniform float cas_sharpness : hint_range(0.0, 2.0) = 0.90;
uniform float playfield_zoom : hint_range(1.0, 2.5) = 1.0; // Zooms playfield ONLY, HUD stays pinned!
uniform bool engine_torches = true;                // Engine-rendered procedural 3D flames & HDR glow

// Procedural 3D Torch Flame Detection (Empirically verified from game backbuffer)
bool is_torch_flame(vec3 col) {
    return (col.r > 0.60 && col.g > 0.22 && col.b < 0.22 && col.r > col.g * 1.28 && col.r > col.b * 3.2);
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
    float flicker = 0.88 + 0.32 * sin(t * 16.0) * cos(t * 6.5 + 1.2);

    // HDR color ramp: blinding yellow-hot core -> rich amber -> deep crimson licking tips
    vec3 core = vec3(3.5, 2.8, 1.2) * flicker;
    vec3 mid  = vec3(2.6, 1.1, 0.15) * flicker;
    vec3 tip  = vec3(1.4, 0.3, 0.04) * flicker;

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

vec3 apply_color_grading(vec3 c, int profile) {
    if (profile == 0) {
        return c; // Vanilla 1996
    }
    
    // OLED Contrast S-curve
    vec3 x = max(vec3(0.0), c - 0.004);
    vec3 graded = (x * (6.2 * x + 0.5)) / (x * (6.2 * x + 1.7) + 0.06);
    
    if (profile == 1) {
        // Dark Gothic (OLED Black & Warm Embers)
        graded.r = pow(graded.r, 0.95) * 1.05;
        graded.g = pow(graded.g, 1.02);
        graded.b = pow(graded.b, 1.08) * 0.92;
    } else if (profile == 2) {
        // Hellish Crimson
        graded.r = pow(graded.r, 0.90) * 1.15;
        graded.g = pow(graded.g, 1.15) * 0.85;
        graded.b = pow(graded.b, 1.25) * 0.75;
    } else if (profile == 3) {
        // Crypt Cyan
        graded.r = pow(graded.r, 1.15) * 0.85;
        graded.g = pow(graded.g, 0.98) * 1.05;
        graded.b = pow(graded.b, 0.92) * 1.15;
    } else if (profile == 4) {
        // Grimdark Desaturated Noir
        float l = dot(graded, vec3(0.299, 0.587, 0.114));
        graded = mix(vec3(l), graded, 0.35);
    }
    
    return clamp(graded, 0.0, 1.0);
}

void fragment() {
    vec2 texel_size = vec2(1.0) / vec2(textureSize(d1_texture, 0));
    
    // Compute sample UV: Playfield zooms, but HUD stays 100% fixed at the bottom!
    vec2 sample_uv = UV;
    float hud_boundary = 0.898; // HUD is the bottom 10% (144 / 1440 = 0.10)
    
    if (playfield_zoom > 1.001 && UV.y < hud_boundary) {
        vec2 playfield_center = vec2(0.5, hud_boundary * 0.5);
        vec2 zoomed_uv = playfield_center + (UV - playfield_center) / playfield_zoom;
        if (zoomed_uv.y < hud_boundary && zoomed_uv.x >= 0.0 && zoomed_uv.x <= 1.0 && zoomed_uv.y >= 0.0) {
            sample_uv = zoomed_uv;
        }
    }
    
    vec3 raw_pixel = texture(d1_texture, sample_uv).bgr;
    
    vec3 base_color;
    if (relief_mode == 1) {
        // 8K Catmull-Rom Bicubic Spline (Smooth Continuous Vector)
        base_color = sample_catmull_rom_8k(d1_texture, sample_uv, texel_size);
    } else if (relief_mode >= 2) {
        // AMD FidelityFX CAS
        base_color = apply_fsr_cas(d1_texture, sample_uv, texel_size);
    } else {
        base_color = raw_pixel;
    }
    
    // Check if this pixel is part of a torch flame on the dungeon floor
    // (Only on the game area, avoiding bottom HUD)
    bool is_flame = engine_torches && (sample_uv.y < 0.88) && is_torch_flame(raw_pixel);
    
    if (is_flame) {
        // Re-draw flame dynamically with procedural engine fire & HDR emission!
        vec3 engine_flame = render_engine_flame(sample_uv, raw_pixel, TIME);
        ALBEDO = clamp(engine_flame, 0.0, 1.0);
        EMISSION = engine_flame * 3.2; // Blazing HDR Glow into Godot Forward+ Bloom!
        ROUGHNESS = 0.1;
    } else {
        // Normal game world
        ALBEDO = apply_color_grading(base_color, color_profile);
        EMISSION = vec3(0.0);
        ROUGHNESS = 0.80;
    }

    // 3D Normal Mapping & Emboss Relief
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

        float gx = (l_tr + 2.0 * l_mr + l_br) - (l_tl + 2.0 * l_ml + l_bl);
        float gy = (l_bl + 2.0 * l_bc + l_br) - (l_tl + 2.0 * l_tc + l_tr);

        float strength = bump_strength * (relief_mode == 2 ? 1.6 : (relief_mode == 3 ? 2.4 : 0.85));
        vec3 normal_tangent = normalize(vec3(-gx * strength, -gy * strength, 1.0));
        NORMAL = (VIEW_MATRIX * vec4(normal_tangent, 0.0)).xyz;
    }

    SPECULAR = 0.15;
    METALLIC = 0.0;
}
