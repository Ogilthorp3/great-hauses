class_name MatchupSplash
extends CanvasLayer
## MatchupSplash — Carmack-Style Instant Asynchronous Versus Loading Splash Screen.
## Eliminates all gray frames and hitching during match start by presenting an
## epic versus presentation of both Great Houses, their sigils, mottos, and armies,
## while background-loading the 3D Gothic Cathedral and 32 pieces in parallel.

const GAME_SCENE_PATH := "res://scenes/game.tscn"
const AdaptiveScaleScript := preload("res://src/ui/adaptive_scale.gd")

const GOLD_TITLE := Color(1.0, 0.88, 0.42)
const GOLD_ACCENT := Color(0.92, 0.74, 0.32)
const TEXT_WARM := Color(0.94, 0.90, 0.84)
const TEXT_DIM := Color(0.68, 0.65, 0.60)
const BG_DARK := Color(0.04, 0.035, 0.04, 1.0)

var _player_house_id: String = "winterfang"
var _rival_house_id: String = "pyre"
var _opponent_info: Dictionary = {}
var _mode_id: String = "tournament"

var _loading_bar: ProgressBar = null
var _status_label: Label = null
var _is_loading: bool = false
var _target_progress: float = 0.0
var _current_progress: float = 0.0
var _game_instance: Node = null


func setup(player_hid: String, rival_hid: String, opp_info: Dictionary, mode_str: String) -> void:
	_player_house_id = player_hid if not player_hid.is_empty() else "winterfang"
	_rival_house_id = rival_hid if not rival_hid.is_empty() else "pyre"
	_opponent_info = opp_info
	_mode_id = mode_str


func _ready() -> void:
	layer = 100
	_build_ui()
	_start_async_load()


func _build_ui() -> void:
	# 1. Full-screen dark velvet backdrop
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = BG_DARK
	add_child(bg)

	# 2. Radial vignette and warm cathedral glow
	var glow_grad := Gradient.new()
	glow_grad.set_color(0, Color(0.28, 0.16, 0.08, 0.65))
	glow_grad.set_color(1, Color(0.0, 0.0, 0.0, 0.85))
	var glow_tex := GradientTexture2D.new()
	glow_tex.gradient = glow_grad
	glow_tex.fill = GradientTexture2D.FILL_RADIAL
	glow_tex.fill_from = Vector2(0.5, 0.45)
	glow_tex.fill_to = Vector2(0.5, 1.0)
	var glow := TextureRect.new()
	glow.texture = glow_tex
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(glow)

	# Main Root Layout
	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_theme_constant_override("separation", 24)
	add_child(main_vbox)

	# Top Match Header
	var header_box := VBoxContainer.new()
	header_box.alignment = BoxContainer.ALIGNMENT_CENTER
	header_box.add_theme_constant_override("separation", 4)
	main_vbox.add_child(header_box)

	var title_lbl := Label.new()
	title_lbl.text = "⚔️  THE WAR FOR THE IRON THRONE  ⚔️"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(28, self))
	title_lbl.add_theme_color_override("font_color", GOLD_TITLE)
	header_box.add_child(title_lbl)

	var opp_label_str: String = str(_opponent_info.get("label", "Seasoned Tactician"))
	var mode_name_str := "Tournament Campaign" if _mode_id == "tournament" else "Exhibition Match"
	var sub_lbl := Label.new()
	sub_lbl.text = "%s  •  Opponent: %s" % [mode_name_str.to_upper(), opp_label_str]
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(16, self))
	sub_lbl.add_theme_color_override("font_color", TEXT_DIM)
	header_box.add_child(sub_lbl)

	# Middle Versus Row (Player House VS Rival House)
	var versus_row := HBoxContainer.new()
	versus_row.alignment = BoxContainer.ALIGNMENT_CENTER
	versus_row.add_theme_constant_override("separation", 36)
	main_vbox.add_child(versus_row)

	# Player House Card (Left)
	var player_house := HouseRegistry.get_house(_player_house_id)
	var player_card := _build_house_card(player_house, "WHITE ARMY (COMMANDER)", true)
	versus_row.add_child(player_card)

	# Center VS Emblem
	var vs_box := VBoxContainer.new()
	vs_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vs_box.custom_minimum_size = Vector2(120, 200)

	var vs_lbl := Label.new()
	vs_lbl.text = "V S"
	vs_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vs_lbl.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(48, self))
	vs_lbl.add_theme_color_override("font_color", GOLD_ACCENT)
	vs_box.add_child(vs_lbl)

	var clash_lbl := Label.new()
	clash_lbl.text = "⚔️"
	clash_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clash_lbl.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(24, self))
	vs_box.add_child(clash_lbl)
	versus_row.add_child(vs_box)

	# Rival House Card (Right)
	var rival_house := HouseRegistry.get_house(_rival_house_id)
	var rival_card := _build_house_card(rival_house, "BLACK ARMY (RIVAL)", false)
	versus_row.add_child(rival_card)

	# Bottom Loading Progress Bar & Status
	var bottom_box := VBoxContainer.new()
	bottom_box.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_box.add_theme_constant_override("separation", 8)
	main_vbox.add_child(bottom_box)

	_status_label = Label.new()
	_status_label.text = "Assembling 32 Champions in the Great Cathedral…"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(15, self))
	_status_label.add_theme_color_override("font_color", GOLD_ACCENT)
	bottom_box.add_child(_status_label)

	_loading_bar = ProgressBar.new()
	_loading_bar.custom_minimum_size = Vector2(560, 10)
	_loading_bar.show_percentage = false
	_loading_bar.value = 0.0
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = GOLD_ACCENT
	bar_style.corner_radius_top_left = 5
	bar_style.corner_radius_top_right = 5
	bar_style.corner_radius_bottom_left = 5
	bar_style.corner_radius_bottom_right = 5
	_loading_bar.add_theme_stylebox_override("fill", bar_style)
	bottom_box.add_child(_loading_bar)


func _build_house_card(house: Dictionary, side_label: String, is_player: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(400, 240)
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.08, 0.07, 0.07, 0.92)
	pstyle.border_color = GOLD_ACCENT if is_player else Color(0.55, 0.45, 0.35)
	pstyle.set_border_width_all(2)
	pstyle.set_content_margin_all(18)
	pstyle.corner_radius_top_left = 10
	pstyle.corner_radius_top_right = 10
	pstyle.corner_radius_bottom_left = 10
	pstyle.corner_radius_bottom_right = 10
	panel.add_theme_stylebox_override("panel", pstyle)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var side_tag := Label.new()
	side_tag.text = side_label
	side_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	side_tag.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(13, self))
	side_tag.add_theme_color_override("font_color", GOLD_ACCENT if is_player else TEXT_DIM)
	vbox.add_child(side_tag)

	# Sigil / Crest Texture
	var sigil_rect := TextureRect.new()
	sigil_rect.custom_minimum_size = Vector2(80, 80)
	sigil_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sigil_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var sigil_path: String = str(house.get("crest_path", house.get("sigil_path", "")))
	if ResourceLoader.exists(sigil_path):
		sigil_rect.texture = load(sigil_path)
	vbox.add_child(sigil_rect)

	# Name
	var name_lbl := Label.new()
	name_lbl.text = str(house.get("name", "Great Haus")).to_upper()
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(22, self))
	name_lbl.add_theme_color_override("font_color", TEXT_WARM)
	vbox.add_child(name_lbl)

	# Motto
	var motto_lbl := Label.new()
	motto_lbl.text = "“%s”" % str(house.get("motto", ""))
	motto_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	motto_lbl.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(15, self))
	motto_lbl.add_theme_color_override("font_color", GOLD_ACCENT)
	vbox.add_child(motto_lbl)

	# Ancestral Seat
	var seat_lbl := Label.new()
	seat_lbl.text = "Seat: %s" % str(house.get("seat", "Ancestral Keep"))
	seat_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seat_lbl.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(13, self))
	seat_lbl.add_theme_color_override("font_color", TEXT_DIM)
	vbox.add_child(seat_lbl)

	# Swatches
	var swatches := HBoxContainer.new()
	swatches.alignment = BoxContainer.ALIGNMENT_CENTER
	swatches.add_theme_constant_override("separation", 6)
	var colors := HouseRegistry.get_colors(house)
	for key in ["primary", "secondary", "accent"]:
		var r := ColorRect.new()
		r.custom_minimum_size = Vector2(28, 12)
		r.color = colors[key]
		swatches.add_child(r)
	vbox.add_child(swatches)

	return panel


func _start_async_load() -> void:
	_is_loading = true
	ResourceLoader.load_threaded_request(GAME_SCENE_PATH, "PackedScene", true)
	set_process(true)


func _process(delta: float) -> void:
	if not _is_loading:
		return

	var progress_arr: Array = []
	var status := ResourceLoader.load_threaded_get_status(GAME_SCENE_PATH, progress_arr)

	if not progress_arr.is_empty():
		_target_progress = float(progress_arr[0]) * 100.0

	_current_progress = lerpf(_current_progress, maxf(_target_progress, 65.0), delta * 5.0)
	if _loading_bar != null:
		_loading_bar.value = _current_progress

	if status == ResourceLoader.THREAD_LOAD_LOADED and _current_progress >= 75.0:
		_is_loading = false
		_complete_transition()
	elif status == ResourceLoader.THREAD_LOAD_FAILED:
		_is_loading = false
		_status_label.text = "Entering Cathedral..."
		get_tree().change_scene_to_file(GAME_SCENE_PATH)


func _complete_transition() -> void:
	if not is_inside_tree() or get_tree() == null:
		return

	if _loading_bar != null:
		_loading_bar.value = 100.0
	if _status_label != null:
		_status_label.text = "Entering the Sanctum Cathedral…"

	var packed_scene: PackedScene = ResourceLoader.load_threaded_get(GAME_SCENE_PATH)
	if packed_scene != null:
		var game = packed_scene.instantiate()
		get_tree().root.add_child(game)
		get_tree().current_scene = game

		# Smooth dissolve directly into 3D Cathedral
		var tween := create_tween()
		tween.tween_property(self, "modulate:a", 0.0, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_callback(queue_free)
	else:
		get_tree().change_scene_to_file(GAME_SCENE_PATH)
