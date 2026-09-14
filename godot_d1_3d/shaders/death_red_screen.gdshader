shader_type canvas_item;

// Authentic Diablo 1 / Hellfire Red Death Screen Post-Process
// Replicates the iconic pause.trn palette translation (monochromatic blood crimson)
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float intensity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 col = texture(screen_texture, SCREEN_UV);
	float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));

	// Diablo 1 death palette ramp:
	// Low lum: deep dark crimson / near black
	// Mid lum: intense blood red
	// High lum: bright scarlet / orange-red
	vec3 red_tint;
	if (lum < 0.35) {
		red_tint = mix(vec3(0.02, 0.0, 0.0), vec3(0.65, 0.06, 0.02), lum / 0.35);
	} else if (lum < 0.75) {
		red_tint = mix(vec3(0.65, 0.06, 0.02), vec3(0.95, 0.20, 0.06), (lum - 0.35) / 0.40);
	} else {
		red_tint = mix(vec3(0.95, 0.20, 0.06), vec3(1.0, 0.50, 0.18), (lum - 0.75) / 0.25);
	}

	// Preserve strong original red highlights (e.g. blood splatters and torches)
	red_tint = max(red_tint, vec3(col.r * 1.15, col.r * 0.18, col.r * 0.06));

	COLOR = vec4(mix(col.rgb, red_tint, intensity), col.a);
}
