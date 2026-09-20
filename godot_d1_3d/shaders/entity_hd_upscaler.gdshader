shader_type canvas_item;
render_mode unshaded;

// Diablo 1 Resurrected - Entity (Hero & Monster) HD Subpixel Upscaler Shader
// Supports AMD CAS, Anime4K Edge Push, Anime4K Thin Lines, 8K Catmull-Rom & Native 1:1

uniform bool hd_enabled = true;
uniform int upscaler_mode : hint_range(0, 4) = 3; // 0: AMD CAS, 1: Anime4K Edge, 2: Anime4K Thin, 3: 8K Catmull-Rom, 4: Native
uniform float sharpness : hint_range(0.0, 1.0) = 0.35;
uniform float gamma : hint_range(0.5, 2.5) = 1.55;
uniform float brightness : hint_range(0.5, 3.0) = 1.45;

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
    if (!hd_enabled || upscaler_mode == 4 || tex_size.x <= 1.0 || tex_size.y <= 1.0) {
        vec3 gamma_c = pow(clamp(c.rgb, 0.0, 1.0), vec3(1.0 / max(gamma, 0.1))) * brightness;
        COLOR = vec4(gamma_c, c.a) * COLOR;
    } else if (c.a < 0.005) {
        COLOR = vec4(0.0);
    } else {
        vec4 sampled;
        if (upscaler_mode == 0) {
            // AMD FidelityFX CAS
            vec4 a = texture(TEXTURE, UV + vec2( 0.0, -1.0) * texel);
            vec4 b = texture(TEXTURE, UV + vec2(-1.0,  0.0) * texel);
            vec4 d = texture(TEXTURE, UV + vec2( 1.0,  0.0) * texel);
            vec4 e = texture(TEXTURE, UV + vec2( 0.0,  1.0) * texel);

            vec3 min_c = min(c.rgb, min(min(a.rgb, b.rgb), min(d.rgb, e.rgb)));
            vec3 max_c = max(c.rgb, max(max(a.rgb, b.rgb), max(d.rgb, e.rgb)));

            vec3 amp = clamp(min(min_c, 2.0 - max_c) / max(max_c, vec3(0.001)), 0.0, 1.0);
            vec3 w = -sqrt(amp) * (sharpness * 0.16);
            vec3 sharp_rgb = (a.rgb * w + b.rgb * w + c.rgb + d.rgb * w + e.rgb * w) / (1.0 + 4.0 * w);

            float avg_a = (a.a + b.a + d.a + e.a) * 0.25;
            float smooth_a = (c.a >= 0.85) ? c.a : mix(c.a, avg_a, 0.20);
            sampled = vec4(clamp(sharp_rgb, 0.0, 1.0), smooth_a);
        } else if (upscaler_mode == 1 || upscaler_mode == 2) {
            // Neural Edge Push (used for modes 1 and 2)
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
            float edge = length(vec2(gx, gy));

            vec4 pushed = c;
            if (edge > 0.035) {
                vec2 dir = normalize(vec2(gx, gy));
                vec2 pushed_uv = UV - dir * (texel * 0.45 * clamp(edge * 2.5, 0.0, 1.0));
                pushed = mix(c, texture(TEXTURE, pushed_uv), clamp(edge * 2.8, 0.0, 1.0));
            }

            if (upscaler_mode == 2) {
                // Anime4K Thin Lines
                vec4 up = texture(TEXTURE, UV + vec2( 0.0, -1.0) * texel);
                vec4 dn = texture(TEXTURE, UV + vec2( 0.0,  1.0) * texel);
                vec4 lf = texture(TEXTURE, UV + vec2(-1.0,  0.0) * texel);
                vec4 rt = texture(TEXTURE, UV + vec2( 1.0,  0.0) * texel);

                vec3 min_c = min(pushed.rgb, min(min(up.rgb, dn.rgb), min(lf.rgb, rt.rgb)));
                vec3 max_c = max(pushed.rgb, max(max(up.rgb, dn.rgb), max(lf.rgb, rt.rgb)));
                vec3 sharpened = pushed.rgb + (pushed.rgb - (up.rgb + dn.rgb + lf.rgb + rt.rgb) * 0.25) * 0.65;
                sampled = vec4(clamp(sharpened, min_c, max_c), pushed.a);
            } else {
                sampled = pushed;
            }
        } else {
            // 8K Catmull-Rom Bicubic Spline (Default)
            vec2 coord = UV / texel - 0.5;
            vec2 f = fract(coord);
            vec2 base = (floor(coord) + 0.5) * texel;

            vec4 wx = catmull_rom_weights(f.x);
            vec4 wy = catmull_rom_weights(f.y);

            vec4 col = vec4(0.0);
            for (int j = 0; j < 4; j++) {
                for (int i = 0; i < 4; i++) {
                    vec2 offset = vec2(float(i - 1), float(j - 1)) * texel;
                    vec4 s = texture(TEXTURE, base + offset);
                    col += s * (wx[i] * wy[j]);
                }
            }
            sampled = clamp(col, 0.0, 1.0);
        }

        // CRT Gamma Correction & Heroic Brightness Highlight
        vec3 gamma_rgb = pow(clamp(sampled.rgb, 0.0, 1.0), vec3(1.0 / max(gamma, 0.1))) * brightness;
        COLOR = vec4(gamma_rgb, sampled.a) * COLOR;
    }
}
