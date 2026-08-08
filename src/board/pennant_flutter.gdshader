shader_type spatial;
render_mode cull_disabled;
// Pennant flutter — cheap time-based sine displacement, no physics.
// The pennant mesh (assets/custom-props/watchtower.glb, "Pennant") is
// authored with its root at local x=0 streaming toward +X, so VERTEX.x
// doubles as the flutter mask: pinned at the pole, free at the tip.

uniform vec3 cloth_color : source_color = vec3(0.75, 0.25, 0.2);
uniform float pennant_length = 0.34;   // local-space length (see make_watchtower.py)
uniform float flutter_strength = 0.05;
uniform float flutter_speed = 5.0;

void vertex() {
	float m = clamp(VERTEX.x / pennant_length, 0.0, 1.0);
	float phase = TIME * flutter_speed + VERTEX.x * 9.0;
	VERTEX.z += sin(phase) * flutter_strength * m * m;
	VERTEX.y += cos(phase * 0.7 + 1.3) * flutter_strength * 0.45 * m * m;
}

void fragment() {
	ALBEDO = cloth_color;
	ROUGHNESS = 0.92;
	SPECULAR = 0.15;
}
