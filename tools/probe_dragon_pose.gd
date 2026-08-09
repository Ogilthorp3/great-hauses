extends SceneTree
## probe_dragon_pose.gd — the SLUMBER COIL's calibration instrument.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
##       -s res://tools/probe_dragon_pose.gd
##
## Why this exists. DragonRig's slumber coil is a SkeletonModifier3D that
## post-multiplies per-bone rotations onto whatever clip is playing, and its
## angles were CHOSEN BY MEASUREMENT (a uniform neck fold big enough to put
## the head on the stone also rolls the skull past level — the wyrm slept
## upside-down on the first attempt). Re-tuning it needs the same numbers
## back, and they are not readable the obvious way: Godot runs the modifier
## stack, hands the result to the skin, then RESTORES the animation pose, so
## `skeleton.get_bone_global_pose()` from _process reports the CLIP's pose and
## a coil that never moved a vertex looks identical to one that did. The only
## place the coiled pose exists is inside the stack, which is what
## `Slumber.sample_bones` / `Slumber.sampled` expose and what this prints.
##
## Landmarks below are rig-local at scale 1.0, feet-on-floor at y = 0. Read
## them with DragonRig.SLUMBER_ROOT_DROP: the node sinks by that much in the
## game, so subtract it for the world height of anything printed here.
## `-- --bones=A,B,C` overrides the sampled set.

const RigScript := preload("res://src/cinematics/dragon_rig.gd")

const DEFAULT_BONES := ["Chest", "Neck3", "Head", "Head_end", "Jaw",
	"Wing1.L", "Wing2.L", "Wing3.L", "Tail4", "Tail6", "Tail8",
	"Thigh.L", "Foot.L", "Toe.L"]

var _rig: DragonRig = null
var _coil = null


func _initialize() -> void:
	_main()


func _main() -> void:
	var bones: Array = DEFAULT_BONES.duplicate()
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--bones="):
			bones = Array(str(a).substr(8).split(",", false))
	_rig = RigScript.spawn(root, "Probe", Vector3.ZERO, 0.0, 1.0)
	await process_frame
	await process_frame
	print("=== dragon rig ===")
	print("  bones=%d  ember materials=%d  root drop=%.3f"
		% [_rig.skeleton.get_bone_count(), _rig.ember_material_count(),
			RigScript.SLUMBER_ROOT_DROP])
	for c in _rig.anim.get_animation_list():
		print("  clip %-14s len=%.2f" % [c, _rig.clip_length(c)])
	_coil = _rig.attach_slumber(RigScript.slumber_default(), 0.0, 0.55)
	_coil.sample_bones = bones
	print("=== coil: %d bends ===" % _coil.bend_count())
	# The clip's own pose, then the coiled one, so the delta is right there.
	var awake := await _sample(0.0)
	var asleep := await _sample(1.0)
	print("%-10s %-25s %-25s %s" % ["bone", "AWAKE (clip)", "ASLEEP (coiled)", "dy"])
	for b in bones:
		var a: Vector3 = awake.get(b, Vector3.INF)
		var s: Vector3 = asleep.get(b, Vector3.INF)
		print("%-10s (%6.3f,%6.3f,%6.3f)    (%6.3f,%6.3f,%6.3f)    %+.3f" % [
			b, a.x, a.y, a.z, s.x, s.y, s.z, s.y - a.y])
	# The two numbers the pose lives or dies by, in WORLD terms.
	var snout: Vector3 = asleep.get("Head_end", Vector3.INF)
	var toe: Vector3 = asleep.get("Toe.L", Vector3.INF)
	print("--- chin above the stone : %+.3f (want ~0)"
		% (snout.y - RigScript.SLUMBER_ROOT_DROP))
	print("--- claws above the stone: %+.3f (want ~0)"
		% (toe.y - RigScript.SLUMBER_ROOT_DROP - 0.17))
	quit(0)


func _sample(weight: float) -> Dictionary:
	_coil.weight = weight
	_rig.play_manual("Perch_Idle")
	_rig.seek_clip(0.0)
	await process_frame
	await process_frame
	return (_coil.sampled as Dictionary).duplicate()
