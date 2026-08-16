extends SceneTree

func _init() -> void:
	var w := 512
	var h := 512
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var frost_silver := Color(0.88, 0.94, 0.98, 1.0)
	var frost_cyan := Color(0.35, 0.82, 0.94, 1.0)
	var fjord_dark := Color(0.08, 0.16, 0.24, 0.95)
	var rune_amber := Color(0.95, 0.55, 0.15, 0.9)

	var center := Vector2(256.0, 256.0)

	# 1. Outer Runic Shield Ring
	var r_outer := 230.0
	var r_inner := 216.0
	for y in range(h):
		for x in range(w):
			var pt := Vector2(x + 0.5, y + 0.5)
			var dist := pt.distance_to(center)
			if dist <= r_outer and dist >= r_inner:
				var angle := (pt - center).angle()
				var notch := sin(angle * 16.0)
				var c := frost_silver if notch > 0.3 else frost_cyan
				img.set_pixel(x, y, c)

	# 2. Three Interlocking Valknut Triangles
	# Triangle 1 (Top pointing): center (256, 170)
	# Triangle 2 (Bottom-left): center (200, 290)
	# Triangle 3 (Bottom-right): center (312, 290)
	var size := 95.0
	var h_tri := size * (sqrt(3.0) / 2.0)

	var tri_centers = [
		Vector2(256.0, 185.0),
		Vector2(195.0, 290.0),
		Vector2(317.0, 290.0)
	]

	for tc in tri_centers:
		var tc_v: Vector2 = tc
		var v1: Vector2 = tc_v + Vector2(0.0, -h_tri * (2.0/3.0))
		var v2: Vector2 = tc_v + Vector2(-size * 0.5, h_tri * (1.0/3.0))
		var v3: Vector2 = tc_v + Vector2(size * 0.5, h_tri * (1.0/3.0))

		_draw_thick_triangle(img, v1, v2, v3, 10.0, frost_silver, frost_cyan, fjord_dark)

	# 3. Twin Ravens flanking top
	# Left Raven (Huginn)
	_draw_raven(img, Vector2(110.0, 150.0), -1.0, rune_amber)
	# Right Raven (Muninn)
	_draw_raven(img, Vector2(402.0, 150.0), 1.0, rune_amber)

	# Save PNG
	var path := "res://assets/sigils/vinterdread.png"
	var err := img.save_png(ProjectSettings.globalize_path(path))
	if err == OK:
		print("Successfully generated Valknut Sigil Banner -> %s" % path)
	else:
		print("Failed to save sigil: %d" % err)
	quit(0)


func _draw_thick_triangle(img: Image, v1: Vector2, v2: Vector2, v3: Vector2, thick: float, c_fill: Color, c_rim: Color, c_core: Color) -> void:
	var bounds_min := Vector2(minf(v1.x, minf(v2.x, v3.x)) - thick - 4, minf(v1.y, minf(v2.y, v3.y)) - thick - 4)
	var bounds_max := Vector2(maxf(v1.x, maxf(v2.x, v3.x)) + thick + 4, maxf(v1.y, maxf(v2.y, v3.y)) + thick + 4)

	var x_start := int(clampf(bounds_min.x, 0, img.get_width() - 1))
	var x_end := int(clampf(bounds_max.x, 0, img.get_width() - 1))
	var y_start := int(clampf(bounds_min.y, 0, img.get_height() - 1))
	var y_end := int(clampf(bounds_max.y, 0, img.get_height() - 1))

	for y in range(y_start, y_end + 1):
		for x in range(x_start, x_end + 1):
			var pt := Vector2(x + 0.5, y + 0.5)
			var d1 := _dist_to_segment(pt, v1, v2)
			var d2 := _dist_to_segment(pt, v2, v3)
			var d3 := _dist_to_segment(pt, v3, v1)
			var d_edge := minf(d1, minf(d2, d3))

			if d_edge <= thick * 0.5:
				var col: Color
				if d_edge < thick * 0.2:
					col = c_fill
				elif d_edge < thick * 0.4:
					col = c_rim
				else:
					col = c_core
				img.set_pixel(x, y, col)


func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var ap := p - a
	var t := clampf(ap.dot(ab) / ab.length_squared(), 0.0, 1.0)
	var closest := a + ab * t
	return (p - closest).length()


func _draw_raven(img: Image, pos: Vector2, dir: float, col: Color) -> void:
	# Stylized Norse raven silhouette
	for dy in range(-30, 30):
		for dx in range(-40, 40):
			var px := int(pos.x + dx * dir)
			var py := int(pos.y + dy)
			if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
				# Wing and body ellipse curve
				var wing := (dx * 0.8)**2 / 400.0 + (dy - dx*0.3)**2 / 120.0
				var head := (dx - 20)**2 / 60.0 + (dy + 10)**2 / 60.0
				if wing <= 1.0 or head <= 1.0:
					img.set_pixel(px, py, col)
