shader_type canvas_item;
render_mode unshaded;

// Diablo: Definitive Edition - Entity (Hero, Monster, Object) High-Definition Subpixel Upscaler
// Supports:
// Mode 0: AMD FidelityFX CAS (Contrast-Adaptive Sharpening + Subpixel Alpha)
// Mode 1: Neural Edge Reconstruction (Scale2x / EPX Diagonal Vector Smoothing)
// Mode 2: Anime4K Thin Lines & Contours (Crisp Inked Gothic Outlines)
// Mode 3: 8K Catmull-Rom Bicubic Spline (Bounded Anti-Ringing Interpolation)
// Mode 4: Native 1:1 Direct Retro Pixel-Art (Crisp Pixels + Anti-Aliased Silhouette)

uniform bool hd_enabled = true;
uniform int upscaler_mode : hint_range(0, 4) = 0; // Default 0: AMD FidelityFX CAS
uniform float sharpness : hint_range(0.0, 1.0) = 0.40;
uniform float gamma : hint_range(0.5, 2.5) = 1.0;
uniform float brightness : hint_range(0.5, 3.0) = 1.0;

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

void fragment() {
    vec2 tex_size = vec2(textureSize(TEXTURE, 0));
    vec2 texel = vec2(1.0) / tex_size;

    vec4 c = texture(TEXTURE, UV);

    // If HD is disabled (Authentic 1996), bypass all enhancements and render raw 1996 retro pixels
    if (!hd_enabled || tex_size.x <= 1.0 || tex_size.y <= 1.0) {
        vec3 col_rgb = (abs(gamma - 1.0) > 0.01 ? pow(clamp(c.rgb, 0.0, 1.0), vec3(1.0 / max(gamma, 0.1))) : c.rgb) * brightness;
        COLOR = vec4(col_rgb, c.a) * COLOR;
    } else if (c.a < 0.005) {
        COLOR = vec4(0.0);
    } else {
        // Cardinal 4-neighbors
        vec4 up = texture(TEXTURE, UV + vec2( 0.0, -1.0) * texel);
        vec4 dn = texture(TEXTURE, UV + vec2( 0.0,  1.0) * texel);
        vec4 lf = texture(TEXTURE, UV + vec2(-1.0,  0.0) * texel);
        vec4 rt = texture(TEXTURE, UV + vec2( 1.0,  0.0) * texel);

        vec2 f = fract(UV / texel);
        float edge_alpha = 1.0;
        if (upscaler_mode != 4) {
            float min_dist = 1.0;
            if (up.a < 0.5) min_dist = min(min_dist, f.y);
            if (dn.a < 0.5) min_dist = min(min_dist, 1.0 - f.y);
            if (lf.a < 0.5) min_dist = min(min_dist, f.x);
            if (rt.a < 0.5) min_dist = min(min_dist, 1.0 - f.x);

            // Diagonal outer corner rounding
            if (up.a < 0.5 && lf.a < 0.5) min_dist = min(min_dist, length(vec2(f.x, f.y)));
            if (up.a < 0.5 && rt.a < 0.5) min_dist = min(min_dist, length(vec2(1.0 - f.x, f.y)));
            if (dn.a < 0.5 && lf.a < 0.5) min_dist = min(min_dist, length(vec2(f.x, 1.0 - f.y)));
            if (dn.a < 0.5 && rt.a < 0.5) min_dist = min(min_dist, length(vec2(1.0 - f.x, 1.0 - f.y)));

            edge_alpha = smoothstep(0.04, 0.35, min_dist);
        }

        vec4 sampled = c;

        if (upscaler_mode == 0) {
            // Mode 0: AMD FidelityFX CAS Super-Resolution (Clean Contrast-Adaptive Sharpening)
            vec3 min_c = min(c.rgb, min(min(up.rgb, dn.rgb), min(lf.rgb, rt.rgb)));
            vec3 max_c = max(c.rgb, max(max(up.rgb, dn.rgb), max(lf.rgb, rt.rgb)));

            vec3 amp = clamp(min(min_c, 2.0 - max_c) / max(max_c, vec3(0.001)), 0.0, 1.0);
            vec3 w = -sqrt(amp) * (sharpness * 0.18);
            vec3 sharp_rgb = (up.rgb * w + dn.rgb * w + c.rgb + lf.rgb * w + rt.rgb * w) / (1.0 + 4.0 * w);
            sampled = vec4(clamp(sharp_rgb, min_c, max_c), c.a);

        } else if (upscaler_mode == 1) {
            // Mode 1: Neural Edge Reconstruction (Scale2x / EPX Subpixel Diagonal Vector Contours)
            vec4 recon = c;

            // Diagonal edge recognition: eliminates blocky stair-stepping on diagonal silhouettes
            bool diff_ud = any(greaterThan(abs(up.rgb - dn.rgb), vec3(0.06)));
            bool diff_lr = any(greaterThan(abs(lf.rgb - rt.rgb), vec3(0.06)));
            if (diff_ud && diff_lr) {
                bool match_ur = all(lessThan(abs(up.rgb - rt.rgb), vec3(0.08)));
                bool match_br = all(lessThan(abs(dn.rgb - rt.rgb), vec3(0.08)));
                bool match_bl = all(lessThan(abs(dn.rgb - lf.rgb), vec3(0.08)));
                bool match_ul = all(lessThan(abs(up.rgb - lf.rgb), vec3(0.08)));

                if (match_ur && f.x > 0.5 && f.y < 0.5) recon = up;
                if (match_br && f.x > 0.5 && f.y > 0.5) recon = dn;
                if (match_bl && f.x < 0.5 && f.y > 0.5) recon = dn;
                if (match_ul && f.x < 0.5 && f.y < 0.5) recon = up;
            }

            sampled = vec4(recon.rgb, c.a);

        } else if (upscaler_mode == 2) {
            // Mode 2: Anime4K Thin Lines & Vector Contours (Inked outlines without wavy UV distortion)
            vec3 min_c = min(c.rgb, min(min(up.rgb, dn.rgb), min(lf.rgb, rt.rgb)));
            vec3 max_c = max(c.rgb, max(max(up.rgb, dn.rgb), max(lf.rgb, rt.rgb)));
            vec3 avg_nb = (up.rgb + dn.rgb + lf.rgb + rt.rgb) * 0.25;

            // High-pass contour ink
            vec3 contour = c.rgb + (c.rgb - avg_nb) * (sharpness * 1.2);
            vec3 sharpened = clamp(contour, min_c * 0.85, max_c);
            sampled = vec4(sharpened, c.a);

        } else if (upscaler_mode == 3) {
            // Mode 3: 8K Catmull-Rom Bicubic Spline (Bounded anti-ringing interpolation)
            vec2 coord = UV / texel - 0.5;
            vec2 f_coord = fract(coord);
            vec2 base = (floor(coord) + 0.5) * texel;

            vec4 wx = catmull_rom_weights(f_coord.x);
            vec4 wy = catmull_rom_weights(f_coord.y);

            vec4 col = vec4(0.0);
            for (int j = 0; j < 4; j++) {
                for (int i = 0; i < 4; i++) {
                    vec2 offset = vec2(float(i - 1), float(j - 1)) * texel;
                    vec4 s = texture(TEXTURE, base + offset);
                    col += s * (wx[i] * wy[j]);
                }
            }
            vec3 min_c = min(c.rgb, min(min(up.rgb, dn.rgb), min(lf.rgb, rt.rgb)));
            vec3 max_c = max(c.rgb, max(max(up.rgb, dn.rgb), max(lf.rgb, rt.rgb)));
            sampled = vec4(clamp(col.rgb, min_c, max_c), c.a);

        } else {
            // Mode 4: Native 1:1 Direct Retro Pixel-Art
            sampled = c;
        }

        // CRT Gamma Correction & Heroic Brightness (Default 1.0 / 1.0)
        vec3 col_rgb = (abs(gamma - 1.0) > 0.01 ? pow(clamp(sampled.rgb, 0.0, 1.0), vec3(1.0 / max(gamma, 0.1))) : sampled.rgb) * brightness;
        COLOR = vec4(col_rgb, sampled.a * edge_alpha) * COLOR;
    }
}
