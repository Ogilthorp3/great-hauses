class_name MatchupSplash
extends CanvasLayer
## MatchupSplash — Street Fighter II Cartoon Arcade Versus Loading Screen.
## High-energy comic book split-screen clash with slamming fighter cards,
## speed lines, bouncing VS emblem, comic dialogue banners, and super-combo energy bar.

const GAME_SCENE_PATH := "res://scenes/game.tscn"
const AdaptiveScaleScript := preload("res://src/ui/adaptive_scale.gd")

# Street Fighter Arcade Colors
const ARCADE_YELLOW := Color(1.0, 0.92, 0.22)
const ARCADE_ORANGE := Color(1.0, 0.55, 0.10)
const ARCADE_RED := Color(0.95, 0.18, 0.22)
const ARCADE_CYAN := Color(0.20, 0.85, 1.0)
const COMIC_WHITE := Color(1.0, 1.0, 1.0)
const COMIC_BLACK := Color(0.04, 0.03, 0.05, 1.0)

var _player_house_id: String = "winterfang"
var _rival_house_id: String = "pyre"
var _opponent_info: Dictionary = {}
var _mode_id: String = "tournament"

# UI Node References
var _root_container: Control = null
var _player_box: Control = null
var _rival_box: Control = null
var _vs_container: Control = null
var _vs_label: Label = null
var _fight_banner: Label = null
var _loading_bar: ProgressBar = null
var _status_label: Label = null
var _flash_rect: ColorRect = null

var _is_loading: bool = false
var _target_progress: float = 0.0
var _current_progress: float = 0.0
var _elapsed_time: float = 0.0
var _screen_shake_time: float = 0.0


func setup(player_hid: String, rival_hid: String, opp_info: Dictionary, mode_str: String) -> void:
	_player_house_id = player_hid if not player_hid.is_empty() else "winterfang"
	_rival_house_id = rival_hid if not rival_hid.is_empty() else "pyre"
	_opponent_info = opp_info
	_mode_id = mode_str


func _ready() -> void:
	layer = 100
	_build_arcade_ui()
	_play_street_fighter_slam()
	_start_async_load()


func _build_arcade_ui() -> void:
	_root_container = Control.new()
	_root_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root_container)

	# 1. Base Comic Halftone Dark Backdrop
	var base_bg := ColorRect.new()
	base_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	base_bg.color = COMIC_BLACK
	_root_container.add_child(base_bg)

	# 2. Split Screen Diagonal Halves
	var p_colors := HouseRegistry.get_colors(_player_house_id)
	var r_colors := HouseRegistry.get_colors(_rival_house_id)

	# Left Player Color Field
	var left_field := ColorRect.new()
	left_field.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left_field.custom_minimum_size = Vector2(680, 0)
	left_field.color = (p_colors["primary"] as Color).lerp(Color(0.05, 0.08, 0.15), 0.45)
	_root_container.add_child(left_field)

	# Right Rival Color Field
	var right_field := ColorRect.new()
	right_field.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right_field.custom_minimum_size = Vector2(680, 0)
	right_field.color = (r_colors["primary"] as Color).lerp(Color(0.18, 0.05, 0.05), 0.45)
	_root_container.add_child(right_field)

	# 3. Dynamic Comic Radial Speed Lines
	var speed_grad := Gradient.new()
	speed_grad.set_color(0, Color(1.0, 1.0, 1.0, 0.15))
	speed_grad.set_color(1, Color(0.0, 0.0, 0.0, 0.6))
	var speed_tex := GradientTexture2D.new()
	speed_tex.gradient = speed_grad
	speed_tex.fill = GradientTexture2D.FILL_RADIAL
	speed_tex.fill_from = Vector2(0.5, 0.5)
	speed_tex.fill_to = Vector2(0.5, 1.0)
	var speed_lines := TextureRect.new()
	speed_lines.texture = speed_tex
	speed_lines.stretch_mode = TextureRect.STRETCH_SCALE
	speed_lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_container.add_child(speed_lines)

	# 4. Top Street Fighter Header
	var top_margin := MarginContainer.new()
	top_margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_margin.add_theme_constant_override("margin_top", 24)
	_root_container.add_child(top_margin)

	var top_vbox := VBoxContainer.new()
	top_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	top_vbox.add_theme_constant_override("separation", 2)
	top_margin.add_child(top_vbox)

	var title_lbl := Label.new()
	title_lbl.text = "★  G R E A T   H A U S E S   C H E S S  ★"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(26, self))
	title_lbl.add_theme_color_override("font_color", ARCADE_YELLOW)
	title_lbl.add_theme_color_override("font_outline_color", COMIC_BLACK)
	title_lbl.add_theme_constant_override("outline_size", 10)
	top_vbox.add_child(title_lbl)

	var opp_str: String = str(_opponent_info.get("label", "Seasoned Master")).to_upper()
	var mode_str := "TOURNAMENT BATTLE" if _mode_id == "tournament" else "EXHIBITION CLASH"
	var mode_lbl := Label.new()
	mode_lbl.text = "⚔️  %s  VS  %s  ⚔️" % [mode_str, opp_str]
	mode_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_lbl.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(16, self))
	mode_lbl.add_theme_color_override("font_color", ARCADE_CYAN)
	mode_lbl.add_theme_color_override("font_outline_color", COMIC_BLACK)
	mode_lbl.add_theme_constant_override("outline_size", 6)
	top_vbox.add_child(mode_lbl)

	# 5. Main Versus Arena (Left Player Card, Center VS, Right Rival Card)
	var arena_hsplit := HBoxContainer.new()
	arena_hsplit.set_anchors_preset(Control.PRESET_CENTER)
	arena_hsplit.grow_horizontal = Control.GROW_DIRECTION_BOTH
	arena_hsplit.grow_vertical = Control.GROW_DIRECTION_BOTH
	arena_hsplit.alignment = BoxContainer.ALIGNMENT_CENTER
	arena_hsplit.add_theme_constant_override("separation", 32)
	_root_container.add_child(arena_hsplit)

	# Player 1 Card (Left)
	var p_house := HouseRegistry.get_house(_player_house_id)
	_player_box = _build_fighter_card(p_house, "1P COMMANDER", "WHITE ARMY", ARCADE_YELLOW, true)
	arena_hsplit.add_child(_player_box)

	# Center Street Fighter "VS" Container
	_vs_container = VBoxContainer.new()
	_vs_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_vs_container.custom_minimum_size = Vector2(160, 280)
	_vs_container.add_theme_constant_override("separation", 8)
	arena_hsplit.add_child(_vs_container)

	_vs_label = Label.new()
	_vs_label.text = "V S"
	_vs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vs_label.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(64, self))
	_vs_label.add_theme_color_override("font_color", ARCADE_RED)
	_vs_label.add_theme_color_override("font_outline_color", ARCADE_YELLOW)
	_vs_label.add_theme_constant_override("outline_size", 16)
	_vs_label.add_theme_color_override("font_shadow_color", COMIC_BLACK)
	_vs_label.add_theme_constant_override("shadow_offset_x", 6)
	_vs_label.add_theme_constant_override("shadow_offset_y", 6)
	_vs_container.add_child(_vs_label)

	_fight_banner = Label.new()
	_fight_banner.text = "⚡ FIGHT! ⚡"
	_fight_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fight_banner.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(20, self))
	_fight_banner.add_theme_color_override("font_color", ARCADE_YELLOW)
	_fight_banner.add_theme_color_override("font_outline_color", COMIC_BLACK)
	_fight_banner.add_theme_constant_override("outline_size", 8)
	_vs_container.add_child(_fight_banner)

	# Player 2 / Rival Card (Right)
	var r_house := HouseRegistry.get_house(_rival_house_id)
	_rival_box = _build_fighter_card(r_house, "2P CHALLENGER", "BLACK ARMY", ARCADE_ORANGE, false)
	arena_hsplit.add_child(_rival_box)

	# 6. Bottom Super Combo Loading Gauge
	var bottom_margin := MarginContainer.new()
	bottom_margin.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_margin.add_theme_constant_override("margin_bottom", 36)
	_root_container.add_child(bottom_margin)

	var bottom_vbox := VBoxContainer.new()
	bottom_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_vbox.add_theme_constant_override("separation", 6)
	bottom_margin.add_child(bottom_vbox)

	_status_label = Label.new()
	_status_label.text = "🔥 CHARGING SUPER COMBO METER… 🔥"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(15, self))
	_status_label.add_theme_color_override("font_color", ARCADE_YELLOW)
	_status_label.add_theme_color_override("font_outline_color", COMIC_BLACK)
	_status_label.add_theme_constant_override("outline_size", 6)
	bottom_vbox.add_child(_status_label)

	_loading_bar = ProgressBar.new()
	_loading_bar.custom_minimum_size = Vector2(620, 16)
	_loading_bar.show_percentage = false
	_loading_bar.value = 0.0

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.12, 0.10, 0.12, 0.9)
	bar_bg.border_color = ARCADE_YELLOW
	bar_bg.set_border_width_all(2)
	bar_bg.corner_radius_top_left = 6
	bar_bg.corner_radius_top_right = 6
	bar_bg.corner_radius_bottom_left = 6
	bar_bg.corner_radius_bottom_right = 6
	_loading_bar.add_theme_stylebox_override("background", bar_bg)

	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = ARCADE_YELLOW
	bar_fill.border_color = ARCADE_ORANGE
	bar_fill.set_border_width_all(2)
	bar_fill.corner_radius_top_left = 6
	bar_fill.corner_radius_top_right = 6
	bar_fill.corner_radius_bottom_left = 6
	bar_fill.corner_radius_bottom_right = 6
	_loading_bar.add_theme_stylebox_override("fill", bar_fill)
	bottom_vbox.add_child(_loading_bar)

	# 7. Comic Flash Strobe Curtain
	_flash_rect = ColorRect.new()
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.color = Color(1.0, 1.0, 0.8, 0.9)
	add_child(_flash_rect)


func _build_fighter_card(house: Dictionary, player_tag: String, army_side: String, theme_col: Color, is_left: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 270)

	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.06, 0.05, 0.07, 0.92)
	pstyle.border_color = theme_col
	pstyle.set_border_width_all(4)
	pstyle.set_content_margin_all(16)
	pstyle.corner_radius_top_left = 12
	pstyle.corner_radius_top_right = 12
	pstyle.corner_radius_bottom_left = 12
	pstyle.corner_radius_bottom_right = 12
	panel.add_theme_stylebox_override("panel", pstyle)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	# Arcade Player Tag & Army Side Badge
	var tag_hbox := HBoxContainer.new()
	tag_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	tag_hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(tag_hbox)

	var tag_lbl := Label.new()
	tag_lbl.text = "【 %s 】" % player_tag
	tag_lbl.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(14, self))
	tag_lbl.add_theme_color_override("font_color", theme_col)
	tag_lbl.add_theme_color_override("font_outline_color", COMIC_BLACK)
	tag_lbl.add_theme_constant_override("outline_size", 6)
	tag_hbox.add_child(tag_lbl)

	var army_lbl := Label.new()
	army_lbl.text = "• %s" % army_side
	army_lbl.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(13, self))
	army_lbl.add_theme_color_override("font_color", COMIC_WHITE)
	army_lbl.add_theme_color_override("font_outline_color", COMIC_BLACK)
	army_lbl.add_theme_constant_override("outline_size", 4)
	tag_hbox.add_child(army_lbl)

	# Cartoon Avatar / Crest Image
	var sigil_rect := TextureRect.new()
	sigil_rect.custom_minimum_size = Vector2(92, 92)
	sigil_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sigil_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var sigil_path: String = str(house.get("crest_path", house.get("sigil_path", "")))
	if ResourceLoader.exists(sigil_path):
		sigil_rect.texture = load(sigil_path)
	vbox.add_child(sigil_rect)

	# Giant Arcade House Name
	var name_lbl := Label.new()
	name_lbl.text = str(house.get("name", "Great Haus")).to_upper()
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(24, self))
	name_lbl.add_theme_color_override("font_color", COMIC_WHITE)
	name_lbl.add_theme_color_override("font_outline_color", COMIC_BLACK)
	name_lbl.add_theme_constant_override("outline_size", 8)
	vbox.add_child(name_lbl)

	# Comic Dialogue Motto Bubble
	var motto_box := PanelContainer.new()
	var mstyle := StyleBoxFlat.new()
	mstyle.bg_color = theme_col.lerp(COMIC_BLACK, 0.5)
	mstyle.border_color = theme_col
	mstyle.set_border_width_all(2)
	mstyle.set_content_margin_all(6)
	mstyle.corner_radius_top_left = 6
	mstyle.corner_radius_top_right = 6
	mstyle.corner_radius_bottom_left = 6
	mstyle.corner_radius_bottom_right = 6
	motto_box.add_theme_stylebox_override("panel", mstyle)

	var motto_lbl := Label.new()
	motto_lbl.text = "💬 “%s”" % str(house.get("motto", "Victory or Death!"))
	motto_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	motto_lbl.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(14, self))
	motto_lbl.add_theme_color_override("font_color", ARCADE_YELLOW)
	motto_lbl.add_theme_color_override("font_outline_color", COMIC_BLACK)
	motto_lbl.add_theme_constant_override("outline_size", 5)
	motto_box.add_child(motto_lbl)
	vbox.add_child(motto_box)

	# Seat Lore
	var seat_lbl := Label.new()
	seat_lbl.text = "🏰 %s" % str(house.get("seat", "Ancestral Realm"))
	seat_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seat_lbl.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(12, self))
	seat_lbl.add_theme_color_override("font_color", Color(0.85, 0.82, 0.78))
	vbox.add_child(seat_lbl)

	return panel


func _play_street_fighter_slam() -> void:
	# 1. Comic flash strobe dissipation
	var flash_tw := create_tween()
	flash_tw.tween_property(_flash_rect, "color:a", 0.0, 0.28).set_trans(Tween.TRANS_SINE)

	# 2. Slam in Left and Right Fighter Cards
	_player_box.position.x -= 400
	_player_box.scale = Vector2(0.6, 0.6)
	var p_tw := create_tween().set_parallel(true)
	p_tw.tween_property(_player_box, "position:x", 0.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	p_tw.tween_property(_player_box, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_rival_box.position.x += 400
	_rival_box.scale = Vector2(0.6, 0.6)
	var r_tw := create_tween().set_parallel(true)
	r_tw.tween_property(_rival_box, "position:x", 0.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	r_tw.tween_property(_rival_box, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 3. Drop in the Giant VS Emblem with Bouncy Slam
	_vs_container.position.y -= 300
	_vs_container.scale = Vector2(1.8, 1.8)
	var vs_tw := create_tween().set_parallel(true)
	vs_tw.tween_property(_vs_container, "position:y", 0.0, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	vs_tw.tween_property(_vs_container, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

	# Trigger screen shake impact
	_screen_shake_time = 0.35

	# 4. Continuous Cartoon Bouncy Idle
	var idle_tw := create_tween().set_loops()
	idle_tw.tween_property(_vs_label, "scale", Vector2(1.08, 1.08), 0.3).set_trans(Tween.TRANS_SINE)
	idle_tw.tween_property(_vs_label, "scale", Vector2(0.94, 0.94), 0.3).set_trans(Tween.TRANS_SINE)

	var fight_tw := create_tween().set_loops()
	fight_tw.tween_property(_fight_banner, "modulate:a", 0.3, 0.25).set_trans(Tween.TRANS_SINE)
	fight_tw.tween_property(_fight_banner, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_SINE)


func _start_async_load() -> void:
	_is_loading = true
	set_process(true)


func _process(delta: float) -> void:
	_elapsed_time += delta

	# Comic screen shake
	if _screen_shake_time > 0.0:
		_screen_shake_time -= delta
		var offset := Vector2(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0))
		_root_container.position = offset
	else:
		_root_container.position = Vector2.ZERO

	if not _is_loading:
		return

	_current_progress = clampf((_elapsed_time / 1.35) * 100.0, 0.0, 100.0)
	if _loading_bar != null:
		_loading_bar.value = _current_progress

	if _elapsed_time >= 1.4:
		_is_loading = false
		_complete_transition()


func _complete_transition() -> void:
	if not is_inside_tree() or get_tree() == null:
		return

	set_process(false)
	if _loading_bar != null:
		_loading_bar.value = 100.0
	if _status_label != null:
		_status_label.text = "⚔️ ROUND 1: FIGHT! ⚔️"

	get_tree().change_scene_to_file(GAME_SCENE_PATH)
