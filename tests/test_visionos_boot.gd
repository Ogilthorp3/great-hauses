extends SceneTree

# XR bring-up is four calls and every one is a SILENT failure if missed:
# find_interface -> initialize -> viewport.use_xr -> XROrigin3D.current.
# The visionOS interface does not exist on macOS, so bring_up() takes its
# side effects as Callables and this suite drives it with fakes.
#
# bring_up() also latches a process-wide once-only guard after the first
# success, so a second call short-circuits before find/initialize and before
# the three setters (case 4). That guard is a static — it survives across
# cases in this one process — so every case below opens with
# VB._reset_for_test() to isolate itself from whatever the previous case
# left behind, and case 4 spends its first assertion PROVING that reset
# actually cleared the guard before trusting anything downstream of it. A
# reset that silently no-ops would otherwise make every case after the first
# success run against an already-'up' session and pass vacuously.

const VB := preload("res://src/xr/visionos_boot.gd")

var failures := 0


func _initialize() -> void:
	_main()


func _ok(label: String, cond: bool) -> void:
	if cond:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s" % label)
		failures += 1


class FakeInterface extends RefCounted:
	var init_result := true
	var initialized := false
	func initialize() -> bool:
		initialized = true
		return init_result


func _deps(iface, log: Array) -> Dictionary:
	return {
		"find_interface": func(n: String): log.append("find:" + n); return iface,
		"set_use_xr": func(v: bool) -> void: log.append("use_xr:" + str(v)),
		"set_origin_current": func(v: bool) -> void: log.append("origin:" + str(v)),
		"set_near": func(v: float) -> void: log.append("near:" + str(v)),
	}


func _main() -> void:
	print("=== visionOS XR bring-up ===")

	# 1. Missing interface must fail loudly at the FIRST step, not silently later.
	VB._reset_for_test()
	var log1: Array = []
	var r1 := VB.bring_up(_deps(null, log1))
	_ok("absent interface -> not ok", r1.ok == false)
	_ok("absent interface -> step 'find'", r1.step == "find")
	_ok("absent interface -> no viewport touched", log1 == ["find:visionOSXR"])
	_ok("absent interface -> error is a diagnostic string", r1.error != "")

	# 2. The interface does NOT auto-initialize; a false return must abort.
	VB._reset_for_test()
	var iface2 := FakeInterface.new()
	iface2.init_result = false
	var log2: Array = []
	var r2 := VB.bring_up(_deps(iface2, log2))
	_ok("initialize() called", iface2.initialized)
	_ok("failed initialize -> not ok", r2.ok == false)
	_ok("failed initialize -> step 'initialize'", r2.step == "initialize")
	_ok("failed initialize -> use_xr never set", not log2.has("use_xr:true"))
	_ok("failed initialize -> error is a diagnostic string", r2.error != "")

	# 3. Happy path: exact order, and the near plane is pinned to the floor.
	# This is also the only case that leaves the once-only guard 'up' — case 4
	# resets it back down and PROVES the reset worked before relying on it.
	VB._reset_for_test()
	var iface3 := FakeInterface.new()
	var log3: Array = []
	var r3 := VB.bring_up(_deps(iface3, log3))
	_ok("happy path ok", r3.ok == true)
	_ok("happy path step 'done'", r3.step == "done")
	_ok("order is find,use_xr,origin,near", log3 == [
		"find:visionOSXR", "use_xr:true", "origin:true", "near:0.1"])

	# 4. Once-only: a second bring_up on an already-up session must NOT
	#    re-run initialize() or the three setters — it only reports ok.
	VB._reset_for_test()
	var iface4 := FakeInterface.new()
	var deps4 := _deps(iface4, [])
	var r4a := VB.bring_up(deps4)
	# Proves the reset above actually cleared the guard case 3 set: if it had
	# leaked, this first call would short-circuit straight to 'done' without
	# ever touching iface4, and every assertion below would pass vacuously
	# against a FakeInterface that was never called.
	_ok("reset cleared the once-only guard -> first call ran for real",
		r4a.step == "done" and iface4.initialized)
	iface4.initialized = false
	var r4 := VB.bring_up(deps4)
	_ok("second bring_up still ok", r4.ok == true)
	_ok("second bring_up did not re-run initialize()", not iface4.initialized)

	# 5. On a non-visionOS host, is_immersive() must be false and start() must
	#    fail at 'find' — the macOS build must keep booting normally.
	# Case 4 leaves the once-only guard 'up' (its second bring_up succeeded
	# without re-running anything) — reset here too, or XS.start() below would
	# short-circuit straight to {ok: true, step: "done"} and this case would
	# prove nothing.
	VB._reset_for_test()
	const XS := preload("res://src/xr/xr_session.gd")
	_ok("macOS host is not immersive", XS.is_immersive() == false)
	var r5 := XS.start(self)
	_ok("macOS start() fails at find", r5.ok == false and r5.step == "find")

	print("=== %s ===" % ("PASS" if failures == 0 else "%d FAILURES" % failures))
	quit(1 if failures > 0 else 0)
