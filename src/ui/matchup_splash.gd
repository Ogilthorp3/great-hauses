class_name MatchupSplash
extends CanvasLayer
## MatchupSplash — Street Fighter & Punch-Out!! Arcade Versus Presentation.
## Bold heraldic fighter cards with luminous house sigils, royal coat of arms,
## authentic house colors, Tale of the Tape boxing stats, pulsing arcade VS emblem,
## and battle countdown.

const GAME_SCENE_PATH := "res://scenes/game.tscn"
const AdaptiveScaleScript := preload("res://src/ui/adaptive_scale.gd")

# Vibrant Arcade / Punch-Out Palette
const ARCADE_GOLD := Color(1.0, 0.84, 0.0)
const ARCADE_RED := Color(0.95, 0.15, 0.20)
const ARCADE_CYAN := Color(0.2, 0.8, 1.0)
const ARCADE_WHITE := Color(1.0, 1.0, 1.0)
const PUNCH_BG := Color(0.02, 0.02, 0.03, 1.0)

var _player_house_id: String = "winterfang"
var _rival_house_id: String = "goldclaw"
var _opponent_info: Dictionary = {}
var _mode_id: String = "tournament"

# UI Nodes
var _root: Control = null
var _p1_panel: Control = null
var _p2_panel: Control = null
var _vs_node: Control = null
var _vs_label: Label = null
var _fight_label: Label = null
var _meter_bar: ProgressBar = null
var _meter_text: Label = null

var _is_loading: bool = false
var _elapsed: float = 0.0


func setup(p_hid: String, r_hid: String, opp: Dictionary, mode: String) -> void:
	_player_house_id = p_hid if not p_hid.is_empty() else "winterfang"
	_rival_house_id = r_hid if not r_hid.is_empty() else "goldclaw"
	_opponent_info = opp
	_mode_id = mode


func _ready() -> void:
	layer = 120
	_build_ui()
	_play_intro_animation()
	_start_transition()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and event.keycode == KEY_SPACE):
		_proceed_to_game()


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# 1. Dark Vignette Arena Backdrop
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = PUNCH_BG
	_root.add_child(bg)

	# 2. Radial Gold Spotlight
	var grad := Gradient.new()
	grad.set_color(0, Color(0.35, 0.22, 0.08, 0.6))
	grad.set_color(1, Color(0.0, 0.0, 0.0, 0.98))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 1.0)
	var burst := TextureRect.new()
	burst.texture = tex
	burst.stretch_mode = TextureRect.STRETCH_SCALE
	burst.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(burst)

	# 3. Top Header — Championship Title Bar
	var top_vbox := VBoxContainer.new()
	top_vbox.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	top_vbox.add_theme_constant_override("separation", 4)
	top_vbox.offset_top = 22
	_root.add_child(top_vbox)

	var title := Label.new()
	title.text = "★  G R E A T   H A U S E S   C H E S S  ★"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(26, self))
	title.add_theme_color_override("font_color", ARCADE_GOLD)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 10)
	top_vbox.add_child(title)

	var opp_title: String = str(_opponent_info.get("label", "Seasoned Master")).to_upper()
	var mode_title := "CHAMPIONSHIP MATCH" if _mode_id == "tournament" else "EXHIBITION DUEL"
	var subtitle := Label.new()
	subtitle.text = "🥊  TALE OF THE TAPE • %s vs %s  🥊" % [mode_title, opp_title]
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(14, self))
	subtitle.add_theme_color_override("font_color", ARCADE_CYAN)
	subtitle.add_theme_color_override("font_outline_color", Color.BLACK)
	subtitle.add_theme_constant_override("outline_size", 6)
	top_vbox.add_child(subtitle)

	# 4. Arena Main Row (Player 1 Left Fighter, Center VS, Player 2 Right Fighter)
	var arena := HBoxContainer.new()
	arena.set_anchors_preset(Control.PRESET_CENTER)
	arena.grow_horizontal = Control.GROW_DIRECTION_BOTH
	arena.grow_vertical = Control.GROW_DIRECTION_BOTH
	arena.alignment = BoxContainer.ALIGNMENT_CENTER
	arena.add_theme_constant_override("separation", 36)
	_root.add_child(arena)

	# Player 1 Champion Card
	var p_data := HouseRegistry.get_house(_player_house_id)
	_p1_panel = _create_fighter_card(p_data, "1P DEFENDING CHAMPION", "WHITE ARMY", ARCADE_GOLD, true)
	arena.add_child(_p1_panel)

	# Center Punch-Out VS Emblem
	_vs_node = VBoxContainer.new()
	_vs_node.alignment = BoxContainer.ALIGNMENT_CENTER
	_vs_node.custom_minimum_size = Vector2(160, 440)
	arena.add_child(_vs_node)

	_vs_label = Label.new()
	_vs_label.text = "V S"
	_vs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vs_label.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(72, self))
	_vs_label.add_theme_color_override("font_color", ARCADE_RED)
	_vs_label.add_theme_color_override("font_outline_color", ARCADE_GOLD)
	_vs_label.add_theme_constant_override("outline_size", 16)
	_vs_node.add_child(_vs_label)

	_fight_label = Label.new()
	_fight_label.text = "🔔 ROUND 1 🔔"
	_fight_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fight_label.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(18, self))
	_fight_label.add_theme_color_override("font_color", ARCADE_GOLD)
	_fight_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_fight_label.add_theme_constant_override("outline_size", 8)
	_vs_node.add_child(_fight_label)

	var prompt_label := Label.new()
	prompt_label.text = "[ Space / Enter ]"
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(11, self))
	prompt_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_vs_node.add_child(prompt_label)

	# Player 2 Challenger Card
	var r_data := HouseRegistry.get_house(_rival_house_id)
	var opp_elo: String = str(_opponent_info.get("desc", "~1700 Elo"))
	_p2_panel = _create_fighter_card(r_data, "2P TITLE CHALLENGER", "BLACK ARMY", ARCADE_RED, false, opp_elo)
	arena.add_child(_p2_panel)

	# 5. Bottom Super Combo Loading Bar
	var bottom_margin := MarginContainer.new()
	bottom_margin.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_margin.add_theme_constant_override("margin_bottom", 22)
	_root.add_child(bottom_margin)

	var bottom_vbox := VBoxContainer.new()
	bottom_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_vbox.add_theme_constant_override("separation", 6)
	bottom_margin.add_child(bottom_vbox)

	_meter_text = Label.new()
	_meter_text.text = "🔥 CHARGING RING GAUGE… 🔥"
	_meter_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_meter_text.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(13, self))
	_meter_text.add_theme_color_override("font_color", ARCADE_GOLD)
	_meter_text.add_theme_color_override("font_outline_color", Color.BLACK)
	_meter_text.add_theme_constant_override("outline_size", 6)
	bottom_vbox.add_child(_meter_text)

	_meter_bar = ProgressBar.new()
	_meter_bar.custom_minimum_size = Vector2(580, 14)
	_meter_bar.show_percentage = false
	_meter_bar.value = 0.0

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.08, 0.07, 0.09, 0.95)
	bar_bg.border_color = ARCADE_GOLD
	bar_bg.set_border_width_all(2)
	bar_bg.corner_radius_top_left = 6
	bar_bg.corner_radius_top_right = 6
	bar_bg.corner_radius_bottom_left = 6
	bar_bg.corner_radius_bottom_right = 6
	_meter_bar.add_theme_stylebox_override("background", bar_bg)

	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = ARCADE_GOLD
	bar_fill.corner_radius_top_left = 6
	bar_fill.corner_radius_top_right = 6
	bar_fill.corner_radius_bottom_left = 6
	bar_fill.corner_radius_bottom_right = 6
	_meter_bar.add_theme_stylebox_override("fill", bar_fill)
	bottom_vbox.add_child(_meter_bar)


func _create_fighter_card(house: Dictionary, role_tag: String, army: String, border_col: Color, is_p1: bool, extra_stat: String = "") -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(420, 520)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.08, 0.96)
	style.border_color = border_col
	style.set_border_width_all(3)
	style.set_content_margin_all(16)
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 10)
	card.add_child(vbox)

	# 1. Fighter Header Badge
	var tag_lbl := Label.new()
	tag_lbl.text = "【 %s 】" % role_tag
	tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag_lbl.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(13, self))
	tag_lbl.add_theme_color_override("font_color", border_col)
	tag_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	tag_lbl.add_theme_constant_override("outline_size", 5)
	vbox.add_child(tag_lbl)

	# 2. Majestic Heraldic Centerpiece — Ornate Shield & Glowing Sigil
	var emblem_container := CenterContainer.new()
	emblem_container.custom_minimum_size = Vector2(380, 240)
	vbox.add_child(emblem_container)

	# Ornate Shield Background
	var shield_box := PanelContainer.new()
	shield_box.custom_minimum_size = Vector2(240, 240)
	var shield_style := StyleBoxFlat.new()
	
	# Extract House Primary / Secondary Color
	var colors: Dictionary = house.get("colors", {})
	var prim_col := Color.html(str(colors.get("primary", "#dfe7ee")))
	var sec_col := Color.html(str(colors.get("secondary", "#2f4a66")))
	var acc_col := Color.html(str(colors.get("accent", "#8bc4ee")))
	
	shield_style.bg_color = sec_col.lerp(Color.BLACK, 0.45)
	shield_style.border_color = border_col
	shield_style.set_border_width_all(4)
	shield_style.corner_radius_top_left = 120
	shield_style.corner_radius_top_right = 120
	shield_style.corner_radius_bottom_left = 120
	shield_style.corner_radius_bottom_right = 120
	shield_box.add_theme_stylebox_override("panel", shield_style)
	emblem_container.add_child(shield_box)

	var sigil_center := CenterContainer.new()
	sigil_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	shield_box.add_child(sigil_center)

	var sigil_tex := TextureRect.new()
	sigil_tex.custom_minimum_size = Vector2(170, 170)
	sigil_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sigil_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE

	var s_path: String = str(house.get("sigil", ""))
	if s_path.is_empty() or not ResourceLoader.exists(s_path):
		var h_id: String = str(house.get("id", "winterfang"))
		s_path = "res://assets/sigils/%s.png" % h_id

	if ResourceLoader.exists(s_path):
		sigil_tex.texture = load(s_path)
	sigil_center.add_child(sigil_tex)

	# 3. House Name & Archetype Title
	var name_box := VBoxContainer.new()
	name_box.alignment = BoxContainer.ALIGNMENT_CENTER
	name_box.add_theme_constant_override("separation", 2)
	vbox.add_child(name_box)

	var h_name: String = str(house.get("name", "Great Haus")).to_upper()
	var name_lbl := Label.new()
	name_lbl.text = "⚔️  %s  ⚔️" % h_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(20, self))
	name_lbl.add_theme_color_override("font_color", ARCADE_WHITE)
	name_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	name_lbl.add_theme_constant_override("outline_size", 8)
	name_box.add_child(name_lbl)

	var arch_str: String = str(house.get("archetype", "Champion")).capitalize()
	var arch_lbl := Label.new()
	arch_lbl.text = "✦ The %s of %s ✦" % [arch_str, str(house.get("seat", "Sanctum"))]
	arch_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arch_lbl.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(12, self))
	arch_lbl.add_theme_color_override("font_color", acc_col.lerp(Color.WHITE, 0.3))
	arch_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	arch_lbl.add_theme_constant_override("outline_size", 4)
	name_box.add_child(arch_lbl)

	# 4. Tale of the Tape Stats Grid
	var stats_panel := PanelContainer.new()
	var sstyle := StyleBoxFlat.new()
	sstyle.bg_color = Color(0.03, 0.03, 0.04, 0.90)
	sstyle.border_color = border_col.lerp(Color.BLACK, 0.3)
	sstyle.set_border_width_all(1)
	sstyle.set_content_margin_all(10)
	sstyle.corner_radius_top_left = 8
	sstyle.corner_radius_top_right = 8
	sstyle.corner_radius_bottom_left = 8
	sstyle.corner_radius_bottom_right = 8
	stats_panel.add_theme_stylebox_override("panel", sstyle)
	vbox.add_child(stats_panel)

	var stats_vbox := VBoxContainer.new()
	stats_vbox.add_theme_constant_override("separation", 4)
	stats_panel.add_child(stats_vbox)

	var realm_lbl := Label.new()
	realm_lbl.text = "🏰 SEAT: %s   •   ⚔️ %s" % [str(house.get("seat", "High Realm")), army]
	realm_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	realm_lbl.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(11, self))
	realm_lbl.add_theme_color_override("font_color", Color(0.88, 0.86, 0.82))
	stats_vbox.add_child(realm_lbl)

	var motto_lbl := Label.new()
	motto_lbl.text = "💬 “%s”" % str(house.get("motto", "To Victory!"))
	motto_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	motto_lbl.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(12, self))
	motto_lbl.add_theme_color_override("font_color", ARCADE_GOLD)
	motto_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	motto_lbl.add_theme_constant_override("outline_size", 4)
	stats_vbox.add_child(motto_lbl)

	if not extra_stat.is_empty():
		var extra_lbl := Label.new()
		extra_lbl.text = "🎯 RANK: %s" % extra_stat
		extra_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		extra_lbl.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(11, self))
		extra_lbl.add_theme_color_override("font_color", ARCADE_CYAN)
		stats_vbox.add_child(extra_lbl)

	return card


func _play_intro_animation() -> void:
	if _p1_panel != null:
		_p1_panel.modulate.a = 0.0
		_p1_panel.pivot_offset = Vector2(210, 260)
		_p1_panel.scale = Vector2(0.7, 0.7)
		var tw1 := create_tween()
		tw1.set_parallel(true)
		tw1.tween_property(_p1_panel, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw1.tween_property(_p1_panel, "modulate:a", 1.0, 0.25)

	if _p2_panel != null:
		_p2_panel.modulate.a = 0.0
		_p2_panel.pivot_offset = Vector2(210, 260)
		_p2_panel.scale = Vector2(0.7, 0.7)
		var tw2 := create_tween()
		tw2.set_parallel(true)
		tw2.tween_property(_p2_panel, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw2.tween_property(_p2_panel, "modulate:a", 1.0, 0.25)

	if _vs_label != null:
		_vs_label.pivot_offset = Vector2(80, 40)
		_vs_label.scale = Vector2.ONE * 2.8
		var tw_vs := create_tween()
		tw_vs.tween_property(_vs_label, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if not _is_loading:
		return
	_elapsed += delta
	var progress := clampf(_elapsed / 2.2, 0.0, 1.0)
	if _meter_bar != null:
		_meter_bar.value = progress * 100.0

	# Pulse VS Label
	if _vs_label != null:
		var pulse := 1.0 + 0.08 * sin(_elapsed * 12.0)
		_vs_label.scale = Vector2(pulse, pulse)

	if _elapsed >= 2.4:
		_proceed_to_game()


func _start_transition() -> void:
	_is_loading = true
	_elapsed = 0.0


func _proceed_to_game() -> void:
	if not _is_loading:
		return
	_is_loading = false
	set_process(false)
	var tree := get_tree()
	if tree != null:
		tree.change_scene_to_file(GAME_SCENE_PATH)
