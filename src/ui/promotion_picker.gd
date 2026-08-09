class_name PromotionPicker
extends CanvasLayer
## THE PROMOTION PICKER — Albert's bug, closed.
##
## For four months a promoting pawn in this game could only ever become a
## queen. The ENGINE was never the problem: `ChessState.construct_move` takes
## any promotion piece and the perft suite has always proven `a7a8n` promoting
## to a knight and undoing back to a pawn. The UI threw the other three away —
## `game.gd::_move_for` filtered the legal-move list down to `promotion == "q"`
## before the player ever saw it. The owner's son noticed. He was right.
##
## This is a MODAL, and it is made of the real thing: each choice is an actual
## PieceView built by the same `scenes/piece_view.tscn` assembly the board
## spawns, in the promoting haus's own colours and kit (crest, helm, banner,
## the mounted destrier for the knight), lit and framed in its own SubViewport.
## This game shows pieces, not text buttons.
##
## THREE WAYS IN, AND IT CAN NEVER HANG:
##   click     the piece itself
##   keys      Q / R / B / N direct · ← → to walk the row · Enter to take it
##   default   Esc, or PICK_TIMEOUT_SEC of silence, takes the QUEEN
## The default is not a convenience: a modal that can hold the board hostage
## is worse than the bug it fixes, so every exit lands on a legal move.
##
## The row is built from the moves the ENGINE actually generated (`offered`),
## never from this file's own idea of what a promotion is — the UI can offer
## nothing the rules did not.
##
## Usage (see game.gd::_choose_promotion):
##     var picker := PromotionPicker.new()
##     picker.house_id = player_house_id
##     picker.side = PieceView.House.FROST
##     picker.offered = ["q", "r", "b", "n"]
##     add_child(picker)
##     var piece_char: String = await picker.chosen

## A choice landed: "q" | "r" | "b" | "n". Always fires exactly once.
signal chosen(piece_char: String)

const PieceScene: PackedScene = preload("res://scenes/piece_view.tscn")

## Display order, and the order the ← → keys walk. Queen first because queen
## is what every silent exit falls back to.
const ORDER: Array[String] = ["q", "r", "b", "n"]
const NAMES := {"q": "Queen", "r": "Rook", "b": "Bishop", "n": "Knight"}
const HOTKEY := {KEY_Q: "q", KEY_R: "r", KEY_B: "b", KEY_N: "n"}
const TYPE_OF := {
	"q": PieceView.Type.QUEEN,
	"r": PieceView.Type.ROOK,
	"b": PieceView.Type.BISHOP,
	"n": PieceView.Type.KNIGHT,
}
## What Esc and the timeout take. Chess's own default, and the one piece a
## player who is not looking at the screen expects.
const DEFAULT_PIECE := "q"
## How long the modal will wait before taking the queen itself. Long enough to
## read four pieces, short enough that a walked-away game finishes its move.
const PICK_TIMEOUT_SEC := 20.0

## The card's 3D window, in pixels. 4 x 168 + gutters fits inside 1280 wide
## (the e2e window) with room to spare, and inside anything larger.
const CARD_VIEWPORT := Vector2i(168, 206)

const PANEL_BG := Color(0.05, 0.04, 0.045, 0.94)
const PANEL_BORDER := Color(0.55, 0.40, 0.20)
const CARD_BG := Color(0.09, 0.08, 0.075, 0.90)
const CARD_BG_FOCUS := Color(0.16, 0.13, 0.09, 0.96)
const TEXT := Color(0.93, 0.89, 0.79)
const DIM := Color(0.75, 0.71, 0.62)
const GOLD := Color(0.88, 0.70, 0.35)
const OUTLINE := Color(0.02, 0.02, 0.03, 0.92)

# -- configuration (set before add_child) ------------------------------------

## The promoting haus (a houses.json id); "" keeps the legacy Frost/Ember skin.
var house_id := ""
## Which army's dye — PieceView.House.FROST is always "mine" in this game.
var side: int = PieceView.House.FROST
## The promotion chars the ENGINE offered, in any order. Rendered in ORDER.
var offered: Array[String] = ["q", "r", "b", "n"]
## Overridable for tests; PICK_TIMEOUT_SEC otherwise.
var timeout_sec := PICK_TIMEOUT_SEC

# -- introspection (e2e evidence) --------------------------------------------

var picked := ""          ## "" until a choice lands
var pick_source := ""     ## "click" | "key" | "escape" | "timeout"
var focus_index := 0      ## which card the keyboard is standing on
var cards: Dictionary = {}   ## piece char -> PanelContainer
var models: Dictionary = {}  ## piece char -> PieceView (the real assembly)

# -- internals ---------------------------------------------------------------

var _row: Array[String] = []
var _hint: Label
var _deadline_ms := 0
var _closed := false


func _ready() -> void:
	# A modal must keep running even if something else pauses the tree, and it
	# must draw above the HUD's own CanvasLayer.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 50
	name = "PromotionPicker"
	_row.clear()
	for pc in ORDER:
		if offered.has(pc):
			_row.append(pc)
	if _row.is_empty():
		# Defensive: a caller that offered nothing still gets an answer instead
		# of a modal nobody can dismiss. DEFERRED — `add_child()` runs `_ready`
		# synchronously, so emitting here would fire `chosen` before the caller
		# has awaited it and hang the board on the one path that exists to stop
		# the board hanging.
		_close.call_deferred(DEFAULT_PIECE, "timeout")
		return
	_build()
	_deadline_ms = Time.get_ticks_msec() + int(maxf(timeout_sec, 1.0) * 1000.0)
	set_process(true)


func _process(_dt: float) -> void:
	if _closed:
		return
	# WALL clock (Time.get_ticks_msec), never a scaled timer: promotions land
	# next to cinematics that bend Engine.time_scale, and a countdown that
	# stretches with the slow-mo is a countdown that lies.
	var left := float(_deadline_ms - Time.get_ticks_msec()) / 1000.0
	if left <= 0.0:
		_close(DEFAULT_PIECE, "timeout")
		return
	if _hint != null:
		_hint.text = "Q · R · B · N     ← → and Enter     Esc takes the %s (%d s)" % [
			NAMES[DEFAULT_PIECE], int(ceil(left))]


func _input(event: InputEvent) -> void:
	## A MODAL OWNS THE KEYBOARD. Every key is swallowed while this is up —
	## not only the ones below — because the keys underneath it are R (reload
	## the match) and Cmd/Ctrl+Z (rewind the board), and either of them landing
	## mid-promotion is a worse bug than the one this panel fixes.
	if _closed or not (event is InputEventKey):
		return
	get_viewport().set_input_as_handled()
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if HOTKEY.has(key.keycode) and _row.has(HOTKEY[key.keycode]):
		_close(str(HOTKEY[key.keycode]), "key")
		return
	match key.keycode:
		KEY_LEFT, KEY_UP:
			_set_focus(focus_index - 1)
		KEY_RIGHT, KEY_DOWN:
			_set_focus(focus_index + 1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_close(_row[focus_index], "enter")   # walked here with the arrows
		KEY_ESCAPE:
			_close(DEFAULT_PIECE if _row.has(DEFAULT_PIECE) else _row[0], "escape")


# ── the choice ─────────────────────────────────────────────────────────────


func _close(piece_char: String, source: String) -> void:
	if _closed:
		return
	_closed = true
	set_process(false)
	picked = piece_char
	pick_source = source
	print("PROMOTION PICK piece=%s source=%s haus=%s" % [
		piece_char, source, house_id if not house_id.is_empty() else "legacy"])
	chosen.emit(piece_char)
	queue_free()


func _set_focus(i: int) -> void:
	focus_index = wrapi(i, 0, _row.size())
	for j in _row.size():
		var card := cards[_row[j]] as PanelContainer
		card.add_theme_stylebox_override("panel", _card_style(j == focus_index))


# ── construction ───────────────────────────────────────────────────────────


func _build() -> void:
	var scrim := ColorRect.new()
	scrim.name = "PromoScrim"
	scrim.color = Color(0.0, 0.0, 0.0, 0.55)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP, not IGNORE: a click that misses a card must die here rather than
	# fall through to the board underneath and select some other piece.
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	var panel := PanelContainer.new()
	panel.name = "PromotionPanel"
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = _accent()
	style.set_border_width_all(2)
	style.set_content_margin_all(22)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title := Label.new()
	title.name = "PromotionTitle"
	title.text = "Your footman reaches the last rank"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", TEXT)
	_outline(title, 5)
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "Raise him to whatever the war needs."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", DIM)
	_outline(sub, 4)
	vbox.add_child(sub)

	var row := HBoxContainer.new()
	row.name = "PromotionRow"
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(row)
	for i in _row.size():
		_make_card(_row[i], i, row)

	_hint = Label.new()
	_hint.name = "PromotionHint"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", GOLD)
	_outline(_hint, 4)
	vbox.add_child(_hint)

	_set_focus(0)


## THE CARD IS PARENTED FIRST, AND THAT IS LOAD-BEARING (caught by the e2e's
## own pixel census, 2026-08-09): a Camera3D that is not yet inside the tree
## refuses `look_at` ("Node not inside tree") and keeps an identity transform,
## so every card shipped a camera sitting inside the piece and four empty
## black boxes — with the piece models correctly built underneath them. The
## assertions on `models[pc].piece_type` all passed. Nothing was on screen.
func _make_card(pc: String, index: int, parent: Control) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "PromoCard_%s" % pc
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(card)      # in the tree BEFORE anything 3D is aimed
	card.add_theme_stylebox_override("panel", _card_style(false))
	card.gui_input.connect(_on_card_input.bind(pc))
	card.mouse_entered.connect(_set_focus.bind(index))
	cards[pc] = card

	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 4)
	card.add_child(vb)

	var svc := SubViewportContainer.new()
	svc.name = "PromoStage_%s" % pc
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	svc.custom_minimum_size = Vector2(CARD_VIEWPORT)
	vb.add_child(svc)

	var sv := SubViewport.new()
	sv.size = CARD_VIEWPORT
	sv.own_world_3d = true          # its own little hall — never the match's
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(sv)
	_dress_stage(sv)

	# THE SAME ASSEMBLY THE BOARD USES. Not an icon, not a sprite sheet:
	# scenes/piece_view.tscn, setup() with this haus's id, so the queen wears
	# the tiara and the crest, the rook flies the banner, and the knight is
	# mounted on the destrier — exactly what will stand on the square.
	var pv: PieceView = PieceScene.instantiate()
	sv.add_child(pv)
	pv.setup(TYPE_OF[pc], side, house_id)
	# Turn him around: on the board an army faces the enemy line (Frost looks
	# +Z), and a shopper looking at four backs learns nothing.
	pv.rotation.y = PI
	models[pc] = pv

	var cam := Camera3D.new()
	sv.add_child(cam)
	var h: float = PieceAssets.piece_height(TYPE_OF[pc])
	# The knight is an ensemble, not a figure — the destrier stands broadside
	# and needs the extra step back or the caparison walks out of frame.
	var pull := 2.25 if pc != "n" else 2.75
	var focus := Vector3(0.0, h * 0.54, 0.0)
	var yaw := deg_to_rad(20.0)
	cam.fov = 34.0
	cam.position = focus + Vector3(sin(yaw), 0.26, -cos(yaw)) * (h * pull + 0.30)
	cam.look_at(focus)
	cam.current = true

	var lbl := Label.new()
	lbl.name = "PromoName_%s" % pc
	lbl.text = "%s  ·  %s" % [NAMES[pc], pc.to_upper()]
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", TEXT)
	_outline(lbl, 4)
	vb.add_child(lbl)
	return card


## A small lit stage per card: a key, a cool fill, and enough ambient that a
## near-black haus (Hartcrown's #1d1a17) is still a piece and not a silhouette.
func _dress_stage(sv: SubViewport) -> void:
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38.0, 205.0, 0.0)
	key.light_energy = 1.35
	key.light_color = Color(1.0, 0.94, 0.82)
	sv.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18.0, 60.0, 0.0)
	fill.light_energy = 0.45
	fill.light_color = Color(0.70, 0.80, 1.0)
	sv.add_child(fill)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.07, 0.065, 0.062)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.58, 0.56, 0.58)
	e.ambient_light_energy = 0.85
	env.environment = e
	sv.add_child(env)


func _on_card_input(event: InputEvent, pc: String) -> void:
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_close(pc, "click")


func _card_style(focused: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = CARD_BG_FOCUS if focused else CARD_BG
	s.border_color = _accent() if focused else Color(0.30, 0.27, 0.23)
	s.set_border_width_all(3 if focused else 1)
	s.set_content_margin_all(8)
	return s


## The haus's own accent, floored for legibility the way the banter caption is
## (a near-black accent is a border nobody can see).
func _accent() -> Color:
	if house_id.is_empty() or not HouseRegistry.has_house(house_id):
		return PANEL_BORDER
	var a: Color = HouseRegistry.get_colors(house_id)["accent"]
	return Color.from_hsv(a.h, minf(a.s, 0.80), maxf(a.v, 0.62), 1.0)


static func _outline(label: Label, px: int) -> void:
	label.add_theme_color_override("font_outline_color", OUTLINE)
	label.add_theme_constant_override("outline_size", px)
