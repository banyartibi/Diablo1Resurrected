shader_type canvas_item;
render_mode blend_mix;

uniform vec4 metal_color_base : source_color = vec4(0.12, 0.11, 0.12, 1.0);     // Dark Gothic Iron
uniform vec4 metal_color_trim : source_color = vec4(0.65, 0.52, 0.28, 1.0);     // Ancient Corroded Brass/Gold
uniform vec4 metal_color_highlight : source_color = vec4(0.95, 0.85, 0.60, 1.0);// Bright Rim Specular
uniform float is_mana_side : hint_range(0.0, 1.0) = 0.0;                        // 0 for Life (left/demon), 1 for Mana (right/angel)

float hash21(vec2 p) {
    p = fract(p * vec2(234.34, 435.345));
    p += dot(p, p + 34.23);
    return fract(p.x * p.y);
}

void fragment() {
    vec2 p = UV * 2.0 - 1.0;
    float dist = length(p);
    float angle = atan(p.y, p.x);

    // Ring dimensions
    float inner_r = 0.82;
    float outer_r = 1.04;

    // Side claw/bracket bulge around horizontal / lower quadrant
    float side_angle = is_mana_side > 0.5 ? 0.0 : 3.14159;
    float angle_diff = abs(angle - side_angle);
    if (angle_diff > 3.14159) angle_diff = 6.28318 - angle_diff;
    
    // Add gothic claw ornaments
    float claw = exp(-angle_diff * 4.0) * 0.14 * smoothstep(0.7, 1.0, dist);
    float bottom_bracket = exp(-abs(angle - 1.5708) * 5.0) * 0.10 * smoothstep(0.7, 1.0, dist);

    float effective_outer = outer_r + claw + bottom_bracket;

    if (dist < inner_r || dist > effective_outer) {
        discard;
    }

    // Carved metallic facets
    float facet = sin(angle * 32.0) * 0.15;
    float ring_pos = (dist - inner_r) / (effective_outer - inner_r); // 0.0 inside, 1.0 outside

    // Metallic normal shading
    float rim_inner = smoothstep(0.0, 0.12, ring_pos) * smoothstep(0.25, 0.12, ring_pos);
    float rim_outer = smoothstep(0.85, 1.0, ring_pos);
    float rim_mid = sin(ring_pos * 3.14159);

    // Bevel shading
    float light_angle = -0.785; // Top-left directional light
    float light_dot = cos(angle - light_angle);
    float shadow = clamp(light_dot * 0.5 + 0.5, 0.2, 1.0);

    vec3 metal = mix(metal_color_base.rgb, metal_color_trim.rgb, rim_inner + rim_outer * 0.6);
    metal = mix(metal, metal_color_highlight.rgb, (rim_inner * 0.8 + rim_outer) * max(0.0, light_dot));
    metal *= shadow;

    // Runic notches at 8 cardinal & ordinal points
    float rune_tick = smoothstep(0.96, 1.0, cos(angle * 8.0)) * rim_mid;
    metal = mix(metal, metal_color_highlight.rgb * 1.4, rune_tick * 0.7);

    // Soft antialiasing at ring boundaries
    float aa_inner = smoothstep(inner_r, inner_r + 0.02, dist);
    float aa_outer = 1.0 - smoothstep(effective_outer - 0.02, effective_outer, dist);
    float alpha = aa_inner * aa_outer;

    COLOR = vec4(metal, alpha);
}
