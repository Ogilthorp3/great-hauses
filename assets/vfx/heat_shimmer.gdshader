// DRACARYS VFX KIT — HEAT SHIMMER
// Screen-space refraction on a camera-facing quad. This is the layer that
// actually sells "this air is 900 degrees"; colour alone never does.
//
// Mobile-renderer safe: `hint_screen_texture` with filter_linear ONLY —
// the Forward Mobile back-buffer copy has no mipmaps, so filter_linear_mipmap
// would sample level 0 anyway on some drivers and blur nothing on others.
//
// depth_test_default (NOT disabled) so the shimmer is correctly occluded by
// geometry standing in front of the flame.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled,
	shadows_disabled, fog_disabled, specular_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D noise_tex : filter_linear, repeat_enable;

// Master fade. 0.0 == completely inert (the kit drives this to 0 on stop,
// which is why a stuck shimmer can never survive hard_stop()).
uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform float strength : hint_range(0.0, 0.25) = 0.045;
uniform float rise_speed = 1.45;
uniform float swirl_speed = 0.5;
uniform float tiling = 2.1;
uniform float edge_softness : hint_range(0.02, 1.0) = 0.62;
// Squash of the elliptical mask: >1 makes the hot column taller than wide.
uniform float mask_aspect = 1.25;
// Extra convection lift near the top of the quad (hot air goes up).
uniform float lift : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	vec2 c = UV - vec2(0.5);
	float d = length(c * vec2(1.0, mask_aspect)) * 2.0;
	float mask = smoothstep(1.0, 1.0 - edge_softness, d) * amount;
	if (mask <= 0.002) {
		discard;
	}

	// Two octaves scrolling upward at different rates = boiling air, not a
	// sliding texture.
	vec2 n1 = texture(noise_tex,
		UV * tiling + vec2(TIME * swirl_speed, -TIME * rise_speed)).rg;
	vec2 n2 = texture(noise_tex,
		UV * (tiling * 2.4) + vec2(-TIME * swirl_speed * 0.63,
			-TIME * rise_speed * 1.9)).rg;
	vec2 turb = (n1 - vec2(0.5)) * 0.68 + (n2 - vec2(0.5)) * 0.32;

	// Convection bias: the distortion drags upward as it rises.
	turb.y -= lift * (1.0 - UV.y) * 0.5;

	vec2 off = turb * strength * mask;
	vec2 suv = clamp(SCREEN_UV + off, vec2(0.0015), vec2(0.9985));
	ALBEDO = texture(screen_tex, suv).rgb;
	ALPHA = mask;
}
