class_name HouseSelect
extends Control
## The Hall of Banners — house-select screen for Great Hauses.
##
## Nine crests hang in a ring in a dark hall. Hover/arrow-key a crest to see
## the house's motto and colors; choose one with double-click or Pledge button,
## then pick an opponent, select war mode, and press Start The War.
## Pure signals out — the integrator owns scene flow.

signal house_chosen(house_id: String)
signal opponent_chosen(opponent: Dictionary)
signal selection_complete(house_id: String, opponent: Dictionary, mode: String)
signal net_host_requested(side: String)
signal net_join_requested(address: String)
signal net_cancelled()

enum Phase { HOUSE, OPPONENT, MODE, DONE, NET }

const RING_RADIUS_FRAC := 0.36    # of the shorter viewport axis
const CREST_SIZE := Vector2(104, 128)
const TEXT_WARM := Color(0.92, 0.88, 0.82)
const TEXT_DIM := Color(0.68, 0.64, 0.58)
const GOLD := Color(0.92, 0.74, 0.32)
const GOLD_HOVER := Color(1.0, 0.85, 0.45)

const OPPONENTS: Array[Dictionary] = [
	{"kind": "engine", "level": "casual", "difficulty": ChessAI.Difficulty.EASY,
		"label": "Engine — Casual", "desc": "A forgiving duel for aspiring commanders"},
	{"kind": "engine", "level": "seasoned", "difficulty": ChessAI.Difficulty.MEDIUM,
		"label": "Engine — Seasoned", "desc": "Tactical battlefield discipline and sharp defense"},
	{"kind": "engine", "level": "master", "difficulty": ChessAI.Difficulty.HARD,
		"label": "Engine — Master", "desc": "Ruthless grandmaster calculation with no mercy"},
	{"kind": "jedi_council", "council_mode": "jedi_council",
		"label": "⚔️ The Jedi Council of Sanctum", "desc": "Consensus of Master Qwen 3.8, Stockfish 18 & Leela Lc0"},
	{"kind": "jedi_council", "council_mode": "qwen_3_8",
		"label": "⚡ Master Qwen 3.8", "desc": "Grand Sage of Tactics: rapid neural calculation and sharp tactical strikes"},
	{"kind": "jedi_council", "council_mode": "stockfish_nnue",
		"label": "👑 Grand Maester (Stockfish 18)", "desc": "Cold, ruthless depth 16+ NNUE calculation with zero mercy"},
	{"kind": "network", "level": "friend", "label": "Play a Friend", "desc": "Direct head-to-head multiplayer duel"},
]

const MODES: Array[Dictionary] = [
	{"id": "tournament", "label": "Begin Tournament",
		"desc": "9-House Single-Elimination campaign for the Iron Throne"},
	{"id": "single", "label": "Single Match",
		"desc": "Direct exhibition battle in the torch-lit Great Hall"},
]

const ZeldaEasterEggsScript := preload("res://src/cinematics/zelda_easter_eggs.gd")
const AdaptiveScaleScript := preload("res://src/ui/adaptive_scale.gd")

var phase := Phase.HOUSE
var selected_house := ""
var selected_opponent: Dictionary = {}
var selected_mode := "tournament"
var _disabled_opponents: Dictionary = {}
var _disabled_modes: Dictionary = {}

var _house_ids: Array[String] = []
var _ring_index := 0
var _opp_index := 0
var _mode_index := 0

var _ring: Control
var _crests: Array[Control] = []
var _preview: VBoxContainer
var _preview_name: Label
var _preview_seat: Label
var _preview_motto: Label
var _preview_swatches: HBoxContainer
var _preview_pledge_btn: Button
var _pledge_banner: PanelContainer

var _opp_panel: PanelContainer
var _opp_buttons: Array[Button] = []
var _opp_confirm_btn: Button

var _mode_panel: PanelContainer
var _mode_buttons: Array[Button] = []
var _mode_summary_label: Label
var _mode_start_btn: Button

var _footer: Label
var _done_label: Label

# -- Play a Friend panel ----------------------------------------------------
var _net_panel: PanelContainer
var _net_choice: VBoxContainer
var _net_host_box: VBoxContainer
var _net_join_box: VBoxContainer
var _net_side_buttons: Array[Button] = []
var _net_side_index := 0
var _net_address: LineEdit
var _net_status_label: Label
var _net_share_label: Label
var _net_prereq_label: Label
var _net_firewall_label: Label
var _net_copy_btn: Button
var _net_copy_note: Label
var _net_cancel_btn: Button
var _net_primary := ""
var _net_busy := false
var net_copied_count := 0
var net_last_copied := ""
var _easter_eggs = null


func _ready() -> void:
	_easter_eggs = ZeldaEasterEggsScript.new()
	add_child(_easter_eggs)
	_house_ids = HouseRegistry.house_ids()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_backdrop()
	_build_title()
	_build_ring()
	_build_preview()
	_build_pledge_banner()
	_build_opp_panel()
	_build_mode_panel()
	_build_net_panel()
	_build_footer()
	_done_label = null
	resized.connect(_layout_ring)
	_set_phase(Phase.HOUSE)
	_set_ring_index(0)
	_layout_ring.call_deferred()


func reset() -> void:
	selected_house = ""
	selected_opponent = {}
	selected_mode = "tournament"
	if _done_label != null:
		_done_label.queue_free()
		_done_label = null
	_set_phase(Phase.HOUSE)
	_set_ring_index(0)


func get_selection() -> Dictionary:
	return {"house": selected_house, "opponent": selected_opponent, "mode": selected_mode}


func set_opponent_enabled(kind: String, enabled: bool, reason := "") -> void:
	if enabled:
		_disabled_opponents.erase(kind)
	else:
		_disabled_opponents[kind] = reason if not reason.is_empty() else "unavailable"
	if not _opp_buttons.is_empty():
		_set_opp_index(_opp_index)


func set_oracle_mode_enabled(oracle_mode: String, enabled: bool, reason := "") -> void:
	if enabled:
		_disabled_modes.erase(oracle_mode)
	else:
		_disabled_modes[oracle_mode] = reason if not reason.is_empty() else "unavailable"
	if not _opp_buttons.is_empty():
		_set_opp_index(_opp_index)


func _opp_disabled(i: int) -> bool:
	return _disabled_opponents.has(str(OPPONENTS[i]["kind"])) \
		or _disabled_modes.has(str(OPPONENTS[i].get("oracle_mode", "")))


func _opp_disabled_reason(i: int) -> String:
	var kind := str(OPPONENTS[i]["kind"])
	if _disabled_opponents.has(kind):
		return str(_disabled_opponents[kind])
	return str(_disabled_modes.get(str(OPPONENTS[i].get("oracle_mode", "")), "unavailable"))


# -- input ------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if phase == Phase.DONE:
		return
	if event is InputEventKey:
		if _easter_eggs != null and _easter_eggs.handle_key_input(event, self):
			accept_event()
			return
	var used := true
	if event.is_action_pressed("ui_cancel"):
		_step_back()
	elif phase == Phase.HOUSE:
		if event.is_action_pressed("ui_left", true):
			_set_ring_index(posmod(_ring_index - 1, _house_ids.size()))
		elif event.is_action_pressed("ui_right", true):
			_set_ring_index(posmod(_ring_index + 1, _house_ids.size()))
		elif event.is_action_pressed("ui_accept"):
			_pledge_current_house()
		else:
			used = false
	elif phase == Phase.OPPONENT:
		if event.is_action_pressed("ui_up", true):
			_set_opp_index(posmod(_opp_index - 1, OPPONENTS.size()))
		elif event.is_action_pressed("ui_down", true):
			_set_opp_index(posmod(_opp_index + 1, OPPONENTS.size()))
		elif event.is_action_pressed("ui_accept"):
			_confirm_opponent()
		else:
			used = false
	elif phase == Phase.MODE:
		if event.is_action_pressed("ui_up", true) or event.is_action_pressed("ui_left", true):
			_set_mode_index(posmod(_mode_index - 1, MODES.size()))
		elif event.is_action_pressed("ui_down", true) or event.is_action_pressed("ui_right", true):
			_set_mode_index(posmod(_mode_index + 1, MODES.size()))
		elif event.is_action_pressed("ui_accept"):
			_start_war()
		else:
			used = false
	else:
		used = false
	if used:
		accept_event()


func _step_back() -> void:
	if phase == Phase.OPPONENT:
		selected_house = ""
		_set_phase(Phase.HOUSE)
	elif phase == Phase.MODE:
		selected_opponent = {}
		_set_phase(Phase.OPPONENT)
	elif phase == Phase.NET:
		net_cancelled.emit()
		_net_busy = false
		selected_opponent = {}
		_set_phase(Phase.OPPONENT)


# -- phase flow -------------------------------------------------------------


func _pledge_current_house() -> void:
	if _house_ids.is_empty():
		return
	_choose_house(_house_ids[_ring_index])


func _choose_house(id: String) -> void:
	selected_house = id
	_ring_index = _house_ids.find(id)
	house_chosen.emit(id)
	
	# Show triumphant pledge banner
	_show_pledge_animation(id)


func _show_pledge_animation(id: String) -> void:
	var house := HouseRegistry.get_house(id)
	var banner_label: Label = _pledge_banner.get_node("VBox/PledgeText")
	var motto_label: Label = _pledge_banner.get_node("VBox/PledgeMotto")
	banner_label.text = "%s PLEDGES TO WAR!" % str(house.get("name", id)).to_upper()
	motto_label.text = "“%s”" % str(house.get("motto", ""))
	
	_preview.visible = false
	_pledge_banner.visible = true
	_pledge_banner.modulate.a = 0.0
	_pledge_banner.scale = Vector2(0.85, 0.85)
	
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_pledge_banner, "modulate:a", 1.0, 0.25)
	tween.tween_property(_pledge_banner, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	await get_tree().create_timer(0.65).timeout
	_pledge_banner.visible = false
	_set_phase(Phase.OPPONENT)


func _on_opponent_pressed(i: int) -> void:
	if phase != Phase.OPPONENT:
		return
	if _opp_disabled(i):
		_set_opp_index(i)
		_footer.text = _opp_disabled_reason(i)
		return
	if _opp_index == i:
		_confirm_opponent()
	else:
		_set_opp_index(i)


func _confirm_opponent() -> void:
	if _opp_disabled(_opp_index):
		_footer.text = _opp_disabled_reason(_opp_index)
		return
	selected_opponent = OPPONENTS[_opp_index].duplicate()
	opponent_chosen.emit(selected_opponent)
	if str(selected_opponent.get("kind", "")) == "network":
		_set_phase(Phase.NET)
		return
	_set_phase(Phase.MODE)


func _on_mode_pressed(i: int) -> void:
	if phase != Phase.MODE:
		return
	_set_mode_index(i)
	_start_war()


func _start_war() -> void:
	selected_mode = str(MODES[_mode_index]["id"])
	_set_phase(Phase.DONE)
	selection_complete.emit(selected_house, selected_opponent, selected_mode)


func _set_phase(p: Phase) -> void:
	phase = p
	_opp_panel.visible = p == Phase.OPPONENT
	_mode_panel.visible = p == Phase.MODE
	_net_panel.visible = p == Phase.NET
	_preview.visible = p == Phase.HOUSE
	_pledge_banner.visible = false
	_refresh_crest_highlights()
	
	if p == Phase.HOUSE:
		_update_preview()
		_footer.text = "Click or Pinch a Haus to Preview · Click Again or Press Pledge Allegiance"
	elif p == Phase.OPPONENT:
		_set_opp_index(_opp_index)
		_footer.text = "Choose your rival · Click Continue to proceed · Esc / Back to return"
	elif p == Phase.MODE:
		_set_mode_index(_mode_index)
		_update_mode_summary()
		_footer.text = "Select Campaign Mode · Press Start The War to begin"
	elif p == Phase.NET:
		_net_show_choice()
		_footer.text = "Host a match, or join your friend's · Esc / Back to return"
	elif p == Phase.DONE:
		_footer.text = ""
		_show_done_banner()


func _update_mode_summary() -> void:
	if _mode_summary_label == null:
		return
	var h_name := str(HouseRegistry.get_house(selected_house).get("name", selected_house))
	var opp_name := str(selected_opponent.get("label", "Unknown Opponent"))
	_mode_summary_label.text = "%s   ⚔️   VS   ⚔️   %s" % [h_name.to_upper(), opp_name.to_upper()]


func _show_done_banner() -> void:
	var house := HouseRegistry.get_house(selected_house)
	_done_label = Label.new()
	_done_label.name = "DoneBanner"
	_done_label.text = "%s RIDES TO WAR.\n“%s”" % [
		str(house.get("name", selected_house)).to_upper(), str(house.get("motto", ""))]
	_done_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_done_label.add_theme_font_size_override("font_size", 34)
	_done_label.add_theme_color_override("font_color", GOLD)
	_done_label.set_anchors_preset(Control.PRESET_CENTER)
	_done_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_done_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_done_label)


# -- selection state --------------------------------------------------------


func _set_ring_index(i: int) -> void:
	_ring_index = i
	_refresh_crest_highlights()
	_update_preview()


func _set_opp_index(i: int) -> void:
	_opp_index = i
	for j in _opp_buttons.size():
		_style_opp_button(_opp_buttons[j], j == i, _opp_disabled(j))


func _set_mode_index(i: int) -> void:
	_mode_index = i
	for j in _mode_buttons.size():
		_style_mode_button(_mode_buttons[j], j == i)


func _style_opp_button(b: Button, active: bool, disabled := false) -> void:
	var title: String = b.get_meta("label")
	var desc: String = b.get_meta("desc")
	if disabled:
		var ash := Color(0.4, 0.38, 0.35)
		b.add_theme_color_override("font_color", ash)
		b.text = "%s  (Offline)" % title
		b.tooltip_text = desc
		return
	
	b.add_theme_color_override("font_color", GOLD if active else TEXT_WARM)
	b.text = ("▶  %s  ◀\n%s" % [title, desc]) if active else ("%s\n%s" % [title, desc])
	
	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.set_content_margin_all(10)
	if active:
		style.bg_color = Color(0.22, 0.16, 0.1, 0.95)
		style.border_color = GOLD
		style.set_border_width_all(2)
	else:
		style.bg_color = Color(0.08, 0.07, 0.07, 0.75)
		style.border_color = Color(0.3, 0.25, 0.2, 0.6)
		style.set_border_width_all(1)
	b.add_theme_stylebox_override("normal", style)
	b.add_theme_stylebox_override("hover", style)
	b.add_theme_stylebox_override("pressed", style)


func _style_mode_button(b: Button, active: bool) -> void:
	var title: String = b.get_meta("label")
	var desc: String = b.get_meta("desc")
	b.add_theme_color_override("font_color", GOLD if active else TEXT_WARM)
	b.text = ("▶  %s  ◀\n%s" % [title, desc]) if active else ("%s\n%s" % [title, desc])
	
	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.set_content_margin_all(14)
	if active:
		style.bg_color = Color(0.25, 0.18, 0.1, 0.95)
		style.border_color = GOLD
		style.set_border_width_all(3)
	else:
		style.bg_color = Color(0.08, 0.07, 0.07, 0.75)
		style.border_color = Color(0.35, 0.3, 0.22, 0.7)
		style.set_border_width_all(1)
	b.add_theme_stylebox_override("normal", style)
	b.add_theme_stylebox_override("hover", style)
	b.add_theme_stylebox_override("pressed", style)


func _refresh_crest_highlights() -> void:
	for i in _crests.size():
		var crest := _crests[i]
		var is_current := i == _ring_index
		var dim := 0.35 if phase != Phase.HOUSE and not is_current else 1.0
		crest.modulate = (Color(1, 1, 1) if is_current else Color(0.55, 0.55, 0.55)) * dim
		var target_scale = Vector2.ONE * (1.26 if is_current else 1.0)
		var tween := create_tween()
		tween.tween_property(crest, "scale", target_scale, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		crest.z_index = 2 if is_current else 0


func _update_preview() -> void:
	if _house_ids.is_empty():
		return
	var house := HouseRegistry.get_house(_house_ids[_ring_index])
	_preview_name.text = str(house.get("name", "?")).to_upper()
	_preview_seat.text = "Ancestral Seat: %s" % str(house.get("seat", "?"))
	_preview_motto.text = "“%s”" % str(house.get("motto", ""))
	var colors := HouseRegistry.get_colors(house)
	var order := ["primary", "secondary", "accent"]
	for i in _preview_swatches.get_child_count():
		(_preview_swatches.get_child(i) as ColorRect).color = colors[order[i]]


# -- construction -----------------------------------------------------------


func _build_backdrop() -> void:
	var base := ColorRect.new()
	base.name = "HallFloor"
	base.color = Color(0.04, 0.035, 0.032)
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)

	var glow_grad := Gradient.new()
	glow_grad.set_color(0, Color(0.26, 0.17, 0.09, 0.6))
	glow_grad.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
	var glow_tex := GradientTexture2D.new()
	glow_tex.gradient = glow_grad
	glow_tex.fill = GradientTexture2D.FILL_RADIAL
	glow_tex.fill_from = Vector2(0.5, 0.45)
	glow_tex.fill_to = Vector2(0.5, 1.0)
	var glow := TextureRect.new()
	glow.name = "TorchGlow"
	glow.texture = glow_tex
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)

	var vig_grad := Gradient.new()
	vig_grad.offsets = PackedFloat32Array([0.0, 0.22, 0.78, 1.0])
	vig_grad.colors = PackedColorArray([
		Color(0, 0, 0, 0.7), Color(0, 0, 0, 0.0),
		Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.8)])
	var vig_tex := GradientTexture2D.new()
	vig_tex.gradient = vig_grad
	vig_tex.fill_from = Vector2(0.5, 0.0)
	vig_tex.fill_to = Vector2(0.5, 1.0)
	var vig := TextureRect.new()
	vig.name = "Vignette"
	vig.texture = vig_tex
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vig)


func _build_title() -> void:
	var header := VBoxContainer.new()
	header.name = "Header"
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.set_anchors_preset(Control.PRESET_CENTER_TOP)
	header.anchor_left = 0.5
	header.anchor_right = 0.5
	header.grow_horizontal = Control.GROW_DIRECTION_BOTH
	header.position.y = 8
	header.add_theme_constant_override("separation", 2)
	add_child(header)

	var mark := TextureRect.new()
	mark.name = "Wordmark"
	mark.texture = load("res://assets/branding/wordmark-great-houses-flat.png")
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.custom_minimum_size = Vector2(360, 42)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(mark)

	var title := Label.new()
	title.name = "Title"
	title.text = "THE HALL OF BANNERS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(22, self))
	title.add_theme_color_override("font_color", TEXT_WARM)
	header.add_child(title)

	var sub := Label.new()
	sub.name = "Subtitle"
	sub.text = "Nine banners. One throne."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(15, self))
	sub.add_theme_color_override("font_color", TEXT_DIM)
	header.add_child(sub)


func _build_ring() -> void:
	_ring = Control.new()
	_ring.name = "CrestRing"
	_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ring)
	for i in _house_ids.size():
		var house := HouseRegistry.get_house(_house_ids[i])
		var crest := _make_crest(house, i)
		_ring.add_child(crest)
		_crests.append(crest)


func _rebuild_ring() -> void:
	if _ring != null:
		for c in _crests:
			if is_instance_valid(c):
				c.queue_free()
		_crests.clear()
		for i in _house_ids.size():
			var house := HouseRegistry.get_house(_house_ids[i])
			var crest := _make_crest(house, i)
			_ring.add_child(crest)
			_crests.append(crest)
		_layout_ring()
		_update_preview()


func _make_crest(house: Dictionary, index: int) -> Control:
	var crest := Control.new()
	crest.name = "Crest_%s" % str(house["id"])
	crest.custom_minimum_size = CREST_SIZE
	crest.size = CREST_SIZE
	crest.pivot_offset = CREST_SIZE * 0.5
	
	var btn := TextureButton.new()
	btn.name = "Sigil"
	btn.texture_normal = HouseRegistry.load_sigil(house)
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.size = Vector2(CREST_SIZE.x, CREST_SIZE.x)
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(_on_crest_pressed.bind(index))
	btn.mouse_entered.connect(_on_crest_hovered.bind(index))
	crest.add_child(btn)

	var label := Label.new()
	label.name = "Name"
	label.text = str(house["name"]).trim_prefix("Haus ")
	label.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(16, self))
	label.add_theme_color_override("font_color", TEXT_WARM)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(0, CREST_SIZE.x + 2)
	label.size = Vector2(CREST_SIZE.x, 24)
	crest.add_child(label)
	return crest


func _on_crest_pressed(index: int) -> void:
	if phase != Phase.HOUSE:
		return
	if _ring_index == index:
		_pledge_current_house()
	else:
		_set_ring_index(index)


func _on_crest_hovered(index: int) -> void:
	if phase != Phase.HOUSE:
		return
	_set_ring_index(index)


func _layout_ring() -> void:
	if _crests.is_empty():
		return
	var top_bound := 125.0
	var bottom_bound := maxf(top_bound + 220.0, size.y - 70.0)
	var center_y := (top_bound + bottom_bound) * 0.5
	var center := Vector2(size.x * 0.5, center_y)

	var max_radius_y := (bottom_bound - top_bound) * 0.5 - CREST_SIZE.y * 0.5 - 6.0
	var max_radius_x := size.x * 0.5 - CREST_SIZE.x * 0.5 - 24.0
	var radius := clampf(minf(max_radius_x, max_radius_y), 110.0, minf(size.x, size.y) * 0.35)

	for i in _crests.size():
		var ang := -TAU / 4.0 + TAU * i / _crests.size()
		var pos := center + Vector2(cos(ang), sin(ang)) * radius - CREST_SIZE * 0.5
		_crests[i].position = pos

	if _preview != null:
		_preview.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_preview.position = center - _preview.size * 0.5


func _build_preview() -> void:
	_preview = VBoxContainer.new()
	_preview.name = "Preview"
	_preview.alignment = BoxContainer.ALIGNMENT_CENTER
	_preview.set_anchors_preset(Control.PRESET_CENTER)
	_preview.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_preview.grow_vertical = Control.GROW_DIRECTION_BOTH
	_preview.position += Vector2(0, 16)
	_preview.add_theme_constant_override("separation", 8)
	add_child(_preview)

	_preview_name = Label.new()
	_preview_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_name.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(30, self))
	_preview_name.add_theme_color_override("font_color", TEXT_WARM)
	_preview.add_child(_preview_name)

	_preview_seat = Label.new()
	_preview_seat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_seat.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(17, self))
	_preview_seat.add_theme_color_override("font_color", TEXT_DIM)
	_preview.add_child(_preview_seat)

	_preview_motto = Label.new()
	_preview_motto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_motto.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(20, self))
	_preview_motto.add_theme_color_override("font_color", GOLD)
	_preview.add_child(_preview_motto)

	_preview_swatches = HBoxContainer.new()
	_preview_swatches.alignment = BoxContainer.ALIGNMENT_CENTER
	_preview_swatches.add_theme_constant_override("separation", 8)
	for i in 3:
		var sw := ColorRect.new()
		sw.custom_minimum_size = Vector2(36, 18)
		_preview_swatches.add_child(sw)
	_preview.add_child(_preview_swatches)

	_preview_pledge_btn = Button.new()
	_preview_pledge_btn.text = "⚔️  PLEDGE ALLEGIANCE  ⚔️"
	_preview_pledge_btn.focus_mode = Control.FOCUS_NONE
	_preview_pledge_btn.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(19, self))
	_preview_pledge_btn.add_theme_color_override("font_color", GOLD)
	_preview_pledge_btn.add_theme_color_override("font_hover_color", GOLD_HOVER)
	
	var bstyle := StyleBoxFlat.new()
	bstyle.bg_color = Color(0.2, 0.15, 0.1, 0.9)
	bstyle.border_color = GOLD
	bstyle.set_border_width_all(2)
	bstyle.corner_radius_top_left = 6
	bstyle.corner_radius_top_right = 6
	bstyle.corner_radius_bottom_left = 6
	bstyle.corner_radius_bottom_right = 6
	bstyle.set_content_margin_all(10)
	_preview_pledge_btn.add_theme_stylebox_override("normal", bstyle)
	_preview_pledge_btn.add_theme_stylebox_override("hover", bstyle)
	_preview_pledge_btn.add_theme_stylebox_override("pressed", bstyle)
	_preview_pledge_btn.pressed.connect(_pledge_current_house)
	_preview.add_child(_preview_pledge_btn)


func _build_pledge_banner() -> void:
	_pledge_banner = PanelContainer.new()
	_pledge_banner.name = "PledgeBanner"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.08, 0.04, 0.98)
	style.border_color = GOLD
	style.set_border_width_all(3)
	style.set_content_margin_all(28)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	_pledge_banner.add_theme_stylebox_override("panel", style)
	_pledge_banner.set_anchors_preset(Control.PRESET_CENTER)
	_pledge_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pledge_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_pledge_banner.visible = false
	
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 10)
	_pledge_banner.add_child(vbox)

	var ptext := Label.new()
	ptext.name = "PledgeText"
	ptext.text = "HAUS WINTERFANG PLEDGES TO WAR!"
	ptext.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ptext.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(28, self))
	ptext.add_theme_color_override("font_color", GOLD)
	vbox.add_child(ptext)

	var pmotto := Label.new()
	pmotto.name = "PledgeMotto"
	pmotto.text = "“The wolf remembers.”"
	pmotto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pmotto.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(20, self))
	pmotto.add_theme_color_override("font_color", TEXT_WARM)
	vbox.add_child(pmotto)

	add_child(_pledge_banner)


func _build_opp_panel() -> void:
	_opp_panel = PanelContainer.new()
	_opp_panel.name = "ChooseOpponent"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.05, 0.96)
	style.border_color = Color(0.65, 0.5, 0.25)
	style.set_border_width_all(2)
	style.set_content_margin_all(24)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	_opp_panel.add_theme_stylebox_override("panel", style)
	_opp_panel.set_anchors_preset(Control.PRESET_CENTER)
	_opp_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_opp_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_opp_panel.visible = false

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	_opp_panel.add_child(root)

	var top_bar := HBoxContainer.new()
	var back_btn := Button.new()
	back_btn.text = "← BACK TO HOUSES"
	back_btn.focus_mode = Control.FOCUS_NONE
	back_btn.add_theme_font_size_override("font_size", 15)
	back_btn.add_theme_color_override("font_color", TEXT_DIM)
	back_btn.pressed.connect(_step_back)
	top_bar.add_child(back_btn)

	var head := Label.new()
	head.text = "CHOOSE YOUR OPPONENT"
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 24)
	head.add_theme_color_override("font_color", TEXT_WARM)
	top_bar.add_child(head)
	root.add_child(top_bar)

	var list_box := VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 6)
	root.add_child(list_box)

	for i in OPPONENTS.size():
		var b := Button.new()
		b.set_meta("label", str(OPPONENTS[i]["label"]))
		b.set_meta("desc", str(OPPONENTS[i].get("desc", "")))
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(560, 48)
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(_on_opponent_pressed.bind(i))
		_style_opp_button(b, i == 0)
		list_box.add_child(b)
		_opp_buttons.append(b)

	_opp_confirm_btn = Button.new()
	_opp_confirm_btn.text = "CONTINUE TO WAR MODE  →"
	_opp_confirm_btn.focus_mode = Control.FOCUS_NONE
	_opp_confirm_btn.custom_minimum_size = Vector2(560, 46)
	_opp_confirm_btn.add_theme_font_size_override("font_size", 20)
	_opp_confirm_btn.add_theme_color_override("font_color", GOLD)
	
	var cstyle := StyleBoxFlat.new()
	cstyle.bg_color = Color(0.2, 0.15, 0.08, 0.95)
	cstyle.border_color = GOLD
	cstyle.set_border_width_all(2)
	cstyle.corner_radius_top_left = 6
	cstyle.corner_radius_top_right = 6
	cstyle.corner_radius_bottom_left = 6
	cstyle.corner_radius_bottom_right = 6
	_opp_confirm_btn.add_theme_stylebox_override("normal", cstyle)
	_opp_confirm_btn.add_theme_stylebox_override("hover", cstyle)
	_opp_confirm_btn.add_theme_stylebox_override("pressed", cstyle)
	_opp_confirm_btn.pressed.connect(_confirm_opponent)
	root.add_child(_opp_confirm_btn)

	add_child(_opp_panel)


func _build_mode_panel() -> void:
	_mode_panel = PanelContainer.new()
	_mode_panel.name = "HowWillYouFight"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.05, 0.96)
	style.border_color = Color(0.65, 0.5, 0.25)
	style.set_border_width_all(2)
	style.set_content_margin_all(26)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	_mode_panel.add_theme_stylebox_override("panel", style)
	_mode_panel.set_anchors_preset(Control.PRESET_CENTER)
	_mode_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_mode_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_mode_panel.visible = false

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	_mode_panel.add_child(root)

	var top_bar := HBoxContainer.new()
	var back_btn := Button.new()
	back_btn.text = "← BACK TO OPPONENTS"
	back_btn.focus_mode = Control.FOCUS_NONE
	back_btn.add_theme_font_size_override("font_size", 15)
	back_btn.add_theme_color_override("font_color", TEXT_DIM)
	back_btn.pressed.connect(_step_back)
	top_bar.add_child(back_btn)

	var head := Label.new()
	head.text = "HOW WILL YOU FIGHT?"
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 24)
	head.add_theme_color_override("font_color", TEXT_WARM)
	top_bar.add_child(head)
	root.add_child(top_bar)

	_mode_summary_label = Label.new()
	_mode_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_summary_label.add_theme_font_size_override("font_size", 18)
	_mode_summary_label.add_theme_color_override("font_color", GOLD)
	root.add_child(_mode_summary_label)

	var list_box := VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 10)
	root.add_child(list_box)

	for i in MODES.size():
		var b := Button.new()
		b.set_meta("label", str(MODES[i]["label"]))
		b.set_meta("desc", str(MODES[i].get("desc", "")))
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(560, 64)
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(_on_mode_pressed.bind(i))
		_style_mode_button(b, i == 0)
		list_box.add_child(b)
		_mode_buttons.append(b)

	_mode_start_btn = Button.new()
	_mode_start_btn.text = "⚔️  START THE WAR  ⚔️"
	_mode_start_btn.focus_mode = Control.FOCUS_NONE
	_mode_start_btn.custom_minimum_size = Vector2(560, 56)
	_mode_start_btn.add_theme_font_size_override("font_size", 24)
	_mode_start_btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	
	var sstyle := StyleBoxFlat.new()
	sstyle.bg_color = Color(0.3, 0.2, 0.08, 0.98)
	sstyle.border_color = GOLD
	sstyle.set_border_width_all(3)
	sstyle.corner_radius_top_left = 8
	sstyle.corner_radius_top_right = 8
	sstyle.corner_radius_bottom_left = 8
	sstyle.corner_radius_bottom_right = 8
	_mode_start_btn.add_theme_stylebox_override("normal", sstyle)
	_mode_start_btn.add_theme_stylebox_override("hover", sstyle)
	_mode_start_btn.add_theme_stylebox_override("pressed", sstyle)
	_mode_start_btn.pressed.connect(_start_war)
	root.add_child(_mode_start_btn)

	add_child(_mode_panel)


# -- Play a Friend panel ----------------------------------------------------


func _build_net_panel() -> void:
	_net_panel = PanelContainer.new()
	_net_panel.name = "PlayAFriend"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.04, 0.045, 0.96)
	style.border_color = Color(0.55, 0.4, 0.2)
	style.set_border_width_all(2)
	style.set_content_margin_all(24)
	_net_panel.add_theme_stylebox_override("panel", style)
	_net_panel.set_anchors_preset(Control.PRESET_CENTER)
	_net_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_net_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_net_panel.visible = false
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	_net_panel.add_child(root)

	var head := Label.new()
	head.text = "PLAY A FRIEND"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 22)
	head.add_theme_color_override("font_color", TEXT_WARM)
	root.add_child(head)

	_net_prereq_label = Label.new()
	_net_prereq_label.name = "NetPrereq"
	_net_prereq_label.text = NetProtocol.prerequisite_text()
	_net_prereq_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_net_prereq_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_net_prereq_label.custom_minimum_size = Vector2(480, 0)
	_net_prereq_label.add_theme_font_size_override("font_size", 15)
	_net_prereq_label.add_theme_color_override("font_color", GOLD)
	root.add_child(_net_prereq_label)

	_net_choice = VBoxContainer.new()
	_net_choice.name = "NetChoice"
	_net_choice.add_theme_constant_override("separation", 8)
	root.add_child(_net_choice)
	_net_choice.add_child(_net_button("Host a Match", _net_choose_host))
	_net_choice.add_child(_net_button("Join a Match", _net_choose_join))

	_net_host_box = VBoxContainer.new()
	_net_host_box.name = "NetHost"
	_net_host_box.visible = false
	_net_host_box.add_theme_constant_override("separation", 8)
	root.add_child(_net_host_box)

	var side_label := Label.new()
	side_label.text = "Which army will you command?"
	side_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	side_label.add_theme_font_size_override("font_size", 16)
	side_label.add_theme_color_override("font_color", TEXT_DIM)
	_net_host_box.add_child(side_label)

	var side_row := HBoxContainer.new()
	side_row.alignment = BoxContainer.ALIGNMENT_CENTER
	side_row.add_theme_constant_override("separation", 6)
	_net_host_box.add_child(side_row)
	for i in NET_SIDES.size():
		var b := Button.new()
		b.set_meta("side_id", str(NET_SIDES[i]["id"]))
		b.set_meta("label", str(NET_SIDES[i]["label"]))
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(_net_on_side_pressed.bind(i))
		_style_net_side_button(b, i == _net_side_index)
		side_row.add_child(b)
		_net_side_buttons.append(b)

	_net_host_box.add_child(_net_button("Open the Gates", _net_host_submit))

	_net_join_box = VBoxContainer.new()
	_net_join_box.name = "NetJoin"
	_net_join_box.visible = false
	_net_join_box.add_theme_constant_override("separation", 8)
	root.add_child(_net_join_box)

	var addr_label := Label.new()
	addr_label.text = "Host's address:"
	addr_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	addr_label.add_theme_font_size_override("font_size", 16)
	addr_label.add_theme_color_override("font_color", TEXT_DIM)
	_net_join_box.add_child(addr_label)

	_net_address = LineEdit.new()
	_net_address.name = "AddressInput"
	_net_address.placeholder_text = "192.168.1.50:4242"
	_net_address.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_net_address.custom_minimum_size = Vector2(280, 36)
	_net_address.add_theme_font_size_override("font_size", 16)
	_net_join_box.add_child(_net_address)
	_net_join_box.add_child(_net_button("Ride Out", _net_join_submit))

	_net_firewall_label = Label.new()
	_net_firewall_label.name = "NetFirewall"
	_net_firewall_label.text = "If macOS asks to allow incoming connections, click Allow."
	_net_firewall_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_net_firewall_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_net_firewall_label.custom_minimum_size = Vector2(440, 0)
	_net_firewall_label.add_theme_font_size_override("font_size", 14)
	_net_firewall_label.add_theme_color_override("font_color", TEXT_DIM)
	_net_firewall_label.visible = false
	root.add_child(_net_firewall_label)

	_net_share_label = Label.new()
	_net_share_label.name = "NetShare"
	_net_share_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_net_share_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_net_share_label.custom_minimum_size = Vector2(440, 0)
	_net_share_label.add_theme_font_size_override("font_size", 15)
	_net_share_label.add_theme_color_override("font_color", GOLD)
	_net_share_label.visible = false
	root.add_child(_net_share_label)

	_net_copy_btn = _net_button("Copy Address", _net_on_copy_pressed)
	_net_copy_btn.name = "NetCopy"
	_net_copy_btn.visible = false
	root.add_child(_net_copy_btn)

	_net_copy_note = Label.new()
	_net_copy_note.name = "NetCopyNote"
	_net_copy_note.text = "Address copied to clipboard."
	_net_copy_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_net_copy_note.add_theme_font_size_override("font_size", 13)
	_net_copy_note.add_theme_color_override("font_color", GOLD)
	_net_copy_note.visible = false
	root.add_child(_net_copy_note)

	_net_status_label = Label.new()
	_net_status_label.name = "NetStatus"
	_net_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_net_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_net_status_label.custom_minimum_size = Vector2(440, 0)
	_net_status_label.add_theme_font_size_override("font_size", 15)
	_net_status_label.add_theme_color_override("font_color", TEXT_WARM)
	root.add_child(_net_status_label)

	_net_cancel_btn = Button.new()
	_net_cancel_btn.name = "NetCancel"
	_net_cancel_btn.text = "✕  Cancel — back to opponents"
	_net_cancel_btn.focus_mode = Control.FOCUS_NONE
	_net_cancel_btn.add_theme_font_size_override("font_size", 15)
	_net_cancel_btn.add_theme_color_override("font_color", TEXT_DIM)
	_net_cancel_btn.pressed.connect(_step_back)
	root.add_child(_net_cancel_btn)

	add_child(_net_panel)


const NET_SIDES: Array[Dictionary] = [
	{"id": "white", "label": "You ride for White"},
	{"id": "black", "label": "You ride for Black"},
	{"id": "random", "label": "Let the gods decide"},
]


func _net_button(label: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", GOLD)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.08, 0.06, 0.9)
	style.border_color = GOLD
	style.set_border_width_all(1)
	style.set_content_margin_all(8)
	b.add_theme_stylebox_override("normal", style)
	b.add_theme_stylebox_override("hover", style)
	b.add_theme_stylebox_override("pressed", style)
	b.pressed.connect(on_pressed)
	return b


func _style_net_side_button(b: Button, active: bool) -> void:
	b.add_theme_color_override("font_color", GOLD if active else TEXT_DIM)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.12, 0.07, 0.9) if active else Color(0.08, 0.07, 0.07, 0.7)
	style.border_color = GOLD if active else Color(0.3, 0.25, 0.2)
	style.set_border_width_all(2 if active else 1)
	style.set_content_margin_all(6)
	b.add_theme_stylebox_override("normal", style)
	b.add_theme_stylebox_override("hover", style)
	b.add_theme_stylebox_override("pressed", style)


func _net_show_choice() -> void:
	_net_choice.visible = true
	_net_host_box.visible = false
	_net_join_box.visible = false
	_net_firewall_label.visible = false
	_net_share_label.visible = false
	_net_copy_btn.visible = false
	_net_copy_note.visible = false
	_net_status_label.text = ""
	_net_busy = false


func _net_choose_host() -> void:
	_net_choice.visible = false
	_net_host_box.visible = true
	_net_join_box.visible = false
	_net_firewall_label.visible = OS.get_name() == "macOS"
	_net_status_label.text = "Choose your side, then open the gates."


func _net_choose_join() -> void:
	_net_choice.visible = false
	_net_host_box.visible = false
	_net_join_box.visible = true
	_net_firewall_label.visible = false
	_net_status_label.text = "Enter the host's address and ride out."


func _net_on_side_pressed(i: int) -> void:
	_net_side_index = i
	for j in _net_side_buttons.size():
		_style_net_side_button(_net_side_buttons[j], j == i)


func _net_host_submit() -> void:
	if _net_busy:
		return
	_net_busy = true
	_net_status_label.text = "Opening the gates…"
	net_host_requested.emit(str(NET_SIDES[_net_side_index]["id"]))


func _net_join_submit() -> void:
	if _net_busy:
		return
	var addr := _net_address.text.strip_edges()
	if addr.is_empty():
		_net_status_label.text = "Please enter an address."
		return
	_net_busy = true
	_net_status_label.text = "Riding out to %s…" % addr
	net_join_requested.emit(addr)


func _net_on_copy_pressed() -> void:
	if _net_primary.is_empty():
		return
	DisplayServer.clipboard_set(_net_primary)
	net_copied_count += 1
	net_last_copied = _net_primary
	_net_copy_note.visible = true


func net_share_lines(lines: Array, primary_addr: String) -> void:
	_net_primary = primary_addr
	_net_share_label.text = "\n".join(lines)
	_net_share_label.visible = true
	_net_copy_btn.visible = not _net_primary.is_empty()
	_net_copy_note.visible = false


func net_status(msg: String) -> void:
	_net_status_label.text = msg


func net_release() -> void:
	_net_busy = false


func net_remembered_address(addr: String) -> void:
	if is_instance_valid(_net_address) and not addr.is_empty():
		_net_address.text = addr


func finish_network() -> void:
	_net_busy = true


func _build_footer() -> void:
	_footer = Label.new()
	_footer.name = "Footer"
	_footer.add_theme_font_size_override("font_size", 15)
	_footer.add_theme_color_override("font_color", TEXT_DIM)
	_footer.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_footer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_footer.position.y = -36
	add_child(_footer)
