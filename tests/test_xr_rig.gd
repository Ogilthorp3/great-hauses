extends SceneTree

# Task 5b — the minimal XR rig scenes/game.tscn must carry so
# src/xr/xr_session.gd's _set_origin_current/_set_near can ever succeed on
# hardware. Added after a 2026-08-10 review found Task 6's acceptance
# criterion ("turning your head moves the view") unreachable: bring-up now
# correctly REPORTS a missing rig (step "origin"/"near" — see
# test_visionos_boot.gd cases 5/6/8) instead of silently no-oping, but
# nothing in this repo tagged a node into the "xr_origin" / "xr_camera"
# groups those setters look up. This suite is the other half of that fix:
# it proves the SAVED SCENE, not the consumer, carries the rig.
#
# What is covered, and why each one is here:
#   - THE GROUPS RESOLVE      get_first_node_in_group("xr_origin") /
#                            "xr_camera" must find an XROrigin3D / an
#                            XRCamera3D — the exact lookup xr_session.gd
#                            performs on a real headset. A typo in either
#                            group name fails ONLY on hardware; this is the
#                            desktop-side check that would have caught it.
#   - THE NEAR FLOOR          CompositorServices refuses a nearer plane than
#                            VisionOSBoot.MIN_NEAR (0.1) and visionOSXR fails
#                            the frame outright — there is no workaround, so
#                            the saved scene must already clear it.
#   - NEITHER NODE IS CURRENT the constraint that makes this task safe to
#                            ship: XRSession.start() is the ONLY code path
#                            allowed to flip these to true, and it can only
#                            run after a real visionOS bring-up succeeds.
#                            A `.tscn` that saved either as current would
#                            steal the viewport on Windows/macOS the instant
#                            the scene loads — no XR interface required.
#   - THE OLD CAMERA SURVIVES the collateral-damage check. CameraRig/Camera3D
#                            (z=11.5, fov=50) is what test_e2e/'s
#                            screen-geometry and rendered-pixel scenarios
#                            photograph. If adding the rig ever displaced it
#                            — wrong parent, a stray `current = true`, an
#                            accidental deletion — this is the assertion
#                            that says so instead of test_e2e finding out an
#                            hour into a build.
#
# The scene is instantiated but deliberately NEVER added to the SceneTree:
# game.gd's _ready() wires HUD/banter/Music/network state that assumes the
# real boot path (main.tscn -> autoloads -> change_scene_to_file), none of
# which this task touches or needs to prove. A node's groups are recorded on
# the Node itself the instant it is instantiated — Node.is_in_group() does
# not require SceneTree membership — so a plain recursive walk proves
# exactly what get_first_node_in_group() would on a live tree, without
# booting the whole game (and its autoload-dependent _ready() chain) headless.
#
# Run: /Users/bert/Projects/godot-visionos/bin/godot.macos.editor.arm64 \
#        --headless --path . -s res://tests/test_xr_rig.gd
# Exit code 0 = all green, 1 = failures.

const GAME_SCENE := "res://scenes/game.tscn"
const VisionOSBootScript := preload("res://src/xr/visionos_boot.gd")

var failures := 0


func _initialize() -> void:
	_main()


func _ok(label: String, cond: bool) -> void:
	if cond:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s" % label)
		failures += 1


## Mirrors SceneTree.get_first_node_in_group() without requiring the node to
## be inside a live SceneTree — see the header note above on why this suite
## never adds the instantiated scene to one.
func _first_in_group(n: Node, group: String) -> Node:
	if n.is_in_group(group):
		return n
	for child in n.get_children():
		var found := _first_in_group(child, group)
		if found != null:
			return found
	return null


func _main() -> void:
	print("=== XR rig: scenes/game.tscn ===")
	var packed: PackedScene = load(GAME_SCENE)
	var game: Node = packed.instantiate()

	var origin := _first_in_group(game, "xr_origin")
	_ok("'xr_origin' group resolves to a node", origin != null)
	_ok("'xr_origin' node is an XROrigin3D", origin is XROrigin3D)

	var cam := _first_in_group(game, "xr_camera")
	_ok("'xr_camera' group resolves to a node", cam != null)
	_ok("'xr_camera' node is an XRCamera3D", cam is XRCamera3D)

	if cam is XRCamera3D:
		_ok("XRCamera3D.near >= VisionOSBoot.MIN_NEAR (%.2f)" % VisionOSBootScript.MIN_NEAR,
			cam.near >= VisionOSBootScript.MIN_NEAR)
		_ok("XRCamera3D.current is false in the saved scene — desktop stays on CameraRig",
			cam.current == false)

	if origin is XROrigin3D:
		_ok("XROrigin3D.current is false in the saved scene — only XRSession.start() may flip it",
			origin.current == false)

	# THE constraint this task exists to protect: the pre-existing player
	# camera must be untouched, both structurally and as the active one.
	var old_cam: Node = game.get_node_or_null("CameraRig/Camera3D")
	_ok("pre-existing CameraRig/Camera3D still exists", old_cam != null)
	if old_cam != null:
		_ok("CameraRig/Camera3D is still the current camera — the rig did not displace it",
			old_cam.current == true)

	game.free()
	print("=== %s ===" % ("PASS" if failures == 0 else "%d FAILURES" % failures))
	quit(1 if failures > 0 else 0)
