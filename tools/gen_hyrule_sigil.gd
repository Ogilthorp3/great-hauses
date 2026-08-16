extends SceneTree

func _init() -> void:
	var w := 512
	var h := 512
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var gold_bright := Color(1.0, 0.92, 0.45, 1.0)
	var gold_main := Color(0.95, 0.76, 0.12, 1.0)
	var gold_dark := Color(0.72, 0.52, 0.06, 1.0)
	var gold_outline := Color(0.35, 0.22, 0.02, 0.9)

	var p_top := Vector2(256.0, 80.0)
	var p_left := Vector2(86.0, 410.0)
	var p_right := Vector2(426.0, 410.0)

	var p_mid_left := (p_top + p_left) * 0.5
	var p_mid_right := (p_top + p_right) * 0.5
	var p_mid_bot := (p_left + p_right) * 0.5

	var tri_top := [p_top, p_mid_left, p_mid_right]
	var tri_bl := [p_mid_left, p_left, p_mid_bot]
	var tri_br := [p_mid_right, p_mid_bot, p_right]

	var tris := [tri_top, tri_bl, tri_br]

	for y in range(h):
		for x in range(w):
			var pt := Vector2(x + 0.5, y + 0.5)
			var in_tri := false
			var min_dist := 1e9

			for tri in tris:
				if _point_in_triangle(pt, tri[0], tri[1], tri[2]):
					in_tri = true
					var d := _dist_to_tri_edges(pt, tri[0], tri[1], tri[2])
					min_dist = minf(min_dist, d)

			if in_tri:
				# Beveled gold shading
				var grad := (pt.y - 80.0) / 330.0
				var col: Color
				if min_dist < 3.0:
					col = gold_outline
				elif min_dist < 8.0:
					col = gold_dark
				else:
					var light := (pt.x - 256.0) / 180.0 * 0.2
					col = gold_main.lerp(gold_bright, clampf(0.5 - grad * 0.4 - light, 0.0, 1.0))
				img.set_pixel(x, y, col)
			else:
				# Antialiasing border
				for tri in tris:
					var d_out := _dist_to_tri_edges(pt, tri[0], tri[1], tri[2])
					if d_out < 1.8 and not _point_in_triangle(pt, tri[0], tri[1], tri[2]):
						var alpha := clampf(1.0 - (d_out / 1.8), 0.0, 1.0)
						var curr := img.get_pixel(x, y)
						if alpha > curr.a:
							img.set_pixel(x, y, Color(gold_outline.r, gold_outline.g, gold_outline.b, alpha * 0.7))

	# Save PNG
	var path := "res://assets/sigils/hyrule.png"
	var err := img.save_png(ProjectSettings.globalize_path(path))
	if err == OK:
		print("Successfully generated Zelda Triforce sigil banner -> %s" % path)
	else:
		print("Failed to save sigil, error: %d" % err)
	quit(0)


func _point_in_triangle(pt: Vector2, v1: Vector2, v2: Vector2, v3: Vector2) -> bool:
	var d1 := _sign(pt, v1, v2)
	var d2 := _sign(pt, v2, v3)
	var d3 := _sign(pt, v3, v1)
	var has_neg := (d1 < 0) or (d2 < 0) or (d3 < 0)
	var has_pos := (d1 > 0) or (d2 > 0) or (d3 > 0)
	return not (has_neg and has_pos)


func _sign(p1: Vector2, p2: Vector2, p3: Vector2) -> float:
	return (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)


func _dist_to_tri_edges(pt: Vector2, v1: Vector2, v2: Vector2, v3: Vector2) -> float:
	var d1 := _dist_to_segment(pt, v1, v2)
	var d2 := _dist_to_segment(pt, v2, v3)
	var d3 := _dist_to_segment(pt, v3, v1)
	return minf(d1, minf(d2, d3))


func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var ap := p - a
	var t := clampf(ap.dot(ab) / ab.length_squared(), 0.0, 1.0)
	var closest := a + ab * t
	return (p - closest).length()
