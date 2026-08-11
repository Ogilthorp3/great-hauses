extends SceneTree

# Task 5b — the minimal XR rig scenes/game.tscn must carry so
# src/xr/xr_session.gd's _set_origin_current/_set_near can ever succeed on
# hardware, AND the two call sites that decide WHEN each phase runs. Added
# after a 2026-08-10 review found Task 6's acceptance criterion ("turning your
# head moves the view") unreachable: bring-up now correctly REPORTS a missing
# rig (step "origin"/"near" — see test_visionos_boot.gd cases 6/7/10) instead
# of silently no-oping, but nothing in this repo tagged a node into the
# "xr_origin" / "xr_camera" groups those setters look up. The first section
# below is the other half of THAT fix: it proves the SAVED SCENE, not the
# consumer, carries the rig.
#
# ROUND 1 FOLLOW-UP (2026-08-10 review round 1): the rig above was correct,
# but XR bring-up had only ONE call site — main.gd._ready(), which runs
# BEFORE any scene, including game.tscn, is added — so the "xr_origin"/
# "xr_camera" lookup ran at a point in boot where no rig could possibly
# exist yet, on every single real-hardware launch. The fix split bring-up
# into two phases across two files (see visionos_boot.gd's "ORDERING SCAR"
# doc): PHASE 1 (XRSession.start(), interface only) stays in main.gd; PHASE
# 2 (XRSession.bind_rig(), the rig lookup) moved to game.gd, where the rig
# is actually live by the time it runs. The "CALL-SITE WIRING" sections
# below are the assertions that would have caught the original defect, and
# that keep it from coming back. A `.tscn`-only test — proving the rig
# itself is correct, as the first section does — could never have caught it:
# the defect was WHEN the lookup ran, not what it looked up, and "when"
# lives in main.gd and game.gd, not in the scene file.
#
# ROUND 2 (2026-08-10 adversarial audit — the scars that shaped the current
# file; each is named again at the assertion it produced):
#   A. The behavioural check "is_immersive() is true" was labelled "real call
#      site bound the rig". It is not: is_immersive() is one bool copied from
#      bind_rig()'s return, so ANY implementation that returns ok=true — one
#      that never looks up a node, never touches the rig — satisfies it. The
#      audit gutted XRSession.bind_rig() to `_immersive = true; return ok`
#      and this suite ran 22/22, exit 0. is_immersive() now claims only what
#      it proves (the call site EXECUTED) and two new assertions carry the
#      binding claim: a near plane deliberately BROKEN before mounting that
#      only a real dep call can repair, and a rig-less mount that must leave
#      is_immersive() FALSE.
#   B. Three assertions could not fail under any implementation. Pre-tree
#      `origin.current` reads false even when the .tscn literally saves
#      `current = true` (XROrigin3D does not retain it outside a live tree),
#      so the "SAVED SCENE FILE" assertion never read the saved file at all —
#      it now reads the file's TEXT. Post-mount `origin.current == true` and
#      `cam.near >= MIN_NEAR` were engine-forced / already-saved values; both
#      are replaced by round-trips only real code can produce.
#   C. main.gd's phase-1 call site had NO behavioural coverage: the audit
#      moved `XRSession.start(get_tree())` into a never-called function and
#      both suites stayed green. It now has its own section that mounts the
#      real main.tscn and reads back the trace phase 1 leaves behind.
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
#   - THE SAVED SCENE CARRIES NEITHER NODE AS CURRENT read two different
#                            ways, deliberately, because the two nodes do not
#                            behave the same. XRCamera3D RETAINS the saved
#                            value on a freshly instantiated, not-yet-mounted
#                            copy, so a property read is a real check there
#                            (mutation-proven: saving `current = true` on it
#                            turns that line red). XROrigin3D does NOT — a
#                            .tscn that explicitly saves `current = true`
#                            still reads false pre-tree, so the equivalent
#                            property read was vacuous and is now a read of
#                            the SAVED FILE'S TEXT instead.
#
#                            SCAR (2026-08-10 review, final gate): this used
#                            to claim "XRSession.bind_rig() is the ONLY code
#                            path allowed to flip these to true" — false at
#                            runtime. scene/3d/xr/xr_nodes.cpp:806-821
#                            (NOTIFICATION_ENTER_TREE) forces `current = true`
#                            on the FIRST XROrigin3D that ever enters ANY
#                            live tree, unconditionally — before bind_rig()
#                            gets a chance to run, and whether or not it ever
#                            succeeds. It is an engine default, not a plan
#                            invariant this suite can enforce or bind_rig()
#                            can prevent, which is why no assertion here
#                            reads XROrigin3D.current as evidence of anything
#                            (2026-08-10 audit: the one that did stayed green
#                            against a bind_rig() that touched no node).
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
#                            loads. Covered at three strengths, weakest
#                            first, and the file says which is which:
#
#                            (a) TEXTUAL, comment-stripped. Cheap, catches a
#                            deleted call, and — for main.gd — is scoped to
#                            _ready()'s own indented body so a call that
#                            drifts into some other function is not accepted.
#                            SCAR (2026-08-10 review, final gate): this used
#                            to be a raw String.contains() over the whole
#                            file and was mutation-proven to pass, exit 0,
#                            against game.gd's real bind_rig() call commented
#                            out — the substring was still sitting there in
#                            the comment. Comment-stripping closed that hole.
#                            It is a pre-check, never a proof: it reads text,
#                            and text is not behaviour.
#
#                            (b) BEHAVIOURAL, main.gd / phase 1. Mounts the
#                            REAL main.tscn and asserts VisionOSBoot's
#                            _last_bring_up_step reads "find" afterwards —
#                            i.e. _ready() genuinely called XRSession.start()
#                            on this host and it failed where a desktop host
#                            must fail. SCAR (2026-08-10 audit): before this
#                            section, moving that call into a live but
#                            never-invoked function left BOTH suites 100%
#                            green, and on hardware the interface would
#                            simply never have come up.
#
#                            (c) BEHAVIOURAL, game.gd / phase 2. Mounts the
#                            REAL game.tscn twice: once with a DELIBERATELY
#                            BROKEN near plane that only bind_rig()'s real
#                            dep call can repair, and once with the rig
#                            removed, where is_immersive() must come back
#                            FALSE. SCAR (2026-08-10 audit): the previous
#                            version of this block asserted is_immersive()
#                            alone and called that "bound the rig" — it ran
#                            fully green against a gutted XRSession.bind_rig()
#                            AND a gutted VisionOSBoot.bind_rig(), neither of
#                            which touched a single node. A latch copied from
#                            a return value proves the call RAN; it takes an
#                            observable change to a real node, plus a case
#                            that must come back false, to prove it BOUND.
#
# The scene in the FIRST section below is instantiated but deliberately
# NEVER added to the SceneTree: game.gd's _ready() wires HUD/banter/Music/
# network state that assumes the real boot path (main.tscn -> autoloads ->
# change_scene_to_file), none of which that section touches or needs to
# prove. A node's groups are recorded on the Node itself the instant it is
# instantiated — Node.is_in_group() does not require SceneTree membership —
# so a plain recursive walk proves exactly what get_first_node_in_group()
# would on a live tree, without booting the whole game headless. The
# BEHAVIOURAL sections are the exception: they mount SEPARATE instances of
# main.tscn and game.tscn for real, specifically because proving a real call
# site requires the real _ready() to actually run — see each section's own
# header for why that is safe here (Session unconfigured, no probe flags: the
# same fallback path --smoke/--dump-tree/direct-launch probes already rely on).
#
# Run: /Applications/Godot.app/Contents/MacOS/Godot \
#        --headless --path . -s res://tests/test_xr_rig.gd
# Exit code 0 = all green, 1 = failures.

const GAME_SCENE := "res://scenes/game.tscn"
const MAIN_SCENE := "res://scenes/main.tscn"
const MAIN_SCRIPT := "res://src/main.gd"
const GAME_SCRIPT := "res://src/game.gd"
const VisionOSBootScript := preload("res://src/xr/visionos_boot.gd")
const XRSessionScript := preload("res://src/xr/xr_session.gd")

## The near plane this suite deliberately breaks on its own mounted copy of
## game.tscn before letting the real call site run. Chosen BELOW
## VisionOSBoot.MIN_NEAR (0.1) and different from every value anything else
## could produce: the saved scene stores 0.1, Camera3D's own default is 0.05,
## so a post-mount reading of >= 0.1 on this instance can only have come from
## XRSession._set_near()'s real `maxf(cam.near, MIN_NEAR)` on this real node.
const SABOTAGE_NEAR := 0.01

var failures := 0

## Every assertion this run actually executed, printed as ASSERTIONS=<n> at
## the end. run_e2e.sh's run_suite compares it against the count written in
## that file's own header and FAILS the suite on a mismatch — because the two
## header counts had silently drifted to half the real number (2026-08-10
## adversarial audit), i.e. the header described a version of these files that
## no longer existed. A hand-maintained number with nothing checking it is a
## comment, not a count.
var checks := 0


## A fake XRInterface, identical in spirit to test_visionos_boot.gd's — this
## suite needs its own copy because it does not preload that suite's file
## (each `-s` suite here is meant to be readable standalone). Only used to
## arm VisionOSBoot's phase-1 guard directly, the same way main.gd's real
## XRSession.start() would on a build where a genuine visionOS interface
## answers — see the BEHAVIOURAL call-site sections below for why this suite
## needs phase 1 up before it can prove anything about phase 2.
class FakeInterface extends RefCounted:
	func initialize() -> bool:
		return true


## Strips GDScript line comments before a source-text match, so a call sitting
## in a comment (dead, unreachable) can never satisfy an assertion that is
## supposed to prove the call is LIVE. Neither main.gd nor game.gd puts a "#"
## inside a string literal (checked by hand at the time this was written), so
## a plain per-line split is sufficient — no need for a full tokenizer here.
## Note the failure direction if that ever stops being true: a "#" inside a
## string TRUNCATES the line, which can only ever make a "calls X" assertion
## go RED (the call disappears from the stripped text), never green. The
## behavioural sections below are what the regression guarantee actually
## rests on either way.
func _strip_comments(src: String) -> String:
	var out: Array[String] = []
	for line in src.split("\n"):
		var hash_at := line.find("#")
		out.append(line if hash_at == -1 else line.substr(0, hash_at))
	return "\n".join(out)


## The comment-stripped BODY of one function: every line after the `func`
## header up to the first non-empty line that starts at column 0, which is
## GDScript's own rule for where a function ends. Scoping main.gd's textual
## check to _ready()'s body is what stops a call that has drifted into a
## never-invoked helper from satisfying it (2026-08-10 audit, PROBE B — the
## whole-file substring match accepted exactly that).
func _func_body(live_src: String, header_prefix: String) -> String:
	var out: Array[String] = []
	var inside := false
	for line in live_src.split("\n"):
		if not inside:
			inside = line.begins_with(header_prefix)
			continue
		if not line.strip_edges().is_empty() and not (line.begins_with("\t") or line.begins_with(" ")):
			break
		out.append(line)
	return "\n".join(out)


## Reads the property lines of the first `[node ...]` block in a SAVED .tscn's
## TEXT whose header contains `header_needle` — the bytes on disk, not a
## property read off an instantiated node.
##
## This exists because a property read is NOT a read of the saved file for
## every node type (2026-08-10 audit, PROBE A): XROrigin3D does not retain
## `current` outside a live tree, so a .tscn that literally stores
## `current = true` still reports false on a fresh instantiate() — an
## assertion phrased as "the saved scene does not set it" could not fail. For
## that node the file text is the only place the saved value is observable.
## Returns {found, props}: `found` is separate because a correct XROrigin3D
## block has NO property lines at all, which must not be confused with "no
## such block in this scene".
func _tscn_node_block(scene_path: String, header_needle: String) -> Dictionary:
	var props: Array[String] = []
	var found := false
	var inside := false
	for line in _read_source(scene_path).split("\n"):
		var t := line.strip_edges()
		if t.begins_with("["):
			if inside:
				break   # the next node's header ends this block
			inside = t.begins_with("[node ") and t.contains(header_needle)
			found = found or inside
			continue
		if not inside or t.is_empty() or t.begins_with(";"):
			continue
		props.append(t)
	return {"found": found, "props": props}


## Arms PHASE 1 the way main.gd's real XRSession.start() would on a genuine
## visionOS launch, from a clean slate at BOTH layers. bind_rig() refuses to
## run at all until phase 1 has reached "done" (test_visionos_boot.gd case 5),
## so every behavioural phase-2 check below has to do this first.
func _arm_phase_1() -> Dictionary:
	VisionOSBootScript._reset_for_test()
	XRSessionScript._reset_for_test()
	return VisionOSBootScript.bring_up({
		"find_interface": func(_n: String): return FakeInterface.new(),
		"set_use_xr": func(_v: bool) -> void: pass,
	})


func _initialize() -> void:
	_main()


func _ok(label: String, cond: bool) -> void:
	checks += 1
	if cond:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s" % label)
		failures += 1


## Mirrors SceneTree.get_first_node_in_group() without requiring the node to
## be inside a live SceneTree — see the header note above on why the first
## section never adds the instantiated scene to one.
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
		# A REAL check, unlike its XROrigin3D counterpart below: Camera3D
		# retains `current` on a not-yet-mounted instance, so saving
		# `current = true` on this node in the .tscn turns this line red
		# (mutation-proven, 2026-08-10 audit M8).
		_ok("XRCamera3D.current is false in the saved scene — desktop stays on CameraRig",
			cam.current == false)

	# The SAVED FILE'S TEXT, not a property read (2026-08-10 audit, PROBE A):
	# XROrigin3D does not retain `current` outside a live tree, so the property
	# read this replaces returned false even against a .tscn that explicitly
	# saved `current = true` — it could not fail, and it silently permitted
	# exactly the value its own label claimed to forbid. Reading the bytes is
	# the only way to make this claim honestly. It is a hygiene check, not a
	# runtime safety guarantee: the engine forces origin.current true on tree
	# entry regardless (see the header SCAR), which is why desktop safety is
	# proven through XRCamera3D/CameraRig in the behavioural section instead.
	var origin_block: Dictionary = _tscn_node_block(GAME_SCENE, 'groups=["xr_origin"]')
	_ok("the saved game.tscn TEXT declares a node in the 'xr_origin' group",
		origin_block.found == true)
	var saved_origin_current := ""
	for prop in origin_block.props:
		if prop.begins_with("current"):
			saved_origin_current = prop
	_ok("the saved game.tscn TEXT sets no `current` on that node (found: '%s')" % saved_origin_current,
		saved_origin_current.is_empty())

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
	# for main.gd it also scopes the match to _ready()'s own indented body,
	# because a live-but-never-called function is the other way text lies
	# (2026-08-10 audit, PROBE B). Even so this is a fast pre-check, not the
	# proof. The proofs are the two behavioural sections below.
	print("--- call-site wiring: textual (comment-stripped) ---")
	var main_src := _read_source(MAIN_SCRIPT)
	var game_src := _read_source(GAME_SCRIPT)
	_ok("%s was readable" % MAIN_SCRIPT, not main_src.is_empty())
	_ok("%s was readable" % GAME_SCRIPT, not game_src.is_empty())
	var main_live := _strip_comments(main_src)
	var game_live := _strip_comments(game_src)
	var main_ready := _func_body(main_live, "func _ready(")
	_ok("main.gd has a _ready() body to read at all", not main_ready.strip_edges().is_empty())
	_ok("main.gd calls XRSession.start() INSIDE _ready() — phase 1, before any scene loads",
		main_ready.contains("XRSession.start("))
	_ok("main.gd does NOT call XRSession.bind_rig() in live code — the rig cannot exist yet here",
		not main_live.contains("XRSession.bind_rig("))
	_ok("game.gd calls XRSession.bind_rig() in live code — phase 2, once the rig is live",
		game_live.contains("XRSession.bind_rig("))
	_ok("game.gd does NOT call XRSession.start() in live code — phase 1 belongs to main.gd only",
		not game_live.contains("XRSession.start("))

	# ── CALL-SITE WIRING, BEHAVIOURAL: main.gd / PHASE 1 ────────────────────
	# The textual check above says the call is written inside _ready(). This
	# says _ready() RAN it. Mounting the real main.tscn is the whole boot
	# path: main.gd._ready() installs no e2e harness (no --e2e flag on this
	# process's command line), takes no network branch and no probe-flag
	# branch, shows the Hall of Banners, and — the line under test — calls
	# XRSession.start(get_tree()) before any of it.
	#
	# On this host XRServer has no interface named "visionOS", so phase 1
	# fails at step "find" and leaves _interface_up FALSE. That is precisely
	# what made this call site unprovable until now: a failed bring_up()
	# changes nothing else, so "it ran and failed at find" and "it was never
	# called" looked identical from outside. VisionOSBoot._last_bring_up_step
	# (added for this, and documented there as a diagnostic in its own right)
	# is the trace that tells them apart.
	print("--- call-site wiring: behavioural (main.gd, phase 1) ---")
	VisionOSBootScript._reset_for_test()
	XRSessionScript._reset_for_test()
	_ok("setup: the phase-1 step latch is clear before main.tscn is mounted",
		VisionOSBootScript._last_bring_up_step == "")
	var main_packed: PackedScene = load(MAIN_SCENE)
	var main_node: Node = main_packed.instantiate()
	root.add_child(main_node)
	# Same two-frame wait as every other real-tree case in this repo: a node
	# added to `root` from inside a `-s` script's _main() is not actually
	# wired in until the next process frame.
	await process_frame
	await process_frame
	_ok("main.tscn, mounted for real, ran its own _ready()", main_node.is_inside_tree())
	# THE assertion PROBE B walked through. Nothing in this suite calls
	# bring_up() between the reset above and this read, so "find" can only
	# have been written by main.gd's own XRSession.start(get_tree()).
	_ok("main.gd's _ready() actually EXECUTED XRSession.start(): phase 1 reached step 'find'",
		VisionOSBootScript._last_bring_up_step == "find")
	_ok("...and correctly failed there — this host has no visionOS XRInterface, so phase 1 stays down",
		VisionOSBootScript._interface_up == false)
	root.remove_child(main_node)
	main_node.free()

	# ── CALL-SITE WIRING, BEHAVIOURAL: game.gd / PHASE 2, POSITIVE ──────────
	# This is what the textual section cannot be: proof the call RUNS and
	# BINDS, not that its name appears somewhere in the file. It reproduces
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
	# `XRSession.bind_rig(get_tree())` inside game.gd's _ready().
	#
	# THE SABOTAGE is the point of this block (2026-08-10 audit, M3b/M3c).
	# Before mounting, this instance's XRCamera3D.near is deliberately broken
	# to SABOTAGE_NEAR — a value the saved scene does not contain and no
	# engine default produces. Only VisionOSBoot.bind_rig() actually calling
	# XRSession._set_near() on this real node can put it back over MIN_NEAR.
	# An implementation that returns {ok: true} without touching a node —
	# which is how this code will actually rot — leaves 0.01 sitting there.
	print("--- call-site wiring: behavioural (game.gd, phase 2, positive) ---")
	var arm_result: Dictionary = _arm_phase_1()
	_ok("setup: phase 1 armed (VisionOSBoot._interface_up) before mounting game.tscn",
		arm_result.ok == true and arm_result.step == "done")
	var wiring_packed: PackedScene = load(GAME_SCENE)
	var wiring_game: Node = wiring_packed.instantiate()
	var pre_cam := _first_in_group(wiring_game, "xr_camera")
	if pre_cam != null:
		pre_cam.near = SABOTAGE_NEAR
	_ok("setup: this instance's XRCamera3D.near was broken to %.2f before mounting" % SABOTAGE_NEAR,
		pre_cam != null and pre_cam.near < VisionOSBootScript.MIN_NEAR)
	root.add_child(wiring_game)
	await process_frame
	await process_frame
	_ok("game.tscn, mounted for real, ran its own _ready()", wiring_game.is_inside_tree())
	var wiring_origin := _first_in_group(wiring_game, "xr_origin")
	var wiring_cam := _first_in_group(wiring_game, "xr_camera")
	# CALL-SITE LIVENESS, and nothing more — say only what this proves.
	# is_immersive() is one bool copied from bind_rig()'s return value
	# (`_immersive = result.ok`), so it goes red when the call site is deleted
	# or commented out, and stays green against any implementation that
	# returns ok=true without doing anything (2026-08-10 audit, M3b/M3c: this
	# assertion alone ran green against a bind_rig() that bound nothing). The
	# two assertions after it are the ones that prove the BINDING.
	_ok("real call site EXECUTED: XRSession.is_immersive() is true after the mount",
		XRSessionScript.is_immersive() == true)
	# THE BINDING PROOF. 0.01 -> >= 0.1 on this specific node is a change only
	# XRSession._set_near()'s real maxf() on a real group lookup can make.
	_ok("real call site BOUND the rig: bind_rig clamped THIS instance's near from %.2f back to >= %.2f"
			% [SABOTAGE_NEAR, VisionOSBootScript.MIN_NEAR],
		wiring_cam != null and wiring_cam.near >= VisionOSBootScript.MIN_NEAR)
	# THE OTHER real setter, proven the one way the engine does NOT force.
	# origin.current reading true after a mount proves nothing (the engine
	# writes it on NOTIFICATION_ENTER_TREE — the assertion that used to read
	# it stayed green against a bind_rig() that touched no node, 2026-08-10
	# audit M3c). A write-back does prove it: only a real group lookup plus a
	# real assignment can drive this node to false and then back to true, and
	# _set_origin_current re-reads the property both times rather than
	# trusting the write. Restoring true also leaves the scene as the engine
	# had it for the desktop-safety assertions below.
	var wrote_false := XRSessionScript._set_origin_current(self, false)
	var read_false: bool = wiring_origin != null and wiring_origin.current == false
	var wrote_true := XRSessionScript._set_origin_current(self, true)
	_ok("the REAL origin setter round-trips on THIS scene's XROrigin3D: false reads back false, true reads back true",
		wrote_false and read_false and wrote_true and wiring_origin != null and wiring_origin.current == true)
	# THE real desktop-safety property (IMPORTANT 1, 2026-08-10 review, final
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

	# ── CALL-SITE WIRING, BEHAVIOURAL: game.gd / PHASE 2, NEGATIVE ──────────
	# The direction a hardcoded success cannot survive (2026-08-10 audit,
	# M3b/M3c). Same real scene, same real call site, one thing different: the
	# rig is removed from the instance before it is mounted, and the previous
	# instance has already been freed, so NOTHING in this tree is in the
	# "xr_origin"/"xr_camera" groups when game.gd's _ready() runs bind_rig().
	# The real implementation must therefore fail at step "origin" and leave
	# is_immersive() FALSE. Any implementation that reports ok=true without
	# reaching a node — the exact rot the positive block above is blind to on
	# its own — reports TRUE here and turns this red.
	print("--- call-site wiring: behavioural (game.gd, phase 2, negative) ---")
	var bare_arm: Dictionary = _arm_phase_1()
	_ok("setup: phase 1 re-armed, both latches cleared, before the rig-less mount",
		bare_arm.ok == true and XRSessionScript.is_immersive() == false)
	var bare_game: Node = wiring_packed.instantiate()
	var bare_origin := _first_in_group(bare_game, "xr_origin")
	if bare_origin != null:
		bare_origin.get_parent().remove_child(bare_origin)
		bare_origin.free()   # takes its XRCamera3D child with it
	_ok("setup: this instance really has no rig left (neither group resolves)",
		_first_in_group(bare_game, "xr_origin") == null
			and _first_in_group(bare_game, "xr_camera") == null)
	root.add_child(bare_game)
	await process_frame
	await process_frame
	_ok("rig-less scene, mounted for real, ran its own _ready()", bare_game.is_inside_tree())
	_ok("no rig in the tree -> the real bind FAILED and XRSession.is_immersive() stays FALSE",
		XRSessionScript.is_immersive() == false)
	# Both real setters, on a genuinely empty tree, from a SECOND suite. Until
	# now the whole "silent no-op setter" regression class (visionos_boot.gd's
	# 6th-silent-green scar) rested on exactly two assertions in
	# test_visionos_boot.gd case 10: reverting either setter to `return true`
	# on a null node turned exactly ONE line red in 66, and nothing else in
	# either suite noticed (2026-08-10 audit, M5 and PROBE D). Two lines here
	# cost nothing and mean losing case 10 no longer loses the class.
	_ok("no rig in the tree -> the real setter agrees: _set_origin_current returns false",
		XRSessionScript._set_origin_current(self, true) == false)
	_ok("no rig in the tree -> the real setter agrees: _set_near returns false",
		XRSessionScript._set_near(self, VisionOSBootScript.MIN_NEAR) == false)
	root.remove_child(bare_game)
	bare_game.free()

	VisionOSBootScript._reset_for_test()
	XRSessionScript._reset_for_test()   # leave no latch behind for whatever runs after this suite
	# main.gd's _ready() called Music.play_menu() and game.gd's called
	# Music.play_game() (the Music autoload outlives both — it is not one of
	# their children, so freeing them above never touched it). Stop it
	# immediately (no fade) rather than leave an AudioStreamPlayback playing
	# into process teardown, which otherwise leaks the stream past this
	# suite's own exit. Fetched by node path, not the bare `Music` global:
	# autoload names are only compiler-visible to scripts loaded as part of a
	# normal scene boot, not to the script driving `-s`'s own SceneTree main
	# loop.
	# (A stopped AudioStreamPlaybackMP3 still shows up in the engine's own
	# "leaked at exit" ObjectDB report on quit — tests/test_music.gd's
	# already-shipped, ALL-GREEN suite exits the same way with the same
	# leak class, at a larger scale, on every run. That is this engine
	# build's headless MP3 teardown, not something to chase here.)
	var music := root.get_node_or_null("Music")
	if music != null and music.has_method("stop_all"):
		music.call("stop_all", 0.0)

	print("ASSERTIONS=%d" % checks)
	print("=== %s ===" % ("PASS" if failures == 0 else "%d FAILURES" % failures))
	quit(1 if failures > 0 else 0)
