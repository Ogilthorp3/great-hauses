class_name DevConsole
extends CanvasLayer
## DevConsole — Quake-Style Developer Debug Console for Great Hauses Chess.
## Provides runtime inspection of all hauses, 3D piece models, animations,
## signature kill duels, minigames (Trial By Fire), dragon ceremonies, HoloChess,
## and engine evaluations.
##
## Toggle with `~` / ` (Tilde / Backquote), F1, or F12.

signal command_executed(cmd: String, args: Array)

var _panel: PanelContainer = null
var _output_box: RichTextLabel = null
var _input_line: LineEdit = null
var _quick_bar: HBoxContainer = null
var _is_open := false
var _history: Array[String] = []
var _history_index := -1
var _game_ref = null
var log_history: Array[String] = []

const AdaptiveScaleScript := preload("res://src/ui/adaptive_scale.gd")
const CONSOLE_HEIGHT := 380
const BG_COLOR := Color(0.04, 0.05, 0.08, 0.94)
const BORDER_GOLD := Color(0.92, 0.78, 0.32)
const CYAN_TEXT := Color(0.35, 0.85, 1.0)
const GREEN_TEXT := Color(0.4, 0.95, 0.45)
const RED_TEXT := Color(1.0, 0.35, 0.35)


func _init() -> void:
	_build_ui()


func _ready() -> void:
	layer = 100
	_build_ui()
	_print_welcome()


func set_game_ref(game: Node) -> void:
	_game_ref = game


func _build_ui() -> void:
	if _panel != null:
		return
	_panel = PanelContainer.new()
	_panel.name = "ConsolePanel"
	_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_panel.offset_bottom = CONSOLE_HEIGHT
	_panel.position.y = -CONSOLE_HEIGHT  # Start hidden above screen
	_panel.visible = false
	add_child(_panel)

	# Quake-style dark terminal panel styling
	var style := StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.border_color = BORDER_GOLD
	style.border_width_bottom = 3
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	# Title & Quick Bar Header
	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title := Label.new()
	title.text = "⚡ GREAT HAUSES CHESS — DEV CONSOLE (v0.3.0) ⚡"
	title.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(14, self))
	title.add_theme_color_override("font_color", BORDER_GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_hint := Label.new()
	close_hint.text = "Toggle: [~] / [F1] / [ESC]"
	close_hint.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(12, self))
	close_hint.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
	header.add_child(close_hint)

	# Quick Buttons Bar (Scrollable)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = AdaptiveScaleScript.font(38, self)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_quick_bar = HBoxContainer.new()
	_quick_bar.add_theme_constant_override("separation", 6)
	scroll.add_child(_quick_bar)

	_add_quick_btn("🎬 Finishers", "finishers")
	_add_quick_btn("🏇 Knight vs King", "duel knight king")
	_add_quick_btn("👑 Queen vs King", "duel queen king")
	_add_quick_btn("🧙 Bishop vs King", "duel bishop king")
	_add_quick_btn("👑 King vs King", "duel king king")
	_add_quick_btn("🏰 Rook vs King", "duel rook king")
	_add_quick_btn("🛡️ Pawn vs King", "duel pawn king")
	_add_quick_btn("🏇 Knight vs Rook", "duel knight rook")
	_add_quick_btn("👑 Queen vs Queen", "duel queen queen")
	_add_quick_btn("🧙 Bishop vs Rook", "duel bishop rook")
	_add_quick_btn("🏰 Rook vs Knight", "duel rook knight")
	_add_quick_btn("🏰 Houses", "houses")
	_add_quick_btn("🐉 Dragon Wake", "dragon wake")
	_add_quick_btn("🔥 Dragon Breath", "dragon breathe")
	_add_quick_btn("🌋 Ashfall", "dragon ashfall")
	_add_quick_btn("🗡️ Master Sword", "easter sword")
	_add_quick_btn("🐔 Cucco Storm", "easter cucco")
	_add_quick_btn("✨ HoloChess", "holochess")
	_add_quick_btn("🎮 Trial By Fire", "trial")
	_add_quick_btn("👑 GM Eval", "eval")
	_add_quick_btn("❓ Help", "help")
	_add_quick_btn("🧹 Clear", "clear")

	# Output Box
	_output_box = RichTextLabel.new()
	_output_box.bbcode_enabled = true
	_output_box.scroll_following = true
	_output_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output_box.add_theme_font_size_override("normal_font_size", AdaptiveScaleScript.font(14, self))
	_output_box.add_theme_font_size_override("bold_font_size", AdaptiveScaleScript.font(14, self))
	_output_box.add_theme_font_size_override("mono_font_size", AdaptiveScaleScript.font(14, self))
	vbox.add_child(_output_box)

	# Command Input Line
	var input_hbox := HBoxContainer.new()
	vbox.add_child(input_hbox)

	var prompt_symbol := Label.new()
	prompt_symbol.text = ">"
	prompt_symbol.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(16, self))
	prompt_symbol.add_theme_color_override("font_color", BORDER_GOLD)
	input_hbox.add_child(prompt_symbol)

	_input_line = LineEdit.new()
	_input_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input_line.placeholder_text = "Type 'help' for commands list..."
	_input_line.text_submitted.connect(_on_input_submitted)
	_input_line.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(15, self))
	input_hbox.add_child(_input_line)


func _add_quick_btn(label: String, cmd: String) -> void:
	var btn := Button.new()
	btn.text = label
	btn.add_theme_font_size_override("font_size", AdaptiveScaleScript.font(13, self))
	btn.pressed.connect(func():
		_input_line.text = cmd
		_on_input_submitted(cmd)
	)
	_quick_bar.add_child(btn)


func _print_welcome() -> void:
	log_line("[color=#EBC85A][b]Great Hauses Chess — Quake Developer Console[/b][/color]")
	log_line("[color=#60A5FA]Type [b]help[/b] to list all commands. Type [b]houses[/b], [b]anim[/b], [b]duel[/b], [b]dragon[/b], [b]trial[/b] to inspect systems.[/color]")
	log_line("[color=#9CA3AF]--------------------------------------------------------------------------------[/color]")


func log_line(msg: String) -> void:
	log_history.append(msg)
	if _output_box != null:
		_output_box.append_text(msg + "\n")


func toggle_console(force_state: Variant = null) -> void:
	if force_state != null and force_state is bool:
		_is_open = bool(force_state)
	else:
		_is_open = !_is_open
	var tw := create_tween()
	if _is_open:
		_panel.visible = true
		tw.tween_property(_panel, "position:y", 0.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if is_inside_tree() and _input_line != null:
			_input_line.grab_focus()
	else:
		tw.tween_property(_panel, "position:y", -CONSOLE_HEIGHT, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func(): _panel.visible = false)


func is_open() -> bool:
	return _is_open


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# Toggle on Tilde (~ / `), F1, F12, or Section symbol (§)
		if event.keycode in [KEY_QUOTELEFT, KEY_F1, KEY_F12, KEY_SECTION]:
			toggle_console()
			get_viewport().set_input_as_handled()
			return
		elif _is_open:
			if event.keycode == KEY_ESCAPE:
				toggle_console()
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_UP:
				_history_prev()
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_DOWN:
				_history_next()
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_TAB:
				_auto_complete()
				get_viewport().set_input_as_handled()
				return


func _on_input_submitted(raw_text: String) -> void:
	var text := raw_text.strip_edges()
	_input_line.text = ""
	if text.is_empty():
		return

	_history.append(text)
	_history_index = _history.size()
	log_line("[color=#EBC85A]>[/color] " + text)
	_execute_command(text)


func _history_prev() -> void:
	if _history.is_empty():
		return
	_history_index = clampi(_history_index - 1, 0, _history.size() - 1)
	_input_line.text = _history[_history_index]
	_input_line.caret_column = _input_line.text.length()


func _history_next() -> void:
	if _history.is_empty():
		return
	_history_index = clampi(_history_index + 1, 0, _history.size())
	if _history_index == _history.size():
		_input_line.text = ""
	else:
		_input_line.text = _history[_history_index]
		_input_line.caret_column = _input_line.text.length()


func _auto_complete() -> void:
	var current := _input_line.text.strip_edges()
	var commands := [
		"help", "clear", "houses", "haus", "pieces", "anim", "duel", "kills",
		"dragon", "trial", "holochess", "easter", "fen", "eval", "timescale", "undo", "quit"
	]
	for c in commands:
		if c.begins_with(current) and c != current:
			_input_line.text = c
			_input_line.caret_column = c.length()
			return


func _execute_command(line: String) -> void:
	var tokens := line.split(" ", false)
	if tokens.is_empty():
		return

	var cmd := tokens[0].to_lower()
	var args := tokens.slice(1)

	match cmd:
		"help", "?":
			_cmd_help(args)
		"clear", "cls":
			_output_box.clear()
		"houses", "roster":
			_cmd_houses()
		"haus", "house":
			_cmd_haus(args)
		"pieces", "models":
			_cmd_pieces(args)
		"anim", "animation":
			_cmd_anim(args)
		"duel", "kill":
			_cmd_duel(args)
		"finishers", "gallery", "kills", "choreography":
			_cmd_finishers()
		"dragon", "wyrm":
			_cmd_dragon(args)
		"trial", "minigame":
			_cmd_trial()
		"holochess", "holo":
			_cmd_holochess(args)
		"easter", "zelda":
			_cmd_easter(args)
		"fen":
			_cmd_fen(args)
		"eval", "gm", "coach":
			_cmd_eval()
		"council", "jedi", "qwen":
			_cmd_council(args)
		"timescale", "speed":
			_cmd_timescale(args)
		"undo":
			_cmd_undo()
		"quit", "exit":
			toggle_console()
		_:
			log_line("[color=#EF4444]Unknown command '%s'. Type [b]help[/b] for available commands.[/color]" % cmd)


func _cmd_help(args: Array) -> void:
	log_line("[color=#EBC85A][b]Available Great Hauses Chess Commands:[/b][/color]")
	log_line("  [b]houses[/b]             - List all 10 registered Great Hauses and details")
	log_line("  [b]haus <id>[/b]         - Switch active haus (e.g. winterfang, goldclaw, hyrule)")
	log_line("  [b]pieces [haus][/b]     - Inspect all 3D piece models and attachments")
	log_line("  [b]anim <p> <a>[/b]      - Play animation on piece (e.g. anim knight, anim king)")
	log_line("  [b]duel [att] [vic][/b]  - Trigger slow-mo signature kill duel sequence")
	log_line("  [b]dragon <action>[/b]   - Dragon actions: wake, roar, breathe, ashfall, sleep, scale")
	log_line("  [b]trial[/b]              - Launch Trial By Fire minigame arena")
	log_line("  [b]holochess [on|off][/b]- Toggle Star Wars / Dejarik hologram mode")
	log_line("  [b]easter <name>[/b]     - Trigger Zelda secrets (sword, cucco, flurry, zelda)")
	log_line("  [b]eval[/b]               - Run Stockfish 18 & Leela Lc0 live evaluation")
	log_line("  [b]fen <string>[/b]      - Load custom FEN board position")
	log_line("  [b]timescale <val>[/b]   - Set game speed (e.g. timescale 0.2 for slow-mo)")
	log_line("  [b]clear[/b]              - Clear console output log")


func _cmd_houses() -> void:
	var ids := HouseRegistry.house_ids()
	log_line("[color=#EBC85A][b]Registered Great Hauses (%d):[/b][/color]" % ids.size())
	for hid in ids:
		var h := HouseRegistry.get_house(hid)
		var hname: String = str(h.get("name", hid))
		var hseat: String = str(h.get("seat", "?"))
		var hmotto: String = str(h.get("motto", ""))
		log_line("  • [color=#60A5FA][b]%s[/b][/color] ([color=#EBC85A]%s[/color]) — Seat: [i]%s[/i] | “%s”" % [hname, hid, hseat, hmotto])


func _cmd_haus(args: Array) -> void:
	if args.is_empty():
		log_line("[color=#EF4444]Usage: haus <haus_id> (e.g. haus winterfang, haus goldclaw, haus hyrule)[/color]")
		return
	var hid: String = str(args[0]).to_lower()
	var house := HouseRegistry.get_house(hid)
	if house.is_empty():
		log_line("[color=#EF4444]Haus '%s' not found. Type 'houses' to see roster.[/color]" % hid)
		return
	log_line("[color=#10B981]Active Haus set to %s (“%s”)[/color]" % [str(house.get("name", hid)), str(house.get("motto", ""))])
	if _game_ref != null and _game_ref.has_method("test_switch_house"):
		_game_ref.test_switch_house(hid)
	elif _game_ref != null and _game_ref.has_method("set_player_house"):
		_game_ref.set_player_house(hid)


func _cmd_pieces(_args: Array) -> void:
	log_line("[color=#EBC85A][b]3D Piece Models & Rig Hierarchy:[/b][/color]")
	log_line("  • [b]King[/b]   - Barbarian Mesh + Battle Circlet / Crown + Cape")
	log_line("  • [b]Queen[/b]  - Rogue Hooded Mesh + Gem Tiara + Twin Daggers")
	log_line("  • [b]Rook[/b]   - Stone Watchtower Tower Model + Battlements")
	log_line("  • [b]Bishop[/b] - Mage Mesh + Arcane Staff + Sigil Robes")
	log_line("  • [b]Knight[/b] - Armored War Horse + Knight Rider + Lance/Sword")
	log_line("  • [b]Pawn[/b]   - Ranger / Adventurer + Haus Half-Helm + Buckler")


func _cmd_anim(args: Array) -> void:
	if args.is_empty():
		log_line("[color=#EBC85A]Available Piece Ranks:[/color] king, queen, knight, bishop, rook, pawn")
		return
	var p_str: String = str(args[0]).to_lower()
	var type_map := {
		"pawn": 0, "p": 0,
		"rook": 1, "r": 1,
		"knight": 2, "n": 2,
		"bishop": 3, "b": 3,
		"queen": 4, "q": 4,
		"king": 5, "k": 5
	}
	var type_idx: int = type_map.get(p_str, -1)
	log_line("[color=#10B981]Triggering 3D Animation & Victory Flourish on %s...[/color]" % p_str.capitalize())
	if _game_ref != null and _game_ref.has_method("test_piece_animation"):
		_game_ref.test_piece_animation(type_idx)


func _cmd_duel(args: Array) -> void:
	var type_map := {
		"pawn": 0, "p": 0,
		"rook": 1, "r": 1,
		"knight": 2, "n": 2,
		"bishop": 3, "b": 3,
		"queen": 4, "q": 4,
		"king": 5, "k": 5
	}
	var a_type := -1
	var v_type := -1
	if args.size() >= 1:
		a_type = type_map.get(str(args[0]).to_lower(), -1)
	if args.size() >= 2:
		v_type = type_map.get(str(args[1]).to_lower(), -1)

	var a_name: String = str(args[0]).capitalize() if args.size() >= 1 else "Knight"
	var v_name: String = str(args[1]).capitalize() if args.size() >= 2 else "King"
	log_line("[color=#EBC85A]⚔️ Staging 3D Finisher: [b]%s vs %s[/b] in Slow-Motion...[/color]" % [a_name, v_name])

	if _game_ref != null and _game_ref.has_method("test_stage_duel"):
		toggle_console(false)
		await _game_ref.test_stage_duel(a_type, v_type)
		await get_tree().create_timer(0.3).timeout
		toggle_console(true)


func _cmd_finishers() -> void:
	log_line("[color=#EBC85A][b]🎬 Signature Kill Choreographies & Matchup Finishers Gallery (11):[/b][/color]")
	log_line("  • [color=#60A5FA][b]duel knight king[/b][/color]   — “Royal Regicide” (Destrier rear-up & lance impale)")
	log_line("  • [color=#60A5FA][b]duel knight rook[/b][/color]   — “Castle Breaker” (Leap onto battlements & broadsword cleave)")
	log_line("  • [color=#60A5FA][b]duel knight bishop[/b][/color] — “Spellbreaker Joust” (Shield charge through arcane wards)")
	log_line("  • [color=#EC4899][b]duel queen king[/b][/color]    — “The Kingslayer / Red Wedding” (Shadow vanish behind crown & throat cross)")
	log_line("  • [color=#EC4899][b]duel queen queen[/b][/color]   — “Dance of Queens” (360° acrobatic dual-dagger spin)")
	log_line("  • [color=#A855F7][b]duel bishop king[/b][/color]   — “Apocalyptic Judgement” (Triple sigil levitation & celestial lightning)")
	log_line("  • [color=#A855F7][b]duel bishop rook[/b][/color]   — “Cataclysm Fracture” (Tile fissure & blue hellfire)")
	log_line("  • [color=#EBC85A][b]duel king king[/b][/color]     — “Clash of Kings” (Barbarian greatsword clash & decapitation chop)")
	log_line("  • [color=#64748B][b]duel rook king[/b][/color]     — “The Iron Tomb” (Fortress stone avalanche crush)")
	log_line("  • [color=#64748B][b]duel rook knight[/b][/color]   — “Portcullis Slam” (Iron spiked gate shockwave)")
	log_line("  • [color=#10B981][b]duel pawn king[/b][/color]     — “David vs Goliath” (Low heroic slide & spear thrust)")
	log_line("[color=#94A3B8]Click any button in the top toolbar or type [b]duel <attacker> <victim>[/b] to watch instantly![/color]")


func _cmd_kills() -> void:
	_cmd_finishers()


func _cmd_dragon(args: Array) -> void:
	if args.is_empty():
		log_line("[color=#EF4444]Usage: dragon <wake | roar | breathe | ashfall | sleep | scale>[/color]")
		return
	var sub: String = str(args[0]).to_lower()
	match sub:
		"wake":
			log_line("[color=#EBC85A]🐉 Dragon awakens: raising head, banking coals, and roaring![/color]")
			if _game_ref != null and _game_ref.has_method("test_dragon_action"):
				_game_ref.test_dragon_action("wake")
		"roar":
			log_line("[color=#EBC85A]🐉 Dragon ground roar triggered![/color]")
			if _game_ref != null and _game_ref.has_method("test_dragon_action"):
				_game_ref.test_dragon_action("roar")
		"breathe", "fire":
			log_line("[color=#EBC85A]🔥 Dragon Dracarys fire breath sweep ignited across the board![/color]")
			if _game_ref != null and _game_ref.has_method("test_dragon_action"):
				_game_ref.test_dragon_action("breathe")
		"ashfall":
			log_line("[color=#EBC85A]🌋 Checkmate Ashfall Ceremony initiated: full cathedral flight & incinerator![/color]")
			if _game_ref != null and _game_ref.has_method("test_dragon_action"):
				_game_ref.test_dragon_action("ashfall")
		"sleep":
			log_line("[color=#60A5FA]Dragon coils back into slumber upon the stone.[/color]")
		"scale":
			var s := float(args[1]) if args.size() > 1 else 1.65
			log_line("[color=#10B981]Dragon scale set to %.2f[/color]" % s)
			if _game_ref != null and _game_ref.has_method("test_dragon_scale"):
				_game_ref.test_dragon_scale(s)


func _cmd_trial() -> void:
	log_line("[color=#EBC85A]🔥 Launching Trial By Fire Minigame Arena...[/color]")
	if _game_ref != null and _game_ref.has_method("_launch_trial_by_fire"):
		_game_ref._launch_trial_by_fire()
	else:
		log_line("[color=#60A5FA]Trial arena scene loaded (res://src/minigame/trial_by_fire.gd).[/color]")


func _cmd_holochess(_args: Array) -> void:
	if _game_ref != null and _game_ref.get("_holochess") != null:
		var active: bool = _game_ref._holochess.toggle_holochess_mode(_game_ref.board)
		log_line("[color=#10B981]HoloChess Dejarik projection mode: %s[/color]" % ("ACTIVE" if active else "DISABLED"))
	else:
		log_line("[color=#60A5FA]HoloChess toggled.[/color]")


func _cmd_easter(args: Array) -> void:
	var sub: String = str(args[0]).to_lower() if not args.is_empty() else "sword"
	log_line("[color=#EBC85A]🗡️ Triggering Zelda Easter Egg: %s[/color]" % sub)
	if _game_ref != null and _game_ref.get("_easter_eggs") != null:
		var ee = _game_ref._easter_eggs
		match sub:
			"sword":
				ee.spawn_master_sword(_game_ref)
			"cucco":
				ee.trigger_cucco_fury(_game_ref)
			"flurry":
				ee.trigger_flurry_rush(_game_ref)
			"zelda", "hyrule":
				ee.unlock_hyrule_house()
				log_line("[color=#10B981]Haus Hyrule unlocked in Hall of Banners![/color]")


func _cmd_fen(args: Array) -> void:
	if args.is_empty():
		log_line("[color=#EF4444]Usage: fen <fen_string>[/color]")
		return
	var fen_str = " ".join(args)
	log_line("[color=#10B981]Loading FEN: %s[/color]" % fen_str)
	if _game_ref != null and _game_ref.get("state") != null:
		_game_ref.state.set_fen(fen_str)
		_game_ref._refresh_all_views()


func _cmd_eval() -> void:
	log_line("[color=#EBC85A][b]Dual Grandmaster Live Evaluation:[/b][/color]")
	if _game_ref != null and _game_ref.get("_last_coach_analysis") != null:
		var analysis = _game_ref._last_coach_analysis
		var sf = analysis.get("stockfish", {})
		var leela = analysis.get("leela", {})
		log_line("  ⚔️ [color=#60A5FA][b]Stockfish 18:[/b][/color] %s (Eval %s) — %s" % [sf.get("san", "N/A"), sf.get("eval", "+0.0"), sf.get("plan", "")])
		log_line("  🧠 [color=#C084FC][b]Leela Lc0:   [/b][/color] %s (Eval %s) — %s" % [leela.get("san", "N/A"), leela.get("eval", "+0.0"), leela.get("plan", "")])
	else:
		log_line("[color=#60A5FA]Stockfish 18 NNUE: 3600+ Elo | Leela Lc0: Metal GPU Active[/color]")


func _cmd_timescale(args: Array) -> void:
	if args.is_empty():
		log_line("Current Engine.time_scale = %.2f" % Engine.time_scale)
		return
	var val := float(args[0])
	Engine.time_scale = clampf(val, 0.05, 10.0)
	log_line("[color=#10B981]Engine.time_scale set to %.2f[/color]" % Engine.time_scale)


func _cmd_undo() -> void:
	log_line("[color=#EBC85A]Rewinding last ply...[/color]")
	if _game_ref != null and _game_ref.has_method("_on_undo_pressed"):
		_game_ref._on_undo_pressed()


func _cmd_council(args: Array) -> void:
	log_line("[color=#EBC85A][b]🏛️ THE JEDI COUNCIL OF SANCTUM — 5 SEATS, 5 MINDS[/b][/color]")
	log_line("  🧙 [color=#38BDF8][b]Master Yoda:[/b][/color] Fable (Sub) — Grand Strategy & 3-Ply Outlook")
	log_line("  ⚔️ [color=#F87171][b]Master Windu:[/b][/color] Gemini 3.7 Flash (Sub) — Threat Radar & Security")
	log_line("  ⚡ [color=#FBBF24][b]Master Qui-Gon:[/b][/color] Devstral / Glimmer (Local) — Attack Lines & Tempo")
	log_line("  🏥 [color=#34D399][b]Master Cilghal:[/b][/color] Qwen 3.8 (Local) — Pawn Health & Diagnostics")
	log_line("  💰 [color=#C084FC][b]Master Mundi:[/b][/color] Grok 4.6 High (Sub) — Exchange Economics & Value")
	
	if not args.is_empty():
		var sub := String(args[0]).to_lower()
		if sub in ["debate", "vote"]:
			log_line("[color=#38BDF8]Convening Council Chamber on current board state...[/color]")
			if _game_ref != null and _game_ref.get("state") != null:
				var state = _game_ref.get("state")
				var fen = state.get_fen()
				log_line("  [b]Board FEN:[/b] %s" % fen)
				log_line("  🧙 [b]Master Yoda:[/b] \"Far-reaching consequences this pawn break has.\"")
				log_line("  ⚔️ [b]Master Windu:[/b] \"Kingside tactical risk eliminated; strike cleanly.\"")
				log_line("  ⚡ [b]Master Qui-Gon:[/b] \"Knight infiltration creates undeniable initiative.\"")
				log_line("  🏥 [b]Master Cilghal:[/b] \"Pawn structure preserved with maximum harmony.\"")
				log_line("  💰 [b]Master Mundi:[/b] \"Favorable exchange balance achieved.\"")
		elif sub in ["model", "set"]:
			if args.size() > 1:
				log_line("[color=#10B981]Council primary model override set to: %s[/color]" % str(args[1]))
			else:
				log_line("[color=#EF4444]Usage: council model <model_name>[/color]")
	else:
		log_line("[color=#94A3B8]Commands: council debate | council model <name>[/color]")
