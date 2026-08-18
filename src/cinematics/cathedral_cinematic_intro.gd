class_name CathedralCinematicIntro
extends Node3D
## CathedralCinematicIntro — AAA Nintendo/Zelda-quality opening cinematic.
## Fly-in from the exterior starry night sky, following the dragon as it swoops
## through the twin spires, enters the grand portal, glides down the soaring vaulted nave,
## perches gracefully beside the golden pipe organ with a triumphant roar, and
## delivers the camera smoothly onto the chessboard ready for battle.

signal intro_completed

const DragonRigScript := preload("res://src/cinematics/dragon_rig.gd")
const AdaptiveScaleScript := preload("res://src/ui/adaptive_scale.gd")

var _cam: Camera3D = null
var _camera_rig: Node = null
var _dragon_rig: DragonRig = null
var _dragon_root: Node3D = null
var _ui_layer: CanvasLayer = null
var _top_bar: ColorRect = null
var _bottom_bar: ColorRect = null
var _location_card: Control = null

var _is_running: bool = false
var _elapsed: float = 0.0
var _skipped: bool = false
var _original_cam_transform: Transform3D


func start_cinematic(game_cam: Camera3D) -> void:
	_cam = game_cam
	_original_cam_transform = _cam.global_transform
	_camera_rig = _cam.get_parent()
	if _camera_rig != null:
		_camera_rig.set_process(false)
		_camera_rig.set_process_unhandled_input(false)

	_is_running = true
	_elapsed = 0.0

	_build_cinematic_ui()
	_spawn_cinematic_dragon()
	set_process(true)
	set_process_unhandled_input(true)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_running:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and (event.keycode == KEY_SPACE or event.keycode == KEY_ESCAPE or event.keycode == KEY_ENTER)):
		_skip_cinematic()
		get_viewport().set_input_as_handled()


func _build_cinematic_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 110
	add_child(_ui_layer)

	# 1. Cinematic Letterbox Bars
	_top_bar = ColorRect.new()
	_top_bar.color = Color.BLACK
	_top_bar.custom_minimum_size = Vector2(0, 75)
	_top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_ui_layer.add_child(_top_bar)

	_bottom_bar = ColorRect.new()
	_bottom_bar.color = Color.BLACK
	_bottom_bar.custom_minimum_size = Vector2(0, 75)
	_bottom_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_ui_layer.add_child(_bottom_bar)

	# 2. Zelda Location Banner (Bottom-Left)
	_location_card = Control.new()
	_location_card.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_location_card.offset_left = 60
	_location_card.offset_bottom = -95
	_location_card.modulate.a = 0.0
	_ui_layer.add_child(_location_card)

	var loc_vbox := VBoxContainer.new()
	loc_vbox.add_theme_constant_override("separation", 2)
	_location_card.add_child(loc_vbox)

	var loc_title := Label.new()
	loc_title.text = "SANCTUM GOTHIC CATHEDRAL"
	loc_title.add_theme_font_size_override("font_size", 24)
	loc_title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	loc_title.add_theme_color_override("font_outline_color", Color.BLACK)
	loc_title.add_theme_constant_override("outline_size", 8)
	loc_vbox.add_child(loc_title)

	var loc_sub := Label.new()
	loc_sub.text = "High Seat of the Nine Hauses • Imperial Choir Loft"
	loc_sub.add_theme_font_size_override("font_size", 14)
	loc_sub.add_theme_color_override("font_color", Color(0.85, 0.82, 0.78))
	loc_sub.add_theme_color_override("font_outline_color", Color.BLACK)
	loc_sub.add_theme_constant_override("outline_size", 4)
	loc_vbox.add_child(loc_sub)

	var skip_lbl := Label.new()
	skip_lbl.text = "Press [ Space / Esc ] to Skip Intro"
	skip_lbl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	skip_lbl.offset_right = -36
	skip_lbl.offset_bottom = -82
	skip_lbl.add_theme_font_size_override("font_size", 12)
	skip_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65, 0.8))
	_ui_layer.add_child(skip_lbl)


func _spawn_cinematic_dragon() -> void:
	_dragon_root = Node3D.new()
	_dragon_root.name = "CinematicDragonRoot"
	add_child(_dragon_root)

	_dragon_rig = DragonRigScript.new()
	_dragon_rig.scale = Vector3.ONE * 1.55
	_dragon_root.add_child(_dragon_rig)
	_dragon_rig.play_loop("Fast_Flying", 1.25)


func _process(delta: float) -> void:
	if not _is_running or _skipped:
		return
	_elapsed += delta

	# ── 6-Phase Cinematic Timeline ───────────────────────────────────────────
	if _elapsed < 3.5:
		# Phase 1: High Sky Exterior Spires Fly-By (0.0s - 3.5s)
		var t := _elapsed / 3.5
		var cam_start := Vector3(-22.0, 42.0, -48.0)
		var cam_end := Vector3(-7.0, 18.0, -32.0)
		_cam.global_position = cam_start.lerp(cam_end, ease(t, -1.8))
		_cam.look_at(Vector3(0.0, 22.0, -22.0), Vector3.UP)

		# Dragon dives from the night sky between the spires towards the grand portal
		var d_start := Vector3(-18.0, 45.0, -42.0)
		var d_end := Vector3(0.0, 4.5, -24.0)
		_dragon_root.global_position = d_start.lerp(d_end, ease(t, 1.35))
		_dragon_root.look_at(_dragon_root.global_position + Vector3(0.38, -0.52, 1.0).normalized(), Vector3.UP)
		_dragon_root.rotation_degrees.z = -24.0 * (1.0 - t)

		# Fade in location card
		if _location_card != null:
			_location_card.modulate.a = clampf(t * 2.0, 0.0, 1.0)

	elif _elapsed < 7.0:
		# Phase 2: Grand Portal Entry & Vaulted Nave Glide (3.5s - 7.0s)
		var t := (_elapsed - 3.5) / 3.5
		var d_start := Vector3(0.0, 4.5, -24.0)
		var d_end := Vector3(0.0, 8.2, 6.0)
		_dragon_root.global_position = d_start.lerp(d_end, t)
		_dragon_root.look_at(_dragon_root.global_position + Vector3(0.0, 0.1, 1.0), Vector3.UP)

		if _dragon_rig.anim != null and _dragon_rig.anim.current_animation != "Glide":
			_dragon_rig.play_loop("Glide", 1.0)

		# Camera tracks behind dragon down the aisle
		_cam.global_position = _dragon_root.global_position + Vector3(0.0, 3.2, -6.8)
		_cam.look_at(_dragon_root.global_position + Vector3(0.0, 0.4, 4.2), Vector3.UP)

	elif _elapsed < 10.0:
		# Phase 3: Arc Up to Choir Loft & Golden Pipe Organ Perch (7.0s - 10.0s)
		var t := (_elapsed - 7.0) / 3.0
		var d_start := Vector3(0.0, 8.2, 6.0)
		var d_mid := Vector3(7.2, 13.5, -6.0)
		var d_perch := Vector3(0.0, 7.2, -18.5)
		
		var q1 := d_start.lerp(d_mid, t)
		var q2 := d_mid.lerp(d_perch, t)
		_dragon_root.global_position = q1.lerp(q2, t)
		_dragon_root.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)

		if t > 0.85 and _dragon_rig.anim != null and _dragon_rig.anim.current_animation != "Roar":
			_dragon_rig.play_once("Roar", 1.15)

		# Dynamic low angle capturing dragon landing before golden pipes
		_cam.global_position = Vector3(-6.0, 10.2, -9.0).lerp(Vector3(0.0, 8.8, -12.0), t)
		_cam.look_at(_dragon_root.global_position + Vector3(0, 0.9, 0), Vector3.UP)

	elif _elapsed < 12.0:
		# Phase 4: Smooth Swoop to Gameplay Chessboard (10.0s - 12.0s)
		var t := (_elapsed - 10.0) / 2.0
		var ease_t := ease(t, -2.0)

		var cam_start_pos := Vector3(0.0, 8.8, -12.0)
		_cam.global_position = cam_start_pos.lerp(_original_cam_transform.origin, ease_t)
		
		var target_rot := _original_cam_transform.basis
		var current_rot := Basis.looking_at(Vector3.ZERO - _cam.global_position, Vector3.UP)
		_cam.global_basis = current_rot.slerp(target_rot, ease_t)

		if _top_bar != null:
			_top_bar.custom_minimum_size.y = 75.0 * (1.0 - ease_t)
		if _bottom_bar != null:
			_bottom_bar.custom_minimum_size.y = 75.0 * (1.0 - ease_t)
		if _location_card != null:
			_location_card.modulate.a = 1.0 - ease_t

	else:
		_finish_cinematic()


func _skip_cinematic() -> void:
	if _skipped:
		return
	_skipped = true
	_finish_cinematic()


func _finish_cinematic() -> void:
	_is_running = false
	set_process(false)
	set_process_unhandled_input(false)

	if _cam != null:
		_cam.global_transform = _original_cam_transform

	if _camera_rig != null:
		_camera_rig.set_process(true)
		_camera_rig.set_process_unhandled_input(true)

	if _ui_layer != null:
		_ui_layer.queue_free()
		_ui_layer = null

	if _dragon_root != null:
		_dragon_root.global_position = Vector3(0.0, 7.2, -18.5)
		_dragon_root.look_at(Vector3(0.0, 0.5, 0.0), Vector3.UP)
		if _dragon_rig != null:
			_dragon_rig.play_loop("Idle", 0.9)

	intro_completed.emit()
