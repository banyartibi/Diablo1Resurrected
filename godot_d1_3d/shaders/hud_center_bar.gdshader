shader_type canvas_item;

// Ensures the carved stone trim has a 100% transparent top border with zero dark background artifacts
uniform float top_fade_start : hint_range(0.0, 0.2) = 0.04;
uniform float top_fade_end : hint_range(0.0, 0.25) = 0.12;
uniform float dark_threshold : hint_range(0.0, 0.5) = 0.25;

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	if (UV.y < top_fade_end) {
		float max_val = max(col.r, max(col.g, col.b));
		if (max_val < dark_threshold) {
			col.a = 0.0;
		} else {
			float fade = smoothstep(top_fade_start, top_fade_end, UV.y);
			col.a *= fade;
		}
	}
	COLOR = col;
}
