extends SceneTree

# TRIAL BY FIRE — headless unit tests for the stalemate minigame's rules.
#
# The whole module was written so this file could exist: src/minigame/
# blast_grid.gd and king_ai.gd are RefCounted state machines ticked with a
# float, with no Node, no autoload and no rendering server anywhere in them.
# Everything below therefore runs in a plain `-s` script in well under a
# second, INCLUDING complete AI-vs-AI matches.
#
# What is covered, and why each one is here:
#   - BLAST SHAPE            a cross, not a square and not a circle; the arms
#                            are `radius` long; the origin tile always burns
#   - STONE STOPS IT         blackstone is not lit and nothing behind it is
#                            (this is the rule the whole lattice rests on)
#   - CRATES EAT IT          a crate burns and the arm dies there — which is
#                            what makes a wall of your own bannermen cover
#   - CHAINS                 an arm that reaches a keg lights it, and the new
#                            keg blasts with ITS OWN radius from ITS OWN tile
#   - PROPAGATION IS TIMED   the far end of an arm lights LATER than the near
#                            end (one tile per ring_step), because "the blast
#                            walks" is a gameplay promise, not a description
#   - BOONS                  hidden under crates, surface when the fire dies,
#                            and apply to the king who steps on them
#   - THE KINGS CAN MEET     the flood-fill that proves the arena is ONE arena
#                            — the check the mirrored lattice needed and never
#                            had. It is gated in both directions: every
#                            generated arena must pass, and three hand-built
#                            sealed boards must be REJECTED
#   - THE WYRM'S RING        torches the outer ring inward, entombs the arena,
#                            and kills a king standing on the cell it takes
#   - DEATH                  a king in a lit tile dies; a king may never walk
#                            INTO fire; the verdict is never "nobody"
#   - AI vs AI TERMINATES    every tier pairing, several seeds, always ends
#                            with a named winner inside a bounded tick budget
#
# Run: /Applications/Godot.app/Contents/MacOS/Godot --headless --path <project> \
#        -s res://tests/test_minigame.gd
# Exit code 0 = all green, 1 = failures.

const Grid := preload("res://src/minigame/blast_grid.gd")
const AI := preload("res://src/minigame/king_ai.gd")

var rows := []
var failures := 0
var checks_run := 0

## A hard-erroring test function aborts silently at the error and its caller
## carries on as if it passed — the floor turns a silent abort into a loud
## failure (same guard test_dragon.gd and test_cinematics.gd use).
const MIN_EXPECTED_CHECKS := 124

const DT := 1.0 / 60.0


func _initialize() -> void:
	print("=== TRIAL BY FIRE — minigame rules suite ===")
	_test_blast_shape()
	_test_stone_and_crates()
	_test_chain()
	_test_timing()
	_test_boons()
	_test_connectivity()
	_test_duel_outcome()
	_test_ring()
	_test_death()
	_test_ai_matches()
	_print_summary()


# ── helpers ─────────────────────────────────────────────────────────────────


func check(test_name: String, expected, actual) -> void:
	checks_run += 1
	var ok := str(expected) == str(actual)
	if not ok:
		failures += 1
	rows.push_back([test_name, str(expected), str(actual), ok])


## An arena with no crates and (optionally) no lattice, so a test measures the
## rule it is about and not the furniture.
func _bare(cfg: Dictionary = {}) -> Grid:
	var g: Grid = Grid.new()
	var base := {"sudden_death_at": 9999.0, "seed": 4242}
	for k in cfg:
		base[k] = cfg[k]
	g.setup(base)
	# strip the odd/odd lattice unless the test asked for it
	if not cfg.get("keep_lattice", false):
		for i in Grid.CELLS:
			g.tiles[i] = Grid.Tile.EMPTY
	base.erase("keep_lattice")
	return g


func _keep(cfg: Dictionary) -> Grid:
	cfg["keep_lattice"] = true
	return _bare(cfg)


## Tick until the fire is out and every keg has gone off (or the budget ends).
## Returns the seconds of simulated time consumed.
func _settle(g: Grid, budget := 8.0) -> float:
	var t := 0.0
	while t < budget:
		g.tick(DT)
		t += DT
		if g.kegs.is_empty() and g.arms.is_empty() and _no_fire(g):
			return t
	return t


func _no_fire(g: Grid) -> bool:
	for i in Grid.CELLS:
		if g.flame[i] > 0.0:
			return false
	return true


## Walk a king one tile and let the stride finish. The grid refuses a step
## while `busy`, so a test that wants two steps has to spend the seconds — and
## spending them is the point: the fuse is burning while he runs.
func _walk(g: Grid, side: int, dir: Vector2i) -> bool:
	if not g.request_step(side, dir):
		return false
	while g.kings[side].busy > 0.0:
		g.tick(DT)
	return true


func _cells(arr) -> Array:
	var out: Array = []
	for c in arr:
		out.append("%d,%d" % [c.x, c.y])
	out.sort()
	return out


## Every tile the fire touched over a whole detonation, gathered from the event
## stream — the timed path's answer, to be compared against blast_cells()'s.
func _burned(g: Grid, budget := 8.0) -> Array:
	var hit := {}
	var t := 0.0
	while t < budget:
		for e in g.drain_events():
			if e["kind"] == "flame":
				hit[e["cell"]] = true
		if g.kegs.is_empty() and g.arms.is_empty() and _no_fire(g):
			break
		g.tick(DT)
		t += DT
	for e in g.drain_events():
		if e["kind"] == "flame":
			hit[e["cell"]] = true
	return _cells(hit.keys())


# ── the blast ───────────────────────────────────────────────────────────────


func _test_blast_shape() -> void:
	var g := _bare()
	# A cross of radius 2 around (3,3): the origin plus two tiles each way.
	var cross := g.blast_cells(Vector2i(3, 3), 2)
	check("blast: radius 2 lights 9 tiles", 9, cross.size())
	check("blast: it is a CROSS, not a square",
		["1,3", "2,3", "3,1", "3,2", "3,3", "3,4", "3,5", "4,3", "5,3"],
		_cells(cross))
	check("blast: the diagonal is NOT lit", false,
		_cells(cross).has("4,4"))
	check("blast: radius 1 lights 5", 5, g.blast_cells(Vector2i(3, 3), 1).size())
	# From (3,3) a radius-4 cross would want 17 tiles, but two of its arms run
	# off an 8-wide board first: the arena's edge is a wall like any other.
	check("blast: radius 4 from (3,3) is clipped to 15", 15,
		g.blast_cells(Vector2i(3, 3), 4).size())
	check("blast: the same cross from the middle of a long arm is not", 13,
		g.blast_cells(Vector2i(3, 3), 3).size())

	# The board edge clips the arms — a corner keg lights an L, not a cross.
	var corner := g.blast_cells(Vector2i(0, 0), 3)
	check("blast: corner keg is clipped by the board edge", 7, corner.size())
	check("blast: nothing off the board", true, _cells(corner).find("-1,0") < 0)

	# The timed walk must agree with the instant preview, cell for cell.
	var g2 := _bare()
	g2.kings[0].cell = Vector2i(7, 0)
	g2.kings[1].cell = Vector2i(0, 7)
	g2.kings[0].radius = 2
	g2.kings[0].cell = Vector2i(3, 3)
	check("blast: keg placed", true, g2.place_keg(0))
	var preview := _cells(g2.blast_cells(Vector2i(3, 3), 2))
	check("blast: the timed walk burns exactly the previewed cells",
		preview, _burned(g2))


func _test_stone_and_crates() -> void:
	var g := _bare()
	g.tiles[g.index(Vector2i(5, 3))] = Grid.Tile.STONE
	var cross := _cells(g.blast_cells(Vector2i(3, 3), 3))
	check("stone: the blackstone tile is NOT lit", false, cross.has("5,3"))
	check("stone: nothing behind it is lit", false, cross.has("6,3"))
	check("stone: the tile in front of it still is", true, cross.has("4,3"))
	check("stone: the other arms are unaffected", true,
		cross.has("0,3") and cross.has("3,0") and cross.has("3,6"))

	# A crate is lit AND eats the rest of that arm.
	var g2 := _bare()
	g2.tiles[g2.index(Vector2i(5, 3))] = Grid.Tile.CRATE
	var c2 := _cells(g2.blast_cells(Vector2i(3, 3), 3))
	check("crate: the crate's tile IS lit", true, c2.has("5,3"))
	check("crate: it stops the arm dead", false, c2.has("6,3"))

	# …and it is destroyed, exactly once, credited to the keg's owner.
	var g3 := _bare()
	g3.tiles[g3.index(Vector2i(5, 3))] = Grid.Tile.CRATE
	g3.tiles[g3.index(Vector2i(3, 5))] = Grid.Tile.CRATE
	g3.kings[0].cell = Vector2i(3, 3)
	g3.kings[0].radius = 3
	g3.kings[1].cell = Vector2i(0, 0)
	check("crate: two crates standing", 2, g3.crates_left())
	g3.place_keg(0)
	var burned := 0
	var t := 0.0
	while t < 8.0:
		for e in g3.drain_events():
			if e["kind"] == "crate_burned":
				burned += 1
		g3.tick(DT)
		t += DT
		if g3.kegs.is_empty() and g3.arms.is_empty():
			break
	for e in g3.drain_events():
		if e["kind"] == "crate_burned":
			burned += 1
	check("crate: both burned", 2, burned)
	check("crate: none left standing", 0, g3.crates_left())
	check("crate: the tile is walkable afterwards", true,
		g3.tile_at(Vector2i(5, 3)) == Grid.Tile.EMPTY)
	check("crate: credited to the king who lit the jar", 2,
		g3.kings[0].crates_burned)
	check("crate: and not to the other one", 0, g3.kings[1].crates_burned)


func _test_chain() -> void:
	# A at (2,2) radius 3 reaches B at (5,2); B blasts from ITS OWN tile.
	var g := _bare()
	g.kings[0].cell = Vector2i(2, 2)
	g.kings[0].radius = 3
	g.kings[0].kegs_max = 2
	g.kings[1].cell = Vector2i(5, 2)
	g.kings[1].radius = 2
	check("chain: jar A set", true, g.place_keg(0))
	check("chain: jar B set", true, g.place_keg(1))
	# B's fuse is long; only A's blast can reach it in time.
	g.kegs[1].fuse = 60.0
	var hit := _burned(g, 10.0)
	check("chain: A's own cross burned", true, hit.has("2,2") and hit.has("2,0"))
	check("chain: the arm reached B", true, hit.has("5,2"))
	check("chain: B chained and burned with ITS radius", true,
		hit.has("7,2") and hit.has("5,0") and hit.has("5,4"))
	check("chain: both jars are gone", 0, g.kegs.size())
	check("chain: each king's jar is back on his belt", "0/0",
		"%d/%d" % [g.kings[0].kegs_live, g.kings[1].kegs_live])

	# An arm STOPS at the keg it lights — it does not run on past it.
	var g2 := _bare()
	g2.kings[0].cell = Vector2i(0, 2)
	g2.kings[0].radius = 6
	g2.kings[0].kegs_max = 2
	g2.kings[1].cell = Vector2i(2, 2)
	g2.kings[1].radius = 1
	g2.place_keg(0)
	g2.place_keg(1)
	g2.kegs[1].fuse = 60.0
	var h2 := _burned(g2, 10.0)
	check("chain: the arm dies at the jar it lights", false, h2.has("5,2"))
	check("chain: the chained jar's own small cross is all that follows", true,
		h2.has("3,2") and h2.has("2,1"))


func _test_timing() -> void:
	# The blast WALKS: one tile per ring_step. The far tile of an arm must
	# light strictly later than the near one.
	var g := _bare({"ring_step": 0.05, "flame_life": 2.0})
	g.kings[0].cell = Vector2i(1, 3)
	g.kings[0].radius = 4
	g.kings[1].cell = Vector2i(7, 7)
	g.place_keg(0)
	var lit_at := {}
	var t := 0.0
	while t < 3.0:
		g.tick(DT)
		t += DT
		for e in g.drain_events():
			if e["kind"] == "flame" and not lit_at.has(e["cell"]):
				lit_at[e["cell"]] = t
		if g.arms.is_empty() and g.kegs.is_empty():
			break
	var near: float = lit_at.get(Vector2i(2, 3), -1.0)
	var far: float = lit_at.get(Vector2i(5, 3), -1.0)
	check("timing: the near tile lit", true, near > 0.0)
	check("timing: the far tile lit", true, far > 0.0)
	check("timing: the fire WALKS outward (far lights after near)", true,
		far > near)
	check("timing: roughly one tile per ring_step", true,
		far - near > 0.1 and far - near < 0.25)


# ── boons ───────────────────────────────────────────────────────────────────


func _test_boons() -> void:
	# The crate at (2,3) hides a draught. The blast comes from (3,3) — the
	# king watches from (0,3), well outside a radius-1 cross, because a king
	# standing on his own jar is a king who does not collect anything.
	var g := _bare({"flame_life": 0.2})
	var cell := Vector2i(2, 3)
	g.tiles[g.index(cell)] = Grid.Tile.CRATE
	g._drops[g.index(cell)] = Grid.Boon.DRAUGHT
	g.kings[0].cell = Vector2i(0, 3)
	g.kings[1].cell = Vector2i(7, 7)
	g.kings[0].radius = 1
	check("boon: hidden inside the crate, not on the floor", Grid.Boon.NONE,
		g.boons[g.index(cell)])
	g.detonate_at(Vector2i(3, 3))
	_settle(g, 8.0)
	check("boon: the crate burned", Grid.Tile.EMPTY, g.tile_at(cell))
	check("boon: it surfaces once the fire on that tile dies",
		Grid.Boon.DRAUGHT, g.boons[g.index(cell)])

	# …and applies when a king walks onto it.
	check("boon: king starts at reach 1", 1, g.kings[0].radius)
	check("boon: he is alive to collect it", true, g.kings[0].alive)
	check("boon: first step", true, _walk(g, 0, Vector2i(1, 0)))
	check("boon: nothing yet at (1,3)", 1, g.kings[0].radius)
	check("boon: second step onto the boon", true, _walk(g, 0, Vector2i(1, 0)))
	check("boon: the draught lengthens the reach", 2, g.kings[0].radius)
	check("boon: it is consumed", Grid.Boon.NONE, g.boons[g.index(cell)])
	check("boon: counted", 1, g.kings[0].boons_taken)

	# each kind does its own thing, and each is capped
	var g2 := _bare({"max_radius": 3, "max_kegs": 2, "max_speed": 1.3,
		"speed_step": 0.2})
	var k = g2.kings[0]
	k.cell = Vector2i(2, 2)
	g2.kings[1].cell = Vector2i(7, 7)
	g2.boons[g2.index(Vector2i(3, 2))] = Grid.Boon.CACHE
	check("boon: king carries one jar", 1, k.kegs_max)
	g2.request_step(0, Vector2i(1, 0))
	check("boon: the cache adds a jar", 2, k.kegs_max)
	g2.boons[g2.index(Vector2i(4, 2))] = Grid.Boon.SPURS
	k.busy = 0.0
	g2.request_step(0, Vector2i(1, 0))
	check("boon: the spurs add speed", true, k.speed > 1.0)
	# caps hold
	for _i in 8:
		var next: Vector2i = k.cell + Vector2i(0, 1)
		if not g2.in_bounds(next):
			break
		k.busy = 0.0
		g2.boons[g2.index(next)] = Grid.Boon.DRAUGHT
		if not g2.request_step(0, Vector2i(0, 1)):
			break
	check("boon: the reach is capped", true, k.radius <= 3)
	check("boon: the jar count is capped", true, k.kegs_max <= 2)
	check("boon: the speed is capped", true, k.speed <= 1.3)

	# a boon lying in a fresh blast is destroyed
	var g3 := _bare()
	g3.boons[g3.index(Vector2i(5, 3))] = Grid.Boon.CACHE
	g3.kings[0].cell = Vector2i(3, 3)
	g3.kings[0].radius = 3
	g3.kings[1].cell = Vector2i(0, 0)
	g3.place_keg(0)
	_settle(g3)
	check("boon: fire consumes a boon left on the floor", Grid.Boon.NONE,
		g3.boons[g3.index(Vector2i(5, 3))])


# ── the two kings must be able to REACH each other ──────────────────────────
#
# THE BUG THIS SUITE MISSED FOR A WHOLE FEATURE. `lattice_is_symmetric` proved
# the arena was FAIR and nothing proved it was CONNECTED, and the mirrored
# lattice is a wall: rows 3 and 4 come out as complementary combs
# (`.#.#.#.#` over `#.#.#.#.`), so nothing 4-connected crosses the middle and
# the two kings started life in sealed halves — in every arena the mode ever
# built. A tie-breaker where the rival cannot be killed is not a tie-breaker.
#
# THE GATE IS TWO-SIDED ON PURPOSE. This project has twice shipped a check that
# could only ever pass, so every assertion below that says "connected" is paired
# with a hand-built board the SAME function must call sealed. If the flood fill
# were stubbed to `return true` tomorrow, five of these would fail.


func _test_connectivity() -> void:
	# ── the shipped arena, and the wall that was in it ──────────────────────
	var g: Grid = Grid.new()
	g.setup({"crates": [], "seed": 4242})
	check("reach: the repair opened four cells", 4, g.carved.size())
	check("reach: every carve is answered by its antipode", true,
		_mirrored(g.carved))
	check("reach: the lattice is STILL symmetric after the carve", true,
		g.lattice_is_symmetric())
	check("reach: the two kings can meet", true, g.kings_connected())
	check("reach: and it is ONE arena, not the biggest half",
		g.open_cells(), g.reachable_from(g.kings[0].cell).size())
	# No crates on this board, so "reachable" and "walkable right now" are the
	# same question — the corridor is a corridor, not a promise.
	check("reach: a king can WALK it without digging", true,
		g.kings_connected(false))

	# NEGATIVE CONTROL 1 — THE REAL BOARD, RE-SEALED. Put the four carved cells
	# back and the arena is the one the mode actually shipped. This is the only
	# control taken from live data rather than built by hand, and it is the one
	# that says the bug was real.
	var sealed: Grid = Grid.new()
	sealed.setup({"crates": [], "seed": 4242})
	for c in sealed.carved:
		sealed.tiles[sealed.index(c)] = Grid.Tile.STONE
	check("reach: NEGATIVE — the un-carved lattice seals the board", false,
		sealed.kings_connected())
	check("reach: NEGATIVE — …into two halves of exactly the same size", true,
		sealed.reachable_from(sealed.kings[0].cell).size() * 2
			== sealed.open_cells())
	check("reach: NEGATIVE — the closing ring cannot save it", false,
		sealed.ring_keeps_one_arena())

	# NEGATIVE CONTROL 2 — A HAND-BUILT BLACKSTONE CUT. The anti-diagonal is the
	# one wall that is its own mirror image, so it separates the two corners
	# while leaving the fairness invariant intact: the check cannot pass this by
	# accidentally measuring symmetry instead of connection.
	var wall := _bare()
	for x in Grid.SIZE:
		wall.tiles[wall.index(Vector2i(x, Grid.SIZE - 1 - x))] = Grid.Tile.STONE
	check("reach: NEGATIVE — a stone wall is symmetric", true,
		wall.lattice_is_symmetric())
	check("reach: NEGATIVE — …and the kings cannot meet across it", false,
		wall.kings_connected())
	check("reach: NEGATIVE — each king has exactly his own half", 28,
		wall.reachable_from(wall.kings[0].cell).size())
	check("reach: NEGATIVE — the ring cannot save it either", false,
		wall.ring_keeps_one_arena())
	# THE MINIMUM, read before anything is cut: one stone opens this wall, so a
	# repair that carves a trench through it is carving more than it must.
	check("reach: the cheapest breach is ONE stone", 1,
		wall.stone_cut_between_kings().size())
	var opened := wall.ensure_kings_connected()
	check("reach: …so the duel route costs its mirrored PAIR, and the three "
		+ "shrinking arenas one more each", 4, opened.size())
	check("reach: …in mirrored pairs", true, _mirrored(opened))
	check("reach: …the kings can now meet", true, wall.kings_connected())
	check("reach: …and so can every arena the ring leaves", true,
		wall.ring_keeps_one_arena())
	check("reach: …and the wall is still fair", true,
		wall.lattice_is_symmetric())

	# NEGATIVE CONTROL 3 — THE SAME WALL MADE OF BANNERMEN. A crate is a door:
	# the shipping gate must call this arena connected and the stricter
	# walk-it-now question must call it blocked. One board, two answers — which
	# is the proof that the `through_crates` flag is doing work and not sitting
	# there as decoration.
	var door := _bare()
	for x in Grid.SIZE:
		door.tiles[door.index(Vector2i(x, Grid.SIZE - 1 - x))] = Grid.Tile.CRATE
	check("reach: NEGATIVE — a wall of crates is not a seal", true,
		door.kings_connected())
	check("reach: NEGATIVE — …but he cannot walk it until he burns it", false,
		door.kings_connected(false))

	# ── every arena this mode can generate ─────────────────────────────────
	# The same crate fields the AI matches are played on, plus the pathological
	# ones: a board with no survivors at all, and a board where every square was
	# offered as a crate.
	var joined := 0
	var ring_safe := 0
	var built := 0
	var seeds := [1, 5, 11, 42, 404, 1234, 20260809, 90210]
	for s in seeds:
		for field in [_crate_field(s), [], _every_square()]:
			var a: Grid = Grid.new()
			a.setup({"crates": field, "seed": s})
			built += 1
			if a.kings_connected():
				joined += 1
			if a.ring_keeps_one_arena():
				ring_safe += 1
	check("reach: every generated arena joins the two kings", built, joined)
	# THE RING MUST COMPRESS THEM TOGETHER, NEVER WALL THEM APART. The comb
	# repeats inside the square the wyrm leaves behind ([2..5] is `.#.#` over
	# `#.#.`), so opening the outer seam alone would let the closing ring split
	# the arena again with twenty squares still in play.
	check("reach: …and every arena the closing ring leaves behind", built,
		ring_safe)
	check("reach: 24 arenas were built to ask", 24, built)


## True when the antipode of every cell in the list is also in the list.
func _mirrored(cells: Array) -> bool:
	var have := {}
	for c in cells:
		have[str(c)] = true
	for c in cells:
		if not have.has(str(Vector2i(Grid.SIZE - 1 - c.x, Grid.SIZE - 1 - c.y))):
			return false
	return true


func _every_square() -> Array:
	var out: Array = []
	for y in Grid.SIZE:
		for x in Grid.SIZE:
			out.append(Vector2i(x, y))
	return out


# ── THE OUTCOME, NOT THE TOPOLOGY ───────────────────────────────────────────
#
# A FLOOD FILL IS NOT A DUEL, and the checks above would all have gone green on
# an arena nobody can actually fight in. Reachability is a claim about the maze;
# this is a claim about the game: ONE KING STANDS AT HIS CORNER AND DOES NOTHING
# AT ALL, the other is a brain, and the wyrm is switched off so the only thing on
# the board that can kill the idle man is the other man's fire.
#
# The number this replaced was worth having and was still too weak: two rival
# kills across 27 AI-vs-AI matches asserted at "more than nothing". This asks the
# question directly, and its negative control is the arena as it actually
# shipped — put the four carved cells back and the hunter cannot land a single
# kill in ten full duels, because he cannot get there.


func _test_duel_outcome() -> void:
	var joined := 0
	var sealed := 0
	var played := 0
	var kill_times: Array[float] = []
	for s in range(1, 11):
		played += 1
		var open_arena := _hunt(s, AI.Difficulty.MASTER, false)
		if open_arena["killed"]:
			joined += 1
			kill_times.append(float(open_arena["t"]))
		if _hunt(s, AI.Difficulty.MASTER, true)["killed"]:
			sealed += 1
	kill_times.sort()
	var median := 0.0 if kill_times.is_empty() \
		else kill_times[kill_times.size() / 2]
	check("duel: ten idle-king hunts were played", 10, played)
	# Measured 18/20 at Master over twenty seeds; asserted at six so a tuning
	# pass costs a re-measure and not a red suite, and never at "> 0", which is
	# the threshold a broken arena can still clear by luck.
	check("duel: the rival's fire reaches an idle king (%d/10, median %.0f s)"
		% [joined, median], true, joined >= 6)
	# THE NEGATIVE CONTROL, ON THE ARENA THAT SHIPPED. Not a hand-built board —
	# the real one, with the four carved gates filled back in.
	check("duel: NEGATIVE — with the comb wall standing he NEVER reaches him",
		0, sealed)


## One hunt. Side 0 stands at his corner and never moves or throws; side 1 is a
## brain; the wyrm's patience is set past any horizon so it cannot do the
## killing. `reseal` fills the four carved gates back in — the arena as it was
## before this fix, and the only control that proves the fix is what changed it.
func _hunt(seed_value: int, tier: int, reseal: bool) -> Dictionary:
	var g: Grid = Grid.new()
	g.setup({"seed": seed_value, "crates": _crate_field(seed_value),
		"sudden_death_at": 100000.0, "fuse_sec": 1.6})
	if reseal:
		for c in g.carved:
			g.tiles[g.index(c)] = Grid.Tile.STONE
	var brain := AI.new(tier, seed_value + 2)
	var ticks := 0
	while ticks < 9000 and not g.is_over():
		var act: Dictionary = brain.decide(g, 1, DT)
		if act.has("keg"):
			g.place_keg(1)
		elif act.has("step"):
			g.request_step(1, act["step"])
		g.tick(DT)
		g.drain_events()
		ticks += 1
	var idle = g.kings[0]
	return {"killed": (not idle.alive) and idle.killed_by == 1, "t": g.time}


# ── the wyrm's ring ─────────────────────────────────────────────────────────


func _test_ring() -> void:
	var g: Grid = Grid.new()
	g.setup({"sudden_death_at": 1.0, "ring_interval": 0.05, "seed": 9,
		"crates": [Vector2i(4, 4), Vector2i(2, 4)]})
	check("ring: not closing yet", false, g.sudden)
	var saw_sudden := false
	var torched := 0
	var t := 0.0
	while t < 1.5:
		g.tick(DT)
		t += DT
		for e in g.drain_events():
			if e["kind"] == "sudden_death":
				saw_sudden = true
			elif e["kind"] == "torched":
				torched += 1
	check("ring: the wyrm loses patience on schedule", true, saw_sudden)
	check("ring: and starts eating the arena", true, g.sudden)
	check("ring: the outer corner went first", Grid.Tile.STONE,
		g.tile_at(Vector2i(0, 0)))
	check("ring: the middle is still open", true,
		g.tile_at(Vector2i(3, 4)) != Grid.Tile.STONE)

	# Run it out: the spiral covers all 64 tiles and entombs everything.
	while t < 12.0:
		g.tick(DT)
		t += DT
		for e in g.drain_events():
			if e["kind"] == "torched":
				torched += 1
	var stone := 0
	for i in Grid.CELLS:
		if g.tiles[i] == Grid.Tile.STONE:
			stone += 1
	check("ring: every square is eventually taken", Grid.CELLS, stone)
	check("ring: one torch event per square", Grid.CELLS, torched)
	check("ring: no crate survives it", 0, g.crates_left())
	check("ring: THE TRIAL ALWAYS ENDS — nobody can wait it out", true,
		g.is_over())
	check("ring: …and it named a winner", true, g.winner() in [0, 1])

	# A king standing where the ring lands dies to it.
	var g2: Grid = Grid.new()
	g2.setup({"sudden_death_at": 0.05, "ring_interval": 0.02, "seed": 3})
	g2.kings[0].cell = Vector2i(0, 0)
	g2.kings[1].cell = Vector2i(4, 4)
	for _n in 30:
		g2.tick(DT)
	check("ring: the wyrm burns the king it reaches", false, g2.kings[0].alive)
	check("ring: the one in the middle is still standing", true,
		g2.kings[1].alive)
	check("ring: the survivor takes the trial", 1, g2.winner())

	# A keg caught by the ring COOKS OFF rather than being swallowed.
	var g3: Grid = Grid.new()
	g3.setup({"sudden_death_at": 0.05, "ring_interval": 0.02, "seed": 3})
	g3.kings[0].cell = Vector2i(1, 0)
	g3.kings[1].cell = Vector2i(4, 4)
	g3.place_keg(0)
	var cooked := false
	for _n in 40:
		g3.tick(DT)
		for e in g3.drain_events():
			if e["kind"] == "detonate":
				cooked = true
	check("ring: the wyrm lights a jar it reaches", true, cooked)


# ── death and the verdict ───────────────────────────────────────────────────


func _test_death() -> void:
	# THE WHOLE GENRE IN ONE TEST: set the jar down, RUN, and let it catch the
	# other man. King 0 needs two steps to leave a radius-2 cross (the arms are
	# straight, so the escape is a diagonal), and the fuse is long enough to
	# make them — which is what the fuse length is FOR.
	var g := _bare()
	g.kings[0].cell = Vector2i(3, 3)
	g.kings[0].radius = 2
	g.kings[1].cell = Vector2i(5, 3)
	check("death: both kings standing", true, not g.is_over())
	check("death: ONGOING while both live", Grid.ONGOING, g.winner())
	check("death: the jar goes down", true, g.place_keg(0))
	check("death: he steps clear (1/2)", true, _walk(g, 0, Vector2i(0, -1)))
	check("death: he steps clear (2/2)", true, _walk(g, 0, Vector2i(-1, 0)))
	check("death: and is out of his own cross", Vector2i(2, 2), g.kings[0].cell)
	var died_side := -99
	var t := 0.0
	while t < 6.0:
		g.tick(DT)
		t += DT
		for e in g.drain_events():
			if e["kind"] == "king_died":
				died_side = e["side"]
		if g.is_over():
			break
	check("death: the king in the cross falls", 1, died_side)
	check("death: the one who ran does not", true, g.kings[0].alive)
	check("death: the trial is over", true, g.is_over())
	check("death: last king standing wins", 0, g.winner())
	check("death: the kill is attributed", 0, g.kings[1].killed_by)

	# A king may be CAUGHT by fire but never WALK into it.
	var g2 := _bare({"flame_life": 1.5})
	g2.kings[0].cell = Vector2i(0, 3)
	g2.kings[0].radius = 1
	g2.kings[1].cell = Vector2i(7, 7)
	g2.tiles[g2.index(Vector2i(2, 3))] = Grid.Tile.EMPTY
	g2.detonate_at(Vector2i(2, 3))
	g2.tick(DT)
	check("death: the tile is burning", true, g2.flame[g2.index(Vector2i(2, 3))] > 0.0)
	g2.kings[0].cell = Vector2i(1, 3)
	g2.kings[0].busy = 0.0
	check("death: a king refuses to walk into fire", false,
		g2.request_step(0, Vector2i(1, 0)))
	check("death: …and is still alive for refusing", true, g2.kings[0].alive)

	# A king mid-step is judged on the tile he committed to.
	var g3 := _bare({"flame_life": 1.0, "step_sec": 0.5})
	g3.kings[0].cell = Vector2i(2, 2)
	g3.kings[1].cell = Vector2i(7, 7)
	g3.request_step(0, Vector2i(1, 0))
	check("death: he is committed to the far tile", Vector2i(3, 2),
		g3.kings[0].cell)
	check("death: and still mid-stride", true, g3.kings[0].busy > 0.0)
	g3.detonate_at(Vector2i(3, 2))
	g3.tick(DT)
	check("death: fire on the committed tile kills him", false, g3.kings[0].alive)

	# Double knockout still names a champion — the whole reason this mode
	# exists is that a tournament cannot accept "nobody".
	# Both kings one tile from the origin, on OPPOSITE arms: the two arms
	# advance in the same tick, so the two deaths carry the same timestamp and
	# the "who stood longest" tiebreak genuinely cannot separate them.
	var g4 := _bare({"start_radius": 2})
	g4.kings[0].cell = Vector2i(2, 3)
	g4.kings[1].cell = Vector2i(4, 3)
	g4.kings[0].crates_burned = 4
	g4.kings[1].crates_burned = 1
	g4.detonate_at(Vector2i(3, 3))
	_settle(g4, 6.0)
	check("verdict: they fell on the same tick", true,
		is_equal_approx(g4.kings[0].died_at, g4.kings[1].died_at))
	check("verdict: both kings fell together", true,
		not g4.kings[0].alive and not g4.kings[1].alive)
	check("verdict: it is STILL decided, never a draw", true,
		g4.winner() in [0, 1])
	check("verdict: the tiebreak reads the chronicle", 0, g4.winner())

	# An "over" event is emitted exactly once.
	var g5 := _bare()
	g5.kings[0].cell = Vector2i(3, 3)
	g5.kings[0].radius = 2
	g5.kings[1].cell = Vector2i(5, 3)
	g5.place_keg(0)
	var overs := 0
	for _n in 400:
		g5.tick(DT)
		for e in g5.drain_events():
			if e["kind"] == "over":
				overs += 1
	check("verdict: the over event fires exactly once", 1, overs)


# ── AI vs AI ────────────────────────────────────────────────────────────────


func _test_ai_matches() -> void:
	## THE TERMINATION GUARANTEE, exercised rather than argued. Every tier
	## pairing, several seeds: the match must end, inside a bounded budget,
	## with a named winner. The wyrm's spiral is what makes this provable —
	## two cowards are entombed on a schedule — but a claim like that is
	## worth exactly as much as the run that demonstrates it.
	var tiers := [AI.Difficulty.CASUAL, AI.Difficulty.SEASONED, AI.Difficulty.MASTER]
	var names := {AI.Difficulty.CASUAL: "Casual",
		AI.Difficulty.SEASONED: "Seasoned", AI.Difficulty.MASTER: "Master"}
	var worst_ticks := 0
	var kegs_seen := 0
	var crates_seen := 0
	var split_ticks := 0
	var rival_kills := 0
	var all_ended := true
	var all_named := true
	var matches := 0
	for a in tiers:
		for b in tiers:
			for seed_value in [11, 404, 90210]:
				var out := _run_ai_match(a, b, seed_value, true)
				matches += 1
				worst_ticks = maxi(worst_ticks, int(out["ticks"]))
				kegs_seen += int(out["kegs"])
				crates_seen += int(out["crates"])
				split_ticks += int(out["split_ticks"])
				rival_kills += int(out["rival_kills"])
				if not out["over"]:
					all_ended = false
					check("ai: %s vs %s seed %d ENDED" % [names[a], names[b],
						seed_value], true, false)
				if not (out["winner"] in [0, 1]):
					all_named = false
	# THE FAIRNESS INVARIANT. A tie-breaker with a lopsided spawn is worse than
	# no tie-breaker: it looks like a game and decides like a coin someone else
	# flipped. The arena's blackstone must be unchanged by the half-turn that
	# swaps the two corners — see BlastGrid.setup for the 65/35 this prevents.
	var fair: Grid = Grid.new()
	fair.setup({"crates": _crate_field(5), "seed": 5})
	check("ai: the arena is symmetric under the corner-swapping half-turn",
		true, fair.lattice_is_symmetric())
	check("ai: every pairing x seed ran", 27, matches)
	check("ai: every match TERMINATED", true, all_ended)
	check("ai: every match named a winner", true, all_named)
	check("ai: inside the tick budget", true, worst_ticks < 9000)
	check("ai: the kings actually fought (jars were lit)", true, kegs_seen > 40)
	check("ai: …and actually broke the field open", true, crates_seen > 40)

	# THE INVARIANT UNDER THE CLOSING RING, MEASURED IN A REAL MATCH rather than
	# argued from the layout: 27 full duels, every tick, while both kings live.
	# The only ticks that may see a split are the last two squares on the board,
	# where the wyrm has already taken 62 of 64 and there is no duel left to
	# have — measured at open<=2 across every match here.
	check("ai: the ring never walls two living kings apart", 0, split_ticks)
	# AND THE POINT OF THE WHOLE FIX. With the comb wall standing this number
	# was ZERO across every pairing and seed — a king could not be killed by the
	# other man's fire because he could not be reached. Measured at 2 with the
	# arena joined; asserted at "it happens at all", because "at all" is exactly
	# what was impossible.
	check("ai: a king CAN fall to the rival's fire (%d times)" % rival_kills,
		true, rival_kills > 0)

	# The tiers must be DIFFERENT, or "difficulty" is a label on nothing.
	# A Master hunting a Casual should win the clear majority of the time.
	var master_wins := 0
	var played := 0
	for seed_value in range(1, 25):
		var out := _run_ai_match(AI.Difficulty.CASUAL, AI.Difficulty.MASTER,
			seed_value * 37)
		played += 1
		if out["winner"] == 1:
			master_wins += 1
	check("ai: 24 Casual-vs-Master trials played", 24, played)
	check("ai: Master beats Casual more often than not (%d/24)" % master_wins,
		true, master_wins > 12)

	# DIAGNOSTIC, not an assertion — the shape of the ladder, printed so the
	# numbers in any report about this mode came off a run and not off a hunch.
	print("")
	print("  tier ladder (row = side 0, col = side 1; cell = side-1 win rate over 12 seeds)")
	for a in tiers:
		var line := "    %-9s" % names[a]
		for b in tiers:
			var wins := 0
			for s in range(12):
				if _run_ai_match(a, b, 1000 + s * 131)["winner"] == 1:
					wins += 1
			line += "  %-9s" % ("%d/12" % wins)
		print(line)
	print("")


## One full AI-vs-AI trial, fixed dt, no rendering. Returns a small report.
##
## `watch` turns on the per-tick connectivity audit. It is off by default and on
## only for the 27 headline matches: a flood fill on every tick of all 159
## matches this file plays (the ladder diagnostic included) is a second and a
## half of nothing, and the property is the same in all of them.
func _run_ai_match(tier_a: int, tier_b: int, seed_value: int,
		watch := false) -> Dictionary:
	var g: Grid = Grid.new()
	g.setup({
		"seed": seed_value,
		"crates": _crate_field(seed_value),
		"sudden_death_at": 20.0,
		"ring_interval": 0.28,
		"fuse_sec": 1.6,
	})
	var brains := [AI.new(tier_a, seed_value + 1), AI.new(tier_b, seed_value + 2)]
	var kegs := 0
	var crates := 0
	var ticks := 0
	var split_ticks := 0
	# Budget: sudden death (20 s) + the whole 64-cell spiral (64 x 0.28 = 18 s)
	# + slack, in 60 Hz ticks. Anything past this is a hang, not a long game.
	var cap := int((20.0 + 64.0 * 0.28 + 6.0) / DT)
	while ticks < cap and not g.is_over():
		# ALTERNATE WHO ACTS FIRST. Both kings are polled inside one tick, so a
		# fixed order hands side 0 a half-tick head start on every race for the
		# same tile — worth 9-3 in a Casual mirror before this line existed, on
		# a mode whose entire job is to break a tie FAIRLY.
		for n in 2:
			var side: int = n if ticks % 2 == 0 else 1 - n
			var act: Dictionary = brains[side].decide(g, side, DT)
			if act.has("keg"):
				g.place_keg(side)
			elif act.has("step"):
				g.request_step(side, act["step"])
		g.tick(DT)
		ticks += 1
		for e in g.drain_events():
			if e["kind"] == "keg_placed":
				kegs += 1
			elif e["kind"] == "crate_burned":
				crates += 1
		if watch and g.kings[0].alive and g.kings[1].alive \
				and g.open_cells() > 2 and not g.kings_connected():
			split_ticks += 1
	var rival_kills := 0
	for k in g.kings:
		# `killed_by` is the side whose jar did it, which INCLUDES your own —
		# and a king blowing himself up is not the other man reaching him.
		if not k.alive and k.killed_by >= 0 and k.killed_by != k.side:
			rival_kills += 1
	return {"over": g.is_over(), "winner": g.winner(), "ticks": ticks,
		"kegs": kegs, "crates": crates, "split_ticks": split_ticks,
		"rival_kills": rival_kills}


## A reproducible field of survivors — roughly what a drawn game leaves behind,
## thick enough that the kings have to dig toward each other.
func _crate_field(seed_value: int) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var out: Array = []
	# Every square is offered; setup() rejects the ones that are blackstone or
	# spawn pocket. THE EARLIER VERSION SKIPPED odd/odd CELLS ITSELF, which was
	# the old lattice's shape and not the mirrored one — it left eight squares
	# that could never hold a crate, ALL OF THEM IN ONE KING'S HALF, and handed
	# that king 80 % of the mirror matches. The arena's shape is the arena's
	# business; a fixture that second-guesses it measures the fixture.
	for y in Grid.SIZE:
		for x in Grid.SIZE:
			if r.randf() < 0.42:
				out.append(Vector2i(x, y))
	return out


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
	quit(1 if failures > 0 else 0)
