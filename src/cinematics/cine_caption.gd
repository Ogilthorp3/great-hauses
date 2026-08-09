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

var _label: Label
var _fade_id := 0


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
