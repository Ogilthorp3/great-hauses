extends SceneTree
## tools/gen_sigils.gd — procedural heraldic sigil generator.
##
## Renders one 256x256 shield-shaped PNG per Great House into
## assets/sigils/<id>.png. Pure Image-API rasterization of signed distance
## fields — abstract geometric marks in the house colors, zero external art.
##
## Run headless from the project root:
##   /Applications/Godot.app/Contents/MacOS/Godot --path . --headless \
##       -s res://tools/gen_sigils.gd
## Exit code 0 = every sigil written, 1 = any failure.
## Re-run + `--import` + commit the PNGs whenever houses.json colors change.

const SIZE := 256
const OUT_DIR := "res://assets/sigils"
const HOUSES_JSON := "res://src/houses/houses.json"

# Heater-shield silhouette: straight-sided box on top, a two-circle lens
# tapering to the point below. Constants solved so the sides (x = ±0.78 at
# y = 0) meet the point at (0, ~0.95).
const SHIELD_HALF_W := 0.78
const SHIELD_TOP := -0.88
const LENS_C := 0.1885
const LENS_R := 0.9685


func _initialize() -> void:
	var houses := _load_houses()
	if houses.is_empty():
		push_error("gen_sigils: no houses loaded from %s" % HOUSES_JSON)
		quit(1)
		return
	var abs_dir := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var failures := 0
	for house: Dictionary in houses:
		var id := str(house["id"])
		var img := _render_sigil(house)
		var out_path := "%s/%s.png" % [abs_dir, id]
		var err := img.save_png(out_path)
		if err == OK:
			print("SIGIL OK   %-12s (%s) -> %s/%s.png" % [id, house["archetype"], OUT_DIR, id])
		else:
			failures += 1
			push_error("SIGIL FAIL %-12s save_png err=%d" % [id, err])
	print("gen_sigils: %d/%d written" % [houses.size() - failures, houses.size()])
	quit(1 if failures > 0 else 0)


func _load_houses() -> Array:
	var f := FileAccess.open(HOUSES_JSON, FileAccess.READ)
	if f == null:
		return []
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed == null or not parsed is Dictionary:
		return []
	return parsed.get("houses", [])


# -- rendering --------------------------------------------------------------


func _render_sigil(house: Dictionary) -> Image:
	var c: Dictionary = house["colors"]
	var primary := Color.html(c["primary"])
	var secondary := Color.html(c["secondary"])
	var accent := Color.html(c["accent"])
	var layers := _house_layers(str(house["archetype"]), primary, secondary, accent)
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var px := 2.0 / SIZE  # uv units per pixel
	var light_at := Vector2(0.0, -0.2)
	for y in SIZE:
		for x in SIZE:
			var p := Vector2(
				(x + 0.5) / SIZE * 2.0 - 1.0,
				(y + 0.5) / SIZE * 2.0 - 1.0)
			var ds := _sd_shield(p)
			var shield_a := _aa(ds, px)
			if shield_a <= 0.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			# Banner field: vertical falloff + a soft light near the chief.
			var t := clampf((p.y + 1.0) * 0.5, 0.0, 1.0)
			var col := primary.darkened(0.28).lerp(primary.darkened(0.55), t)
			col = col.lightened(maxf(0.0, 1.0 - p.distance_to(light_at) * 1.05) * 0.14)
			# Inset border trim in the accent color.
			var bd := absf(ds + 0.075) - 0.02
			col = col.lerp(accent, _aa(bd, px) * 0.85)
			# The heraldic mark, layer by layer.
			for layer: Dictionary in layers:
				var d := _shapes_dist(p, layer["shapes"])
				col = col.lerp(layer["color"], _aa(d, px))
			col.a = shield_a
			img.set_pixel(x, y, col)
	return img


## Linear antialias over ~2px of SDF distance; 1 fully inside, 0 outside.
func _aa(d: float, px: float) -> float:
	return clampf(0.5 - d / (2.0 * px), 0.0, 1.0)


func _sd_shield(p: Vector2) -> float:
	var q := Vector2(absf(p.x), p.y)
	if p.y <= 0.0:
		var d := Vector2(q.x - SHIELD_HALF_W, SHIELD_TOP - p.y)
		return Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length() + minf(maxf(d.x, d.y), 0.0)
	# Bottom point: intersection of two circles, folded through |x|.
	return q.distance_to(Vector2(-LENS_C, 0.0)) - LENS_R


func _shapes_dist(p: Vector2, shapes: Array) -> float:
	var d := 1e9
	for s: Dictionary in shapes:
		match s["t"]:
			"circle":
				d = minf(d, p.distance_to(s["c"]) - s["r"])
			"seg":
				d = minf(d, _sd_segment(p, s["a"], s["b"]) - s["th"] * 0.5)
			"poly":
				d = minf(d, _sd_polygon(p, s["pts"]))
			"vesica":
				d = minf(d, maxf(
					p.distance_to(s["c1"]) - s["r"],
					p.distance_to(s["c2"]) - s["r"]))
	return d


func _sd_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var pa := p - a
	var ba := b - a
	var h := clampf(pa.dot(ba) / ba.length_squared(), 0.0, 1.0)
	return (pa - ba * h).length()


## Exact signed distance to a simple polygon (iq's winding formulation).
func _sd_polygon(p: Vector2, v: PackedVector2Array) -> float:
	var d := (p - v[0]).length_squared()
	var s := 1.0
	var j := v.size() - 1
	for i in v.size():
		var e := v[j] - v[i]
		var w := p - v[i]
		var b := w - e * clampf(w.dot(e) / e.length_squared(), 0.0, 1.0)
		d = minf(d, b.length_squared())
		var c1 := p.y >= v[i].y
		var c2 := p.y < v[j].y
		var c3 := e.x * w.y > e.y * w.x
		if (c1 and c2 and c3) or (not c1 and not c2 and not c3):
			s = -s
		j = i
	return s * sqrt(d)


# -- shape constructors -----------------------------------------------------


func _cir(cx: float, cy: float, r: float) -> Dictionary:
	return {"t": "circle", "c": Vector2(cx, cy), "r": r}


func _seg(ax: float, ay: float, bx: float, by: float, th: float) -> Dictionary:
	return {"t": "seg", "a": Vector2(ax, ay), "b": Vector2(bx, by), "th": th}


func _poly(pts: Array) -> Dictionary:
	return {"t": "poly", "pts": PackedVector2Array(pts)}


func _vesica(c1: Vector2, c2: Vector2, r: float) -> Dictionary:
	return {"t": "vesica", "c1": c1, "c2": c2, "r": r}


## Tapered radial spike: triangle from radius r0 to a tip at r1.
func _spike(center: Vector2, ang: float, r0: float, r1: float, half_w: float) -> Dictionary:
	var dir := Vector2(cos(ang), sin(ang))
	var perp := Vector2(-dir.y, dir.x)
	return _poly([
		center + dir * r0 + perp * half_w,
		center + dir * r0 - perp * half_w,
		center + dir * r1,
	])


func _rotated(pts: Array, ang: float, off: Vector2) -> Array:
	var out: Array = []
	for v: Vector2 in pts:
		out.append(v.rotated(ang) + off)
	return out


# -- the nine marks ---------------------------------------------------------
# Each returns paint layers: [{color, shapes}]. uv space: x right, y down,
# shield interior roughly x∈[-0.78,0.78], y∈[-0.88,0.95].


func _house_layers(archetype: String, primary: Color, secondary: Color, accent: Color) -> Array:
	match archetype:
		"wolf":
			return _mark_wolf(secondary)
		"lion":
			return _mark_lion(secondary)
		"stag":
			return _mark_stag(secondary)
		"dragon":
			return _mark_dragon(secondary, accent)
		"kraken":
			return _mark_kraken(secondary)
		"rose":
			return _mark_rose(secondary, accent)
		"sun":
			return _mark_sun(secondary, accent)
		"falcon":
			return _mark_falcon(secondary)
		"trout":
			return _mark_trout(secondary, primary)
	push_error("gen_sigils: unknown archetype '%s'" % archetype)
	return []


## Wolf — angular triple-claw chevron rake.
func _mark_wolf(ink: Color) -> Array:
	var shapes: Array = []
	for i in 3:
		var yb := -0.44 + 0.27 * i
		shapes.append(_seg(-0.44, yb, 0.0, yb + 0.20, 0.075))
		shapes.append(_seg(0.0, yb + 0.20, 0.44, yb, 0.075))
	return [{"color": ink, "shapes": shapes}]


## Lion — gold lozenge ringed by a spiked mane.
func _mark_lion(ink: Color) -> Array:
	var c := Vector2(0.0, -0.10)
	var shapes: Array = [
		_poly([Vector2(0.0, -0.34), Vector2(0.21, -0.10), Vector2(0.0, 0.14), Vector2(-0.21, -0.10)]),
	]
	for k in 8:
		shapes.append(_spike(c, k * TAU / 8.0, 0.30, 0.52, 0.05))
	return [{"color": ink, "shapes": shapes}]


## Stag — branching antler rack over a small head wedge.
func _mark_stag(ink: Color) -> Array:
	var shapes: Array = [
		_seg(0.0, 0.30, 0.0, -0.04, 0.06),
		_poly([Vector2(-0.10, 0.30), Vector2(0.10, 0.30), Vector2(0.0, 0.46)]),
	]
	for side in [-1.0, 1.0]:
		shapes.append(_seg(0.0, -0.04, side * 0.30, -0.44, 0.06))
		shapes.append(_seg(side * 0.12, -0.20, side * 0.33, -0.12, 0.055))
		shapes.append(_seg(side * 0.21, -0.33, side * 0.43, -0.30, 0.055))
	return [{"color": ink, "shapes": shapes}]


## Dragon — three-pointed flame fan rising from a single root.
func _mark_dragon(ink: Color, hot: Color) -> Array:
	var b := Vector2(0.0, 0.42)
	var shapes: Array = []
	for ang_deg in [-38.0, 0.0, 38.0]:
		var a := deg_to_rad(ang_deg)
		var dir := Vector2(sin(a), -cos(a))
		var perp := Vector2(-dir.y, dir.x)
		var mid := b + dir * 0.34
		shapes.append(_poly([b, mid + perp * 0.10, b + dir * 0.86, mid - perp * 0.10]))
	return [
		{"color": ink, "shapes": shapes},
		{"color": hot, "shapes": [_cir(0.0, 0.42, 0.07)]},
	]


## Kraken — radial tentacle spokes around a black heart.
func _mark_kraken(ink: Color) -> Array:
	var c := Vector2(0.0, -0.06)
	var shapes: Array = [_cir(c.x, c.y, 0.15)]
	for k in 8:
		shapes.append(_spike(c, k * TAU / 8.0 + TAU / 16.0, 0.17, 0.52, 0.055))
	return [{"color": ink, "shapes": shapes}]


## Rose — six-petal rosette with a bright heart.
func _mark_rose(ink: Color, heart: Color) -> Array:
	var c := Vector2(0.0, -0.05)
	var petals: Array = []
	for k in 6:
		var ang := k * TAU / 6.0 - TAU / 4.0
		var pc := c + Vector2(cos(ang), sin(ang)) * 0.24
		petals.append(_cir(pc.x, pc.y, 0.16))
	return [
		{"color": ink, "shapes": petals},
		{"color": heart, "shapes": [_cir(c.x, c.y, 0.11)]},
	]


## Sun — rayed disc run through by a gold spear.
func _mark_sun(ink: Color, spear: Color) -> Array:
	var c := Vector2(0.0, -0.05)
	var shapes: Array = [_cir(c.x, c.y, 0.20)]
	for k in 12:
		var r1 := 0.52 if k % 2 == 0 else 0.40
		shapes.append(_spike(c, k * TAU / 12.0, 0.23, r1, 0.05))
	var s0 := Vector2(-0.52, 0.44)
	var s1 := Vector2(0.42, -0.44)
	var dir := (s1 - s0).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var spear_shapes: Array = [
		_seg(s0.x, s0.y, s1.x, s1.y, 0.035),
		_poly([s1 + dir * 0.11, s1 + perp * 0.05, s1 - perp * 0.05]),
	]
	return [
		{"color": ink, "shapes": shapes},
		{"color": spear, "shapes": spear_shapes},
	]


## Falcon — twin swept wings over a diamond tail, head to the chief.
func _mark_falcon(ink: Color) -> Array:
	var shapes: Array = [
		_poly([Vector2(0.0, -0.16), Vector2(0.075, 0.04), Vector2(0.0, 0.36), Vector2(-0.075, 0.04)]),
		_cir(0.0, -0.22, 0.065),
	]
	for side in [-1.0, 1.0]:
		shapes.append(_poly([
			Vector2(side * 0.02, 0.02), Vector2(side * 0.54, -0.34), Vector2(side * 0.10, -0.16)]))
		shapes.append(_poly([
			Vector2(side * 0.02, 0.12), Vector2(side * 0.46, -0.10), Vector2(side * 0.08, 0.00)]))
	return [{"color": ink, "shapes": shapes}]


## Trout — leaping fish: vesica body, tail fin, primary-color eye.
func _mark_trout(ink: Color, eye: Color) -> Array:
	var ang := -0.44  # leap up-and-right
	var off := Vector2(0.0, -0.02)
	var body := _vesica(
		Vector2(0.0, -0.30).rotated(ang) + off,
		Vector2(0.0, 0.30).rotated(ang) + off,
		0.45)
	var tail := _poly(_rotated(
		[Vector2(-0.30, 0.0), Vector2(-0.52, -0.15), Vector2(-0.52, 0.15)], ang, off))
	var fin := _poly(_rotated(
		[Vector2(0.02, -0.12), Vector2(0.14, -0.28), Vector2(-0.12, -0.19)], ang, off))
	var eye_c := Vector2(0.19, -0.02).rotated(ang) + off
	return [
		{"color": ink, "shapes": [body, tail, fin]},
		{"color": eye, "shapes": [_cir(eye_c.x, eye_c.y, 0.035)]},
	]
