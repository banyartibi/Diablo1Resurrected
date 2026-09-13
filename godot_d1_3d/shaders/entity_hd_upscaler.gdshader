shader_type canvas_item;
render_mode unshaded;

// Diablo 1 Resurrected - Entity (Hero & Monster) HD Subpixel CAS Shader
// Clean Contrast Adaptive Sharpening + Subpixel Alpha Reconstruction
// Zero UV warping, zero luminance distortion

uniform bool hd_enabled = true;
uniform float sharpness : hint_range(0.0, 1.0) = 0.35;
uniform float gamma : hint_range(0.5, 2.5) = 1.55;
uniform float brightness : hint_range(0.5, 3.0) = 1.45;

void fragment() {
    vec2 tex_size = vec2(textureSize(TEXTURE, 0));
    vec2 texel = vec2(1.0) / tex_size;

    vec4 c = texture(TEXTURE, UV);
    if (!hd_enabled || tex_size.x <= 1.0 || tex_size.y <= 1.0) {
        vec3 gamma_c = pow(clamp(c.rgb, 0.0, 1.0), vec3(1.0 / max(gamma, 0.1))) * brightness;
        COLOR = vec4(gamma_c, c.a) * COLOR;
    } else if (c.a < 0.005) {
        COLOR = vec4(0.0);
    } else {
        // AMD FidelityFX CAS (Clean gentle sharpening without UV warping)
        vec4 a = texture(TEXTURE, UV + vec2( 0.0, -1.0) * texel);
        vec4 b = texture(TEXTURE, UV + vec2(-1.0,  0.0) * texel);
        vec4 d = texture(TEXTURE, UV + vec2( 1.0,  0.0) * texel);
        vec4 e = texture(TEXTURE, UV + vec2( 0.0,  1.0) * texel);

        vec3 min_c = min(c.rgb, min(min(a.rgb, b.rgb), min(d.rgb, e.rgb)));
        vec3 max_c = max(c.rgb, max(max(a.rgb, b.rgb), max(d.rgb, e.rgb)));

        vec3 amp = clamp(min(min_c, 2.0 - max_c) / max(max_c, vec3(0.001)), 0.0, 1.0);
        vec3 w = -sqrt(amp) * (sharpness * 0.16);
        vec3 sharp_rgb = (a.rgb * w + b.rgb * w + c.rgb + d.rgb * w + e.rgb * w) / (1.0 + 4.0 * w);

        // Subpixel alpha reconstruction for smooth sprite outline
        float avg_a = (a.a + b.a + d.a + e.a) * 0.25;
        float smooth_a = (c.a >= 0.85) ? c.a : mix(c.a, avg_a, 0.20);

        // Authentic Diablo 1 CRT Gamma Correction & Heroic Brightness Highlight
        vec3 gamma_rgb = pow(clamp(sharp_rgb, 0.0, 1.0), vec3(1.0 / max(gamma, 0.1))) * brightness;

        COLOR = vec4(gamma_rgb, smooth_a) * COLOR;
    }
}
