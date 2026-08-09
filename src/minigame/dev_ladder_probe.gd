extends SceneTree
## Diagnostic (not a gate): the Trial-by-Fire tier ladder and spawn-corner
## fairness, measured over enough matches to mean something. Both orientations
## are played for every pairing, so a corner advantage cancels out of the tier
## numbers instead of hiding inside them.
const Grid := preload("res://src/minigame/blast_grid.gd")
const AI := preload("res://src/minigame/king_ai.gd")
const DT := 1.0 / 60.0
const N := 40

func _crates(sv: int) -> Array:
	var r := RandomNumberGenerator.new(); r.seed = sv
	var out: Array = []
	for y in 8:
		for x in 8:
			if r.randf() < 0.42: out.append(Vector2i(x, y))
	return out

func _run(sv: int, ta: int, tb: int) -> int:
	var g: Grid = Grid.new()
	g.setup({"seed": sv, "crates": _crates(sv), "sudden_death_at": 20.0,
		"ring_interval": 0.28, "fuse_sec": 1.6})
	var brains := [AI.new(ta, sv + 1), AI.new(tb, sv + 2)]
	var ticks := 0
	while ticks < 4000 and not g.is_over():
		for n in 2:
			var side: int = n if ticks % 2 == 0 else 1 - n
			var act: Dictionary = brains[side].decide(g, side, DT)
			if act.has("keg"): g.place_keg(side)
			elif act.has("step"): g.request_step(side, act["step"])
		g.tick(DT); ticks += 1
	return g.winner()

func _initialize() -> void:
	var tiers := [AI.Difficulty.CASUAL, AI.Difficulty.SEASONED, AI.Difficulty.MASTER]
	var nm := {AI.Difficulty.CASUAL: "Casual", AI.Difficulty.SEASONED: "Seasoned",
		AI.Difficulty.MASTER: "Master"}
	# corner fairness: same tier both sides, count wins by CORNER
	var c00 := 0
	for i in N * 2:
		if _run(500 + i * 97, AI.Difficulty.SEASONED, AI.Difficulty.SEASONED) == 0:
			c00 += 1
	print("corner (0,0) wins %d/%d (%.0f%%) in Seasoned mirrors" % [c00, N * 2, 100.0 * c00 / (N * 2)])
	print("")
	print("head to head, %d seeds x 2 orientations — ROW tier's win rate" % N)
	for a in tiers:
		var line := "  %-9s" % nm[a]
		for b in tiers:
			var w := 0
			for i in N:
				if _run(1000 + i * 131, a, b) == 0: w += 1     # A as side 0
				if _run(1000 + i * 131, b, a) == 1: w += 1     # A as side 1
			line += "  %-10s" % ("%.0f%%" % (100.0 * w / (N * 2)))
		print(line)
	quit(0)
