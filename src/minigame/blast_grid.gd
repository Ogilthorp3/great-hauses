extends RefCounted
## TRIAL BY FIRE — the rules engine, and nothing else.
##
## WHY THIS EXISTS AT ALL. A knockout tournament needs a winner, and until now
## the answer to a stalemate was that the player was quietly eliminated by
## arithmetic. So the two kings settle it themselves: the board they just drew
## on becomes an arena, the survivors become the things that burn, and the last
## king standing takes the tie. It is the better game AND the better rule.
##
## THIS FILE IS PURE. No Node, no mesh, no autoload, no tree — a RefCounted
## state machine ticked with a float. That is deliberate and it is the whole
## testability story: tests/test_minigame.gd runs thousands of ticks of it,
## including complete AI-vs-AI matches, in a headless `-s` script with no
## rendering server and no PieceAssets. Everything you can SEE is in the view
## layer (trial_by_fire.gd) and reads this module's EVENT QUEUE; the view can
## never disagree with the rules because it is not allowed to hold any.
##
## THE GRID IS THE BOARD. 8x8, same indices BoardView uses (sq.x 0..7, sq.y
## 0..7), so `board.square_to_world(cell)` is the only coordinate maths the view
## ever does. Nothing here invents a coordinate system.
##
## THE PIECES ARE THE CRATES. Every survivor of the drawn game stands on its
## square as a destructible block — including your own men, which is the choice
## that makes the arena interesting: the wall between you and the rival king is
## made of your own bannermen and you have to decide whether to burn them.
##
## THE STONE IS THE LATTICE. Indestructible blackstone plinths on every
## odd/odd square — the classic Bomberman lattice, which is what turns an open
## field into corridors and makes a cross-shaped blast a tactical shape instead
## of a circle with corners.
##
## THE DRAGON IS THE CLOCK. Past `sudden_death_at` the wyrm starts torching the
## outer ring inward along a spiral, one cell per `ring_interval`: crates burn,
## kegs cook off, and the cell becomes stone. It shrinks the arena, it makes
## camping fatal, and — the part that matters for a tournament — it is a HARD
## TERMINATION PROOF: the spiral is 64 cells long and covers every square, so
## two kings who refuse to fight are entombed by a schedule. `winner()` can
## always be asked, and after `is_over()` it never answers "nobody".
##
## TIMING MODEL (all seconds, all wall-independent — the caller owns dt):
##   * a keg's fuse burns for `fuse_sec`
##   * the blast leaves the keg's tile INSTANTLY and then walks outward ONE
##     TILE PER `ring_step` — you can watch it race down a corridor, and an arm
##     that meets a keg lights its fuse to zero (the chain) and stops there
##   * a lit tile burns for `flame_life`
##   * a king commits to a whole tile per step and is `busy` for
##     `step_sec / speed` — death is evaluated on the tile he is COMMITTED to,
##     never on the two he is between. That is a real rule, not an
##     approximation: it means a tight escape is possible (step_sec 0.21 <
##     flame_life 0.62), which is where all the drama in this genre lives.

enum Tile { EMPTY, CRATE, STONE }

## THE BOONS the fallen leave behind. Haus-flavoured, because they come off
## haus bannermen: the Ashwyrm draught makes the fire reach further, the
## alchemist's cache lets a king carry another jar, and the Swiftcrest spurs
## are the falcon haus's tread.
enum Boon { NONE, DRAUGHT, CACHE, SPURS }

const BOON_NAMES := {
	Boon.NONE: "",
	Boon.DRAUGHT: "Ashwyrm Draught",   # the wildfire reaches one tile further
	Boon.CACHE: "Alchemist's Cache",   # one more jar on the belt
	Boon.SPURS: "Swiftcrest Spurs",    # the falcon haus's tread
}

const SIZE := 8
const CELLS := SIZE * SIZE
const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## Winner sentinels.
const ONGOING := -1

# ── tuning (every one of these is overridable through setup(), which is how
# the test suite compresses a 90-second trial into 400 ticks) ───────────────
var ring_step := 0.045        ## seconds the blast takes to walk one tile
var flame_life := 0.62        ## how long a lit tile burns
var fuse_sec := 2.35          ## a keg's fuse
var step_sec := 0.21          ## a king's grid step at speed 1.0
## WHEN THE WYRM LOSES PATIENCE — 45 s, and the number was measured, not felt.
##
## It used to be 75 (70 in the arena scene), and it was chosen against a mode in
## which the two kings COULD NOT REACH EACH OTHER: nothing was ever decided by
## the kings, so the clock had to run long enough to entomb them both and the
## typical duel ended at ~88 s in a double knockout resolved by a bookkeeping
## tiebreak. With the arena joined, 108 AI duels with the wyrm switched off are
## decided by the kings at p25 16 s / MEDIAN 28 s / p75 41 s — and a 70 s clock
## would then wake the dragon in 11 % of duels, which makes the best beat in the
## mode dead content.
##
## 45 s sits just past the third quartile ON PURPOSE. THE WYRM IS THE
## ANTI-CAMPING CLOCK, not a co-star: three duels in four are already settled by
## then and are not interrupted, and the long quarter — the cagey ones, the ones
## that stall, the ones this clock exists for — become dragon fights (~23 %).
## The dragon is not rare in the mode either way: it STIRS in the transmutation
## at the top of every single trial (see trial_by_fire.gd), so a player always
## learns what the clock is; 45 s is when it stops watching.
var sudden_death_at := 45.0
var ring_interval := 0.55     ## …and how fast it eats the arena after that
var start_radius := 1
var start_kegs := 1
var max_radius := 5
var max_kegs := 6
var speed_step := 0.16        ## each pair of spurs adds this much speed
var max_speed := 1.8
var drop_chance := 0.46       ## fraction of crates hiding a boon

# ── state ───────────────────────────────────────────────────────────────────
var tiles := PackedInt32Array()
var boons := PackedInt32Array()     ## Boon lying on the stone, walkable
var flame := PackedFloat32Array()   ## seconds of fire left on each tile
var kegs: Array = []
var arms: Array = []                ## the blast's four fingers, mid-walk
var kings: Array = []
var events: Array = []              ## drained by the view every frame
var time := 0.0
var sudden := false
var rng := RandomNumberGenerator.new()

## THE BLACKSTONE `setup()` HAD TO OPEN so the two kings could meet. Empty on
## every arena the lattice builds on its own — which is exactly what makes it
## evidence: a non-empty list is the arena admitting it generated a wall.
var carved: Array[Vector2i] = []

var _drops := {}          ## cell index -> Boon hidden inside that crate
var _pending := {}        ## cell index -> Boon revealed, waiting for the fire to die
var _spiral: Array = []       ## 32 antipodal PAIRS — see _spiral_order()
var _spiral_i := 0
var _ring_t := 0.0
var _over_announced := false


class King:
	extends RefCounted
	var side := 0
	var cell := Vector2i.ZERO
	var from := Vector2i.ZERO   ## the tile he stepped off (the view lerps this)
	var facing := Vector2i(0, 1)
	var busy := 0.0             ## seconds left in the current step
	var alive := true
	var radius := 1
	var kegs_max := 1
	var kegs_live := 0
	var speed := 1.0
	var crates_burned := 0
	var boons_taken := 0
	var died_at := -1.0
	var killed_by := -1         ## side whose keg did it; -1 = the wyrm


class Keg:
	extends RefCounted
	var cell := Vector2i.ZERO
	var owner := 0
	var radius := 1
	var fuse := 0.0
	var born := 0.0


class Arm:
	extends RefCounted
	## One finger of a cross, walking outward a tile at a time.
	var cell := Vector2i.ZERO
	var dir := Vector2i.ZERO
	var left := 0
	var owner := 0
	var t := 0.0


# ── construction ────────────────────────────────────────────────────────────


## Build the arena. `cfg` keys (all optional):
##   crates: Array[Vector2i]   — where the survivors stand (they become blocks)
##   spawns: Array[Vector2i]   — the two kings' corners (default opposite ones)
##   seed:   int               — deterministic boon drops and AI dice
##   plus any tuning field above, by name.
## Every tuning field setup() will accept by name. An explicit list, not a
## property probe: a silently-ignored typo in a test's config is a test that
## measures the DEFAULTS while claiming to measure a tuned arena.
const TUNABLES: Array[String] = [
	"ring_step", "flame_life", "fuse_sec", "step_sec", "sudden_death_at",
	"ring_interval", "start_radius", "start_kegs", "max_radius", "max_kegs",
	"speed_step", "max_speed", "drop_chance",
]


func setup(cfg: Dictionary = {}) -> void:
	for key in cfg:
		var k := str(key)
		if k in ["crates", "spawns", "seed"]:
			continue
		if not TUNABLES.has(k):
			push_error("BlastGrid.setup: unknown key '%s'" % k)
			continue
		set(k, cfg[key])
	rng.seed = int(cfg.get("seed", 20260809))
	tiles = PackedInt32Array()
	tiles.resize(CELLS)
	boons = PackedInt32Array()
	boons.resize(CELLS)
	flame = PackedFloat32Array()
	flame.resize(CELLS)
	kegs.clear()
	arms.clear()
	kings.clear()
	events.clear()
	carved.clear()
	_drops.clear()
	_pending.clear()
	time = 0.0
	sudden = false
	_spiral_i = 0
	_ring_t = 0.0
	_over_announced = false

	# THE LATTICE — indestructible blackstone, laid on HALF the board and turned
	# 180 degrees onto the other half. It is what makes the arena play like
	# Bomberman and not like a paintball field: it turns an open board into
	# corridors, so a cross is a shape you can hide from and a corner is worth
	# standing behind.
	#
	# THE MIRROR IS NOT DECORATION — IT IS THE FAIRNESS. The obvious lattice is
	# "blackstone on every odd/odd square", and it is not symmetric under the
	# half-turn that swaps the two spawn corners (rotate the odd/odd set and you
	# get the even/even one). The consequence was measured, not guessed: 40
	# Casual mirror matches with the spawns SWAPPED put the (0,0) corner at
	# 26/40 and the (7,7) corner at 15/40, because (0,0) has cover at (1,1) and
	# (2,2)-vs-(5,5) breaks the second ring too. Planting one compensating stone
	# only moved the bias (7/40 -> 34/40 the other way): the advantage lives in
	# the whole neighbourhood, not in one tile. Building one half and rotating
	# it is the only construction that cannot be lopsided, and a mode whose
	# entire job is to break a tie FAIRLY does not get to ship a 65/35 spawn.
	for y in SIZE / 2:
		for x in SIZE:
			if x % 2 == 1 and y % 2 == 1:
				tiles[_i(Vector2i(x, y))] = Tile.STONE
				tiles[_i(Vector2i(SIZE - 1 - x, SIZE - 1 - y))] = Tile.STONE

	var spawns: Array = cfg.get("spawns", [Vector2i(0, 0), Vector2i(SIZE - 1, SIZE - 1)])
	for side in 2:
		var k := King.new()
		k.side = side
		k.cell = spawns[side]
		k.from = k.cell
		k.facing = Vector2i(0, 1) if side == 0 else Vector2i(0, -1)
		k.radius = start_radius
		k.kegs_max = start_kegs
		kings.append(k)

	# Elbow room: nobody opens the trial already walled in.
	var pockets := {}
	for k in kings:
		for c in _pocket(k.cell):
			pockets[_i(c)] = true
			if tiles[_i(c)] == Tile.STONE:
				tiles[_i(c)] = Tile.EMPTY

	for raw in cfg.get("crates", []):
		var c: Vector2i = raw
		if not in_bounds(c):
			continue
		var i := _i(c)
		if pockets.has(i) or tiles[i] == Tile.STONE:
			continue
		tiles[i] = Tile.CRATE
		if rng.randf() < drop_chance:
			var roll := rng.randf()
			_drops[i] = Boon.DRAUGHT if roll < 0.42 \
				else (Boon.CACHE if roll < 0.78 else Boon.SPURS)

	# THE DUEL INVARIANT, PROVED AND IF NEED BE MADE. Last thing, after the
	# crates: an arena the two kings cannot reach each other in is not a duel,
	# it is two men waiting for a dragon.
	carved = ensure_kings_connected()

	_spiral = _spiral_order()


## True when the blackstone lattice is unchanged by the half-turn that swaps the
## two spawn corners. THE fairness invariant — asserted by the suite, because
## the bias it prevents is invisible in any single match and decisive across a
## tournament.
func lattice_is_symmetric() -> bool:
	for i in CELLS:
		var c := cell_of(i)
		var m := Vector2i(SIZE - 1 - c.x, SIZE - 1 - c.y)
		if (tiles[i] == Tile.STONE) != (tiles[_i(m)] == Tile.STONE):
			return false
	return true


# ── THE DUEL INVARIANT: the two kings must be able to REACH each other ──────
#
# THE BUG THIS CLOSES, AND IT WAS TOTAL. The lattice above is proved SYMMETRIC
# and the pockets are proved OPEN, and NEITHER OF THOSE SAYS THE TWO KINGS ARE
# IN THE SAME ARENA. Print the mirrored lattice and the hole is obvious the
# moment you look at rows 3 and 4:
#
#     7 ........        The half-turn that fixed the 65/35 spawn also flips the
#     6 #.#.#.#.        parity of the pillars across the seam, so the two middle
#     5 ........        rows come out as COMPLEMENTARY COMBS. Every gap in row 3
#     4 #.#.#.#.   <--  is a pillar in row 4 and every gap in row 4 is a pillar
#     3 .#.#.#.#   <--  in row 3. Nothing 4-connected crosses. The board was two
#     2 ........        sealed halves with one king in each, in EVERY arena the
#     1 .#.#.#.#        mode ever built — 399/399 in the probe that found it.
#     0 ........
#
# So the "duel" could not be lost to the other man's fire: the only deaths
# available were self-inflicted or by wyrm, which is the exact not-a-duel this
# whole mode exists to replace. The fairness fix was real and it is kept; what
# was missing is anything that PROVED the arena was still one arena afterwards.
#
# AND IT REPEATS AT EVERY SCALE. The same comb sits inside the sub-board the
# wyrm's ring leaves behind ([2..5] is `.#.#` over `#.#.`), so opening the outer
# seam alone would hand the kings a corridor and then let the closing ring wall
# them apart again with 20 squares still on the board. The repair therefore has
# to hold for the arena the wyrm is about to leave, not only the one it starts
# with — see `ensure_kings_connected`.
#
# A CRATE IS A DOOR, NOT A WALL. Bannermen are destructible, so a corridor
# behind one is a corridor a king can open with a jar — the digging IS the game.
# Blackstone is the only thing that can seal the arena for good, so the shipping
# gate is "no all-blackstone cut". `through_crates = false` asks the strictly
# harder question (can he WALK it right now) that the gate must NOT be: an
# opening position where every route is currently plugged by bannermen is a good
# opening position.


## Every cell reachable from `start`, as a set of cell indices. `inset` shrinks
## the board to the square the wyrm's ring has not eaten yet.
func reachable_from(start: Vector2i, through_crates := true, inset := 0) -> Dictionary:
	var seen := {}
	if not _inside(start, inset) or tiles[_i(start)] == Tile.STONE:
		return seen
	seen[_i(start)] = true
	var stack: Array[Vector2i] = [start]
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for d in DIRS:
			var n: Vector2i = c + d
			if not _inside(n, inset) or seen.has(_i(n)):
				continue
			var t := tiles[_i(n)]
			if t == Tile.STONE:
				continue
			if t == Tile.CRATE and not through_crates:
				continue
			seen[_i(n)] = true
			stack.append(n)
	return seen


func _inside(c: Vector2i, inset: int) -> bool:
	return c.x >= inset and c.x < SIZE - inset \
		and c.y >= inset and c.y < SIZE - inset


## THE INVARIANT ITSELF: king A can get to king B. Asserted on every generated
## arena by the suite and — because a check that cannot fail is worse than no
## check — against hand-built sealed boards it must REJECT.
func kings_connected(through_crates := true) -> bool:
	if kings.size() < 2:
		return false
	return reachable_from(kings[0].cell, through_crates).has(_i(kings[1].cell))


## THE SAME QUESTION ASKED OF THE ARENA THE WYRM IS LEAVING BEHIND: with the
## outer `inset` rings entombed, is every square still standing part of ONE
## arena? The ring is supposed to compress the kings together; a ring that
## divides what it has not eaten yet is a ring that walls them apart.
func region_is_connected(inset: int) -> bool:
	var first := Vector2i(-1, -1)
	var total := 0
	for i in CELLS:
		var c := cell_of(i)
		if not _inside(c, inset) or tiles[i] == Tile.STONE:
			continue
		total += 1
		if first.x < 0:
			first = c
	if total <= 1:
		return true
	return reachable_from(first, true, inset).size() == total


## Every stage of the closing ring, in one answer. The gate the suite asserts on
## every generated arena.
func ring_keeps_one_arena() -> bool:
	for inset in SIZE / 2:
		if not region_is_connected(inset):
			return false
	return true


## How many squares are still arena (anything the wyrm has not entombed).
func open_cells() -> int:
	var n := 0
	for i in CELLS:
		if tiles[i] != Tile.STONE:
			n += 1
	return n


## THE FEWEST BLACKSTONE CELLS whose removal joins `a` to `b`, as the path they
## lie on. A 0-1 BFS: stepping onto blackstone costs one carve, stepping
## anywhere else costs nothing, so the cheapest route IS the minimum — any set
## of removals that opens a route contains every stone on the route it opens,
## and no route is cheaper than this one.
##
## Deterministic to the tile: no RNG, fixed neighbour order, and the tiles it
## reads came from the seed. Same seed, same drawn position, same carve.
func _cheapest_stone_path(a: Vector2i, b: Vector2i, inset: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not _inside(a, inset) or not _inside(b, inset):
		return out
	var unreached := CELLS + 1
	var dist := PackedInt32Array()
	var prev := PackedInt32Array()
	dist.resize(CELLS)
	prev.resize(CELLS)
	for i in CELLS:
		dist[i] = unreached
		prev[i] = -1
	var src := _i(a)
	var dst := _i(b)
	dist[src] = 0
	var deque: Array[int] = [src]
	while not deque.is_empty():
		var cur: int = deque.pop_front()
		var cc := cell_of(cur)
		for d in DIRS:
			var n := cc + d
			if not _inside(n, inset):
				continue
			var j := _i(n)
			var w := 1 if tiles[j] == Tile.STONE else 0
			if dist[cur] + w >= dist[j]:
				continue
			dist[j] = dist[cur] + w
			prev[j] = cur
			if w == 0:
				deque.push_front(j)
			else:
				deque.push_back(j)
	if dist[dst] >= unreached:
		return out
	var walk := dst
	while walk != -1:
		if tiles[walk] == Tile.STONE:
			out.append(cell_of(walk))
		walk = prev[walk]
	out.reverse()
	return out


## THE CHEAPEST BREACH, without touching anything: the blackstone a jar-proof
## wall between the two kings is actually made of. Empty when they can already
## meet. The suite reads it to prove the repair carves the MINIMUM and not
## merely *a* corridor.
func stone_cut_between_kings() -> Array[Vector2i]:
	if kings.size() < 2:
		return []
	return _cheapest_stone_path(kings[0].cell, kings[1].cell, 0)


## Open the cheapest corridor between two cells. Returns what it carved.
##
## IT CARVES IN MIRROR PAIRS, and that is not tidiness. The lattice's half-turn
## symmetry is the measured fairness fix this arena rests on (see setup: the
## unmirrored lattice put one corner at 26/40). An unpaired carve would open the
## arena and hand one corner a gate the other does not have — trading a sealed
## tie-breaker for a rigged one. The antipode of a blackstone cell is a
## blackstone cell while the lattice is symmetric, so the pair always exists,
## and opening the far side can only help the near side's route.
func _carve_between(a: Vector2i, b: Vector2i, inset: int) -> Array[Vector2i]:
	var opened: Array[Vector2i] = []
	var path := _cheapest_stone_path(a, b, inset)
	for c in path:
		for m in [c, Vector2i(SIZE - 1 - c.x, SIZE - 1 - c.y)]:
			if not _inside(m, inset) or tiles[_i(m)] != Tile.STONE:
				continue
			tiles[_i(m)] = Tile.EMPTY
			opened.append(m)
	return opened


## PROVE THE KINGS CAN MEET — now, and at every stage of the wyrm's closing
## ring — and open the minimum blackstone where they cannot. Returns the cells
## it had to carve.
##
## Two passes, and the second is the one that is easy to forget: joining the two
## corners fixes the arena the duel STARTS in, and the ring then eats that
## corridor and leaves the same comb wall standing in the middle four ranks with
## twenty squares still in play. So every sub-board the ring will leave behind
## is joined too, outward in, which on the shipped lattice costs four cells and
## turns the seam into four symmetric gates.
func ensure_kings_connected() -> Array[Vector2i]:
	var opened: Array[Vector2i] = []
	if kings.size() < 2:
		return opened
	# I. THE DUEL AS IT OPENS — a route from one king's corner to the other's.
	# A bounded loop, never `while true`: a repair that cannot converge has to
	# say so out loud, not hang a bracket decider inside setup().
	for _pass in 4:
		if kings_connected():
			break
		var cut := _carve_between(kings[0].cell, kings[1].cell, 0)
		if cut.is_empty():
			push_error("BlastGrid: the two kings cannot be joined at all")
			break
		opened.append_array(cut)
	# II. THE DUEL AS THE RING CLOSES — every arena the wyrm is about to leave.
	for inset in range(1, SIZE / 2):
		for _pass in 8:
			if region_is_connected(inset):
				break
			var seed_cell := Vector2i(-1, -1)
			var stranded := Vector2i(-1, -1)
			var seen := {}
			for i in CELLS:
				var c := cell_of(i)
				if not _inside(c, inset) or tiles[i] == Tile.STONE:
					continue
				if seed_cell.x < 0:
					seed_cell = c
					seen = reachable_from(seed_cell, true, inset)
				elif not seen.has(i):
					stranded = c
					break
			if stranded.x < 0:
				break
			var cut := _carve_between(seed_cell, stranded, inset)
			if cut.is_empty():
				push_error("BlastGrid: ring inset %d cannot be joined" % inset)
				break
			opened.append_array(cut)
	if not kings_connected() or not ring_keeps_one_arena():
		push_error("BlastGrid: carved %d cells and the arena is still split"
			% opened.size())
	return opened


## The three tiles a king must have free at his corner: his own and two out.
func _pocket(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = [c]
	for d in DIRS:
		var n := c + d
		if in_bounds(n):
			out.append(n)
	return out


## THE CLOSING SPIRAL, IN ANTIPODAL PAIRS. Outer ring first, clockwise, then
## inward — and each step takes a cell TOGETHER WITH THE ONE DIAGONALLY OPPOSITE
## IT. Returns 32 steps of two cells; every square is covered exactly once,
## which is the termination proof this whole module rests on.
##
## The pairing is the second half of the fairness fix. A plain spiral starts at
## (0,0), so the wyrm eats one king's corner first EVERY MATCH: with the lattice
## already symmetric, that alone still measured 62/38 in favour of the far
## corner over 80 mirror matches. Burning a cell and its antipode in the same
## breath makes the closing ring blind to which corner you chose — and it looks
## better too: the fire falls on both flanks at once and the arena closes like a
## fist rather than unrolling like a carpet.
func _spiral_order() -> Array:
	var ring: Array[Vector2i] = []
	var lo := 0
	var hi := SIZE - 1
	while lo <= hi:
		for x in range(lo, hi + 1):
			ring.append(Vector2i(x, lo))
		for y in range(lo + 1, hi + 1):
			ring.append(Vector2i(hi, y))
		if lo < hi:
			for x in range(hi - 1, lo - 1, -1):
				ring.append(Vector2i(x, hi))
			for y in range(hi - 1, lo, -1):
				ring.append(Vector2i(lo, y))
		lo += 1
		hi -= 1
	var out: Array = []
	var seen := {}
	for c in ring:
		if seen.has(_i(c)):
			continue
		seen[_i(c)] = true
		var m := Vector2i(SIZE - 1 - c.x, SIZE - 1 - c.y)
		if m == c:
			out.append([c])
			continue
		seen[_i(m)] = true
		out.append([c, m])
	return out


# ── geometry ────────────────────────────────────────────────────────────────


func index(c: Vector2i) -> int:
	return c.y * SIZE + c.x


func cell_of(i: int) -> Vector2i:
	return Vector2i(i % SIZE, i / SIZE)


func _i(c: Vector2i) -> int:
	return c.y * SIZE + c.x


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < SIZE and c.y >= 0 and c.y < SIZE


func tile_at(c: Vector2i) -> int:
	return tiles[_i(c)] if in_bounds(c) else Tile.STONE


func keg_at(c: Vector2i) -> Keg:
	for keg in kegs:
		if keg.cell == c:
			return keg
	return null


## Can a king's foot land here? (Not "is it safe" — that is danger_map's job.)
func walkable(c: Vector2i) -> bool:
	if not in_bounds(c):
		return false
	if tiles[_i(c)] != Tile.EMPTY:
		return false
	return keg_at(c) == null


## THE CROSS, resolved instantly and without mutating anything — the shape a
## keg of this radius WOULD burn if it went off right now. Two callers: the
## AI's danger map, and the suite that asserts the shape. The timed walk in
## `_advance_arm` is required to agree with this, cell for cell.
##
## Rules, in order, per arm: leave the board -> stop; blackstone -> stop
## WITHOUT lighting it; a crate -> light it and stop (the crate eats the blast,
## which is why a wall of your own bannermen is real cover); another keg ->
## light it and stop (it will chain from there with its OWN radius).
func blast_cells(origin: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not in_bounds(origin):
		return out
	out.append(origin)
	for d in DIRS:
		var c := origin
		for _s in radius:
			c += d
			if not in_bounds(c):
				break
			var t := tiles[_i(c)]
			if t == Tile.STONE:
				break
			out.append(c)
			if t == Tile.CRATE:
				break
			if keg_at(c) != null:
				break
	return out


# ── the king's two verbs ────────────────────────────────────────────────────


## Commit to the neighbouring tile. Refused mid-step, into stone, into a crate,
## into a keg (including your own, once you have stepped off it), off the board,
## and INTO LIVE FIRE — a king may be caught by a blast but never walk into one.
func request_step(side: int, dir: Vector2i) -> bool:
	if dir == Vector2i.ZERO or side < 0 or side >= kings.size():
		return false
	var k: King = kings[side]
	if not k.alive or k.busy > 0.0:
		return false
	var c: Vector2i = k.cell + dir
	k.facing = dir
	if not walkable(c) or flame[_i(c)] > 0.0:
		return false
	k.from = k.cell
	k.cell = c
	k.busy = step_sec / maxf(k.speed, 0.05)
	events.append({"kind": "step", "side": side, "from": k.from, "to": c,
		"dur": k.busy})
	_take_boon(k)
	return true


## Set a wildfire jar down on the tile you are standing on.
func place_keg(side: int) -> bool:
	if side < 0 or side >= kings.size():
		return false
	var k: King = kings[side]
	if not k.alive or k.kegs_live >= k.kegs_max:
		return false
	if keg_at(k.cell) != null or flame[_i(k.cell)] > 0.0:
		return false
	var keg := Keg.new()
	keg.cell = k.cell
	keg.owner = side
	keg.radius = k.radius
	keg.fuse = fuse_sec
	keg.born = time
	kegs.append(keg)
	k.kegs_live += 1
	events.append({"kind": "keg_placed", "cell": keg.cell, "side": side,
		"radius": keg.radius, "fuse": keg.fuse})
	return true


# ── the clock ───────────────────────────────────────────────────────────────


func tick(dt: float) -> void:
	if dt <= 0.0:
		return
	time += dt
	for k: King in kings:
		k.busy = maxf(0.0, k.busy - dt)

	# fuses
	for keg: Keg in kegs.duplicate():
		if kegs.has(keg):
			keg.fuse -= dt
			if keg.fuse <= 0.0:
				detonate_at(keg.cell)

	# THE WALK. A detonation triggered inside this loop appends fresh arms to
	# `arms`, so the list is emptied first and rebuilt from survivors: new arms
	# land in the rebuilt list and start walking on the NEXT tick, which is what
	# makes a chain visibly ripple instead of resolving in one frame.
	var walking: Array = arms
	arms = []
	for a: Arm in walking:
		a.t += dt
		var alive_arm := true
		while alive_arm and a.t >= ring_step:
			a.t -= ring_step
			alive_arm = _advance_arm(a)
		if alive_arm:
			arms.append(a)

	# the fire burns down; boons hidden under a crate surface when it does
	for i in CELLS:
		if flame[i] > 0.0:
			flame[i] -= dt
			if flame[i] <= 0.0:
				flame[i] = 0.0
				events.append({"kind": "flame_out", "cell": cell_of(i)})
				if _pending.has(i):
					boons[i] = _pending[i]
					_pending.erase(i)
					events.append({"kind": "boon_revealed", "cell": cell_of(i),
						"boon": boons[i]})

	_tick_wyrm(dt)

	if is_over() and not _over_announced:
		_over_announced = true
		events.append({"kind": "over", "winner": winner()})


## THE WYRM'S PATIENCE runs out, and then the arena does.
func _tick_wyrm(dt: float) -> void:
	if not sudden:
		if time < sudden_death_at:
			return
		sudden = true
		events.append({"kind": "sudden_death", "at": time})
	_ring_t += dt
	while _ring_t >= ring_interval and _spiral_i < _spiral.size():
		_ring_t -= ring_interval
		for c in _spiral[_spiral_i]:
			_torch(c)
		_spiral_i += 1


## One cell of the closing ring: whatever stood there is gone, and the square
## itself becomes blackstone. A keg caught by the wyrm COOKS OFF rather than
## being swallowed — a dragon lighting your ordnance for you is the best thing
## that happens in the last ten seconds of a trial.
func _torch(c: Vector2i) -> void:
	var i := _i(c)
	if tiles[i] == Tile.CRATE:
		_burn_crate(c, -1)
	if keg_at(c) != null:
		detonate_at(c)
	boons[i] = Boon.NONE
	_pending.erase(i)
	_drops.erase(i)
	tiles[i] = Tile.STONE
	events.append({"kind": "torched", "cell": c})
	for k: King in kings:
		if k.alive and k.cell == c:
			_kill(k, -1)


# ── fire ────────────────────────────────────────────────────────────────────


## Blow a keg (or light bare ground, when the wyrm does it). The origin tile
## lights at once; the four arms walk out from the next tick.
func detonate_at(c: Vector2i) -> void:
	if not in_bounds(c):
		return
	var keg := keg_at(c)
	var radius := start_radius
	var owner := -1
	if keg != null:
		radius = keg.radius
		owner = keg.owner
		kegs.erase(keg)
		var k: King = kings[owner]
		k.kegs_live = maxi(0, k.kegs_live - 1)
	events.append({"kind": "detonate", "cell": c, "radius": radius, "side": owner})
	_light(c, owner)
	for d in DIRS:
		var a := Arm.new()
		a.cell = c
		a.dir = d
		a.left = radius
		a.owner = owner
		arms.append(a)


func _advance_arm(a: Arm) -> bool:
	var c: Vector2i = a.cell + a.dir
	if not in_bounds(c):
		return false
	var i := _i(c)
	var t := tiles[i]
	if t == Tile.STONE:
		return false
	if t == Tile.CRATE:
		_light(c, a.owner)
		_burn_crate(c, a.owner)
		return false
	if keg_at(c) != null:
		detonate_at(c)   # THE CHAIN — and this arm dies here
		return false
	_light(c, a.owner)
	a.cell = c
	a.left -= 1
	return a.left > 0


func _light(c: Vector2i, owner: int) -> void:
	var i := _i(c)
	var was := flame[i]
	flame[i] = maxf(flame[i], flame_life)
	if was <= 0.0:
		events.append({"kind": "flame", "cell": c, "side": owner})
	if boons[i] != Boon.NONE:
		events.append({"kind": "boon_burned", "cell": c, "boon": boons[i]})
		boons[i] = Boon.NONE
	for k: King in kings:
		if k.alive and k.cell == c:
			_kill(k, owner)


func _burn_crate(c: Vector2i, owner: int) -> void:
	var i := _i(c)
	tiles[i] = Tile.EMPTY
	if owner >= 0:
		kings[owner].crates_burned += 1
	events.append({"kind": "crate_burned", "cell": c, "side": owner})
	if _drops.has(i):
		_pending[i] = _drops[i]   # surfaces when the fire on this tile dies
		_drops.erase(i)


func _take_boon(k: King) -> void:
	var i := _i(k.cell)
	var b: int = boons[i]
	if b == Boon.NONE:
		return
	boons[i] = Boon.NONE
	k.boons_taken += 1
	match b:
		Boon.DRAUGHT:
			k.radius = mini(k.radius + 1, max_radius)
		Boon.CACHE:
			k.kegs_max = mini(k.kegs_max + 1, max_kegs)
		Boon.SPURS:
			k.speed = minf(k.speed + speed_step, max_speed)
	events.append({"kind": "boon_taken", "cell": k.cell, "side": k.side, "boon": b})


func _kill(k: King, by: int) -> void:
	if not k.alive:
		return
	k.alive = false
	k.died_at = time
	k.killed_by = by
	events.append({"kind": "king_died", "side": k.side, "cell": k.cell, "by": by})


# ── verdict ─────────────────────────────────────────────────────────────────


func is_over() -> bool:
	return not (kings[0].alive and kings[1].alive)


## THE WHOLE POINT: this never answers "nobody".
##
## Last king standing, and when the last two fall together the trial is still
## decided — by who stood longest, then by who burned more of the field, then
## by who gathered more boons. A double knockout that resolved to a draw would
## put the tournament back exactly where the stalemate left it.
func winner() -> int:
	var a: King = kings[0]
	var b: King = kings[1]
	if a.alive and b.alive:
		return ONGOING
	if a.alive:
		return 0
	if b.alive:
		return 1
	if not is_equal_approx(a.died_at, b.died_at):
		return 0 if a.died_at > b.died_at else 1
	if a.crates_burned != b.crates_burned:
		return 0 if a.crates_burned > b.crates_burned else 1
	if a.boons_taken != b.boons_taken:
		return 0 if a.boons_taken > b.boons_taken else 1
	return 0


func drain_events() -> Array:
	var out := events
	events = []
	return out


# ── what the AI is allowed to know ──────────────────────────────────────────


## Every tile that will be on fire within `horizon` seconds, as
## {cell index -> seconds until it lights}. Live fire is 0.
##
## The chain is modelled: a keg standing inside another keg's cross inherits
## the earlier fuse (two relaxation passes, which is enough for the chain
## lengths an 8x8 lattice can hold), so a Master-tier king will not walk into
## the far end of a chain that has not started yet.
func danger_map(horizon: float) -> Dictionary:
	var out := {}
	for i in CELLS:
		if flame[i] > 0.0:
			out[i] = 0.0

	for a: Arm in arms:
		var c: Vector2i = a.cell
		var eta: float = maxf(ring_step - a.t, 0.0)
		for _s in a.left:
			c += a.dir
			if not in_bounds(c):
				break
			var t := tiles[_i(c)]
			if t == Tile.STONE:
				break
			out[_i(c)] = minf(out.get(_i(c), 99.0), eta)
			if t == Tile.CRATE or keg_at(c) != null:
				break
			eta += ring_step

	var eta_of := {}
	for keg: Keg in kegs:
		eta_of[_i(keg.cell)] = keg.fuse
	for _pass in 2:
		for keg: Keg in kegs:
			var e: float = eta_of[_i(keg.cell)]
			for c in blast_cells(keg.cell, keg.radius):
				var j := _i(c)
				if eta_of.has(j) and eta_of[j] > e:
					eta_of[j] = e
	for keg: Keg in kegs:
		var e: float = eta_of[_i(keg.cell)]
		for c in blast_cells(keg.cell, keg.radius):
			var j := _i(c)
			out[j] = minf(out.get(j, 99.0), e)

	if sudden:
		var e := maxf(ring_interval - _ring_t, 0.0)
		for n in range(_spiral_i, _spiral.size()):
			if e > horizon:
				break
			for c in _spiral[n]:
				var j := _i(c)
				out[j] = minf(out.get(j, 99.0), e)
			e += ring_interval

	for j in out.keys():
		if out[j] > horizon:
			out.erase(j)
	return out


## Seconds until the wyrm reaches this tile (INF before sudden death, and for
## tiles it has already taken). The HUD's countdown and the AI both read it.
func ring_eta(c: Vector2i) -> float:
	if not sudden:
		return INF
	for n in range(_spiral_i, _spiral.size()):
		if _spiral[n].has(c):
			return maxf(ring_interval - _ring_t, 0.0) \
				+ float(n - _spiral_i) * ring_interval
	return INF


func crates_left() -> int:
	var n := 0
	for i in CELLS:
		if tiles[i] == Tile.CRATE:
			n += 1
	return n
