class_name TrialBridge
extends RefCounted
## THE WIRING between a drawn war and the Trial by Fire.
##
## WHY THIS FILE EXISTS AT ALL. `src/game.gd` owns exactly one seam for this
## feature — `settle_tournament_draw()` — and the instruction that came with it
## was to replace that function's BODY and nothing else. A faithful integration
## still needs sixty-odd lines of lifecycle (harvest the survivors, take the
## frame away from the match, run a real-time duel, give the frame back, never
## hang the bracket). Those lines live here so the seam stays four lines long
## and game.gd's diff is one function.
##
## WHAT IT GUARANTEES, in the order the guarantees matter:
##   1. IT NEVER HANGS THE TOURNAMENT. Every failure — a scene that will not
##      load, a trial that never answers, a missing king — lands on the same
##      fallback the game shipped with (the rival advances, and the card says
##      so). `run()` cannot raise past its caller.
##   2. IT ALWAYS GIVES THE FRAME BACK. The match's board, hall, pieces, HUD,
##      camera and environment are restored on every exit path, including the
##      deadline and the concede, and `Engine.time_scale` is restored with them.
##   3. THE ARENA IS THE DRAWN POSITION. The crates are the pieces that were
##      still standing when the kings ran out of moves — harvested from the
##      live ChessState, not mocked.
##
## WHICH DRAWS. Stalemate and insufficient material only (see BY_FIRE). Both
## are draws where neither army CAN win — the kings settling it themselves is
## the thematically honest answer. Threefold and fifty-move are draws by
## bookkeeping rather than by position, and they keep the existing draw card.

const TRIAL_SCENE := "res://scenes/minigame/trial_by_fire.tscn"

## THE ONE DEADLINE. Wall-clock, so a slow-motion cinematic elsewhere cannot
## stretch it. A duel that has not answered in this long has something wrong
## with it, and a bracket that waits forever is worse than a bracket that
## falls back. The dragon's own ring closes the arena in ~70 s + travel, so
## this is roughly double the longest honest duel.
const DEADLINE_SEC := 150.0

## How long the verdict sits on screen before the frame goes back to the match.
const VERDICT_HOLD_SEC := 2.4

## The draws the kings settle themselves, by ChessState.RESULT.
const BY_FIRE: Array[int] = [
	ChessState.RESULT.STALEMATE,
	ChessState.RESULT.INSUFFICIENT,
]


## ── pure decisions (no tree, no scene — all of this is unit-tested) ────────


static func settles_by_fire(result: int) -> bool:
	return BY_FIRE.has(result)


## ChessAI.Difficulty -> KingAi.Difficulty. The two enums are 1:1 by integer
## (EASY/MEDIUM/HARD -> CASUAL/SEASONED/MASTER) and the suite asserts that they
## stay that way, because this silent correspondence is exactly the kind of
## thing a later reorder breaks without a single error.
static func tier_from_difficulty(difficulty: int) -> int:
	return clampi(difficulty, 0, 2)


## The arena is reproducible from the position that produced it: the same drawn
## war always builds the same maze and hides the same boons. Replaying a
## bracket round therefore replays the same trial, and a bug report can be
## reproduced from the FEN alone.
static func seed_from_fen(fen: String) -> int:
	return abs(hash(fen)) & 0x7FFFFFFF


## The survivors, as the arena wants them: [board cell, PieceView.Type, side].
## The two kings are left out — they are the duellists, not the crates.
##
## `geom` is anything exposing `sq_of(index) -> Vector2i`; game.gd's own static
## is passed in rather than copied, so the board-index convention has exactly
## one definition in this project and this file cannot drift from it.
static func survivors_from_state(state, player_color: bool, geom) -> Array:
	var out: Array = []
	for idx in 64:
		var c = state.pieces[idx]
		if c == null:
			continue
		var lower := str(c).to_lower()
		if lower == "k":
			continue
		# Side 0 is always the player's colours, matching PieceView.House.FROST
		# in the match that just ended — a Black player's own men stay his.
		var side := 0 if ChessState.piece_color(c) == player_color else 1
		out.append([geom.sq_of(idx), TYPE_OF.get(lower, 0), side])
	return out


## Piece char -> PieceView.Type, AS INTEGERS ON PURPOSE.
##
## Writing `PieceView.Type.PAWN` here would be prettier and would cost this
## file its testability: PieceView names the `PieceAssets` autoload, and a
## script that so much as names an autoload cannot COMPILE in a `-s` run
## (tests/test_kill_styles.gd carries the scar). Naming it here would drag the
## whole bridge — and every suite that imports it — behind that wall. The
## integers are pinned to the enum by a check in tests/test_trial_wiring.gd,
## which builds the shim first and can afford to look.
const TYPE_OF := {"p": 0, "r": 1, "n": 2, "b": 3, "q": 4, "k": 5}


## The words the verdict card says. Kept beside the decision so the card can
## never disagree with the bracket — the failure the old draw code shipped.
static func verdict_lines(won: bool, rival_display: String, ran: bool,
		why: String) -> Array[String]:
	if not ran:
		# The trial did not happen. Say which of the two reasons it was; a
		# player who never saw a duel deserves better than a shrug.
		return [
			"A drawn war wins no round — %s rides on in your place." % rival_display,
			"(%s)" % why,
		]
	if won:
		return [
			"THE TRIAL BY FIRE — your king walked out of the ashes.",
			"%s burns. You ride on." % rival_display,
		]
	if why == "conceded":
		# A YIELD IS NOT A DEATH. Telling a player who walked out that his king
		# "fell in the arena" is the same class of lie the minigame's own
		# double-knockout copy was fixed for: the verdict was right and the
		# sentence describing it was not.
		return [
			"THE TRIAL BY FIRE — you would not set foot in the arena.",
			"%s takes the round unopposed." % rival_display,
		]
	return [
		"THE TRIAL BY FIRE — the ashes favour %s." % rival_display,
		"Your king fell in the arena. %s rides on." % rival_display,
	]


## ── the run ────────────────────────────────────────────────────────────────


var _hidden: Array = []          # [node, kind, remembered value] to put back
var _time_scale := 1.0
var _trial: Node = null


## Settle a drawn tournament war by fire.
##
## Returns the seam's contract verbatim:
##   {"player_advances": bool, "lines": Array[String], "ran": bool, "why": String}
## `ran`/`why` are extra evidence for the suites and the logs; the seam passes
## the whole dictionary through, and `_show_match_end` only ever reads the two
## contract keys.
func run(game: Node, result: int) -> Dictionary:
	var rival: String = str(game.get("_rival_display"))
	var why := _refuse_reason(game, result)
	if not why.is_empty():
		return _verdict(false, rival, false, why)

	_time_scale = Engine.time_scale
	var scene := load(TRIAL_SCENE) as PackedScene
	if scene == null:
		return _verdict(false, rival, false, "the arena could not be raised")
	_trial = scene.instantiate()
	if _trial == null:
		return _verdict(false, rival, false, "the arena could not be raised")

	var side := 1   # the rival, unless the player's king is the one left standing
	# THE FRAME CHANGES HANDS HERE. Everything after this point must reach the
	# restore, which is why the body below has exactly one exit.
	_take_the_frame(game)
	game.add_child(_trial)
	_trial.set("embedded", true)
	_trial.start({
		"survivors": survivors_from_state(game.get("state"),
			bool(game.get("player_color")), game),
		"houses": [_house_of(game, "player_house_id"), _house_of(game, "rival_house_id")],
		"tier": tier_from_difficulty(int(game.get("ai_difficulty"))),
		"seed": seed_from_fen(str(game.get("state").get_fen())),
	})

	var answered := await _await_verdict(game)
	if answered >= 0:
		side = answered
	else:
		# The deadline fired. Take the grid's own standing verdict if it has one
		# rather than inventing an answer — it is still the arena's decision.
		var grid = _trial.get("grid")
		if grid != null and grid.winner() != grid.ONGOING:
			side = grid.winner()
		push_warning("Trial by Fire: no verdict in %.0fs — taking the standing count"
			% DEADLINE_SEC)

	# READ BEFORE THE FRAME GOES BACK. `_give_the_frame_back` frees the arena
	# and nulls the handle, so asking it afterwards always answered "fought" —
	# and a player who yielded was told his king had fallen in a fight he never
	# took. Caught by the concede e2e reading its own card.
	var was_conceded := _trial_was_conceded()
	await _hold(game, VERDICT_HOLD_SEC)
	_give_the_frame_back(game)
	return _verdict(side == 0, rival, true, "conceded" if was_conceded else "fought")


## Why the trial must not run. Empty string = run it.
func _refuse_reason(game: Node, result: int) -> String:
	if not settles_by_fire(result):
		return "this draw is settled by the book, not by fire"
	if not _is_tournament():
		# THE OWNER'S RULE IS "offer it, do not force it" FOR A SINGLE MATCH,
		# and v1 ships the decline half of that honestly rather than the force
		# half quietly. There is no offer UI because there is nowhere to put
		# one: `_end_sequence` only reaches this seam inside `_in_tournament()`,
		# and that call site was fenced off this phase. Wiring the offer is
		# three lines there (call the seam for a single-match draw too, behind a
		# prompt) plus deleting this guard — see RELEASE-NOTES.
		return "a single match keeps its draw — the trial settles brackets"
	if Session.is_network():
		# SAID PLAINLY RATHER THAN FAKED. The chess is turn-based and
		# host-authoritative; this duel is real-time, and a real-time duel
		# without a synchronised host tick is two different fights on two
		# screens agreeing on nothing. v1 does not ship that.
		return "the Trial by Fire is a single-player rite in this build"
	if game.get("state") == null or not game.is_inside_tree():
		return "the war ended before the arena could be raised"
	return ""


static func _is_tournament() -> bool:
	return Session.configured and Session.mode == "tournament" \
		and Session.tournament != null


## Await `trial_finished`, or the wall-clock deadline, whichever lands first.
## Returns the winning side, or -1 if nothing answered.
func _await_verdict(game: Node) -> int:
	var tree := game.get_tree()
	if tree == null:
		return -1
	var box := {"side": -1, "done": false}
	_trial.trial_finished.connect(func(s: int) -> void:
		box["side"] = s
		box["done"] = true, CONNECT_ONE_SHOT)
	# ignore_time_scale — the deadline is a promise to the player, and a promise
	# measured on a clock the game can bend is not a promise.
	var deadline := tree.create_timer(DEADLINE_SEC, true, false, true)
	var expired := false
	deadline.timeout.connect(func() -> void: expired = true)
	while not box["done"] and not expired:
		if not is_instance_valid(_trial):
			return -1
		await tree.process_frame
	return int(box["side"]) if box["done"] else -1


func _hold(game: Node, sec: float) -> void:
	var tree := game.get_tree()
	if tree == null:
		return
	await tree.create_timer(sec, true, false, true).timeout


func _trial_was_conceded() -> bool:
	return is_instance_valid(_trial) and bool(_trial.get("conceded"))


func _house_of(game: Node, key: String) -> String:
	var id := str(game.get(key))
	# The legacy Frost/Ember skin has no haus ids; the arena needs two names it
	# can dress with, so fall back to the pair the standalone scene ships with.
	if id.is_empty():
		return "winterfang" if key == "player_house_id" else "goldclaw"
	return id


func _verdict(won: bool, rival: String, ran: bool, why: String) -> Dictionary:
	return {
		"player_advances": won,
		"lines": verdict_lines(won, rival, ran, why),
		"ran": ran,
		"why": why,
	}


## ── the frame ──────────────────────────────────────────────────────────────
##
## The arena scene is a near-copy of game.tscn — its own board, hall, camera,
## sun and environment — because it has to READ as the board the war was played
## on. Two of everything cannot be on screen at once, so the match's own copy
## is switched off for the duration and switched back on afterwards. Nothing is
## freed and nothing is rebuilt: the match is still standing behind the arena,
## which is what makes the return instant and the restore total.


func _take_the_frame(game: Node) -> void:
	_hidden.clear()
	for child in game.get_children():
		if child == _trial:
			continue
		if child is WorldEnvironment:
			# WorldEnvironment is a plain Node — no `visible` to turn off, and
			# two live ones in a tree is an engine warning and a coin flip over
			# which fog wins. Unhook the environment instead.
			_hidden.append([child, "env", (child as WorldEnvironment).environment])
			(child as WorldEnvironment).environment = null
		elif child is Node3D and (child as Node3D).visible:
			_hidden.append([child, "vis", true])
			(child as Node3D).visible = false
		elif child is CanvasLayer and (child as CanvasLayer).visible:
			_hidden.append([child, "vis", true])
			(child as CanvasLayer).visible = false


func _give_the_frame_back(game: Node) -> void:
	if is_instance_valid(_trial):
		_trial.queue_free()
	_trial = null
	for entry in _hidden:
		var node: Node = entry[0]
		if not is_instance_valid(node):
			continue
		match entry[1]:
			"env":
				(node as WorldEnvironment).environment = entry[2]
			"vis":
				node.set("visible", true)
	_hidden.clear()
	# THE CAMERA COMES HOME. The arena's Camera3D enters the tree as `current`
	# and takes the viewport; freeing it does not hand the viewport back, so the
	# match's own camera has to claim it again or the verdict card opens over an
	# empty world.
	var cam := game.find_child("Camera3D", true, false) as Camera3D
	if cam != null:
		cam.current = true
	# Whatever the duel did to the clock, the match gets its own back. This is
	# belt-and-braces — the arena does not touch time_scale — but a mode that
	# takes the frame is exactly where a stuck clock would hide.
	Engine.time_scale = _time_scale


## Emergency release: used when the seam's own body fails in a way `run()` did
## not anticipate, so a half-hidden match can never reach the player.
func abort(game: Node) -> void:
	_give_the_frame_back(game)
