// DRACARYS VFX KIT — CORE JET STEM
// The solid pressure core the particles ride on. Particles alone read as a
// puff; a tapered, view-dense, fast-scrolling stem reads as something being
// FORCED out under pressure.
//
// Geometry contract: a CylinderMesh (axis = local +Y) with
//   bottom_radius = narrow (the muzzle), top_radius = wide (the far end),
// rotated -90 deg about X by the kit so +Y maps to the muzzle's forward (-Z).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled,
	shadows_disabled, fog_disabled, specular_disabled;

uniform sampler2D noise_tex : filter_linear, repeat_enable;

uniform vec3 core_color : source_color = vec3(1.0, 0.96, 0.86);
uniform vec3 mid_color : source_color = vec3(1.0, 0.52, 0.12);
uniform vec3 tail_color : source_color = vec3(0.85, 0.13, 0.02);

uniform float energy = 7.0;           // HDR multiplier -> bloom
uniform float amount : hint_range(0.0, 1.0) = 1.0;   // master fade / retract
uniform float stem_height = 6.0;      // must match CylinderMesh.height
uniform float flow_speed = 4.2;       // texture metres/second down the barrel
uniform float noise_tiling = 2.6;
uniform float density_power = 1.7;    // view-facing falloff (volumetric feel)
uniform float tip_bite : hint_range(0.5, 6.0) = 2.1;  // how fast it dies at the tip
uniform float throat : hint_range(0.0, 0.5) = 0.06;   // hard bright collar at the mouth
uniform float flicker = 0.14;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	// 0 at the muzzle, 1 at the far end.
	float t = clamp(v_local.y / max(stem_height, 0.001) + 0.5, 0.0, 1.0);

	// View-facing density: bright through the middle of the barrel, thin at
	// the silhouette. Without this a cylinder reads as a cylinder.
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float density = pow(clamp(facing, 0.0, 1.0), density_power);

	// Fast axial flow — the single strongest "under pressure" cue.
	vec2 fuv = vec2(UV.x * noise_tiling, t * noise_tiling * 1.6 - TIME * flow_speed);
	float n = texture(noise_tex, fuv).r;
	float n2 = texture(noise_tex, fuv * vec2(2.3, 1.9) + vec2(0.37, -TIME * flow_speed * 0.55)).r;
	float turb = mix(n, n2, 0.45);

	// Pressure taper: full-bore at the throat, eaten away toward the tip.
	float along = pow(1.0 - t, tip_bite);
	// A hard, over-bright collar right at the lips.
	float collar = smoothstep(throat, 0.0, t);

	float dens = clamp(along * (0.55 + 0.75 * turb) + collar * 1.4, 0.0, 3.0);
	dens *= density * amount;

	// White-hot -> orange -> deep red along the barrel.
	vec3 col = mix(core_color, mid_color, smoothstep(0.02, 0.42, t));
	col = mix(col, tail_color, smoothstep(0.40, 0.95, t));
	col += core_color * collar * 0.9;

	float pulse = 1.0 - flicker + flicker * (0.5 + 0.5 * sin(TIME * 47.0 + t * 9.0));

	ALBEDO = col * energy * dens * pulse;
	ALPHA = clamp(dens, 0.0, 1.0);
}
