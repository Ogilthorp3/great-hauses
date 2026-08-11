class_name VisionOSBoot
extends RefCounted
## The visionOS immersive XR bring-up, split into two phases with two
## different call sites (2026-08-10 review round 1 — see ORDERING SCAR
## below for why one phase was never enough).
##
## PHASE 1 — bring_up(): find_interface -> initialize -> use_xr. Called from
## src/main.gd._ready(), BEFORE any scene is added — the immersive space
## genuinely needs the interface up before any content exists to render
## into it.
##
## PHASE 2 — bind_rig(): resolve "xr_origin"/"xr_camera" and make the origin
## current / clamp the near plane. Called from src/game.gd._ready(), once
## game.tscn — and the rig it carries — is actually in the tree. bind_rig()
## REQUIRES phase 1 to have already reached "done"; called before that, it
## fails fast at step "not_active" instead of attempting the lookups (and
## therefore instead of failing at "origin" for a rig that was never given a
## chance to exist).
##
## Every one of these calls fails SILENTLY if skipped — a missing use_xr
## renders a flat mono view into the headset, a missing XROrigin3D.current
## renders from the world origin. So both phases are their own tiny state
## machine that reports WHICH step failed, and their side effects are
## Callables so the headless suite on macOS (where no visionOS interface
## exists) can drive them with fakes.
##
## set_origin_current and set_near are NOT fire-and-forget: each returns a
## bool, and bind_rig() treats a false return as a bind failure at step
## "origin" / "near" respectively — a build with no node in the "xr_origin" /
## "xr_camera" group must be REPORTED, not silently accepted as "done". Each
## phase's once-only guard latches ONLY on that phase's own genuine success,
## so a failure at "origin" or "near" leaves the NEXT bind_rig() free to run
## for real again (e.g. once the rig actually exists in the scene), rather
## than permanently latching a session that never truly bound.
##
## ORDERING SCAR (2026-08-10 review round 1, the finding that split this
## file in two): before this split there was ONE bring_up(), doing all four
## steps, with ONE call site — main.gd._ready(), which runs BEFORE any scene
## (including game.tscn, where the rig lives) is added. "xr_origin" and
## "xr_camera" therefore could not possibly resolve at that call: the lookup
## ran at a point in boot where the rig it was looking for did not exist
## yet, no matter how correctly scenes/game.tscn tagged it. Every real-
## hardware launch failed at step "origin", on EVERY SINGLE LAUNCH, with a
## completely correct rig sitting unused in the very next scene to load. A
## `.tscn`-only test could not have caught this — nothing was wrong with
## what the lookup looked for, only WHEN it ran. See test_xr_rig.gd's
## "CALL-SITE WIRING" section for the assertion that now guards it.
##
## Scar (2026-08-10 review, 6th silent-green on this plan, BEFORE the split
## above): set_origin_current/set_near were `-> void`. On a real device with
## no "xr_origin"/"xr_camera" group tagged (the rig was deferred to a later
## plan), find/initialize/use_xr all succeeded, the two setters silently
## no-op'd on a null node, bring_up() still latched `_up = true` and returned
## {ok: true, step: "done"}, and is_immersive() reported true — nothing in
## the return value or the logs said the origin was never made current or
## the near plane never verified.

## Scar (2026-08-10 review, final gate): this was "visionOSXR". The engine
## registers the interface as "visionOS" — visionos_xr_interface.mm:64,
## `const String VisionOSXRInterface::name = "visionOS";` (the CLASS is
## VisionOSXRInterface; the STRING it registers under is not). XRServer's
## lookup is an exact string compare, so the old value failed step "find" on
## every single real-device launch — the interface was always there, this
## file was just asking for it by the wrong name. `grep -rn "visionOSXR"`
## over the engine repo returns zero hits; it was never a real name anywhere
## but here. See the "find" branch below for the diagnostic that now fires
## if this ever drifts from the engine's registered name again.
const INTERFACE_NAME := "visionOS"

## CompositorServices refuses a nearer plane; visionos_xr_interface.mm
## validates it and fails the frame. There is no workaround.
const MIN_NEAR := 0.1

## PHASE 1's once-only guard. A second bring_up() on an interface that is
## already up short-circuits before touching find_interface/initialize
## again — real hardware documents a second initialize() as re-negotiating
## the compositor session, which is exactly the kind of thing that shows up
## as a dropped frame or a visible hitch mid-game, not as a clean error this
## state machine could report.
static var _interface_up := false

## PHASE 2's once-only guard. Deliberately SEPARATE from _interface_up: a
## rig that fails to bind (missing "xr_origin"/"xr_camera" group) must not
## be confused with an interface that never came up, and a later, genuine
## bind_rig() — once the rig actually lands in the tree — must still be free
## to run even though phase 1 already latched long before it.
static var _rig_bound := false

## The step the LAST bring_up() call returned at ("" = phase 1 has not been
## attempted since boot / since the last reset). Two reasons it exists:
##
## 1. DIAGNOSTIC. main.gd only push_error()s the failure step on visionOS;
##    anything that wants to ask "did phase 1 ever run on this host, and what
##    did it conclude?" after the fact — a crash reporter, a HUD, a support
##    dump — has no other way to find out, because a failed bring_up()
##    deliberately changes no other state.
##
## 2. OBSERVABILITY OF THE CALL SITE. On every non-visionOS host phase 1 fails
##    at "find" (XRServer has no interface by that name), and a failure leaves
##    _interface_up false — i.e. bring_up() running and bring_up() never being
##    called are, without this, indistinguishable from the outside. That made
##    src/main.gd's phase-1 call site unprovable: a test could only check that
##    the file CONTAINED the call, never that _ready() actually ran it (a
##    2026-08-10 adversarial audit moved `XRSession.start(get_tree())` into a
##    never-called function and every suite stayed green). This latch is the
##    trace that makes the real thing observable — see tests/test_xr_rig.gd's
##    "call-site wiring: behavioural (main.gd)" section, which mounts the real
##    main.tscn and asserts this reads "find" afterwards.
static var _last_bring_up_step := ""

## Static, not per-instance: both bring_up() and bind_rig() are called as
## static funcs with no object of their own to hold state on, and the guards
## have to survive across unrelated callers within the same run (e.g. a
## scene re-entering its ready path), not just across calls on one instance.
##
## _reset_for_test() exists because a process-wide latch is exactly the kind
## of hidden state a test suite must be able to clear between cases — an
## unresettable one would make every case after the first success run
## against an already-'up'/'bound' session and silently stop testing
## anything.
static func _reset_for_test() -> void:
	_interface_up = false
	_rig_bound = false
	_last_bring_up_step = ""


## PHASE 1 — see the class doc. deps: {find_interface, set_use_xr}.
## Deliberately takes no origin/near dependency at all: this phase cannot
## attempt a rig lookup even by mistake, because nothing here is given the
## means to perform one.
static func bring_up(deps: Dictionary) -> Dictionary:
	# Every return below records its step in _last_bring_up_step first (see
	# that var's doc): it is the ONLY trace this phase leaves on a host where
	# it fails, and therefore the only way anything outside can tell "phase 1
	# ran and failed at find" from "phase 1 was never called at all".
	if _interface_up:
		_last_bring_up_step = "done"
		return {"ok": true, "step": "done", "error": ""}

	_last_bring_up_step = "find"
	var iface = deps["find_interface"].call(INTERFACE_NAME)
	if iface == null:
		# A wrong INTERFACE_NAME must not look like "no device" — it looks
		# EXACTLY like a missing headset otherwise, which is what let the
		# "visionOSXR" typo above survive every review until now. On an
		# actual visionOS build, print every interface XRServer DOES know
		# about, so the next name mismatch names itself instead of hiding
		# behind this same generic message.
		if OS.get_name() == "visionOS":
			var available: Array[String] = []
			for entry in XRServer.get_interfaces():
				available.append(str((entry as Dictionary).get("name", "?")))
			push_error("visionOS XR bring-up: no XRInterface named '%s'. XRServer.get_interfaces() reports: %s" \
				% [INTERFACE_NAME, ", ".join(available) if not available.is_empty() else "<none>"])
		return {"ok": false, "step": "find",
			"error": "no XRInterface named '%s' — is this a visionOS build?" % INTERFACE_NAME}

	# The interface does NOT auto-initialize.
	_last_bring_up_step = "initialize"
	if not iface.initialize():
		return {"ok": false, "step": "initialize",
			"error": "XRInterface.initialize() returned false"}

	deps["set_use_xr"].call(true)
	_interface_up = true
	_last_bring_up_step = "done"
	return {"ok": true, "step": "done", "error": ""}


## PHASE 2 — see the class doc. deps: {set_origin_current, set_near}. Fails
## fast at step "not_active" if PHASE 1 never reached "done": bind_rig() must
## never attempt the setters on a host (or a still-booting visionOS launch)
## where the interface itself is not up, and it must SAY SO rather than
## silently returning ok on a call that did nothing — the same discipline
## the 6th-silent-green scar above forced onto "origin"/"near", now applied
## to the phase boundary itself.
static func bind_rig(deps: Dictionary) -> Dictionary:
	if not _interface_up:
		return {"ok": false, "step": "not_active",
			"error": "XR interface is not up — bring_up() must succeed before bind_rig() runs"}

	if _rig_bound:
		return {"ok": true, "step": "done", "error": ""}

	if not deps["set_origin_current"].call(true):
		return {"ok": false, "step": "origin",
			"error": "no node made current in the 'xr_origin' group — is an XROrigin3D tagged?"}

	if not deps["set_near"].call(MIN_NEAR):
		return {"ok": false, "step": "near",
			"error": "near plane not verified >= %.2f m — is an XRCamera3D tagged 'xr_camera'?" % MIN_NEAR}

	_rig_bound = true
	return {"ok": true, "step": "done", "error": ""}
