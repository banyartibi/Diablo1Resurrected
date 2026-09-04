shader_type canvas_item;
render_mode blend_mix;

uniform vec4 border_color : source_color = vec4(0.45, 0.40, 0.30, 1.0);
uniform vec4 glow_color : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 bg_color : source_color = vec4(0.06, 0.05, 0.07, 0.95);
uniform float border_thickness : hint_range(0.01, 0.2) = 0.05;
uniform float corner_cut : hint_range(0.0, 0.2) = 0.08;
uniform bool is_circular = false;
uniform bool is_active = false;

void fragment() {
    float max_dist = 0.0;
    if (is_circular) {
        max_dist = length((UV - 0.5) * 2.0);
    } else {
        vec2 p = abs(UV - 0.5) * 2.0; // [0, 1] from center
        float chamfer = max(p.x, p.y);
        float corner_dist = (p.x + p.y) * 0.7071;
        max_dist = max(chamfer, corner_dist * (1.0 + corner_cut));
    }

    if (max_dist > 1.0) {
        discard;
    }

    // Border vs interior
    float inner_edge = 1.0 - border_thickness;
    float is_border = smoothstep(inner_edge, inner_edge + 0.02, max_dist);

    // Inner bevel gradient
    float inner_bevel = clamp((1.0 - max_dist) / (1.0 - inner_edge), 0.0, 1.0);

    vec3 col = mix(bg_color.rgb * (0.8 + 0.2 * inner_bevel), border_color.rgb, is_border);

    // Active glow around border
    if (is_active && glow_color.a > 0.01) {
        float glow_ring = smoothstep(inner_edge - 0.08, 1.0, max_dist);
        col += glow_color.rgb * glow_ring * 1.5;
    }

    // Top-left metallic highlight
    float highlight = max(0.0, (0.5 - UV.x) + (0.5 - UV.y)) * is_border * 0.35;
    col += vec3(highlight);

    COLOR = vec4(col, bg_color.a);
}
