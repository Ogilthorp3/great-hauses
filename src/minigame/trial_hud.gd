extends CanvasLayer
## TRIAL BY FIRE — the chrome. Two king cards, the wyrm's patience, a title
## card and a verdict card.
##
## EVERYTHING A PLAYER NEEDS IS ALREADY ON THE BOARD (the jar's pulse is the
## fuse, the pool's colour is the burn) — so the HUD only carries the two things
## the board CANNOT say: what each king is carrying, and how long the wyrm will
## put up with this. It stays out of the middle of the frame, because the middle
## of the frame is the arena.

const INK := Color(0.93, 0.90, 0.84)
const DIM := Color(0.62, 0.59, 0.55)
const WILD := Color(0.42, 0.95, 0.52)
const EMBER := Color(1.0, 0.62, 0.22)
const PANEL := Color(0.05, 0.045, 0.04, 0.62)

## THE HINT LINE MUST NOT LIE ABOUT THE CONTROLS. Standalone, R rebuilds the
## arena and Esc quits the process. Inside a real match neither is true — R is
## refused outright (rerolling a bracket decider is an exploit) and Esc yields
## the ROUND, not the game. The first shipped frame of the embedded arena had
## "R to retry · ESC to leave" printed across the bottom of a tournament
## decider, which is exactly the copy-that-contradicts-the-verdict defect this
## mode was already fixed for once.
const HINT_STANDALONE := "WASD / arrows to move   ·   SPACE to set a wildfire jar   ·   R to retry   ·   ESC to leave"
const HINT_EMBEDDED := "WASD / arrows to move   ·   SPACE to set a wildfire jar   ·   ESC yields the round"

var _cards: Array[RichTextLabel] = []
var _clock: Label
var _clock_bar: ColorRect
var _clock_fill: ColorRect
var _title: Label
var _verdict: Label
var _hint: Label


func _ready() -> void:
	layer = 10
	for side in 2:
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", _box())
		panel.set_anchors_preset(Control.PRESET_TOP_LEFT if side == 0
			else Control.PRESET_TOP_RIGHT)
		panel.position = Vector2(28.0, 24.0) if side == 0 else Vector2(-306.0, 24.0)
		panel.custom_minimum_size = Vector2(278.0, 0.0)
		var card := RichTextLabel.new()
		card.bbcode_enabled = true
		card.fit_content = true
		card.scroll_active = false
		card.custom_minimum_size = Vector2(258.0, 0.0)
		card.add_theme_font_size_override("normal_font_size", 17)
		card.add_theme_font_size_override("bold_font_size", 17)
		panel.add_child(card)
		add_child(panel)
		_cards.append(card)

	var clock_box := VBoxContainer.new()
	clock_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	clock_box.position = Vector2(-170.0, 22.0)
	clock_box.custom_minimum_size = Vector2(340.0, 0.0)
	clock_box.add_theme_constant_override("separation", 6)
	_clock = Label.new()
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock.add_theme_font_size_override("font_size", 16)
	_clock.add_theme_color_override("font_color", DIM)
	clock_box.add_child(_clock)
	_clock_bar = ColorRect.new()
	_clock_bar.color = Color(0.12, 0.11, 0.10, 0.85)
	_clock_bar.custom_minimum_size = Vector2(340.0, 7.0)
	_clock_fill = ColorRect.new()
	_clock_fill.color = EMBER
	_clock_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_clock_fill.size = Vector2(0.0, 7.0)
	_clock_bar.add_child(_clock_fill)
	clock_box.add_child(_clock_bar)
	add_child(clock_box)

	_title = _big("TRIAL BY FIRE", 58, -376.0)
	_title.add_theme_color_override("font_color", WILD)
	_verdict = _big("", 58, -376.0)
	_verdict.visible = false
	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.position = Vector2(-300.0, -52.0)
	_hint.custom_minimum_size = Vector2(600.0, 0.0)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.add_theme_color_override("font_color", DIM)
	_hint.text = HINT_STANDALONE
	add_child(_hint)


func _big(text: String, size: int, dy: float) -> Label:
	var l := Label.new()
	l.text = text
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.position = Vector2(-520.0, dy)
	l.custom_minimum_size = Vector2(1040.0, 0.0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", INK)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 3)
	l.add_theme_constant_override("shadow_offset_y", 4)
	add_child(l)
	return l


func _box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.set_content_margin_all(14.0)
	sb.set_corner_radius_all(3)
	sb.border_color = Color(0.30, 0.27, 0.22, 0.8)
	sb.set_border_width_all(1)
	return sb


## Fade the title out over the opening beat — it names the mode and then gets
## out of the way, because the arena is the thing worth looking at.
## Tell the HUD which set of controls is actually live (see HINT_* above).
func set_embedded(on: bool) -> void:
	if _hint != null and is_instance_valid(_hint):
		_hint.text = HINT_EMBEDDED if on else HINT_STANDALONE


func open() -> void:
	_title.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(_title, "modulate:a", 0.0, 0.9)


func set_king(side: int, name_text: String, tint: Color, jars: int, jars_max: int,
		reach: int, speed: float, alive: bool, tier_text: String) -> void:
	if side >= _cards.size():
		return
	var head := "[b][color=#%s]%s[/color][/b]" % [tint.to_html(false), name_text]
	if not tier_text.is_empty():
		head += "  [color=#8a8378]%s[/color]" % tier_text
	var body := "\n[color=#%s]%s[/color]  jars    " % [
		WILD.to_html(false), _pips(jars, jars_max)]
	body += "[color=#8a8378]reach[/color] %d   [color=#8a8378]tread[/color] %.1fx" % [
		reach, speed]
	if not alive:
		head = "[b][color=#6b3030]%s — FALLEN[/color][/b]" % name_text
		body = "\n[color=#6b3030]the fire took him[/color]"
	_cards[side].text = head + body


func _pips(n: int, of_n: int) -> String:
	var s := ""
	for i in of_n:
		s += "●" if i < n else "○"
	return s


## `patience` is 0..1 toward sudden death; once the wyrm is awake the bar
## becomes the arena's own countdown and turns green — the same wildfire green
## as the thing that is about to eat the square you are standing on.
func set_clock(patience: float, awake: bool, squares_left: int) -> void:
	if awake:
		_clock.text = "THE WYRM IS AWAKE — %d squares remain" % squares_left
		_clock.add_theme_color_override("font_color", WILD)
		_clock_fill.color = WILD
		_clock_fill.size.x = 340.0 * clampf(float(squares_left) / 64.0, 0.0, 1.0)
	else:
		_clock.text = "the wyrm watches"
		_clock.add_theme_color_override("font_color", DIM)
		_clock_fill.color = EMBER.lerp(Color(0.95, 0.25, 0.15), patience)
		_clock_fill.size.x = 340.0 * clampf(patience, 0.0, 1.0)


func announce(text: String, tint: Color) -> void:
	_verdict.text = text
	_verdict.add_theme_color_override("font_color", tint)
	_verdict.visible = true
	_verdict.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_verdict, "modulate:a", 1.0, 0.5)
