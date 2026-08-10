extends Node3D
## TRIAL BY FIRE — the arena controller, and the standalone entry point.
##
## THE FEATURE. A knockout tournament needs a winner and the current answer to a
## draw is that the player is quietly eliminated by arithmetic. So when the war
## ends in a stalemate the two kings settle it themselves: the board they just
## drew on becomes an arena, the surviving pieces become the things that burn,
## and the last king standing takes the tie.
##
## WHAT THIS FILE DOES, AND ONLY THIS: it owns the seam between the rules
## (src/minigame/blast_grid.gd, pure and headless) and the picture (arena_fx,
## incinerator, wyrm_clock, trial_hud). Every frame it feeds input to the grid,
## ticks it, and drains its event queue into geometry. It holds NO game state of
## its own — if the two ever disagree, the grid is right and this file has a
## bug, which is the only arrangement in which the headless suite means anything.
##
## EVERYTHING IS BORROWED:
##   THE ARENA is BoardView — the same 8x8 stone the match was played on, the
##     same square_to_world() mapping, in the same GreatHall under the same
##     eight torches. No new coordinate system was invented for this mode.
##   THE CRATES are PieceView survivors, standing on their own squares, wearing
##     their own hauses. Your bannermen are the wall between you and the rival
##     king, and you have to decide whether to burn them.
##   THE INCINERATION is dragon_spectator.gd's charred-skeleton recipe (see
##     incinerator.gd) — retuned green and quartered in length.
##   THE CLOCK is the dragon, torching the ring inward with the dracarys kit
##     (see wyrm_clock.gd).
##   THE WALK is the piece's own Walking_A off the shared Rig_Medium library,
##     and a king who falls plays the same Death_A he would have in the war.
##
## STANDALONE THIS PHASE. Run it directly, with a mocked board state:
##   Godot --path <project> res://scenes/minigame/trial_by_fire.tscn
## Options, after a `--` separator:
##   --tbf-ai                 both kings driven by the AI (a demo / soak run)
##   --tbf-tier=casual|seasoned|master     the rival's difficulty
##   --tbf-seed=<int>         reproducible arena and boons
##   --tbf-fast               short fuse + impatient wyrm, for a quick look
##   --tbf-shots=<dir>        save PNGs at the scripted beats and quit
## Nothing here is wired into src/game.gd yet — that is a later phase, and the
## hand-over is one call plus one signal (see `start()` and `trial_finished`).

const GridScript := preload("res://src/minigame/blast_grid.gd")
const AiScript := preload("res://src/minigame/king_ai.gd")
const FxScript := preload("res://src/minigame/arena_fx.gd")
const IncinScript := preload("res://src/minigame/incinerator.gd")
const WyrmScript := preload("res://src/minigame/wyrm_clock.gd")
const HudScript := preload("res://src/minigame/trial_hud.gd")

## Emitted once the trial is decided: `side` is the winning king (0 = the
## player's). THE INTEGRATION SEAM — game.gd awaits this and awards the tie.
signal trial_finished(side: int)

## The mocked drawn position: who was still standing when the kings ran out of
## moves. Board coords (BoardView's sq: x = 7-(file-1), y = rank-1) paired with
## PieceView.Type. Deliberately lopsided and deliberately NOT symmetric — a real
## stalemate never is, and the arena's fairness comes from its blackstone (see
## BlastGrid.setup), not from counting the dead.
const MOCK_SURVIVORS := [
	# side 0 — the player's colours
	[Vector2i(1, 1), 0], [Vector2i(3, 1), 0], [Vector2i(5, 2), 0],
	[Vector2i(2, 3), 3], [Vector2i(6, 1), 1], [Vector2i(4, 0), 2],
	[Vector2i(0, 2), 0], [Vector2i(7, 2), 0],
	# side 1 — the rival's
	[Vector2i(2, 6), 0], [Vector2i(4, 6), 0], [Vector2i(6, 5), 0],
	[Vector2i(5, 4), 3], [Vector2i(1, 6), 1], [Vector2i(3, 7), 2],
	[Vector2i(7, 5), 0], [Vector2i(0, 5), 4],
]

const HOUSE_A := "winterfang"
const HOUSE_B := "goldclaw"
const TIER_WORDS := {"casual": 0, "seasoned": 1, "master": 2}

@export var player_house := HOUSE_A
@export var rival_house := HOUSE_B
@export var rival_tier := 1        ## KingAi.Difficulty
@export var both_ai := false
@export var arena_seed := 20260809

var grid
var _ai := []
var _fx: Node3D
var _incin: Node3D
var _wyrm: Node3D
var _hud: CanvasLayer
var _board: Node3D
var _kings: Array[Node3D] = []
var _king_from: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _king_to: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _king_t: Array[float] = [0.0, 0.0]
var _king_dur: Array[float] = [1.0, 1.0]
var _king_walking: Array[bool] = [false, false]
var _crates := {}          ## cell index -> PieceView
var _held := Vector2i.ZERO
var _running := false
var _shots_dir := ""
var _shot_n := 0
var _announced := false
var _drive_demo := false

## Set by TrialBridge when the arena runs INSIDE a live match. It changes what
## the two "get me out of here" keys mean, and both changes are safety rather
## than taste: standalone, Esc quits the process and R rebuilds the arena; in a
## bracket decider, Esc quitting the game would take the tournament with it and
## R would let a losing player reroll the maze until he wins.
var embedded := false
## True when the player walked away rather than fought. Kept distinct from
## losing: the card says which one happened.
var conceded := false

## Which music tier the arena has asked for, in order. Evidence for the e2e:
## the score is supposed to FOLLOW the duel (fuse -> kegs -> dragon), and the
## only honest proof of that is the sequence the game actually asked for.
var music_tier_log: Array[int] = []


func _ready() -> void:
	_board = get_node_or_null("Board")
	# STANDALONE ONLY. When game.gd instances this scene the caller supplies the
	# real survivors through start(), and an auto-start here would build a whole
	# mocked arena first and throw it away one frame later — two halls, two
	# grids, and 16 bannermen spawned for nothing. Auto-start is therefore
	# conditional on BEING the scene, which is exactly when the cmdline flags
	# below are meant for us.
	if get_tree() != null and get_tree().current_scene != self:
		return
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a == "--tbf-ai":
			both_ai = true
		elif a.begins_with("--tbf-tier="):
			rival_tier = int(TIER_WORDS.get(a.substr(11), 1))
		elif a.begins_with("--tbf-seed="):
			arena_seed = int(a.substr(11))
		elif a.begins_with("--tbf-shots="):
			_shots_dir = a.substr(12)
		elif a == "--tbf-drive":
			_drive_demo = true
	var fast := args.has("--tbf-fast") or not _shots_dir.is_empty()
	start({"seed": arena_seed, "fast": fast})
	if _drive_demo:
		_drive_by_hand()
	if not _shots_dir.is_empty():
		_run_shot_reel()


## THE INTEGRATION SEAM. game.gd will call this with the real survivors and then
## await `trial_finished`. `cfg` keys: survivors (Array of [Vector2i, type,
## side]), seed, fast, houses, tier. Everything has a mocked default so the
## scene runs standalone, which is the whole point of this phase.
func start(cfg: Dictionary = {}) -> void:
	_teardown()
	var survivors: Array = cfg.get("survivors", _mock_survivors())
	var houses: Array = cfg.get("houses", [player_house, rival_house])
	player_house = str(houses[0])
	rival_house = str(houses[1])
	rival_tier = int(cfg.get("tier", rival_tier))
	var fast: bool = bool(cfg.get("fast", false))

	# THE ARENA DECIDES WHERE THE WALLS ARE, so ask it. The grid is built ONCE
	# with no crates purely to read its blackstone back, and the survivors are
	# then seated on squares it left free. Two setups instead of one, and worth
	# it: the first cut hard-coded survivor squares against the OLD lattice and
	# half the army silently vanished into stone — an arena with five crates in
	# it, which is a field, not a maze. Nothing here may re-derive the lattice
	# rule; there is one copy of it and it lives in blast_grid.gd.
	grid = GridScript.new()
	grid.setup({"crates": [], "seed": int(cfg.get("seed", arena_seed))})
	var free_cells: Array[Vector2i] = []
	for i in GridScript.CELLS:
		if grid.tiles[i] == GridScript.Tile.EMPTY:
			free_cells.append(grid.cell_of(i))
	survivors = _seat_survivors(survivors, free_cells)
	var crate_cells: Array = []
	for s in survivors:
		crate_cells.append(s[0])
	grid = GridScript.new()
	grid.setup({
		"crates": crate_cells,
		"seed": int(cfg.get("seed", arena_seed)),
		"sudden_death_at": 22.0 if fast else 70.0,
		"ring_interval": 0.30 if fast else 0.60,
		"fuse_sec": 1.9 if fast else 2.35,
	})
	_ai = [AiScript.new(rival_tier, int(cfg.get("seed", arena_seed)) + 1),
		AiScript.new(rival_tier, int(cfg.get("seed", arena_seed)) + 2)]

	_fx = FxScript.new()
	_fx.name = "ArenaFx"
	add_child(_fx)
	_fx.build(GridScript.CELLS, _board.TILE_SIZE, _board.TILE_HEIGHT)
	_incin = IncinScript.new()
	_incin.name = "Incinerator"
	add_child(_incin)
	_wyrm = WyrmScript.new()
	_wyrm.name = "WyrmClock"
	add_child(_wyrm)
	_hud = HudScript.new()
	_hud.name = "TrialHud"
	add_child(_hud)
	_hud.open()
	_hud.set_embedded(embedded)   # R and Esc mean different things in a match

	var hall := get_node_or_null("GreatHall")
	if hall != null and hall.has_method("dress_for_match"):
		hall.dress_for_match(player_house, rival_house)

	# THE BLACKSTONE. Placed from the grid's own tiles, never from a second copy
	# of the lattice rule — one source of truth for where a wall is.
	for i in GridScript.CELLS:
		if grid.tiles[i] == GridScript.Tile.STONE:
			_fx.add_stone(i, _world(grid.cell_of(i)), _board.PLINTH_STONE)

	# THE CRATES — the survivors, on their squares, in their own colours.
	for s in survivors:
		var cell: Vector2i = s[0]
		var idx: int = grid.index(cell)
		if grid.tiles[idx] != GridScript.Tile.CRATE:
			continue   # the arena claimed that square (blackstone or a pocket)
		var side: int = int(s[2]) if s.size() > 2 else 0
		_crates[idx] = _spawn_piece(int(s[1]), side, cell)

	for side in 2:
		var k := _spawn_piece(5, side, grid.kings[side].cell)   # 5 = KING
		k.name = "TrialKing%d" % side
		_kings.append(k)
		_king_from[side] = k.position
		_king_to[side] = k.position
		_king_t[side] = 1.0
		_king_dur[side] = 1.0

	_running = true
	_announced = false
	# THE FUSE. Tier 1 is a bare motorik sequencer — the arena is quiet and
	# nothing has been thrown yet. The other two tiers are the same loop with
	# more layers, and they are already playing underneath at silence.
	_music_tier(0)
	_refresh_hud()


func _teardown() -> void:
	_running = false
	_music_stop(0.0)   # a restart (R) cuts, it does not crossfade into itself
	for n in [_fx, _incin, _wyrm, _hud]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	for idx in _crates:
		if is_instance_valid(_crates[idx]):
			_crates[idx].queue_free()
	_crates.clear()
	for k in _kings:
		if is_instance_valid(k):
			k.queue_free()
	_kings.clear()


# ── the frame ───────────────────────────────────────────────────────────────


func _process(delta: float) -> void:
	if not _running or grid == null:
		return
	var dt := minf(delta, 1.0 / 20.0)   # a stalled frame must not skip a fuse
	_drive(dt)
	grid.tick(dt)
	_consume(grid.drain_events())
	_animate_kings(dt)
	_refresh_hud()


## Feed the two kings. Side 0 is the keyboard unless --tbf-ai; side 1 is always
## a brain. THE ORDER ALTERNATES BY FRAME: both are polled inside one tick, so a
## fixed order hands one of them a half-frame head start on every race for the
## same square — and this mode's entire job is to break a tie fairly.
func _drive(dt: float) -> void:
	var order := [0, 1] if Engine.get_process_frames() % 2 == 0 else [1, 0]
	for side in order:
		if side == 0 and not both_ai:
			if _held != Vector2i.ZERO:
				grid.request_step(0, _held)
			continue
		var act: Dictionary = _ai[side].decide(grid, side, dt)
		if act.has("keg"):
			grid.place_keg(side)
		elif act.has("step"):
			grid.request_step(side, act["step"])


## THE ONE-WAY VALVE: rules in, geometry out. Every branch here reads an event
## and builds something; not one of them decides anything.
func _consume(events: Array) -> void:
	for e in events:
		match e["kind"]:
			"keg_placed":
				_fx.add_keg(grid.index(e["cell"]), _world(e["cell"]), e["fuse"])
				# THE KEGS. Kick, tabor and bass arrive on the first jar that is
				# actually thrown — the cue is the EVENT, not a stopwatch, so a
				# cautious opening stays bare for as long as it stays cautious.
				_music_tier(1)
			"detonate":
				_fx.drop_keg(grid.index(e["cell"]))
				_fx.ignite(_world(e["cell"]))
			"flame":
				_fx.light(grid.index(e["cell"]), _world(e["cell"]), grid.flame_life)
			"crate_burned":
				var idx: int = grid.index(e["cell"])
				if _crates.has(idx) and is_instance_valid(_crates[idx]):
					_incin.burn(_crates[idx])
				_crates.erase(idx)
			"boon_revealed":
				_fx.add_boon(grid.index(e["cell"]), _world(e["cell"]), e["boon"])
			"boon_burned":
				_fx.drop_boon(grid.index(e["cell"]))
			"boon_taken":
				_fx.claim_boon(grid.index(e["cell"]), _world(e["cell"]), e["boon"])
			"step":
				_begin_step(int(e["side"]), e["from"], e["to"], float(e["dur"]))
			"sudden_death":
				_wyrm.wake()
				# THE WYRM. Lute, recorder and the hurdy-gurdy drone come in on
				# the same event that wakes the dragon — the ring starts closing
				# and the music stops being a pulse and becomes a piece.
				_music_tier(2)
			"torched":
				var ti: int = grid.index(e["cell"])
				_wyrm.torch(_world(e["cell"]))
				if _crates.has(ti) and is_instance_valid(_crates[ti]):
					_incin.burn(_crates[ti])
				_crates.erase(ti)
				_fx.drop_boon(ti)
				if not _fx.has_stone(ti):
					_fx.add_stone(ti, _world(e["cell"]), _board.PLINTH_STONE)
			"king_died":
				_fall(int(e["side"]))
			"over":
				_finish(int(e["winner"]))


## Walk away. The round is lost — that is the price, and it is stated on the
## card — but the match, the bracket and the process all survive.
func concede() -> void:
	if not _running or _announced:
		return
	conceded = true
	_running = false   # the arena stops taking input; the grid is left as it is
	_finish(1)


func _finish(side: int) -> void:
	if _announced:
		return
	_announced = true
	if conceded:
		_hud.announce("YOU YIELD THE ARENA", HudScript.EMBER)
		trial_finished.emit(side)
		return
	# THE DOUBLE KNOCKOUT NEEDS ITS OWN SENTENCE. When a chain takes both kings
	# the grid still names a champion (BlastGrid.winner — a tournament cannot
	# accept "nobody"), and the first cut announced that champion with "YOUR KING
	# STANDS" while his own card two inches away read "FALLEN". The verdict was
	# right and the copy was a lie, which is worse than either.
	var who := "YOUR KING" if side == 0 else "THE RIVAL KING"
	var tint: Color = HudScript.WILD if side == 0 else Color(0.95, 0.45, 0.25)
	if grid.kings[side].alive:
		_hud.announce("%s STANDS" % who, tint)
	else:
		_hud.announce("THE ASHES FAVOUR %s" % who, tint)
	trial_finished.emit(side)


# ── the kings ───────────────────────────────────────────────────────────────


## A committed step: the grid has already moved him (death is judged on the tile
## he is committed to — see BlastGrid's timing note), so the view's job is only
## to carry the body there over the same seconds and play the walk.
func _begin_step(side: int, from: Vector2i, to: Vector2i, dur: float) -> void:
	if side >= _kings.size() or not is_instance_valid(_kings[side]):
		return
	_king_from[side] = _world(from)
	_king_to[side] = _world(to)
	_king_t[side] = 0.0
	_king_dur[side] = maxf(dur, 0.02)
	var d := _king_to[side] - _king_from[side]
	_kings[side].rotation.y = atan2(d.x, d.z)
	if not _king_walking[side]:
		_king_walking[side] = true
		_play_clip(_kings[side], "Walking_A", 1.35, 0.12)


func _animate_kings(delta: float) -> void:
	for side in _kings.size():
		var k := _kings[side]
		if not is_instance_valid(k):
			continue
		if _king_t[side] < 1.0:
			_king_t[side] = minf(_king_t[side] + delta / _king_dur[side], 1.0)
			# A shallow stride bob. Without it a grid-stepper slides, and a king
			# who slides is a chess piece being dragged, not a man running.
			var u: float = _king_t[side]
			k.position = _king_from[side].lerp(_king_to[side], u) \
				+ Vector3.UP * absf(sin(u * PI)) * 0.035
			if u >= 1.0 and _king_walking[side]:
				_king_walking[side] = false
				_play_clip(k, "Idle_A", 1.0, 0.2)


func _fall(side: int) -> void:
	if side >= _kings.size() or not is_instance_valid(_kings[side]):
		return
	var k := _kings[side]
	_kings[side] = null
	_king_t[side] = 1.0
	# The king's own death, the same one he would have died in the war: PieceView
	# plays Hit_A, Death_A and sinks into the stone, then frees itself.
	if k.has_method("die"):
		k.die(k.DEATH_BURN if "DEATH_BURN" in k else "")
	else:
		k.queue_free()


## The piece's OWN AnimationPlayer, found by type rather than by reaching into
## PieceView's private `_anim`: that file belongs to another lane this phase, and
## a presentation module has no business holding its internals. Every KayKit
## character in this game carries one and it is loaded with the shared
## Rig_Medium library, so "Walking_A" and "Idle_A" are always there.
func _play_clip(node: Node3D, clip: String, speed: float, blend: float) -> void:
	for ap: AnimationPlayer in node.find_children("*", "AnimationPlayer", true, false):
		if ap.has_animation(clip):
			ap.speed_scale = speed
			ap.play(clip, blend)
			return


# ── the score ───────────────────────────────────────────────────────────────
#
# The arena drives MusicManager's three Trial-by-Fire layers; it does not own
# an audio system of its own. The node is looked up rather than referenced as
# the `Music` autoload global because the headless suites run this file with
# `-s`, where no autoload exists — a hard reference would turn "no music" into
# "no tests".


func _music() -> Node:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Music")


func _music_tier(tier: int) -> void:
	if not music_tier_log.is_empty() and music_tier_log[-1] == tier:
		return
	# The curve only ever climbs. Without this a jar thrown after the wyrm woke
	# would pull the lute back out of the mix at the tensest moment in the mode.
	if not music_tier_log.is_empty() and tier < music_tier_log[-1]:
		return
	music_tier_log.append(tier)
	var m := _music()
	if m == null:
		return
	if music_tier_log.size() == 1 and m.has_method("play_trial"):
		m.play_trial(tier)
	elif m.has_method("trial_tier"):
		m.trial_tier(tier)


func _music_stop(fade: float) -> void:
	music_tier_log.clear()
	var m := _music()
	if m != null and m.has_method("stop_trial"):
		m.stop_trial(fade)


func _spawn_piece(piece_type: int, side: int, cell: Vector2i) -> Node3D:
	var scene: PackedScene = load("res://scenes/piece_view.tscn")
	var p: Node3D = scene.instantiate()
	add_child(p)
	p.setup(piece_type, side, player_house if side == 0 else rival_house)
	p.position = _world(cell)
	return p


func _world(cell: Vector2i) -> Vector3:
	var local: Vector3 = _board.square_to_world(cell)
	return (_board as Node3D).to_global(local) if _board is Node3D else local


func _refresh_hud() -> void:
	if _hud == null or not is_instance_valid(_hud):
		return
	for side in 2:
		var k = grid.kings[side]
		_hud.set_king(side,
			"YOUR KING" if side == 0 else "THE RIVAL",
			Color(0.62, 0.79, 0.92) if side == 0 else Color(0.95, 0.78, 0.35),
			k.kegs_max - k.kegs_live, k.kegs_max, k.radius, k.speed, k.alive,
			"" if side == 0 and not both_ai else _ai[side].label())
	var patience: float = clampf(grid.time / maxf(grid.sudden_death_at, 0.01), 0.0, 1.0)
	var left := 0
	for i in GridScript.CELLS:
		if grid.tiles[i] != GridScript.Tile.STONE:
			left += 1
	_hud.set_clock(patience, grid.sudden, left)


# ── input ───────────────────────────────────────────────────────────────────


## WHILE THE ARENA OWNS THE FRAME, IT OWNS THE KEYBOARD.
##
## THE SCAR, measured 2026-08-09: the match's own `_unhandled_key_input` reads
## Esc as "return to the Hall of Banners" the moment `game_over` is set — and it
## IS set, because the stalemate is what raised this arena. Godot runs
## `_unhandled_key_input` BEFORE `_unhandled_input`, so the match answered first
## and the very first Esc pressed inside a bracket decider abandoned the duel
## and dropped the player at the menu. (In the e2e that re-entered the Hall,
## re-installed the harness, and ran the whole scenario three times in one log —
## which is how it was caught.) R would have reloaded the scene the same way,
## and Cmd+Z would have offered a take-back on a war that is already over.
##
## `_input` runs before all of them, so embedded the arena consumes every key.
## M is the one exception: it is the mute toggle and it harms nothing.
func _input(event: InputEvent) -> void:
	if not embedded or not (event is InputEventKey):
		return
	if (event as InputEventKey).keycode == KEY_M:
		return
	_route_key(event as InputEventKey)
	get_viewport().set_input_as_handled()


## Standalone only — embedded, `_input` above has already routed the key.
func _unhandled_input(event: InputEvent) -> void:
	if embedded or not (event is InputEventKey):
		return
	_route_key(event as InputEventKey)


func _route_key(event: InputEventKey) -> void:
	if event.echo:
		return
	var key := event.keycode
	if event.pressed:
		match key:
			KEY_ESCAPE:
				if embedded:
					concede()   # a way out that costs the round, never the game
				else:
					get_tree().quit()
				return
			KEY_R:
				if embedded:
					return      # no rerolling a bracket decider
				start({"seed": arena_seed + 1})
				return
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				if _running and not both_ai:
					grid.place_keg(0)
				return
	var dir := _dir_of(key)
	if dir == Vector2i.ZERO:
		return
	if event.pressed:
		_held = dir
	elif _held == dir:
		_held = Vector2i.ZERO


## Screen-space, not board-space. The default camera looks down the +Z axis from
## behind the player (orbit yaw PI), which flips X on screen — so "left" on the
## keyboard is +X in board coords. Getting this backwards is invisible in a test
## and instantly infuriating with a keyboard in your hands.
func _dir_of(key: int) -> Vector2i:
	match key:
		KEY_W, KEY_UP:
			return Vector2i(0, 1)
		KEY_S, KEY_DOWN:
			return Vector2i(0, -1)
		KEY_A, KEY_LEFT:
			return Vector2i(1, 0)
		KEY_D, KEY_RIGHT:
			return Vector2i(-1, 0)
	return Vector2i.ZERO


func _mock_survivors() -> Array:
	var out: Array = []
	var n := 0
	for s in MOCK_SURVIVORS:
		out.append([s[0], s[1], 0 if n < MOCK_SURVIVORS.size() / 2 else 1])
		n += 1
	return out


## Seat every survivor on a square the arena actually left open, keeping each
## man as close to where he stood as possible: the crate field IS the drawn
## position, and a bishop that teleports across the board to become a crate has
## thrown away the one thing that makes this arena THIS match's arena. A man
## whose square became blackstone slides to the nearest free one; a man with
## nowhere to go is simply not in the trial.
func _seat_survivors(survivors: Array, free_cells: Array[Vector2i]) -> Array:
	var taken := {}
	for k in grid.kings:
		for d in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0),
				Vector2i(0, 1), Vector2i(0, -1)]:
			taken[grid.index(k.cell + d) if grid.in_bounds(k.cell + d) else -1] = true
	var out: Array = []
	for s in survivors:
		var want: Vector2i = s[0]
		var best := Vector2i(-1, -1)
		var best_d := 999
		for c in free_cells:
			var i: int = grid.index(c)
			if taken.has(i):
				continue
			var d: int = absi(c.x - want.x) + absi(c.y - want.y)
			if d < best_d:
				best_d = d
				best = c
		if best.x < 0:
			continue
		taken[grid.index(best)] = true
		out.append([best, s[1], s[2] if s.size() > 2 else 0])
	return out


# ── the shot reel (windowed capture, for looking at what shipped) ───────────


## Drive a demo match and photograph the beats that matter. Waits on STATE (a
## jar exists, a cross is burning, the wyrm is awake) and never on a stopwatch:
## the ashfall in this project shipped a whole day of frames that photographed
## the wrong beat because they were timed rather than triggered, and the fix was
## exactly this — instruments wait on the thing they claim to show.
func _run_shot_reel() -> void:
	if not _drive_demo:
		both_ai = true
	await get_tree().create_timer(0.6).timeout
	await _shot("01_arena")
	await _until(func() -> bool: return not grid.kegs.is_empty(), 12.0)
	await _shot("02_jar_lit")
	# A CROSS, not the first three tiles that happen to catch. Six lit tiles on
	# one blast is a cross with arms; five could be two small ones in different
	# corners, which is what the first reel actually photographed and what made
	# "the blast reads as a blast" impossible to judge from it.
	await _until(func() -> bool: return _biggest_fire_run() >= 6, 30.0)
	await _shot("03_blast")
	await _until(func() -> bool: return _incin.remains_count() > 0, 14.0)
	# …and let the flash pass. The skeleton is the point of the incineration and
	# for the first 0.13 s it is still a white-hot bannerman.
	await get_tree().create_timer(0.45).timeout
	await _shot("04_incineration")
	await _until(func() -> bool: return _wyrm.is_awake(), 60.0)
	await get_tree().create_timer(1.2).timeout
	await _shot("05_wyrm_wakes")
	await _until(func() -> bool: return grid.sudden and _burning_tiles() >= 1, 20.0)
	await _shot("06_ring_closes")
	await _until(func() -> bool: return grid.is_over(), 90.0)
	await get_tree().create_timer(1.0).timeout
	await _shot("07_verdict")
	get_tree().quit()


func _burning_tiles() -> int:
	var n := 0
	for i in GridScript.CELLS:
		if grid.flame[i] > 0.0:
			n += 1
	return n


## The largest CONNECTED patch of fire — one blast, not the whole board's worth
## of unrelated ones added together.
func _biggest_fire_run() -> int:
	var seen := {}
	var best := 0
	for i in GridScript.CELLS:
		if grid.flame[i] <= 0.0 or seen.has(i):
			continue
		var n := 0
		var stack := [i]
		seen[i] = true
		while not stack.is_empty():
			var j: int = stack.pop_back()
			n += 1
			for d in GridScript.DIRS:
				var c: Vector2i = grid.cell_of(j) + d
				if not grid.in_bounds(c):
					continue
				var k: int = grid.index(c)
				if grid.flame[k] > 0.0 and not seen.has(k):
					seen[k] = true
					stack.append(k)
		best = maxi(best, n)
	return best


## HAND-DRIVEN PROOF. `--tbf-drive` runs the player's king off SYNTHETIC KEY
## EVENTS pushed through Input.parse_input_event — the same InputEventKey the
## keyboard produces, through the same _unhandled_input, through the same
## _held / place_keg path. It is not the AI wearing a player's hat: if the
## keyboard binding were wrong, this would sit still.
func _drive_by_hand() -> void:
	var moves: Array = [
		[KEY_W, 0.30], [KEY_W, 0.30], [KEY_SPACE, 0.10],
		[KEY_S, 0.30], [KEY_S, 0.30], [KEY_A, 0.34], [KEY_A, 0.34],
		[KEY_SPACE, 0.10], [KEY_D, 0.30], [KEY_W, 0.34], [KEY_W, 0.34],
	]
	var opened: Vector2i = grid.kings[0].cell
	print("TBF DRIVE begins at %s" % str(opened))
	var trail: Array = [str(opened)]
	for beat in moves:
		if not _running or grid.is_over() or not grid.kings[0].alive:
			break
		_key(beat[0], true)
		await get_tree().create_timer(float(beat[1])).timeout
		_key(beat[0], false)
		await get_tree().process_frame
		trail.append("%s%s" % [str(grid.kings[0].cell),
			"+jar" if beat[0] == KEY_SPACE else ""])
	print("TBF DRIVE %s | alive=%s" % [" ".join(PackedStringArray(trail)),
		grid.kings[0].alive])


func _key(code: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _until(cond: Callable, budget: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(budget * 1000.0):
		if cond.call():
			return
		await get_tree().process_frame


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(_shots_dir)
	_shot_n += 1
	img.save_png("%s/%s.png" % [_shots_dir, label])
	print("TBF SHOT %s" % label)
