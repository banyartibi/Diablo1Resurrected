shader_type canvas_item;

// Godot-native global brightness & color profile grading applied to the composited GameView render target.
// 1.0 = neutral (no change). The Options "Brightness" slider drives this uniform
// over 50%..150% (i.e. 0.5..1.5). This is a Godot-native effect and does NOT touch
// the C++/palette-based gamma pipeline.
uniform float brightness : hint_range(0.5, 1.5) = 1.2;
uniform int color_profile : hint_range(0, 4) = 0; // 0: Vanilla, 1: Dark Gothic, 2: Hellish Crimson, 3: Crypt Cyan, 4: Noir

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
        // Crypt Cyan - Chilling, eerie spectral cold dungeon ambiance
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
	vec4 tex = texture(TEXTURE, UV);
	vec3 col = tex.rgb * brightness;
	if (color_profile > 0) {
		col = apply_color_grading(col, color_profile);
	}
	COLOR = vec4(col, tex.a);
}