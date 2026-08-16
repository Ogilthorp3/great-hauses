class_name CoachOverlay
extends CanvasLayer
## CoachOverlay — Interactive Dual-Grandmaster Training HUD for Great Hauses.
## Displays live threat radar, master opening guides, and dual perspective cards
## from Stockfish 18 NNUE (Tactics) and Leela Lc0 (Positional Strategy).

signal hint_requested()
signal stockfish_hint_requested()
signal leela_hint_requested()
signal coach_toggled(enabled: bool)

var is_coach_active := false
var _panel: PanelContainer = null
var _title_label: Label = null
var _opening_label: Label = null
var _threat_label: Label = null

# Consensus Banner
var _consensus_panel: PanelContainer = null
var _consensus_label: Label = null

# Stockfish Card UI
var _sf_panel: PanelContainer = null
var _sf_title: Label = null
var _sf_plan: Label = null
var _sf_btn: Button = null

# Leela Card UI
var _leela_panel: PanelContainer = null
var _leela_title: Label = null
var _leela_plan: Label = null
var _leela_btn: Button = null

var _toggle_button: Button = null

const GOLD_ACCENT := Color(0.95, 0.82, 0.35)
const RED_ALERT := Color(1.0, 0.35, 0.35)
const CYAN_TIP := Color(0.4, 0.88, 1.0)
const LEELA_VIOLET := Color(0.85, 0.65, 1.0)
const BG_COLOR := Color(0.08, 0.10, 0.14, 0.94)
const CARD_BG := Color(0.12, 0.14, 0.18, 0.90)


func _ready() -> void:
	layer = 20
	_build_ui()


func _build_ui() -> void:
	if _panel != null:
		return

	# Main container in bottom-left
	_panel = PanelContainer.new()
	_panel.name = "CoachPanel"
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_panel.position = Vector2(24, -280)
	_panel.custom_minimum_size = Vector2(460, 250)
	_panel.visible = false
	add_child(_panel)

	var main_style := StyleBoxFlat.new()
	main_style.bg_color = BG_COLOR
	main_style.border_color = GOLD_ACCENT
	main_style.set_border_width_all(2)
	main_style.set_corner_radius_all(8)
	main_style.content_margin_left = 14
	main_style.content_margin_right = 14
	main_style.content_margin_top = 10
	main_style.content_margin_bottom = 10
	_panel.add_theme_stylebox_override("panel", main_style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	# Header row
	var header_hbox := HBoxContainer.new()
	vbox.add_child(header_hbox)

	_title_label = Label.new()
	_title_label.text = "👑 DUAL GRANDMASTER COUNCIL"
	_title_label.add_theme_font_size_override("font_size", 14)
	_title_label.add_theme_color_override("font_color", GOLD_ACCENT)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(_title_label)

	_toggle_button = Button.new()
	_toggle_button.text = "Hide [C]"
	_toggle_button.add_theme_font_size_override("font_size", 11)
	_toggle_button.pressed.connect(toggle_coach)
	header_hbox.add_child(_toggle_button)

	# Opening & Threat status in top header
	var status_hbox := HBoxContainer.new()
	vbox.add_child(status_hbox)

	_opening_label = Label.new()
	_opening_label.text = "📖 Opening: Seize Center"
	_opening_label.add_theme_font_size_override("font_size", 11)
	_opening_label.add_theme_color_override("font_color", CYAN_TIP)
	_opening_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_hbox.add_child(_opening_label)

	_threat_label = Label.new()
	_threat_label.text = "🛡️ Threat: Secure"
	_threat_label.add_theme_font_size_override("font_size", 11)
	_threat_label.add_theme_color_override("font_color", Color(0.6, 0.95, 0.6))
	status_hbox.add_child(_threat_label)

	# Consensus Banner
	_consensus_panel = PanelContainer.new()
	var con_style := StyleBoxFlat.new()
	con_style.bg_color = Color(0.25, 0.20, 0.05, 0.9)
	con_style.border_color = GOLD_ACCENT
	con_style.set_border_width_all(1)
	con_style.set_corner_radius_all(6)
	con_style.content_margin_left = 8
	con_style.content_margin_right = 8
	con_style.content_margin_top = 4
	con_style.content_margin_bottom = 4
	_consensus_panel.add_theme_stylebox_override("panel", con_style)
	_consensus_panel.visible = false
	vbox.add_child(_consensus_panel)

	_consensus_label = Label.new()
	_consensus_label.text = "🌟 TITAN CONSENSUS: Both Engines Agree!"
	_consensus_label.add_theme_font_size_override("font_size", 11)
	_consensus_label.add_theme_color_override("font_color", GOLD_ACCENT)
	_consensus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_consensus_panel.add_child(_consensus_label)

	# Dual Engines Cards HBox
	var cards_hbox := HBoxContainer.new()
	cards_hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(cards_hbox)

	# Stockfish Card (Left)
	_sf_panel = PanelContainer.new()
	_sf_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sf_style := StyleBoxFlat.new()
	sf_style.bg_color = CARD_BG
	sf_style.border_color = CYAN_TIP
	sf_style.set_border_width_all(1)
	sf_style.set_corner_radius_all(6)
	sf_style.content_margin_left = 8
	sf_style.content_margin_right = 8
	sf_style.content_margin_top = 6
	sf_style.content_margin_bottom = 6
	_sf_panel.add_theme_stylebox_override("panel", sf_style)
	cards_hbox.add_child(_sf_panel)

	var sf_vbox := VBoxContainer.new()
	sf_vbox.add_theme_constant_override("separation", 3)
	_sf_panel.add_child(sf_vbox)

	_sf_title = Label.new()
	_sf_title.text = "⚔️ STOCKFISH (Tactics)"
	_sf_title.add_theme_font_size_override("font_size", 11)
	_sf_title.add_theme_color_override("font_color", CYAN_TIP)
	sf_vbox.add_child(_sf_title)

	_sf_plan = Label.new()
	_sf_plan.text = "Analyzing deep tactical lines..."
	_sf_plan.add_theme_font_size_override("font_size", 10)
	_sf_plan.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	_sf_plan.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sf_plan.custom_minimum_size = Vector2(190, 52)
	sf_vbox.add_child(_sf_plan)

	_sf_btn = Button.new()
	_sf_btn.text = "💡 [T] Tactical Move"
	_sf_btn.add_theme_font_size_override("font_size", 10)
	_sf_btn.pressed.connect(func(): stockfish_hint_requested.emit())
	sf_vbox.add_child(_sf_btn)

	# Leela Card (Right)
	_leela_panel = PanelContainer.new()
	_leela_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var leela_style := StyleBoxFlat.new()
	leela_style.bg_color = CARD_BG
	leela_style.border_color = LEELA_VIOLET
	leela_style.set_border_width_all(1)
	leela_style.set_corner_radius_all(6)
	leela_style.content_margin_left = 8
	leela_style.content_margin_right = 8
	leela_style.content_margin_top = 6
	leela_style.content_margin_bottom = 6
	_leela_panel.add_theme_stylebox_override("panel", leela_style)
	cards_hbox.add_child(_leela_panel)

	var leela_vbox := VBoxContainer.new()
	leela_vbox.add_theme_constant_override("separation", 3)
	_leela_panel.add_child(leela_vbox)

	_leela_title = Label.new()
	_leela_title.text = "🧠 LEELA (Strategy)"
	_leela_title.add_theme_font_size_override("font_size", 11)
	_leela_title.add_theme_color_override("font_color", LEELA_VIOLET)
	leela_vbox.add_child(_leela_title)

	_leela_plan = Label.new()
	_leela_plan.text = "Evaluating positional harmony..."
	_leela_plan.add_theme_font_size_override("font_size", 10)
	_leela_plan.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	_leela_plan.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_leela_plan.custom_minimum_size = Vector2(190, 52)
	leela_vbox.add_child(_leela_plan)

	_leela_btn = Button.new()
	_leela_btn.text = "🧠 [L] Strategic Move"
	_leela_btn.add_theme_font_size_override("font_size", 10)
	_leela_btn.pressed.connect(func(): leela_hint_requested.emit())
	leela_vbox.add_child(_leela_btn)


func update_analysis(info: Dictionary) -> void:
	if _panel == null:
		_build_ui()
	if not is_coach_active:
		return

	# Opening
	var op_name: String = info.get("opening_name", "")
	if not op_name.is_empty():
		_opening_label.text = "📖 %s" % op_name

	# Threat Radar
	var threats: Array = info.get("threats", [])
	if threats.is_empty():
		_threat_label.text = "🛡️ Threat: Secure"
		_threat_label.add_theme_color_override("font_color", Color(0.6, 0.95, 0.6))
	else:
		var threat_names: Array[String] = []
		for t in threats:
			threat_names.append("%s on %s" % [t.get("name", "Piece"), t.get("coord", "")])
		_threat_label.text = "⚠️ ALERT: %s under attack!" % ", ".join(threat_names)
		_threat_label.add_theme_color_override("font_color", RED_ALERT)

	# Consensus Banner
	var is_con: bool = info.get("is_consensus", false)
	_consensus_panel.visible = is_con

	# Stockfish
	var sf_dict: Dictionary = info.get("stockfish", {})
	var sf_san: String = sf_dict.get("san", "")
	var sf_eval: float = sf_dict.get("eval", 0.0)
	var sf_sign := "+" if sf_eval >= 0 else ""
	if not sf_san.is_empty():
		_sf_title.text = "⚔️ STOCKFISH 18 (%s | %s%.2f)" % [sf_san, sf_sign, sf_eval]
		_sf_plan.text = sf_dict.get("plan", "Direct tactical move.")
		_sf_btn.text = "💡 [T] Play %s" % sf_san
	else:
		_sf_plan.text = info.get("explanation", "")

	# Leela
	var leela_dict: Dictionary = info.get("leela", {})
	var leela_san: String = leela_dict.get("san", "")
	var leela_eval: float = leela_dict.get("eval", 0.0)
	var leela_sign := "+" if leela_eval >= 0 else ""
	if not leela_san.is_empty():
		_leela_title.text = "🧠 LEELA Lc0 (%s | %s%.2f)" % [leela_san, leela_sign, leela_eval]
		_leela_plan.text = leela_dict.get("plan", "Positional harmony move.")
		_leela_btn.text = "🧠 [L] Play %s" % leela_san
	else:
		_leela_plan.text = "Position is balanced."


func toggle_coach() -> bool:
	if _panel == null:
		_build_ui()
	is_coach_active = not is_coach_active
	_panel.visible = is_coach_active
	coach_toggled.emit(is_coach_active)
	return is_coach_active
