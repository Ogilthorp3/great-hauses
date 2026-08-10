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
#   - THE SAVED SCENE CARRIES NEITHER NODE AS CURRENT what the .tscn file
#                            itself holds, checked on a freshly instantiated,
#                            NOT-yet-tree-mounted copy — informational, not a
#                            runtime safety guarantee (see the correction
#                            below for the guarantee that actually holds).
#
#                            SCAR (2026-08-10 review, final gate): this used
#                            to claim "XRSession.bind_rig() is the ONLY code
#                            path allowed to flip these to true" — false at
#                            runtime. scene/3d/xr/xr_nodes.cpp:806-821
#                            (NOTIFICATION_ENTER_TREE) forces `current = true`
#                            on the FIRST XROrigin3D that ever enters ANY
#                            live tree, unconditionally — before bind_rig()
#                            gets a chance to run, and whether or not it ever
#                            succeeds. Measured: pre-tree origin.current is
#                            false (the saved value, checked below); the
#                            instant the SAME node is tree-mounted (the
#                            BEHAVIOURAL call-site section further down does
#                            exactly this with the real scene), it is true —
#                            an engine default, not a plan invariant this
#                            suite can enforce or bind_rig() can prevent.
#
#                            The guarantee that DOES hold, and is what
#                            actually keeps this task safe to ship on
#                            Windows/macOS: XRCamera3D (a Camera3D subclass)
#                            never becomes the VIEWPORT's active camera,
#                            because CameraRig/Camera3D already claims that
#                            slot before XRCamera3D is ever added — by scene
#                            order (camera_3d.cpp's own "first Camera3D in
#                            this Viewport wins" rule) AND by explicitly
#                            saving `current = true` on CameraRig/Camera3D,
#                            belt and braces. XROrigin3D.current flipping
#                            true is therefore harmless: it governs which
#                            origin XR pose tracking is applied against, not
#                            which Camera3D the flat viewport renders
#                            through. The BEHAVIOURAL section proves THIS
#                            claim, on the real tree-mounted scene, in both
#                            directions: XRCamera3D.current stays false AND
#                            CameraRig/Camera3D.current stays true.
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
#                            loads.
#
#                            SCAR (2026-08-10 review, final gate): this used
#                            to be ONLY a raw String.contains() over the two
#                            files' text, and it was NOT a regression guard —
#                            it was mutation-proven to pass, exit 0, against
#                            game.gd's real bind_rig() call commented out and
#                            replaced with a hardcoded {"ok": true, ...}: the
#                            substring "XRSession.bind_rig(" was still sitting
#                            right there in the comment, and a raw text search
#                            cannot tell a live call from a dead one. Two
#                            fixes below, in order of how much they're
#                            trusted: the text check now strips comments
#                            first (closes that exact hole, still fast, still
#                            no engine boot required) — but the assertion
#                            that actually earns the name "regression guard"
#                            is the BEHAVIOURAL one after it, which mounts the
#                            real game.tscn into a real live tree and reads
#                            XRSession's own state back. That one cannot be
#                            fooled by anything sitting in a comment, a dead
#                            branch, or a hardcoded return, because it never
#                            looks at source text at all — only at whether
#                            the rig actually ended up bound.
#
# The scene in the FIRST section below is instantiated but deliberately
# NEVER added to the SceneTree: game.gd's _ready() wires HUD/banter/Music/
# network state that assumes the real boot path (main.tscn -> autoloads ->
# change_scene_to_file), none of which that section touches or needs to
# prove. A node's groups are recorded on the Node itself the instant it is
# instantiated — Node.is_in_group() does not require SceneTree membership —
# so a plain recursive walk proves exactly what get_first_node_in_group()
# would on a live tree, without booting the whole game headless. The
# BEHAVIOURAL call-site section further down is the one exception: it
# mounts a SEPARATE instance of game.tscn for real, specifically because
# proving the real call site requires the real _ready() to actually run —
# see that section's own header for why this is safe with Session
# unconfigured (the same fallback path --smoke/--dump-tree/direct-launch
# probes already rely on).
#
# Run: /Users/bert/Projects/godot-visionos/bin/godot.macos.editor.arm64 \
#        --headless --path . -s res://tests/test_xr_rig.gd
# Exit code 0 = all green, 1 = failures.

const GAME_SCENE := "res://scenes/game.tscn"
const MAIN_SCRIPT := "res://src/main.gd"
const GAME_SCRIPT := "res://src/game.gd"
const VisionOSBootScript := preload("res://src/xr/visionos_boot.gd")
const XRSessionScript := preload("res://src/xr/xr_session.gd")

var failures := 0


## A fake XRInterface, identical in spirit to test_visionos_boot.gd's — this
## suite needs its own copy because it does not preload that suite's file
## (each `-s` suite here is meant to be readable standalone). Only used to
## arm VisionOSBoot's phase-1 guard directly, the same way main.gd's real
## XRSession.start() would on a build where a genuine visionOS interface
## answers — see the BEHAVIOURAL call-site section below for why this suite
## needs phase 1 up before it can prove anything about phase 2.
class FakeInterface extends RefCounted:
	func initialize() -> bool:
		return true


## Strips GDScript line comments before a source-text match, so a call sitting
## in a comment (dead, unreachable) can never satisfy an assertion that is
## supposed to prove the call is LIVE. Neither main.gd nor game.gd puts a "#"
## inside a string literal (checked by hand at the time this was written), so
## a plain per-line split is sufficient — no need for a full tokenizer here.
func _strip_comments(src: String) -> String:
	var out: Array[String] = []
	for line in src.split("\n"):
		var hash_at := line.find("#")
		out.append(line if hash_at == -1 else line.substr(0, hash_at))
	return "\n".join(out)


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
		# Pre-tree ONLY — this reads the SAVED FILE's value, not a runtime
		# guarantee. The engine itself forces this true the instant any
		# XROrigin3D enters a live tree (see the header SCAR note); the
		# BEHAVIOURAL section below proves the property that actually holds
		# at runtime (CameraRig/Camera3D, not XROrigin3D.current, is what
		# desktop safety depends on).
		_ok("XROrigin3D.current is false in the SAVED SCENE FILE (pre-tree only)",
			origin.current == false)

	# THE constraint this task exists to protect: the pre-existing player
	# camera must be untouched, both structurally and as the active one.
	var old_cam: Node = game.get_node_or_null("CameraRig/Camera3D")
	_ok("pre-existing CameraRig/Camera3D still exists", old_cam != null)
	if old_cam != null:
		_ok("CameraRig/Camera3D is still the current camera — the rig did not displace it",
			old_cam.current == true)

	game.free()

	# ── CALL-SITE WIRING, TEXTUAL — cheap, comment-stripped, still gameable ──
	# Reading the two call sites directly is the cheapest check there is, and
	# it still catches a mutation that DELETES a call outright. What it
	# cannot catch on its own is a call sitting dead in a comment (see the
	# SCAR note at the top of this file) — so this strips comments first, and
	# treats this section as a fast pre-check, not the proof. The proof is
	# the behavioural section below.
	print("--- call-site wiring: textual (comment-stripped) ---")
	var main_src := _read_source(MAIN_SCRIPT)
	var game_src := _read_source(GAME_SCRIPT)
	_ok("%s was readable" % MAIN_SCRIPT, not main_src.is_empty())
	_ok("%s was readable" % GAME_SCRIPT, not game_src.is_empty())
	var main_live := _strip_comments(main_src)
	var game_live := _strip_comments(game_src)
	_ok("main.gd calls XRSession.start() in live code — phase 1, before any scene loads",
		main_live.contains("XRSession.start("))
	_ok("main.gd does NOT call XRSession.bind_rig() in live code — the rig cannot exist yet here",
		not main_live.contains("XRSession.bind_rig("))
	_ok("game.gd calls XRSession.bind_rig() in live code — phase 2, once the rig is live",
		game_live.contains("XRSession.bind_rig("))
	_ok("game.gd does NOT call XRSession.start() in live code — phase 1 belongs to main.gd only",
		not game_live.contains("XRSession.start("))

	# ── CALL-SITE WIRING, BEHAVIOURAL — the actual regression guard ─────────
	# This is what the textual section above cannot be: proof the call
	# RUNS, not that its name appears somewhere in the file. It reproduces
	# game.gd's own real boot precondition (phase 1 already up — exactly
	# what main.gd's real XRSession.start() would have left behind on a
	# genuine visionOS launch by the time game.tscn loads) and then mounts
	# the ACTUAL scenes/game.tscn resource into the ACTUAL live tree, exactly
	# as change_scene_to_file(GAME_SCENE) does on every real launch. Session
	# is unconfigured here (as it is for --smoke/--dump-tree/direct probes),
	# so game.gd's _ready() takes the legacy-skin fallback throughout:
	# _resolve_identity/_dress_hall/_setup_banter/_setup_network all return
	# immediately on Session.configured == false, and no AI/oracle move fires
	# from the standard-start position with White to move — nothing here
	# reaches network, HTTP, or a spawned engine process. What DOES run
	# unconditionally, every launch, is the one line under test:
	# `XRSession.bind_rig(get_tree())` inside game.gd's _ready(). If that
	# line never executes — commented out, deleted, hardcoded around, moved
	# to the wrong file — nothing else in this block can make XRSession
	# report immersive or flip this scene's OWN rig nodes, because
	# _immersive and Node.current are not this test's to set; only the real
	# call site can move them.
	print("--- call-site wiring: behavioural ---")
	VisionOSBootScript._reset_for_test()
	XRSessionScript._reset_for_test()
	var arm_result: Dictionary = VisionOSBootScript.bring_up({
		"find_interface": func(_n: String): return FakeInterface.new(),
		"set_use_xr": func(_v: bool) -> void: pass,
	})
	_ok("setup: phase 1 armed (VisionOSBoot._interface_up) before mounting game.tscn",
		arm_result.ok == true and arm_result.step == "done")
	var wiring_packed: PackedScene = load(GAME_SCENE)
	var wiring_game: Node = wiring_packed.instantiate()
	root.add_child(wiring_game)
	# Children ready before parent, but a node added to `root` inside a `-s`
	# script's _main() is not actually wired into the live tree until the
	# next process frame — same reason test_visionos_boot.gd's case 11 awaits
	# twice before trusting get_first_node_in_group() to see what it added.
	await process_frame
	await process_frame
	_ok("game.tscn, mounted for real, ran its own _ready()", wiring_game.is_inside_tree())
	# THE load-bearing assertion. is_immersive() is set ONLY inside
	# XRSession.bind_rig() itself (`_immersive = result.ok`) — nothing else
	# in this test or in the engine can move it. Mutation-verified
	# (2026-08-10 review, final gate): commenting out game.gd's real
	# bind_rig() call and hardcoding a success dict in its place leaves
	# THIS assertion, and only this one among the four below, red.
	_ok("real call site bound the rig: XRSession.is_immersive() is true",
		XRSessionScript.is_immersive() == true)
	var wiring_origin := _first_in_group(wiring_game, "xr_origin")
	var wiring_cam := _first_in_group(wiring_game, "xr_camera")
	# Corroborating, NOT independently diagnostic (2026-08-10 review, final
	# gate — the same finding that fixed IMPORTANT 1 above): origin.current
	# is forced true by the engine's own NOTIFICATION_ENTER_TREE the instant
	# ANY XROrigin3D is tree-mounted, and this scene's near=0.1 is already
	# the saved-file value — both would read exactly this way even if
	# bind_rig() never ran. Mutation-verified: neither line went red under
	# the same "hardcode a fake success" mutation that turns is_immersive()
	# above red. They stay here as a sanity check on the rig's shape, not as
	# proof of the call site.
	_ok("corroborating: THIS scene's own XROrigin3D.current is true",
		wiring_origin != null and wiring_origin.current == true)
	_ok("corroborating: THIS scene's own XRCamera3D.near clears the floor",
		wiring_cam != null and wiring_cam.near >= VisionOSBootScript.MIN_NEAR)
	# THE OTHER real safety property (IMPORTANT 1, 2026-08-10 review, final
	# gate): XROrigin3D.current flipping true is harmless ONLY because
	# XRCamera3D never becomes the VIEWPORT's active camera, and
	# CameraRig/Camera3D — the camera test_e2e's screen-geometry scenarios
	# actually photograph — stays the one in use throughout. This is what
	# desktop safety genuinely depends on; proven here on the real,
	# tree-mounted scene, after the real call site has run, not before it.
	var wiring_old_cam: Node = wiring_game.get_node_or_null("CameraRig/Camera3D")
	_ok("desktop safety: XRCamera3D.current is still false — it never became the viewport camera",
		wiring_cam != null and wiring_cam.current == false)
	_ok("desktop safety: CameraRig/Camera3D is still the current camera after a real bind",
		wiring_old_cam != null and wiring_old_cam.current == true)
	root.remove_child(wiring_game)
	wiring_game.free()
	VisionOSBootScript._reset_for_test()
	XRSessionScript._reset_for_test()   # leave no latch behind for whatever runs after this suite
	# game.gd's _ready() unconditionally called Music.play_game() (the Music
	# autoload outlives wiring_game — it is not one of its children, so
	# freeing wiring_game above never touched it). Stop it immediately (no
	# fade) rather than leave an AudioStreamPlayback playing into process
	# teardown, which otherwise leaks the stream past this suite's own exit.
	# Fetched by node path, not the bare `Music` global: autoload names are
	# only compiler-visible to scripts loaded as part of a normal scene
	# boot, not to the script driving `-s`'s own SceneTree main loop.
	# (A stopped AudioStreamPlaybackMP3 still shows up in the engine's own
	# "leaked at exit" ObjectDB report on quit — tests/test_music.gd's
	# already-shipped, ALL-GREEN suite exits the same way with the same
	# leak class, at a larger scale, on every run. That is this engine
	# build's headless MP3 teardown, not something to chase here.)
	var music := root.get_node_or_null("Music")
	if music != null and music.has_method("stop_all"):
		music.call("stop_all", 0.0)

	print("=== %s ===" % ("PASS" if failures == 0 else "%d FAILURES" % failures))
	quit(1 if failures > 0 else 0)
