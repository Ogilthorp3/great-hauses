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
## Clips shipped in the GLB (probed 2026-08-08):
##   Death · Fast_Flying · Flying_Idle · Headbutt · HitReact · No · Punch · Yes
## Rig: 17 bones — Root/Torso/Neck/Head(+_end), 4-bone wings. The mesh
## floats ~1.6-3.1 u above the armature root (ships mid-flight), so callers
## place the root LOW. Native forward is +Z (rotate PI to face -Z).

const DRAGON_SCENE: PackedScene = preload("res://assets/custom-props/dragon.glb")
## Dim torch-glow lift so the beast reads inside the dark hall (same value
## the championship staging always used).
const EMISSIVE_LIFT := Color(0.22, 0.17, 0.13)
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


## The 8-omni budget is FULL — no light for the dragon. Lift it out of pure
## black with a faint warm material self-glow instead (no light nodes).
func _apply_emissive_lift(model: Node) -> void:
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s)
			if src is StandardMaterial3D:
				var m: StandardMaterial3D = src.duplicate()
				m.emission_enabled = true
				m.emission = EMISSIVE_LIFT
				mi.set_surface_override_material(s, m)


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


# -- emissive particle builder (shared: ashfall flame, ember drift) --------


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
