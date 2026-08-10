extends SceneTree
## Diagnostic (not a gate): everything you need to judge the Trial-by-Fire tier
## ladder, measured rather than argued.
##
## FIVE QUESTIONS, IN THE ORDER YOU SHOULD ASK THEM. The first two are controls
## on the ARENA and they come first on purpose — this file's own history is the
## reason. A "Master is over-cautious" finding once survived a whole afternoon
## before the board turned out to be the culprit (the fixture's crate generator
## still skipped odd/odd cells from a retired lattice, leaving eight
## permanently-open squares in ONE king's half). A board that is fair to DICE
## and unfair to a brain is a brain problem; a board that is unfair to dice is a
## board problem, and no tier number measured on it means anything.
##
##   1. DICE FAIRNESS   two random walkers, same arena. Corner (0,0) should take
##                      about half, and the two sides should kill themselves
##                      about equally often.
##   2. MIRROR FAIRNESS the same question asked of a real brain: Seasoned vs
##                      Seasoned, corner win rate.
##   3. THE LADDER      every pairing, both orientations, so a corner advantage
##                      cancels out of the tier numbers instead of hiding in
##                      them. Row tier's win rate against the column tier.
##   4. THE HUNT        ONE KING STANDS STILL and never presses a key, the wyrm
##                      is switched off, and the only thing that can kill him is
##                      the rival's fire. This is the honest measure of whether a
##                      tier can threaten a PLAYER: a tier that cannot land a
##                      kill here is not an easy opponent, it is no opponent.
##   5. THE CHRONICLE   what actually kills kings at each tier (own jar, rival's
##                      jar, wyrm, survived) — the number that says WHERE a
##                      tier's win rate comes from.
##
## Run: Godot --headless --path <project> -s res://src/minigame/dev_ladder_probe.gd
## Optional: -- n=60 hunts=30   (seeds per pairing / seeds per hunt orientation)

const Grid := preload("res://src/minigame/blast_grid.gd")
const AI := preload("res://src/minigame/king_ai.gd")
const DT := 1.0 / 60.0

var n_seeds := 40
var n_hunts := 20
## Which arena the numbers are measured on — and BOTH OF THESE ARE ARENAS THE
## PLAYER ACTUALLY PLAYS, which is the whole point. `fast` is trial_by_fire.gd's
## quick match and is what tests/test_minigame.gd now plays; `full` is the
## shipping default.
##
## THE SUITE USED TO PLAY NEITHER. Its AI fixture was 20 s / 0.28 / fuse 1.6 —
## invented numbers, and the fuse in particular is shorter than anything that
## ships. That matters more than it sounds: a king's ability to survive HIS OWN
## JAR is dominated by the fuse, so the Casual tier measured as an impossible
## opponent (8 % against an idle king at fuse 1.6, 35 % at the shipped 1.9) and
## the wyrm decided half of every duel, flattening the top two tiers to a coin
## flip. The tier ladder is a property of the arena as much as of the brains, and
## a fixture arena nobody ships is a fixture measuring itself. Same family of
## mistake as the crate generator that skipped odd/odd cells; different disguise.
var arena := "fast"
const ARENAS := {
	"fast": {"sudden_death_at": 22.0, "ring_interval": 0.30, "fuse_sec": 1.9},
	"full": {"sudden_death_at": 45.0, "ring_interval": 0.60, "fuse_sec": 2.35},
}

const TIERS := [AI.Difficulty.CASUAL, AI.Difficulty.SEASONED, AI.Difficulty.MASTER]
const NAMES := {AI.Difficulty.CASUAL: "Casual", AI.Difficulty.SEASONED: "Seasoned",
	AI.Difficulty.MASTER: "Master"}
const BY_NAME := {"casual": AI.Difficulty.CASUAL, "seasoned": AI.Difficulty.SEASONED,
	"master": AI.Difficulty.MASTER}

## THE SWEEP, so a candidate value never has to be tried by editing the shipping
## tier table. `-- master.ring_sense=2.0 casual.hunt=3` patches those two keys
## for the whole run and prints the patch at the top of the report, which is what
## makes a pasted number traceable back to the run that produced it.
var patch := {}
## `quick=1` drops the two arena controls and the kings/wyrm split — the parts
## that re-play duels already played. For sweeping a candidate value, not for
## the number you are going to quote.
var quick := false
## `focus=master:seasoned` plays ONE cell of the ladder and nothing else, which
## is what makes a high-seed answer affordable. A 40-seed cell is 80 duels and
## carries about six points of standard error — enough noise to read a tuning
## step that is not there. Sweep on `focus` with n>=100, quote from the full run.
var focus: Array = []


## The one cell, at whatever seed count you paid for, with its error bar.
func _focus_cell() -> void:
	var a: int = focus[0]
	var b: int = focus[1]
	var w := 0
	for i in n_seeds:
		var sv := 1000 + i * 131
		if _duel(sv, a, b)["winner"] == 0:
			w += 1
		if _duel(sv, b, a)["winner"] == 1:
			w += 1
	var n := n_seeds * 2
	var p := float(w) / float(n)
	print("FOCUS %s over %s: %d/%d = %.1f%% (+/- %.1f)"
		% [NAMES[a], NAMES[b], w, n, 100.0 * p,
		100.0 * sqrt(maxf(p * (1.0 - p), 0.0) / float(n))])
	quit(0)


func _brain(tier: int, seed_value: int) -> AI:
	var b: AI = AI.new(tier, seed_value)
	if patch.has(tier):
		b.overrides = patch[tier]
	return b


## The same field the suite plays on — every square offered, setup() rejects the
## blackstone and the spawn pockets. DO NOT second-guess the lattice here.
func _crates(sv: int) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = sv
	var out: Array = []
	for y in Grid.SIZE:
		for x in Grid.SIZE:
			if r.randf() < 0.42:
				out.append(Vector2i(x, y))
	return out


func _arena(sv: int, wyrm := true) -> Grid:
	var g: Grid = Grid.new()
	var cfg: Dictionary = ARENAS[arena].duplicate()
	cfg["seed"] = sv
	cfg["crates"] = _crates(sv)
	if not wyrm:
		cfg["sudden_death_at"] = 100000.0
	g.setup(cfg)
	return g


## The wyrm's spiral is the termination proof: sudden death, plus 64 cells at
## `ring_interval`, plus slack. Anything past this is a hang, not a long game.
func _cap() -> int:
	var a: Dictionary = ARENAS[arena]
	return int((float(a["sudden_death_at"]) + 64.0 * float(a["ring_interval"])
		+ 6.0) / DT)


## One full duel. Returns the winner plus the chronicle of how each king ended.
func _duel(sv: int, ta: int, tb: int) -> Dictionary:
	var g := _arena(sv)
	var brains := [_brain(ta, sv + 1), _brain(tb, sv + 2)]
	var ticks := 0
	while ticks < _cap() and not g.is_over():
		for n in 2:
			var side: int = n if ticks % 2 == 0 else 1 - n
			var act: Dictionary = brains[side].decide(g, side, DT)
			if act.has("keg"):
				g.place_keg(side)
			elif act.has("step"):
				g.request_step(side, act["step"])
		g.tick(DT)
		ticks += 1
	return {"winner": g.winner(), "fate": [_fate(g, 0), _fate(g, 1)],
		"t": g.time, "dragon": g.sudden}


## "alive", "self", "rival" or "wyrm" — where a king's trial ended.
func _fate(g: Grid, side: int) -> String:
	var k = g.kings[side]
	if k.alive:
		return "alive"
	if k.killed_by < 0:
		return "wyrm"
	return "self" if k.killed_by == side else "rival"


func _run(sv: int, ta: int, tb: int) -> int:
	return int(_duel(sv, ta, tb)["winner"])


# ── 1. the dice control ─────────────────────────────────────────────────────
#
# A walker with no brain at all: a legal step at random, a jar now and then, no
# danger map, no retreat. If the ARENA is lopsided this is where it shows,
# because there is no strategy here to blame it on.


func _walker_duel(sv: int) -> Dictionary:
	var g := _arena(sv)
	var r := RandomNumberGenerator.new()
	r.seed = sv * 7919 + 13
	var cool := [0.0, 0.0]
	var ticks := 0
	while ticks < _cap() and not g.is_over():
		for n in 2:
			var side: int = n if ticks % 2 == 0 else 1 - n
			cool[side] -= DT
			if cool[side] > 0.0 or g.kings[side].busy > 0.0 or not g.kings[side].alive:
				continue
			cool[side] = 0.25
			if r.randf() < 0.15:
				g.place_keg(side)
			else:
				var d: Vector2i = Grid.DIRS[r.randi() % 4]
				g.request_step(side, d)
		g.tick(DT)
		ticks += 1
	return {"winner": g.winner(), "fate": [_fate(g, 0), _fate(g, 1)]}


# ── 4. the hunt ─────────────────────────────────────────────────────────────
#
# THE HONEST QUESTION. The idle king is what a beginner actually is for the
# first ten seconds of the mode: standing in his corner, not pressing anything.
# The wyrm is switched off so the ONLY thing that can kill him is the rival's
# fire — no clock, no accident, just "can this tier come and get you".


func _hunt(sv: int, tier: int, idle_side: int) -> Dictionary:
	var g := _arena(sv, false)
	var hunter := 1 - idle_side
	var brain := _brain(tier, sv + 2)
	var ticks := 0
	while ticks < 9000 and not g.is_over():
		var act: Dictionary = brain.decide(g, hunter, DT)
		if act.has("keg"):
			g.place_keg(hunter)
		elif act.has("step"):
			g.request_step(hunter, act["step"])
		g.tick(DT)
		g.drain_events()
		ticks += 1
	var idle = g.kings[idle_side]
	return {
		"killed": (not idle.alive) and idle.killed_by == hunter,
		"suicide": not g.kings[hunter].alive,
		"t": g.time,
	}


# ── the report ──────────────────────────────────────────────────────────────


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := str(a).split("=")
		if kv.size() == 2 and kv[0] == "n":
			n_seeds = int(kv[1])
		elif kv.size() == 2 and kv[0] == "hunts":
			n_hunts = int(kv[1])
		elif kv.size() == 2 and kv[0] == "arena" and ARENAS.has(kv[1]):
			arena = kv[1]
		elif kv.size() == 2 and kv[0] == "quick":
			quick = int(kv[1]) != 0
		elif kv.size() == 2 and kv[0] == "focus":
			var fp := kv[1].split(":")
			if fp.size() == 2 and BY_NAME.has(fp[0]) and BY_NAME.has(fp[1]):
				focus = [BY_NAME[fp[0]], BY_NAME[fp[1]]]
			else:
				push_error("probe: focus wants <tier>:<tier>, got '%s'" % kv[1])
		elif kv.size() == 2 and kv[0].contains("."):
			var parts := kv[0].split(".")
			if not BY_NAME.has(parts[0]):
				push_error("probe: no tier called '%s'" % parts[0])
				continue
			var tier: int = BY_NAME[parts[0]]
			if not AI.TIERS[tier].has(parts[1]):
				push_error("probe: tier has no key '%s'" % parts[1])
				continue
			if not patch.has(tier):
				patch[tier] = {}
			patch[tier][parts[1]] = float(kv[1]) if kv[1].contains(".") else int(kv[1])
	var t0 := Time.get_ticks_msec()
	print("ARENA %s %s" % [arena, ARENAS[arena]])
	# BEFORE the focus early-return, always: a swept number whose patch was not
	# echoed is a number you cannot attribute. (zsh does not word-split an
	# unquoted "$ARGS", so a whole sweep can silently run UNPATCHED and quietly
	# reproduce the baseline — this line is what catches that.)
	for t in patch:
		print("PATCH %s %s" % [NAMES[t], patch[t]])
	if not focus.is_empty():
		_focus_cell()
		return

	# 1. DICE — the control that has to come first.
	if not quick:
		var w00 := 0
		var wself := [0, 0]
		for i in n_seeds:
			var out := _walker_duel(300 + i * 41)
			if out["winner"] == 0:
				w00 += 1
			for side in 2:
				if out["fate"][side] == "self":
					wself[side] += 1
		print("CONTROL random walkers: corner (0,0) took %d/%d (%.0f%%), self-kills %d vs %d"
			% [w00, n_seeds, 100.0 * w00 / n_seeds, wself[0], wself[1]])

		# 2. MIRROR — the same question with a brain in the seat.
		var c00 := 0
		for i in n_seeds:
			if _run(500 + i * 97, AI.Difficulty.SEASONED, AI.Difficulty.SEASONED) == 0:
				c00 += 1
		print("CONTROL Seasoned mirrors: corner (0,0) took %d/%d (%.0f%%)"
			% [c00, n_seeds, 100.0 * c00 / n_seeds])
		print("")

	# 3. THE LADDER.
	var fates := {}
	for t in TIERS:
		fates[t] = {"alive": 0, "self": 0, "rival": 0, "wyrm": 0}
	var dragon := 0
	var duels := 0
	print("LADDER  %d seeds x 2 orientations — ROW tier's win rate vs COLUMN tier"
		% n_seeds)
	print("                 %-11s%-11s%-11s" % ["Casual", "Seasoned", "Master"])
	for a in TIERS:
		var line := "  %-13s" % NAMES[a]
		for b in TIERS:
			var w := 0
			for i in n_seeds:
				var sv := 1000 + i * 131
				var x := _duel(sv, a, b)      # A as side 0
				if x["winner"] == 0:
					w += 1
				var y := _duel(sv, b, a)      # A as side 1
				if y["winner"] == 1:
					w += 1
				for pair in [[x, a, b], [y, b, a]]:
					var d: Dictionary = pair[0]
					fates[pair[1]][d["fate"][0]] += 1
					fates[pair[2]][d["fate"][1]] += 1
					duels += 1
					if d["dragon"]:
						dragon += 1
			line += "  %-9s" % ("%.0f%%" % (100.0 * w / (n_seeds * 2)))
		print(line)
	print("")

	# 4. THE HUNT.
	print("HUNT    idle king, wyrm off — %d seeds x 2 orientations" % n_hunts)
	for t in TIERS:
		var killed := 0
		var suicides := 0
		var times: Array[float] = []
		for i in n_hunts:
			for idle_side in 2:
				var h := _hunt(1 + i * 17, t, idle_side)
				if h["killed"]:
					killed += 1
					times.append(float(h["t"]))
				if h["suicide"]:
					suicides += 1
		times.sort()
		var med := 0.0 if times.is_empty() else times[times.size() / 2]
		print("  %-9s kills %2d/%2d (%3.0f%%)   median %5.1f s   hunter died %d"
			% [NAMES[t], killed, n_hunts * 2, 100.0 * killed / (n_hunts * 2),
			med, suicides])
	print("")

	# 4b. WHERE THE PARITY LIVES. A cell of the ladder is one number and it hides
	# the two very different games inside it: the duels the KINGS decided and the
	# duels the WYRM did. A tier gap that exists in the first and vanishes in the
	# second is a gap being drowned by a clock, not a gap that is missing.
	var split_pairs: Array = [] if quick else [
		[AI.Difficulty.MASTER, AI.Difficulty.SEASONED],
		[AI.Difficulty.SEASONED, AI.Difficulty.CASUAL],
		[AI.Difficulty.MASTER, AI.Difficulty.CASUAL]]
	if not quick:
		print("SPLIT   each pairing's win rate, duels the kings decided vs the wyrm's")
	for pair in split_pairs:
		var kings_w := 0
		var kings_n := 0
		var wyrm_w := 0
		var wyrm_n := 0
		for i in n_seeds:
			var sv := 1000 + i * 131
			for orient in 2:
				var a: int = pair[0] if orient == 0 else pair[1]
				var b: int = pair[1] if orient == 0 else pair[0]
				var d := _duel(sv, a, b)
				var won: bool = (d["winner"] == 0) if orient == 0 else (d["winner"] == 1)
				if d["dragon"]:
					wyrm_n += 1
					if won:
						wyrm_w += 1
				else:
					kings_n += 1
					if won:
						kings_w += 1
		print("  %-9s vs %-9s  kings %2d/%-3d (%3.0f%%)   wyrm %2d/%-3d (%3.0f%%)"
			% [NAMES[pair[0]], NAMES[pair[1]],
			kings_w, kings_n, 100.0 * kings_w / maxi(kings_n, 1),
			wyrm_w, wyrm_n, 100.0 * wyrm_w / maxi(wyrm_n, 1)])
	print("")

	# 5. THE CHRONICLE.
	print("CHRONICLE  how each tier's kings ended, across every ladder duel")
	for t in TIERS:
		var f: Dictionary = fates[t]
		var tot: int = f["alive"] + f["self"] + f["rival"] + f["wyrm"]
		print("  %-9s survived %3d (%2.0f%%)  own jar %3d (%2.0f%%)  rival %3d (%2.0f%%)  wyrm %3d (%2.0f%%)"
			% [NAMES[t], f["alive"], 100.0 * f["alive"] / maxi(tot, 1),
			f["self"], 100.0 * f["self"] / maxi(tot, 1),
			f["rival"], 100.0 * f["rival"] / maxi(tot, 1),
			f["wyrm"], 100.0 * f["wyrm"] / maxi(tot, 1)])
	print("")
	print("%d ladder duels, %d woke the dragon (%.0f%%), %.1f s of wall clock"
		% [duels, dragon, 100.0 * dragon / maxi(duels, 1),
		(Time.get_ticks_msec() - t0) / 1000.0])
	quit(0)
