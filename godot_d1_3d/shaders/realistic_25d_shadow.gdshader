shader_type canvas_item;
render_mode blend_mix;

// Realistic 2.5D Directional Projection Shadow
// Skews the animated character/monster sprite onto the isometric floor plane
// with 9-tap Gaussian penumbra filtering and contact darkening near the feet.

uniform vec2 shadow_skew = vec2(0.28, 0.42);
uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.52);
uniform float shadow_blur : hint_range(0.0, 6.0) = 2.0;
uniform float contact_fade : hint_range(0.0, 1.0) = 0.35;

void vertex() {
	// For sprites anchored at feet (offset.y = -sh * 0.5), VERTEX.y ranges from -sh (head) to 0 (feet).
	float h = max(0.0, -VERTEX.y);
	// Skew horizontal position away from light
	VERTEX.x += h * shadow_skew.x;
	// Flatten height onto the floor plane along the projection vector
	VERTEX.y = h * shadow_skew.y;
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE * shadow_blur;

	// 9-tap separable Gaussian-like blur for smooth organic penumbra
	float a = texture(TEXTURE, UV).a * 0.25;
	a += texture(TEXTURE, clamp(UV + vec2(px.x, 0.0), vec2(0.0), vec2(1.0))).a * 0.14;
	a += texture(TEXTURE, clamp(UV - vec2(px.x, 0.0), vec2(0.0), vec2(1.0))).a * 0.14;
	a += texture(TEXTURE, clamp(UV + vec2(0.0, px.y), vec2(0.0), vec2(1.0))).a * 0.14;
	a += texture(TEXTURE, clamp(UV - vec2(0.0, px.y), vec2(0.0), vec2(1.0))).a * 0.14;
	a += texture(TEXTURE, clamp(UV + vec2(px.x, px.y) * 0.707, vec2(0.0), vec2(1.0))).a * 0.0825;
	a += texture(TEXTURE, clamp(UV - vec2(px.x, px.y) * 0.707, vec2(0.0), vec2(1.0))).a * 0.0825;
	a += texture(TEXTURE, clamp(UV + vec2(-px.x, px.y) * 0.707, vec2(0.0), vec2(1.0))).a * 0.0825;
	a += texture(TEXTURE, clamp(UV + vec2(px.x, -px.y) * 0.707, vec2(0.0), vec2(1.0))).a * 0.0825;

	// Edge fade if UV is near boundary
	float edge_mask = smoothstep(0.0, 0.02, UV.x) * smoothstep(1.0, 0.98, UV.x) *
	                  smoothstep(0.0, 0.02, UV.y) * smoothstep(1.0, 0.98, UV.y);
	a *= edge_mask;

	if (a <= 0.01) {
		discard;
	}

	// Contact darkening: near feet (UV.y close to 1.0) the shadow is denser.
	// Near head (UV.y close to 0.0) the penumbra is softer and more diffused.
	float foot_factor = clamp(UV.y, 0.0, 1.0);
	float density = mix(1.0 - contact_fade, 1.0 + contact_fade * 0.5, foot_factor * foot_factor);

	float final_alpha = clamp(a * shadow_color.a * density, 0.0, 0.85);
	COLOR = vec4(shadow_color.rgb, final_alpha);
}
