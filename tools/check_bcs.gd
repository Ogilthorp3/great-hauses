extends SceneTree
## check_bcs.gd — prove Image.adjust_bcs can express the linear value remap
## L' = floor + gain * L, so the kit-luminance pass runs in ENGINE code instead
## of a 1M-iteration GDScript loop per atlas.
##
##   contrast  = gain / (gain + 2*floor)
##   brightness= gain + 2*floor
##
## Run: /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
##          -s res://tools/check_bcs.gd

func _initialize() -> void:
	var worst := 0.0
	for pair in [[0.52, 0.85], [0.30, 0.70], [0.0, 1.0], [0.45, 0.60]]:
		worst = maxf(worst, _probe(pair[0], pair[1]))
	print("worst error over all cases = %.5f" % worst)
	quit(0 if worst < 0.01 else 1)


func _probe(floor_v: float, gain: float) -> float:
	var img := Image.create(16, 1, false, Image.FORMAT_RGBA8)
	for x in 16:
		var l := float(x) / 15.0
		img.set_pixel(x, 0, Color(l, l, l, 1.0))
	# Pass A: halve the range about 0.5 -> L1 = 0.25 + 0.5*L (never clamps).
	img.adjust_bcs(1.0, 0.5, 0.0)
	# Pass B: L = 2*L1 - 0.5, so floor + gain*L = (0.5 - 0.5*c) + c*b*L1 with
	#   c = 1 - 2*floor + gain,  b = 2*gain / c.
	var c := 1.0 - 2.0 * floor_v + gain
	img.adjust_bcs(2.0 * gain / c, c, 1.0)
	var worst := 0.0
	for x in 16:
		var l := float(x) / 15.0
		var want: float = clampf(floor_v + gain * l, 0.0, 1.0)
		var got := img.get_pixel(x, 0).r
		worst = maxf(worst, absf(want - got))
	print("floor=%.2f gain=%.2f  worst=%.5f" % [floor_v, gain, worst])
	return worst
