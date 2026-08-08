extends SceneTree

# Headless test suite for the Great Houses chess engine port.
# Run: /Applications/Godot.app/Contents/MacOS/Godot --headless --path <project> -s res://tests/run_tests.gd
# Exit code 0 = all green, 1 = failures.

const CS := preload("res://src/chess/ChessState.gd")
const CA := preload("res://src/chess/ChessAI.gd")

const KIWIPETE := "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"

var rows := []
var failures := 0
var _mark := 0


func _initialize() -> void:
	_main()


func _main() -> void:
	print("=== Great Houses Chess Engine — headless test suite ===")
	_mark = Time.get_ticks_msec()
	_test_fen()
	_test_castling()
	_test_en_passant()
	_test_promotion()
	_test_results_and_draws()
	_test_perft()
	await _test_ai()
	_print_summary()


## Helpers ##

func check(test_name: String, expected, actual) -> void:
	var now := Time.get_ticks_msec()
	var ms := now - _mark
	_mark = now
	var ok := str(expected) == str(actual)
	if not ok:
		failures += 1
	rows.push_back([test_name, str(expected), str(actual), ok, ms])


func ucis(state) -> Array:
	var list := []
	for m in state.legal_moves():
		list.push_back(m.to_uci())
	return list


func apply_uci(state, uci: String) -> bool:
	var m = state.move_from_uci(uci)
	if m == null:
		return false
	state.apply_move(m)
	return true


func result_name(state) -> String:
	return CS.RESULT.keys()[state.get_result()]


func perft(state, depth: int) -> int:
	if depth == 0:
		return 1
	var moves: Array = state.generate_legal_moves(false)
	if depth == 1:
		return moves.size()
	var total := 0
	for m in moves:
		state.play_move(m)
		total += perft(state, depth - 1)
		state.undo()
	return total


## Tests ##

func _test_fen() -> void:
	var state := CS.new()
	check("fen: startpos roundtrip", CS.INITIAL_FEN, state.get_fen())
	check("fen: kiwipete accepted", true, state.set_fen(KIWIPETE))
	check("fen: kiwipete roundtrip", KIWIPETE, state.get_fen())
	var before := state.get_fen()
	check("fen: invalid rejected", false, state.set_fen("totally invalid"))
	check("fen: state unchanged after reject", before, state.get_fen())


func _test_castling() -> void:
	var state := CS.new()
	check("castle: clean O-O fen", true, state.set_fen("4k3/8/8/8/8/8/8/4K2R w K - 0 1"))
	var u := ucis(state)
	check("castle: O-O available", true, u.has("e1g1"))
	var m = state.move_from_uci("e1g1")
	check("castle: kingside flags set", true, m.is_castling and m.castle_kingside)
	check("castle: rook path h1->f1", "h1f1",
			CS.square_get_name(m.rook_from) + CS.square_get_name(m.rook_to))
	state.apply_move(m)
	check("castle: applied K on g1, R on f1", "RK",
			str(state.pieces[CS.SQUARES.F1]) + str(state.pieces[CS.SQUARES.G1]))
	state.undo()
	check("castle: undo restores e1/h1", "KR",
			str(state.pieces[CS.SQUARES.E1]) + str(state.pieces[CS.SQUARES.H1]))

	check("castle: through-check fen", true, state.set_fen("4kr2/8/8/8/8/8/8/4K2R w K - 0 1"))
	u = ucis(state)
	check("castle: through check forbidden", false, u.has("e1g1"))
	check("castle: king can't step into f1", false, u.has("e1f1"))

	check("castle: into-check fen", true, state.set_fen("4k1r1/8/8/8/8/8/8/4K2R w K - 0 1"))
	check("castle: into check forbidden", false, ucis(state).has("e1g1"))

	check("castle: while-in-check fen", true, state.set_fen("4k3/8/8/8/7b/8/8/4K2R w K - 0 1"))
	check("castle: while in check forbidden", false, ucis(state).has("e1g1"))

	check("castle: O-O-O b1-attacked fen", true, state.set_fen("1r2k3/8/8/8/8/8/8/R3K3 w Q - 0 1"))
	check("castle: O-O-O legal with b1 attacked", true, ucis(state).has("e1c1"))

	check("castle: O-O-O b1-occupied fen", true, state.set_fen("4k3/8/8/8/8/8/8/RN2K3 w Q - 0 1"))
	check("castle: O-O-O blocked by b1 piece", false, ucis(state).has("e1c1"))


func _test_en_passant() -> void:
	var state := CS.new()
	check("ep: capture fen accepted", true,
			state.set_fen("rnbqkbnr/ppp1pppp/8/8/3pP3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 2"))
	var u := ucis(state)
	check("ep: d4xe3 available", true, u.has("d4e3"))
	var m = state.move_from_uci("d4e3")
	check("ep: move flagged en_passant", true, m.en_passant)
	check("ep: captured square is e4", "e4", CS.square_get_name(m.captured_square))
	state.apply_move(m)
	check("ep: captured pawn removed from e4", "<null>", str(state.pieces[CS.SQUARES.E4]))
	check("ep: capturing pawn lands on e3", "p", str(state.pieces[CS.SQUARES.E3]))
	state.undo()
	check("ep: undo restores both pawns", "Pp",
			str(state.pieces[CS.SQUARES.E4]) + str(state.pieces[CS.SQUARES.D4]))

	# Discovered check along the rank makes the ep capture illegal (pinned ep pawn)
	check("ep: pinned fen accepted", true, state.set_fen("8/8/8/8/k2Pp2Q/8/8/4K3 b - d3 0 1"))
	check("ep: pinned target pruned from fen", "-", state.get_fen().split(" ")[3])
	u = ucis(state)
	check("ep: discovered-check capture forbidden", false, u.has("e4d3"))
	check("ep: plain pawn push still legal", true, u.has("e4e3"))


func _test_promotion() -> void:
	var state := CS.new()
	check("promo: fen accepted", true, state.set_fen("8/P6k/8/8/8/8/8/K7 w - - 0 1"))
	var u := ucis(state)
	check("promo: all four promotions offered", true,
			u.has("a7a8q") and u.has("a7a8n") and u.has("a7a8r") and u.has("a7a8b"))
	var m = state.move_from_uci("a7a8n")
	check("promo: underpromotion piece is N", "N", str(m.promotion))
	state.apply_move(m)
	check("promo: knight on a8 after apply", "N", str(state.pieces[CS.SQUARES.A8]))
	state.undo()
	check("promo: undo restores pawn on a7", "P<null>",
			str(state.pieces[CS.SQUARES.A7]) + str(state.pieces[CS.SQUARES.A8]))

	check("promo: capture fen accepted", true, state.set_fen("1r6/P6k/8/8/8/8/8/K7 w - - 0 1"))
	var mc = state.move_from_uci("a7b8q")
	check("promo: capture-promotion available", true, mc != null)
	check("promo: capture-promotion takes rook", "r", str(mc.captured_piece) if mc != null else "null")


func _test_results_and_draws() -> void:
	var state := CS.new()
	check("result: fools-mate fen", true,
			state.set_fen("rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3"))
	check("result: checkmate detected", "CHECKMATE", result_name(state))
	check("result: stalemate fen", true, state.set_fen("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1"))
	check("result: stalemate detected", "STALEMATE", result_name(state))

	# Threefold repetition: knight shuffle from the start position
	state = CS.new()
	var ok := true
	for uci in ["g1f3", "g8f6", "f3g1", "f6g8"]:
		ok = ok and apply_uci(state, uci)
	check("draw: first shuffle cycle applied", true, ok)
	check("draw: twofold is still ONGOING", "ONGOING", result_name(state))
	for uci in ["g1f3", "g8f6", "f3g1", "f6g8"]:
		ok = ok and apply_uci(state, uci)
	check("draw: second shuffle cycle applied", true, ok)
	check("draw: threefold detected", "THREEFOLD", result_name(state))

	# Fifty-move rule
	check("draw: halfmove-99 fen", true, state.set_fen("8/8/8/8/8/4k3/8/R3K3 w - - 99 80"))
	check("draw: clock 99 still ONGOING", "ONGOING", result_name(state))
	check("draw: quiet rook move applied", true, apply_uci(state, "a1a2"))
	check("draw: fifty-move detected", "FIFTY_MOVE", result_name(state))

	# Insufficient material
	check("draw: K vs K+B fen", true, state.set_fen("k7/8/8/8/8/8/8/KB6 w - - 0 1"))
	check("draw: K vs K+B insufficient", "INSUFFICIENT", result_name(state))
	check("draw: K vs K fen", true, state.set_fen("k7/8/8/8/8/8/8/K7 w - - 0 1"))
	check("draw: K vs K insufficient", "INSUFFICIENT", result_name(state))
	check("draw: K+R vs K fen", true, state.set_fen("8/8/8/8/8/4k3/8/R3K3 w - - 0 1"))
	check("draw: K+R vs K is sufficient", "ONGOING", result_name(state))


func _test_perft() -> void:
	var state := CS.new()
	check("perft: startpos depth 1", 20, perft(state, 1))
	check("perft: startpos depth 2", 400, perft(state, 2))
	check("perft: startpos depth 3", 8902, perft(state, 3))
	check("perft: startpos depth 4", 197281, perft(state, 4))
	check("perft: kiwipete fen", true, state.set_fen(KIWIPETE))
	check("perft: kiwipete depth 1", 48, perft(state, 1))
	check("perft: kiwipete depth 2", 2039, perft(state, 2))
	check("perft: kiwipete depth 3", 97862, perft(state, 3))


func _test_ai() -> void:
	var diff_names := {CA.Difficulty.EASY: "EASY", CA.Difficulty.MEDIUM: "MEDIUM", CA.Difficulty.HARD: "HARD"}
	for diff in [CA.Difficulty.EASY, CA.Difficulty.MEDIUM, CA.Difficulty.HARD]:
		var dname: String = diff_names[diff]
		var state := CS.new()
		check("ai %s: mate-in-1 fen" % dname, true, state.set_fen("6k1/5ppp/8/8/8/8/8/4R1K1 w - - 0 1"))
		var ai := CA.new()
		var t0 := Time.get_ticks_msec()
		var move = await ai.choose_move(state, diff)
		var elapsed := Time.get_ticks_msec() - t0
		_mark = Time.get_ticks_msec()
		check("ai %s: finds mate-in-1" % dname, "e1e8", move.to_uci() if move != null else "null")
		check("ai %s: within 5s (%d ms)" % [dname, elapsed], true, elapsed < 5000)
		if move != null:
			state.apply_move(move)
			check("ai %s: chosen move mates" % dname, "CHECKMATE", result_name(state))


## Reporting ##

func _short(s: String, width: int) -> String:
	if s.length() <= width:
		return s
	return s.substr(0, width - 3) + "..."


func _print_summary() -> void:
	print("")
	print("%-4s %-42s %-26s %-26s %-6s %8s" % ["#", "Test", "Expected", "Actual", "Pass", "ms"])
	print("-".repeat(116))
	var i := 1
	for row in rows:
		print("%-4d %-42s %-26s %-26s %-6s %8d" % [i, _short(row[0], 42), _short(row[1], 26),
				_short(row[2], 26), "PASS" if row[3] else "FAIL", row[4]])
		i += 1
	print("-".repeat(116))
	var total := rows.size()
	print("TOTAL: %d  PASSED: %d  FAILED: %d" % [total, total - failures, failures])
	print("RESULT: %s" % ("ALL GREEN" if failures == 0 else "FAILURES PRESENT"))
	quit(1 if failures > 0 else 0)
