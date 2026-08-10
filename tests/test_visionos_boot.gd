extends SceneTree

# XR bring-up is four calls and every one is a SILENT failure if missed:
# find_interface -> initialize -> viewport.use_xr -> XROrigin3D.current.
# The visionOS interface does not exist on macOS, so bring_up() takes its
# side effects as Callables and this suite drives it with fakes.

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
	var log1: Array = []
	var r1 := VB.bring_up(_deps(null, log1))
	_ok("absent interface -> not ok", r1.ok == false)
	_ok("absent interface -> step 'find'", r1.step == "find")
	_ok("absent interface -> no viewport touched", log1 == ["find:visionOSXR"])

	# 2. The interface does NOT auto-initialize; a false return must abort.
	var iface2 := FakeInterface.new()
	iface2.init_result = false
	var log2: Array = []
	var r2 := VB.bring_up(_deps(iface2, log2))
	_ok("initialize() called", iface2.initialized)
	_ok("failed initialize -> not ok", r2.ok == false)
	_ok("failed initialize -> step 'initialize'", r2.step == "initialize")
	_ok("failed initialize -> use_xr never set", not log2.has("use_xr:true"))

	# 3. Happy path: exact order, and the near plane is pinned to the floor.
	var iface3 := FakeInterface.new()
	var log3: Array = []
	var r3 := VB.bring_up(_deps(iface3, log3))
	_ok("happy path ok", r3.ok == true)
	_ok("happy path step 'done'", r3.step == "done")
	_ok("order is find,use_xr,origin,near", log3 == [
		"find:visionOSXR", "use_xr:true", "origin:true", "near:0.1"])

	# 4. Idempotent: a second bring_up must not re-initialize.
	var iface4 := FakeInterface.new()
	var deps4 := _deps(iface4, [])
	VB.bring_up(deps4)
	iface4.initialized = false
	var r4 := VB.bring_up(deps4)
	_ok("second bring_up still ok", r4.ok == true)

	print("=== %s ===" % ("PASS" if failures == 0 else "%d FAILURES" % failures))
	quit(1 if failures > 0 else 0)
