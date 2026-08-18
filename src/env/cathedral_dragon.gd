class_name CathedralDragon
extends Node3D
## CathedralDragon — Ambient and Event-Driven Dragon Flight in the Sanctum Cathedral.
## Drives the DragonRig through majestic flight paths, banking turns, and rafter perches
## in the soaring 36m Gothic Cathedral vaulting.

const DragonRigScript := preload("res://src/cinematics/dragon_rig.gd")

var _rig: DragonRig = null
var _flight_time: float = 0.0
var _is_patrolling: bool = true
var _flight_speed: float = 0.18   # Speed along flight loop
var _flight_altitude: float = 20.0
var _bank_angle: float = 0.0
var _current_loop_radius: float = 14.0

# Waypoints around the Cathedral Nave for smooth spline patrol
const PATROL_NODES := [
	Vector3(0.0, 22.0, -18.0),
	Vector3(7.5, 24.5, -8.0),
	Vector3(8.0, 23.0, 8.0),
	Vector3(2.0, 21.0, 20.0),
	Vector3(-4.0, 23.5, 18.0),
	Vector3(-8.0, 25.0, 4.0),
	Vector3(-7.5, 23.0, -10.0),
]


func _ready() -> void:
	_rig = DragonRigScript.new()
	_rig.name = "DragonRig"
	add_child(_rig)
	_rig.scale = Vector3.ONE * 1.35
	_rig.play_loop("Glide", 1.0)
	set_process(true)


func _process(delta: float) -> void:
	if not _is_patrolling:
		return

	_flight_time += delta * _flight_speed
	var t := fmod(_flight_time, float(PATROL_NODES.size()))
	var idx := int(floor(t))
	var frac := t - float(idx)

	# Catmull-Rom or cubic spline interpolation between nodes
	var p0: Vector3 = PATROL_NODES[(idx - 1 + PATROL_NODES.size()) % PATROL_NODES.size()]
	var p1: Vector3 = PATROL_NODES[idx]
	var p2: Vector3 = PATROL_NODES[(idx + 1) % PATROL_NODES.size()]
	var p3: Vector3 = PATROL_NODES[(idx + 2) % PATROL_NODES.size()]

	var next_pos := _cubic_spline(p0, p1, p2, p3, frac)
	var tangent_t := fmod(_flight_time + 0.04, float(PATROL_NODES.size()))
	var t_idx := int(floor(tangent_t))
	var t_frac := tangent_t - float(t_idx)
	var tp0: Vector3 = PATROL_NODES[(t_idx - 1 + PATROL_NODES.size()) % PATROL_NODES.size()]
	var tp1: Vector3 = PATROL_NODES[t_idx]
	var tp2: Vector3 = PATROL_NODES[(t_idx + 1) % PATROL_NODES.size()]
	var tp3: Vector3 = PATROL_NODES[(t_idx + 2) % PATROL_NODES.size()]
	var forward_pos := _cubic_spline(tp0, tp1, tp2, tp3, t_frac)

	global_position = next_pos

	var dir := (forward_pos - next_pos).normalized()
	if dir.length_squared() > 0.001:
		var target_look := global_position + dir
		look_at(target_look, Vector3.UP)
		# Add bank roll on turns
		var turn_yaw_delta := -dir.x * 0.45
		rotate_object_local(Vector3.FORWARD, turn_yaw_delta)

	# Flap wings when ascending or periodically
	var v_speed := dir.y
	if _rig.anim != null:
		if v_speed > 0.15:
			if _rig.anim.current_animation != "Fast_Flying":
				_rig.play_loop("Fast_Flying", 1.1)
		else:
			if _rig.anim.current_animation != "Glide":
				_rig.play_loop("Glide", 0.95)


func swoop_over_altar() -> void:
	## Dramatic dive through the nave over the chess board and back into rafters
	if not _is_patrolling:
		return
	var tw := create_tween().set_parallel(false)
	_rig.play_loop("Fast_Flying", 1.4)
	tw.tween_property(self, "global_position:y", 8.5, 2.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func(): _rig.play_once("Roar", 1.2))
	tw.tween_interval(1.5)
	tw.tween_property(self, "global_position:y", 22.0, 3.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): _rig.play_loop("Glide", 1.0))


func _cubic_spline(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (
		(2.0 * p1) +
		(-p0 + p2) * t +
		(2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
		(-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)
