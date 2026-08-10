extends SceneTree

# Task 5b — the minimal XR rig scenes/game.tscn must carry so
# src/xr/xr_session.gd's _set_origin_current/_set_near can ever succeed on
# hardware. Added after a 2026-08-10 review found Task 6's acceptance
# criterion ("turning your head moves the view") unreachable: bring-up now
# correctly REPORTS a missing rig (step "origin"/"near" — see
# test_visionos_boot.gd cases 6/7/10) instead of silently no-oping, but
# nothing in this repo tagged a node into the "xr_origin" / "xr_camera"
# groups those setters look up. The first section below is the other half
# of THAT fix: it proves the SAVED SCENE, not the consumer, carries the rig.
#
# ROUND 1 FOLLOW-UP (2026-08-10 review round 1): the rig above was correct,
# but XR bring-up had only ONE call site — main.gd._ready(), which runs
# BEFORE any scene, including game.tscn, is added — so the "xr_origin"/
# "xr_camera" lookup ran at a point in boot where no rig could possibly
# exist yet, on every single real-hardware launch. The fix split bring-up
# into two phases across two files (see visionos_boot.gd's "ORDERING SCAR"
# doc): PHASE 1 (XRSession.start(), interface only) stays in main.gd; PHASE
# 2 (XRSession.bind_rig(), the rig lookup) moved to game.gd, where the rig
# is actually live by the time it runs. The "CALL-SITE WIRING" section below
# is the assertion that would have caught the original defect, and the one
# that keeps it from coming back: it reads the ACTUAL SOURCE of main.gd and
# game.gd and asserts each calls the phase that belongs to it, and only
# that phase. A `.tscn`-only test — proving the rig itself is correct, as
# the first section does — could never have caught this: the defect was
# WHEN the lookup ran, not what it looked up, and "when" lives in main.gd
# and game.gd, not in the scene file.
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
#                            ship: XRSession.bind_rig() (phase 2) is the ONLY
#                            code path allowed to flip these to true, and it
#                            can only run after a real visionOS interface is
#                            already up (phase 1) AND the rig is in the
#                            tree. A `.tscn` that saved either as current
#                            would steal the viewport on Windows/macOS the
#                            instant the scene loads — no XR interface
#                            required.
#   - THE OLD CAMERA SURVIVES the collateral-damage check. CameraRig/Camera3D
#                            (z=11.5, fov=50) is what test_e2e/'s
#                            screen-geometry and rendered-pixel scenarios
#                            photograph. If adding the rig ever displaced it
#                            — wrong parent, a stray `current = true`, an
#                            accidental deletion — this is the assertion
#                            that says so instead of test_e2e finding out an
#                            hour into a build.
#   - CALL-SITE WIRING        main.gd calls XRSession.start() (phase 1) and
#                            must NEVER call bind_rig() (phase 2) — it runs
#                            before any scene exists, so a rig lookup there
#                            can only ever fail. game.gd calls bind_rig()
#                            and must NEVER call start() — the interface
#                            must already be up by the time a match scene
#                            loads. This is the regression guard for the
#                            EXACT mutation that shipped: moving the rig
#                            lookup back to the early call site, or removing
#                            it from the late one, flips this red without
#                            needing a single real device.
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
const MAIN_SCRIPT := "res://src/main.gd"
const GAME_SCRIPT := "res://src/game.gd"
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


func _read_source(res_path: String) -> String:
	var f := FileAccess.open(res_path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()


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
		_ok("XROrigin3D.current is false in the saved scene — only XRSession.bind_rig() may flip it",
			origin.current == false)

	# THE constraint this task exists to protect: the pre-existing player
	# camera must be untouched, both structurally and as the active one.
	var old_cam: Node = game.get_node_or_null("CameraRig/Camera3D")
	_ok("pre-existing CameraRig/Camera3D still exists", old_cam != null)
	if old_cam != null:
		_ok("CameraRig/Camera3D is still the current camera — the rig did not displace it",
			old_cam.current == true)

	game.free()

	# ── CALL-SITE WIRING — the assertion that would have caught round 1 ──
	# Why a plain SOURCE TEXT check, rather than something that boots the
	# real engine: the round-1 defect was never about what bring_up()/
	# bind_rig() DO when called — VisionOSBoot's own suite covers that
	# exhaustively with fakes — it was about WHICH FILE calls WHICH PHASE.
	# That is a property of main.gd and game.gd's source, not of runtime
	# behaviour reachable from a headless SceneTree script (reproducing
	# main.gd's actual boot sequence here would mean re-driving House
	# Select -> change_scene_to_file, which is exactly the windowed e2e
	# 'boot' scenario's job, not a `-s` unit suite's). Reading the two call
	# sites directly is the cheapest check that is still IMPOSSIBLE to pass
	# by accident: it fails the moment either file calls the wrong phase,
	# which is precisely the shape of the mutation that shipped in round 1
	# (the only call site, main.gd, tried to do both phases at once).
	print("--- call-site wiring ---")
	var main_src := _read_source(MAIN_SCRIPT)
	var game_src := _read_source(GAME_SCRIPT)
	_ok("%s was readable" % MAIN_SCRIPT, not main_src.is_empty())
	_ok("%s was readable" % GAME_SCRIPT, not game_src.is_empty())
	_ok("main.gd calls XRSession.start() — phase 1, before any scene loads",
		main_src.contains("XRSession.start("))
	_ok("main.gd does NOT call XRSession.bind_rig() — the rig cannot exist yet here",
		not main_src.contains("XRSession.bind_rig("))
	_ok("game.gd calls XRSession.bind_rig() — phase 2, once the rig is live",
		game_src.contains("XRSession.bind_rig("))
	_ok("game.gd does NOT call XRSession.start() — phase 1 belongs to main.gd only",
		not game_src.contains("XRSession.start("))

	print("=== %s ===" % ("PASS" if failures == 0 else "%d FAILURES" % failures))
	quit(1 if failures > 0 else 0)
