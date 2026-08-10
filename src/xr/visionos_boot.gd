class_name VisionOSBoot
extends RefCounted
## The four calls that stand up the visionOS immersive XR interface.
##
## Every one of them fails SILENTLY if skipped — a missing use_xr renders a
## flat mono view into the headset, a missing XROrigin3D.current renders from
## the world origin. So bring-up is a state machine that reports WHICH step
## failed, and its side effects are Callables so the headless suite on macOS
## (where no visionOS interface exists) can drive it with fakes.

const INTERFACE_NAME := "visionOSXR"

## CompositorServices refuses a nearer plane; visionos_xr_interface.mm
## validates it and fails the frame. There is no workaround.
const MIN_NEAR := 0.1


static func bring_up(deps: Dictionary) -> Dictionary:
	var iface = deps["find_interface"].call(INTERFACE_NAME)
	if iface == null:
		return {"ok": false, "step": "find",
			"error": "no XRInterface named '%s' — is this a visionOS build?" % INTERFACE_NAME}

	# The interface does NOT auto-initialize.
	if not iface.initialize():
		return {"ok": false, "step": "initialize",
			"error": "XRInterface.initialize() returned false"}

	deps["set_use_xr"].call(true)
	deps["set_origin_current"].call(true)
	deps["set_near"].call(MIN_NEAR)
	return {"ok": true, "step": "done", "error": ""}
