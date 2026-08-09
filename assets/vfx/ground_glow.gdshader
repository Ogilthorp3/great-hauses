// DRACARYS VFX KIT — GROUND GLOW (the no-Light3D firelight cheat)
// A flat additive radial pool laid on the floor under the impact. The hall's
// 8-omni budget is FULL, so the "light" the fire casts on the stone is this
// quad, not an OmniLight3D. Reads convincingly on dark low-poly stone.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled,
	shadows_disabled, fog_disabled, specular_disabled;

uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform vec3 glow_color : source_color = vec3(1.0, 0.44, 0.11);
uniform vec3 hot_color : source_color = vec3(1.0, 0.86, 0.62);
uniform float energy = 2.4;
uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform float falloff : hint_range(0.5, 6.0) = 2.4;
uniform float hot_core : hint_range(0.0, 1.0) = 0.28;
uniform float flicker : hint_range(0.0, 1.0) = 0.30;
uniform float flicker_speed = 0.9;

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float fall = pow(clamp(1.0 - d, 0.0, 1.0), falloff);
	if (fall <= 0.001 || amount <= 0.001) {
		discard;
	}
	float n = texture(noise_tex,
		UV * 1.7 + vec2(TIME * flicker_speed * 0.31, TIME * flicker_speed * 0.19)).r;
	float f = (1.0 - flicker) + flicker * (n * 2.0);
	vec3 col = mix(glow_color, hot_color, smoothstep(1.0 - hot_core, 1.0, 1.0 - d));
	ALBEDO = col * energy * fall * f * amount;
	ALPHA = clamp(fall * amount * 1.2, 0.0, 1.0);
}
