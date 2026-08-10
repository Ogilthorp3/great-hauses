class_name VisionOSBoot
extends RefCounted
## The four calls that stand up the visionOS immersive XR interface.
##
## Every one of them fails SILENTLY if skipped — a missing use_xr renders a
## flat mono view into the headset, a missing XROrigin3D.current renders from
## the world origin. So bring-up is a state machine that reports WHICH step
## failed, and its side effects are Callables so the headless suite on macOS
## (where no visionOS interface exists) can drive it with fakes.
##
## set_origin_current and set_near are NOT fire-and-forget: each returns a
## bool, and bring_up() treats a false return as a bring-up failure at step
## "origin" / "near" respectively — a build with no node in the "xr_origin" /
## "xr_camera" group must be REPORTED, not silently accepted as "done". The
## once-only guard latches ONLY on a genuinely complete bring-up, so a
## failure at "origin" or "near" leaves the NEXT bring_up() free to run for
## real again (e.g. once the rig actually exists in the scene), rather than
## permanently latching a session that never truly came up.
##
## Scar (2026-08-10 review, 6th silent-green on this plan): before this,
## set_origin_current/set_near were `-> void`. On a real device with no
## "xr_origin"/"xr_camera" group tagged (the rig was deferred to a later
## plan), find/initialize/use_xr all succeeded, the two setters silently
## no-op'd on a null node, bring_up() still latched `_up = true` and returned
## {ok: true, step: "done"}, and is_immersive() reported true — nothing in
## the return value or the logs said the origin was never made current or
## the near plane never verified.

const INTERFACE_NAME := "visionOSXR"

## CompositorServices refuses a nearer plane; visionos_xr_interface.mm
## validates it and fails the frame. There is no workaround.
const MIN_NEAR := 0.1

## ONCE-ONLY GUARD. Nothing in the visionOS XRInterface contract promises a
## second initialize() is a no-op — on real hardware it is documented to
## re-negotiate the compositor session, which is exactly the kind of thing
## that shows up as a dropped frame or a visible hitch mid-game, not as a
## clean error this state machine could report. So a session that is already
## up must short-circuit BEFORE find/initialize and before the three
## setters, on nothing riskier than "did we already succeed once" — the
## cheapest and safest reading of "once-only" there is.
##
## Static, not per-instance: bring_up() is called as a static func with no
## object of its own to hold state on, and the guard has to survive across
## unrelated callers within the same run (e.g. a scene re-entering its ready
## path), not just across calls on one instance.
##
## _reset_for_test() exists because a process-wide latch is exactly the kind
## of hidden state a test suite must be able to clear between cases — an
## unresettable one would make every case after the first success run
## against an already-'up' session and silently stop testing anything.
static var _up := false


static func _reset_for_test() -> void:
	_up = false


static func bring_up(deps: Dictionary) -> Dictionary:
	if _up:
		return {"ok": true, "step": "done", "error": ""}

	var iface = deps["find_interface"].call(INTERFACE_NAME)
	if iface == null:
		return {"ok": false, "step": "find",
			"error": "no XRInterface named '%s' — is this a visionOS build?" % INTERFACE_NAME}

	# The interface does NOT auto-initialize.
	if not iface.initialize():
		return {"ok": false, "step": "initialize",
			"error": "XRInterface.initialize() returned false"}

	deps["set_use_xr"].call(true)

	if not deps["set_origin_current"].call(true):
		return {"ok": false, "step": "origin",
			"error": "no node made current in the 'xr_origin' group — is an XROrigin3D tagged?"}

	if not deps["set_near"].call(MIN_NEAR):
		return {"ok": false, "step": "near",
			"error": "near plane not verified >= %.2f m — is an XRCamera3D tagged 'xr_camera'?" % MIN_NEAR}

	_up = true
	return {"ok": true, "step": "done", "error": ""}
