class_name CineCaption
extends CanvasLayer
## The cinematics caption, extracted as a reusable layer for modules that
## may not own a DuelDirector (spectator/ashfall). Same look as the
## director's caption — italic serif, candle-gold, hard shadow, low center —
## so every cinematic line in the game reads as one voice. DuelDirector
## keeps its private copy untouched (its duel flow is off-limits); if the
## styles ever drift, this file is the canonical one.
##
## Wall-clock fade (immune to Engine.time_scale — captions play inside
## slow-mo). show_line() is fire-and-forget; hide_line() is instant.
##
## CLEARING THE SUBJECT (2026-08-09). A lower-third caption is only "out of
## the way" when the thing being filmed is NOT in the lower third — and the
## two best frames in this game put it there: the crowned champion stands on
## the dais at bottom-centre in the throne-room tableau, and the throne itself
## sits under the plate in the ashfall frames. The plate landed square on both
## (critic defect P2b). So the plate now SLIDES: give it world points to keep
## clear of via `avoid_points`, and each frame it picks the nearest horizontal
## placement in its own band that no longer covers them. Nothing to avoid, or
## nothing projecting onto the caption row, means it stays dead centre — the
## default look is unchanged.

## World-space points the plate must not cover (Vector3). Set by the ceremony
## that owns the frame; cleared with an empty array.
var avoid_points: Array = []
## Screen-space breathing room kept between the plate edge and a subject: the
## caption clears the subject's BODY, not the pixel its origin projects to.
var avoid_pad := 34.0
## Half-width (px) of the body a projected point stands for.
var avoid_body := 90.0

var _label: Label
var _fade_id := 0
var _dx := 0.0            # live horizontal slide, smoothed (px from centre)


func _ready() -> void:
	layer = 91   # one above DuelDirector's caption layer (90) — never fight it
	visible = false
	_label = Label.new()
	_label.name = "CaptionLabel"
	var serif := SystemFont.new()
	serif.font_names = PackedStringArray(
		["Didot", "Georgia", "Palatino", "Times New Roman", "serif"])
	serif.font_italic = true
	_label.add_theme_font_override("font", serif)
	_label.add_theme_font_size_override("font_size", 34)
	_label.add_theme_color_override("font_color", Color(0.91, 0.85, 0.68))
	_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Same backing plate + same bottom-sixth anchor as DuelDirector's caption
	# (ISSUES.md #4) — the cinematic voice looks identical wherever it speaks.
	_label.add_theme_stylebox_override("normal", DuelDirector.caption_backing())
	_label.anchor_left = 0.5
	_label.anchor_right = 0.5
	_label.anchor_top = 1.0
	_label.anchor_bottom = 1.0
	_label.offset_top = -160.0
	_label.offset_bottom = -96.0
	_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_label)


func _process(_delta: float) -> void:
	if not visible or _label == null:
		return
	_dx = slide_toward(_label, _dx, avoid_points, get_viewport(),
		avoid_pad, avoid_body)


## THE SLIDE, shared by every cinematic caption in the game (DuelDirector's
## own plate calls this too — one voice, one placement rule).
##
## `label` must be the bottom-anchored, centre-anchored caption Label built
## like the one above: anchor_left == anchor_right == 0.5 with
## GROW_DIRECTION_BOTH, so offset_left == offset_right == dx slides the plate
## dx pixels off frame centre. Returns the new (smoothed) dx and applies it.
static func slide_toward(label: Label, dx: float, avoid: Array,
		vp: Viewport, pad := 34.0, body := 90.0) -> float:
	var want := clear_offset(label, dx, avoid, vp, pad, body)
	# Ease (wall clock via the frame count is close enough for a title card):
	# the ceremony camera moves, and a plate that teleports every frame reads
	# as a glitch, not as a title.
	dx = lerpf(dx, want, 0.18)
	if absf(dx) < 0.5:
		dx = 0.0
	label.offset_left = dx
	label.offset_right = dx
	return dx


## Where the plate WANTS to be (px from frame centre) so it covers none of
## `avoid`. Pure geometry — no state touched — so a test can drive it with a
## hand-built label and camera.
static func clear_offset(label: Label, dx: float, avoid: Array,
		vp: Viewport, pad := 34.0, body := 90.0) -> float:
	if label == null or vp == null or avoid.is_empty():
		return 0.0
	var cam := vp.get_camera_3d()
	if cam == null or not is_instance_valid(cam):
		return 0.0
	var vp_size := vp.get_visible_rect().size
	var rect := label.get_global_rect()
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return dx   # not laid out yet — keep what we had
	# Clearance the plate's CENTRE needs from a subject's centre: half the
	# plate, half the body, and air between them.
	var half := rect.size.x * 0.5 + body + pad
	var min_c := 16.0 + rect.size.x * 0.5
	var max_c := vp_size.x - 16.0 - rect.size.x * 0.5
	if min_c >= max_c:
		return 0.0   # the plate is wider than the frame; centre is all there is
	# Project the subjects that could possibly be under a lower-third plate.
	var subs := PackedFloat32Array()
	for p in avoid:
		if not (p is Vector3):
			continue
		if cam.is_position_behind(p):
			continue
		var s: Vector2 = cam.unproject_position(p)
		if s.y < vp_size.y * 0.5:
			continue   # standing in the upper half — nowhere near the plate
		subs.append(s.x)
	if subs.is_empty():
		return 0.0
	# Each subject forbids an INTERVAL of plate centres. Solve for all of them
	# at once: the answer is the legal centre nearest the frame's own centre.
	#
	# Doing this one subject at a time (push off A, then push off B, …) does
	# not converge — with the champion on the dais and the throne behind him
	# the second push threw the plate back across the first and it settled
	# between them, still on the king's head (measured 2026-08-09: subjects at
	# x 925 and 963, plate centre 983, half-width 238 — on both).
	var cands := PackedFloat32Array([vp_size.x * 0.5])
	for sx in subs:
		cands.append(sx - half)
		cands.append(sx + half)
	var best := vp_size.x * 0.5
	var best_score := -INF
	for c in cands:
		var cc: float = clampf(c, min_c, max_c)
		var nearest := INF
		for sx in subs:
			nearest = minf(nearest, absf(sx - cc))
		# Legal (clears everything) beats illegal; among equals, stay central.
		var score: float = (1.0e6 if nearest >= half - 0.5 else nearest) \
			- absf(cc - vp_size.x * 0.5)
		if score > best_score:
			best_score = score
			best = cc
	return best - vp_size.x * 0.5


func show_line(text: String, fade_sec: float = 0.25) -> void:
	if _label == null:
		return
	_fade_id += 1
	var my_id := _fade_id
	_label.text = text
	_label.modulate = Color(1, 1, 1, 0)
	visible = true
	var t0 := Time.get_ticks_msec()
	while visible and _fade_id == my_id:
		var u := clampf(float(Time.get_ticks_msec() - t0) / (fade_sec * 1000.0), 0.0, 1.0)
		_label.modulate = Color(1, 1, 1, u)
		if u >= 1.0:
			return
		var tree := get_tree()
		if tree == null:
			return
		await tree.process_frame


func hide_line(fade_sec: float = 0.3) -> void:
	## Fades OUT by default (wall clock, slow-mo immune); pass 0.0 for the
	## hard cut a teardown needs.
	_fade_id += 1
	if fade_sec <= 0.0 or _label == null or not visible:
		visible = false
		return
	var my := _fade_id
	var t0 := Time.get_ticks_msec()
	while visible and _fade_id == my:
		var u := clampf(float(Time.get_ticks_msec() - t0) / (fade_sec * 1000.0), 0.0, 1.0)
		_label.modulate = Color(1, 1, 1, 1.0 - u)
		if u >= 1.0:
			visible = false
			return
		var tree := get_tree()
		if tree == null:
			visible = false
			return
		await tree.process_frame
