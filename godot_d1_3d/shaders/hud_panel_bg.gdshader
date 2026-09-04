shader_type canvas_item;
render_mode blend_mix;

// Diablo IV Gothic HUD Background Panel Shader
// Procedural weathered dark slate, forged demon iron trim, rivets, and gothic wing brackets

uniform vec4 stone_base_color : source_color = vec4(0.045, 0.042, 0.048, 0.96);
uniform vec4 stone_highlight_color : source_color = vec4(0.09, 0.085, 0.095, 1.0);
uniform vec4 iron_trim_color : source_color = vec4(0.2, 0.18, 0.16, 1.0);
uniform vec4 gold_filigree_color : source_color = vec4(0.65, 0.48, 0.22, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.85);

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
    vec2 uv = UV;
    
    // Normalized coordinates [-1, 1] horizontally, [0, 1] vertically (top to bottom)
    float nx = (uv.x - 0.5) * 2.0; // -1.0 (left) to +1.0 (right)
    float ny = uv.y;              // 0.0 (top) to 1.0 (bottom)

    // Center slab horizontal bounds (-0.75 to +0.75), with curved wings extending to [-0.95, +0.95]
    float wing_arch = smoothstep(0.1, 0.9, ny) * 0.18;
    float max_w = 0.74 + wing_arch;
    
    // Silhouette mask of the gothic panel
    float dist_x = abs(nx);
    
    vec4 result = vec4(0.0);

    if (dist_x > max_w + 0.08 || ny < 0.04 || ny > 0.98) {
        // Soft drop shadow fading outwards
        float shadow_dist = max(dist_x - max_w, max(0.04 - ny, ny - 0.98));
        float shadow_alpha = exp(-shadow_dist * 25.0) * 0.6;
        result = vec4(0.0, 0.0, 0.0, shadow_alpha);
    } else {
        // Panel border boundary
        float border_mask = smoothstep(max_w, max_w - 0.025, dist_x);
        if (border_mask <= 0.001) {
            result = vec4(0.0, 0.0, 0.0, 0.4);
        } else {
            // Weathered stone texture
            float stone_noise = noise(uv * vec2(40.0, 12.0)) * 0.5 + noise(uv * vec2(80.0, 24.0)) * 0.25;
            vec3 col = mix(stone_base_color.rgb, stone_highlight_color.rgb, stone_noise);

            // Inner panel recessed area (where buttons and slots sit)
            float inner_x = max_w - 0.035;
            bool is_iron_border = (dist_x > inner_x) || (ny < 0.12) || (ny > 0.92);

            if (is_iron_border) {
                // Forged demon iron rim with metallic highlights
                float iron_noise = noise(uv * vec2(60.0, 30.0)) * 0.3;
                col = iron_trim_color.rgb * (0.85 + iron_noise);
                
                // Top edge highlight (directional light from above)
                if (ny < 0.14) {
                    float top_rim = smoothstep(0.14, 0.06, ny);
                    col = mix(col, vec3(0.4, 0.38, 0.36), top_rim * 0.6);
                }

                // Gold filigree inner bevel line
                float filigree_dist = abs(dist_x - inner_x);
                float filigree_y = min(abs(ny - 0.12), abs(ny - 0.92));
                float filigree_line = min(filigree_dist, filigree_y);
                if (filigree_line < 0.006) {
                    float filigree_intensity = smoothstep(0.006, 0.0, filigree_line);
                    col = mix(col, gold_filigree_color.rgb * 1.2, filigree_intensity * 0.85);
                }

                // Iron Rivets along the top and bottom borders
                float rivet_step_x = 0.08;
                float rx = mod(dist_x + 0.04, rivet_step_x) - (rivet_step_x * 0.5);
                if (dist_x < max_w - 0.04) {
                    float r_top = length(vec2(rx * 2.0, (ny - 0.085) * 4.0));
                    float r_bot = length(vec2(rx * 2.0, (ny - 0.955) * 4.0));
                    float r_min = min(r_top, r_bot);
                    if (r_min < 0.045) {
                        float r_norm = sqrt(max(0.0, 1.0 - (r_min / 0.045)));
                        vec3 rivet_col = mix(iron_trim_color.rgb * 0.5, gold_filigree_color.rgb, 0.4);
                        rivet_col += vec3(r_norm * 0.35); // specular
                        col = rivet_col;
                    }
                }
            } else {
                // Recessed slate backing for action slots
                float seam_x = mod(uv.x * 14.0, 1.0);
                float seam_line = smoothstep(0.03, 0.0, seam_x) * smoothstep(0.97, 1.0, seam_x);
                col *= (1.0 - seam_line * 0.25);

                float inner_shadow = smoothstep(0.12, 0.26, ny);
                col *= mix(0.55, 1.0, inner_shadow);
            }

            // Outer edge darkening (vignette)
            float edge_fade = smoothstep(max_w, max_w - 0.02, dist_x);
            float alpha = stone_base_color.a * edge_fade;

            // Bottom grounding shadow
            if (ny > 0.90) {
                col *= mix(1.0, 0.4, (ny - 0.90) * 10.0);
            }

            result = vec4(col, alpha);
        }
    }

    COLOR = result;
}
