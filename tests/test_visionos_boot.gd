extends SceneTree

# XR bring-up is four calls and every one is a SILENT failure if missed:
# find_interface -> initialize -> viewport.use_xr -> XROrigin3D.current.
# The visionOS interface does not exist on macOS, so bring_up() takes its
# side effects as Callables and this suite drives it with fakes.
#
# set_origin_current and set_near are NOT fire-and-forget: each Callable
# returns a bool, and bring_up() treats false as a failure at step "origin" /
# "near" — a build with no node in the "xr_origin" / "xr_camera" group must
# be REPORTED, not silently accepted as "done" (2026-08-10 review: this was
# exactly backwards — both setters were `-> void`, so a missing rig produced
# {ok: true, step: "done"} and is_immersive() == true while doing nothing).
# Cases 5 and 6 below prove those two failures are reported AND that the
# once-only guard does not latch on them, so a later bring_up (once the rig
# exists) still runs for real.
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


## origin_ok / near_ok let a case simulate a missing "xr_origin" / "xr_camera"
## group node without touching any real scene tree — set_origin_current and
## set_near still log the call (so ordering/skip assertions keep working),
## they just report failure via their return value, exactly like the real
## XRSession helpers do when get_first_node_in_group() comes back null.
func _deps(iface, log: Array, origin_ok := true, near_ok := true) -> Dictionary:
	return {
		"find_interface": func(n: String): log.append("find:" + n); return iface,
		"set_use_xr": func(v: bool) -> void: log.append("use_xr:" + str(v)),
		"set_origin_current": func(v: bool) -> bool: log.append("origin:" + str(v)); return origin_ok,
		"set_near": func(v: float) -> bool: log.append("near:" + str(v)); return near_ok,
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

	# 5. set_origin_current returning false must abort at step 'origin' — a
	#    build with no node in the 'xr_origin' group must be REPORTED, not
	#    silently accepted as 'done' (2026-08-10 review: this was the defect —
	#    the setter was void, the missing group was invisible, and bring_up()
	#    still returned ok=true). set_near must never run once origin failed,
	#    and — critically — the once-only guard must NOT latch on this
	#    failure: a later bring_up (no reset in between) with a working
	#    origin must run for real, proven by initialize() being called again.
	VB._reset_for_test()
	var iface5 := FakeInterface.new()
	var log5: Array = []
	var r5o := VB.bring_up(_deps(iface5, log5, false, true))
	_ok("origin failure -> not ok", r5o.ok == false)
	_ok("origin failure -> step 'origin'", r5o.step == "origin")
	_ok("origin failure -> error is a diagnostic string", r5o.error != "")
	_ok("origin failure -> near never set", not log5.has("near:0.1"))
	iface5.initialized = false
	var r5b := VB.bring_up(_deps(iface5, [], true, true))
	_ok("origin failure did not latch the once-only guard -> next bring_up runs for real",
		r5b.ok == true and iface5.initialized)

	# 6. set_near returning false must abort at step 'near' — same
	#    report-don't-latch guarantee as case 5, on the other silent setter.
	VB._reset_for_test()
	var iface6 := FakeInterface.new()
	var log6: Array = []
	var r6n := VB.bring_up(_deps(iface6, log6, true, false))
	_ok("near failure -> not ok", r6n.ok == false)
	_ok("near failure -> step 'near'", r6n.step == "near")
	_ok("near failure -> error is a diagnostic string", r6n.error != "")
	_ok("near failure -> origin WAS set before near ran", log6.has("origin:true"))
	iface6.initialized = false
	var r6b := VB.bring_up(_deps(iface6, [], true, true))
	_ok("near failure did not latch the once-only guard -> next bring_up runs for real",
		r6b.ok == true and iface6.initialized)

	# 7. On a non-visionOS host, is_immersive() must be false and start() must
	#    fail at 'find' — the macOS build must keep booting normally.
	# Cases 5/6 leave the once-only guard 'up' (their recovery bring_up
	# succeeded) — reset here too, or XS.start() below would short-circuit
	# straight to {ok: true, step: "done"} and this case would prove nothing.
	VB._reset_for_test()
	const XS := preload("res://src/xr/xr_session.gd")
	_ok("macOS host is not immersive", XS.is_immersive() == false)
	var r7 := XS.start(self)
	_ok("macOS start() fails at find", r7.ok == false and r7.step == "find")

	# 8. The REAL XRSession helpers, not fakes. Cases 5/6 only prove that
	#    VisionOSBoot.bring_up() honours a false return from its deps — they
	#    never call XRSession._set_origin_current/_set_near themselves, and
	#    on this host XRSession.start() always fails at 'find' before it
	#    could ever reach them either. So without this case, reverting
	#    _set_origin_current to silently `return true` on a null node would
	#    slip past the whole suite undetected — which is exactly the
	#    regression this round of review exists to close. This suite's own
	#    tree has nothing in "xr_origin"/"xr_camera" (repo-wide grep: zero
	#    hits — the rig is deferred to a later plan), so it doubles as a
	#    faithful stand-in for "the group genuinely does not exist yet".
	_ok("XRSession._set_origin_current returns false with no 'xr_origin' node",
		XS._set_origin_current(self, true) == false)
	_ok("XRSession._set_near returns false with no 'xr_camera' node",
		XS._set_near(self, 0.1) == false)

	print("=== %s ===" % ("PASS" if failures == 0 else "%d FAILURES" % failures))
	quit(1 if failures > 0 else 0)
