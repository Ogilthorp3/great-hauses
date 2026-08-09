// DRACARYS VFX KIT — IGNITION SHOCK RING
// A thin expanding annulus fired once at the muzzle on ignition (and once at
// the ground on impact). Costs one quad and is most of why the ignition frame
// reads as violence rather than as a lamp turning on.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled,
	shadows_disabled, fog_disabled, specular_disabled;

uniform vec3 ring_color : source_color = vec3(1.0, 0.72, 0.36);
uniform float energy = 5.0;
uniform float amount : hint_range(0.0, 1.0) = 1.0;
// 0 -> thin ring at the centre, 1 -> thin ring at the rim.
uniform float radius : hint_range(0.0, 1.0) = 0.5;
uniform float thickness : hint_range(0.01, 0.6) = 0.16;
uniform float inner_glow : hint_range(0.0, 1.0) = 0.25;

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float band = 1.0 - smoothstep(0.0, thickness, abs(d - radius));
	band = pow(band, 1.6);
	// Faint hot wash inside the ring so the centre is not a hole.
	float wash = inner_glow * pow(clamp(1.0 - d / max(radius, 0.001), 0.0, 1.0), 2.0);
	float a = clamp((band + wash) * amount, 0.0, 1.0);
	if (a <= 0.002) {
		discard;
	}
	ALBEDO = ring_color * energy * (band + wash * 0.6) * amount;
	ALPHA = a;
}
