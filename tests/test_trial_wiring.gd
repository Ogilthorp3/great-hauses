extends SceneTree

# TRIAL BY FIRE — headless tests for the WIRING between a drawn war and the
# arena. `tests/test_minigame.gd` proves the rules; this file proves the seam.
#
# What is covered, and why each one is here:
#   - WHICH DRAWS            stalemate and insufficient material go to the
#                            arena; threefold and fifty-move keep the card.
#                            The policy is a constant, so it is testable
#   - THE ENUMS ARE 1:1      ChessAI.Difficulty and KingAi.Difficulty agree by
#                            INTEGER and nothing enforces that but this check.
#                            A later reorder of either enum silently hands the
#                            player a Master when he chose Casual
#   - SURVIVORS ARE THE WAR  the crates are harvested from a REAL stalemate
#                            position reached by the real engine — right
#                            count, no kings, right sides — and their cells
#                            agree with game.gd's own sq_of, which is the one
#                            board-index convention in this project
#   - THE CONTRACT SHAPE     every exit path returns the seam's dictionary,
#                            including every refusal. An e2e step asserts this
#                            same shape on the live game node
#   - THE WAY OUT WORKS      one Esc yields the round from the FIRST FRAME the
#                            arena is on screen — while the board is still
#                            becoming it — and no other key over that beat
#                            costs anything. Run against a live arena through
#                            the real key pipeline, and CONTROLLED by a mutant
#                            arena whose concede() is empty
#   - IT NEVER SAYS NOTHING  the verdict lines are non-empty and name the
#                            reason on every path, so the card cannot go blank
#   - THE HARVEST IS PLAYABLE the position the arena inherits from that real
#                            stalemate builds a legal arena and an AI-vs-AI
#                            duel on it always ends with a named winner —
#                            the property that lets a bracket depend on it
#   - THE SCORE IS REAL      the three tier files exist, load as audio, are
#                            the same length (they are ONE loop), and the
#                            manager's tier API only ever moves volumes
#
# Run: /Applications/Godot.app/Contents/MacOS/Godot --headless --path <project> \
#        -s res://tests/test_trial_wiring.gd
# Exit code 0 = all green, 1 = failures.

const Grid := preload("res://src/minigame/blast_grid.gd")
const AI := preload("res://src/minigame/king_ai.gd")
const MusicScript := preload("res://src/audio/music_manager.gd")
## The arena controller itself. Safe to preload in a `-s` run for the same
## reason TrialBridge is: it names no autoload. It reaches Music through
## `get_node_or_null` and PieceView through a runtime `load()`, which is why
## the way-out test below only needs the PieceAssets shim at RUN time.
const TrialScript := preload("res://src/minigame/trial_by_fire.gd")


## THE NEGATIVE CONTROL, and the only reason the way-out gate can be trusted.
## The same arena, the same scene, the same key — with `concede()` emptied. If
## the probe below reports a yield from THIS one, the probe is measuring
## something other than the code it claims to measure and the suite says so.
class NeuteredConcede extends TrialScript:
	func concede() -> void:
		pass


## The board-index convention, spelled out from the one place it is documented
## (src/minigame/trial_by_fire.gd's header: "sq: x = 7-(file-1), y = rank-1").
##
## WHY A STUB AND NOT game.gd ITSELF: game.gd cannot COMPILE in a `-s` run —
## it names the `PieceAssets` and `Music` autoloads, and a script run creates
## no autoloads, so preloading it fails the whole suite. The live seam passes
## the game node itself, so the running game has exactly one definition; what
## this file tests is the HARVEST (which pieces, which side, which count), and
## the e2e asserts the live cells against game.gd's own `sq_of`.
class Geom:
	static func sq_of(idx: int) -> Vector2i:
		@warning_ignore("integer_division")
		return Vector2i(7 - (idx % 8), 7 - (idx / 8))

## The e2e's own stalemate problem, verified against this engine: White plays
## a1g1 and Black — king boxed, every pawn frozen head-to-head — has no move.
## 13 pieces are still standing when it happens, which is the point: the arena
## inherits a real crate field, not two kings in an empty room.
const TRIAL_FEN := "7k/8/p1p1p2K/P1P1P3/1p1p1p2/1P1P1P2/8/R7 w - - 0 1"
const STALEMATING_MOVE := "a1g1"

## PieceView.Type by value. Spelled out rather than named for the same reason
## TrialBridge.TYPE_OF is — see the pinning check in `_test_survivors`.
const TYPE_ROOK := 1
const TYPE_KING := 5

var rows := []
var failures := 0
var checks_run := 0

## A hard-erroring test function aborts silently at the error and its caller
## carries on as if it passed — the floor turns a silent abort into a loud
## failure (the guard test_minigame.gd and test_dragon.gd both use).
const MIN_EXPECTED_CHECKS := 76

## The floor above catches a test that DIES. This catches a test that takes the
## whole tree down with it — `SceneTree.quit()` ends the run with exit code 0
## and `run_e2e.sh` reads exit 0 as a green suite, so a stray quit anywhere in
## here would report ALL GREEN having asserted nothing. (The way-out test drives
## a live arena whose standalone Esc branch is a `get_tree().quit()`; this is
## the guard that makes reaching it a red suite instead of a silent one.)
var _summary_done := false


func _initialize() -> void:
	_main()


func _finalize() -> void:
	if not _summary_done:
		print("RESULT: ABORTED — the tree quit before the summary printed")
		quit(1)


func _main() -> void:
	print("=== TRIAL BY FIRE — draw-seam wiring suite ===")
	_test_which_draws()
	_test_difficulty_is_one_to_one()
	_test_seed()
	_test_survivors()
	_test_contract_shape()
	await _test_the_way_out()
	_test_harvest_is_playable()
	await _test_score()
	_print_summary()


# ── helpers ─────────────────────────────────────────────────────────────────


func check(test_name: String, expected, actual) -> void:
	checks_run += 1
	var ok := str(expected) == str(actual)
	if not ok:
		failures += 1
	rows.push_back([test_name, str(expected), str(actual), ok])


## The real drawn position, reached the way the game reaches it: set the FEN,
## play the stalemating move through the engine, assert the engine agrees.
func _drawn_state():
	var s := ChessState.new()
	s.set_fen(TRIAL_FEN)
	s.apply_move(s.move_from_uci(STALEMATING_MOVE))
	return s


# ── which draws ─────────────────────────────────────────────────────────────


func _test_which_draws() -> void:
	check("policy: stalemate goes to the arena", true,
		TrialBridge.settles_by_fire(ChessState.RESULT.STALEMATE))
	check("policy: insufficient material goes to the arena", true,
		TrialBridge.settles_by_fire(ChessState.RESULT.INSUFFICIENT))
	check("policy: threefold keeps the card", false,
		TrialBridge.settles_by_fire(ChessState.RESULT.THREEFOLD))
	check("policy: fifty-move keeps the card", false,
		TrialBridge.settles_by_fire(ChessState.RESULT.FIFTY_MOVE))
	check("policy: a checkmate is not a draw", false,
		TrialBridge.settles_by_fire(ChessState.RESULT.CHECKMATE))
	check("policy: an ongoing game is not a draw", false,
		TrialBridge.settles_by_fire(ChessState.RESULT.ONGOING))
	check("policy: exactly two draws settle by fire", 2, TrialBridge.BY_FIRE.size())


# ── the two difficulty enums ────────────────────────────────────────────────


func _test_difficulty_is_one_to_one() -> void:
	# THE UNGUARDED CORRESPONDENCE. game.gd hands the arena its ChessAI tier by
	# integer; nothing in either file mentions the other. These three checks
	# are the whole enforcement.
	check("enums: EASY == CASUAL", int(AI.Difficulty.CASUAL),
		int(ChessAI.Difficulty.EASY))
	check("enums: MEDIUM == SEASONED", int(AI.Difficulty.SEASONED),
		int(ChessAI.Difficulty.MEDIUM))
	check("enums: HARD == MASTER", int(AI.Difficulty.MASTER),
		int(ChessAI.Difficulty.HARD))
	check("tier: easy -> casual", int(AI.Difficulty.CASUAL),
		TrialBridge.tier_from_difficulty(ChessAI.Difficulty.EASY))
	check("tier: medium -> seasoned", int(AI.Difficulty.SEASONED),
		TrialBridge.tier_from_difficulty(ChessAI.Difficulty.MEDIUM))
	check("tier: hard -> master", int(AI.Difficulty.MASTER),
		TrialBridge.tier_from_difficulty(ChessAI.Difficulty.HARD))
	# A tier out of range must land on a real tier, not on a crash inside
	# KingAi.TIERS three seconds into a bracket decider.
	check("tier: nonsense clamps low", 0, TrialBridge.tier_from_difficulty(-4))
	check("tier: nonsense clamps high", 2, TrialBridge.tier_from_difficulty(99))
	for t in [0, 1, 2]:
		var brain := AI.new(TrialBridge.tier_from_difficulty(t), 1)
		check("tier %d builds a brain with a label" % t, true,
			not brain.label().is_empty())


# ── the seed ────────────────────────────────────────────────────────────────


func _test_seed() -> void:
	var a := TrialBridge.seed_from_fen(TRIAL_FEN)
	var b := TrialBridge.seed_from_fen(TRIAL_FEN)
	check("seed: the same war builds the same arena", a, b)
	check("seed: is never negative", true, a >= 0)
	check("seed: a different war builds a different arena", true,
		a != TrialBridge.seed_from_fen("8/8/8/8/8/8/8/K6k w - - 0 1"))
	# Seeds feed RandomNumberGenerator.seed, which is fine with any int — but a
	# seed that changes per RUN would make a bug report unreproducible.
	check("seed: survives a round trip through the grid", true,
		_grid_for(a).lattice_is_symmetric())


func _grid_for(seed_value: int) -> Grid:
	var g: Grid = Grid.new()
	g.setup({"crates": [], "seed": seed_value})
	return g


# ── the survivors ───────────────────────────────────────────────────────────


func _test_survivors() -> void:
	var s = _drawn_state()
	check("fen: the engine calls it a stalemate", "STALEMATE",
		ChessState.RESULT.keys()[int(s.get_result())])
	var survivors := TrialBridge.survivors_from_state(s, false, Geom)
	check("survivors: 13 pieces became crates", 13, survivors.size())
	var kings := 0
	var mine := 0
	var theirs := 0
	var in_bounds := 0
	for row in survivors:
		var cell: Vector2i = row[0]
		if int(row[1]) == TYPE_KING:
			kings += 1
		if int(row[2]) == 0:
			mine += 1
		else:
			theirs += 1
		if cell.x >= 0 and cell.x < 8 and cell.y >= 0 and cell.y < 8:
			in_bounds += 1
	check("survivors: the kings are duellists, not crates", 0, kings)
	check("survivors: 7 of the player's men", 7, mine)
	check("survivors: 6 of the rival's", 6, theirs)
	check("survivors: every cell is on the board", 13, in_bounds)
	# No two crates may share a square, or the arena silently loses a man.
	var seen := {}
	for row in survivors:
		seen[str(row[0])] = true
	check("survivors: no two men on one square", 13, seen.size())

	# THE BOARD-INDEX CONVENTION HAS ONE DEFINITION. The bridge is handed
	# game.gd's own static rather than carrying a copy, and this is the check
	# that says so out loud: the rook that made the move is on g1, and the
	# arena must agree with the match about which square that is.
	var g1 := ChessState.square_index_from_name("g1")
	check("survivors: the rook is on g1 in the engine", "R", str(s.pieces[g1]))
	var want := Geom.sq_of(g1)
	var found := false
	for row in survivors:
		if row[0] == want and int(row[1]) == TYPE_ROOK:
			found = true
	check("survivors: the arena seats the rook on the documented g1", true, found)

	# THE INTEGERS IN TrialBridge.TYPE_OF ARE PINNED HERE, and this is the only
	# place in the suite that may look at PieceView: naming it requires the
	# PieceAssets shim below, which is why the bridge itself does not.
	var assets: Node = load("res://src/board/piece_assets.gd").new()
	assets.name = "PieceAssets"
	root.add_child(assets)
	var pv: GDScript = load("res://src/board/piece_view.gd")
	var want_types := {"p": pv.Type.PAWN, "r": pv.Type.ROOK, "n": pv.Type.KNIGHT,
		"b": pv.Type.BISHOP, "q": pv.Type.QUEEN, "k": pv.Type.KING}
	for c in want_types:
		check("types: '%s' is PieceView.Type %d" % [c, int(want_types[c])],
			int(want_types[c]), int(TrialBridge.TYPE_OF[c]))
	check("types: the map covers all six ranks", 6, TrialBridge.TYPE_OF.size())
	assets.free()

	# THE HINT LINE MUST NOT PROMISE CONTROLS THE MODE REFUSES. Embedded, R is
	# ignored and Esc yields the round rather than quitting — the first frame
	# shipped of an embedded arena printed "R to retry · ESC to leave" across a
	# bracket decider.
	var hud: GDScript = load("res://src/minigame/trial_hud.gd")
	check("hint: embedded never offers R", false,
		str(hud.HINT_EMBEDDED).contains("R to retry"))
	check("hint: embedded never offers to leave the game", false,
		str(hud.HINT_EMBEDDED).contains("ESC to leave"))
	check("hint: embedded says Esc costs the round", true,
		str(hud.HINT_EMBEDDED).contains("yields the round"))
	check("hint: standalone still offers both", true,
		str(hud.HINT_STANDALONE).contains("R to retry")
			and str(hud.HINT_STANDALONE).contains("ESC to leave"))

	# A Black player's own men stay HIS men (side 0), which is what keeps the
	# crates wearing the player's haus in the arena.
	var flipped := TrialBridge.survivors_from_state(s, true, Geom)
	var mine_flipped := 0
	for row in flipped:
		if int(row[2]) == 0:
			mine_flipped += 1
	check("survivors: seating flips with the player's colour", 6, mine_flipped)


# ── the contract ────────────────────────────────────────────────────────────


func _test_contract_shape() -> void:
	# Every refusal and every result is the same dictionary. The e2e asserts
	# this shape against the LIVE game node; this asserts it against all four
	# shapes at once, which the e2e cannot reach in one run.
	var cases := [
		["fought and won", true, true, "fought"],
		["fought and lost", false, true, "fought"],
		["never ran", false, false, "the Trial by Fire is a single-player rite in this build"],
		["conceded", false, true, "conceded"],
	]
	for c in cases:
		var lines := TrialBridge.verdict_lines(bool(c[1]), "Haus Ember",
			bool(c[2]), str(c[3]))
		check("verdict '%s': says something" % c[0], true, lines.size() > 0)
		var blank := false
		for l in lines:
			if l.strip_edges().is_empty():
				blank = true
		check("verdict '%s': no blank line" % c[0], false, blank)
		check("verdict '%s': names the rival" % c[0], true,
			"\n".join(lines).contains("Haus Ember"))
	# The two outcomes must not read the same — the card is the only place the
	# player learns which one happened.
	check("verdict: winning and losing read differently", true,
		str(TrialBridge.verdict_lines(true, "Haus Ember", true, "fought"))
			!= str(TrialBridge.verdict_lines(false, "Haus Ember", true, "fought")))
	# A refusal must SAY the reason rather than shrug, and the network refusal
	# is the one a player is most likely to hit.
	var refused := TrialBridge.verdict_lines(false, "Haus Ember", false,
		"the Trial by Fire is a single-player rite in this build")
	check("verdict: a refusal states its reason", true,
		"\n".join(refused).contains("single-player"))
	# A YIELD IS NOT A DEATH — the card must not report a fight that never
	# happened (the concede e2e caught exactly this sentence).
	var yielded := "\n".join(TrialBridge.verdict_lines(false, "Haus Ember", true,
		"conceded"))
	check("verdict: a concede does not claim the king fell", false,
		yielded.contains("fell in the arena"))
	check("verdict: a concede says it was unopposed", true,
		yielded.contains("unopposed"))


# ── the way out ─────────────────────────────────────────────────────────────


## THE PLAYER'S ONLY WAY OUT OF A DUEL, ASSERTED AT THE WORST MOMENT FOR IT.
##
## THE SCAR, measured 2026-08-09. The arena opens with a 2.5 s beat in which the
## board BECOMES the arena, and every key over that beat was routed into
## `skip_transform()` — so the first Esc a player pressed skipped a cutscene and
## yielded nothing, while the HUD had been reading "ESC yields the round" since
## the frame the beat started. `concede()`'s own `if not _running` guard was a
## second trap underneath the first. The e2e caught it as "Esc did not concede
## the arena"; this is the headless version, which answers in two seconds
## instead of ninety and does not need a window.
##
## THE PRESS IS A REAL KEY, through `Input.parse_input_event` — the same
## InputEventKey a keyboard produces, into the same `_input`, the same
## `_route_key` and the same `concede()`. A test that called `concede()`
## directly could not have seen this bug at all, because `concede()` was never
## reached.
##
## AND IT IS CONTROLLED. The identical probe runs a second time against
## `NeuteredConcede` — the same scene with `concede()` emptied — and the suite
## fails if THAT one reports a yield. Without the mutant this gate could pass
## vacuously in three different ways (press after the beat, read a field nothing
## sets, assert something always true) and look exactly the same from here. This
## project has shipped two gates that passed vacuously; the mutant is the
## cheapest insurance against a third.
func _test_the_way_out() -> void:
	# PieceView names the PieceAssets autoload and a `-s` run creates none —
	# the same shim `_test_survivors` builds, for the same reason.
	var assets: Node = load("res://src/board/piece_assets.gd").new()
	assets.name = "PieceAssets"
	root.add_child(assets)
	# THE ROOT IS NOT IN THE TREE DURING `_initialize` (the same wait
	# `_test_score` takes, for the same reason): until one frame has passed,
	# `add_child` does not run `_ready`, the arena never finds its own Board,
	# and `start()` dies on a null `_board` — which reads from out here exactly
	# like "Esc did not concede", i.e. like the bug this test exists to catch.
	await process_frame

	# ── the gate: one Esc, at the earliest moment there is an arena at all ──
	var esc := await _arena_probe(false, true, KEY_ESCAPE)
	check("way out: the press landed while the board was still becoming the arena",
		true, bool(esc["transforming_at_press"]))
	check("way out: …and before the duel had opened", false,
		bool(esc["running_at_press"]))
	check("way out: …inside the first half of the beat (u=%.3f)" % esc["u_at_press"],
		true, float(esc["u_at_press"]) < 0.5)
	check("way out: ONE Esc yields the round", true, bool(esc["conceded"]))
	check("way out: the verdict is announced", true, bool(esc["announced"]))
	check("way out: the round goes to the rival", 1, int(esc["side"]))
	check("way out: the beat is landed, not left half-risen", true,
		bool(esc["skipped"]))
	check("way out: the clock is handed back (%.2f)" % esc["time_scale"], true,
		is_equal_approx(float(esc["time_scale"]), 1.0))
	check("way out: the grid is left as it is", true, bool(esc["grid_kept"]))
	check("way out: the arena survives the yield — it costs the round, not the game",
		true, bool(esc["alive_after"]))

	# ── the negative control ───────────────────────────────────────────────
	var mute := await _arena_probe(true, true, KEY_ESCAPE)
	check("control: the mutant was pressed at the same moment", true,
		bool(mute["transforming_at_press"]))
	check("control: an emptied concede() yields nothing", false,
		bool(mute["conceded"]))
	check("control: …and announces no verdict", false, bool(mute["announced"]))
	# The mutant does not even skip the beat, which is the sharpest evidence in
	# this file: Esc's ONLY route is now through `concede()`, so emptying that
	# one method takes the whole effect of the key with it.
	check("control: …and does not so much as land the beat", false,
		bool(mute["skipped"]))
	check("control: so this gate measures concede(), not the press", true,
		bool(esc["conceded"]) and not bool(mute["conceded"]))

	# ── and skipping is still only skipping ────────────────────────────────
	# THE OTHER HALF OF THE CONTRACT. Esc had to become special without making
	# every key special: a player mashing SPACE over a cutscene he did not ask
	# for must not forfeit a bracket round.
	var space := await _arena_probe(false, true, KEY_SPACE)
	check("mash: SPACE over the beat costs no round", false, bool(space["conceded"]))
	check("mash: SPACE over the beat lands the beat", true, bool(space["skipped"]))
	check("mash: …and opens the duel", true, bool(space["running_after"]))
	# R is standalone-only: rerolling a bracket decider is an exploit, and the
	# arena it rebuilt would be a different arena — so the grid must be the same
	# object afterwards.
	var retry := await _arena_probe(false, true, KEY_R)
	check("mash: R over the beat costs no round", false, bool(retry["conceded"]))
	check("mash: R never rerolls an embedded arena", true, bool(retry["grid_kept"]))

	# ── standalone is untouched ────────────────────────────────────────────
	# ONE KEY ONLY. Standalone Esc is `get_tree().quit()` and there is no way to
	# press it in-process without taking the suite with it — `_finalize` above
	# turns that into a red suite rather than a silent one, and the branch
	# itself is asserted by the e2e's own "the process survives" step. What is
	# checked here is that the standalone SKIP path still behaves: no key over
	# the beat concedes when nobody is embedded.
	var solo := await _arena_probe(false, false, KEY_SPACE)
	check("standalone: a key over the beat still only skips", true,
		bool(solo["skipped"]))
	check("standalone: and yields nothing", false, bool(solo["conceded"]))

	assets.free()
	check("way out: no arena walked out carrying the clock (%.2f)"
		% Engine.time_scale, true, is_equal_approx(Engine.time_scale, 1.0))


## Build a live arena, press ONE key at the earliest moment it exists, and
## report what happened. `neutered` swaps in the mutant script; `embedded` is
## the flag TrialBridge sets when the arena runs inside a match.
func _arena_probe(neutered: bool, embedded: bool, key: Key) -> Dictionary:
	var scene := load(TrialBridge.TRIAL_SCENE) as PackedScene
	var arena: Node = scene.instantiate()
	if neutered:
		arena.set_script(NeuteredConcede)
	root.add_child(arena)
	arena.set("embedded", embedded)
	var box := {"side": -1}
	arena.trial_finished.connect(func(s: int) -> void: box["side"] = s)
	# `start()` builds the grid, the crates, the kings and the HUD and then
	# begins the transmutation — so the instant it returns there IS an arena,
	# and the duel has not opened. That is the moment under test.
	arena.start({"seed": 4242})
	await process_frame
	var grid_before: int = arena.get("grid").get_instance_id()
	var out := {
		"transforming_at_press": bool(arena.get("transforming")),
		"running_at_press": bool(arena.get("_running")),
		"u_at_press": float(arena.call("_transform_u")),
	}
	_key(key, true)
	await process_frame
	_key(key, false)
	await process_frame
	await process_frame
	var grid_after = arena.get("grid")
	out["conceded"] = bool(arena.get("conceded"))
	out["announced"] = bool(arena.get("_announced"))
	out["skipped"] = bool(arena.get("transform_skipped"))
	out["running_after"] = bool(arena.get("_running"))
	out["side"] = int(box["side"])
	# READ BEFORE THE FREE. Freeing the arena restores the clock by itself
	# (`_exit_tree`), so asking afterwards would answer 1.0 on every path
	# including the broken ones — the same "read it before you tear it down"
	# trap TrialBridge carries for `conceded`.
	out["time_scale"] = Engine.time_scale
	out["grid_kept"] = grid_after != null and grid_after.get_instance_id() == grid_before
	out["alive_after"] = is_instance_valid(arena)
	arena.queue_free()
	await process_frame
	await process_frame
	return out


func _key(code: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


# ── the harvest is playable ─────────────────────────────────────────────────


func _test_harvest_is_playable() -> void:
	# THE PROPERTY A BRACKET DEPENDS ON. It is not enough that the rules
	# terminate on a mocked field (test_minigame.gd proves that); the field
	# this seam actually hands them has to terminate too, at every tier, or a
	# tournament can hang on a position nobody tested.
	var s = _drawn_state()
	var survivors := TrialBridge.survivors_from_state(s, false, Geom)
	var cells: Array = []
	for row in survivors:
		cells.append(row[0])
	for tier in [0, 1, 2]:
		var seed_value: int = TrialBridge.seed_from_fen(TRIAL_FEN) + int(tier)
		var g: Grid = Grid.new()
		g.setup({"crates": cells, "seed": seed_value,
			"sudden_death_at": 20.0, "ring_interval": 0.25})
		check("arena t%d: the lattice is fair" % tier, true, g.lattice_is_symmetric())
		check("arena t%d: both kings stand" % tier, true,
			g.kings[0].alive and g.kings[1].alive)
		check("arena t%d: the drawn war became a crate field" % tier, true,
			g.crates_left() > 0)
		var brains := [AI.new(tier, seed_value + 1), AI.new(tier, seed_value + 2)]
		var ticks := 0
		while not g.is_over() and ticks < 12000:
			for side in 2:
				var act: Dictionary = brains[side].decide(g, side, 1.0 / 60.0)
				if act.has("keg"):
					g.place_keg(side)
				elif act.has("step"):
					g.request_step(side, act["step"])
			g.tick(1.0 / 60.0)
			g.drain_events()
			ticks += 1
		check("arena t%d: the duel ended" % tier, true, g.is_over())
		check("arena t%d: it named a winner" % tier, true,
			g.winner() == 0 or g.winner() == 1)


# ── the score ───────────────────────────────────────────────────────────────


func _test_score() -> void:
	check("music: three tiers are declared", 3, MusicScript.TRIAL_TIERS.size())
	var lengths: Array[float] = []
	for path in MusicScript.TRIAL_TIERS:
		check("music: %s exists" % path.get_file(), true,
			ResourceLoader.exists(path))
		var stream := load(path) as AudioStream
		check("music: %s loads as audio" % path.get_file(), true, stream != null)
		if stream != null:
			lengths.append(stream.get_length())
	# THE LAYERING RESTS ON THIS. The three files are one loop rendered three
	# ways; if their lengths ever diverge they cannot be played together and
	# the "tier" API becomes a track change with a phase error in it.
	if lengths.size() == 3:
		check("music: tier 2 is the same loop as tier 1", true,
			absf(lengths[0] - lengths[1]) < 0.001)
		check("music: tier 3 is the same loop as tier 1", true,
			absf(lengths[0] - lengths[2]) < 0.001)
		check("music: the loop is 60.000 s", "60.000", "%.3f" % lengths[0])

	var m: Node = MusicScript.new()
	m.name = "Music"
	m.settings_path = "user://test_trial_wiring_settings.json"
	root.add_child(m)
	if not m.is_inside_tree():
		# During `_initialize` the root has not entered the tree yet, so the
		# manager's `_ready` (and its decks, and its bus) do not exist until one
		# frame later — and an AudioStreamPlayer outside the tree silently
		# ignores play(). test_music.gd learned this first; the same wait is the
		# difference between measuring the mixer and measuring nothing.
		await process_frame
	check("music: no trial is playing at rest", -1, m.current_trial_tier())
	check("music: stopping a trial that never began is safe", -1,
		_stop_and_report(m))
	m.play_trial(0)
	check("music: play_trial builds three layers", 3, m.trial_players().size())
	var all_playing := true
	for p in m.trial_players():
		if not p.playing:
			all_playing = false
	# THE SAMPLE LOCK: every layer is rolling, not just the audible one. This is
	# what makes a tier change a mix move instead of a re-seek.
	check("music: all three layers roll together", true, all_playing)
	check("music: tier 1 is the audible one", 0, m.current_trial_tier())
	m.trial_tier(2)
	check("music: the mix moved to the dragon", 2, m.current_trial_tier())
	var still_playing := true
	for p in m.trial_players():
		if not p.playing:
			still_playing = false
	check("music: a tier change re-seeks nothing", true, still_playing)
	check("music: play_trial twice does not stack layers", 3,
		_replay_and_count(m))
	m.stop_trial(0.0)
	check("music: stopping releases the layers", 0, m.trial_players().size())
	check("music: and forgets the tier", -1, m.current_trial_tier())
	m.free()


func _stop_and_report(m: Node) -> int:
	m.stop_trial(0.0)
	return m.current_trial_tier()


func _replay_and_count(m: Node) -> int:
	m.play_trial(1)
	return m.trial_players().size()


# ── reporting ───────────────────────────────────────────────────────────────


func _short(s: String, width: int) -> String:
	return s if s.length() <= width else s.substr(0, width - 3) + "..."


func _print_summary() -> void:
	print("")
	print("%-4s %-58s %-16s %-16s %-6s" % ["#", "Test", "Expected", "Actual", "Pass"])
	print("-".repeat(104))
	var i := 1
	for row in rows:
		print("%-4d %-58s %-16s %-16s %-6s" % [i, _short(row[0], 58),
			_short(row[1], 16), _short(row[2], 16), "PASS" if row[3] else "FAIL"])
		i += 1
	print("-".repeat(104))
	if checks_run < MIN_EXPECTED_CHECKS:
		failures += 1
		print("FLOOR: only %d checks ran, expected at least %d — a test aborted silently"
			% [checks_run, MIN_EXPECTED_CHECKS])
	print("TOTAL: %d  PASSED: %d  FAILED: %d" % [rows.size(),
		rows.size() - failures, failures])
	print("RESULT: %s" % ("ALL GREEN" if failures == 0 else "FAILURES PRESENT"))
	_summary_done = true
	quit(1 if failures > 0 else 0)
