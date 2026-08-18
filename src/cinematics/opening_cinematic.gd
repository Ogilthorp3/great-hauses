class_name OpeningCinematic
extends CanvasLayer
## OpeningCinematic — Civilization-Style Epic Opening Sequence for Great Hauses Chess.
## Displays the Sanctum Gothic Cathedral backdrop with gold typography,
## responsive layout, and smooth zero-hitch transition to the Hall of Banners.

signal cinematic_completed()

const INTRO_IMG_PATH := "res://assets/cinematics/opening_cathedral.jpg"
const AdaptiveScaleScript := preload("res://src/ui/adaptive_scale.gd")

const GOLD_TITLE := Color(1.0, 0.88, 0.42)
const GOLD_SUB := Color(0.92, 0.78, 0.32)
const TEXT_WARM := Color(0.94, 0.90, 0.84)
const OUTLINE_DARK := Color(0.04, 0.03, 0.02, 0.95)

var _bg_rect: TextureRect = null
var _prompt_label: Label = null
var _fade_rect: ColorRect = null
var _has_finished: bool = false


func _ready() -> void:
	layer = 80
	_build_ui()
	_start_animation()


func _build_ui() -> void:
	# 1. Base Dark Slate Backdrop
	var base_bg := ColorRect.new()
	base_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	base_bg.color = Color(0.03, 0.025, 0.03, 1.0)
	add_child(base_bg)

	# 2. Cathedral Artwork Image (Full Screen Cover)
	_bg_rect = TextureRect.new()
	_bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	if ResourceLoader.exists(INTRO_IMG_PATH):
		_bg_rect.texture = load(INTRO_IMG_PATH)
	add_child(_bg_rect)

	# 3. Vignette Gradient Overlay
	var vig_grad := Gradient.new()
	vig_grad.set_color(0, Color(0.0, 0.0, 0.0, 0.25))
	vig_grad.set_color(1, Color(0.0, 0.0, 0.0, 0.85))
	var vig_tex := GradientTexture2D.new()
	vig_tex.gradient = vig_grad
	vig_tex.fill = GradientTexture2D.FILL_RADIAL
	vig_tex.fill_from = Vector2(0.5, 0.5)
	vig_tex.fill_to = Vector2(0.5, 1.0)
	var vignette := TextureRect.new()
	vignette.texture = vig_tex
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(vignette)

	# 4. Centered Title & Lore Container
	var center_box := VBoxContainer.new()
	center_box.set_anchors_preset(Control.PRESET_CENTER)
	center_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	center_box.alignment = BoxContainer.ALIGNMENT_CENTER
	center_box.add_theme_constant_override("separation", 14)
	add_child(center_box)

	var title_lbl := Label.new()
	title_lbl.text = "G R E A T   H A U S E S   C H E S S"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(44, self))
	title_lbl.add_theme_color_override("font_color", GOLD_TITLE)
	title_lbl.add_theme_color_override("font_outline_color", OUTLINE_DARK)
	title_lbl.add_theme_constant_override("outline_size", 10)
	title_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	title_lbl.add_theme_constant_override("shadow_offset_x", 3)
	title_lbl.add_theme_constant_override("shadow_offset_y", 4)
	center_box.add_child(title_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = "⚔️   NINE BANNERS. ONE THRONE.   ⚔️"
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(20, self))
	sub_lbl.add_theme_color_override("font_color", GOLD_SUB)
	sub_lbl.add_theme_color_override("font_outline_color", OUTLINE_DARK)
	sub_lbl.add_theme_constant_override("outline_size", 6)
	center_box.add_child(sub_lbl)

	var lore_lbl := Label.new()
	lore_lbl.text = "“In the soaring vaults of the Grand Cathedral, the ancient battle begins.”"
	lore_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lore_lbl.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(16, self))
	lore_lbl.add_theme_color_override("font_color", TEXT_WARM)
	lore_lbl.add_theme_color_override("font_outline_color", OUTLINE_DARK)
	lore_lbl.add_theme_constant_override("outline_size", 4)
	center_box.add_child(lore_lbl)

	# 5. Pulsing Bottom Prompt
	var bottom_box := MarginContainer.new()
	bottom_box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_box.add_theme_constant_override("margin_bottom", 40)
	add_child(bottom_box)

	_prompt_label = Label.new()
	_prompt_label.text = "▶  PRESS SPACE, ENTER OR CLICK TO ENTER THE HALL OF BANNERS  ◀"
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(15, self))
	_prompt_label.add_theme_color_override("font_color", GOLD_SUB)
	_prompt_label.add_theme_color_override("font_outline_color", OUTLINE_DARK)
	_prompt_label.add_theme_constant_override("outline_size", 6)
	bottom_box.add_child(_prompt_label)

	var pulse := create_tween().set_loops()
	pulse.tween_property(_prompt_label, "modulate:a", 0.35, 0.85).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(_prompt_label, "modulate:a", 1.0, 0.85).set_trans(Tween.TRANS_SINE)

	# 6. Fade-In Black Curtain
	_fade_rect = ColorRect.new()
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.color = Color(0, 0, 0, 1.0)
	add_child(_fade_rect)


func _start_animation() -> void:
	var tw := create_tween()
	tw.tween_property(_fade_rect, "color:a", 0.0, 0.8).set_trans(Tween.TRANS_SINE)

	# Subtle Ken Burns zoom on the Cathedral
	var zoom_tw := create_tween()
	zoom_tw.tween_property(_bg_rect, "scale", Vector2(1.06, 1.06), 12.0).set_trans(Tween.TRANS_SINE)

	# Auto-advance after 4.5 seconds if untouched
	var auto_tw := create_tween()
	auto_tw.tween_interval(4.5)
	auto_tw.tween_callback(finish_cinematic)


func _unhandled_input(event: InputEvent) -> void:
	if _has_finished:
		return
	if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed):
		finish_cinematic()
		get_viewport().set_input_as_handled()


func finish_cinematic() -> void:
	if _has_finished:
		return
	_has_finished = true

	var t := create_tween()
	t.tween_property(_fade_rect, "color:a", 1.0, 0.35).set_trans(Tween.TRANS_SINE)
	t.tween_callback(func():
		cinematic_completed.emit()
		queue_free()
	)
