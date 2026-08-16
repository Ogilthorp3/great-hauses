class_name OpeningCinematic
extends CanvasLayer
## OpeningCinematic — Civilization-Style Epic Opening Sequence for Great Hauses.
## Displays an atmospheric video/cinematic trailer with narration subtitles,
## torchlight fade-ins, and seamless transition to the Hall of Banners.

signal cinematic_completed()

var _video_player: VideoStreamPlayer = null
var _title_label: Label = null
var _subtitle_label: Label = null
var _prompt_label: Label = null
var _fade_rect: ColorRect = null
var _tween: Tween = null
var _audio_player: AudioStreamPlayer = null

const INTRO_VIDEO_PATH := "res://assets/cinematics/opening_intro.ogv"
const GOLD_COLOR := Color(0.95, 0.82, 0.35)


func _ready() -> void:
	layer = 50
	_build_ui()
	_start_playback()


func _build_ui() -> void:
	# Dark cinematic backdrop
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.03, 0.04, 0.06, 1.0)
	add_child(bg)

	# Video Player
	_video_player = VideoStreamPlayer.new()
	_video_player.set_anchors_preset(Control.PRESET_FULL_RECT)
	_video_player.expand = true
	_video_player.loop = false
	_video_player.finished.connect(_on_video_finished)
	add_child(_video_player)

	# Main Title
	_title_label = Label.new()
	_title_label.set_anchors_preset(Control.PRESET_CENTER)
	_title_label.position = Vector2(-300, -80)
	_title_label.custom_minimum_size = Vector2(600, 60)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.text = "G R E A T   H A U S E S"
	_title_label.add_theme_font_size_override("font_size", 36)
	_title_label.add_theme_color_override("font_color", GOLD_COLOR)
	add_child(_title_label)

	# Subtitle / Narration Box
	_subtitle_label = Label.new()
	_subtitle_label.set_anchors_preset(Control.PRESET_CENTER)
	_subtitle_label.position = Vector2(-400, 20)
	_subtitle_label.custom_minimum_size = Vector2(800, 60)
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle_label.add_theme_font_size_override("font_size", 16)
	_subtitle_label.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	_subtitle_label.text = "From the embers of ancient stone, the Great Hauses assemble for battle..."
	add_child(_subtitle_label)

	# Skip prompt
	_prompt_label = Label.new()
	_prompt_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_prompt_label.position = Vector2(0, -60)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 13)
	_prompt_label.add_theme_color_override("font_color", Color(0.65, 0.68, 0.75))
	_prompt_label.text = "[ Press SPACE, ENTER or CLICK to Enter the Hall of Banners ]"
	add_child(_prompt_label)

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

	# Check for video file
	if ResourceLoader.exists(INTRO_VIDEO_PATH):
		var stream = load(INTRO_VIDEO_PATH)
		if stream is VideoStream:
			_title_label.visible = false
			_video_player.stream = stream
			_video_player.play()
			return

	# Cinematic subtitle sequence
	var seq_tween := create_tween()
	seq_tween.tween_interval(1.8)
	seq_tween.tween_callback(func():
		_subtitle_label.text = "Knights clash upon the grand cathedral board under the dragon's watchful gaze..."
	)
	seq_tween.tween_interval(2.2)
	seq_tween.tween_callback(func():
		_subtitle_label.text = "Choose your house. Claim your throne."
	)
	seq_tween.tween_interval(2.0)
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
