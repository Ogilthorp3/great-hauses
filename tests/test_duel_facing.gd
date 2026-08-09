extends SceneTree

# Headless unit tests for the FACE-TO-FACE duel doctrine (2026-08-08):
# DuelDirector turns both combatants to meet before the strike and holds
# the lock through it, the survivor eases back to his side's resting yaw,
# and the checkmate king dies facing his killer. Includes the regression
# that motivated the feature: a stale fire-and-forget rotation tween (the
# _face_home tween PieceView leaves after a walk) must NOT leave a duel
# fought back-to-back.
# Run: /Applications/Godot.app/Contents/MacOS/Godot --headless --path <project> -s res://tests/test_duel_facing.gd
# Exit code 0 = all green, 1 = failures.

const DD := preload("res://src/cinematics/duel_director.gd")

var failures := 0
var checks_run := 0

## Silent-abort floor (same guard as test_cinematics.gd).
const MIN_EXPECTED_CHECKS := 20


class Duck:
	extends Node3D
	## PieceView-shaped fighter: the duck fields DuelDirector reads for
	## facing (piece_type/side) plus the spawn-orientation field
	## (_home_yaw) the rest-restore duck-reads.
	var piece_type := 2   # knight
	var side := 0         # FROST
	var _home_yaw := 0.0

	func _init(pt: int = 2, s: int = 0, home: float = 0.0) -> void:
		piece_type = pt
		side = s
		_home_yaw = home
		rotation.y = home


func _initialize() -> void:
	_main()


func _main() -> void:
	print("=== Great Hauses — duel facing headless suite ===")
	await process_frame
	await process_frame
	Engine.time_scale = 1.0
	await _test_duel_face_off()
	await _test_rook_exemption()
	await _test_checkmate_facing()
	await _test_skip_still_rests()
	check("final: time_scale is 1.0", true, is_equal_approx(Engine.time_scale, 1.0))
	check("final: no test silently aborted (checks >= %d)" % MIN_EXPECTED_CHECKS,
			true, checks_run >= MIN_EXPECTED_CHECKS)
	print("---")
	if failures == 0:
		print("DUELFACING OK — all checks passed")
	else:
		print("DUELFACING FAILED — %d check(s) failed" % failures)
	quit(0 if failures == 0 else 1)


## Helpers ##


func check(test_name: String, expected, actual) -> void:
	checks_run += 1
	var ok := str(expected) == str(actual)
	if not ok:
		failures += 1
	print("%s %s (expected %s, got %s)" % ["PASS" if ok else "FAIL", test_name, expected, actual])


func _fast_director() -> DuelDirector:
	var d: DuelDirector = DD.new()
	d.swoop_wall = 0.05
	d.return_wall = 0.05
	d.duel_ramp_down_wall = 0.05
	d.duel_slow_hold_wall = 0.15
	d.duel_ramp_up_wall = 0.05
	d.duel_tail_wall = 0.05
	d.checkmate_hold_wall = 0.15
	d.face_off_wall = 0.1
	d.face_rest_wall = 0.1
	d.failsafe_wall_sec = 5.0
	root.add_child(d)
	return d


func _wait_wall(sec: float) -> void:
	await create_timer(sec, true, false, true).timeout


func _wait_until(pred: Callable, timeout_sec: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if pred.call():
			return true
		await process_frame
	return false


static func _fwd(n: Node3D) -> Vector3:
	return n.global_transform.basis.z.normalized()   # native forward is +Z


## The full claim: forwards anti-parallel AND each pointed at the other.
static func _facing_each_other(a: Node3D, b: Node3D) -> bool:
	var dir := (b.global_position - a.global_position)
	dir.y = 0.0
	if dir.length() < 0.01:
		return false
	dir = dir.normalized()
	return _fwd(a).dot(_fwd(b)) < -0.95 \
		and _fwd(a).dot(dir) > 0.95 \
		and _fwd(b).dot(-dir) > 0.95


static func _yaw_close(n: Node3D, yaw: float, tol: float = 0.06) -> bool:
	return absf(wrapf(n.rotation.y - yaw, -PI, PI)) < tol


## Tests ##


func _test_duel_face_off() -> void:
	var d := _fast_director()
	# Both fighters start facing the SAME way (+Z) — decisively not each
	# other — 1.6 u apart on the x axis.
	var a := Duck.new(2, 0, 0.0)
	var v := Duck.new(4, 1, PI)
	root.add_child(a)
	root.add_child(v)
	a.position = Vector3(-0.8, 0.0, 0.0)
	v.position = Vector3(0.8, 0.0, 0.2)
	a.rotation.y = 0.0
	v.rotation.y = 0.0
	check("setup: not facing each other", false, _facing_each_other(a, v))

	# THE REGRESSION: a stale fire-and-forget home-yaw tween on the
	# attacker (exactly what PieceView._face_home leaves behind after the
	# walk to the duel edge) fights the turn — the director must win.
	var stale := a.create_tween()
	stale.tween_property(a, "rotation:y", 0.0, 0.18)

	var probe := {"at_strike": false, "mid_hold": false}
	var strike := func() -> void:
		probe["at_strike"] = _facing_each_other(a, v)
		await _wait_wall(0.3)   # inside the slow-mo window at test speeds
		probe["mid_hold"] = _facing_each_other(a, v)
		await _wait_wall(0.05)
	await d.play_duel(a, v, {}, strike)
	check("duel: face to face at strike time", true, probe["at_strike"])
	check("duel: lock holds through the strike", true, probe["mid_hold"])
	check("duel: survivor back at resting yaw", true, _yaw_close(a, a._home_yaw))
	check("duel: time_scale restored", true, is_equal_approx(Engine.time_scale, 1.0))
	check("duel: inactive after", false, d.is_active())
	d.free()
	a.free()
	v.free()


func _test_rook_exemption() -> void:
	## Towers have no face: the rook's yaw must never be touched, while
	## the living fighter still turns to face the tower.
	var d := _fast_director()
	var a := Duck.new(2, 0, 0.0)          # knight
	var rook := Duck.new(1, 1, PI)        # the tower
	root.add_child(a)
	root.add_child(rook)
	a.position = Vector3(-0.8, 0.0, 0.4)
	rook.position = Vector3(0.9, 0.0, -0.3)
	a.rotation.y = 0.0
	rook.rotation.y = 0.7   # arbitrary — must stay exactly here
	var probe := {"attacker_on_target": false, "rook_yaw": 0.0}
	var strike := func() -> void:
		var dir := (rook.global_position - a.global_position).normalized()
		probe["attacker_on_target"] = _fwd(a).dot(dir) > 0.95
		probe["rook_yaw"] = rook.rotation.y
		await _wait_wall(0.1)
	await d.play_duel(a, rook, {}, strike)
	check("rook: attacker faces the tower", true, probe["attacker_on_target"])
	check("rook: tower yaw untouched at strike", true,
			is_equal_approx(float(probe["rook_yaw"]), 0.7))
	check("rook: tower yaw untouched after", true, is_equal_approx(rook.rotation.y, 0.7))
	check("rook: time_scale restored", true, is_equal_approx(Engine.time_scale, 1.0))
	d.free()
	a.free()
	rook.free()


func _test_checkmate_facing() -> void:
	## The king dies facing his killer (nearest enemy piece), the killer
	## faces the king — and afterwards resumes his own resting yaw.
	var d := _fast_director()
	var king := Duck.new(5, 1, PI)
	var queen := Duck.new(4, 0, 0.0)      # the killer: nearest enemy
	var far := Duck.new(0, 0, 0.0)        # decoy enemy, much farther out
	root.add_child(king)
	root.add_child(queen)
	root.add_child(far)
	king.position = Vector3(0.0, 0.0, 0.0)
	queen.position = Vector3(1.2, 0.0, 1.2)
	far.position = Vector3(5.0, 0.0, -5.0)
	king.rotation.y = PI
	queen.rotation.y = 0.0
	var probe := {"at_death": false, "far_turned": false}
	var death := func() -> void:
		probe["at_death"] = _facing_each_other(king, queen)
		probe["far_turned"] = not _yaw_close(far, 0.0, 0.01)
		await _wait_wall(0.2)
	await d.play_checkmate(king, "EMBER", death)
	check("checkmate: king faces his killer at death", true, probe["at_death"])
	check("checkmate: the decoy enemy never turned", false, probe["far_turned"])
	check("checkmate: killer resumes resting yaw", true, _yaw_close(queen, 0.0))
	check("checkmate: time_scale restored", true, is_equal_approx(Engine.time_scale, 1.0))
	check("checkmate: inactive after", false, d.is_active())
	d.free()
	king.free()
	queen.free()
	far.free()


func _test_skip_still_rests() -> void:
	## Skip mid-duel: the strike still completes and the survivor still
	## ends at his resting yaw (snapped, not stranded mid-turn).
	var d := _fast_director()
	d.duel_slow_hold_wall = 3.0   # long hold so there is a window to skip in
	var a := Duck.new(2, 0, 0.0)
	var v := Duck.new(4, 1, PI)
	root.add_child(a)
	root.add_child(v)
	a.position = Vector3(-0.8, 0.0, 0.0)
	v.position = Vector3(0.8, 0.0, 0.0)
	a.rotation.y = 0.0
	v.rotation.y = 0.0
	var done := {"v": false}
	var strike := func() -> void:
		await _wait_wall(0.5)
	var runner := func() -> void:
		await d.play_duel(a, v, {}, strike)
		done["v"] = true
	runner.call()
	var slowed: bool = await _wait_until(func() -> bool: return Engine.time_scale < 0.9, 2.0)
	check("skip: slow-mo entered", true, slowed)
	d.skip()
	var finished: bool = await _wait_until(func() -> bool: return done["v"], 3.0)
	check("skip: sequence completes", true, finished)
	check("skip: survivor at resting yaw", true, _yaw_close(a, a._home_yaw))
	check("skip: time_scale restored", true, is_equal_approx(Engine.time_scale, 1.0))
	check("skip: inactive after", false, d.is_active())
	d.free()
	a.free()
	v.free()
