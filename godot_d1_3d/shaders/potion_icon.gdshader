shader_type canvas_item;
render_mode blend_mix;

uniform int potion_type : hint_range(0, 7) = 1;

void fragment() {
    if (potion_type == 0) {
        discard;
    }

    vec2 p = UV * 2.0 - 1.0; // [-1, 1]
    
    // Flask geometry: neck at top (y: -0.85 to -0.45), round bulb at bottom (y: -0.45 to 0.75)
    float bulb_dist = length(p - vec2(0.0, 0.15));
    bool in_bulb = bulb_dist < 0.65;
    bool in_neck = abs(p.x) < 0.22 && p.y >= -0.80 && p.y <= -0.40;
    bool in_cork = abs(p.x) < 0.24 && p.y >= -0.92 && p.y < -0.80;
    bool in_lip = abs(p.x) < 0.28 && abs(p.y - (-0.78)) < 0.05;

    if (!in_bulb && !in_neck && !in_cork && !in_lip) {
        discard;
    }

    // Determine colors
    vec3 liquid_col = vec3(0.9, 0.1, 0.1); // default heal
    vec3 glow_col = vec3(1.2, 0.2, 0.2);
    bool is_full = false;

    if (potion_type == 1) {
        liquid_col = vec3(0.92, 0.08, 0.12);
        glow_col = vec3(1.4, 0.2, 0.2);
    } else if (potion_type == 2) {
        liquid_col = vec3(1.0, 0.05, 0.15);
        glow_col = vec3(1.8, 0.3, 0.3);
        is_full = true;
    } else if (potion_type == 3) {
        liquid_col = vec3(0.08, 0.45, 0.95);
        glow_col = vec3(0.2, 0.6, 1.6);
    } else if (potion_type == 4) {
        liquid_col = vec3(0.12, 0.55, 1.0);
        glow_col = vec3(0.3, 0.8, 1.8);
        is_full = true;
    } else if (potion_type == 5) {
        liquid_col = vec3(0.72, 0.12, 0.85);
        glow_col = vec3(1.2, 0.3, 1.5);
    } else if (potion_type == 6) {
        liquid_col = vec3(0.85, 0.18, 0.98);
        glow_col = vec3(1.6, 0.4, 1.8);
        is_full = true;
    } else if (potion_type == 7) {
        liquid_col = vec3(0.95, 0.75, 0.12);
        glow_col = vec3(1.5, 1.2, 0.3);
    }

    vec3 col;
    float alpha = 1.0;

    if (in_cork) {
        // Wooden cork or golden cap
        if (is_full) {
            col = vec3(0.95, 0.82, 0.35) * (0.8 + 0.3 * (1.0 - abs(p.x) * 3.0));
        } else {
            col = vec3(0.55, 0.38, 0.22) * (0.8 + 0.3 * (1.0 - abs(p.x) * 3.0));
        }
    } else if (in_lip) {
        col = is_full ? vec3(0.9, 0.78, 0.3) : vec3(0.4, 0.45, 0.5);
    } else {
        // Liquid vs empty neck
        float liquid_level = is_full ? -0.45 : -0.20;
        if (p.y > liquid_level) {
            // Inside liquid
            float center_glow = 1.0 - bulb_dist * 1.2;
            col = mix(liquid_col, glow_col, max(0.0, center_glow * 0.7));
            // Meniscus line
            if (abs(p.y - liquid_level) < 0.04) {
                col += vec3(0.4);
            }
        } else {
            // Empty glass neck
            col = vec3(0.12, 0.14, 0.18);
            alpha = 0.5;
        }

        // Glass highlight arc
        float spec = smoothstep(0.55, 0.45, length(p - vec2(-0.25, -0.05))) * 0.65;
        col += vec3(spec);

        // Glass rim
        if (bulb_dist > 0.58 && in_bulb) {
            col = mix(col, vec3(0.6, 0.7, 0.8), 0.5);
        }
    }

    COLOR = vec4(col, alpha);
}
