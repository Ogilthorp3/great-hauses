extends RefCounted
## TRIAL BY FIRE — the rival king's brain.
##
## Pure like the grid it reads: no Node, no tree, no rendering. `decide()` takes
## the grid and returns at most one verb per call ({"step": Vector2i} or
## {"keg": true}), which is exactly what a human can do with a keyboard. It has
## no privileged access — everything it knows comes from `grid.danger_map()`,
## the same projection the HUD could draw.
##
## THE THREE TIERS ARE THE CHESS OPPONENTS. src/ui/house_select.gd offers
## Casual / Seasoned / Master and hands ChessAI.Difficulty.EASY/MEDIUM/HARD to
## the engine; a king who fought you as Master and then plays the tie-breaker
## like a drunk is a broken promise, so the same three names carry over and the
## mapping is one table.
##
##   CASUAL   slow to react (0.42 s), sees 1.15 s into the future, and BLUNDERS
##            — a 20 % chance per decision that it simply ignores the danger
##            map, plus no retreat check before it sets a keg down. It still
##            kills itself in most duels, which is what "casual" has to mean in
##            a game where the enemy is mostly your own bad planning; but it
##            has a short nerve (four tiles) and WILL come at a player who
##            stands still, because an opponent that can never reach you is a
##            difficulty setting in name only.
##   SEASONED 0.20 s, 2.10 s of lookahead, checks it has somewhere to run
##            BEFORE lighting a fuse, and comes hunting once you are within
##            five tiles.
##   MASTER   0.06 s, 3.20 s of lookahead, never blunders, always hunting. It
##            reads the chain (danger_map's two relaxation passes), it will not
##            walk into the far end of a fuse that has not started, and when the
##            arena closes it does not retreat a tile at a time — it searches
##            the whole board for the square that burns LAST and goes and stands
##            there. That last skill is `refuge`, and it is what actually
##            separates this tier from the one below it.
##
## THE DECISION LADDER, in priority order — the ordering IS the personality:
##   1. AM I IN THE FIRE'S PATH?  Breadth-first to the nearest tile that is
##      safe AND reachable before it stops being safe. This outranks
##      everything: no amount of opportunity is worth standing in a cross.
##   2. IS IT WORTH A KEG?  Adjacent to a crate, or the rival is close enough
##      to be caught. Gated on having a retreat (a tier that skips this gate
##      is a tier that suicides, which is the Casual tier's whole character).
##   3. WHERE DO I WANT TO BE?  Boon on the floor > a crate to break > the
##      rival king. Nearest-first, breadth-first, through safe tiles only.
##
## PATHFINDING IS TIME-AWARE. A tile is not "walkable" or "blocked", it is
## "reachable before it burns": every BFS step costs `step_sec / speed`, and a
## tile whose danger eta is earlier than the arrival time is a wall. That single
## rule is the difference between an AI that avoids fire and an AI that walks
## into fire that has not happened yet.

const Grid := preload("res://src/minigame/blast_grid.gd")

enum Difficulty { CASUAL, SEASONED, MASTER }

const TIERS := {
	Difficulty.CASUAL: {
		"label": "Casual", "think": 0.42, "horizon": 1.15, "blunder": 0.20,
		"hunt": 4, "retreat": false, "wander": 0.35, "refuge": 1,
	},
	Difficulty.SEASONED: {
		"label": "Seasoned", "think": 0.20, "horizon": 2.10, "blunder": 0.08,
		"hunt": 5, "retreat": true, "wander": 0.12, "refuge": 1,
	},
	Difficulty.MASTER: {
		"label": "Master", "think": 0.06, "horizon": 3.20, "blunder": 0.0,
		"hunt": 99, "retreat": true, "wander": 0.0, "refuge": 8,
	},
}

## WHERE THE LADDER WAS ACTUALLY BROKEN — TWO SEPARATE FAULTS, ONE AT EACH END,
## and the diagnosis for both came out of src/minigame/dev_ladder_probe.gd.
##
## THE CONTROL FIRST, because this file has been burned once by skipping it. Two
## RANDOM WALKERS on the same arenas: corner (0,0) took 48-52 % and the two sides
## killed themselves 19-vs-21. The board is fair to dice, so what follows is a
## brain problem and not another broken fixture.
##
## FAULT 1 — MASTER ≈ SEASONED (55 %, a coin flip) WHILE BEATING CASUAL 90 %.
## The obvious reading is "the top two brains are the same brain", and it is
## wrong. Split every duel by WHO DECIDED IT:
##
##     arena      duels the KINGS decided     duels the WYRM decided
##     full        Master 82 %                 Master 56 %
##     fast        Master 69 %                 Master 40 %
##     fixture     Master 76 %                 Master 53 %
##
## Master out-fought Seasoned by 20-30 points and then played the closing ring
## EXACTLY AS WELL AS IT DID — and on the short clocks the wyrm decides 50-59 %
## of all duels, so the cell averaged down to 50 %. The tiers were never
## separated at the thing that settles half the mode: SURVIVING A SHRINKING
## ARENA. That is the second skill this game asks for and it had no tier axis at
## all, because every tier ran the same one-tile hill climb when cornered.
##
## THE FIX IS `refuge` — how deep a king searches for the tile that burns LAST
## once nothing is safe (see _refuge). Depth 1 is the old neighbours-only step;
## depth 8 crosses the arena, which under a closing ring means walking to the
## middle while the fire is still on the rim. Measured on the `fast` arena,
## Master over Seasoned against refuge depth: 1 -> 52 %, 2 -> 65 %, 4 -> 70 %,
## 8 -> 70 %, 16 -> 70 %. It is pure lookahead over the same public danger map —
## nothing a player with good eyes could not do.
##
## THE FALSE LEAD, KEPT BECAUSE IT COST AN HOUR. The first idea was `ring_sense`:
## the wyrm's spiral is scheduled minutes ahead, so let the good tiers multiply
## their horizon once it wakes and leave early. It is worse, badly, and the
## direction is the lesson — Master over Seasoned by ring_sense: 1.0 -> 52 %,
## 1.5 -> 35 %, 2.0 -> 35 %, 3.0 -> 25 %, 6.0 -> 25 %. A king who sees the whole
## board burning finds rule 1 (get out of the fire's path) true on EVERY tile of
## every decision, so he never lays another jar, never takes another boon, and
## spends the endgame running from a fire that has not started. Seeing further is
## not the skill; knowing where to stand is. Reverted.
##
## FAULT 2 — CASUAL COULD NOT THREATEN A STANDING PLAYER AT ALL. Against an idle
## king with the wyrm switched off it landed 3 kills in 40 attempts on the
## fixture arena (the suite's own measurement was 0/20) — and it killed ITSELF in
## 35 of those 40. That is not an easy opponent, it is no opponent: a player who
## never presses a key is never in danger from it.
##
## Two causes, and the second one dominates:
##   `hunt` 0 -> 4   with a nerve of zero it never walked toward the rival at
##                   all, so it only ever reached him by accident.
##   `blunder` 0.30 -> 0.20   the real one. Blundering is ignoring the danger map
##                   for a decision, and at 0.30 the Casual king blew himself up
##                   long before he arrived anywhere. Idle-king kills against
##                   blunder: 0.30 -> 12 %, 0.20 -> 25 %, 0.12 -> 40 %, 0.05 ->
##                   65 %. 0.20 is a floor, not a promotion — he still kills
##                   himself in three duels out of four and still loses to
##                   Seasoned by a mile. THE FLOOR WAS RAISED, THE CEILING WAS
##                   NOT LOWERED: no tier above him was weakened to make the
##                   ladder monotone.
##
## ALSO TRIED AND REVERTED: making `retreat` a probability (Casual checks for a
## door half the time instead of never). Idle-king kills at retreat 0.0 / 0.5 /
## 1.0 came out 30 % / 22 % / 30 % — noise on 40 duels. It reads like a fix and
## measures like nothing, so `retreat` stays the bool it was.

## Margin between "I arrive" and "it burns". Below this a step is a coin flip
## on floating-point noise, and a king who takes those dies to rounding.
const SAFETY_MARGIN := 0.14
## TRANSIT IS TIMED; A DESTINATION IS NOT. Two questions that look like one, and
## conflating them is how this file lost an afternoon.
##
##   PASSING THROUGH a tile only requires that it is not on fire AT THE MOMENT
##   YOU CROSS IT — the `arrive` test inside _path_to — which is what lets a
##   king thread a corridor between two burning crosses.
##   STANDING ON one requires that it will not burn AT ALL, because the king is
##   still there when it does. A retreat two steps out (0.42 s) from a jar with
##   a 1.6 s fuse passes every "safe when I arrive" test while sitting squarely
##   inside that jar's own cross — which is exactly how the kings were dying:
##   instrumented over 80 mirror matches, 46 of 48 self-kills happened ONE TILE
##   from the king's own keg.
##
## THE FALSE LEAD IS WORTH MORE THAN THE FIX. The strict rule below was tried
## first, MEASURED AS WORSE (Seasoned beat Master 15-24 — the better tier
## apparently losing because it saw further), and replaced by a timed one. That
## measurement was real; the conclusion drawn from it was wrong. The FIXTURE was
## broken: the suite's crate generator still skipped odd/odd cells from an older
## lattice, leaving eight permanently-open squares in ONE king's half — worth
## 80/20 on its own. Every AI conclusion measured on that arena was measuring
## the arena.
##
## The tell was available all along and is the cheap check to run FIRST: random
## walkers on the same board came out 43 self-kills to 37, i.e. fair. A board
## that is fair to dice and unfair to a brain is a brain problem; a board that
## is unfair to DICE is a board problem. On the corrected arena the strict rule
## is comfortably better — corner fairness 48 %, self-kills 41 vs 39, and a
## ladder that is finally monotone: Master 66 % on Seasoned, Seasoned 84 % on
## Casual, Master 84 % on Casual.
## How far the breadth-first search will look before giving up. 64 cells is the
## whole arena; the cap exists so a pathological grid cannot spin.
const BFS_CAP := 96

var difficulty: int = Difficulty.SEASONED
var rng := RandomNumberGenerator.new()

## PER-INSTANCE TIER OVERRIDES — the sweep seam, and empty in the game.
##
## The tier table above is the shipping answer, and it got to be the shipping
## answer by being measured against a few hundred alternatives. Doing that by
## editing the constant means every sweep is a working-tree edit you can forget
## to undo; this lets dev_ladder_probe.gd try a value without the file ever
## changing. Nothing in src/ writes it.
var overrides := {}

var _cool := 0.0
var _last_step := Vector2i.ZERO


func _init(tier: int = Difficulty.SEASONED, seed_value: int = 7) -> void:
	difficulty = tier
	rng.seed = seed_value
	# Stagger the first thought so two AIs seeded alike do not move in lockstep.
	_cool = rng.randf() * 0.2


func tier() -> Dictionary:
	if overrides.is_empty():
		return TIERS[difficulty]
	var t: Dictionary = TIERS[difficulty].duplicate()
	for k in overrides:
		t[k] = overrides[k]
	return t


func label() -> String:
	return str(TIERS[difficulty]["label"])


## One turn of thought. Returns {} (do nothing), {"step": Vector2i} or
## {"keg": true}. Safe to call every frame: it rate-limits itself to the tier's
## reaction time and refuses while the king is mid-step.
func decide(grid, side: int, dt: float) -> Dictionary:
	_cool -= dt
	if side < 0 or side >= grid.kings.size():
		return {}
	var me = grid.kings[side]
	if not me.alive or me.busy > 0.0 or grid.is_over():
		return {}
	if _cool > 0.0:
		return {}
	var t: Dictionary = tier()
	_cool = float(t["think"])

	var danger: Dictionary = grid.danger_map(float(t["horizon"]))
	var here: int = grid.index(me.cell)
	var blind: bool = rng.randf() < float(t["blunder"])

	# ── 1. get out of the fire's path ─────────────────────────────────────
	if danger.has(here) and not blind:
		var run := _path_to(grid, me, danger,
			_somewhere_to_stand(grid, danger))
		if not run.is_empty():
			return _step(me, run[0])
		var salvage := _refuge(grid, me, danger, int(t["refuge"]))
		if salvage != Vector2i.ZERO:
			return _step(me, me.cell + salvage)
		return {}

	# ── 2. is it worth a jar? ─────────────────────────────────────────────
	if me.kegs_live < me.kegs_max and _worth_a_keg(grid, me, side, int(t["hunt"])):
		if not bool(t["retreat"]) or _has_retreat(grid, me, danger):
			return {"keg": true}

	# ── 3. go somewhere useful ────────────────────────────────────────────
	var want := _seek(grid, me, side, danger, int(t["hunt"]))
	if not want.is_empty():
		return _step(me, want[0])

	# Nothing to do: shuffle rather than stand in the open (only the sloppier
	# tiers do this — a Master that has nothing to do is holding a corner).
	if rng.randf() < float(t["wander"]):
		var opts := _safe_neighbours(grid, me, danger)
		if not opts.is_empty():
			return _step(me, opts[rng.randi() % opts.size()])
	return {}


func _step(me, target: Vector2i) -> Dictionary:
	_last_step = target - me.cell
	return {"step": _last_step}


# ── the searches ────────────────────────────────────────────────────────────


## Breadth-first from the king to the nearest cell satisfying `accept`, through
## tiles that are still safe WHEN HE GETS THERE. `accept` is called with
## (cell, arrival_seconds) — the arrival time is half the question for anything
## fire-related. Returns the path as cells (excluding the start); [] when
## nothing qualifies.
func _path_to(grid, me, danger: Dictionary, accept: Callable) -> Array:
	var step_cost: float = grid.step_sec / maxf(me.speed, 0.05)
	var start: Vector2i = me.cell
	var came := {}
	var depth := {grid.index(start): 0}
	var queue: Array[Vector2i] = [start]
	var head := 0
	var seen := 0
	while head < queue.size() and seen < BFS_CAP:
		var c: Vector2i = queue[head]
		head += 1
		seen += 1
		var d: int = depth[grid.index(c)]
		if c != start and accept.call(c, float(d) * step_cost):
			return _unwind(came, start, c)
		for dir in Grid.DIRS:
			var n: Vector2i = c + dir
			if not grid.walkable(n):
				continue
			var ni: int = grid.index(n)
			if depth.has(ni):
				continue
			var arrive := float(d + 1) * step_cost
			if grid.flame[ni] > 0.0 and grid.flame[ni] > arrive:
				continue   # still burning when I would arrive
			if danger.has(ni) and float(danger[ni]) < arrive + SAFETY_MARGIN:
				continue   # it lights before, or just as, I get there
			depth[ni] = d + 1
			came[ni] = c
			queue.append(n)
	return []


## `came` is keyed by grid index, valued by predecessor cell. Walks back from
## the goal and returns [first step after start, …, goal].
## Somewhere the king can STOP: no fire is coming to this tile at all inside the
## tier's horizon. Strict on purpose — see the block above for the two
## measurements that settled it.
func _somewhere_to_stand(grid, danger: Dictionary) -> Callable:
	return func(c: Vector2i, _at: float) -> bool:
		return not danger.has(grid.index(c))


func _unwind(came: Dictionary, start: Vector2i, goal: Vector2i) -> Array:
	var path: Array = [goal]
	var c := goal
	for _guard in BFS_CAP:
		var i: int = c.y * Grid.SIZE + c.x
		if not came.has(i):
			break
		var p: Vector2i = came[i]
		if p == start:
			break
		path.push_front(p)
		c = p
	return path


## Somewhere worth walking to, best goal first.
func _seek(grid, me, side: int, danger: Dictionary, hunt: int) -> Array:
	# a boon lying on the stone
	var to_boon := _path_to(grid, me, danger, func(c: Vector2i, _at: float) -> bool:
		return grid.boons[grid.index(c)] != Grid.Boon.NONE)
	if not to_boon.is_empty():
		return to_boon
	# a tile touching a crate — that is where a keg does work
	var to_crate := _path_to(grid, me, danger, func(c: Vector2i, _at: float) -> bool:
		for d in Grid.DIRS:
			if grid.tile_at(c + d) == Grid.Tile.CRATE:
				return true
		return false)
	if not to_crate.is_empty():
		return to_crate
	# the rival — only within the tier's nerve
	var foe = grid.kings[1 - side]
	if foe.alive and hunt > 0:
		var gap: int = absi(foe.cell.x - me.cell.x) + absi(foe.cell.y - me.cell.y)
		if gap <= hunt:
			return _path_to(grid, me, danger, func(c: Vector2i, _at: float) -> bool:
				return absi(c.x - foe.cell.x) + absi(c.y - foe.cell.y) <= 1)
	return []


## Would a keg here accomplish anything? A crate to break, or a rival close
## enough that the cross (or one step of chasing) reaches him.
func _worth_a_keg(grid, me, side: int, hunt: int) -> bool:
	for d in Grid.DIRS:
		if grid.tile_at(me.cell + d) == Grid.Tile.CRATE:
			return true
	if hunt <= 0:
		return false
	var foe = grid.kings[1 - side]
	if not foe.alive:
		return false
	var gap: int = absi(foe.cell.x - me.cell.x) + absi(foe.cell.y - me.cell.y)
	if gap > mini(hunt, 3):
		return false
	for c in grid.blast_cells(me.cell, me.radius):
		if c == foe.cell:
			return true
	return gap <= 2


## Simulate the jar we are about to set down and ask whether anywhere safe is
## still reachable BEFORE IT GOES OFF. This is the gate between "aggressive"
## and "suicidal", and it is deliberately a SET test, not a timing one: the
## retreat tile must be OUTSIDE the cross entirely. "It does not burn until
## after I arrive" is true of every tile in the blast and is how this gate
## used to wave the king to his own funeral.
func _has_retreat(grid, me, danger: Dictionary) -> bool:
	var blast := {}
	for c in grid.blast_cells(me.cell, me.radius):
		blast[grid.index(c)] = true
	var hypo := danger.duplicate()
	for i in blast:
		hypo[i] = minf(hypo.get(i, 99.0), grid.fuse_sec)
	# The RETREAT gate is deliberately looser than the "somewhere to stand" gate
	# above it: the question here is only "will my own jar kill me", so the tile
	# has to be out of MY cross and clear of other fire for one reaction plus two
	# steps — not clear of everything the tier can see. Tightening this to full
	# strictness makes both good tiers refuse to bomb and collapses the ladder:
	# measured, Master-over-Seasoned fell from 66 % to 50 % on that change alone.
	var slack: float = float(tier()["think"]) \
		+ 2.0 * grid.step_sec / maxf(me.speed, 0.05)
	var budget: float = grid.fuse_sec - grid.flame_life * 0.5
	var run := _path_to(grid, me, hypo, func(c: Vector2i, at: float) -> bool:
		if at > budget or blast.has(grid.index(c)):
			return false
		return float(hypo.get(grid.index(c), 99.0)) > at + slack)
	return not run.is_empty()


## NOTHING IS SAFE ANY MORE: go to the tile that burns LAST, within `depth`
## steps. Returns the first step of the way there, or ZERO to stand still.
##
## THE DEPTH IS THE TIER, and it is the difference between a king who takes the
## nearest breath and one who reads the whole closing arena. At depth 1 this is
## exactly the old neighbours-only hill climb — one tile of foresight, which is
## the sloppy tiers' character and was every tier's behaviour until the ring was
## measured. At depth 16 the search covers the arena, so under the wyrm's ring
## (where every remaining tile has an eta and the etas grow inward) the deepest
## pocket IS the middle: the Master king walks to the centre while the fire is
## still on the rim, instead of retreating one tile at a time into the corner
## the spiral is about to reach.
##
## Time-aware like every other search here: a tile you cannot get to before it
## lights is not a refuge, it is a slower death.
func _refuge(grid, me, danger: Dictionary, depth: int) -> Vector2i:
	var step_cost: float = grid.step_sec / maxf(me.speed, 0.05)
	var start: Vector2i = me.cell
	var came := {}
	var dist := {grid.index(start): 0}
	var queue: Array[Vector2i] = [start]
	var head := 0
	var best := start
	var best_eta: float = float(danger.get(grid.index(start), 0.0))
	var best_depth := 0
	while head < queue.size() and head < BFS_CAP:
		var c: Vector2i = queue[head]
		head += 1
		var d: int = dist[grid.index(c)]
		if d >= depth:
			continue
		for dir in Grid.DIRS:
			var n: Vector2i = c + dir
			if not grid.walkable(n):
				continue
			var ni: int = grid.index(n)
			if dist.has(ni):
				continue
			var arrive := float(d + 1) * step_cost
			if grid.flame[ni] > 0.0 and grid.flame[ni] > arrive:
				continue   # still burning when I would get there
			var eta: float = float(danger.get(ni, 99.0))
			if eta < arrive:
				continue   # it is ash before I arrive — not a refuge
			dist[ni] = d + 1
			came[ni] = c
			queue.append(n)
			# The latest-burning tile wins; ties go to the nearer one, because
			# every extra step is a step spent inside the fire he is fleeing.
			if eta > best_eta or (is_equal_approx(eta, best_eta) and d + 1 < best_depth):
				best_eta = eta
				best = n
				best_depth = d + 1
	if best == start:
		return Vector2i.ZERO
	var path := _unwind(came, start, best)
	return Vector2i.ZERO if path.is_empty() else (path[0] as Vector2i) - start


func _safe_neighbours(grid, me, danger: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in Grid.DIRS:
		var n: Vector2i = me.cell + d
		if grid.walkable(n) and not danger.has(grid.index(n)) \
				and grid.flame[grid.index(n)] <= 0.0:
			out.append(n)
	return out
