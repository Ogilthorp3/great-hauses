class_name OpeningCinematic
extends CanvasLayer
## OpeningCinematic — Civilization-Style Epic Opening Sequence for Great Hauses Chess.
## Displays the cinematic trailer with prominent shimmering Gold typography,
## dramatic narration cards, and smooth transition to the Hall of Banners.

signal cinematic_completed()

var _video_player: VideoStreamPlayer = null
var _title_label: Label = null
var _subtitle_label: Label = null
var _prompt_label: Label = null
var _fade_rect: ColorRect = null
var _tween: Tween = null
var _audio_player: AudioStreamPlayer = null

const INTRO_VIDEO_PATH := "res://assets/cinematics/opening_intro.ogv"
const GOLD_TITLE := Color(1.0, 0.88, 0.42)
const GOLD_SUB := Color(0.92, 0.78, 0.32)
const TEXT_WARM := Color(0.93, 0.90, 0.84)
const OUTLINE_DARK := Color(0.06, 0.04, 0.02, 0.95)


func _ready() -> void:
	layer = 50
	_build_ui()
	_start_playback()


func _build_ui() -> void:
	# Dark cinematic backdrop
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.02, 0.04, 1.0)
	add_child(bg)

	# Video Player
	_video_player = VideoStreamPlayer.new()
	_video_player.set_anchors_preset(Control.PRESET_FULL_RECT)
	_video_player.expand = true
	_video_player.loop = false
	_video_player.finished.connect(_on_video_finished)
	add_child(_video_player)

	# Cinematic Title Overlay Container
	var overlay := VBoxContainer.new()
	overlay.set_anchors_preset(Control.PRESET_CENTER)
	overlay.position = Vector2(-500, -120)
	overlay.custom_minimum_size = Vector2(1000, 240)
	overlay.add_theme_constant_override("separation", 14)
	add_child(overlay)

	# Main Title in BIG GOLD FONT
	_title_label = Label.new()
	_title_label.text = "G R E A T   H A U S E S   C H E S S"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 46)
	_title_label.add_theme_color_override("font_color", GOLD_TITLE)
	_title_label.add_theme_color_override("font_outline_color", OUTLINE_DARK)
	_title_label.add_theme_constant_override("outline_size", 10)
	_title_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_title_label.add_theme_constant_override("shadow_offset_x", 3)
	_title_label.add_theme_constant_override("shadow_offset_y", 4)
	overlay.add_child(_title_label)

	# Subtitle / Motto in Rich Gold
	_subtitle_label = Label.new()
	_subtitle_label.text = "⚔️   NINE BANNERS. ONE THRONE.   ⚔️"
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.add_theme_font_size_override("font_size", 20)
	_subtitle_label.add_theme_color_override("font_color", GOLD_SUB)
	_subtitle_label.add_theme_color_override("font_outline_color", OUTLINE_DARK)
	_subtitle_label.add_theme_constant_override("outline_size", 6)
	overlay.add_child(_subtitle_label)

	# Narrative Lore line
	var lore_label := Label.new()
	lore_label.text = "“From the embers of ancient stone, the armies assemble for war.”"
	lore_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lore_label.add_theme_font_size_override("font_size", 16)
	lore_label.add_theme_color_override("font_color", TEXT_WARM)
	lore_label.add_theme_color_override("font_outline_color", OUTLINE_DARK)
	lore_label.add_theme_constant_override("outline_size", 4)
	overlay.add_child(lore_label)

	# Pulsing skip prompt at bottom
	_prompt_label = Label.new()
	_prompt_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_prompt_label.position = Vector2(0, -65)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 15)
	_prompt_label.add_theme_color_override("font_color", GOLD_SUB)
	_prompt_label.add_theme_color_override("font_outline_color", OUTLINE_DARK)
	_prompt_label.add_theme_constant_override("outline_size", 5)
	_prompt_label.text = "▶  PRESS SPACE, ENTER OR CLICK TO ENTER THE HALL OF BANNERS  ◀"
	add_child(_prompt_label)

	# Subtle breathing pulse on prompt
	var pulse := create_tween().set_loops()
	pulse.tween_property(_prompt_label, "modulate:a", 0.4, 0.9).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(_prompt_label, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE)

	# Audio player for cinematic stinger
	_audio_player = AudioStreamPlayer.new()
	_audio_player.bus = &"Master"
	add_child(_audio_player)

	# Fade overlay
	_fade_rect = ColorRect.new()
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.color = Color(0, 0, 0, 1.0)
	add_child(_fade_rect)


func _start_playback() -> void:
	# Fade in from black
	_tween = create_tween()
	_tween.tween_property(_fade_rect, "color:a", 0.0, 1.0)

	# Play video if present
	if ResourceLoader.exists(INTRO_VIDEO_PATH):
		var stream = load(INTRO_VIDEO_PATH)
		if stream is VideoStream:
			_video_player.stream = stream
			_video_player.play()
			return

	# Fallback timer when no video stream present
	var seq_tween := create_tween()
	seq_tween.tween_interval(5.0)
	seq_tween.tween_callback(finish_cinematic)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_SPACE, KEY_ESCAPE, KEY_ENTER]:
			finish_cinematic()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		finish_cinematic()
		get_viewport().set_input_as_handled()


func _on_video_finished() -> void:
	finish_cinematic()


func finish_cinematic() -> void:
	if _fade_rect.color.a > 0.8:
		return
	if _video_player != null and _video_player.is_playing():
		_video_player.stop()

	var t := create_tween()
	t.tween_property(_fade_rect, "color:a", 1.0, 0.4)
	t.tween_callback(func():
		cinematic_completed.emit()
		queue_free()
	)
