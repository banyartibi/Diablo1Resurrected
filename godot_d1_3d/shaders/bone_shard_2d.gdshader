// 2D Canvas Item version of bone_shard.gdshader (Mode 1 Native Godot 2.5D VFX)
// Aged ivory / ancient bone shard shape
shader_type canvas_item;

void fragment() {
	vec2 uv = abs(UV - vec2(0.5));
	float d = uv.x * 2.5 + uv.y * 1.2;
	if (d > 0.48) {
		discard;
	}
	float edge = smoothstep(0.48, 0.38, d);

	vec3 bone_base = vec3(0.88, 0.85, 0.74);
	vec3 bone_shade = vec3(0.65, 0.60, 0.50);
	vec3 col = mix(bone_base, bone_shade, (UV.x + UV.y) * 0.5);

	COLOR = vec4(col, COLOR.a * edge);
}
