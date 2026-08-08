class_name HouseSelect
extends Control
## The Hall of Banners — house-select screen for Great Houses.
##
## Nine crests hang in a ring in a dark hall. Hover/arrow-key a crest to see
## the house's motto and colors; choose one, then pick an opponent (Engine
## Casual/Seasoned/Master or DS4-Oracle Max Thinking), then Begin Tournament
## or Single Match. Pure signals out — the integrator owns scene flow:
##
##   house_chosen(house_id)                          - crest clicked/accepted
##   opponent_chosen(opponent)                       - opponent Dictionary
##   selection_complete(house_id, opponent, mode)    - mode: "tournament"|"single"
##
## opponent Dictionary shapes:
##   {"kind":"engine", "level":"casual"|"seasoned"|"master",
##    "difficulty": ChessAI.Difficulty.*, "label": String}
##   {"kind":"ds4_oracle", "level":"max_thinking",
##    "oracle_mode":"pure"|"counseled"|"maester", "label": String}
##
## Keyboard: Left/Right rotate the ring (Up/Down move in opponent lists),
## Enter/Space accept, Esc steps back a phase.

signal house_chosen(house_id: String)
signal opponent_chosen(opponent: Dictionary)
signal selection_complete(house_id: String, opponent: Dictionary, mode: String)

enum Phase { HOUSE, OPPONENT, MODE, DONE }

const RING_RADIUS_FRAC := 0.36    # of the shorter viewport axis
const CREST_SIZE := Vector2(96, 118)
const TEXT_WARM := Color(0.85, 0.8, 0.7)
const TEXT_DIM := Color(0.62, 0.58, 0.5)
const GOLD := Color(0.8, 0.62, 0.3)

const OPPONENTS: Array[Dictionary] = [
	{"kind": "engine", "level": "casual", "difficulty": ChessAI.Difficulty.EASY,
		"label": "Engine — Casual"},
	{"kind": "engine", "level": "seasoned", "difficulty": ChessAI.Difficulty.MEDIUM,
		"label": "Engine — Seasoned"},
	{"kind": "engine", "level": "master", "difficulty": ChessAI.Difficulty.HARD,
		"label": "Engine — Master"},
	{"kind": "ds4_oracle", "level": "max_thinking", "oracle_mode": "pure",
		"label": "Pure Oracle"},
	{"kind": "ds4_oracle", "level": "max_thinking", "oracle_mode": "counseled",
		"label": "Counseled Oracle"},
	{"kind": "ds4_oracle", "level": "max_thinking", "oracle_mode": "maester",
		"label": "Oracle + Grand Maester"},
]
const MODES: Array[Dictionary] = [
	{"id": "tournament", "label": "Begin Tournament"},
	{"id": "single", "label": "Single Match"},
]

var phase := Phase.HOUSE
var selected_house := ""
var selected_opponent: Dictionary = {}
var selected_mode := ""
var _disabled_opponents: Dictionary = {}   # opponent kind -> reason
var _disabled_modes: Dictionary = {}       # oracle_mode -> reason (per-entry)

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
var _opp_panel: PanelContainer
var _opp_buttons: Array[Button] = []
var _mode_panel: PanelContainer
var _mode_buttons: Array[Button] = []
var _footer: Label
var _done_label: Label


func _ready() -> void:
	_house_ids = HouseRegistry.house_ids()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_backdrop()
	_build_title()
	_build_ring()
	_build_preview()
	_opp_panel = _build_list_panel("CHOOSE YOUR OPPONENT", OPPONENTS, _opp_buttons,
			_on_opponent_pressed, Vector2(0.5, 0.5))
	_mode_panel = _build_list_panel("HOW WILL YOU FIGHT?", MODES, _mode_buttons,
			_on_mode_pressed, Vector2(0.5, 0.5))
	_build_footer()
	_done_label = null
	resized.connect(_layout_ring)
	_set_phase(Phase.HOUSE)
	_set_ring_index(0)
	_layout_ring.call_deferred()


## Return to a fresh HOUSE phase (integrator can reuse the scene).
func reset() -> void:
	selected_house = ""
	selected_opponent = {}
	selected_mode = ""
	if _done_label != null:
		_done_label.queue_free()
		_done_label = null
	_set_phase(Phase.HOUSE)
	_set_ring_index(0)


func get_selection() -> Dictionary:
	return {"house": selected_house, "opponent": selected_opponent, "mode": selected_mode}


## Grey an opponent kind in or out (e.g. "ds4_oracle" when the tunnel is
## down). Disabled entries can be highlighted but not accepted; attempting
## shows `reason` in the footer.
func set_opponent_enabled(kind: String, enabled: bool, reason := "") -> void:
	if enabled:
		_disabled_opponents.erase(kind)
	else:
		_disabled_opponents[kind] = reason if not reason.is_empty() else "unavailable"
	if not _opp_buttons.is_empty():
		_set_opp_index(_opp_index)


## Grey a single Oracle mode in or out (e.g. "maester" when stockfish is not
## installed) without touching the other DS4-Oracle entries.
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
	var used := true
	if event.is_action_pressed("ui_cancel"):
		_step_back()
	elif phase == Phase.HOUSE:
		if event.is_action_pressed("ui_left", true):
			_set_ring_index(posmod(_ring_index - 1, _house_ids.size()))
		elif event.is_action_pressed("ui_right", true):
			_set_ring_index(posmod(_ring_index + 1, _house_ids.size()))
		elif event.is_action_pressed("ui_accept"):
			_choose_house(_house_ids[_ring_index])
		else:
			used = false
	elif phase == Phase.OPPONENT:
		if event.is_action_pressed("ui_up", true):
			_set_opp_index(posmod(_opp_index - 1, OPPONENTS.size()))
		elif event.is_action_pressed("ui_down", true):
			_set_opp_index(posmod(_opp_index + 1, OPPONENTS.size()))
		elif event.is_action_pressed("ui_accept"):
			_on_opponent_pressed(_opp_index)
		else:
			used = false
	elif phase == Phase.MODE:
		if event.is_action_pressed("ui_up", true) or event.is_action_pressed("ui_left", true):
			_set_mode_index(posmod(_mode_index - 1, MODES.size()))
		elif event.is_action_pressed("ui_down", true) or event.is_action_pressed("ui_right", true):
			_set_mode_index(posmod(_mode_index + 1, MODES.size()))
		elif event.is_action_pressed("ui_accept"):
			_on_mode_pressed(_mode_index)
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


# -- phase flow -------------------------------------------------------------


func _choose_house(id: String) -> void:
	selected_house = id
	_ring_index = _house_ids.find(id)
	house_chosen.emit(id)
	_set_phase(Phase.OPPONENT)


func _on_opponent_pressed(i: int) -> void:
	if phase != Phase.OPPONENT:
		return
	if _opp_disabled(i):
		_set_opp_index(i)
		_footer.text = _opp_disabled_reason(i)
		return
	_set_opp_index(i)
	selected_opponent = OPPONENTS[i].duplicate()
	opponent_chosen.emit(selected_opponent)
	_set_phase(Phase.MODE)


func _on_mode_pressed(i: int) -> void:
	if phase != Phase.MODE:
		return
	_set_mode_index(i)
	selected_mode = str(MODES[i]["id"])
	_set_phase(Phase.DONE)
	selection_complete.emit(selected_house, selected_opponent, selected_mode)


func _set_phase(p: Phase) -> void:
	phase = p
	_opp_panel.visible = p == Phase.OPPONENT
	_mode_panel.visible = p == Phase.MODE
	_preview.visible = p == Phase.HOUSE
	_refresh_crest_highlights()
	if p == Phase.HOUSE:
		_update_preview()
		_footer.text = "Left/Right choose a banner · Enter to pledge · Esc back"
	elif p == Phase.OPPONENT:
		_set_opp_index(_opp_index)
		_footer.text = "Up/Down choose your rival · Enter to accept · Esc back"
	elif p == Phase.MODE:
		_set_mode_index(_mode_index)
		_footer.text = "Choose your war · Enter to accept · Esc back"
	elif p == Phase.DONE:
		_footer.text = ""
		_show_done_banner()


func _show_done_banner() -> void:
	var house := HouseRegistry.get_house(selected_house)
	_done_label = Label.new()
	_done_label.name = "DoneBanner"
	_done_label.text = "%s rides to war.\n%s" % [
		str(house.get("name", selected_house)), str(house.get("motto", ""))]
	_done_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_done_label.add_theme_font_size_override("font_size", 30)
	_done_label.add_theme_color_override("font_color", TEXT_WARM)
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
		_style_list_button(_opp_buttons[j], j == i, _opp_disabled(j))


func _set_mode_index(i: int) -> void:
	_mode_index = i
	for j in _mode_buttons.size():
		_style_list_button(_mode_buttons[j], j == i)


func _style_list_button(b: Button, active: bool, disabled := false) -> void:
	if disabled:
		var ash := Color(0.33, 0.31, 0.28)
		b.add_theme_color_override("font_color", ash)
		b.add_theme_color_override("font_hover_color", ash)
		b.text = "%s — sleeps" % b.get_meta("label")
		return
	b.add_theme_color_override("font_color", GOLD if active else TEXT_DIM)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.text = ("»  %s  «" % b.get_meta("label")) if active else str(b.get_meta("label"))


func _refresh_crest_highlights() -> void:
	for i in _crests.size():
		var crest := _crests[i]
		var is_current := i == _ring_index
		var dim := 0.4 if phase != Phase.HOUSE and not is_current else 1.0
		crest.modulate = (Color(1, 1, 1) if is_current else Color(0.58, 0.58, 0.58)) * dim
		crest.modulate.a = 1.0
		crest.scale = Vector2.ONE * (1.16 if is_current else 1.0)
		crest.z_index = 1 if is_current else 0


func _update_preview() -> void:
	if _house_ids.is_empty():
		return
	var house := HouseRegistry.get_house(_house_ids[_ring_index])
	_preview_name.text = str(house.get("name", "?"))
	_preview_seat.text = "Seat: %s" % str(house.get("seat", "?"))
	_preview_motto.text = "“%s”" % str(house.get("motto", ""))
	var colors := HouseRegistry.get_colors(house)
	var order := ["primary", "secondary", "accent"]
	for i in _preview_swatches.get_child_count():
		(_preview_swatches.get_child(i) as ColorRect).color = colors[order[i]]


# -- construction -----------------------------------------------------------


func _build_backdrop() -> void:
	var base := ColorRect.new()
	base.name = "HallFloor"
	base.color = Color(0.05, 0.042, 0.038)
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)

	# Warm torch glow pooling in the middle of the hall.
	var glow_grad := Gradient.new()
	glow_grad.set_color(0, Color(0.24, 0.16, 0.09, 0.55))
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

	# Vignette: the hall falls away into darkness top and bottom.
	var vig_grad := Gradient.new()
	vig_grad.offsets = PackedFloat32Array([0.0, 0.22, 0.78, 1.0])
	vig_grad.colors = PackedColorArray([
		Color(0, 0, 0, 0.65), Color(0, 0, 0, 0.0),
		Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.75)])
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
	var title := Label.new()
	title.name = "Title"
	title.text = "THE HALL OF BANNERS"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", TEXT_WARM)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title.position.y = 26
	add_child(title)
	var sub := Label.new()
	sub.name = "Subtitle"
	sub.text = "Nine banners. One throne."
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", TEXT_DIM)
	sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sub.position.y = 70
	add_child(sub)


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
	btn.focus_mode = Control.FOCUS_NONE  # keyboard handled by the hall itself
	btn.pressed.connect(_on_crest_pressed.bind(index))
	btn.mouse_entered.connect(_on_crest_hovered.bind(index))
	crest.add_child(btn)
	var label := Label.new()
	label.name = "Name"
	label.text = str(house["name"]).trim_prefix("House ")
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", TEXT_WARM)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(0, CREST_SIZE.x + 2)
	label.size = Vector2(CREST_SIZE.x, 18)
	crest.add_child(label)
	return crest


func _on_crest_pressed(index: int) -> void:
	if phase != Phase.HOUSE:
		return
	_set_ring_index(index)
	_choose_house(_house_ids[index])


func _on_crest_hovered(index: int) -> void:
	if phase != Phase.HOUSE:
		return
	_set_ring_index(index)


func _layout_ring() -> void:
	if _crests.is_empty():
		return
	var center := size * 0.5 + Vector2(0, 20)
	var radius := minf(size.x, size.y) * RING_RADIUS_FRAC
	for i in _crests.size():
		var ang := -TAU / 4.0 + TAU * i / _crests.size()
		var pos := center + Vector2(cos(ang), sin(ang)) * radius - CREST_SIZE * 0.5
		_crests[i].position = pos


func _build_preview() -> void:
	_preview = VBoxContainer.new()
	_preview.name = "Preview"
	_preview.alignment = BoxContainer.ALIGNMENT_CENTER
	_preview.set_anchors_preset(Control.PRESET_CENTER)
	_preview.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_preview.grow_vertical = Control.GROW_DIRECTION_BOTH
	_preview.position += Vector2(0, 20)
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_preview)
	_preview_name = _preview_label(24, TEXT_WARM)
	_preview_seat = _preview_label(15, TEXT_DIM)
	_preview_motto = _preview_label(17, GOLD)
	_preview_swatches = HBoxContainer.new()
	_preview_swatches.alignment = BoxContainer.ALIGNMENT_CENTER
	_preview_swatches.add_theme_constant_override("separation", 6)
	for i in 3:
		var sw := ColorRect.new()
		sw.custom_minimum_size = Vector2(26, 14)
		_preview_swatches.add_child(sw)
	_preview.add_child(_preview_swatches)


func _preview_label(font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	_preview.add_child(l)
	return l


func _build_list_panel(heading: String, entries: Array[Dictionary],
		buttons: Array[Button], on_pressed: Callable, _anchor: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = heading.to_pascal_case()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.04, 0.045, 0.94)
	style.border_color = Color(0.55, 0.4, 0.2)
	style.set_border_width_all(2)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.visible = false
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	var head := Label.new()
	head.text = heading
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 19)
	head.add_theme_color_override("font_color", TEXT_WARM)
	vbox.add_child(head)
	for i in entries.size():
		var b := Button.new()
		b.set_meta("label", str(entries[i]["label"]))
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(on_pressed.bind(i))
		_style_list_button(b, i == 0)
		vbox.add_child(b)
		buttons.append(b)
	add_child(panel)
	return panel


func _build_footer() -> void:
	_footer = Label.new()
	_footer.name = "Footer"
	_footer.add_theme_font_size_override("font_size", 14)
	_footer.add_theme_color_override("font_color", TEXT_DIM)
	_footer.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_footer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_footer.position.y = -34
	add_child(_footer)
