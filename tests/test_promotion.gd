extends SceneTree

# Headless test suite for PROMOTION — the choice, the chess, and the wire.
# Run: /Applications/Godot.app/Contents/MacOS/Godot --headless --path <project> \
#          -s res://tests/test_promotion.gd
# Exit code 0 = all green, 1 = failures.
#
# ALBERT'S BUG. For four months a promoting pawn in this game could only ever
# become a queen. The engine was never at fault — `construct_move` has always
# taken any piece and the perft suite has always proven `a7a8n` — the UI threw
# the other three away before the player saw them. This suite is the standing
# proof that all four are reachable, that they are DIFFERENT MOVES, and that
# the piece a player picks survives every path it has to travel.
#
# WHY UNDERPROMOTION IS REAL CHESS AND NOT A CURIOSITY — both halves proven
# below on ONE position (UNDER_FEN):
#   * a KNIGHT gives CHECK from a square where a queen gives none, and
#   * a ROOK avoids the STALEMATE that the queen would have caused.
# The same position drives the `promote` e2e scenario, so the thing the player
# clicks through is the thing asserted here.
#
# Also proven:
#   * the engine offers exactly four promotions per promotion square,
#   * undoing any of the four puts the PAWN back and restores the FEN byte for
#     byte (a take-back must never leave a queen standing),
#   * HOST AUTHORITY over the promotion piece: the validator honours q/r/b/n,
#     falls back to the QUEEN BY NAME for an empty/unknown/hostile `promo`,
#     and only ever returns a move the HOST ITSELF generated,
#   * the promotion piece survives encode -> decode on the wire,
#   * the picker's own contract (order, default, key map, piece types),
#   * the two-instance e2e's scripted game is legal AND its underpromotion is
#     LOAD-BEARING — promoting to a queen there would check White and make the
#     scripted mate illegal, so a picked knight that silently became a queen
#     could not possibly pass the head-to-head gate.

const CS := preload("res://src/chess/ChessState.gd")
const NP := preload("res://src/net/net_protocol.gd")

# NOTE — the test_costumes.gd rule: a `-s` run never instances autoloads, and
# any script that NAMES the PieceAssets global fails to COMPILE until a node
# called "PieceAssets" hangs under /root. The promotion picker builds real
# PieceViews, so it is one of those scripts: shim the autoload first, then
# load() the picker and the e2e driver, and touch their constants through the
# script constant map instead of a const preload.
const T_ROOK := 1        # PieceView.Type mirrors (see test_costumes.gd)
const T_KNIGHT := 2
const T_BISHOP := 3
const T_QUEEN := 4

## A hard-erroring test function aborts silently at the error, so "no FAIL
## lines" is not proof the suite ran. This floor makes that loud.
const MIN_EXPECTED_CHECKS := 85

var assets: Node          # the PieceAssets shim
var PICKER: Dictionary = {}   # promotion_picker.gd's constants
var E2E: Dictionary = {}      # e2e_driver.gd's constants

## THE PROMOTION PROBLEM (also test_e2e/run_e2e.sh PROMOTE_FEN).
## White: Kb5, Pc7, Ph6.  Black: Ka7, Ph7 (wedged behind h6, it has no move).
## White to play. c8=Q stalemates. c8=R does not. c8=N is check.
const UNDER_FEN := "8/k1P4p/7P/1K6/8/8/8/8 w - - 0 1"
## The plain promotion position kept from the older suites.
const PROMO_FEN := "7k/P7/8/8/8/8/8/K7 w - - 0 1"

var rows := []
var failures := 0


func _initialize() -> void:
	print("=== Great Hauses — promotion (the choice) test suite ===")
	assets = load("res://src/board/piece_assets.gd").new()
	assets.name = "PieceAssets"
	get_root().add_child(assets)
	PICKER = load("res://src/ui/promotion_picker.gd").get_script_constant_map()
	E2E = load("res://test_e2e/e2e_driver.gd").get_script_constant_map()
	_test_four_choices()
	_test_why_it_matters()
	_test_undo_restores_the_pawn()
	_test_host_authority_over_the_piece()
	_test_wire_round_trip()
	_test_picker_contract()
	_test_net_scripted_underpromotion()
	_print_summary()


# ── helpers ────────────────────────────────────────────────────────────────


func check(test_name: String, expected, actual) -> void:
	var ok := str(expected) == str(actual)
	if not ok:
		failures += 1
	rows.push_back([test_name, str(expected), str(actual), ok])


func fresh(fen: String):
	var s = CS.new()
	if not s.set_fen(fen):
		push_error("test FEN refused by the engine: %s" % fen)
	return s


func after(fen: String, uci: String):
	## The position that `uci` produces from `fen`. Returns null if illegal.
	var s = fresh(fen)
	var m = s.move_from_uci(uci)
	if m == null:
		return null
	s.apply_move(m)
	return s


func result_name(state) -> String:
	return CS.RESULT.keys()[state.get_result()]


# ── the four choices exist, and they are four different moves ──────────────


func _test_four_choices() -> void:
	var s = fresh(PROMO_FEN)
	var seen := {}
	for m in s.legal_moves():
		if m.from_square == CS.square_index_from_name("a7"):
			seen[str(m.promotion).to_lower()] = m.to_uci()
	check("choices: the engine offers exactly four promotions", 4, seen.size())
	check("choices: queen offered", "a7a8q", str(seen.get("q", "")))
	check("choices: rook offered", "a7a8r", str(seen.get("r", "")))
	check("choices: bishop offered", "a7a8b", str(seen.get("b", "")))
	check("choices: knight offered", "a7a8n", str(seen.get("n", "")))
	# Four moves, four different boards — the reason a picker is not cosmetic.
	var fens := {}
	for uci in ["a7a8q", "a7a8r", "a7a8b", "a7a8n"]:
		fens[str(after(PROMO_FEN, uci).get_fen())] = true
	check("choices: the four promotions produce four DIFFERENT positions", 4, fens.size())
	# ...and SAN names the piece, so the HUD move list says which one was taken
	# (a8=R+ and a8=Q+ carry their check mark; a8=N and a8=B do not).
	var sans: Array[String] = []
	for m in fresh(PROMO_FEN).legal_moves(true):
		if m.promotion != null:
			sans.append(str(m.notation_san))
	sans.sort()
	check("choices: SAN records the promoted piece",
			"[\"a8=B\", \"a8=N\", \"a8=Q+\", \"a8=R+\"]", str(sans))


# ── the two proofs that make this real chess ───────────────────────────────


func _test_why_it_matters() -> void:
	var start = fresh(UNDER_FEN)
	check("why: the problem position is White to move", false, start.turn)
	var promos := 0
	for m in start.legal_moves():
		if m.promotion != null:
			promos += 1
	check("why: all four promotions available on c8", 4, promos)

	# THE KNIGHT GIVES CHECK WHERE THE QUEEN GIVES NONE. Nc8 forks out to a7;
	# a queen on c8 sees the 8th rank, the c-file and the b7/d7 diagonal — and
	# not the black king's square at all.
	var knight = after(UNDER_FEN, "c7c8n")
	var queen = after(UNDER_FEN, "c7c8q")
	check("why: knight promotion gives CHECK", true, knight.in_check())
	check("why: queen promotion gives no check", false, queen.in_check())

	# THE ROOK AVOIDS THE STALEMATE THE QUEEN CAUSES. The black king's last
	# square is b7, which the queen covers diagonally and the rook cannot.
	check("why: queen promotion STALEMATES the opponent",
			"STALEMATE", result_name(queen))
	check("why: rook promotion leaves the war ONGOING",
			"ONGOING", result_name(after(UNDER_FEN, "c7c8r")))
	check("why: bishop promotion leaves the war ONGOING",
			"ONGOING", result_name(after(UNDER_FEN, "c7c8b")))
	check("why: knight promotion leaves the war ONGOING (check, not mate)",
			"ONGOING", result_name(knight))
	var rook = after(UNDER_FEN, "c7c8r")
	check("why: after the rook, Black has exactly one move left", 1,
			rook.legal_moves().size())
	check("why: and that move is Kb7", "a7b7", str(rook.legal_moves()[0].to_uci()))


# ── a take-back must never leave a queen standing ──────────────────────────


func _test_undo_restores_the_pawn() -> void:
	for piece in ["q", "r", "b", "n"]:
		var s = fresh(UNDER_FEN)
		var m = s.move_from_uci("c7c8" + piece)
		check("undo: c7c8%s is legal" % piece, true, m != null)
		if m == null:
			continue
		s.apply_move(m)
		var c8 := CS.square_index_from_name("c8")
		check("undo: %s stands on c8 before the take-back" % piece,
				piece.to_upper(), str(s.pieces[c8]))
		s.undo()
		check("undo: the PAWN is back on c7 (%s)" % piece, "P",
				str(s.pieces[CS.square_index_from_name("c7")]))
		check("undo: c8 is empty again (%s)" % piece, "<null>",
				"<null>" if s.pieces[c8] == null else str(s.pieces[c8]))
		check("undo: the position is byte-identical again (%s)" % piece,
				UNDER_FEN, str(s.get_fen()))


# ── HOST AUTHORITY: the client picks, the host decides ─────────────────────


func _test_host_authority_over_the_piece() -> void:
	var from_idx := CS.square_index_from_name("c7")
	var to_idx := CS.square_index_from_name("c8")
	for piece in NP.PROMOTION_PIECES:
		var host = fresh(UNDER_FEN)
		var fen_before := str(host.get_fen())
		var v := NP.validate_request(host, false, from_idx, to_idx, piece)
		check("host: '%s' is accepted" % piece, true, bool(v["ok"]))
		check("host: '%s' comes back as the %s" % [piece, piece],
				piece, str(v["move"].promotion).to_lower() if v["ok"] else "-")
		# The returned move must be one the HOST generated, not one assembled
		# from what the packet claimed: it has to appear in the host's own
		# legal-move list AND carry the engine metadata only the generator
		# fills in (the mover, and the halfmove clock to undo back to).
		var mine := false
		for m in host.legal_moves(true):
			if m.to_uci() == v["move"].to_uci():
				mine = true
				break
		check("host: '%s' returns a move the HOST ITSELF generated" % piece, true, mine)
		check("host: '%s' carries engine metadata, not packet fields" % piece, true,
				bool(v["ok"]) and str(v["move"].piece) == "P" \
					and int(v["move"].prev_halfmove_clock) >= 0)
		check("host: validating '%s' never mutates the board" % piece,
				fen_before, str(host.get_fen()))

	# Everything a client can put on the wire that is not one of the four.
	for junk in ["", "k", "p", "x", "QQ", "nq", "1", "knight"]:
		var host = fresh(UNDER_FEN)
		var v := NP.validate_request(host, false, from_idx, to_idx, junk)
		check("host: unreadable promo '%s' falls back to the QUEEN"
				% junk.strip_edges(), "q",
				str(v["move"].promotion).to_lower() if bool(v["ok"]) else "-")

	# Case does not decide the piece: "N" is the same request as "n".
	var host_upper = fresh(UNDER_FEN)
	var upper := NP.validate_request(host_upper, false, from_idx, to_idx, "N")
	check("host: 'N' and 'n' are the same request", "n",
			str(upper["move"].promotion).to_lower() if bool(upper["ok"]) else "-")

	# ...and a promotion request for a square that is not a promotion is still
	# just the ordinary move (the picker never opens there).
	var plain = fresh(UNDER_FEN)
	var kb := NP.validate_request(plain, false, CS.square_index_from_name("b5"),
			CS.square_index_from_name("b4"), "n")
	check("host: a non-promotion move ignores the promo field", true,
			bool(kb["ok"]) and kb["move"].promotion == null)


# ── the wire ───────────────────────────────────────────────────────────────


func _test_wire_round_trip() -> void:
	for piece in NP.PROMOTION_PIECES:
		var s = fresh(UNDER_FEN)
		var m = s.move_from_uci("c7c8" + piece)
		var back = NP.decode_move(NP.encode_move(m))
		check("wire: '%s' survives encode -> decode" % piece,
				str(m.promotion), str(back.promotion))
		check("wire: '%s' keeps its uci" % piece, m.to_uci(), back.to_uci())
	# A payload with no promo field at all decodes to a non-promotion move
	# rather than an invented queen. (Kb4, not Kb6 — b6 stands beside the
	# black king and is not a legal square at all.)
	var d := NP.encode_move(fresh(UNDER_FEN).move_from_uci("b5b4"))
	check("wire: an ordinary move carries no promotion", "<null>",
			"<null>" if NP.decode_move(d).promotion == null else "set")


# ── the picker's own contract ──────────────────────────────────────────────


func _test_picker_contract() -> void:
	var order: Array = PICKER.get("ORDER", [])
	var type_of: Dictionary = PICKER.get("TYPE_OF", {})
	var names_of: Dictionary = PICKER.get("NAMES", {})
	var hotkeys: Dictionary = PICKER.get("HOTKEY", {})
	check("picker: four choices, queen first",
			"[\"q\", \"r\", \"b\", \"n\"]", str(order))
	check("picker: the silent default is the queen", "q", str(PICKER.get("DEFAULT_PIECE")))
	check("picker: the order matches the wire's own piece list",
			str(NP.PROMOTION_PIECES), str(order))
	var names: Array[String] = []
	for pc in order:
		names.append(str(names_of[pc]))
	check("picker: every choice is NAMED for the player",
			"[\"Queen\", \"Rook\", \"Bishop\", \"Knight\"]", str(names))
	check("picker: every choice has its own model type", 4, type_of.size())
	check("picker: the queen card builds a QUEEN", T_QUEEN, int(type_of["q"]))
	check("picker: the rook card builds a ROOK", T_ROOK, int(type_of["r"]))
	check("picker: the bishop card builds a BISHOP", T_BISHOP, int(type_of["b"]))
	check("picker: the knight card builds a KNIGHT", T_KNIGHT, int(type_of["n"]))
	# A KEYBOARD PATH FOR EVERY CHOICE, and no two on the same key.
	var keyed: Array[String] = []
	for k in hotkeys:
		keyed.append(str(hotkeys[k]))
	keyed.sort()
	check("picker: one distinct hotkey per choice", "[\"b\", \"n\", \"q\", \"r\"]", str(keyed))
	var timeout := float(PICKER.get("PICK_TIMEOUT_SEC", 0.0))
	check("picker: the modal cannot wait forever", true,
			timeout > 0.0 and timeout <= 60.0)


# ── the head-to-head script, verified before it is written down ────────────


func _test_net_scripted_underpromotion() -> void:
	## The two-instance gate (test_e2e/run_net_e2e.sh) plays a scripted game in
	## which the JOINER underpromotes. Walking it here proves (a) the script is
	## legal, and (b) the knight is LOAD-BEARING: a queen on the same square
	## would check White, so the scripted mate could not be played. A picked
	## knight that silently became a queen cannot pass that gate.
	var white: Array = E2E.get("NET_LINE_WHITE", [])
	var black: Array = E2E.get("NET_LINE_BLACK", [])
	var total := int(E2E.get("NET_TOTAL_PLIES", 0))
	var s = fresh(str(E2E.get("NET_FEN", "")))
	var line: Array[String] = []
	for i in maxi(white.size(), black.size()):
		if i < white.size():
			line.append(str(white[i]))
		if i < black.size():
			line.append(str(black[i]))
	check("net-script: the scripted game is %d plies" % total, total, line.size())
	var promoted_at := ""
	var played := 0
	for uci in line:
		var m = s.move_from_uci(uci)
		if m == null:
			check("net-script: ply %d (%s) is legal" % [played, uci], true, false)
			return
		if m.promotion != null:
			promoted_at = uci
		s.apply_move(m)
		played += 1
	check("net-script: every scripted ply is legal", E2E.NET_TOTAL_PLIES, played)
	check("net-script: the joiner underpromotes to a KNIGHT", "b2b1n", promoted_at)
	check("net-script: the scripted game ends in CHECKMATE", "CHECKMATE", result_name(s))
	check("net-script: the knight is still standing on b1", "n",
			str(s.pieces[CS.square_index_from_name("b1")]))

	# The counterfactual: the same game with a QUEEN instead.
	var q = fresh(E2E.NET_FEN)
	for uci in line:
		var want := uci
		if uci == "b2b1n":
			want = "b2b1q"
		var m = q.move_from_uci(want)
		if m == null:
			check("net-script: a QUEEN there makes the scripted mate ILLEGAL",
					true, want == "a1a8")
			check("net-script: ...because the queen checks White", true, q.in_check())
			return
		q.apply_move(m)
	check("net-script: a QUEEN there makes the scripted mate ILLEGAL", true, false)


# ── reporting ──────────────────────────────────────────────────────────────


func _short(s: String, width: int) -> String:
	if s.length() <= width:
		return s
	return s.substr(0, width - 3) + "..."


func _print_summary() -> void:
	print("")
	print("%-4s %-62s %-20s %-20s %-6s" % ["#", "Test", "Expected", "Actual", "Pass"])
	print("-".repeat(116))
	var i := 1
	for row in rows:
		print("%-4d %-62s %-20s %-20s %-6s" % [i, _short(row[0], 62),
				_short(row[1], 20), _short(row[2], 20), "PASS" if row[3] else "FAIL"])
		i += 1
	print("-".repeat(116))
	var total := rows.size()
	# A hard error aborts a test function silently and its checks never run —
	# so an empty failure list is not proof the suite executed (the
	# test_costumes.gd floor, same reason).
	if total < MIN_EXPECTED_CHECKS:
		failures += 1
		print("FAIL: only %d checks ran, expected at least %d — a test aborted silently"
				% [total, MIN_EXPECTED_CHECKS])
	print("TOTAL: %d  PASSED: %d  FAILED: %d" % [total, total - failures, failures])
	print("RESULT: %s" % ("ALL GREEN" if failures == 0 else "FAILURES PRESENT"))
	quit(1 if failures > 0 else 0)
