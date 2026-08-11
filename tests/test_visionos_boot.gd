extends SceneTree

# XR bring-up is TWO PHASES with TWO CALL SITES (2026-08-10 review round 1 —
# see visionos_boot.gd's "ORDERING SCAR" doc for the full writeup):
#
#   PHASE 1  bring_up()   find_interface -> initialize -> use_xr
#            called from main.gd._ready(), BEFORE any scene is added.
#   PHASE 2  bind_rig()   xr_origin.current=true -> xr_camera.near>=0.1
#            called from game.gd._ready(), once game.tscn (and its rig) is
#            actually in the tree.
#
# The split exists because ONE bring_up(), with ONE call site in main.gd —
# which runs before ANY scene, including game.tscn where the rig lives — is
# added — cannot ever resolve "xr_origin"/"xr_camera": the lookup ran at a
# point in boot where the rig it wanted did not exist yet. Every real-
# hardware launch failed at step "origin", every single time, no matter how
# correctly the rig was tagged. bind_rig() now REQUIRES phase 1 to have
# already reached "done" (case 5 below) — a rig lookup can no longer even be
# ATTEMPTED before the interface itself is up, which is the structural half
# of the fix. test_xr_rig.gd's "CALL-SITE WIRING" section covers the other
# half: that the right phase is actually called from the right file.
#
# Every one of the four underlying calls (find/initialize/use_xr/origin/near)
# fails SILENTLY if skipped — a missing use_xr renders a flat mono view into
# the headset, a missing XROrigin3D.current renders from the world origin.
# The visionOS interface does not exist on macOS, so both phases take their
# side effects as Callables and this suite drives them with fakes, except
# case 11 which proves the REAL, non-faked path against a real live tree.
#
# set_origin_current and set_near are NOT fire-and-forget: each Callable
# returns a bool, and bind_rig() treats false as a failure at step "origin" /
# "near" — a build with no node in the "xr_origin" / "xr_camera" group must
# be REPORTED, not silently accepted as "done" (2026-08-10 review: this was
# exactly backwards — both setters were `-> void`, so a missing rig produced
# {ok: true, step: "done"} and is_immersive() == true while doing nothing).
# Cases 6 and 7 below prove those two failures are reported AND that phase
# 2's once-only guard does not latch on them, so a later bind_rig (once the
# rig exists) still runs for real.
#
# Each phase latches its OWN process-wide once-only guard after its own
# first success (cases 4 and 8) — they are static, so they survive across
# cases in this one process, and every case below opens with
# VB._reset_for_test() to isolate itself from whatever the previous case
# left behind.

const VB := preload("res://src/xr/visionos_boot.gd")
const XS := preload("res://src/xr/xr_session.gd")

var failures := 0

## Every assertion this run actually executed, printed as ASSERTIONS=<n> at
## the end. run_e2e.sh's run_suite compares it against the count written in
## that file's own header and FAILS the suite on a mismatch — because the two
## header counts had silently drifted to half the real number (2026-08-10
## adversarial audit), i.e. the header described a version of these files that
## no longer existed. A hand-maintained number with nothing checking it is a
## comment, not a count.
var checks := 0


func _initialize() -> void:
	_main()


func _ok(label: String, cond: bool) -> void:
	checks += 1
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


## Phase 1 deps (find_interface, set_use_xr only — see VB.bring_up()'s doc:
## this phase is deliberately given no way to touch origin/near at all).
func _deps1(iface, log: Array) -> Dictionary:
	return {
		"find_interface": func(n: String): log.append("find:" + n); return iface,
		"set_use_xr": func(v: bool) -> void: log.append("use_xr:" + str(v)),
	}


## Phase 2 deps (set_origin_current, set_near only). origin_ok/near_ok let a
## case simulate a missing "xr_origin"/"xr_camera" group node without
## touching any real scene tree — the setters still log the call (so
## ordering/skip assertions keep working), they just report failure via
## their return value, exactly like the real XRSession helpers do when
## get_first_node_in_group() comes back null.
func _deps2(log: Array, origin_ok := true, near_ok := true) -> Dictionary:
	return {
		"set_origin_current": func(v: bool) -> bool: log.append("origin:" + str(v)); return origin_ok,
		"set_near": func(v: float) -> bool: log.append("near:" + str(v)); return near_ok,
	}


func _main() -> void:
	print("=== visionOS XR bring-up (two-phase) ===")

	# ── PHASE 1 : bring_up() ────────────────────────────────────────────

	# 1. Missing interface must fail loudly at the FIRST step, not silently later.
	VB._reset_for_test()
	var log1: Array = []
	var r1 := VB.bring_up(_deps1(null, log1))
	_ok("absent interface -> not ok", r1.ok == false)
	_ok("absent interface -> step 'find'", r1.step == "find")
	_ok("absent interface -> no viewport touched", log1 == ["find:visionOS"])
	_ok("absent interface -> error is a diagnostic string", r1.error != "")

	# 2. The interface does NOT auto-initialize; a false return must abort.
	VB._reset_for_test()
	var iface2 := FakeInterface.new()
	iface2.init_result = false
	var log2: Array = []
	var r2 := VB.bring_up(_deps1(iface2, log2))
	_ok("initialize() called", iface2.initialized)
	_ok("failed initialize -> not ok", r2.ok == false)
	_ok("failed initialize -> step 'initialize'", r2.step == "initialize")
	_ok("failed initialize -> use_xr never set", not log2.has("use_xr:true"))
	_ok("failed initialize -> error is a diagnostic string", r2.error != "")

	# 3. Happy path: exact order. Phase 1 deps carry no origin/near keys at
	#    all, so this ALSO proves phase 1 cannot attempt a rig lookup even
	#    by accident — there is nothing here for it to call.
	VB._reset_for_test()
	var iface3 := FakeInterface.new()
	var log3: Array = []
	var r3 := VB.bring_up(_deps1(iface3, log3))
	_ok("happy path ok", r3.ok == true)
	_ok("happy path step 'done'", r3.step == "done")
	_ok("order is find,use_xr — nothing rig-shaped in this phase",
		log3 == ["find:visionOS", "use_xr:true"])

	# 4. Once-only: a second bring_up on an already-up interface must NOT
	#    re-run initialize() — it only reports ok.
	VB._reset_for_test()
	var iface4 := FakeInterface.new()
	var deps4 := _deps1(iface4, [])
	var r4a := VB.bring_up(deps4)
	# Proves the reset above actually cleared the guard case 3 set: if it had
	# leaked, this first call would short-circuit straight to 'done' without
	# ever touching iface4, and every assertion below would pass vacuously
	# against a FakeInterface that was never called.
	_ok("reset cleared phase 1's guard -> first call ran for real",
		r4a.step == "done" and iface4.initialized)
	iface4.initialized = false
	var r4 := VB.bring_up(deps4)
	_ok("second bring_up still ok", r4.ok == true)
	_ok("second bring_up did not re-run initialize()", not iface4.initialized)

	# ── PHASE 2 : bind_rig() ────────────────────────────────────────────

	# 5. THE ORDERING-SCAR GUARD. bind_rig() called before phase 1 has ever
	#    reached "done" must fail at step "not_active" and must NEVER touch
	#    the origin/near setters — this is the structural half of the fix
	#    (visionos_boot.gd's class doc has the full incident writeup): the
	#    old single-phase bring_up() effectively DID this — attempted the
	#    rig lookup with no guarantee the interface (let alone the rig) was
	#    ready — and it is exactly what made every real-hardware launch fail
	#    at "origin". This case proves that class of mistake is no longer
	#    possible to make silently: skip phase 1, and phase 2 refuses to run
	#    at all rather than attempting a lookup that cannot succeed yet.
	VB._reset_for_test()
	var log5: Array = []
	var r5 := VB.bind_rig(_deps2(log5))
	_ok("bind_rig before bring_up -> not ok", r5.ok == false)
	_ok("bind_rig before bring_up -> step 'not_active'", r5.step == "not_active")
	_ok("bind_rig before bring_up -> error is a diagnostic string", r5.error != "")
	_ok("bind_rig before bring_up -> origin/near NEVER attempted", log5 == [])

	# 6. set_origin_current returning false must abort at step 'origin' — a
	#    build with no node in the 'xr_origin' group must be REPORTED, not
	#    silently accepted as 'done'. set_near must never run once origin
	#    failed, and — critically — phase 2's once-only guard must NOT latch
	#    on this failure: a later bind_rig (no reset in between) with a
	#    working origin must run for real.
	VB._reset_for_test()
	var iface6 := FakeInterface.new()
	VB.bring_up(_deps1(iface6, []))   # phase 1 up first — bind_rig needs it
	var log6o: Array = []
	var r6o := VB.bind_rig(_deps2(log6o, false, true))
	_ok("origin failure -> not ok", r6o.ok == false)
	_ok("origin failure -> step 'origin'", r6o.step == "origin")
	_ok("origin failure -> error is a diagnostic string", r6o.error != "")
	_ok("origin failure -> near never set", not log6o.has("near:0.1"))
	var r6b := VB.bind_rig(_deps2([], true, true))
	_ok("origin failure did not latch phase 2's guard -> next bind_rig runs for real",
		r6b.ok == true and r6b.step == "done")

	# 7. set_near returning false must abort at step 'near' — same
	#    report-don't-latch guarantee as case 6, on the other silent setter.
	VB._reset_for_test()
	var iface7 := FakeInterface.new()
	VB.bring_up(_deps1(iface7, []))
	var log7n: Array = []
	var r7n := VB.bind_rig(_deps2(log7n, true, false))
	_ok("near failure -> not ok", r7n.ok == false)
	_ok("near failure -> step 'near'", r7n.step == "near")
	_ok("near failure -> error is a diagnostic string", r7n.error != "")
	_ok("near failure -> origin WAS set before near ran", log7n.has("origin:true"))
	var r7b := VB.bind_rig(_deps2([], true, true))
	_ok("near failure did not latch phase 2's guard -> next bind_rig runs for real",
		r7b.ok == true and r7b.step == "done")

	# 8. Once-only: a second bind_rig on an already-bound rig must NOT
	#    re-run the setters — it only reports ok.
	VB._reset_for_test()
	var iface8 := FakeInterface.new()
	VB.bring_up(_deps1(iface8, []))
	var deps8 := _deps2([])
	var r8a := VB.bind_rig(deps8)
	_ok("phase 2 first call ran for real", r8a.ok == true and r8a.step == "done")
	var log8b: Array = []
	var r8b := VB.bind_rig(_deps2(log8b))
	_ok("second bind_rig still ok", r8b.ok == true)
	_ok("second bind_rig did not re-run the setters", log8b == [])

	# ── XRSession — the real wiring, not fakes ─────────────────────────

	# 9. On a non-visionOS host, is_immersive() must be false, start() must
	#    fail at 'find', and bind_rig() — called on a host where phase 1
	#    never came up — must fail at 'not_active' too, through the REAL
	#    XRSession call, not VisionOSBoot fakes.
	VB._reset_for_test()
	_ok("macOS host is not immersive", XS.is_immersive() == false)
	var r9a := XS.start(self)
	_ok("macOS start() fails at find", r9a.ok == false and r9a.step == "find")
	var r9b := XS.bind_rig(self)
	_ok("macOS bind_rig() fails at not_active (phase 1 never came up)",
		r9b.ok == false and r9b.step == "not_active")
	_ok("macOS host is still not immersive after a failed bind_rig",
		XS.is_immersive() == false)

	# 10. The REAL XRSession setters, not fakes. Case 6/7 only prove that
	#     VisionOSBoot.bind_rig() honours a false return from its deps — they
	#     never call XRSession._set_origin_current/_set_near themselves. So
	#     without this case, reverting _set_origin_current to silently
	#     `return true` on a null node would slip past the whole suite
	#     undetected — which is exactly the regression this module exists to
	#     close. This suite's own tree has nothing in "xr_origin"/"xr_camera"
	#     yet (case 11 below adds and removes its own), so it doubles as a
	#     faithful stand-in for "the group genuinely does not exist yet".
	_ok("XRSession._set_origin_current returns false with no 'xr_origin' node",
		XS._set_origin_current(self, true) == false)
	_ok("XRSession._set_near returns false with no 'xr_camera' node",
		XS._set_near(self, 0.1) == false)

	# 11. THE MECHANISM HALF of the ordering fix — NOT the ordering guard
	#     itself. Correction (2026-08-10 adversarial audit): this case used to
	#     be labelled "the assertion that would have caught the ordering scar".
	#     It would not have. It calls XS.bind_rig(self) directly, from the
	#     test; it never routes through main.gd or game.gd, so re-introducing
	#     the defect (start() calling bind_rig() internally, game.gd's call
	#     removed) leaves this whole suite green — re-verified at 46/46 after
	#     this round's fixes, so it is a standing limitation, not a stale
	#     note. Only
	#     tests/test_xr_rig.gd's two behavioural call-site sections see that
	#     class of defect. What this case genuinely proves is below.
	#
	#     Cases 1-10 prove the CONTRACT (phase 2 requires phase 1;
	#     phase 1 cannot touch the rig). This case proves the PAYOFF: once
	#     phase 1 is genuinely up AND the rig genuinely exists in a live
	#     tree — the exact situation game.gd._ready() is in when it calls
	#     bind_rig() — the REAL, non-faked XRSession.bind_rig() succeeds and
	#     the real nodes end up correctly bound. Before the split, this
	#     exact sequence (rig-in-tree, then bind) was IMPOSSIBLE to reach
	#     from the single call site in main.gd, because main.gd runs before
	#     any scene — including one with a rig in it — exists. Proving the
	#     happy path here only means something because case 5 already proved
	#     the premature path is refused.
	VB._reset_for_test()
	var iface11 := FakeInterface.new()
	var real_start := XS.start(self)
	_ok("setup: XRSession.start() fails at find on this host (no real interface)",
		real_start.ok == false and real_start.step == "find")
	# start() failing above means phase 1's guard is still down — arm it
	# directly through VisionOSBoot with a fake interface, the same way
	# case 1-4 do, so bind_rig() below is willing to run at all.
	VB.bring_up(_deps1(iface11, []))
	var origin11 := XROrigin3D.new()
	origin11.name = "TestXROrigin3D"
	origin11.add_to_group("xr_origin")
	var cam11 := XRCamera3D.new()
	cam11.name = "TestXRCamera3D"
	cam11.add_to_group("xr_camera")
	origin11.add_child(cam11)
	root.add_child(origin11)
	# A node added to `root` inside a `-s` script's _initialize()/_main() is
	# not yet actually wired into the live tree — `root.get_tree()` is null
	# until the next process frame (same reason test_costumes.gd awaits
	# twice after adding its PieceAssets shim). get_first_node_in_group()
	# would silently return null here without this, which would make this
	# case pass for the WRONG reason (indistinguishable from case 10's
	# true-negative) instead of proving the real positive path.
	await process_frame
	await process_frame
	var r11 := XS.bind_rig(self)
	_ok("rig-exists-when-called -> bind_rig ok", r11.ok == true)
	_ok("rig-exists-when-called -> step 'done'", r11.step == "done")
	# NOT `origin11.current == true` (2026-08-10 adversarial audit): the engine
	# writes that itself on NOTIFICATION_ENTER_TREE for the first XROrigin3D to
	# enter any live tree (scene/3d/xr/xr_nodes.cpp), so it read true even when
	# VisionOSBoot.bind_rig() was gutted to `_rig_bound = true; return ok`
	# without calling either dep Callable — a green line presented as this
	# case's payoff while proving nothing. The write-back IS the payoff: only a
	# real get_first_node_in_group("xr_origin") plus a real assignment can
	# drive this node to false, and _set_origin_current re-reads the property
	# rather than trusting the write. It is the positive counterpart to case
	# 10's true-negative. Restored to true immediately after, so this case
	# leaves the node exactly as the engine had it.
	var wrote_false := XS._set_origin_current(self, false)
	var read_false := origin11.current == false
	var wrote_true := XS._set_origin_current(self, true)
	_ok("rig-exists-when-called -> the REAL setter round-trips on the live node: false reads back false, true reads back true",
		wrote_false and read_false and wrote_true and origin11.current == true)
	_ok("rig-exists-when-called -> XRCamera3D.near clamped to the floor",
		cam11.near >= VB.MIN_NEAR)
	_ok("rig-exists-when-called -> XRSession now reports immersive",
		XS.is_immersive() == true)
	origin11.remove_child(cam11)
	root.remove_child(origin11)
	cam11.free()
	origin11.free()
	VB._reset_for_test()
	XS._reset_for_test()   # this case is the one that sets _immersive=true; both
	                        # layers' latches must be clear for whatever runs next
	                        # (2026-08-10 review, final gate — XS's own latch was
	                        # not covered by VB._reset_for_test() and stayed stuck)

	# ── THE TWO VALUES NOTHING ELSE IN THIS SUITE NAMES ────────────────────

	# 12. Both of these are single strings/keys that fail ONLY on real
	#     hardware, silently, and both were previously covered by accident or
	#     not at all (2026-08-10 adversarial audit, M6 and M7).
	#
	#     INTERFACE_NAME: reverting it to the old "visionOSXR" typo used to
	#     surface as two array-equality failures in cases 1 and 3 whose labels
	#     ("no viewport touched", "order is find,use_xr") never mention the
	#     interface name at all — a reader of that failure output learns the
	#     wrong thing. The engine registers the interface as "visionOS"
	#     (visionos_xr_interface.mm:64, `const String
	#     VisionOSXRInterface::name = "visionOS";` — the CLASS is
	#     VisionOSXRInterface; the STRING it registers under is not), and
	#     XRServer.find_interface() is an exact string compare, so a drift
	#     here fails step "find" on every single device launch. This assertion
	#     names itself.
	_ok("VisionOSBoot.INTERFACE_NAME is the engine's registered string 'visionOS' (visionos_xr_interface.mm:64), not the class name",
		VB.INTERFACE_NAME == "visionOS")
	#     xr/shaders/enabled: multiview shader variants are compiled ONLY when
	#     this project setting is true (scene_shader_forward_mobile.cpp:625-627
	#     gates enable_multiview_shader_group() on it) and it defaults to FALSE
	#     (rendering_server.cpp:3816). The Mobile renderer this project is
	#     pinned to has no lazy fallback for a missing multiview variant
	#     (render_forward_mobile.cpp:1033-1035), so deleting the key ships a
	#     build that cannot render a stereo frame. The audit deleted it and
	#     BOTH suites stayed 100% green: the only guard was
	#     tools/build/assert_visionos_preset.py, which runs from
	#     tools/build/build.sh — a different gate that run_e2e.sh's Gate A does
	#     not invoke. A dev running the test suite got green on an unshippable
	#     build. `false` is the default passed explicitly here so a DELETED key
	#     is read as false and fails, exactly like an explicitly false one.
	_ok("project.godot keeps xr/shaders/enabled true — the Mobile renderer has no lazy multiview fallback",
		ProjectSettings.get_setting("xr/shaders/enabled", false) == true)

	print("ASSERTIONS=%d" % checks)
	print("=== %s ===" % ("PASS" if failures == 0 else "%d FAILURES" % failures))
	quit(1 if failures > 0 else 0)
