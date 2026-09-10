shader_type canvas_item;

// Godot-native global brightness applied to the composited GameView render target.
// 1.0 = neutral (no change). The Options "Brightness" slider drives this uniform
// over 50%..150% (i.e. 0.5..1.5). This is a Godot-native effect and does NOT touch
// the C++/palette-based gamma pipeline.
uniform float brightness : hint_range(0.5, 1.5) = 1.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(tex.rgb * brightness, tex.a);
}