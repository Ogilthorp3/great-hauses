class_name XRSession
extends RefCounted
## Live wiring for VisionOSBoot. Everything testable lives in visionos_boot.gd;
## this file exists only to bind the four Callables to the real servers, so it
## stays small enough to read in one screen.
##
## The dict literal below binds each Callable to a single-statement lambda.
## The origin/camera setters need an `if node != null` guard, which does not
## fit inside a Dictionary literal as a multi-statement lambda — GDScript
## lambdas embedded in a literal must be one statement each, and a trailing
## comma after a block is not valid syntax. So the guarded bodies live in
## named private static helpers below, and the lambdas just call them. Same
## behaviour as a single inline lambda, just parseable.

const VisionOSBootScript := preload("res://src/xr/visionos_boot.gd")

static var _immersive := false


static func is_immersive() -> bool:
	return _immersive


static func _set_origin_current(tree: SceneTree, v: bool) -> void:
	var origin := tree.get_first_node_in_group("xr_origin")
	if origin != null:
		origin.current = v


static func _set_near(tree: SceneTree, v: float) -> void:
	var cam := tree.get_first_node_in_group("xr_camera")
	if cam != null:
		cam.near = maxf(cam.near, v)


static func start(tree: SceneTree) -> Dictionary:
	var viewport := tree.root
	var result: Dictionary = VisionOSBootScript.bring_up({
		"find_interface": func(n: String): return XRServer.find_interface(n),
		"set_use_xr": func(v: bool) -> void: viewport.use_xr = v,
		"set_origin_current": func(v: bool) -> void: _set_origin_current(tree, v),
		"set_near": func(v: float) -> void: _set_near(tree, v),
	})
	_immersive = result.ok
	return result
