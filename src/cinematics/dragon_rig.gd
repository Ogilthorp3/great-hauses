class_name DragonRig
extends Node3D
## Shared controller for the championship dragon GLB — the single owner of
## the loader that used to live inline in GreatHall.summon_champion_dragon
## (refactored out 2026-08-08 so the spectator/ashfall module and the
## championship staging drive ONE rig instead of duplicating it).
##
## Owns: instancing assets/custom-props/dragon.glb, the no-new-lights
## emissive lift (the hall's 8-omni budget is FULL — glow comes from
## emission, never from Light3D), AnimationPlayer discovery, loop/one-shot
## clip helpers, and the head-bone mouth mount used by the ashfall flame.
##
## THE SERPENT-WYRM (dragon-v2, installed 2026-08-09) replaced the Quaternius
## chibi. Clips as they arrive GODOT-SIDE (probed, not assumed — Godot's
## importer strips a trailing _Cycle/_Loop, which is why the GLB's
## `Flap_Cycle` lands as `Flap`):
##   Perch_Idle · Flying_Idle(=Hover) · Fast_Flying(=Flap) · Glide ·
##   Rear_Breathe(=Headbutt) · Land_Settle · Roar · HitReact · Yes · No
## The three aliases are byte-identical duplicates the asset ships on
## purpose so every incumbent call site kept working. `Death` and `Punch`
## are NOT authored; play_once/play_loop no-op on a missing clip.
##
## Rig: 42 bones — Root/Torso/Chest/Neck..Neck6/Head(+_end)/Jaw, 7-bone
## wings, 8-bone tail, real legs. Native forward is +Z (rotate PI to face
## -Z).
##
## THE ORIGIN MOVED — the one breaking change. The old rig hung its mesh
## around a MID-AIR root, so callers placed the root LOW and added a fudge.
## This `Root` sits ON THE GROUND between the feet; the torso mass centre is
## measured at BODY_RISE (0.95) × rig scale above it. Anywhere a dragon
## height was hardcoded against the old rig, the author's rule applies:
##     new_root_y = old_root_y + 1.15 × rig_scale
## (2.10 − 0.95 = 1.15). Applied 2026-08-09 to DragonSpectator's perch /
## hover / bank / throne constants and GreatHall.DRAGON_HOVER +
## spectator_perch().

const DRAGON_SCENE: PackedScene = preload("res://assets/custom-props/dragon.glb")

## THE HALL PALETTE — an open defect the asset's author flagged and this
## module owns (2026-08-09).
##
## The GLB ships a deliberately dark hide (albedo 0.118 linear / 0.378 sRGB,
## pushed cool) tuned against a FOUR-OMNI stand-in. Dropped into THIS hall —
## 8 warm torches, two cool fill directionals, a filmic tonemap at exposure
## 1.12 — plus the old flat warm emissive lift, it came back
## BROWN-MONOCHROME. Measured on in-game frames from the ceremony camera:
## hide median hue 240° sat 0.114 val 0.137, sail median hue 25° sat 0.142 —
## two materials a quarter of a saturation point apart, both in the mud, so
## hide, sail, plates and bone all read as ONE brown blob at hall distance.
##
## The fix is the ALBEDO, per the author's own note — nothing here depends on
## emission to read (the coals are authored bright). Three moves:
##   1. lift the hide OUT of the mud and push it further BLUE-slate,
##   2. push the sail the other way, WARM, so it separates by HUE and the
##      wings read as leather against cold scale instead of more of it,
##   3. stop painting a warm lift over everything — including the coals,
##      whose authored emission the old pass silently overwrote with it.
const EMISSIVE_LIFT := Color(0.15, 0.145, 0.165)   # near-neutral, weaker
const HIDE_GAIN := 1.62
const HIDE_COOL := Color(0.86, 0.97, 1.22)
const SAIL_GAIN := 1.34
const SAIL_WARM := Color(1.34, 0.94, 0.70)
const BONE_GAIN := 1.12
## Board units from the armature root to the torso/chest mass centre at rig
## scale 1.0 (measured on the shipped GLB; feet at y = 0.000). This is the
## number every "where does the beast READ on screen" calculation uses.
const BODY_RISE := 0.95
const HEAD_BONE := "Head"
const HEAD_END_BONE := "Head_end"

var anim: AnimationPlayer = null
var skeleton: Skeleton3D = null

var _mouth: Node3D = null


## Build a rig under `parent`. `pos`/`yaw`/`rig_scale` land on this wrapper
## node; the GLB scene hangs unscaled beneath it.
static func spawn(parent: Node, rig_name: String, pos: Vector3, yaw: float,
		rig_scale: float) -> DragonRig:
	var rig := DragonRig.new()
	rig.name = rig_name
	parent.add_child(rig)
	rig.position = pos
	rig.rotation.y = yaw
	rig.scale = Vector3.ONE * rig_scale
	return rig


func _ready() -> void:
	var model := DRAGON_SCENE.instantiate()
	model.name = "Model"
	add_child(model)
	_apply_emissive_lift(model)
	var anims := model.find_children("*", "AnimationPlayer", true, false)
	anim = anims[0] if not anims.is_empty() else null
	var skels := model.find_children("*", "Skeleton3D", true, false)
	skeleton = skels[0] if not skels.is_empty() else null


## The 8-omni budget is FULL — no light for the dragon. It is lit out of the
## gloom by material work alone: a per-ROLE albedo correction (see the
## palette block above) plus a faint self-glow. Roles come from the GLB's
## material names, which `dragon-v2/tools/verify_glb.py` asserts, so a
## rename cannot silently slip past this. An unrecognised material (any
## other model routed through this rig) falls back to the old flat lift.
func _apply_emissive_lift(model: Node) -> void:
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s)
			if src is StandardMaterial3D:
				var m: StandardMaterial3D = src.duplicate()
				_paint_for_hall(m)
				mi.set_surface_override_material(s, m)


static func _paint_for_hall(m: StandardMaterial3D) -> void:
	var role := m.resource_name
	if role.begins_with("dragon_ember"):
		# THE COALS. Authored bright and already emissive — the old pass
		# overwrote that emission with the flat lift and put the fire in the
		# throat out. Leave them exactly as the asset intends.
		m.emission_enabled = true
		return
	if role.begins_with("dragon_membrane"):
		# THE SAIL: dark ash-leather, pushed WARM so it separates from the
		# cold hide by hue rather than fighting it for value. The warm rim
		# (`dragon_membrane_edge`) keeps its authored glow.
		m.albedo_color = _tint(m.albedo_color, SAIL_GAIN, SAIL_WARM)
		if not m.emission_enabled:
			m.emission_enabled = true
			m.emission = EMISSIVE_LIFT
		return
	if role == "dragon_void":
		return   # eye sockets stay holes
	if role == "dragon_bone":
		m.albedo_color = _tint(m.albedo_color, BONE_GAIN, Color.WHITE)
		m.emission_enabled = true
		m.emission = EMISSIVE_LIFT
		return
	# THE HIDE (scale / scale_dark / scute / plate) and anything unnamed:
	# lifted out of the mud and pushed cool blue-slate.
	var cool := HIDE_COOL if role.begins_with("dragon_") else Color.WHITE
	m.albedo_color = _tint(m.albedo_color, HIDE_GAIN, cool)
	m.emission_enabled = true
	m.emission = EMISSIVE_LIFT


## Gain + hue push, alpha untouched and every channel clamped (a Color
## multiplied by a float in GDScript also scales alpha — the exact trap the
## dracarys kit documents).
static func _tint(c: Color, gain: float, tint: Color) -> Color:
	return Color(
		clampf(c.r * gain * tint.r, 0.0, 1.0),
		clampf(c.g * gain * tint.g, 0.0, 1.0),
		clampf(c.b * gain * tint.b, 0.0, 1.0),
		c.a)


# -- clips -----------------------------------------------------------------


func has_clip(clip: String) -> bool:
	return anim != null and anim.has_animation(clip)


func clip_length(clip: String) -> float:
	if not has_clip(clip):
		return 0.0
	return anim.get_animation(clip).length


## Loop `clip` (loop mode forced onto the imported animation, which ships
## one-shot) at `speed`. Safe no-op when the clip is missing.
func play_loop(clip: String, speed: float = 1.0, blend: float = 0.3) -> void:
	if not has_clip(clip):
		return
	anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	anim.speed_scale = speed
	anim.play(clip, blend)


## Play `clip` once at `speed`; returns its wall-clock duration (0.0 when
## missing) so callers can await their own clocks — this never blocks.
func play_once(clip: String, speed: float = 1.0, blend: float = 0.15) -> float:
	if not has_clip(clip):
		return 0.0
	anim.get_animation(clip).loop_mode = Animation.LOOP_NONE
	anim.speed_scale = speed
	anim.play(clip, blend)
	return clip_length(clip) / maxf(speed, 0.01)


## Take the playhead by hand: the clip is loaded and PAUSED, and the caller
## drives it with seek_clip() off its own wall clock.
##
## Why the ceremony needs this: `Rear_Breathe` is authored inhale (0.00-0.92)
## → HELD BLAST (0.92-1.33) → recoil (1.75-2.25). The shot is that 0.41 s
## hold — but the ASHFALL breath sweeps fire across a whole army over ~2.8 s
## of wall clock under a 0.55 time_scale. No single playback speed can make
## a 0.41 s hold cover a 2.8 s sweep AND keep the lunge snappy, so the
## ceremony maps wall time onto clip time itself (see _breath_clip_time).
## Returns false when the clip is missing.
func play_manual(clip: String) -> bool:
	if not has_clip(clip):
		return false
	anim.get_animation(clip).loop_mode = Animation.LOOP_NONE
	anim.speed_scale = 1.0
	anim.play(clip)
	anim.pause()
	anim.seek(0.0, true)
	return true


## Park a hand-driven playhead at `t` seconds (see play_manual).
func seek_clip(t: float) -> void:
	if anim == null:
		return
	anim.seek(maxf(t, 0.0), true)


# -- emissive particle builder (shared: ashfall flame, ember drift) --------


## A soft radial alpha falloff, built once per emitter.
##
## THIS IS THE FIX FOR "BARE OPAQUE SQUARES". Every emitter this factory
## built used to ship a QuadMesh with NO albedo_texture — so each particle
## drew a flat, hard-edged, screen-aligned RECTANGLE of uniform alpha. That
## is exactly what the art critic saw and named ("bare opaque squares… JPEG
## compression blocks, not embers"). Swapping the ashfall flame for the
## dracarys kit did NOT fix it: the smoulder wisps and the tableau ember
## drift still came through here, and grey rectangles were still hanging in
## the hall after the fire (caught by eye on in-game frames 2026-08-09, then
## pinned down by dyeing the kit's own billboards red and watching the
## squares stay grey — they were never the kit's).
static func _soft_dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 0.72, 1.0])
	g.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0), Color(1.0, 1.0, 1.0, 0.72),
		Color(1.0, 1.0, 1.0, 0.22), Color(1.0, 1.0, 1.0, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 96
	t.height = 96
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t


## GPUParticles3D factory for every dragon effect — EMISSIVE MATERIALS ONLY
## (the hall's 8-omni budget is FULL: this helper never creates a Light3D).
## cfg keys: amount, lifetime, size, velocity(Vector2 min/max), spread,
## gravity, grow, ramp([[offset, Color], ...]), blend, emission_energy;
## optional: direction (default +Z out of the jaws), emission_radius.
static func spawn_emitter(parent: Node3D, node_name: String, cfg: Dictionary) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = node_name
	p.amount = cfg["amount"]
	p.lifetime = cfg["lifetime"]
	p.emitting = false
	p.speed_scale = 1.5   # reads fierce under the ashfall slow-mo
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var pm := ParticleProcessMaterial.new()
	pm.direction = cfg.get("direction", Vector3(0.0, 0.0, 1.0))
	pm.spread = cfg["spread"]
	pm.initial_velocity_min = (cfg["velocity"] as Vector2).x
	pm.initial_velocity_max = (cfg["velocity"] as Vector2).y
	pm.gravity = cfg["gravity"]
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = cfg.get("emission_radius", 0.09)
	pm.scale_min = 0.7
	pm.scale_max = 1.25
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.35))
	curve.add_point(Vector2(0.4, 1.0))
	curve.add_point(Vector2(1.0, cfg["grow"] / 2.6))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for stop in cfg["ramp"]:
		offs.append(stop[0])
		cols.append(stop[1])
	grad.offsets = offs
	grad.colors = cols
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(cfg["size"], cfg["size"])
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = cfg["blend"]
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_dot()   # never ship an untextured quad
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.disable_receive_shadows = true
	mat.disable_ambient_light = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	if float(cfg["emission_energy"]) > 0.0:
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.45, 0.12)
		mat.emission_energy_multiplier = cfg["emission_energy"]
	quad.material = mat
	p.draw_pass_1 = quad
	parent.add_child(p)
	return p


# -- head-bone mount (ashfall flame origin) --------------------------------


## A Node3D riding the Head bone at the snout tip, +Z aimed out of the
## mouth. Lazily built; null when the rig has no head bone (never the case
## for the shipped GLB, but the rig stays duck-safe).
func mouth_node() -> Node3D:
	if _mouth != null:
		return _mouth
	if skeleton == null:
		return null
	var head := skeleton.find_bone(HEAD_BONE)
	if head == -1:
		return null
	var att := BoneAttachment3D.new()
	att.name = "MouthMount"
	att.bone_name = HEAD_BONE
	skeleton.add_child(att)
	var mouth := Node3D.new()
	mouth.name = "Mouth"
	att.add_child(mouth)
	# Place the mouth just past the snout: Head_end in head-bone space.
	var head_rest := skeleton.get_bone_global_rest(head)
	var end_idx := skeleton.find_bone(HEAD_END_BONE)
	if end_idx != -1:
		var local_end: Vector3 = head_rest.affine_inverse() \
			* skeleton.get_bone_global_rest(end_idx).origin
		mouth.position = local_end * 1.15
		# Aim +Z along the bone (out of the mouth): -Z toward the head.
		if local_end.length() > 0.001:
			mouth.basis = Basis.looking_at(-local_end.normalized(), Vector3.FORWARD)
	_mouth = mouth
	return _mouth
