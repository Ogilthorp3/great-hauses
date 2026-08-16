class_name CoachOverlay
extends CanvasLayer
## CoachOverlay — Interactive Grandmaster Training HUD for Great Hauses.
## Displays live threat radar, master opening guides, and tactical move explanations.

signal hint_requested()
signal coach_toggled(enabled: bool)

var is_coach_active := true
var _panel: PanelContainer = null
var _title_label: Label = null
var _opening_label: Label = null
var _threat_label: Label = null
var _advice_label: Label = null
var _hint_button: Button = null
var _toggle_button: Button = null

const GOLD_ACCENT := Color(0.95, 0.82, 0.35)
const RED_ALERT := Color(1.0, 0.35, 0.35)
const CYAN_TIP := Color(0.4, 0.88, 1.0)
const BG_COLOR := Color(0.08, 0.10, 0.14, 0.92)


func _ready() -> void:
	layer = 20
	_build_ui()


func _build_ui() -> void:
	# Main container in bottom-left
	_panel = PanelContainer.new()
	_panel.name = "CoachPanel"
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_panel.position = Vector2(24, -220)
	_panel.custom_minimum_size = Vector2(380, 190)
	add_child(_panel)

	# Styling
	var style := StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.border_color = GOLD_ACCENT
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	# Header row
	var header_hbox := HBoxContainer.new()
	vbox.add_child(header_hbox)

	_title_label = Label.new()
	_title_label.text = "👑 GRANDMASTER COACH"
	_title_label.add_theme_font_size_override("font_size", 14)
	_title_label.add_theme_color_override("font_color", GOLD_ACCENT)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(_title_label)

	_toggle_button = Button.new()
	_toggle_button.text = "Hide [C]"
	_toggle_button.add_theme_font_size_override("font_size", 11)
	_toggle_button.pressed.connect(toggle_coach)
	header_hbox.add_child(_toggle_button)

	# Opening & Phase
	_opening_label = Label.new()
	_opening_label.text = "Opening: Seize the Center"
	_opening_label.add_theme_font_size_override("font_size", 12)
	_opening_label.add_theme_color_override("font_color", CYAN_TIP)
	vbox.add_child(_opening_label)

	# Threat Radar
	_threat_label = Label.new()
	_threat_label.text = "🛡️ Threat Radar: All pieces safe"
	_threat_label.add_theme_font_size_override("font_size", 12)
	_threat_label.add_theme_color_override("font_color", Color(0.8, 0.9, 0.8))
	vbox.add_child(_threat_label)

	# Master Advice
	_advice_label = Label.new()
	_advice_label.text = "Recommendation: Control central squares (e4/d4) and develop knights before bishops!"
	_advice_label.add_theme_font_size_override("font_size", 13)
	_advice_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	_advice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_advice_label.custom_minimum_size = Vector2(350, 48)
	vbox.add_child(_advice_label)

	# Hint Button
	_hint_button = Button.new()
	_hint_button.text = "💡 Highlight Best Move [T]"
	_hint_button.add_theme_font_size_override("font_size", 12)
	_hint_button.pressed.connect(func(): hint_requested.emit())
	vbox.add_child(_hint_button)


func update_analysis(info: Dictionary) -> void:
	if _panel == null:
		_build_ui()
	if not is_coach_active:
		return

	var op_name: String = info.get("opening_name", "")
	var op_tip: String = info.get("opening_tip", "")
	if not op_name.is_empty():
		_opening_label.text = "📖 %s" % op_name
		if not op_tip.is_empty() and info.get("explanation", "").is_empty():
			_advice_label.text = op_tip

	var threats: Array = info.get("threats", [])
	if threats.is_empty():
		_threat_label.text = "🛡️ Threat Radar: Position secure — no hanging pieces."
		_threat_label.add_theme_color_override("font_color", Color(0.6, 0.95, 0.6))
	else:
		var threat_names: Array[String] = []
		for t in threats:
			threat_names.append("%s on %s" % [t.get("name", "Piece"), t.get("coord", "")])
		_threat_label.text = "⚠️ ALERT: %s under attack!" % ", ".join(threat_names)
		_threat_label.add_theme_color_override("font_color", RED_ALERT)

	var explanation: String = info.get("explanation", "")
	if not explanation.is_empty():
		_advice_label.text = explanation


func toggle_coach() -> bool:
	if _panel == null:
		_build_ui()
	is_coach_active = not is_coach_active
	_panel.visible = is_coach_active
	coach_toggled.emit(is_coach_active)
	return is_coach_active
