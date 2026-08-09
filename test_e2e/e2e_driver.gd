## e2e_driver.gd — in-engine E2E driver (autoload "E2EDriver", LAST in order).
##
## Dormant unless the game is launched with user args:
##     Godot --path <proj> -- --e2e=<scenario> [--e2e-artifacts=<abs dir>]
##                            [--e2e-fen=<fen>] [--e2e-timeout=<sec>]
##
## Driver pattern ported from Duke's Gambit (our own test harness file — no
## game code shared): it drives the REAL running game by synthesizing
## InputEvents through Input.parse_input_event, with the empirical
## canvas->window transform calibration so stretch/HiDPI can never break the
## click math. Never calls handlers directly — the input path IS the test.
##
## Every game scenario first navigates the Hall of Banners (house select) by
## synthesized clicks: crest -> opponent -> mode, then plays in game.tscn.
##
## Scenarios:
##   boot        select flows into the game, 32 pieces standing, banners
##               dyed to the chosen house, HUD carries the house names, and
##               the hover-only glyph rings (ISSUES.md #2) through the real
##               mouse path: hidden at rest, revealed under the cursor,
##               held lit by selection, faded out on leave
##   orientation (launched with --debug-coords) the labeled-overlay
##               tiebreaker: saves labeled.png, the engine's own file/rank/
##               royal beliefs photographed from the default player camera —
##               a permanent human-auditable orientation artifact
##   board-truth startpos ground truth, convention-INDEPENDENT: squares
##               located by screen geometry (visual-a1 = the board polygon's
##               bottom-left corner), checkerboard + queen-color read from
##               RENDERED pixels, royals found by rendered world position,
##               White seated nearest; engine tile-node parity kept as a
##               secondary crosscheck — the earned check for the 2026-08-08
##               tile-parity inversion ("queen not on her color")
##   board-moves (needs BOARD_FEN) clicks visual e1/d1 BY SCREEN POSITION and
##               asserts the surfaced highlights equal the hand-derived king
##               moveset (incl. the O-O hop) and queen moveset (incl. the
##               long a4 ray), all in visual space — the royal movesets
##               through the real click → highlight pipeline, mirror-proof
##   move        click e2 pawn -> e4 via real clicks, AI replies within 30 s
##   duel        (needs --e2e-fen with an immediate white capture) executes
##               the capture by clicks; slow-mo duel plays out untouched;
##               asserts victim gone, death anim, attacker arrival, and
##               time_scale restored to 1.0
##   castle      (needs --e2e-fen with O-O available) castles by clicks;
##               visually asserts the king STANDS on visual g1, rook on f1
##   enpassant   (needs EP_FEN) exd6 e.p. by screen-position clicks; asserts
##               the pawn lands visual d6 and the captured pawn vanishes
##               from visual d5 — the square BEHIND the landing
##   promote     (needs PROMOTE_FEN, a real promotion PROBLEM) the promotion
##               picker: all four pieces taken in one run — clicking the piece
##               model, the hotkey, the arrow keys, and Esc for the silent
##               default — each undone back to the pawn; asserts the knight's
##               CHECK, the rook AVOIDING the stalemate the queen causes, the
##               right model and flourish per choice, then the draw card, the
##               rival's draw taunt and the tournament draw seam
##   slowmo      capture triggers the DuelDirector; asserts activation, the
##               time dip, skip-on-click restore, and a clean final settle
##   tournament  Begin Tournament with a mate-in-1 FEN: three rounds of
##               scripted mates; asserts bracket advance, banner re-dress
##               each round, and the championship panel
##   oracle-mock DS4-Oracle (Pure Oracle) against an in-driver canned HTTP
##               mock; asserts a legal oracle move, llm source, thinking HUD
##   oracle-modes Counseled Oracle vs the mock LLM + REAL local stockfish:
##               (needs --e2e-fen with Black to move) the mock's first
##               proposal is a deliberate blunder; asserts the counsel's
##               reconsideration prompt was issued, the blunder was not
##               played, the revised move landed, and the HUD mode label
##   music       Music autoload wiring: menu playlist on the select screen,
##               gameplay playlist in the hall, M mute toggle on the real
##               input path (asserted on the Music bus), duel duck −8 dB +
##               stinger, unduck after the cinematics settle
##   banter      (needs BANTER_FEN) rival smack talk through the real HUD:
##               opening + first-blood captions in the rival's accent color,
##               then the 2-fullmove rate limit holds across 2 more plies
##               (banter_skipped rate_limited evidence). DS4_CHESS_URL points
##               at a dead port so the canned pools answer deterministically.
##   dragon-live (needs DRAGON_FEN — mate-in-1 with three loser pawns left
##               standing) the spectator wyrm: perched from the hall anchor,
##               notice_move wired, reactions locked under the duel cam, then
##               the scripted mate → ASHFALL. Every ceremony frame is taken on
##               the ceremony's own PHASE (never on the bent clock): the bank
##               silhouette, the TORRENT (gated on is_jet_burning AND on a
##               flame census of the saved pixels), and the ember/ash tail
##               after the cut. Then time_scale restored, loser views purged,
##               victory flow — which must not open until the wyrm is done.
##   undo        (needs DUEL_FEN) take-back insurance vs the mock Pure Oracle
##               in TOURNAMENT mode: full-round revert restores FEN + view
##               census byte-identical (captured pawn resurrects), a
##               mid-think undo cancels the player ply and the mock's DELAYED
##               late reply is discarded with no desync, then the 3-undo
##               tournament limit disables the button and Cmd/Ctrl+Z goes
##               inert
##   fullgame    complete scripted game (two-rook ladder mate) vs the engine;
##               asserts board/view sync every ply and time_scale hygiene
##   showcase    beauty run for Gate C: hall wide shot, select screen,
##               mid-duel caption frame, a BanterCaption frame, idles to the
##               45 s mark, then the championship throne-room tableau
##               (crowned king + throne + dragon, camera parked on the frame)
##
## Output contract (consumed by run_e2e.sh):
##     "E2E PASS <step>" / "E2E FAIL <step> — <reason>" lines,
##     per-step PNGs in the artifacts dir, exit code 0/1, watchdog.

extends Node

const DEFAULT_HOUSE := "winterfang"
const MOCK_MODEL := "deepseek-v4-flash-mock"

var scenario: String = ""
var artifacts_dir: String = ""
var timeout_sec: float = 60.0

var _steps_passed: int = 0
var _shot_i: int = 0
var _done: bool = false
var _to_window: Transform2D = Transform2D.IDENTITY
var _last_input_pos := Vector2(-1e9, -1e9)
var _start_ms := 0

# -- mock oracle server state (oracle-mock / oracle-modes / undo) --
var _mock_server: TCPServer
var _mock_port := 0
var _mock_running := false
var _mock_replies: Array = []    # queued chat contents; default "MOVE: e7e5"
var _mock_requests: Array = []   # parsed JSON bodies of every chat call
var _mock_delay_ms := 0          # undo scenario: hold each oracle reply this long
var _mock_served := 0            # oracle chat replies fully written to the wire

## Observe every event that actually reaches the scene tree — proves
## synthesized events are delivered and learns the coordinate space
## parse_input_event expects.
func _input(event: InputEvent) -> void:
	if scenario != "" and event is InputEventMouse:
		_last_input_pos = (event as InputEventMouse).position

# ── Activation ─────────────────────────────────────────────────────────────
func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--e2e="):
			scenario = arg.substr(6)
		elif arg.begins_with("--e2e-artifacts="):
			artifacts_dir = arg.substr(16)
		elif arg.begins_with("--e2e-timeout="):
			timeout_sec = float(arg.substr(14))
	if scenario.is_empty():
		return   # dormant — normal gameplay is completely untouched
	if artifacts_dir.is_empty():
		artifacts_dir = ProjectSettings.globalize_path("res://test_e2e/artifacts") \
			+ "/" + scenario
	DirAccess.make_dir_recursive_absolute(artifacts_dir)
	_start_ms = Time.get_ticks_msec()
	if scenario in ["oracle-mock", "oracle-modes", "undo"]:
		# The env var must exist before main.gd/game.gd ever build an oracle;
		# autoload _ready runs before the main scene loads, so this is early
		# enough — and each e2e launch is its own process, nothing leaks.
		_start_mock_oracle()
	elif scenario in ["music", "banter", "dragon-live", "promote",
			"net-host", "net-join", "net-hall"]:
		# Deterministic offline: BanterEngine shares the Oracle's endpoint
		# family — a dead port makes its LLM path fail instantly so the
		# canned pools answer synchronously.
		OS.set_environment("DS4_CHESS_URL", "http://127.0.0.1:9")
	print("E2E driver active — scenario=%s timeout=%.0fs artifacts=%s"
		% [scenario, timeout_sec, artifacts_dir])
	_watchdog()
	_run()

# ── Top-level flow ─────────────────────────────────────────────────────────
func _watchdog() -> void:
	await get_tree().create_timer(timeout_sec).timeout
	if _done:
		return
	print("E2E FAIL watchdog — scenario '%s' exceeded %.0fs" % [scenario, timeout_sec])
	await _shot("timeout")
	_finish(1)

func _run() -> void:
	await get_tree().process_frame
	var have_scene := await _wait_until(
		func(): return get_tree().current_scene != null, 20.0)
	if not have_scene:
		await _fail("boot", "no main scene appeared within 20s")
		return
	if not await _calibrate_input():
		await _fail("input-pipeline", "synthesized mouse events do not reach the viewport")
		return
	_pass("input-pipeline")
	match scenario:
		"boot":
			await _scenario_boot()
		"board-truth":
			await _scenario_board_truth()
		"board-moves":
			await _scenario_board_moves()
		"orientation":
			await _scenario_orientation()
		"move":
			await _scenario_move()
		"duel":
			await _scenario_duel(false)
		"castle":
			await _scenario_castle()
		"enpassant":
			await _scenario_enpassant()
		"promote":
			await _scenario_promote()
		"slowmo":
			await _scenario_slowmo()
		"tournament":
			await _scenario_tournament()
		"oracle-mock":
			await _scenario_oracle_mock()
		"oracle-modes":
			await _scenario_oracle_modes()
		"undo":
			await _scenario_undo()
		"music":
			await _scenario_music()
		"banter":
			await _scenario_banter()
		"dragon-live":
			await _scenario_dragon_live()
		"fullgame":
			await _scenario_fullgame()
		"showcase":
			await _scenario_duel(true)
		"net-host":
			await _scenario_net(true)
		"net-join":
			await _scenario_net(false)
		"net-hall":
			await _scenario_net_hall()
		_:
			await _fail("scenario", "unknown scenario '%s'" % scenario)

func _finish(code: int) -> void:
	if _done:
		return
	_done = true
	_mock_running = false
	print("E2E DONE scenario=%s exit=%d steps_passed=%d" % [scenario, code, _steps_passed])
	get_tree().quit(code)

func _pass(step: String) -> void:
	_steps_passed += 1
	print("E2E PASS %s" % step)

func _fail(step: String, why: String) -> void:
	print("E2E FAIL %s — %s" % [step, why])
	await _shot("FAIL_" + step)
	_finish(1)

# ── Generic helpers ────────────────────────────────────────────────────────
func _wait_until(pred: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if _done:
			return false
		if pred.call():
			return true
		await get_tree().process_frame
	return false

func _sleep(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

## WALL-CLOCK sleep — immune to Engine.time_scale.
##
## THE SCAR (2026-08-09): every cinematic in this game bends Engine.time_scale
## (0.55 for ASHFALL, 0.15 for checkmate) while its own choreography runs on
## wall time. A plain `_sleep(1.5)` taken after the ashfall dip therefore
## waited 1.5/0.55 = 2.7 REAL seconds and landed the "mid_ashfall" shot at
## ~2.8 s — the tail of the bank. The jet does not ignite until ~4.85 s, so
## the torrent that had been built, wired and unit-tested was never once
## photographed: every fire image on disk was hours older than the code. A
## test that measures a cinematic must not measure it with the clock the
## cinematic is bending.
func _sleep_wall(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout   # ignore_time_scale

## Wait for a genuinely drawn frame — BOUNDED. Under full window occlusion
## macOS stops drawing while process frames continue, so an unbounded
## `await RenderingServer.frame_post_draw` wedges the scenario until the
## watchdog (seen 2026-08-08 with another Godot window covering the e2e
## window). On timeout the caller proceeds with the last drawn frame.
func _await_drawn(timeout_s := 3.0) -> void:
	var drawn := [false]
	RenderingServer.frame_post_draw.connect(func() -> void: drawn[0] = true,
		CONNECT_ONE_SHOT)
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while not drawn[0] and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

func _shot(step_name: String) -> Image:
	await _await_drawn()
	var img := get_viewport().get_texture().get_image()
	if img == null:
		print("E2E WARN no viewport image for screenshot '%s'" % step_name)
		return null
	_shot_i += 1
	var path := "%s/%02d_%s.png" % [artifacts_dir, _shot_i, step_name]
	var err := img.save_png(path)
	if err != OK:
		print("E2E WARN screenshot save failed (err %d): %s" % [err, path])
	# The frames an art critic reads are the frames whose overlay planes we
	# photograph — no awaits between the pixel grab and the census, so the
	# rects below ARE the rects in the PNG just saved.
	if OVERLAY_DUMP_SHOTS.has(step_name):
		_dump_overlays(step_name)
	return img

# ── Fire census (the "is there actually fire in this frame?" instrument) ───
## Earned 2026-08-09: the dracarys torrent shipped, passed its unit tests, and
## no frame anywhere on disk contained a single pixel of it — the scenario's
## post-dip await was scaled by the very time_scale the ceremony had bent, so
## every fire shot landed before the ignition (see _sleep_wall). "The fire is
## wired" was an UNVERIFIED CLAIM for a whole day. This makes it a measurement:
## the same pixels that go into the PNG are counted for flame, in the run log,
## every run. Matches tools/frame_measure.py `fire` so a critic reproducing the
## number off the PNG gets the driver's number back.
##
## Flame = hot hue (red well clear of blue), saturated, and bright. Counted on
## a 320x180 box-downsample of the frame — 57 k samples is plenty for a share
## and 921 k GDScript get_pixel calls is not affordable per shot.
const FIRE_MIN_R := 0.45
const FIRE_MIN_RB := 0.18      ## how far red must lead blue
const FIRE_MIN_SAT := 0.30
const FIRE_MIN_V := 0.35
## Share of the frame that must be flame in the torrent shot. The torch-lit
## hall with NO fire measures ~1.2%; the module preview's jet measures ~18%.
## 3% is comfortably outside the torchlight floor and well under the jet.
const FIRE_TORRENT_MIN_SHARE := 3.0
## The tail (embers, ash, ground smoke) after the jet is cut — thinner, but it
## must still be burning something.
const FIRE_TAIL_MIN_SHARE := 1.5

## {share, px, samples, v_mean, x0, y0, x1, y1} for `img` (never null-returns:
## an unreadable image reports share 0).
func _fire_census(img: Image) -> Dictionary:
	var out := {"share": 0.0, "px": 0, "samples": 0, "v_mean": 0.0,
		"x0": -1, "y0": -1, "x1": -1, "y1": -1}
	if img == null:
		return out
	var small := img.duplicate() as Image
	if small == null:
		return out
	if small.get_format() != Image.FORMAT_RGBA8:
		small.convert(Image.FORMAT_RGBA8)
	small.resize(320, 180, Image.INTERPOLATE_BILINEAR)
	var w := small.get_width()
	var h := small.get_height()
	var n := 0
	var vsum := 0.0
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in h:
		for x in w:
			var c := small.get_pixel(x, y)
			var v: float = maxf(c.r, maxf(c.g, c.b))
			var mn: float = minf(c.r, minf(c.g, c.b))
			var sat: float = 0.0 if v <= 0.0 else (v - mn) / v
			if c.r < FIRE_MIN_R or c.r - c.b < FIRE_MIN_RB \
					or sat < FIRE_MIN_SAT or v < FIRE_MIN_V:
				continue
			n += 1
			vsum += v
			x0 = mini(x0, x)
			y0 = mini(y0, y)
			x1 = maxi(x1, x)
			y1 = maxi(y1, y)
	var total := float(w * h)
	out["samples"] = int(total)
	out["px"] = n
	out["share"] = 100.0 * float(n) / total
	out["v_mean"] = (vsum / float(n)) if n > 0 else 0.0
	if n > 0:
		# Report in FULL-FRAME pixels so a bbox from the log can be pasted
		# straight into tools/frame_crop.py against the saved PNG.
		var sx := float(img.get_width()) / float(w)
		var sy := float(img.get_height()) / float(h)
		out["x0"] = int(x0 * sx)
		out["y0"] = int(y0 * sy)
		out["x1"] = int((x1 + 1) * sx)
		out["y1"] = int((y1 + 1) * sy)
	return out

func _report_fire(tag: String, img: Image) -> Dictionary:
	var c := _fire_census(img)
	print("E2E FIRE %s share=%.3f%% px=%d/%d v_mean=%.3f bbox=(%d,%d)-(%d,%d)" % [
		tag, c["share"], c["px"], c["samples"], c["v_mean"],
		c["x0"], c["y0"], c["x1"], c["y1"]])
	return c

func _colors_close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.02 and absf(a.g - b.g) < 0.02 and absf(a.b - b.b) < 0.02

## Banter caption identity check. This used to be `_colors_close(got, accent)`
## — an exact-RGB pin that FROZE the taunt at whatever value the house dye
## happened to be, and Goldclaw's dye measured 1.13:1 against the stone floor
## it lands on (the taunt was on screen and unreadable). The contract is now
## the right one: the caption must still be THIS HOUSE'S HUE, and it must
## carry a value a human can read. Returns "" when both hold.
func _accent_identity_why(game: Node, got: Color, accent: Color) -> String:
	var want: Color = game.legible_accent(accent)
	if not _colors_close(got, want):
		return "caption color %s != legible_accent(%s) = %s" % [got, accent, want]
	# Hue is the house. (An achromatic dye has no meaningful hue to keep.)
	var dh: float = absf(got.h - accent.h)
	dh = minf(dh, 1.0 - dh)
	if accent.s > 0.1 and dh > 0.02:
		return "caption hue %.3f drifted from rival accent hue %.3f" % [got.h, accent.h]
	if got.v < 0.9:
		return "caption value %.2f is too dark to read over torch-lit stone" % got.v
	return ""

# ── Overlay census (the "who painted that rectangle?" instrument) ──────────
## Earned 2026-08-09: an art critic found a flat mustard slab across three
## shipped mid-duel frames and two passes of eyeballing the source failed to
## name it. A screenshot cannot be interrogated; the tree at the instant of
## the screenshot can. `_dump_overlays` photographs BOTH overlay planes at
## the exact frame `_shot` saves:
##
##   * every visible Control (CanvasLayer HUD, captions, panels) with its
##     screen rect, and
##   * every visible VisualInstance3D projected through the LIVE camera to a
##     screen-space bbox — so a 3D quad that only exists under the duel cam
##     (marker, decal, weapon-trail flash) is measured in the same pixel
##     units the critic used.
##
## Output lines are `E2E OVERLAY <tag> ...`, never PASS/FAIL: this is an
## evidence instrument, not a gate. Match a suspect rect from the PNG against
## these lines and the culprit names itself, file and node.
const OVERLAY_MIN_AREA := 3000.0   # px² — below this it is not "a rectangle on the frame"
## Fraction of the frame a single flat billboard may cover before it stops
## being an effect and starts being a panel slapped over the fight.
const OVERLAY_SLAB_SHARE := 0.04
## The hero/critique frames. Every one of these is a shot a human has been
## asked to judge, so every one gets its overlay census in the run log.
const OVERLAY_DUMP_SHOTS: Array[String] = [
	"mid_duel", "mid_slowmo", "duel_caption", "banter_caption",
	"after_promotion", "attacker_selected",
	# The ceremony frames. A critic found the HUD title block lying across the
	# dragon's skull and the victory modal opened over the wyrm mid-ashfall
	# (2026-08-09): whatever is drawn on top of a ceremony now names itself.
	"torrent", "mid_ashfall", "throne_room",
]

func _dump_overlays(tag: String) -> void:
	var vp := get_viewport()
	var vp_size := vp.get_visible_rect().size
	print("E2E OVERLAY %s viewport=%dx%d" % [tag, int(vp_size.x), int(vp_size.y)])
	var cam := vp.get_camera_3d()
	var rows: Array[Dictionary] = []
	_collect_overlays(get_tree().root, cam, vp_size, rows)
	rows.sort_custom(func(a, b): return float(a["area"]) > float(b["area"]))
	for r in rows:
		print("E2E OVERLAY %s %-3s %-22s %-18s pos=(%d,%d) size=%dx%d aspect=%.2f path=%s %s" % [
			tag, r["plane"], r["name"], r["cls"],
			int(r["x"]), int(r["y"]), int(r["w"]), int(r["h"]),
			(float(r["w"]) / maxf(float(r["h"]), 1.0)), r["path"], r["note"]])
	# Loud, non-gating: a single flat billboard covering a big slice of a hero
	# frame is the "unfinished debug panel" failure mode. WARN (never FAIL) so
	# the suite stays a correctness gate while the art defect still shouts in
	# the log with the node path and mesh/material that produced it.
	var frame_area := maxf(vp_size.x * vp_size.y, 1.0)
	for r in rows:
		if r["plane"] != "3D":
			continue
		var share := float(r["area"]) / frame_area
		if share >= OVERLAY_SLAB_SHARE and str(r["note"]).contains("BILLBOARD"):
			print("E2E OVERLAY WARN %s flat billboard covers %.1f%% of the frame: %s (%s)"
				% [tag, share * 100.0, r["path"], r["note"]])
	print("E2E OVERLAY %s end (%d node(s) >= %d px²)" % [tag, rows.size(), int(OVERLAY_MIN_AREA)])

func _collect_overlays(node: Node, cam: Camera3D, vp_size: Vector2,
		rows: Array[Dictionary]) -> void:
	for child in node.get_children():
		_collect_overlays(child, cam, vp_size, rows)
	var rect := Rect2()
	var plane := ""
	if node is Control:
		var c := node as Control
		if not c.is_visible_in_tree():
			return
		rect = c.get_global_rect()
		plane = "2D"
	elif node is VisualInstance3D and cam != null and is_instance_valid(cam):
		var vi := node as VisualInstance3D
		if not vi.is_visible_in_tree():
			return
		rect = _screen_bbox(vi, cam)
		if rect.size == Vector2.ZERO:
			return
		plane = "3D"
	else:
		return
	if rect.size.x * rect.size.y < OVERLAY_MIN_AREA:
		return
	# Off-frame nodes are not what anyone is looking at.
	if not rect.intersects(Rect2(Vector2.ZERO, vp_size)):
		return
	rows.append({
		"plane": plane, "name": node.name, "cls": node.get_class(),
		"x": rect.position.x, "y": rect.position.y,
		"w": rect.size.x, "h": rect.size.y,
		"area": rect.size.x * rect.size.y,
		"path": str(node.get_path()).replace("/root/", ""),
		"note": _overlay_note(node),
	})

func _overlay_note(node: Node) -> String:
	## Enough of a mesh/material fingerprint to identify the SOURCE LINE that
	## built an anonymous runtime node ("@MeshInstance3D@89" names nothing).
	if not (node is MeshInstance3D):
		return ""
	var mi := node as MeshInstance3D
	var bits: Array[String] = []
	var mesh := mi.mesh
	if mesh != null:
		var d := mesh.get_class()
		if mesh is QuadMesh or mesh is PlaneMesh:
			d += " %.2fx%.2f" % [mesh.size.x, mesh.size.y]
		elif mesh is BoxMesh:
			d += " %.2fx%.2fx%.2f" % [mesh.size.x, mesh.size.y, mesh.size.z]
		elif mesh is CylinderMesh:
			d += " r%.2f h%.2f" % [mesh.top_radius, mesh.height]
		bits.append(d)
	var mat := mi.material_override
	if mat is BaseMaterial3D:
		var bm := mat as BaseMaterial3D
		bits.append("albedo=%s" % bm.albedo_color.to_html())
		if bm.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED:
			bits.append("BILLBOARD keep_scale=%s" % str(bm.billboard_keep_scale))
	elif mat is ShaderMaterial:
		bits.append("ShaderMaterial")
	if mi.scale != Vector3.ONE:
		bits.append("scale=%.2f,%.2f,%.2f" % [mi.scale.x, mi.scale.y, mi.scale.z])
	return " ".join(bits)

func _screen_bbox(vi: VisualInstance3D, cam: Camera3D) -> Rect2:
	## Screen-space bbox of a 3D instance as it is ACTUALLY RASTERISED.
	##
	## A billboarded quad is the whole reason this instrument exists, and its
	## world AABB is a lie: the billboard basis is rebuilt in the vertex
	## shader from the camera, and with billboard_keep_scale = false (Godot's
	## default) the node's own scale is normalised away too. Projecting the
	## AABB of such a node reports a rect that is nowhere on screen. So:
	## billboards are measured in the camera's own right/up basis, everything
	## else by its eight world-AABB corners.
	var xf := vi.global_transform
	var bb := _billboard_quad_size(vi)
	if bb != Vector2.ZERO:
		if cam.is_position_behind(xf.origin):
			return Rect2()
		var cb := cam.global_transform.basis
		var right := cb.x * (bb.x * 0.5)
		var up := cb.y * (bb.y * 0.5)
		var lo_b := Vector2.INF
		var hi_b := -Vector2.INF
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var p := cam.unproject_position(xf.origin + right * sx + up * sy)
				lo_b = lo_b.min(p)
				hi_b = hi_b.max(p)
		return Rect2(lo_b, hi_b - lo_b)
	var aabb := vi.get_aabb()
	var lo := Vector2.INF
	var hi := -Vector2.INF
	for i in 8:
		var corner := xf * (aabb.position + Vector3(
			aabb.size.x * float(i & 1),
			aabb.size.y * float((i >> 1) & 1),
			aabb.size.z * float((i >> 2) & 1)))
		if cam.is_position_behind(corner):
			return Rect2()
		var p := cam.unproject_position(corner)
		lo = lo.min(p)
		hi = hi.max(p)
	return Rect2(lo, hi - lo)

func _billboard_quad_size(vi: VisualInstance3D) -> Vector2:
	## World-space width/height of a billboarded flat mesh, or ZERO if the
	## node is not one. Honours billboard_keep_scale (off = scale ignored,
	## which is exactly the trap that froze a "weapon-trail" tween).
	if not (vi is MeshInstance3D):
		return Vector2.ZERO
	var mi := vi as MeshInstance3D
	var mat := mi.material_override
	if not (mat is BaseMaterial3D):
		return Vector2.ZERO
	var bm := mat as BaseMaterial3D
	if bm.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED:
		return Vector2.ZERO
	var mesh := mi.mesh
	if not (mesh is QuadMesh or mesh is PlaneMesh):
		return Vector2.ZERO
	var sz: Vector2 = mesh.size
	if bm.billboard_keep_scale:
		var s := mi.global_transform.basis.get_scale()
		sz = Vector2(sz.x * s.x, sz.y * s.y)
	return sz

# ── Input synthesis ────────────────────────────────────────────────────────
## parse_input_event feeds events as-if-from-the-OS, i.e. in window
## coordinates; unproject() is in canvas coordinates. Calibrate the
## canvas->window transform empirically so stretch/HiDPI differences can
## never break the click math.
func _calibrate_input() -> bool:
	var vp := get_viewport()
	get_window().grab_focus()
	await get_tree().process_frame
	var probe := Vector2(41.0, 57.0)
	for cand in [vp.get_final_transform(), Transform2D.IDENTITY]:
		_last_input_pos = Vector2(-1e9, -1e9)
		var mm := InputEventMouseMotion.new()
		mm.position = (cand as Transform2D) * probe
		mm.global_position = mm.position
		Input.parse_input_event(mm)
		await get_tree().process_frame
		await get_tree().process_frame
		print("E2E DEBUG calib sent=%s seen=%s vp_mouse=%s final=%s win=%s" % [
			str(mm.position), str(_last_input_pos), str(vp.get_mouse_position()),
			str(vp.get_final_transform()), str(get_window().size)])
		if _last_input_pos.distance_to(probe) < 2.0:
			_to_window = cand
			return true
	return false

func _click_at(canvas_pos: Vector2) -> void:
	var wpos := _to_window * canvas_pos
	var mm := InputEventMouseMotion.new()
	mm.position = wpos
	mm.global_position = wpos
	Input.parse_input_event(mm)
	await get_tree().process_frame
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	down.position = wpos
	down.global_position = wpos
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = wpos
	up.global_position = wpos
	Input.parse_input_event(up)
	await get_tree().process_frame
	await get_tree().process_frame

func _click_control(c: Control) -> void:
	await _click_at(c.get_global_rect().get_center())

func _press_key(keycode: Key) -> void:
	## One key tap through the real input pipeline (parse_input_event).
	var down := InputEventKey.new()
	down.keycode = keycode
	down.physical_keycode = keycode
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := InputEventKey.new()
	up.keycode = keycode
	up.physical_keycode = keycode
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame
	await get_tree().process_frame


func _press_cmd_z() -> void:
	## Cmd/Ctrl+Z through the real input pipeline — both modifier flags set so
	## is_command_or_control_pressed() holds on every platform.
	var down := InputEventKey.new()
	down.keycode = KEY_Z
	down.physical_keycode = KEY_Z
	down.ctrl_pressed = true
	down.meta_pressed = true
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := InputEventKey.new()
	up.keycode = KEY_Z
	up.physical_keycode = KEY_Z
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame
	await get_tree().process_frame


func _move_mouse(canvas_pos: Vector2) -> void:
	## Park the cursor at a canvas position (real motion event, no click) —
	## the hover path under test IS this event stream.
	var wpos := _to_window * canvas_pos
	var mm := InputEventMouseMotion.new()
	mm.position = wpos
	mm.global_position = wpos
	Input.parse_input_event(mm)
	await get_tree().process_frame
	await get_tree().process_frame


## Hover a board square until pred holds — motion is re-sent each attempt
## (hover picking is throttled, and a lone event can race the throttle).
func _hover_square_until(game: Node, sq: Vector2i, pred: Callable,
		attempts := 4) -> bool:
	var board: Node = game.get("board")
	var cam := get_viewport().get_camera_3d()
	for i in attempts:
		await _move_mouse(cam.unproject_position(board.square_to_world(sq)))
		if await _wait_until(pred, 1.0):
			return true
	return false

# ── Game accessors ─────────────────────────────────────────────────────────
func _game() -> Node:
	var cs := get_tree().current_scene
	if cs != null and cs.get("state") != null and cs.get("board") != null:
		return cs
	return null

func _select_screen() -> Control:
	var cs := get_tree().current_scene
	if cs == null:
		return null
	if cs is HouseSelect:
		return cs
	return cs.find_child("HouseSelect", true, false) as Control

func _find_button(root: Node, needle: String) -> Button:
	for b: Button in root.find_children("*", "Button", true, false):
		var label := str(b.get_meta("label")) if b.has_meta("label") else b.text
		if label.contains(needle):
			return b
	return null

func _black_snapshot(state: Object) -> String:
	var parts: PackedStringArray = []
	for i in 64:
		var p = state.pieces[i]
		if p != null and ChessState.piece_color(p):
			parts.append("%d%s" % [i, p])
	return ",".join(parts)

func _click_square(game: Node, sq: Vector2i) -> void:
	var board: Node = game.get("board")
	var world: Vector3 = board.square_to_world(sq)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		print("E2E WARN no active Camera3D for square click %s" % str(sq))
		return
	var canvas := cam.unproject_position(world)
	print("E2E DEBUG sq=%s world=%s canvas=%s pick_roundtrip=%s behind=%s" % [
		str(sq), str(world), str(canvas), str(board.pick_square(canvas)),
		str(cam.is_position_behind(world))])
	await _click_at(canvas)
	print("E2E DEBUG post-click seen=%s selected=%s busy=%s" % [
		str(_last_input_pos), str(game.get("selected")), str(game.get("busy"))])

## Click a square until it is the selected one (a human would re-click too).
func _select_square(game: Node, sq: Vector2i, attempts: int = 3) -> bool:
	for i in attempts:
		await _click_square(game, sq)
		if await _wait_until(func(): return game.get("selected") == sq, 1.5):
			return true
		print("E2E WARN select attempt %d/%d for %s failed (selected=%s) — retrying"
			% [i + 1, attempts, str(sq), str(game.get("selected"))])
		await _sleep(0.6)
	return false

# ── Visual-space geometry (convention-INDEPENDENT board truth) ─────────────
## Chess truth is a SCREEN property: from White's seat, a1 is the bottom-left
## board corner, files ascend left-to-right, White sits nearest. The helpers
## below locate "visual squares" purely from (a) the board slab's fixed world
## AABB and (b) which of its corners land where ON SCREEN through the live
## camera. No sq_of, no square_to_world, no engine indices — a global mirror
## in ANY game layer (mapping, spawn, camera) fails these assertions; it can
## never pass self-consistently the way engine-frame checks can (the
## 2026-08-08 scar this section was built from).

const VIS_BOARD_HALF := 4.0   # 8 tiles x 1.0, slab centered on the Board node
const VIS_TILE_TOP := 0.22

## Anchor corners of the board top face, named BY SCREEN GEOMETRY:
## [0] screen bottom-left corner (chess truth: a1's outer corner),
## [1] screen bottom-right (h1's), [2] the far corner adjacent to [0] (a8's).
func _visual_anchors(game: Node) -> Array:
	var board: Node3D = game.get("board")
	var cam := get_viewport().get_camera_3d()
	var corners: Array = []
	for xs in [-1.0, 1.0]:
		for zs in [-1.0, 1.0]:
			corners.append(board.to_global(
				Vector3(VIS_BOARD_HALF * xs, VIS_TILE_TOP, VIS_BOARD_HALF * zs)))
	corners.sort_custom(func(a, b):
		return cam.unproject_position(a).y > cam.unproject_position(b).y)
	var bl: Vector3 = corners[0]
	var br: Vector3 = corners[1]
	if cam.unproject_position(bl).x > cam.unproject_position(br).x:
		var t := bl
		bl = br
		br = t
	# Of the two far corners, a8's is the one whose offset from a1's corner is
	# perpendicular to the near edge (the diagonal corner dots ~0.7).
	var far_adj: Vector3 = corners[2]
	if absf((corners[2] - bl).normalized().dot((br - bl).normalized())) > 0.5:
		far_adj = corners[3]
	return [bl, br, far_adj]

func _visual_ij(square_name: String) -> Vector2i:
	return Vector2i(square_name[0].unicode_at(0) - "a".unicode_at(0),
		int(square_name.substr(1)) - 1)

## World center of visual square (i files from screen-LEFT, j ranks from the
## NEAR edge), i/j 0..7 — visual-a1 is (0,0), visual-h1 (7,0), visual-a8 (0,7).
func _visual_square_world(game: Node, i: float, j: float) -> Vector3:
	var a := _visual_anchors(game)
	var right: Vector3 = (a[1] - a[0]) / 8.0
	var deep: Vector3 = (a[2] - a[0]) / 8.0
	return a[0] + right * (i + 0.5) + deep * (j + 0.5)

func _visual_name_world(game: Node, square_name: String) -> Vector3:
	var ij := _visual_ij(square_name)
	return _visual_square_world(game, float(ij.x), float(ij.y))

## Nearest visual square for a world position on the board top.
func _visual_of_world(game: Node, world: Vector3) -> Vector2i:
	var a := _visual_anchors(game)
	var right: Vector3 = (a[1] - a[0]) / 8.0
	var deep: Vector3 = (a[2] - a[0]) / 8.0
	var rel: Vector3 = world - a[0]
	return Vector2i(
		int(floor(rel.dot(right) / right.length_squared())),
		int(floor(rel.dot(deep) / deep.length_squared())))

## The piece view standing on a visual square (by its rendered world
## position), or null.
func _view_on_visual(game: Node, square_name: String) -> Node:
	var want := _visual_ij(square_name)
	var views: Dictionary = game.get("views")
	for sq in views:
		var pv = views[sq]
		if is_instance_valid(pv) \
				and _visual_of_world(game, (pv as Node3D).global_position) == want:
			return pv
	return null

func _assert_visual_royal(game: Node, square_name: String, want_type: int,
		want_crown: bool) -> bool:
	var pv := _view_on_visual(game, square_name)
	if pv == null:
		await _fail("visual-royal-%s" % square_name,
			"no piece view standing on visual %s" % square_name)
		return false
	if int(pv.get("piece_type")) != want_type:
		await _fail("visual-royal-%s" % square_name, "piece_type %d on visual %s, expected %d"
			% [int(pv.get("piece_type")), square_name, want_type])
		return false
	var crowned: bool = not pv.find_children("Crown", "", true, false).is_empty()
	if crowned != want_crown:
		await _fail("visual-royal-%s" % square_name, "crown %s on visual %s, expected %s"
			% [str(crowned), square_name, str(want_crown)])
		return false
	return true

## Click a visual square by SCREEN position (never through sq_of).
func _click_visual(game: Node, square_name: String) -> void:
	var cam := get_viewport().get_camera_3d()
	await _click_at(cam.unproject_position(_visual_name_world(game, square_name)))

## Where the selection highlight quad sits, in visual coords (or (-9,-9)).
func _selection_visual(game: Node) -> Vector2i:
	var board: Node = game.get("board")
	var quad: Node3D = board.get("_select_quad")
	if quad == null or not quad.visible:
		return Vector2i(-9, -9)
	return _visual_of_world(game, quad.global_position)

## Select a visual square via real clicks; the proof of selection is the
## rendered highlight quad standing on that same visual square.
func _select_visual(game: Node, square_name: String, attempts: int = 3) -> bool:
	var want := _visual_ij(square_name)
	for i in attempts:
		await _click_visual(game, square_name)
		if await _wait_until(func(): return _selection_visual(game) == want, 1.5):
			return true
		print("E2E WARN visual select attempt %d/%d for %s failed (quad at %s) — retrying"
			% [i + 1, attempts, square_name, str(_selection_visual(game))])
		await _sleep(0.6)
	return false

## Visible legal-move markers, as visual squares.
func _visible_marker_visuals(game: Node) -> Array[Vector2i]:
	var board: Node = game.get("board")
	var out: Array[Vector2i] = []
	for q in board.get_node("MoveMarkers").get_children():
		if q.visible:
			var v := _visual_of_world(game, (q as Node3D).global_position)
			if not out.has(v):
				out.append(v)
	return out

func _visual_set(names: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for n in names:
		out.append(_visual_ij(str(n)))
	return out

func _visual_names(squares: Array[Vector2i]) -> String:
	var parts: PackedStringArray = []
	for v in squares:
		if v.x >= 0 and v.x < 8 and v.y >= 0 and v.y < 8:
			parts.append("%s%d" % [char("a".unicode_at(0) + v.x), v.y + 1])
		else:
			parts.append(str(v))
	return ",".join(parts)

## Mean 3x3 luminance of the RENDERED frame at a world point (canvas coords
## go through the calibrated canvas->window transform, same as clicks).
func _sample_lum(img: Image, cam: Camera3D, world: Vector3) -> float:
	var p := _to_window * cam.unproject_position(world)
	var sum := 0.0
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var c := img.get_pixelv(Vector2i(
				clampi(int(p.x) + dx, 0, img.get_width() - 1),
				clampi(int(p.y) + dy, 0, img.get_height() - 1)))
			sum += c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
	return sum / 9.0

# ── The Hall of Banners (house select) by clicks ───────────────────────────
func _navigate_select(house_id: String, opponent_needle: String, mode_needle: String) -> bool:
	if not await _wait_until(func(): return _select_screen() != null, 15.0):
		await _fail("select-screen", "the Hall of Banners never appeared")
		return false
	var sel: Control = _select_screen()
	await _sleep(0.4)   # deferred ring layout + first draw
	await _shot("house_select")
	var crest: Node = sel.find_child("Crest_%s" % house_id, true, false)
	if crest == null:
		await _fail("select-crest", "no crest for house '%s'" % house_id)
		return false
	if not await _click_until(crest.get_node("Sigil"),
			func(): return int(sel.get("phase")) == 1, "crest"):
		await _fail("select-house", "crest clicks never advanced to the opponent phase")
		return false
	_pass("select-house (%s)" % house_id)
	var opp_btn := _find_button(sel, opponent_needle)
	if opp_btn == null:
		await _fail("select-opponent", "no opponent button matching '%s'" % opponent_needle)
		return false
	if not await _click_until(opp_btn,
			func(): return int(sel.get("phase")) == 2, "opponent"):
		await _fail("select-opponent", "opponent clicks never advanced to the mode phase")
		return false
	_pass("select-opponent (%s)" % opponent_needle)
	var mode_btn := _find_button(sel, mode_needle)
	if mode_btn == null:
		await _fail("select-mode", "no mode button matching '%s'" % mode_needle)
		return false
	await _click_control(mode_btn)
	if not await _wait_until(func(): return _game() != null, 15.0):
		await _fail("select-into-game", "the game scene never appeared after selection")
		return false
	_pass("select-into-game")
	return true

## Click a control until pred holds (the _select_square retry philosophy —
## a human would re-click a missed button too; select-screen clicks flaked
## one-off under environment focus churn, 2026-08-08).
func _click_until(c: Control, pred: Callable, what: String, attempts := 3) -> bool:
	for i in attempts:
		await _click_control(c)
		if await _wait_until(pred, 3.0):
			return true
		print("E2E WARN %s click %d/%d did not land — retrying" % [what, i + 1, attempts])
		await _sleep(0.5)
	return false

# ── Shared boot steps ──────────────────────────────────────────────────────
func _boot_game(expected_pieces: int) -> Node:
	var got := await _wait_until(func(): return _game() != null, 20.0)
	if not got:
		await _fail("game-scene-loaded", "game root with state+board never appeared")
		return null
	var game := _game()
	_pass("game-scene-loaded")
	var state: Object = game.get("state")
	var engine_count := 0
	for i in 64:
		if state.pieces[i] != null:
			engine_count += 1
	if expected_pieces > 0 and engine_count != expected_pieces:
		await _fail("boot-engine-pieces",
			"engine holds %d pieces, expected %d" % [engine_count, expected_pieces])
		return null
	var views: Dictionary = game.get("views")
	if views.size() != engine_count:
		await _fail("boot-views-match",
			"%d piece views for %d engine pieces" % [views.size(), engine_count])
		return null
	var standing := 0
	for sq in views:
		var pv: Node = views[sq]
		if is_instance_valid(pv) and pv.get_child_count() > 0:
			standing += 1
	if standing != engine_count:
		await _fail("boot-pieces-standing",
			"only %d/%d piece views have a model" % [standing, engine_count])
		return null
	_pass("boot-pieces-standing (%d)" % standing)
	return game

## Board/view sync: every engine piece has a live view on its square and no
## orphan views linger. `allow_missing_king` covers the post-checkmate state
## where the mated king's view died under the cinematic.
func _assert_sync(game: Node, step: String, allow_missing_king := false) -> bool:
	var state: Object = game.get("state")
	var views: Dictionary = game.get("views")
	var engine_count := 0
	var missing: Array[String] = []
	for i in 64:
		if state.pieces[i] == null:
			continue
		engine_count += 1
		var sq: Vector2i = game.sq_of(i)
		var pv = views.get(sq)
		if pv == null or not is_instance_valid(pv):
			missing.append("%s(%s)" % [ChessState.square_get_name(i), str(state.pieces[i])])
	if allow_missing_king and missing.size() == 1 \
			and (missing[0].contains("(k)") or missing[0].contains("(K)")):
		missing.clear()
		engine_count -= 1
	if not missing.is_empty() or views.size() != engine_count:
		await _fail(step, "desync: views=%d engine=%d missing=[%s]"
			% [views.size(), engine_count, ",".join(missing)])
		return false
	return true

# ── Scenario: boot ─────────────────────────────────────────────────────────
func _scenario_boot() -> void:
	if not await _navigate_select(DEFAULT_HOUSE, "Casual", "Single Match"):
		return
	var game := await _boot_game(32)
	if game == null:
		return
	# The hall wears the chosen house's dye (banner 3 = west wall, player).
	var hall: Node = game.get_node_or_null("GreatHall")
	var expect: Color = HouseRegistry.get_colors(DEFAULT_HOUSE)["primary"]
	var got: Color = hall.get_banner(3).house_color
	if not _colors_close(got, expect):
		await _fail("boot-banners-dressed", "west banner %s, expected %s" % [got, expect])
		return
	_pass("boot-banners-dressed")
	var title: Label = game.find_child("Title", true, false)
	if title == null or not title.text.contains(DEFAULT_HOUSE.to_upper()):
		await _fail("boot-hud-houses", "HUD title missing the chosen house: '%s'"
			% (title.text if title != null else "<no Title>"))
		return
	_pass("boot-hud-houses")
	if not await _assert_hover_glyphs(game):
		return
	await _sleep(1.0)   # let idles and torchlight settle for the screenshot
	await _shot("boot_lineup")
	_finish(0)


## Hover-only glyph rings (ISSUES.md #2), driven through the REAL input path:
## every ring hidden at rest, hover reveals exactly the piece under the
## cursor, selection holds its ring lit at beacon energy, and leaving the
## square (with nothing selected) fades the ring back out.
func _assert_hover_glyphs(game: Node) -> bool:
	var views: Dictionary = game.get("views")
	var lit_at_rest := 0
	for sq in views:
		if bool((views[sq] as Node).get("_ring_shown")):
			lit_at_rest += 1
	if lit_at_rest != 0:
		await _fail("glyph-hidden-at-rest",
			"%d glyph rings lit before any hover" % lit_at_rest)
		return false
	_pass("glyph-hidden-at-rest (0/%d rings lit)" % views.size())
	var e2_sq: Vector2i = game.sq_of(ChessState.square_index_from_name("e2"))
	var e4_sq: Vector2i = game.sq_of(ChessState.square_index_from_name("e4"))
	var pv_e2: Node = views.get(e2_sq)
	if pv_e2 == null:
		await _fail("glyph-hover-target", "no piece view on e2 to hover")
		return false
	if not await _hover_square_until(game, e2_sq,
			func(): return bool(pv_e2.get("_ring_shown"))):
		await _fail("glyph-hover-reveal", "hovering e2 never revealed its glyph ring")
		return false
	_pass("glyph-hover-reveal (e2 ring fades in under the cursor)")
	# Leaving for the empty e4 square fades the pawn's ring back out.
	if not await _hover_square_until(game, e4_sq,
			func(): return not bool(pv_e2.get("_ring_shown"))):
		await _fail("glyph-hover-hide", "leaving e2 never hid its glyph ring")
		return false
	_pass("glyph-hover-hide (ring gone on leave)")
	# Selection keeps the ring lit at beacon energy (the set_selected path).
	if not await _select_square(game, e2_sq):
		await _fail("glyph-select", "e2 never became the selected square")
		return false
	var rest_energy: float = PieceAssets.GLYPH_ENERGY_REST
	if not await _wait_until(func():
		return bool(pv_e2.get("_ring_shown")) \
			and (pv_e2.get("_glyph_mat") as StandardMaterial3D) \
			.emission_energy_multiplier > rest_energy + 0.5, 3.0):
		await _fail("glyph-selected-lit", "selected e2 ring not lit at beacon energy")
		return false
	_pass("glyph-selected-lit (selection holds the ring)")
	# Deselect via the second click; the cursor still rests on e2, so the
	# hover layer keeps the ring shown — hovering away finally hides it.
	await _click_square(game, e2_sq)
	if not await _wait_until(func(): return game.get("selected") == null, 3.0):
		await _fail("glyph-deselect", "second e2 click never cleared the selection")
		return false
	if not await _hover_square_until(game, e4_sq,
			func(): return not bool(pv_e2.get("_ring_shown"))):
		await _fail("glyph-deselect-hide", "ring stayed lit after deselect + leave")
		return false
	_pass("glyph-deselect-hide (rest state restored)")
	return true

# ── Scenario: orientation (labeled-overlay tiebreaker) ─────────────────────
## Launched WITH --debug-coords: the game renders the engine's own belief of
## files/ranks/royal squares as world-space labels; this scenario walks the
## real select flow (default player camera, no shortcuts) and saves the frame
## as labeled.png — a permanent, human-auditable orientation artifact every
## run. The assertion is intentionally thin: the labels exist and the shot
## saved. The PICTURE is the check — conventions can be self-consistently
## wrong, a labeled photograph cannot.
func _scenario_orientation() -> void:
	if not await _navigate_select(DEFAULT_HOUSE, "Casual", "Single Match"):
		return
	var game := await _boot_game(32)
	if game == null:
		return
	if game.get_node_or_null("DebugCoords") == null:
		await _fail("orientation-overlay",
			"no DebugCoords node — was --debug-coords passed to the launch?")
		return
	_pass("orientation-overlay-present")
	await _sleep(1.2)   # idles + label render settle
	await _await_drawn()
	var img := get_viewport().get_texture().get_image()
	if img == null:
		await _fail("orientation-shot", "no viewport image for labeled.png")
		return
	var path := artifacts_dir + "/labeled.png"
	if img.save_png(path) != OK:
		await _fail("orientation-shot", "could not save %s" % path)
		return
	_pass("orientation-labeled-shot (%s)" % path)
	_finish(0)

# ── Scenario: board-truth ──────────────────────────────────────────────────
## The rendered board must BE a correct chessboard AS A HUMAN SEES IT. The
## primary assertions are convention-INDEPENDENT: squares are located by
## screen geometry (visual-a1 = the board polygon's bottom-left corner from
## the default player camera), colors are sampled from the actual rendered
## pixels, royals are found by their rendered world positions. Engine-frame
## crosschecks (tile nodes vs square_is_dark) are kept as a SECONDARY layer —
## they catch parity regressions but, unlike the visual layer, a globally
## mirrored convention could pass them self-consistently (the 2026-08-08
## scar: 20/20 green while the user saw a wrong board).
func _scenario_board_truth() -> void:
	if not await _navigate_select(DEFAULT_HOUSE, "Casual", "Single Match"):
		return
	var game := await _boot_game(32)
	if game == null:
		return
	var board: Node = game.get("board")
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		await _fail("board-camera", "no active Camera3D")
		return
	await _sleep(1.0)   # idles settle before the frame we sample
	# 1) VISUAL: White (the player's FROST side) is seated nearest the
	#    camera — every piece in visual ranks 1-2 is FROST, ranks 7-8 EMBER.
	#    This is the orbit camera's default-yaw contract, checked by pixels'
	#    own geometry, not by yaw value.
	var views: Dictionary = game.get("views")
	var seat_wrong: Array[String] = []
	for sq in views:
		var pv: Node3D = views[sq]
		if not is_instance_valid(pv):
			continue
		var v := _visual_of_world(game, pv.global_position)
		if v.y <= 1 and int(pv.get("side")) != PieceView.House.FROST:
			seat_wrong.append("rival piece near at %s" % _visual_names([v]))
		elif v.y >= 6 and int(pv.get("side")) != PieceView.House.EMBER:
			seat_wrong.append("player piece far at %s" % _visual_names([v]))
		elif v.y > 1 and v.y < 6:
			seat_wrong.append("piece adrift mid-board at %s" % _visual_names([v]))
	if not seat_wrong.is_empty():
		await _fail("board-white-seated-near", "%d/32 misplaced (first: %s)"
			% [seat_wrong.size(), seat_wrong[0]])
		return
	_pass("board-white-seated-near (player army fills visual ranks 1-2)")
	# 2) VISUAL: rendered-pixel checkerboard. Sample the empty middle (visual
	#    ranks 3-6) from the actual frame: with a1 dark, a tile at (i,j) is
	#    dark iff (i+j) is even, so every adjacent pair must alternate luminance.
	await _await_drawn()
	var img := get_viewport().get_texture().get_image()
	if img == null:
		await _fail("board-pixel-parity", "no viewport image to sample")
		return
	var pair_wrong: Array[String] = []
	for j in range(2, 6):
		for i in range(0, 7):
			var l0 := _sample_lum(img, cam, _visual_square_world(game, float(i), float(j)))
			var l1 := _sample_lum(img, cam, _visual_square_world(game, float(i + 1), float(j)))
			var dark_left := (i + j) % 2 == 0
			if absf(l0 - l1) < 0.01 or dark_left != (l0 < l1):
				pair_wrong.append("%s=%.3f vs %s=%.3f" % [
					_visual_names([Vector2i(i, j)]), l0,
					_visual_names([Vector2i(i + 1, j)]), l1])
	if not pair_wrong.is_empty():
		await _fail("board-pixel-parity", "%d/28 adjacent pairs wrong (first: %s)"
			% [pair_wrong.size(), pair_wrong[0]])
		return
	_pass("board-pixel-parity (28/28 rendered pairs alternate, a1-parity dark)")
	# 3) VISUAL: the two user-facing color truths, sampled on the tile strip
	#    in front of the rank-1 pieces: a1 darker than b1, d1 (queen's
	#    square) LIGHTER than e1 — the queen stands on her color.
	var lum_a1 := _sample_lum(img, cam, _visual_square_world(game, 0.0, -0.38))
	var lum_b1 := _sample_lum(img, cam, _visual_square_world(game, 1.0, -0.38))
	var lum_d1 := _sample_lum(img, cam, _visual_square_world(game, 3.0, -0.38))
	var lum_e1 := _sample_lum(img, cam, _visual_square_world(game, 4.0, -0.38))
	if not (lum_a1 < lum_b1 - 0.005):
		await _fail("board-a1-dark", "a1 strip %.3f !< b1 strip %.3f" % [lum_a1, lum_b1])
		return
	if not (lum_d1 > lum_e1 + 0.005):
		await _fail("board-queen-on-her-color",
			"d1 strip %.3f !> e1 strip %.3f — the queen's square must be light"
			% [lum_d1, lum_e1])
		return
	_pass("board-a1-dark · board-queen-on-her-color (rendered strips)")
	# 4) VISUAL royals both sides, located by rendered position: uncrowned
	#    (tiara-only) queen on visual d1/d8, crowned king on visual e1/e8.
	for check in [["d1", PieceView.Type.QUEEN, false], ["e1", PieceView.Type.KING, true],
			["d8", PieceView.Type.QUEEN, false], ["e8", PieceView.Type.KING, true]]:
		if not await _assert_visual_royal(game, str(check[0]), int(check[1]), bool(check[2])):
			return
	_pass("board-royals (visual: queen d1/d8 uncrowned · king e1/e8 crowned)")
	# 5) ENGINE crosscheck: all 64 tile nodes wear the engine's stone.
	var wrong: Array[String] = []
	for idx in 64:
		var sq: Vector2i = game.sq_of(idx)
		var tile: MeshInstance3D = board.get_node_or_null(
			"Tiles/Tile_%d_%d" % [sq.x, sq.y])
		if tile == null:
			await _fail("board-tile-parity", "no tile node for %s (view sq %s)"
				% [ChessState.square_get_name(idx), str(sq)])
			return
		var want: Color = board.DARK_STONE if ChessState.square_is_dark(idx) \
			else board.LIGHT_STONE
		var got: Color = (tile.material_override as StandardMaterial3D).albedo_color
		if not _colors_close(got, want):
			wrong.append(ChessState.square_get_name(idx))
	if not wrong.is_empty():
		await _fail("board-tile-parity", "%d/64 tiles wear the wrong stone (first: %s)"
			% [wrong.size(), ",".join(wrong.slice(0, 8))])
		return
	_pass("board-tile-parity (64/64 tile nodes match engine square colors)")
	await _shot("board_truth_startpos")
	_finish(0)

# ── Scenario: board-moves ──────────────────────────────────────────────────
## FEN contract (run_e2e.sh BOARD_FEN): White to move, Qd1 + Ke1, O-O legal
## (O-O-O is truthfully blocked — the queen herself holds d1). Convention-
## INDEPENDENT throughout: visual squares are clicked by SCREEN position and
## the surfaced highlight markers are read back as visual squares, compared
## against the humanly-computed movesets for that FEN. No engine indices
## anywhere in the assertions — a mirrored mapping fails here, loudly.
##
## Hand-derived truth for BOARD_FEN (Ra1 Qd1 Ke1 Rh1, Pd2 Pe2):
##   king e1  -> f1, f2, g1 (O-O hop; d1/d2/e2 blocked by own pieces,
##               O-O-O blocked by the queen herself)
##   queen d1 -> c1, b1 (a1 rook stops the file), c2, b3, a4 (long diagonal;
##               d2/e2 own pawns block north and north-east)
const KING_E1_VISUAL := ["f1", "f2", "g1"]
const QUEEN_D1_VISUAL := ["c1", "b1", "c2", "b3", "a4"]

func _scenario_board_moves() -> void:
	if not await _navigate_select(DEFAULT_HOUSE, "Casual", "Single Match"):
		return
	var game := await _boot_game(0)
	if game == null:
		return
	var state: Object = game.get("state")
	if not await _wait_until(func():
		return game.get("busy") == false and state.turn == false, 15.0):
		await _fail("board-moves-turn", "never became the player's turn")
		return
	if not await _assert_visual_royal(game, "d1", PieceView.Type.QUEEN, false) \
			or not await _assert_visual_royal(game, "e1", PieceView.Type.KING, true):
		return
	_pass("board-moves-royals (visual: tiara'd queen d1 · crowned king e1)")
	# The crowned piece, clicked where a human sees it: exactly the king's
	# moves, including the two-file O-O hop to visual g1.
	if not await _select_visual(game, "e1"):
		await _fail("board-moves-select-king",
			"clicking visual e1 never selected it (highlight quad elsewhere)")
		return
	var shown := _visible_marker_visuals(game)
	if not _same_squares(shown, _visual_set(KING_E1_VISUAL)):
		await _fail("board-moves-king-set",
			"crowned piece highlights visual [%s], chess truth says [%s]"
			% [_visual_names(shown), ",".join(KING_E1_VISUAL)])
		return
	await _shot("king_highlights")
	_pass("board-moves-king (visual e1 shows exactly %s)" % ",".join(KING_E1_VISUAL))
	# The hooded queen on visual d1: exactly the queen's moves, with the long
	# a4 diagonal proving queen-range rays.
	if not await _select_visual(game, "d1"):
		await _fail("board-moves-select-queen",
			"clicking visual d1 never selected it (highlight quad elsewhere)")
		return
	shown = _visible_marker_visuals(game)
	if not _same_squares(shown, _visual_set(QUEEN_D1_VISUAL)):
		await _fail("board-moves-queen-set",
			"queen highlights visual [%s], chess truth says [%s]"
			% [_visual_names(shown), ",".join(QUEEN_D1_VISUAL)])
		return
	var origin := _visual_ij("d1")
	var longest := 0
	for v in shown:
		longest = maxi(longest, maxi(absi(v.x - origin.x), absi(v.y - origin.y)))
	if longest < 3:
		await _fail("board-moves-queen-ray",
			"no long queen ray on screen (longest visual span %d, need >=3)" % longest)
		return
	await _shot("queen_highlights")
	_pass("board-moves-queen (visual d1 shows exactly %s, ray span %d)"
		% [",".join(QUEEN_D1_VISUAL), longest])
	_finish(0)

func _same_squares(a: Array[Vector2i], b: Array[Vector2i]) -> bool:
	if a.size() != b.size():
		return false
	for sq in a:
		if not b.has(sq):
			return false
	return true

# ── Scenario: move ─────────────────────────────────────────────────────────
func _scenario_move() -> void:
	if not await _navigate_select(DEFAULT_HOUSE, "Casual", "Single Match"):
		return
	var game := await _boot_game(32)
	if game == null:
		return
	var state: Object = game.get("state")
	if not await _wait_until(func():
		return game.get("busy") == false and state.turn == false, 15.0):
		await _fail("move-player-turn", "never became the player's turn")
		return
	_pass("move-player-turn")
	var e2 := ChessState.square_index_from_name("e2")
	var e4 := ChessState.square_index_from_name("e4")
	if state.pieces[e2] != "P":
		await _fail("move-e2-white-pawn", "e2 holds '%s', not a white pawn" % str(state.pieces[e2]))
		return
	_pass("move-e2-white-pawn")
	var e2_sq: Vector2i = game.sq_of(e2)
	var e4_sq: Vector2i = game.sq_of(e4)
	if not await _select_square(game, e2_sq):
		await _fail("move-select-pawn", "e2 never became the selected square")
		return
	_pass("move-select-pawn")
	await _shot("pawn_selected")
	var black_before := _black_snapshot(state)
	await _click_square(game, e4_sq)
	if not await _wait_until(func():
		return state.pieces[e2] == null and state.pieces[e4] == "P", 5.0):
		await _fail("move-pawn-e4", "engine never showed the pawn on e4")
		return
	_pass("move-pawn-e4")
	await _shot("after_e4")
	if not await _wait_until(func():
		return state.turn == false and _black_snapshot(state) != black_before, 30.0):
		await _fail("move-ai-replied", "AI did not reply within 30s")
		return
	_pass("move-ai-replied")
	if not await _wait_until(func(): return game.get("busy") == false, 15.0):
		await _fail("move-anim-settled", "reply animation never finished")
		return
	_pass("move-anim-settled")
	await _shot("after_ai_reply")
	_finish(0)

# ── Shared: wait for the player's turn, find + click a scripted move ───────
func _ready_for_scripted_move(prefix: String) -> Node:
	var game := await _boot_game(0)   # custom FEN — piece count varies
	if game == null:
		return null
	var state: Object = game.get("state")
	if not await _wait_until(func():
		return game.get("busy") == false and state.turn == false, 15.0):
		await _fail(prefix + "-player-turn", "never became the player's turn")
		return null
	_pass(prefix + "-player-turn")
	return game

## Click from->to for the first legal move matching pred. Returns the move.
func _click_first_matching(game: Node, pred: Callable, prefix: String) -> Variant:
	var state: Object = game.get("state")
	var move = null
	for m in state.legal_moves():
		if pred.call(m):
			move = m
			break
	if move == null:
		await _fail(prefix + "-move-available", "the FEN offers no matching move")
		return null
	_pass(prefix + "-move-available (%s)" % move.to_uci())
	if not await _select_square(game, game.sq_of(move.from_square)):
		await _fail(prefix + "-select", "%s never became the selected square"
			% str(game.sq_of(move.from_square)))
		return null
	_pass(prefix + "-select")
	await _click_square(game, game.sq_of(move.to_square))
	return move

func _settle(game: Node, step: String) -> bool:
	if not await _wait_until(func(): return game.get("busy") == false, 20.0):
		await _fail(step, "board never settled (busy stuck)")
		return false
	_pass(step)
	return true

# ── Scenario: castle ───────────────────────────────────────────────────────
func _scenario_castle() -> void:
	if not await _navigate_select(DEFAULT_HOUSE, "Casual", "Single Match"):
		return
	var game := await _ready_for_scripted_move("castle")
	if game == null:
		return
	var state: Object = game.get("state")
	var move = await _click_first_matching(game,
		func(m): return m.is_castling, "castle")
	if move == null:
		return
	var king_sq: Vector2i = game.sq_of(move.to_square)
	var rook_sq: Vector2i = game.sq_of(move.rook_to)
	if not await _wait_until(func():
		return state.pieces[move.to_square] == "K" \
			and state.pieces[move.rook_to] == "R", 5.0):
		await _fail("castle-engine-applied", "engine never applied %s" % move.to_uci())
		return
	_pass("castle-engine-applied")
	if not await _wait_until(func():
		var v: Dictionary = game.get("views")
		return v.has(king_sq) and v.has(rook_sq) \
			and v[king_sq].piece_type == PieceView.Type.KING \
			and v[rook_sq].piece_type == PieceView.Type.ROOK, 8.0):
		await _fail("castle-views-landed", "king/rook views never landed on %s/%s"
			% [str(king_sq), str(rook_sq)])
		return
	_pass("castle-views-landed")
	# VISUAL sanity (convention-independent): after O-O the crowned king must
	# STAND two squares right of where he started — on visual g1 — with the
	# rook having crossed him onto visual f1. CASTLE_FEN has no black rooks,
	# so these views are unambiguous.
	if not await _wait_until(func():
		var kv := _view_on_visual(game, "g1")
		var rv := _view_on_visual(game, "f1")
		return kv != null and int(kv.get("piece_type")) == PieceView.Type.KING \
			and rv != null and int(rv.get("piece_type")) == PieceView.Type.ROOK, 8.0):
		var king_at := "<none>"
		var views_now: Dictionary = game.get("views")
		for sq in views_now:
			var pv = views_now[sq]
			if is_instance_valid(pv) and int(pv.get("piece_type")) == PieceView.Type.KING \
					and int(pv.get("side")) == PieceView.House.FROST:
				king_at = _visual_names([_visual_of_world(game,
					(pv as Node3D).global_position)])
		await _fail("castle-visual-landing",
			"O-O did not put the king on visual g1 with the rook on visual f1 (king at %s)"
			% king_at)
		return
	_pass("castle-visual-landing (king visual g1 · rook visual f1)")
	await _shot("after_castle")
	if not await _settle(game, "castle-settled"):
		return
	_finish(0)

# ── Scenario: enpassant ────────────────────────────────────────────────────
## FEN contract (run_e2e.sh EP_FEN): "4k3/8/8/3pP3/8/8/8/4K3 w - d6" —
## White pawn e5, Black pawn d5 just double-stepped, exd6 e.p. available;
## black has ONLY the king besides, so nothing can recapture and the visual
## end-state is unambiguous. Clicks land by SCREEN position; the assertion is
## the humanly-correct outcome: the white pawn STANDS on visual d6, and both
## visual d5 (the captured pawn — NOT the destination square) and visual e5
## are empty. This is the classic mirror tell: only a correct mapping removes
## the pawn one square BEHIND the diagonal landing.
func _scenario_enpassant() -> void:
	if not await _navigate_select(DEFAULT_HOUSE, "Casual", "Single Match"):
		return
	var game := await _ready_for_scripted_move("ep")
	if game == null:
		return
	var state: Object = game.get("state")
	var ep_move = null
	for m in state.legal_moves():
		if m.en_passant:
			ep_move = m
			break
	if ep_move == null:
		await _fail("ep-move-available", "the FEN offers no en-passant capture")
		return
	_pass("ep-move-available (%s)" % ep_move.to_uci())
	if not await _select_visual(game, "e5"):
		await _fail("ep-select", "clicking visual e5 never selected the pawn")
		return
	_pass("ep-select (visual e5)")
	await _click_visual(game, "d6")
	# Engine truth first: pawn to d6, d5 AND e5 emptied.
	var d6 := ChessState.square_index_from_name("d6")
	var d5 := ChessState.square_index_from_name("d5")
	var e5 := ChessState.square_index_from_name("e5")
	if not await _wait_until(func():
		return str(state.pieces[d6]) == "P" and state.pieces[d5] == null \
			and state.pieces[e5] == null, 5.0):
		await _fail("ep-engine-applied",
			"engine state after click: d6=%s d5=%s e5=%s" % [
				str(state.pieces[d6]), str(state.pieces[d5]), str(state.pieces[e5])])
		return
	_pass("ep-engine-applied")
	# The capture duel + walk play out; then the VISUAL end-state.
	if not await _wait_until(func():
		var pv := _view_on_visual(game, "d6")
		return pv != null and int(pv.get("piece_type")) == PieceView.Type.PAWN \
			and int(pv.get("side")) == PieceView.House.FROST, 20.0):
		await _fail("ep-visual-landing", "no white pawn standing on visual d6")
		return
	_pass("ep-visual-landing (white pawn on visual d6)")
	if not await _settle(game, "ep-settled"):   # black king replies
		return
	if _view_on_visual(game, "d5") != null or _view_on_visual(game, "e5") != null:
		await _fail("ep-victim-removed",
			"a piece still stands on visual d5/e5 after the e.p. capture")
		return
	var views: Dictionary = game.get("views")
	if views.size() != 3:
		await _fail("ep-piece-count", "%d piece views remain, expected 3 (K, k, P)"
			% views.size())
		return
	_pass("ep-victim-removed (visual d5/e5 clear · 3 views remain)")
	await _shot("after_enpassant")
	_finish(0)

# ── Scenario: promote ──────────────────────────────────────────────────────
## ALBERT'S BUG, walked end to end on the real click path.
##
## FEN contract (run_e2e.sh PROMOTE_FEN) — and it is a CHESS PROBLEM, not a
## prop: "8/k1P4p/7P/1K6/8/8/8/8 w - - 0 1".
##   White Kb5, Pc7, Ph6 · Black Ka7, Ph7 (wedged behind h6 — it has no move).
## From c7 all four promotions are legal AND all four are different games:
##   c8=Q  covers b7 diagonally, Black has no move and is not in check
##         -> STALEMATE. The old "promotions auto-pick the queen" code could
##         only ever produce this one.
##   c8=R  same rank, same file, no diagonal -> b7 is free -> the war goes on.
##         Promoting to a ROOK is the only way to avoid the stalemate.
##   c8=N  a knight forks out to a7 -> CHECK, from a square where the queen
##         gives none.
##   c8=B  no check, no stalemate.
## The scenario takes ALL FOUR, one at a time, undoing back to the pawn in
## between — by clicking the piece model, by hotkey, by walking the row with
## the arrow keys, and finally by pressing Esc to prove the silent default is
## still the queen. tests/test_promotion.gd asserts the same chess headless.
func _scenario_promote() -> void:
	if not await _navigate_select(DEFAULT_HOUSE, "Casual", "Single Match"):
		return
	var game := await _ready_for_scripted_move("promote")
	if game == null:
		return
	var state: Object = game.get("state")
	var start_fen := str(state.get_fen())
	var c7 := ChessState.square_index_from_name("c7")
	var c8 := ChessState.square_index_from_name("c8")

	# The engine's own answer to "why does this matter", read off THIS board
	# before a single click — the proof and the position can never drift apart.
	var offered := {}
	for m in state.legal_moves():
		if m.promotion != null and m.from_square == c7:
			offered[str(m.promotion).to_lower()] = true
	if offered.size() != 4:
		await _fail("promote-four-offered",
			"the engine offers %d promotions from c7, expected 4" % offered.size())
		return
	_pass("promote-four-offered (q r b n)")
	var probe := {}
	for pc in ["q", "r", "b", "n"]:
		var s = ChessState.new()
		s.set_fen(start_fen)
		s.apply_move(s.move_from_uci("c7c8" + pc))
		probe[pc] = {"result": s.get_result(), "check": s.in_check()}
	var q_stalemates: bool = int(probe["q"]["result"]) == ChessState.RESULT.STALEMATE
	var r_survives: bool = int(probe["r"]["result"]) == ChessState.RESULT.ONGOING
	var n_checks: bool = bool(probe["n"]["check"]) and not bool(probe["q"]["check"])
	if not (q_stalemates and r_survives and n_checks):
		await _fail("promote-why-it-matters",
			"queen->%s rook->%s knight-check=%s queen-check=%s" % [
				ChessState.RESULT.keys()[int(probe["q"]["result"])],
				ChessState.RESULT.keys()[int(probe["r"]["result"])],
				str(probe["n"]["check"]), str(probe["q"]["check"])])
		return
	_pass("promote-why-it-matters (queen STALEMATES · rook does not · only the knight CHECKS)")

	# ── 1. the ROOK, by clicking the piece model ───────────────────────────
	if not await _promote_as(game, "r", "click", start_fen):
		return
	if int(state.get_result()) != ChessState.RESULT.ONGOING:
		await _fail("promote-rook-avoids-stalemate",
			"the war ended %s after the rook promotion"
				% ChessState.RESULT.keys()[int(state.get_result())])
		return
	_pass("promote-rook-avoids-stalemate (the queen would have stalemated Black)")
	await _shot("after_rook_promotion")
	if not await _undo_back_to_pawn(game, start_fen, "rook"):
		return

	# ── 2. the KNIGHT, by hotkey — and it gives check ──────────────────────
	if not await _promote_as(game, "n", "key", start_fen):
		return
	if not state.in_check():
		await _fail("promote-knight-checks",
			"the knight promotion did not put Black in check")
		return
	_pass("promote-knight-checks (a knight forks the king from a square a queen cannot)")
	await _shot("after_knight_promotion")
	if not await _undo_back_to_pawn(game, start_fen, "knight"):
		return

	# ── 3. the BISHOP, by walking the row with the arrow keys ──────────────
	if not await _promote_as(game, "b", "arrows", start_fen):
		return
	if not await _undo_back_to_pawn(game, start_fen, "bishop"):
		return

	# ── 4. the QUEEN, by Esc — the silent default, and the stalemate ───────
	if not await _promote_as(game, "q", "escape", start_fen):
		return
	var picks: Array = game.get("promo_picks")
	if str(picks) != str(["r", "n", "b", "q"]):
		await _fail("promote-all-four", "the player picked %s" % str(picks))
		return
	_pass("promote-all-four (%s — click · hotkey · arrows · Esc)" % str(picks))

	# THE DRAW, and what the game says about it.
	if not await _wait_until(func(): return bool(game.get("game_over")), 25.0):
		await _fail("promote-draw", "the queen promotion never ended the game")
		return
	if int(state.get_result()) != ChessState.RESULT.STALEMATE:
		await _fail("promote-draw", "result=%s, expected STALEMATE"
			% ChessState.RESULT.keys()[int(state.get_result())])
		return
	_pass("promote-draw (STALEMATE — the outcome the old queen-only code forced)")
	# A draw is not a death: no king falls, so no dragon ceremony runs.
	if not (game.get("death_log") as Array).is_empty():
		await _fail("promote-draw-no-ceremony",
			"a death animation played on a draw: %s" % str(game.get("death_log")))
		return
	_pass("promote-draw-no-ceremony")
	if not await _wait_until(func(): return bool(game.get("_victory_shown")), 20.0):
		await _fail("promote-draw-card", "the verdict card never opened on the draw")
		return
	var card: Label = game.find_child("VictoryPanel", true, false) \
		.find_children("*", "Label", true, false)[0]
	if not card.text.to_lower().contains("draw"):
		await _fail("promote-draw-card", "the draw card says '%s'" % card.text)
		return
	_pass("promote-draw-card (%s)" % card.text.replace("\n", " · "))
	# THE BANTER DRAW POOL: a stalemate used to be met with silence.
	var banter: Node = game.get("banter")
	if banter == null or str(banter.get("last_beat")) != BanterEngine.BEAT_DRAW:
		await _fail("promote-draw-banter", "the rival's last beat was '%s', expected 'draw'"
			% (str(banter.get("last_beat")) if banter != null else "<no banter>"))
		return
	_pass("promote-draw-banter (beat=draw source=%s)" % str(banter.get("last_source")))
	await _shot("after_queen_promotion_draw")

	# THE DRAW SEAM the Trial by Fire minigame replaces — called on the LIVE
	# game node, so its contract is checked where it is actually used.
	var verdict: Dictionary = await game.settle_tournament_draw(state.get_result())
	if bool(verdict.get("player_advances", true)) \
			or (verdict.get("lines", []) as Array).is_empty():
		await _fail("promote-draw-seam",
			"settle_tournament_draw returned %s — it must answer the bracket AND "
			% str(verdict) + "supply the words the card says")
		return
	_pass("promote-draw-seam (%s)" % str((verdict["lines"] as Array)[0]))
	_finish(0)


## Open the promotion modal by clicking c7 -> c8, prove it is showing the real
## pieces, then take `want` by `how` ("click" | "key" | "arrows" | "escape").
func _promote_as(game: Node, want: String, how: String, start_fen: String) -> bool:
	var state: Object = game.get("state")
	var c7 := ChessState.square_index_from_name("c7")
	var c8 := ChessState.square_index_from_name("c8")
	var step := "promote-%s" % PromotionPicker.NAMES[want].to_lower()
	if not await _wait_until(func():
		return not bool(game.get("busy")) and state.turn == false \
			and not bool(game.get("game_over")), 25.0):
		await _fail(step, "never became the player's turn again")
		return false
	if not await _select_square(game, game.sq_of(c7)):
		await _fail(step, "clicking c7 never selected the pawn")
		return false
	await _click_square(game, game.sq_of(c8))
	if not await _wait_until(func(): return game.get("promo_picker") != null, 6.0):
		await _fail(step, "clicking the promotion square never opened the picker")
		return false
	var picker: Node = game.get("promo_picker")
	# THE MODAL IS MADE OF THE REAL THING: four cards, each holding an actual
	# PieceView of the right type in the promoting haus's own kit.
	var models: Dictionary = picker.get("models")
	var cards: Dictionary = picker.get("cards")
	if models.size() != 4 or cards.size() != 4:
		await _fail(step, "the picker offers %d models / %d cards, expected 4 of each"
			% [models.size(), cards.size()])
		return false
	for pc in PromotionPicker.ORDER:
		var pv = models.get(pc)
		if pv == null or not is_instance_valid(pv):
			await _fail(step, "no piece model on the '%s' card" % pc)
			return false
		if int(pv.get("piece_type")) != int(PromotionPicker.TYPE_OF[pc]):
			await _fail(step, "the '%s' card is showing piece_type %d, expected %d"
				% [pc, int(pv.get("piece_type")), int(PromotionPicker.TYPE_OF[pc])])
			return false
		if str(pv.get("house_id")) != str(game.get("player_house_id")):
			await _fail(step, "the '%s' card wears haus '%s', expected '%s'"
				% [pc, str(pv.get("house_id")), str(game.get("player_house_id"))])
			return false
		var name_label: Label = cards[pc].find_child("PromoName_%s" % pc, true, false)
		if name_label == null \
				or not name_label.text.contains(str(PromotionPicker.NAMES[pc])):
			await _fail(step, "the '%s' card does not name its piece" % pc)
			return false
	# ── AND THEY MUST BE ON SCREEN ────────────────────────────────────────
	# EVERY assertion above passed on the first build of this panel and the
	# player saw FOUR EMPTY BLACK BOXES: the cards were parented after their
	# Camera3D was aimed, `look_at` refused ("Node not inside tree"), and each
	# camera sat inside its own piece. The models were right, the types were
	# right, the names were right, the pixels were nothing. So the frame that
	# is saved is also COUNTED — same image, no awaits in between.
	var img := await _shot("promotion_picker")
	var inks: Array[String] = []
	for pc in PromotionPicker.ORDER:
		var stage: Control = cards[pc].find_child("PromoStage_%s" % pc, true, false)
		var ink := _stage_ink(img, stage)
		inks.append("%s=%.1f%%" % [pc, ink])
		if ink < PICKER_INK_MIN_SHARE:
			await _fail(step, ("the '%s' card renders %.1f%% lit pixels (floor %.1f%%) "
				+ "— the panel is showing an empty box, not a piece")
					% [pc, ink, PICKER_INK_MIN_SHARE])
			return false
	_pass("%s-picker (4 real %s pieces, named and RENDERED: %s, %s)" % [step,
		str(game.get("player_house_id")), " ".join(inks), how])

	match how:
		"click":
			await _click_control(cards[want])
		"key":
			await _press_key(_promo_hotkey(want))
		"arrows":
			for _i in PromotionPicker.ORDER.find(want):
				await _press_key(KEY_RIGHT)
			await _press_key(KEY_ENTER)
		"escape":
			await _press_key(KEY_ESCAPE)
	if not await _wait_until(func(): return game.get("promo_picker") == null, 6.0):
		await _fail(step, "the picker never closed after the '%s' path" % how)
		return false
	var picks: Array = game.get("promo_picks")
	if picks.is_empty() or str(picks.back()) != want:
		await _fail(step, "the picker answered '%s', expected '%s'"
			% [str(picks.back()) if not picks.is_empty() else "<nothing>", want])
		return false
	# ENGINE first (authoritative), then the piece that actually walked out.
	if not await _wait_until(func():
		return str(state.pieces[c8]).to_lower() == want, 8.0):
		await _fail(step, "engine has '%s' on c8, expected '%s'"
			% [str(state.pieces[c8]), want])
		return false
	_pass("%s-engine-applied" % step)
	var to_sq: Vector2i = game.sq_of(c8)
	if not await _wait_until(func():
		var v: Dictionary = game.get("views")
		return v.has(to_sq) and is_instance_valid(v[to_sq]) \
			and int(v[to_sq].piece_type) == int(PromotionPicker.TYPE_OF[want]), 12.0):
		var v2: Dictionary = game.get("views")
		await _fail(step, "the view on c8 is %s, expected a %s"
			% [str(int(v2[to_sq].piece_type)) if v2.has(to_sq) else "<none>",
				str(PromotionPicker.NAMES[want])])
		return false
	_pass("%s-view-replaced (a %s stands on c8)" % [step, PromotionPicker.NAMES[want]])
	# THE FLOURISH IS THE CHOSEN PIECE'S FLOURISH. Photographed INSIDE it, on
	# the wall clock — the promotion cinematic runs at time_scale 0.6, so a
	# scaled wait lands the hero frame where the flourish is not (the ashfall
	# scar, same shape); and the arriving piece rises out of the stone, so
	# anything earlier photographs a piece still underground.
	if not await _wait_until(func():
		var dd: Node = game.get("duel_director")
		return dd != null and dd.is_active(), 6.0):
		await _fail(step, "the promotion flourish never played for the %s"
			% PromotionPicker.NAMES[want])
		return false
	_pass("%s-flourish" % step)
	var played: Array = game.get("promotions_played")
	if played.is_empty() \
			or not str(played.back()).contains(str(PromotionPicker.NAMES[want]).to_lower()):
		await _fail(step, "the promotion log says '%s'"
			% (str(played.back()) if not played.is_empty() else "<nothing>"))
		return false
	return true


## Share (%) of a Control's rect in `img` that is LIT — i.e. brighter than the
## picker stage's own background. The stage clears to 0.07 luma; a piece under
## the card's key light comes in far above it, and an empty box comes in at
## zero. Measured on the saved frame, in the same call that saved it.
const PICKER_INK_LUMA := 0.18
## Floor for "there is a piece in this box". Pinned from the measurement, not
## guessed — see the PASS line, which prints all four shares every run.
const PICKER_INK_MIN_SHARE := 4.0


func _stage_ink(img: Image, ctrl: Control) -> float:
	if img == null or ctrl == null:
		return 0.0
	# Canvas -> window/image space: the same transform the click math uses.
	var r := ctrl.get_global_rect()
	var p0: Vector2 = _to_window * r.position
	var p1: Vector2 = _to_window * r.end
	var x0 := clampi(int(min(p0.x, p1.x)) + 2, 0, img.get_width() - 1)
	var y0 := clampi(int(min(p0.y, p1.y)) + 2, 0, img.get_height() - 1)
	var x1 := clampi(int(max(p0.x, p1.x)) - 2, 0, img.get_width() - 1)
	var y1 := clampi(int(max(p0.y, p1.y)) - 2, 0, img.get_height() - 1)
	if x1 <= x0 or y1 <= y0:
		return 0.0
	var lit := 0
	var seen := 0
	var y := y0
	while y <= y1:
		var x := x0
		while x <= x1:
			var c := img.get_pixel(x, y)
			seen += 1
			if c.get_luminance() > PICKER_INK_LUMA:
				lit += 1
			x += 2
		y += 2
	return 0.0 if seen == 0 else 100.0 * float(lit) / float(seen)


func _promo_hotkey(pc: String) -> Key:
	for k in PromotionPicker.HOTKEY:
		if str(PromotionPicker.HOTKEY[k]) == pc:
			return k
	return KEY_Q


## Cmd/Ctrl+Z after a promotion must put the PAWN back — never leave the new
## piece standing, and never leave the board one ply out of step.
func _undo_back_to_pawn(game: Node, start_fen: String, label: String) -> bool:
	var state: Object = game.get("state")
	var c7 := ChessState.square_index_from_name("c7")
	if not await _settle(game, "promote-%s-settled" % label):
		return false
	await _press_cmd_z()
	if not await _wait_until(func(): return str(state.get_fen()) == start_fen, 15.0):
		await _fail("promote-%s-undo" % label,
			"after the take-back the board reads %s, expected %s"
				% [str(state.get_fen()), start_fen])
		return false
	var pawn_sq: Vector2i = game.sq_of(c7)
	if not await _wait_until(func():
		var v: Dictionary = game.get("views")
		return v.has(pawn_sq) and is_instance_valid(v[pawn_sq]) \
			and int(v[pawn_sq].piece_type) == PieceView.Type.PAWN, 8.0):
		await _fail("promote-%s-undo" % label,
			"no PAWN view standing on c7 after the take-back")
		return false
	_pass("promote-%s-undo (the pawn is back on c7, not a %s)" % [label, label])
	return true

# ── Scenario: duel / showcase ──────────────────────────────────────────────
## duel: assert-heavy capture via clicks (the slow-mo duel plays untouched).
## showcase: same duel plus beauty screenshots and a 45 s zero-error soak.
func _scenario_duel(showcase: bool) -> void:
	if not await _navigate_select(DEFAULT_HOUSE, "Casual", "Single Match"):
		return
	var game := await _boot_game(0)   # custom FEN — piece count varies
	if game == null:
		return
	var state: Object = game.get("state")
	if not await _wait_until(func():
		return game.get("busy") == false and state.turn == false, 15.0):
		await _fail("duel-player-turn", "never became the player's turn")
		return
	_pass("duel-player-turn")
	if showcase:
		# Hero wide shot with the env module's framing note (pitch ~-0.55,
		# distance ~13 keeps the far-wall banners in frame).
		var rig: Node = game.get_node_or_null("CameraRig")
		if rig != null:
			rig.set("target_distance", 13.0)
			rig.set("_target_pitch", -0.55)
		await _sleep(1.5)
		await _shot("great_hall_wide")
		if rig != null:
			rig.set("target_distance", 11.5)
			rig.set("_target_pitch", -0.85)
		await _sleep(1.0)
		await _shot("board_overview")
	# Find the scripted capture from the engine itself — the FEN promises one.
	var capture = null
	for m in state.legal_moves():
		if m.is_capture():
			capture = m
			break
	if capture == null:
		await _fail("duel-capture-available", "the FEN offers White no capture move")
		return
	_pass("duel-capture-available (%s)" % capture.to_uci())
	var from_sq: Vector2i = game.sq_of(capture.from_square)
	var to_sq: Vector2i = game.sq_of(capture.to_square)
	var victim_sq: Vector2i = game.sq_of(capture.captured_square)
	var victim_idx: int = capture.captured_square
	var views: Dictionary = game.get("views")
	var attacker: Node = views.get(from_sq)
	var victim: Node = views.get(victim_sq)
	if attacker == null or victim == null:
		await _fail("duel-actors-present", "missing attacker/victim view on the board")
		return
	if not await _select_square(game, from_sq):
		await _fail("duel-select-attacker", "%s never became the selected square" % str(from_sq))
		return
	_pass("duel-select-attacker")
	await _shot("attacker_selected")
	var deaths_before: int = (game.get("death_log") as Array).size()
	await _click_square(game, to_sq)
	if not await _wait_until(func():
		return state.pieces[capture.to_square] != null \
			and not ChessState.piece_color(state.pieces[capture.to_square]) \
			and state.pieces[capture.from_square] == null, 5.0):
		await _fail("duel-engine-applied", "engine never applied the capture %s" % capture.to_uci())
		return
	_pass("duel-engine-applied")
	await _sleep(1.2)   # walk + swoop + slow-mo ramp
	await _shot("mid_duel")
	if showcase:
		await _sleep(0.5)
		await _shot("duel_caption")   # inside the caption hold window
	if not await _wait_until(func():
		return (game.get("death_log") as Array).size() > deaths_before, 12.0):
		await _fail("duel-death-anim", "no death animation was recorded")
		return
	var last_death: String = (game.get("death_log") as Array).back()
	_pass("duel-death-anim (%s)" % last_death)
	if not await _wait_until(func(): return not is_instance_valid(victim), 6.0):
		await _fail("duel-victim-removed", "victim view still alive on the board")
		return
	if state.pieces[victim_idx] != null and ChessState.piece_color(state.pieces[victim_idx]):
		await _fail("duel-victim-removed", "black piece still on the captured square (engine)")
		return
	_pass("duel-victim-removed")
	if not await _wait_until(func():
		var v: Dictionary = game.get("views")
		return v.get(to_sq) == attacker, 10.0):
		await _fail("duel-attacker-occupies", "attacker view never registered on %s" % str(to_sq))
		return
	_pass("duel-attacker-occupies")
	if showcase:
		# Gate C hero: the rival's taunt caption (fires after the duel
		# resolves; LLM path may take up to 8 s before the pool answers).
		var bc: Label = game.find_child("BanterCaption", true, false)
		if bc != null and await _wait_until(func(): return bc.visible, 12.0):
			await _shot("banter_caption")
			_pass("showcase-banter-caption")
	await _shot("post_duel")
	# Let the rival's reply (WorkerThreadPool search + animation + possibly
	# its own duel) finish before quitting — tearing the engine down mid-task
	# segfaults on shutdown.
	if not await _wait_until(func(): return game.get("busy") == false, 30.0):
		await _fail("duel-settled", "board never settled after the duel")
		return
	_pass("duel-settled")
	var dd: Node = game.get("duel_director")
	if not await _wait_until(func():
		return not dd.is_active() and is_equal_approx(Engine.time_scale, 1.0), 10.0):
		await _fail("duel-timescale-restored", "time_scale=%f after the duel" % Engine.time_scale)
		return
	_pass("duel-timescale-restored")
	if showcase:
		while Time.get_ticks_msec() - _start_ms < 45_000 and not _done:
			await _sleep(1.0)
		await _shot("closing_tableau")
		_pass("showcase-45s-soak")
		await _showcase_throne_room(game)
	_finish(0)


## Showcase closer: the championship tableau — champion-dyed banners, the
## Throne of Blades, the dragon hovering overhead, the crowned champion king
## on the dais, camera parked framing it all (09_throne_room.png).
func _showcase_throne_room(game: Node) -> void:
	var hall: Node = game.get_node_or_null("GreatHall")
	if hall == null or hall.get("throne") == null:
		await _fail("showcase-throne-present", "the great hall has no throne")
		return
	_pass("showcase-throne-present")
	var views: Dictionary = game.get("views")
	var crowned := false
	for sq in views:
		var pv = views[sq]
		if is_instance_valid(pv) and int(pv.get("piece_type")) == PieceView.Type.KING \
				and pv.find_child("Crown", true, false) != null:
			crowned = true
	if not crowned:
		await _fail("showcase-king-crowned", "no crowned king on the field")
		return
	_pass("showcase-king-crowned")
	var done := {"done": false}
	var runner := func() -> void:
		await game.start_championship_tableau()
		done["done"] = true
	runner.call()
	var dd: Node = game.get("duel_director")
	if not await _wait_until(func(): return dd.is_active(), 15.0):
		await _fail("showcase-tableau-started", "championship tableau never started")
		return
	_pass("showcase-tableau-started")
	if hall.get("dragon") == null:
		await _fail("showcase-dragon-summoned", "no dragon above the throne")
		return
	_pass("showcase-dragon-summoned")
	await _sleep_wall(2.4)   # glide (1.5 s) done — inside the tableau hold
	# WHERE THE SUBJECT ACTUALLY IS, in the pixel space the overlay census
	# reports its rects in. "The caption clears the champion" is a claim about
	# two rectangles; this line is the second one, so a critic can check the
	# arithmetic against the PNG instead of taking the plate's word for it.
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var king_pos := Vector3.INF
		for sq in (game.get("views") as Dictionary):
			var pv = (game.get("views") as Dictionary)[sq]
			if is_instance_valid(pv) and int(pv.get("piece_type")) == PieceView.Type.KING \
					and int(pv.get("side")) == PieceView.House.FROST:
				king_pos = (pv as Node3D).global_position
		for tag in [["dais", hall.throne_dais() + Vector3.UP * 0.9],
				["throne", hall.throne_focus() - Vector3.UP * 2.4],
				["king", king_pos + Vector3.UP * 0.9]]:
			var p: Vector3 = tag[1]
			if not p.is_finite():
				continue
			print("E2E SUBJECT throne_room %-7s world=%v screen=%v behind=%s" % [
				tag[0], p, cam.unproject_position(p), cam.is_position_behind(p)])
	await _shot("throne_room")
	if not await _wait_until(func(): return done["done"], 25.0):
		await _fail("showcase-tableau-finished", "championship tableau never finished")
		return
	if not await _wait_until(func():
		return not dd.is_active() and is_equal_approx(Engine.time_scale, 1.0), 10.0):
		await _fail("showcase-tableau-clean",
			"director active or time_scale=%f after the tableau" % Engine.time_scale)
		return
	_pass("showcase-throne-room-tableau")

# ── Scenario: slowmo (duel director activation + skip contract) ────────────
func _scenario_slowmo() -> void:
	if not await _navigate_select(DEFAULT_HOUSE, "Casual", "Single Match"):
		return
	var game := await _boot_game(0)
	if game == null:
		return
	var state: Object = game.get("state")
	var dd: Node = game.get("duel_director")
	if dd == null:
		await _fail("slowmo-director", "game has no DuelDirector")
		return
	if not await _wait_until(func():
		return game.get("busy") == false and state.turn == false, 15.0):
		await _fail("slowmo-player-turn", "never became the player's turn")
		return
	var capture = null
	for m in state.legal_moves():
		if m.is_capture():
			capture = m
			break
	if capture == null:
		await _fail("slowmo-capture-available", "the FEN offers no capture")
		return
	if not await _select_square(game, game.sq_of(capture.from_square)):
		await _fail("slowmo-select", "attacker never selected")
		return
	await _click_square(game, game.sq_of(capture.to_square))
	if not await _wait_until(func(): return dd.is_active(), 8.0):
		await _fail("slowmo-activated", "duel director never became active")
		return
	_pass("slowmo-activated")
	if not await _wait_until(func(): return Engine.time_scale < 0.9, 3.0):
		await _fail("slowmo-time-dipped", "time_scale never dipped (%.2f)" % Engine.time_scale)
		return
	_pass("slowmo-time-dipped (%.2f)" % Engine.time_scale)
	await _sleep(0.3)
	await _shot("mid_slowmo")
	# A click mid-cinematic = skip: presentation snaps, time restores fast,
	# gameplay still resolves at normal speed.
	await _click_at(get_viewport().get_visible_rect().size * 0.5)
	if not await _wait_until(func(): return absf(Engine.time_scale - 1.0) < 0.01, 2.0):
		await _fail("slowmo-skip-restores",
			"click-skip did not restore time_scale (%.2f)" % Engine.time_scale)
		return
	_pass("slowmo-skip-restores")
	if not await _wait_until(func(): return not dd.is_active(), 10.0):
		await _fail("slowmo-cinematic-ended", "director stayed active after skip")
		return
	_pass("slowmo-cinematic-ended")
	if not await _wait_until(func():
		return state.pieces[capture.to_square] != null \
			and not ChessState.piece_color(state.pieces[capture.to_square]), 10.0):
		await _fail("slowmo-capture-resolved", "capture never resolved on the engine")
		return
	_pass("slowmo-capture-resolved")
	# Let the rival reply (possibly its own un-skipped duel) fully settle.
	if not await _wait_until(func():
		return game.get("busy") == false and not dd.is_active(), 40.0):
		await _fail("slowmo-settled", "board never settled")
		return
	if not is_equal_approx(Engine.time_scale, 1.0):
		await _fail("slowmo-final-timescale", "time_scale=%f after settle" % Engine.time_scale)
		return
	_pass("slowmo-final-timescale-1.0")
	await _shot("post_slowmo")
	_finish(0)

# ── Scenario: tournament (3 scripted mates to the throne) ──────────────────
func _scenario_tournament() -> void:
	if not await _navigate_select("goldclaw", "Casual", "Begin Tournament"):
		return
	var prev_rival := ""
	var prev_banner := Color.BLACK
	for round_i in 3:
		var game := await _boot_game(0)
		if game == null:
			return
		var rival := str(game.get("rival_house_id"))
		if rival.is_empty():
			await _fail("tourn-rival-%d" % round_i, "no rival house resolved")
			return
		if rival == prev_rival:
			await _fail("tourn-rival-advanced-%d" % round_i, "rival did not change (%s)" % rival)
			return
		var hall: Node = game.get_node_or_null("GreatHall")
		var expect: Color = HouseRegistry.get_colors(rival)["primary"]
		var got: Color = hall.get_banner(6).house_color
		if not _colors_close(got, expect):
			await _fail("tourn-banners-%d" % round_i,
				"east banner %s != rival primary %s" % [got, expect])
			return
		if round_i > 0 and _colors_close(got, prev_banner):
			await _fail("tourn-redress-%d" % round_i, "banner color unchanged between rounds")
			return
		prev_rival = rival
		prev_banner = got
		_pass("tourn-round%d-dressing (%s)" % [round_i, rival])
		var state: Object = game.get("state")
		if not await _wait_until(func():
			return game.get("busy") == false and state.turn == false, 15.0):
			await _fail("tourn-turn-%d" % round_i, "never became the player's turn")
			return
		# The FEN promises a mate-in-1 — find it in the SAN'd turn moves.
		var mate = null
		for m in game.get("_turn_moves"):
			if m.notation_san != null and str(m.notation_san).ends_with("#"):
				mate = m
				break
		if mate == null:
			await _fail("tourn-mate-available-%d" % round_i, "FEN offers no mate-in-1")
			return
		if not await _select_square(game, game.sq_of(mate.from_square)):
			await _fail("tourn-select-%d" % round_i, "mate mover never selected")
			return
		await _click_square(game, game.sq_of(mate.to_square))
		if not await _wait_until(func(): return bool(game.get("game_over")), 10.0):
			await _fail("tourn-mate-%d" % round_i, "game never ended after the mate")
			return
		_pass("tourn-round%d-mate" % round_i)
		# The checkmate cinematic (~5 s) ends in victory_panel_requested.
		if not await _wait_until(func():
			var vp = game.get("_victory_panel")
			return vp != null and vp.visible, 25.0):
			await _fail("tourn-victory-panel-%d" % round_i, "victory panel never appeared")
			return
		await _shot("round%d_victory" % round_i)
		# The panel fires before the death tail ends; while the director is
		# active it consumes every click as "skip" — wait for it to let go.
		var dd: Node = game.get("duel_director")
		if not await _wait_until(func(): return not dd.is_active(), 15.0):
			await _fail("tourn-cinematic-released-%d" % round_i,
				"duel director never released input after the checkmate")
			return
		var t = Session.tournament
		if t == null:
			await _fail("tourn-state-%d" % round_i, "Session.tournament is null")
			return
		if round_i < 2:
			if t.is_over():
				await _fail("tourn-bracket-%d" % round_i, "tournament ended early")
				return
			var nxt: String = t.current_opponent()
			if nxt.is_empty() or nxt == rival:
				await _fail("tourn-bracket-advanced-%d" % round_i,
					"bracket did not advance past %s" % rival)
				return
			_pass("tourn-round%d-bracket-advanced (next: %s)" % [round_i, nxt])
			var btn := _find_button(game, "Ride to")
			if btn == null:
				await _fail("tourn-continue-%d" % round_i, "no continue button on the panel")
				return
			await _click_control(btn)
			if not await _wait_until(func():
				var g := _game()
				return g != null and g != game, 15.0):
				await _fail("tourn-next-round-%d" % round_i, "next round scene never loaded")
				return
		else:
			if not t.is_champion():
				await _fail("tourn-champion", "player is not champion after 3 wins")
				return
			if not bool(t.bracket_state().get("complete", false)):
				await _fail("tourn-complete", "bracket not complete after the final")
				return
			_pass("tourn-champion")
			await _sleep(0.6)
			await _shot("championship_panel")
	if not is_equal_approx(Engine.time_scale, 1.0):
		await _fail("tourn-timescale", "time_scale=%f at the end" % Engine.time_scale)
		return
	_pass("tourn-timescale-1.0")
	_finish(0)

# ── Scenario: oracle-mock (DS4-Oracle vs the in-driver canned server) ──────
func _scenario_oracle_mock() -> void:
	if not _mock_running:
		await _fail("oracle-mock-server", "in-driver mock oracle failed to listen")
		return
	_pass("oracle-mock-server (port %d)" % _mock_port)
	if not await _navigate_select(DEFAULT_HOUSE, "Pure Oracle", "Single Match"):
		return
	var game := await _boot_game(32)
	if game == null:
		return
	if game.get("oracle") == null:
		await _fail("oracle-node", "game did not create the Ds4Opponent node")
		return
	_pass("oracle-node")
	var state: Object = game.get("state")
	if not await _wait_until(func():
		return game.get("busy") == false and state.turn == false, 15.0):
		await _fail("oracle-player-turn", "never became the player's turn")
		return
	_mock_replies = ["The pawn answers in kind.\nMOVE: e7e5"]
	var e2 := ChessState.square_index_from_name("e2")
	var e4 := ChessState.square_index_from_name("e4")
	if not await _select_square(game, game.sq_of(e2)):
		await _fail("oracle-select-pawn", "e2 never became the selected square")
		return
	await _click_square(game, game.sq_of(e4))
	if not await _wait_until(func(): return state.pieces[e4] == "P", 5.0):
		await _fail("oracle-e4", "engine never showed the pawn on e4")
		return
	_pass("oracle-e4")
	# The Oracle (mock) must answer with its scripted legal reply.
	var e5 := ChessState.square_index_from_name("e5")
	if not await _wait_until(func(): return str(state.pieces[e5]) == "p", 25.0):
		await _fail("oracle-legal-move",
			"the Oracle's e7e5 never landed (e5='%s')" % str(state.pieces[e5]))
		return
	_pass("oracle-legal-move (e7e5)")
	var oracle: Node = game.get("oracle")
	if str(oracle.last_source) != "llm":
		await _fail("oracle-source-llm", "last_source='%s', expected 'llm'" % str(oracle.last_source))
		return
	_pass("oracle-source-llm")
	if int(game.get("oracle_think_count")) < 1:
		await _fail("oracle-thinking-hud", "thinking_started never reached the HUD")
		return
	_pass("oracle-thinking-hud (%d)" % int(game.get("oracle_think_count")))
	if not await _wait_until(func(): return game.get("busy") == false, 15.0):
		await _fail("oracle-settled", "board never settled after the oracle move")
		return
	if not is_equal_approx(Engine.time_scale, 1.0):
		await _fail("oracle-timescale", "time_scale=%f after the oracle move" % Engine.time_scale)
		return
	_pass("oracle-settled")
	await _shot("after_oracle_move")
	_finish(0)

# ── Scenario: oracle-modes (Counseled Oracle: blunder caught by counsel) ───
## Launch with a Black-to-move FEN where d8d2 (Qxd2+??) trades queen for pawn
## and d8d7 is sound (run_e2e.sh's COUNSEL_FEN). The Oracle opens: mock
## proposes the blunder, real stockfish (depth 12) rejects it, the revised
## proposal plays. Covers mode selection clicks, Session->game wiring, the
## HUD mode label, and the reconsideration prompt.
func _scenario_oracle_modes() -> void:
	if not _mock_running:
		await _fail("oracle-modes-server", "in-driver mock oracle failed to listen")
		return
	_pass("oracle-modes-server (port %d)" % _mock_port)
	# Queue the canned proposals BEFORE the game scene boots the Oracle.
	_mock_replies = ["The queen strikes!\nMOVE: d8d2", "Wisdom prevails.\nMOVE: d8d7"]
	if not await _navigate_select(DEFAULT_HOUSE, "Counseled Oracle", "Single Match"):
		return
	var game := _game()
	var oracle: Node = game.get("oracle")
	if oracle == null:
		await _fail("oracle-modes-node", "game did not create the Ds4Opponent node")
		return
	if str(oracle.get("mode")) != "counseled":
		await _fail("oracle-modes-mode",
			"oracle mode '%s', expected 'counseled'" % str(oracle.get("mode")))
		return
	_pass("oracle-modes-mode (counseled)")
	var mode_lbl: Label = game.find_child("OracleMode", true, false)
	if mode_lbl == null or not mode_lbl.text.contains("Counseled"):
		await _fail("oracle-modes-hud", "HUD mode label missing/wrong: '%s'"
			% (mode_lbl.text if mode_lbl != null else "<none>"))
		return
	_pass("oracle-modes-hud (%s)" % mode_lbl.text)
	var state: Object = game.get("state")
	var d7 := ChessState.square_index_from_name("d7")
	var d2 := ChessState.square_index_from_name("d2")
	if not await _wait_until(func(): return str(state.pieces[d7]) == "q", 60.0):
		await _fail("oracle-modes-counseled-move",
			"the counseled d8d7 never landed (d7='%s')" % str(state.pieces[d7]))
		return
	_pass("oracle-modes-counseled-move (d8d7)")
	if str(state.pieces[d2]) != "P":
		await _fail("oracle-modes-blunder-avoided",
			"the d2 pawn is gone — the blunder was played")
		return
	_pass("oracle-modes-blunder-avoided")
	if _mock_requests.size() < 2:
		await _fail("oracle-modes-reconsidered",
			"only %d chat requests — no reconsideration issued" % _mock_requests.size())
		return
	var msgs: Array = _mock_requests[1].get("messages", [])
	var prompt2 := String((msgs.back() as Dictionary).get("content", "")) \
		if not msgs.is_empty() else ""
	if not prompt2.contains("Choose again"):
		await _fail("oracle-modes-reconsidered", "second request lacks the reconsideration prompt")
		return
	_pass("oracle-modes-reconsidered")
	if not str(oracle.get("last_source")).begins_with("counseled"):
		await _fail("oracle-modes-source", "last_source='%s'" % str(oracle.get("last_source")))
		return
	_pass("oracle-modes-source (%s)" % str(oracle.get("last_source")))
	if not await _wait_until(func(): return game.get("busy") == false, 20.0):
		await _fail("oracle-modes-settled", "board never settled after the counseled move")
		return
	if not is_equal_approx(Engine.time_scale, 1.0):
		await _fail("oracle-modes-timescale", "time_scale=%f" % Engine.time_scale)
		return
	_pass("oracle-modes-settled")
	await _shot("after_counseled_move")
	_finish(0)

# ── Scenario: undo (take-back insurance vs the mock Oracle, tournament) ────
## FEN contract (run_e2e.sh DUEL_FEN): White has exactly one capture (exd5).
## Runs in TOURNAMENT mode (limit 3) against the mock Pure Oracle so both
## the limit path and the mid-think cancellation are deterministic:
##   round 1  exd5 duel + scripted Nf6 reply, button undo -> FEN + view
##            census byte-identical to the pre-move snapshot (the captured
##            pawn resurrects), SAN truncated, 2 left
##   round 2  the mock HOLDS its reply 4 s; undo lands mid-think, reverts
##            the player ply only, and the late reply is discarded with no
##            desync, 1 left
##   round 3  Cmd/Ctrl+Z spends the last undo -> 0 left, button disabled
##   round 4  a fresh round, then button + Cmd/Ctrl+Z are both inert
func _scenario_undo() -> void:
	if not _mock_running:
		await _fail("undo-mock-server", "in-driver mock oracle failed to listen")
		return
	_pass("undo-mock-server (port %d)" % _mock_port)
	if not await _navigate_select(DEFAULT_HOUSE, "Pure Oracle", "Begin Tournament"):
		return
	var game := await _boot_game(0)
	if game == null:
		return
	if game.get("oracle") == null:
		await _fail("undo-oracle-node", "game did not create the Ds4Opponent node")
		return
	var state: Object = game.get("state")
	if not await _wait_until(func():
		return game.get("busy") == false and state.turn == false, 15.0):
		await _fail("undo-player-turn", "never became the player's turn")
		return
	_pass("undo-player-turn")
	var undo_btn: Button = game.find_child("UndoButton", true, false)
	if undo_btn == null:
		await _fail("undo-button-present", "no UndoButton in the HUD")
		return
	if not undo_btn.disabled or int(game.get("_undos_left")) != 3 \
			or not undo_btn.text.contains("3"):
		await _fail("undo-button-idle",
			"before any move: disabled=%s left=%s text='%s' (want disabled, 3 left)"
			% [str(undo_btn.disabled), str(game.get("_undos_left")), undo_btn.text])
		return
	_pass("undo-button-idle (disabled until a move exists · '%s')" % undo_btn.text)
	var fen0 := str(state.get_fen())
	var census0 := _view_census(game)

	# ── round 1: full round, then the button reverts both plies ──
	_mock_replies = ["The knight answers.\nMOVE: g8f6"]
	if not await _play_capture_round(game, "undo-r1", true):
		return
	if str(state.get_fen()) == fen0 or (game.get("_san_log") as Array).size() != 2:
		await _fail("undo-r1-advanced", "round did not land as expected (san=%d)"
			% (game.get("_san_log") as Array).size())
		return
	await _shot("before_first_undo")
	if not await _click_until(undo_btn,
			func(): return str(state.get_fen()) == fen0, "undo-r1-button"):
		await _fail("undo-r1-fen-restored", "FEN never returned to the pre-move snapshot")
		return
	_pass("undo-r1-fen-restored (both plies reverted)")
	if _view_census(game) != census0:
		await _fail("undo-r1-view-census",
			"view census differs after the undo (was %s, now %s)"
			% [census0, _view_census(game)])
		return
	if not await _assert_sync(game, "undo-r1-sync"):
		return
	if (game.get("_san_log") as Array).size() != 0:
		await _fail("undo-r1-san-truncated", "SAN list not truncated")
		return
	if int(game.get("_undos_left")) != 2 or not undo_btn.text.contains("2"):
		await _fail("undo-r1-remaining", "left=%s text='%s' (want 2)"
			% [str(game.get("_undos_left")), undo_btn.text])
		return
	_pass("undo-r1-clean (census+sync+SAN · captured pawn resurrected · 2 left)")
	await _shot("after_undo_full_round")

	# ── round 2: mid-think undo; the DELAYED late reply must be discarded ──
	_mock_delay_ms = 4000
	_mock_replies = ["The knight answers again.\nMOVE: g8f6"]
	var served_before := _mock_served
	if not await _play_capture_round(game, "undo-r2", false):
		return
	if not await _wait_until(func():
		return bool(game.get("oracle_thinking")) and bool(game.get("_ai_waiting")), 25.0):
		await _fail("undo-r2-thinking", "the Oracle's thinking window never opened")
		return
	_pass("undo-r2-thinking (mock reply held %d ms)" % _mock_delay_ms)
	if not await _click_until(undo_btn,
			func(): return str(state.get_fen()) == fen0, "undo-r2-button"):
		await _fail("undo-r2-fen-restored", "mid-think undo never restored the FEN")
		return
	if not await _wait_until(func():
		return game.get("busy") == false and state.turn == false, 4.0):
		await _fail("undo-r2-interactive", "board not interactive after the mid-think undo")
		return
	_pass("undo-r2-fen-restored (player ply reverted while the Oracle thought)")
	# The late reply: wait until the mock has WRITTEN it, then give the game
	# every chance to (wrongly) apply it — nothing may move.
	if not await _wait_until(func(): return _mock_served > served_before, 20.0):
		await _fail("undo-r2-late-reply", "the delayed oracle reply was never served")
		return
	await _sleep(2.0)
	if str(state.get_fen()) != fen0:
		await _fail("undo-r2-late-discarded",
			"the late reply mutated the board: %s" % str(state.get_fen()))
		return
	if _view_census(game) != census0:
		await _fail("undo-r2-late-census", "view census drifted after the late reply")
		return
	if not await _assert_sync(game, "undo-r2-sync"):
		return
	if bool(game.get("busy")) or int(game.get("_undos_left")) != 1:
		await _fail("undo-r2-state", "busy=%s left=%s (want idle, 1 left)"
			% [str(game.get("busy")), str(game.get("_undos_left"))])
		return
	_pass("undo-r2-late-discarded (stale Oracle reply dropped, no desync · 1 left)")
	_mock_delay_ms = 0

	# ── round 3: Cmd/Ctrl+Z spends the last take-back ──
	_mock_replies = ["The knight, a third time.\nMOVE: g8f6"]
	if not await _play_capture_round(game, "undo-r3", true):
		return
	var keyed := false
	for i in 3:
		await _press_cmd_z()
		if await _wait_until(func(): return str(state.get_fen()) == fen0, 3.0):
			keyed = true
			break
	if not keyed:
		await _fail("undo-r3-fen-restored", "Cmd/Ctrl+Z undo never restored the FEN")
		return
	if int(game.get("_undos_left")) != 0 or not undo_btn.disabled \
			or not undo_btn.text.contains("0"):
		await _fail("undo-r3-limit", "after 3 undos: left=%s disabled=%s text='%s'"
			% [str(game.get("_undos_left")), str(undo_btn.disabled), undo_btn.text])
		return
	_pass("undo-r3-limit (Cmd/Ctrl+Z · 0 left · button disabled)")

	# ── round 4: allowance spent — button and key must both be inert ──
	_mock_replies = ["The knight, unbothered.\nMOVE: g8f6"]
	if not await _play_capture_round(game, "undo-r4", true):
		return
	var fen_r4 := str(state.get_fen())
	await _click_control(undo_btn)
	await _press_cmd_z()
	await _sleep(2.0)
	if str(state.get_fen()) != fen_r4 or int(game.get("undo_count")) != 3:
		await _fail("undo-limit-inert", "a 4th undo landed (fen_changed=%s undo_count=%s)"
			% [str(str(state.get_fen()) != fen_r4), str(game.get("undo_count"))])
		return
	_pass("undo-limit-inert (button + Cmd/Ctrl+Z both refused)")
	if not is_equal_approx(Engine.time_scale, 1.0):
		await _fail("undo-timescale", "time_scale=%f at the end" % Engine.time_scale)
		return
	_pass("undo-timescale-1.0")
	await _shot("undo_final")
	_finish(0)


## One scripted round from the DUEL_FEN position: click the exd5 capture;
## with wait_settle, also wait out the duel + the scripted rival reply.
func _play_capture_round(game: Node, prefix: String, wait_settle: bool) -> bool:
	var state: Object = game.get("state")
	if not await _wait_until(func():
		return game.get("busy") == false and state.turn == false, 20.0):
		await _fail(prefix + "-turn", "never became the player's turn")
		return false
	var capture = null
	for m in state.legal_moves():
		if m.is_capture():
			capture = m
			break
	if capture == null:
		await _fail(prefix + "-capture", "the position offers no capture")
		return false
	if not await _select_square(game, game.sq_of(capture.from_square)):
		await _fail(prefix + "-select", "attacker never selected")
		return false
	await _click_square(game, game.sq_of(capture.to_square))
	if not await _wait_until(func():
		return state.pieces[capture.from_square] == null, 5.0):
		await _fail(prefix + "-applied", "engine never applied %s" % capture.to_uci())
		return false
	_pass(prefix + "-applied (%s)" % capture.to_uci())
	if not wait_settle:
		return true
	if not await _wait_until(func():
		return game.get("busy") == false and state.turn == false \
			and not (game.get("duel_director") as Node).is_active(), 60.0):
		await _fail(prefix + "-settled", "round never settled")
		return false
	return true


## Deterministic census of the live piece views: "sq:type:side" rows, sorted —
## byte-comparable across an undo round trip (the resurrection proof).
func _view_census(game: Node) -> String:
	var rows: Array[String] = []
	var views: Dictionary = game.get("views")
	for sq in views:
		var pv = views[sq]
		if pv == null or not is_instance_valid(pv):
			rows.append("%d,%d:dead" % [sq.x, sq.y])
			continue
		rows.append("%d,%d:%d:%d" % [sq.x, sq.y,
			int(pv.get("piece_type")), int(pv.get("side"))])
	rows.sort()
	return ",".join(rows)


# ══ Scenarios: head-to-head multiplayer ════════════════════════════════════
##
## THE GATE IS THE TWO-INSTANCE GAME, not these functions. `net-host` and
## `net-join` are the two HALVES of one test: test_e2e/run_net_e2e.sh launches
## a real pair of Godot processes on this Mac, one of each, and they play a
## real game against each other through the real click path. The runner then
## diffs the `E2E NETFEN` lines the two processes printed — if the two boards
## ever disagreed by one ply, the diff says so. A green unit suite proves the
## protocol; only this proves multiplayer.
##
## The scripted game (NET_FEN, verified against the engine before it was
## written down) is chosen to walk every path that matters:
##   ply 0  White  Rh7    a normal move from the host
##   ply 1  Black  c6     a normal move from the joiner
##   ply 2  White  exd5   a CAPTURE — the slow-motion duel, on both screens
##   ply 3  Black  b1=N   the JOINER UNDERPROMOTES through the picker, and the
##                        piece has to survive the trip to the host's validator
##   ply 4  White  Ra8#   CHECKMATE — the ceremony, and the verdict card
##
## THE UNDERPROMOTION IS LOAD-BEARING, on purpose. A QUEEN on b1 checks the
## white king down the first rank, which makes ply 4's mate illegal — so a
## client's picked KNIGHT that silently became a queen anywhere on the wire
## cannot pass this gate: the script would simply stop working. Both instances
## also assert the knight standing on b1 at the end (see _scenario_net).
## tests/test_promotion.gd walks this exact line headless, including the
## queen counterfactual.
const NET_FEN := "4k3/2p5/8/3p4/4P3/8/1p6/R3K2R w KQ - 0 1"
const NET_LINE_WHITE: Array[String] = ["h1h7", "e4d5", "a1a8"]
const NET_LINE_BLACK: Array[String] = ["c7c6", "b2b1n"]
const NET_TOTAL_PLIES := 5

var _net_duel_shot := false
var _net_first_move_shot := false


func _scenario_net(host_role: bool) -> void:
	var tag := "host" if host_role else "join"
	# main.gd dials before it swaps scenes, and a command-line joiner retries
	# (the two processes are launched seconds apart), so this wait is long.
	if not await _wait_until(func(): return _game() != null, 90.0):
		await _fail("net-%s-connected" % tag,
			"the match never started — no game scene after 90 s")
		return
	var game := await _boot_game(0)
	if game == null:
		return
	var netm: Node = game.get("net")
	if netm == null:
		await _fail("net-%s-connected" % tag, "the game scene has no NetMatch node")
		return
	if not netm.is_active():
		await _fail("net-%s-connected" % tag,
			"NetMatch is not in a match (state=%d, '%s') — the other instance "
				% [int(netm.get("state")), str(netm.get("detail"))]
			+ "probably died before this one was seated")
		return
	_pass("net-%s-connected" % tag)

	# Seating: who am I, which army is mine, and does the HUD say so.
	var my_color: bool = bool(game.get("player_color"))
	var want_color: bool = not host_role       # host is White in this scenario
	if my_color != want_color:
		await _fail("net-%s-seated" % tag, "player_color=%s, expected %s"
			% [str(my_color), str(want_color)])
		return
	if bool(netm.get("is_host")) != host_role:
		await _fail("net-%s-seated" % tag, "is_host=%s on the %s instance"
			% [str(netm.get("is_host")), tag])
		return
	_pass("net-%s-seated (%s)" % [tag, NetProtocol.color_name(my_color)])

	var status: Label = game.find_child("NetStatus", true, false)
	var want_word := NetProtocol.color_name(my_color)
	if status == null or not status.text.contains(want_word):
		await _fail("net-%s-hud" % tag, "HUD NetStatus missing or silent about the side: '%s'"
			% (status.text if status != null else "<absent>"))
		return
	_pass("net-%s-hud (%s)" % [tag, status.text])

	# Take-backs are OFF online, and the control has to SAY so — a disabled
	# button that still reads "undo · 3 left" is a lie in the HUD.
	var undo_btn: Button = game.find_child("UndoButton", true, false)
	if undo_btn == null or not undo_btn.disabled or not undo_btn.text.contains("no take-backs"):
		await _fail("net-%s-undo-off" % tag, "undo button: text='%s' disabled=%s"
			% [undo_btn.text if undo_btn != null else "<absent>",
				str(undo_btn.disabled) if undo_btn != null else "?"])
		return
	# ...and the key press is inert too, not merely the button.
	#
	# THE PROBE ITSELF WAS THE FLAKE (verifier defect P5, 2026-08-09). It used
	# to snapshot the FEN, press Cmd/Z, sleep 0.4 s and assert the FEN was
	# UNCHANGED — but the FEN is not ours to hold still: the opponent's own
	# legitimate ply lands whenever it lands, and roughly one run in three it
	# landed inside that window. A CORRECT game failed the gate, this instance
	# exited, and the other one then failed its own step waiting for a partner
	# that had gone. Undo itself was never broken; the assertion was.
	#
	# So assert what only a take-back can do: bump the counter, or REWIND. A
	# legitimate ply only ever grows the move stack and the applied-ply log; an
	# undo is the one thing that shortens them.
	var state: Object = game.get("state")
	var stack_before: int = (state.move_stack as Array).size()
	var plies_before: int = (game.get("net_plies") as Array).size()
	await _press_cmd_z()
	await _sleep(0.4)
	var undos: int = int(game.get("undo_count"))
	var stack_after: int = (state.move_stack as Array).size()
	var plies_after: int = (game.get("net_plies") as Array).size()
	if undos != 0 or stack_after < stack_before or plies_after < plies_before:
		await _fail("net-%s-undo-off" % tag,
			("Cmd/Ctrl+Z rewound the board in a network match "
			+ "(undo_count=%d, move_stack %d->%d, applied plies %d->%d)")
				% [undos, stack_before, stack_after, plies_before, plies_after])
		return
	_pass("net-%s-undo-off (undo_count=0, nothing rewound: stack %d->%d, plies %d->%d)"
		% [tag, stack_before, stack_after, plies_before, plies_after])

	# Every settled ply, printed on BOTH instances — the runner diffs these.
	game.connect("net_ply_settled", func(s: int, fen: String) -> void:
		print("E2E NETFEN %d %s" % [s, fen]))
	_net_duel_watch(game)      # fire and forget: photograph the duel when it starts
	await _shot("seated")

	if not host_role:
		# Ply 0 belongs to White. The joiner asks for a move that WOULD be legal
		# on its own turn (d5d4, and never part of the scripted game) — and is
		# refused, in words a human can read.
		#
		# THIS PROBE RACES THE HOST BY CONSTRUCTION, and the race has TWO correct
		# answers (verifier defect P5's second face, caught on the 6th
		# consecutive run, 2026-08-09). The request is written for the seq we
		# hold; the host may legitimately play ply 0 while it is in flight. So:
		#   * it arrives first  -> "it is not your turn" (the validator),
		#   * ply 0 beats it    -> "that move was for an earlier position"
		#     (the generation guard, which is if anything the stronger refusal).
		# Demanding only the first made a CORRECT game fail about one run in
		# three. What must hold in BOTH cases — and is asserted in both — is that
		# the move was refused with a reason and never, ever applied.
		if not await _net_illegal_probe(game, netm, "wrong-turn", "d5", "d4",
				["not your turn", "earlier position"], false):
			return

	var my_line: Array[String] = NET_LINE_WHITE if host_role else NET_LINE_BLACK
	var probed_illegal := host_role   # the joiner also probes on its own turn
	for i in my_line.size():
		if not host_role and not probed_illegal:
			# Wait for our turn, THEN ask for something illegal: this proves the
			# refusal is about legality, not about turn order. NOT a race — on
			# our own turn the host cannot advance the ply counter under us, it
			# is waiting for exactly this move — so this one stays strict.
			if not await _wait_until(func():
				return not bool(game.get("busy")) and bool(state.turn) == my_color, 90.0):
				await _fail("net-join-illegal-geometry", "our turn never came")
				return
			if not await _net_illegal_probe(game, netm, "geometry", "e8", "e5",
					["not a legal move"], true):
				return
			probed_illegal = true
		if not await _net_play(game, tag, my_line[i]):
			return
	# The last ply may be the opponent's; wait for the whole game either way.
	if not await _wait_until(func():
		return (game.get("net_plies") as Array).size() >= NET_TOTAL_PLIES, 120.0):
		await _fail("net-%s-plies" % tag, "only %d of %d plies completed"
			% [(game.get("net_plies") as Array).size(), NET_TOTAL_PLIES])
		return
	_pass("net-%s-plies (%d)" % [tag, (game.get("net_plies") as Array).size()])

	# THE UNDERPROMOTION, CHECKED ON BOTH BOARDS. The joiner's picker chose a
	# KNIGHT; the host validated it out of its own legal-move list and
	# broadcast it back. Both instances must hold the same piece, in the
	# engine AND in the army standing on the board — a client that could
	# promote to something the host never validated shows up right here, and
	# so does a piece that survived the wire but spawned as a queen.
	var b1 := ChessState.square_index_from_name("b1")
	if str(state.pieces[b1]) != "n":
		await _fail("net-%s-underpromotion" % tag,
			"b1 holds '%s', expected the joiner's knight" % str(state.pieces[b1]))
		return
	var knight_view = (game.get("views") as Dictionary).get(game.sq_of(b1))
	if knight_view == null or not is_instance_valid(knight_view) \
			or int(knight_view.piece_type) != PieceView.Type.KNIGHT:
		await _fail("net-%s-underpromotion" % tag,
			"the piece standing on b1 is %s, expected a KNIGHT"
				% ("nothing" if knight_view == null else str(int(knight_view.piece_type))))
		return
	_pass("net-%s-underpromotion (a knight on b1, engine and board)" % tag)

	# The duel ran here, not only on the other machine.
	if (game.get("death_log") as Array).is_empty():
		await _fail("net-%s-duel" % tag, "no death animation played on this instance")
		return
	_pass("net-%s-duel (%s)" % [tag, str((game.get("death_log") as Array).back())])
	if not await _wait_until(func(): return _net_duel_shot, 20.0):
		await _fail("net-%s-duel-photographed" % tag,
			"the capture duel was never photographed on this instance")
		return
	_pass("net-%s-duel-photographed" % tag)

	# Checkmate: the same verdict on both screens, and no unilateral rematch.
	if not await _wait_until(func(): return bool(game.get("game_over")), 60.0):
		await _fail("net-%s-checkmate" % tag, "the game never ended")
		return
	if state.get_result() != ChessState.RESULT.CHECKMATE:
		await _fail("net-%s-checkmate" % tag, "result=%d, expected CHECKMATE"
			% state.get_result())
		return
	_pass("net-%s-checkmate" % tag)
	if not await _wait_until(func(): return bool(game.get("_victory_shown")), 70.0):
		await _fail("net-%s-verdict" % tag, "the verdict card never opened")
		return
	var cont: Button = game.find_child("ContinueButton", true, false)
	if cont == null or not cont.text.contains("Hall of Banners"):
		await _fail("net-%s-verdict" % tag,
			"the network verdict card offers '%s' — it must send both players home, "
			% (cont.text if cont != null else "<absent>") + "never a one-sided rematch")
		return
	_pass("net-%s-verdict (%s)" % [tag, cont.text])
	await _shot("checkmate")

	# THE NEW GUARDS MUST BE INERT IN AN HONEST MATCH (verifier defects P1/P2/P3,
	# 2026-08-09). The host now drops a hello once the match has started, and
	# drops any ack or move request from a peer that does not hold the joiner's
	# seat; the joiner now puts every request on a deadline. A whole real game —
	# five plies, a duel and a mate — must trip NONE of them. A guard that
	# refuses honest traffic is a worse bug than the one it was added for.
	var refused: int = int(netm.get("refused_packet_count"))
	if refused != 0:
		await _fail("net-%s-guards-inert" % tag,
			"%d legitimate packet(s) were dropped by the host guards (last: '%s')"
				% [refused, str(netm.get("last_refused_packet"))])
		return
	_pass("net-%s-guards-inert" % tag)
	var late: int = int(netm.get("request_slow_count"))
	var stalled: int = int(netm.get("request_stalled_count")) \
		+ int(game.get("net_stalled_count"))
	if stalled != 0 or late != 0:
		await _fail("net-%s-no-false-stall" % tag,
			"the move-request deadline fired in a healthy match (late=%d stalled=%d)"
				% [late, stalled])
		return
	_pass("net-%s-no-false-stall" % tag)

	# The final board, printed last so the runner can pin the end state too.
	print("E2E NETFINAL %s" % str(state.get_fen()))
	print("E2E NETREJECTS %d" % (game.get("net_rejections") as Array).size())
	_finish(0)


## Photograph the capture duel the moment the director takes the camera —
## fire-and-forget, because the main flow is busy waiting for the ply to land.
func _net_duel_watch(game: Node) -> void:
	var dd: Node = game.get("duel_director")
	if dd == null:
		return
	if not await _wait_until(func(): return dd.is_active(), 150.0):
		return
	await _sleep_wall(1.1)   # wall clock: the duel BENDS Engine.time_scale
	await _shot("mid_duel")
	_net_duel_shot = true


## HOST AUTHORITY, live on the wire: hand the transport a move the host must
## refuse, and prove (a) it is refused with a reason, (b) the board does not
## move, on this instance or the other one.
## `check_board` is false for the wrong-turn probe: it fires while the OPPONENT
## legitimately owns the move, so the FEN is allowed to change under it — what
## must never happen is OUR uci appearing in the applied-ply log, and that is
## asserted in both cases.
##
## `want_reasons` is a LIST because some probes race the opponent's own ply and
## have more than one correct refusal (see the wrong-turn probe). Any one of
## them passes, and the one actually observed is printed in the PASS line, so a
## drift in which branch fires is visible in the log instead of silent.
func _net_illegal_probe(game: Node, netm: Node, label: String, from_name: String,
		to_name: String, want_reasons: Array, check_board: bool) -> bool:
	var state: Object = game.get("state")
	var fen_before := str(state.get_fen())
	var uci := from_name + to_name
	var rejects_before: int = (game.get("net_rejections") as Array).size()
	var bad := ChessMove.new()
	bad.from_square = ChessState.square_index_from_name(from_name)
	bad.to_square = ChessState.square_index_from_name(to_name)
	netm.request_move(bad)
	if not await _wait_until(func():
		return (game.get("net_rejections") as Array).size() > rejects_before, 15.0):
		await _fail("net-illegal-%s" % label,
			"the host ACCEPTED %s — a client forced an illegal move" % uci)
		return false
	var reason: String = str((game.get("net_rejections") as Array).back())
	var matched := want_reasons.is_empty()
	for want in want_reasons:
		if reason.contains(str(want)):
			matched = true
			break
	if not matched:
		await _fail("net-illegal-%s" % label,
			"refused, but for none of the reasons this probe accepts %s: '%s'"
				% [str(want_reasons), reason])
		return false
	await _sleep(0.5)
	for entry in (game.get("net_plies") as Array):
		if str(entry).contains("|%s|" % uci):
			await _fail("net-illegal-%s" % label,
				"the refused move %s was applied anyway (%s)" % [uci, str(entry)])
			return false
	if check_board and str(state.get_fen()) != fen_before:
		await _fail("net-illegal-%s" % label,
			"the board moved on a refused request (%s -> %s)"
				% [fen_before, str(state.get_fen())])
		return false
	_pass("net-illegal-%s refused (%s)" % [label, reason])
	return true


## One scripted ply, played the way a human plays it: click the piece, click
## the square. Nothing is applied locally — the host's broadcast is what moves
## the board, on both machines.
func _net_play(game: Node, tag: String, uci: String) -> bool:
	var state: Object = game.get("state")
	var my_color: bool = bool(game.get("player_color"))
	if not await _wait_until(func():
		return not bool(game.get("busy")) and bool(state.turn) == my_color \
			and not bool(game.get("game_over")), 120.0):
		await _fail("net-%s-turn-%s" % [tag, uci], "our turn for %s never came" % uci)
		return false
	var from_idx := ChessState.square_index_from_name(uci.substr(0, 2))
	var to_idx := ChessState.square_index_from_name(uci.substr(2, 2))
	if not await _select_square(game, game.sq_of(from_idx)):
		await _fail("net-%s-select-%s" % [tag, uci], "could not select %s" % uci.substr(0, 2))
		return false
	await _click_square(game, game.sq_of(to_idx))
	if uci.length() > 4:
		# A PROMOTION ON THE WIRE. The picker opens on THIS machine, the piece
		# it answers rides in the move request, and the HOST's validator is the
		# only thing that decides whether it is legal. Taken by hotkey so the
		# choice is unambiguous in the log.
		var want := uci.substr(4, 1)
		if not await _wait_until(func(): return game.get("promo_picker") != null, 8.0):
			await _fail("net-%s-promo-picker" % tag,
				"the promotion picker never opened for %s" % uci)
			return false
		await _press_key(_promo_hotkey(want))
		if not await _wait_until(func(): return game.get("promo_picker") == null, 8.0):
			await _fail("net-%s-promo-picker" % tag, "the picker never closed for %s" % uci)
			return false
		_pass("net-%s-promo-picked (%s)" % [tag, PromotionPicker.NAMES[want]])
	if not await _wait_until(func(): return state.pieces[from_idx] == null, 25.0):
		await _fail("net-%s-applied-%s" % [tag, uci],
			"the host never broadcast %s back" % uci)
		return false
	_pass("net-%s-played (%s)" % [tag, uci])
	if not _net_first_move_shot:
		_net_first_move_shot = true
		await _shot("after_%s" % uci)
	return true


# ── Scenario: net-hall (the Play a Friend panel, through real clicks) ──────
## The two-instance gate proves the MATCH; this proves the DOOR. Every step is
## a synthesized click on the real Hall of Banners: pick a banner, pick "Play a
## Friend", host (addresses appear, the socket is really listening), back out,
## then dial an address nobody is answering and read the error a human gets.
func _scenario_net_hall() -> void:
	if not await _wait_until(func(): return _select_screen() != null, 20.0):
		await _fail("hall-present", "the Hall of Banners never appeared")
		return
	var sel: Control = _select_screen()
	await _sleep(0.4)
	var crest: Node = sel.find_child("Crest_%s" % DEFAULT_HOUSE, true, false)
	if crest == null:
		await _fail("hall-crest", "no crest for house '%s'" % DEFAULT_HOUSE)
		return
	if not await _click_until(crest.get_node("Sigil"),
			func(): return int(sel.get("phase")) == 1, "crest"):
		await _fail("hall-crest", "crest clicks never advanced to the opponent phase")
		return
	_pass("hall-house")

	var friend_btn := _find_button(sel, "Play a Friend")
	if friend_btn == null:
		await _fail("hall-friend-entry", "no 'Play a Friend' entry in the opponent panel")
		return
	# Phase.NET is 4 (appended last so HOUSE/OPPONENT/MODE/DONE keep their ids).
	if not await _click_until(friend_btn,
			func(): return int(sel.get("phase")) == 4, "play-a-friend"):
		await _fail("hall-friend-entry", "'Play a Friend' never opened the network panel")
		return
	_pass("hall-friend-entry")
	await _shot("play_a_friend")

	var host_btn := _find_button(sel, "Host a Match")
	if host_btn == null:
		await _fail("hall-host-button", "no 'Host a Match' button")
		return
	await _click_control(host_btn)
	await _sleep(0.3)
	var side_btn := _find_button(sel, "You ride for Black")
	if side_btn == null:
		await _fail("hall-side-choice", "the host panel offers no side choice")
		return
	await _click_control(side_btn)
	_pass("hall-side-choice")
	var gates := _find_button(sel, "Open the Gates")
	if gates == null:
		await _fail("hall-open-gates", "no 'Open the Gates' button")
		return
	await _click_control(gates)
	if not await _wait_until(func():
		var n := NetMatch.get_active(get_tree())
		return n != null and n.state == NetMatch.State.HOSTING, 10.0):
		await _fail("hall-hosting", "the host never started listening")
		return
	var live := NetMatch.get_active(get_tree())
	if bool(live.get("my_color")) != NetProtocol.COLOR_BLACK:
		await _fail("hall-side-choice", "chose Black but the host seated itself as White")
		return
	var share: Label = sel.find_child("NetShare", true, false)
	if share == null or not share.visible or not share.text.contains(":%d"
			% NetProtocol.DEFAULT_PORT):
		await _fail("hall-share-address",
			"the host panel never showed an address to send a friend: '%s'"
				% (share.text if share != null else "<absent>"))
		return
	_pass("hall-hosting (%s)" % share.text.replace("\n", " | "))
	await _shot("hosting_addresses")

	# WHAT THE HOST IS TOLD BEFORE ANYTHING GOES WRONG (verifier notes,
	# 2026-08-09). Both of these used to live only inside a failure message.
	var prereq: Label = sel.find_child("NetPrereq", true, false)
	if prereq == null or not prereq.is_visible_in_tree() \
			or not prereq.text.contains("Wi-Fi") or not prereq.text.contains("tailnet"):
		await _fail("hall-prerequisite",
			"the panel never states what you both need BEFORE you host: '%s'"
				% (prereq.text if prereq != null else "<absent>"))
		return
	_pass("hall-prerequisite (%s)" % prereq.text)
	var firewall: Label = sel.find_child("NetFirewallNote", true, false)
	if firewall == null or not firewall.is_visible_in_tree() \
			or not firewall.text.contains("Allow"):
		await _fail("hall-firewall-note",
			"nothing warns the host about the 'allow incoming connections' prompt: '%s'"
				% (firewall.text if firewall != null else "<absent>"))
		return
	_pass("hall-firewall-note")

	# THE ORDER OF THE SHARE LIST: the line to try first must BE first, and say so.
	var share_lines: PackedStringArray = share.text.split("\n", false)
	var first_addr_line := ""
	for l in share_lines:
		if str(l).contains(":%d" % NetProtocol.DEFAULT_PORT):
			first_addr_line = str(l)
			break
	if first_addr_line.is_empty() or not first_addr_line.contains("first"):
		await _fail("hall-share-order",
			"the first address offered does not say it is the one to try: '%s'"
				% first_addr_line)
		return
	_pass("hall-share-order (%s)" % first_addr_line.strip_edges())

	# THE COPY BUTTON: a host must not have to read an IP out digit by digit.
	var copy_btn := _find_button(sel, "Copy")
	if copy_btn == null or not copy_btn.is_visible_in_tree():
		await _fail("hall-copy-button", "the host panel offers no way to copy the address")
		return
	DisplayServer.clipboard_set("")     # so a stale clipboard cannot pass this
	await _click_control(copy_btn)
	await _sleep(0.3)
	var copied := str(sel.get("net_last_copied"))
	var on_clipboard := DisplayServer.clipboard_get()
	if int(sel.get("net_copied_count")) != 1 or copied.is_empty():
		await _fail("hall-copy-button", "the copy button did not fire (count=%s, '%s')"
			% [str(sel.get("net_copied_count")), copied])
		return
	if on_clipboard != copied:
		await _fail("hall-copy-button",
			"the clipboard holds '%s' but the panel claims it copied '%s'"
				% [on_clipboard, copied])
		return
	if not first_addr_line.contains(copied):
		await _fail("hall-copy-button",
			"it copied '%s', which is not the address it offered first ('%s')"
				% [copied, first_addr_line])
		return
	# ...and SAYS so, visibly — a clipboard write is invisible by nature.
	var copied_note: Label = sel.find_child("NetCopied", true, false)
	if copied_note == null or not copied_note.is_visible_in_tree() \
			or not copied_note.text.contains(copied):
		await _fail("hall-copy-confirmed",
			"nothing on screen confirms the copy happened: '%s'"
				% (copied_note.text if copied_note != null else "<absent>"))
		return
	_pass("hall-copy-button (clipboard = %s)" % on_clipboard)
	await _shot("copied_address")

	# Back out THROUGH THE VISIBLE CONTROL (verifier note): "waiting for your
	# friend to join…" used to offer no button at all — Esc worked, but only as
	# a line of footer text. The panel must HANG UP, not just hide, or the next
	# Host attempt collides with its own listening socket.
	var cancel_btn := _find_button(sel, "Cancel")
	if cancel_btn == null or not cancel_btn.is_visible_in_tree():
		await _fail("hall-cancel-button",
			"there is no visible way out while the room is open")
		return
	await _click_control(cancel_btn)
	if not await _wait_until(func():
		return int(sel.get("phase")) == 1 and NetMatch.get_active(get_tree()) == null, 8.0):
		await _fail("hall-cancel", "the Cancel button did not close the room (phase=%d, net=%s)"
			% [int(sel.get("phase")), str(NetMatch.get_active(get_tree()))])
		return
	_pass("hall-cancel-hangs-up (visible button)")

	# The error a human actually gets: dial a port nobody is listening on.
	friend_btn = _find_button(sel, "Play a Friend")
	if not await _click_until(friend_btn,
			func(): return int(sel.get("phase")) == 4, "play-a-friend-2"):
		await _fail("hall-rejoin", "could not reopen the network panel")
		return
	var join_btn := _find_button(sel, "Join a Match")
	await _click_control(join_btn)
	await _sleep(0.3)
	var field: LineEdit = sel.find_child("NetAddress", true, false)
	if field == null:
		await _fail("hall-join-field", "no address field in the join panel")
		return
	# THE WHOLE PASTED LINE (verifier note, 2026-08-09). The host panel prints
	# an address followed by the line that says when to use it, and people
	# select the whole line — because that is what a line is. This pastes one
	# through the real clipboard with the real Cmd/Ctrl+V, and the field must
	# understand it: before, the commentary went to ENet verbatim and came back
	# as "could not reach 127.0.0.1:7899   ·  same Wi-Fi…", which reads like a
	# wrong address rather than like a parsing problem.
	var pasted := "127.0.0.1:7899   ·  same Wi-Fi — try this one first"
	DisplayServer.clipboard_set(pasted)
	field.clear()
	field.grab_focus()
	await _press_paste()
	await _sleep(0.3)
	if field.text != pasted:
		await _fail("hall-join-field", "the pasted line did not land in the field: '%s'"
			% field.text)
		return
	_pass("hall-join-field-pasted (%s)" % field.text)
	var ride := _find_button(sel, "Ride Out")
	await _click_control(ride)
	if not await _wait_until(func(): return field.text == "127.0.0.1:7899", 5.0):
		await _fail("hall-join-paste-understood",
			"the field kept the commentary instead of showing what it understood: '%s'"
				% field.text)
		return
	_pass("hall-join-paste-understood (%s)" % field.text)
	var status: Label = sel.find_child("NetStatus", true, false)
	if status == null:
		await _fail("hall-join-error", "the join panel has no status line")
		return
	if not await _wait_until(func():
		return status.text.contains("could not reach"), 25.0):
		await _fail("hall-join-error",
			"an unreachable host produced no actionable message: '%s'" % status.text)
		return
	# It must name the ADDRESS, not echo back the line that was pasted. (The
	# error's own prose legitimately says "the same Wi-Fi or the same tailnet",
	# so the tell is the commentary marker the host panel prints, never those
	# words.)
	if not status.text.contains("127.0.0.1:7899") or status.text.contains("·") \
			or status.text.contains("try this one first"):
		await _fail("hall-join-error",
			"the error does not name the ADDRESS that failed (it kept the pasted "
			+ "commentary): '%s'" % status.text)
		return
	_pass("hall-join-error (%s)" % status.text)
	await _shot("join_error")
	_finish(0)


## Paste through the REAL shortcut, the way a player pastes an address a
## friend sent them. Cmd+V on macOS, Ctrl+V elsewhere — exactly one modifier,
## because the InputMap's ui_paste action matches modifiers exactly.
func _press_paste() -> void:
	var down := InputEventKey.new()
	down.keycode = KEY_V
	down.physical_keycode = KEY_V
	down.unicode = "v".unicode_at(0)
	down.pressed = true
	if OS.get_name() == "macOS":
		down.meta_pressed = true
	else:
		down.ctrl_pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up: InputEventKey = down.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


## Type a string through the REAL input pipeline (unicode-carrying key events),
## so a LineEdit is filled the way a player fills it.
func _type_text(text: String) -> void:
	for i in text.length():
		var ch := text[i]
		var down := InputEventKey.new()
		down.pressed = true
		down.unicode = ch.unicode_at(0)
		down.keycode = ch.to_upper().unicode_at(0) as Key
		down.physical_keycode = down.keycode
		Input.parse_input_event(down)
		await get_tree().process_frame
		var up := InputEventKey.new()
		up.pressed = false
		up.unicode = ch.unicode_at(0)
		up.keycode = down.keycode
		up.physical_keycode = down.keycode
		Input.parse_input_event(up)
		await get_tree().process_frame


# ── Scenario: music (playlists, mute, duck + sting through real signals) ───
func _scenario_music() -> void:
	var music: Node = get_node_or_null("/root/Music")
	if music == null:
		await _fail("music-autoload", "no /root/Music autoload registered")
		return
	_pass("music-autoload")
	if not await _wait_until(func(): return _select_screen() != null, 15.0):
		await _fail("music-select-screen", "the Hall of Banners never appeared")
		return
	if not await _wait_until(func():
		return str(music.current_mode()) == "menu" and music.live_deck() != null \
			and music.live_deck().playing, 8.0):
		await _fail("music-menu-track", "menu playlist never started (mode='%s')"
			% str(music.current_mode()))
		return
	_pass("music-menu-track (%s)"
		% str(music.live_deck().stream.resource_path).get_file())
	# The CC BY attribution label rides the select screen.
	if _select_screen().find_child("MusicCredits", true, false) == null:
		await _fail("music-credits-label", "no MusicCredits label on the select screen")
		return
	_pass("music-credits-label")
	# M toggles mute — real input path, asserted on the Music bus itself.
	var bus := AudioServer.get_bus_index("Music")
	await _press_key(KEY_M)
	if not await _wait_until(func():
		return bool(music.is_muted()) and AudioServer.is_bus_mute(bus), 3.0):
		await _fail("music-mute", "M did not mute the Music bus")
		return
	await _press_key(KEY_M)
	if not await _wait_until(func():
		return not bool(music.is_muted()) and not AudioServer.is_bus_mute(bus), 3.0):
		await _fail("music-unmute", "second M did not unmute the Music bus")
		return
	_pass("music-mute-toggle (M, bus-verified)")
	if not await _navigate_select(DEFAULT_HOUSE, "Casual", "Single Match"):
		return
	var game := await _boot_game(0)
	if game == null:
		return
	if not await _wait_until(func(): return str(music.current_mode()) == "game", 8.0):
		await _fail("music-game-track", "gameplay playlist never started (mode='%s')"
			% str(music.current_mode()))
		return
	_pass("music-game-track")
	# The scripted duel: sting + duck on the way in, unduck once settled.
	var state: Object = game.get("state")
	if not await _wait_until(func():
		return game.get("busy") == false and state.turn == false, 15.0):
		await _fail("music-player-turn", "never became the player's turn")
		return
	var capture = await _click_first_matching(game,
		func(m): return m.is_capture(), "music-capture")
	if capture == null:
		return
	var dd: Node = game.get("duel_director")
	if not await _wait_until(func(): return dd.is_active(), 8.0):
		await _fail("music-duel-started", "duel director never became active")
		return
	if not await _wait_until(func(): return bool(music.is_ducked()), 3.0):
		await _fail("music-duel-duck", "playlist never ducked for the duel")
		return
	if not await _wait_until(func(): return music.sting_player().playing, 3.0):
		await _fail("music-duel-sting", "no stinger fired at the duel start")
		return
	_pass("music-duel-duck+sting")
	# The deck's actual volume follows the duck target (−8 dB, 0.35 s ramp).
	if not await _wait_until(func():
		return music.live_deck().volume_db < -7.0, 3.0):
		await _fail("music-duck-volume",
			"live deck never reached the duck level (%.1f dB)"
			% music.live_deck().volume_db)
		return
	_pass("music-duck-volume (%.1f dB)" % music.live_deck().volume_db)
	await _shot("mid_duel_ducked")
	# Full settle (the rival's reply may duel too) — then the duck must lift.
	if not await _wait_until(func():
		return game.get("busy") == false and not dd.is_active(), 40.0):
		await _fail("music-settled", "board never settled after the duel")
		return
	if not await _wait_until(func():
		return not bool(music.is_ducked()) and music.live_deck().volume_db > -1.0, 5.0):
		await _fail("music-unduck", "playlist never unducked after the cinematics (%.1f dB)"
			% music.live_deck().volume_db)
		return
	_pass("music-unduck (%.1f dB)" % music.live_deck().volume_db)
	if not is_equal_approx(Engine.time_scale, 1.0):
		await _fail("music-timescale", "time_scale=%f after settle" % Engine.time_scale)
		return
	_pass("music-timescale-1.0")
	await _shot("post_duel_music")
	_finish(0)

# ── Scenario: banter (rival smack talk through the real HUD) ───────────────
## FEN contract (run_e2e.sh BANTER_FEN): White Qd1 Ke1 Pe4 Ph4 · Black Ka8
## Pd5 Ph5 — a capture NOW (first blood, fullmove 1) and a guaranteed second
## capture (Qxh5) two plies later; the wedged h-pawn and the far king make
## both deterministic. DS4_CHESS_URL points at a dead port (set in _ready)
## so every line is a synchronous canned-pool line.
var _banter_skips: Array = []   # [beat, why] pairs recorded off banter_skipped

func _scenario_banter() -> void:
	if not await _navigate_select(DEFAULT_HOUSE, "Casual", "Single Match"):
		return
	var game := await _boot_game(0)
	if game == null:
		return
	var banter: Node = game.get("banter")
	if banter == null:
		await _fail("banter-node", "game did not create the BanterEngine node")
		return
	_pass("banter-node (rival: %s)" % str(banter.get("house_id")))
	banter.banter_skipped.connect(func(beat: String, why: String) -> void:
		_banter_skips.append([beat, why]))
	var caption: Label = game.find_child("BanterCaption", true, false)
	if caption == null:
		await _fail("banter-caption-node", "no BanterCaption label in the HUD")
		return
	# The opening taunt (game_start, pool path) in the rival's accent color.
	if not await _wait_until(func(): return caption.visible, 10.0):
		await _fail("banter-opening-line", "no opening caption (taunts=%d skips=%d)"
			% [int(banter.get("taunt_count")), int(banter.get("skip_count"))])
		return
	var rival := str(game.get("rival_house_id"))
	var accent: Color = HouseRegistry.get_colors(rival)["accent"]
	var got: Color = caption.get_theme_color("font_color")
	var why_accent := _accent_identity_why(game, got, accent)
	if not why_accent.is_empty():
		await _fail("banter-accent-color", why_accent)
		return
	_pass("banter-opening-line (accent-tinted: %s)" % caption.text)
	var opening_text := caption.text
	# Capture #1 (fullmove 1): the first-blood beat must land in the HUD.
	var state: Object = game.get("state")
	if not await _wait_until(func():
		return game.get("busy") == false and state.turn == false, 15.0):
		await _fail("banter-player-turn", "never became the player's turn")
		return
	var taunts_before := int(banter.get("taunt_count"))
	var cap1 = await _click_first_matching(game,
		func(m): return m.is_capture(), "banter-cap1")
	if cap1 == null:
		return
	if not await _wait_until(func():
		return int(banter.get("taunt_count")) > taunts_before \
			and caption.visible and caption.text != opening_text, 20.0):
		await _fail("banter-capture-line", "capture taunt never reached the HUD (taunts=%d)"
			% int(banter.get("taunt_count")))
		return
	got = caption.get_theme_color("font_color")
	why_accent = _accent_identity_why(game, got, accent)
	if not why_accent.is_empty():
		await _fail("banter-capture-accent", why_accent)
		return
	_pass("banter-capture-line (%s)" % caption.text)
	await _shot("banter_capture_caption")
	var capture_text := caption.text
	var taunts_after_cap := int(banter.get("taunt_count"))
	# Two more plies (rival's reply + our second capture): the module must
	# HOLD the 2-fullmove gap — skip evidence, no new caption, no new taunt.
	if not await _wait_until(func():
		return game.get("busy") == false and state.turn == false, 30.0):
		await _fail("banter-turn-2", "board never settled before the second capture")
		return
	var cap2 = await _click_first_matching(game,
		func(m): return m.is_capture(), "banter-cap2")
	if cap2 == null:
		return
	if not await _wait_until(func(): return _banter_skipped("rate_limited"), 20.0):
		await _fail("banter-rate-limited",
			"second capture beat was not rate-limited (skips=%s taunts=%d)"
			% [str(_banter_skips), int(banter.get("taunt_count"))])
		return
	if int(banter.get("taunt_count")) != taunts_after_cap:
		await _fail("banter-rate-limit-held", "a taunt landed inside the fullmove gap")
		return
	if caption.visible and caption.text != capture_text:
		await _fail("banter-caption-unchanged",
			"caption changed inside the gap: %s" % caption.text)
		return
	_pass("banter-rate-limited (2-fullmove gap held across 2 more plies)")
	if not await _wait_until(func(): return game.get("busy") == false, 30.0):
		await _fail("banter-settled", "board never settled")
		return
	_pass("banter-settled (taunts=%d skips=%d)"
		% [int(banter.get("taunt_count")), int(banter.get("skip_count"))])
	await _shot("banter_final")
	_finish(0)

func _banter_skipped(why: String) -> bool:
	for s in _banter_skips:
		if str(s[1]) == why:
			return true
	return false

# ── Scenario: dragon-live (the wyrm watches; ASHFALL burns the losers) ─────
## FEN contract (run_e2e.sh DRAGON_FEN): Ra8# is mate-in-1 and the mated
## house keeps three pawns — fuel for the pyre. Asserts the full integration:
## spawn/perch, notice_move feed, duel-cam reaction gate, ASHFALL chain,
## time_scale + view hygiene, victory flow.
func _scenario_dragon_live() -> void:
	if not await _navigate_select(DEFAULT_HOUSE, "Casual", "Single Match"):
		return
	var game := await _boot_game(0)
	if game == null:
		return
	var spectator: Node = game.get("spectator")
	if spectator == null or not is_instance_valid(spectator):
		await _fail("dragon-present", "game did not spawn the DragonSpectator")
		return
	var hall: Node = game.get_node_or_null("GreatHall")
	if hall == null \
			or not (spectator.get("perch_position") as Vector3) \
			.is_equal_approx(hall.spectator_perch()):
		await _fail("dragon-perched", "spectator perch %s != hall.spectator_perch()"
			% str(spectator.get("perch_position")))
		return
	_pass("dragon-present (perched at %s)" % str(spectator.get("perch_position")))
	if not bool(spectator.call("can_react")):
		await _fail("dragon-can-react", "spectator cannot react while idle")
		return
	if (spectator.get("_last_move_pos") as Vector3).is_finite():
		await _fail("dragon-glance-idle", "glance target set before any ply")
		return
	_pass("dragon-idle-ready (can_react, no glance target yet)")
	# ── THE SLEEPER, PHOTOGRAPHED FROM THE PLAYER'S OWN SEAT ──
	# The dragon spends the whole match coiled on the stone beside the board.
	# This shot is taken BEFORE any cinematic camera exists, so it is the
	# gameplay camera and nothing else — the only frame that can honestly
	# answer "does it read as a sleeping animal in the game?".
	if not bool(spectator.call("is_asleep")):
		await _fail("dragon-asleep", "the wyrm is not asleep at the board")
		return
	var rest_pos: Vector3 = spectator.get("rest_position")
	if rest_pos.y > 0.0 or absf(rest_pos.x) < 4.6:
		await _fail("dragon-rests-on-the-floor",
			"rest_position %s is not on the floor beside the board" % str(rest_pos))
		return
	_pass("dragon-asleep (coiled at %s, slumber %.2f)"
		% [str(rest_pos), float(spectator.call("slumber_weight"))])
	await _sleep(1.0)   # let the coil, torches and breathing settle
	await _shot("dragon_resting")
	var state: Object = game.get("state")
	if not await _wait_until(func():
		return game.get("busy") == false and state.turn == false, 15.0):
		await _fail("dragon-player-turn", "never became the player's turn")
		return
	# The FEN promises a mate-in-1 — find it in the SAN'd turn moves (the
	# tournament scenario's pattern; bare legal_moves() carries no SAN).
	var mate = null
	for m in game.get("_turn_moves"):
		if m.notation_san != null and str(m.notation_san).ends_with("#"):
			mate = m
			break
	if mate == null:
		await _fail("dragon-mate-available", "the FEN offers no mate-in-1")
		return
	_pass("dragon-mate-available (%s)" % mate.to_uci())
	if not await _select_square(game, game.sq_of(mate.from_square)):
		await _fail("dragon-mate-select", "mate mover never selected")
		return
	await _click_square(game, game.sq_of(mate.to_square))
	if not await _wait_until(func(): return bool(game.get("game_over")), 10.0):
		await _fail("dragon-mate-applied", "game never ended after the mate")
		return
	_pass("dragon-mate-applied")
	# Under the checkmate cinematic the duel cam owns the frame: gated.
	var dd: Node = game.get("duel_director")
	if await _wait_until(func(): return dd.is_active(), 10.0):
		if bool(spectator.call("can_react")):
			await _fail("dragon-duel-gate", "spectator can react under the duel cam")
			return
		_pass("dragon-duel-gate (reactions locked under the cinematic)")
	if not (spectator.get("_last_move_pos") as Vector3).is_finite():
		await _fail("dragon-notice-move", "notice_move never reached the spectator")
		return
	_pass("dragon-notice-move (glance target fed from the real ply)")
	# ASHFALL: chained after the king's death, before the victory flow.
	if not await _wait_until(func():
		return bool(spectator.call("is_ashfall_active")), 30.0):
		await _fail("dragon-ashfall-started", "ASHFALL never started after the checkmate")
		return
	_pass("dragon-ashfall-started")
	if not await _wait_until(func(): return Engine.time_scale < 0.9, 3.0):
		await _fail("dragon-ashfall-dip", "no cinematic time dip (%.2f)" % Engine.time_scale)
		return
	# ── THE CEREMONY, PHOTOGRAPHED ON ITS OWN CLOCK ──
	# Every shot below waits on the ceremony's PHASE, never on a stopwatch the
	# ceremony is bending (see _sleep_wall). The wide silhouette shot is the
	# bank; the fire shots are gated on the jet actually burning.
	# THE WAKE comes first: the wyrm is still on the floor, head up, jaw wide.
	# Gated on the phase for the same reason as the fire — a stopwatch would
	# photograph whatever the bent clock happened to be showing.
	if not await _wait_until(func():
		return str(spectator.call("ashfall_phase")) == "roar", 8.0):
		await _fail("dragon-wake-roar", "the wyrm never roared (phase=%s)"
			% str(spectator.call("ashfall_phase")))
		return
	await _sleep_wall(0.35)   # into the roar: head up, jaw at its widest
	await _shot("wake_roar")
	if not (spectator.get("position") as Vector3).is_equal_approx(
			spectator.get("rest_position") as Vector3):
		var dy: float = absf((spectator.get("position") as Vector3).y
			- (spectator.get("rest_position") as Vector3).y)
		if dy > 0.6:
			await _fail("dragon-roars-on-the-ground",
				"the wyrm was already %.2f m airborne when it roared" % dy)
			return
	_pass("dragon-wake-roar (roared on the stone, before the wings)")
	if not await _wait_until(func():
		return str(spectator.call("ashfall_phase")) == "bank", 4.0):
		await _fail("dragon-ashfall-bank", "the ceremony never reached the bank")
		return
	await _sleep_wall(1.4)   # mid-lap: the wyrm crossing the hall in profile
	await _shot("mid_ashfall")
	_pass("dragon-bank-photographed")
	# THE TORRENT. The jet ignites a quarter of the way into the breath beat;
	# is_jet_burning() is true only while the jet itself (not its ember tail)
	# is up, so this cannot photograph an empty sky again.
	if not await _wait_until(func():
		return bool(spectator.call("is_jet_burning")), 12.0):
		await _fail("dragon-jet-lit",
			"the jet never ignited (phase=%s)" % str(spectator.call("ashfall_phase")))
		return
	_pass("dragon-jet-lit (phase=%s)" % str(spectator.call("ashfall_phase")))
	await _sleep_wall(0.7)   # into the sweep — the torrent at full length
	var torrent_img: Image = await _shot("torrent")
	var fire := _report_fire("torrent", torrent_img)
	if float(fire["share"]) < FIRE_TORRENT_MIN_SHARE:
		await _fail("dragon-torrent-photographed",
			"only %.3f%% of the torrent frame is flame (need %.1f%%)"
				% [fire["share"], FIRE_TORRENT_MIN_SHARE])
		return
	_pass("dragon-torrent-photographed (%.2f%% flame)" % fire["share"])
	# THE TAIL. cut() retracts the jet and leaves embers, drifting ash, ground
	# fire and smoke alive — the beat the linger phase exists to show.
	if not await _wait_until(func():
		return not bool(spectator.call("is_jet_burning")), 12.0):
		await _fail("dragon-jet-cut", "the jet never cut")
		return
	await _sleep_wall(1.2)
	var tail_img: Image = await _shot("ember_tail")
	var tail := _report_fire("ember_tail", tail_img)
	if not bool(spectator.call("is_fire_tail_alive")):
		await _fail("dragon-ember-tail", "the fire died with the jet — no tail")
		return
	if float(tail["share"]) < FIRE_TAIL_MIN_SHARE:
		await _fail("dragon-ember-tail",
			"only %.3f%% of the tail frame is ember/ash fire (need %.1f%%)"
				% [tail["share"], FIRE_TAIL_MIN_SHARE])
		return
	_pass("dragon-ember-tail (%.2f%% flame)" % tail["share"])
	if not await _wait_until(func():
		return not bool(spectator.call("is_ashfall_active")), 15.0):
		await _fail("dragon-ashfall-finished", "ASHFALL never finished")
		return
	_pass("dragon-ashfall-finished")
	if not await _wait_until(func():
		return is_equal_approx(Engine.time_scale, 1.0), 5.0):
		await _fail("dragon-timescale", "time_scale=%f after ASHFALL" % Engine.time_scale)
		return
	_pass("dragon-timescale-1.0")
	if not await _wait_until(func(): return _dragon_losers_purged(game), 10.0):
		await _fail("dragon-losers-purged", "loser views survived ASHFALL (views=%d)"
			% (game.get("views") as Dictionary).size())
		return
	_pass("dragon-losers-purged (only the two white views remain)")
	if not await _wait_until(func():
		var vp = game.get("_victory_panel")
		return vp != null and vp.visible, 15.0):
		await _fail("dragon-victory-flow", "victory panel never appeared")
		return
	_pass("dragon-victory-flow")
	# THE ARC CLOSES. It flew back down to the same stone, landed, and coiled
	# up again — so the next match starts from rest and the wake still has
	# somewhere to go. Photographed AFTER the coil is back, not during it.
	if not await _wait_until(func():
		return bool(spectator.call("is_asleep")) \
			and float(spectator.call("slumber_weight")) > 0.9, 8.0):
		await _fail("dragon-resettles",
			"the wyrm never went back to sleep (slumber %.2f at %s)"
				% [float(spectator.call("slumber_weight")),
					str(spectator.get("position"))])
		return
	_pass("dragon-resettles (asleep again on its own stone)")
	await _shot("after_ashfall")
	_finish(0)

## True when only the two live white views (Ra8 + Ke1) remain and no freed
## corpse lingers in the views dict.
func _dragon_losers_purged(game: Node) -> bool:
	var views: Dictionary = game.get("views")
	if views.size() != 2:
		return false
	for sq in views:
		var pv = views[sq]
		if pv == null or not is_instance_valid(pv) \
				or int(pv.get("side")) != PieceView.House.FROST:
			return false
	return true

# ── Scenario: fullgame (two-rook ladder mate, Gate D) ──────────────────────
func _scenario_fullgame() -> void:
	if not await _navigate_select(DEFAULT_HOUSE, "Casual", "Single Match"):
		return
	var game := await _boot_game(0)
	if game == null:
		return
	var state: Object = game.get("state")
	var dd: Node = game.get("duel_director")
	var white_plies := 0
	while white_plies < 40:
		if not await _wait_until(func():
			return bool(game.get("game_over")) \
				or (game.get("busy") == false and state.turn == false and not dd.is_active()), 40.0):
			await _fail("fullgame-turn", "board never settled for White ply %d" % (white_plies + 1))
			return
		if bool(game.get("game_over")):
			break
		if not is_equal_approx(Engine.time_scale, 1.0):
			await _fail("fullgame-timescale", "time_scale=%f between moves" % Engine.time_scale)
			return
		if not await _assert_sync(game, "fullgame-sync-ply%d" % white_plies):
			return
		var mv = _ladder_pick(state, game)
		if mv == null:
			await _fail("fullgame-plan", "ladder found no move at ply %d" % white_plies)
			return
		if not await _select_square(game, game.sq_of(mv.from_square)):
			await _fail("fullgame-select", "could not select the mover for %s" % mv.to_uci())
			return
		await _click_square(game, game.sq_of(mv.to_square))
		if not await _wait_until(func():
			return state.turn == true or bool(game.get("game_over")), 6.0):
			await _fail("fullgame-applied", "engine never applied %s" % mv.to_uci())
			return
		white_plies += 1
	if white_plies >= 40:
		await _fail("fullgame-mate", "no mate within 40 White moves")
		return
	_pass("fullgame-mate-reached (%d white moves)" % white_plies)
	if state.get_result() != ChessState.RESULT.CHECKMATE or state.turn != true:
		await _fail("fullgame-result", "expected Black checkmated, result=%d" % state.get_result())
		return
	_pass("fullgame-checkmate")
	if not await _wait_until(func():
		var vp = game.get("_victory_panel")
		return vp != null and vp.visible, 25.0):
		await _fail("fullgame-victory-panel", "victory panel never appeared")
		return
	_pass("fullgame-victory-panel")
	if not await _wait_until(func():
		return is_equal_approx(Engine.time_scale, 1.0) and not dd.is_active(), 10.0):
		await _fail("fullgame-timescale-restored",
			"time_scale=%f after the end" % Engine.time_scale)
		return
	_pass("fullgame-timescale-restored")
	if not await _assert_sync(game, "fullgame-final-sync", true):
		return
	_pass("fullgame-final-sync")
	await _shot("fullgame_end")
	_finish(0)

## Two-rook ladder policy: mate-in-1 if available, else fence the row below
## the black king, else check on the king's row from a safe distance,
## sliding the fence away when the king hunts it. Falls back to any
## non-drawing move (never needed on a clean ladder).
func _ladder_pick(state: Object, game: Node) -> Variant:
	var moves: Array = game.get("_turn_moves")
	for m in moves:
		if m.notation_san != null and str(m.notation_san).ends_with("#"):
			return m
	var bk: int = state.get_king(true)
	@warning_ignore("integer_division")
	var kr: int = bk / 8
	var kc: int = bk % 8
	var rooks: Array[int] = []
	for i in 64:
		if str(state.pieces[i]) == "R":
			rooks.append(i)
	var fence := -1
	for r in rooks:
		@warning_ignore("integer_division")
		if r / 8 == kr + 1:
			fence = r
	if fence >= 0 and absi(fence % 8 - kc) <= 1:
		var flee = _rook_to_row(moves, fence, kr + 1, kc, 3)
		if flee != null:
			return flee
	if fence < 0:
		for r in rooks:
			var build = _rook_to_row(moves, r, kr + 1, kc, 2)
			if build != null:
				return build
	else:
		for r in rooks:
			if r == fence:
				continue
			var chk = _rook_to_row(moves, r, kr, kc, 2)
			if chk != null:
				return chk
	for m in moves:
		var probe = state.duplicate(false)
		var pm = probe.move_from_uci(m.to_uci())
		if pm == null:
			continue
		probe.apply_move(pm)
		var res: int = probe.get_result()
		if res == ChessState.RESULT.ONGOING or res == ChessState.RESULT.CHECKMATE:
			return m
	return null

func _rook_to_row(moves: Array, from_idx: int, want_row: int, king_col: int,
		min_dist: int) -> Variant:
	var best = null
	var best_d := -1
	for m in moves:
		if m.from_square != from_idx:
			continue
		@warning_ignore("integer_division")
		var tr: int = m.to_square / 8
		var tc: int = m.to_square % 8
		if tr != want_row:
			continue
		var d := absi(tc - king_col)
		if d < min_dist:
			continue
		if d > best_d:
			best_d = d
			best = m
	return best

# ── Canned OpenAI-style HTTP mock (oracle-mock scenario) ───────────────────
func _start_mock_oracle() -> bool:
	_mock_server = TCPServer.new()
	if _mock_server.listen(0, "127.0.0.1") != OK:
		return false
	_mock_port = _mock_server.get_local_port()
	OS.set_environment(Ds4Opponent.ENV_URL, "http://127.0.0.1:%d" % _mock_port)
	_mock_running = true
	_pump_mock.call_deferred()
	print("E2E mock oracle listening on 127.0.0.1:%d" % _mock_port)
	return true

func _pump_mock() -> void:
	while _mock_running:
		if _mock_server.is_connection_available():
			var peer := _mock_server.take_connection()
			await _handle_mock_conn(peer)
		await get_tree().process_frame

func _handle_mock_conn(peer: StreamPeerTCP) -> void:
	peer.set_no_delay(true)
	var raw := PackedByteArray()
	var deadline := Time.get_ticks_msec() + 5000
	var header_end := -1
	var content_len := 0
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		var n := peer.get_available_bytes()
		if n > 0:
			var chunk: Array = peer.get_data(n)
			if chunk[0] == OK:
				raw.append_array(chunk[1])
		if header_end < 0:
			header_end = _find_header_end(raw)
			if header_end >= 0:
				content_len = _parse_content_length(
					raw.slice(0, header_end).get_string_from_utf8())
		if header_end >= 0 and raw.size() >= header_end + content_len:
			break
		await get_tree().process_frame
	if header_end < 0:
		peer.disconnect_from_host()
		return
	var request_line := raw.slice(0, header_end).get_string_from_utf8().get_slice("\r\n", 0)
	var path := request_line.get_slice(" ", 1)
	var response_body: String
	var count_serve := false   # true for oracle chat replies (feeds _mock_served)
	if path.ends_with("/models"):
		response_body = JSON.stringify({
			"object": "list",
			"data": [{"id": MOCK_MODEL, "object": "model"}],
		})
	else:
		var body_text := raw.slice(header_end, header_end + content_len).get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(body_text)
		var req: Dictionary = parsed if parsed is Dictionary else {}
		var content := "MOVE: e7e5"
		if _is_banter_request(req):
			# The rival's BanterEngine shares the oracle tunnel by design
			# (same DS4_CHESS_URL family). Serve it a canned taunt WITHOUT
			# consuming the oracle's scripted replies or polluting the
			# recorded oracle requests — 2026-08-08: the game_start taunt
			# once ate the scripted blunder proposal and the counsel had
			# nothing left to reject.
			content = "The mock wind howls, and the tunnel answers for two."
		else:
			_mock_requests.append(req)
			if _mock_delay_ms > 0:
				# undo scenario: hold the reply so a take-back can land while
				# the Oracle is still thinking — the reply arrives LATE, for a
				# position that no longer exists, and must be discarded.
				await _sleep(_mock_delay_ms / 1000.0)
			if not _mock_replies.is_empty():
				content = _mock_replies.pop_front()
			count_serve = true
		response_body = JSON.stringify({
			"id": "chatcmpl-e2e-mock",
			"object": "chat.completion",
			"model": MOCK_MODEL,
			"choices": [{
				"index": 0,
				"message": {"role": "assistant", "content": content},
				"finish_reason": "stop",
			}],
			"usage": {"prompt_tokens": 0, "completion_tokens": 0},
		})
	var body_bytes := response_body.to_utf8_buffer()
	var head := ("HTTP/1.1 200 OK\r\n" +
		"Content-Type: application/json\r\n" +
		"Content-Length: %d\r\n" % body_bytes.size() +
		"Connection: close\r\n\r\n")
	peer.put_data(head.to_utf8_buffer())
	peer.put_data(body_bytes)
	if count_serve:
		_mock_served += 1
	for i in 8:  # let the client drain before we hang up
		peer.poll()
		await get_tree().process_frame
	peer.disconnect_from_host()

## True when a chat request came from the BanterEngine, not the Oracle —
## its persona system prompt always opens "You are the voice of ...".
func _is_banter_request(req: Dictionary) -> bool:
	var msgs: Variant = req.get("messages")
	if not (msgs is Array) or (msgs as Array).is_empty():
		return false
	var first: Variant = (msgs as Array)[0]
	if not (first is Dictionary):
		return false
	return str((first as Dictionary).get("content", "")).begins_with("You are the voice of")


func _find_header_end(raw: PackedByteArray) -> int:
	for i in range(0, raw.size() - 3):
		if raw[i] == 13 and raw[i + 1] == 10 and raw[i + 2] == 13 and raw[i + 3] == 10:
			return i + 4
	return -1

func _parse_content_length(headers: String) -> int:
	for line in headers.split("\r\n"):
		if line.to_lower().begins_with("content-length:"):
			return int(line.get_slice(":", 1).strip_edges())
	return 0
