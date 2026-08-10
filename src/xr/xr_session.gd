class_name XRSession
extends RefCounted
## Live wiring for VisionOSBoot. Everything testable lives in visionos_boot.gd;
## this file exists only to bind the Callables to the real servers, so it
## stays small enough to read in one screen.
##
## TWO PHASES, TWO CALL SITES (2026-08-10 review round 1 — the ordering
## defect that made Task 6 unreachable). start() must run BEFORE any scene is
## added (src/main.gd._ready() — the interface has to exist before content
## does), which means "xr_origin"/"xr_camera" cannot possibly be in the tree
## at that call: game.tscn has not loaded. The old single-phase start() tried
## the rig lookup anyway and failed at step "origin" on EVERY launch — a
## completely correct rig sitting unused one scene-load away. bind_rig() is
## the second call, made from src/game.gd._ready() once game.tscn — and the
## rig it carries — is actually live. See visionos_boot.gd's class doc for
## the full ORDERING SCAR writeup and test_xr_rig.gd's "CALL-SITE WIRING"
## section for the assertion that now guards this from recurring.
##
## The dict literals below bind each Callable to a single-statement lambda.
## The origin/camera setters need an `if node != null` guard, which does not
## fit inside a Dictionary literal as a multi-statement lambda — GDScript
## lambdas embedded in a literal must be one statement each, and a trailing
## comma after a block is not valid syntax. So the guarded bodies live in
## named private static helpers below, and the lambdas just call them. Same
## behaviour as a single inline lambda, just parseable.

const VisionOSBootScript := preload("res://src/xr/visionos_boot.gd")

static var _immersive := false


## TEST-ONLY, mirrors VisionOSBoot._reset_for_test() at this layer.
## _immersive is XRSession's OWN static latch (set by bind_rig() below), not
## one of VisionOSBoot's two guards — resetting only the base layer left this
## stuck at whatever the last bind_rig() reported (2026-08-10 review, final
## gate). A suite that mounts the real rig more than once in one process
## (see tests/test_xr_rig.gd's behavioural call-site check) needs both
## layers clearable independently, so this is a separate function rather
## than folded into VisionOSBoot's — that module has, and must keep, no
## knowledge that XRSession exists.
static func _reset_for_test() -> void:
	_immersive = false


## True only once BOTH phases have completed: the interface is up AND the
## rig (xr_origin/xr_camera) is bound. Phase 1 alone — interface found and
## initialized, but the rig not yet in the tree — is deliberately NOT
## "immersive": nothing is tracking the headset's pose until bind_rig() also
## succeeds, and reporting true before that would be exactly the kind of
## silent overclaim this module exists to prevent.
static func is_immersive() -> bool:
	return _immersive


## Returns false (and warns) when the rig isn't in the scene — VisionOSBoot
## treats that as a bind failure at step "origin", not a silent no-op.
## Reads `current` back after the assignment rather than trusting the
## assignment succeeded (2026-08-10 review, final gate) — cheap, and it is
## the one line standing between "the origin is actually current" and "we
## asked it to be": Node.current has other ways to end up false (a second
## XROrigin3D taking it back the same frame, for instance) that a bare
## `return true` would never notice.
static func _set_origin_current(tree: SceneTree, v: bool) -> bool:
	var origin := tree.get_first_node_in_group("xr_origin")
	if origin == null:
		push_warning("XRSession: no node in the 'xr_origin' group — XR origin was never made current")
		return false
	origin.current = v
	return origin.current == v


## Returns false (and warns) when the rig isn't in the scene — VisionOSBoot
## treats that as a bind failure at step "near", not a silent no-op.
## Reads `near` back after the clamp rather than trusting `maxf` did what it
## looks like it did (2026-08-10 review, final gate) — same discipline as
## _set_origin_current above.
static func _set_near(tree: SceneTree, v: float) -> bool:
	var cam := tree.get_first_node_in_group("xr_camera")
	if cam == null:
		push_warning("XRSession: no node in the 'xr_camera' group — near plane was never verified")
		return false
	cam.near = maxf(cam.near, v)
	return cam.near >= v


## PHASE 1 — call from src/main.gd._ready(), BEFORE any scene is added.
## Finds and initializes the visionOS XRInterface and turns on use_xr. Does
## NOT touch xr_origin/xr_camera — the rig cannot exist yet at this point in
## boot (game.tscn has not loaded). See bind_rig() for phase 2.
static func start(tree: SceneTree) -> Dictionary:
	var viewport := tree.root
	return VisionOSBootScript.bring_up({
		"find_interface": func(n: String): return XRServer.find_interface(n),
		"set_use_xr": func(v: bool) -> void: viewport.use_xr = v,
	})


## PHASE 2 — call from src/game.gd._ready(), once game.tscn (and its rig) is
## actually in the tree. Requires start() to have already succeeded; on a
## host where it has not (e.g. desktop, or a visionOS launch where phase 1
## itself failed), this is a clean, REPORTED no-op ({ok: false,
## step: "not_active"}) — never a silent one, never a crash.
static func bind_rig(tree: SceneTree) -> Dictionary:
	var result: Dictionary = VisionOSBootScript.bind_rig({
		"set_origin_current": func(v: bool) -> bool: return _set_origin_current(tree, v),
		"set_near": func(v: float) -> bool: return _set_near(tree, v),
	})
	_immersive = result.ok
	return result
