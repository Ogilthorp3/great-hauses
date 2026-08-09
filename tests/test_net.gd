extends SceneTree

# Headless unit tests for head-to-head multiplayer: src/net/net_protocol.gd
# and src/net/net_ply_gate.gd.
#
# Run: /Applications/Godot.app/Contents/MacOS/Godot --headless --path <project> \
#          -s res://tests/test_net.gd
# Exit code 0 = all green, 1 = failures.
#
# What is proven here (the transport itself is proven by the TWO-INSTANCE e2e,
# test_e2e/run_net_e2e.sh — a green unit suite is not evidence that two
# machines can play):
#   * every ChessMove field survives the wire, including the presentation
#     metadata a capture duel is animated from,
#   * HOST AUTHORITY: a client cannot force an illegal move, cannot move on
#     its opponent's turn, cannot touch its opponent's pieces, cannot move a
#     pinned piece, cannot address a square off the board — and every refusal
#     leaves the host's board byte-identical,
#   * the cinematic gate: one ack never opens it, both acks open it once, a
#     stale ack is dropped, and a peer that never acks can DELAY it but never
#     wedge it,
#   * take-backs are off online, and the addresses/ports a human types parse.

const START := "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
const EP_FEN := "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2"
const CASTLE_FEN := "4k3/8/8/8/8/8/7P/4K2R w K - 0 1"
const PROMO_FEN := "7k/P7/8/8/8/8/8/K7 w - - 0 1"
const CAPTURE_FEN := "rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2"
# White's e2 rook is pinned to the e1 king by the black e8 rook: stepping off
# the e-file is illegal (it uncovers the king) while sliding ALONG the pin is
# fine — the pair that separates "geometrically plausible" from "legal here".
const PIN_FEN := "4r2k/8/8/8/8/8/4R3/4K3 w - - 0 1"

var rows := []
var failures := 0


func _initialize() -> void:
	print("=== Great Houses — head-to-head network test suite ===")
	_test_move_wire()
	_test_validator_accepts()
	_test_client_cannot_force_illegal_moves()
	_test_turn_ownership()
	_test_applied_payload()
	_test_seating()
	_test_addresses()
	_test_undo_policy()
	_test_ply_gate()
	_test_enet_transport()
	_print_summary()


func check(test_name: String, expected, actual) -> void:
	var ok := str(expected) == str(actual)
	if not ok:
		failures += 1
	rows.push_back([test_name, str(expected), str(actual), ok])


func _state(fen: String) -> ChessState:
	var s := ChessState.new()
	if not s.set_fen(fen):
		push_error("test fen rejected: %s" % fen)
	return s


func _find(state: ChessState, uci: String):
	for m in state.legal_moves(true):
		if m.to_uci() == uci:
			return m
	return null


# ── The wire: every field of every move shape ──────────────────────────────


func _test_move_wire() -> void:
	# A quiet opening move.
	var s := _state(START)
	var quiet = _find(s, "e2e4")
	check("wire: e2e4 found", true, quiet != null)
	var back = NetProtocol.decode_move(NetProtocol.encode_move(quiet))
	check("wire: quiet uci survives", "e2e4", back.to_uci())
	check("wire: quiet san survives", str(quiet.notation_san), str(back.notation_san))
	check("wire: quiet piece survives", "P", back.piece)
	check("wire: quiet is not a capture", false, back.is_capture())
	check("wire: quiet prev_halfmove_clock survives",
			quiet.prev_halfmove_clock, back.prev_halfmove_clock)

	# A capture — captured_square is what the duel animates from.
	var c := _state(CAPTURE_FEN)
	var cap = _find(c, "e4d5")
	check("wire: exd5 found", true, cap != null)
	var cback = NetProtocol.decode_move(NetProtocol.encode_move(cap))
	check("wire: capture flagged", true, cback.is_capture())
	check("wire: captured piece survives", "p", str(cback.captured_piece))
	check("wire: captured_square survives", cap.captured_square, cback.captured_square)

	# En passant — the victim does NOT stand on the landing square.
	var e := _state(EP_FEN)
	var ep = _find(e, "e5d6")
	check("wire: exd6 e.p. found", true, ep != null)
	var eback = NetProtocol.decode_move(NetProtocol.encode_move(ep))
	check("wire: e.p. flag survives", true, eback.en_passant)
	check("wire: e.p. is a capture", true, eback.is_capture())
	check("wire: e.p. victim square survives", ep.captured_square, eback.captured_square)
	check("wire: e.p. victim != landing square", true,
			eback.captured_square != eback.to_square)
	check("wire: prev_ep_target survives", str(ep.prev_ep_target), str(eback.prev_ep_target))

	# Castling — the rook path rides along so both sides glide the same rook.
	var k := _state(CASTLE_FEN)
	var oo = _find(k, "e1g1")
	check("wire: O-O found", true, oo != null)
	var kback = NetProtocol.decode_move(NetProtocol.encode_move(oo))
	check("wire: castling flag survives", true, kback.is_castling)
	check("wire: kingside flag survives", true, kback.castle_kingside)
	check("wire: rook_from survives", oo.rook_from, kback.rook_from)
	check("wire: rook_to survives", oo.rook_to, kback.rook_to)
	check("wire: lose_castling survives", str(oo.lose_castling), str(kback.lose_castling))

	# Promotion.
	var p := _state(PROMO_FEN)
	var pr = _find(p, "a7a8q")
	check("wire: a8=Q found", true, pr != null)
	var pback = NetProtocol.decode_move(NetProtocol.encode_move(pr))
	check("wire: promotion piece survives", "Q", str(pback.promotion))
	check("wire: promotion uci survives", "a7a8q", pback.to_uci())

	# A malformed packet must never become a half-applied move.
	check("wire: garbage decodes to null", true,
			NetProtocol.decode_move({"nonsense": 1}) == null)
	check("wire: empty decodes to null", true, NetProtocol.decode_move({}) == null)


# ── Host authority ─────────────────────────────────────────────────────────


func _test_validator_accepts() -> void:
	var s := _state(START)
	var v := NetProtocol.validate_request(s, NetProtocol.COLOR_WHITE,
			ChessState.square_index_from_name("e2"),
			ChessState.square_index_from_name("e4"))
	check("validate: legal move accepted", true, bool(v["ok"]))
	check("validate: accepted move is e2e4", "e2e4", v["move"].to_uci())
	check("validate: accepting does not move the board", START, s.get_fen())

	# A promotion with no piece named takes the queen rather than refusing a
	# move the player obviously meant.
	var p := _state(PROMO_FEN)
	var pv := NetProtocol.validate_request(p, NetProtocol.COLOR_WHITE,
			ChessState.square_index_from_name("a7"),
			ChessState.square_index_from_name("a8"))
	check("validate: bare promotion defaults to queen", "a7a8q",
			pv["move"].to_uci() if bool(pv["ok"]) else "REJECTED")
	var nv := NetProtocol.validate_request(p, NetProtocol.COLOR_WHITE,
			ChessState.square_index_from_name("a7"),
			ChessState.square_index_from_name("a8"), "n")
	check("validate: knight promotion honoured", "a7a8n",
			nv["move"].to_uci() if bool(nv["ok"]) else "REJECTED")


## THE TEST THE BRIEF ASKED FOR: a client tries to force illegal moves, over
## and over, and gets nothing but reasons. Every attempt is checked twice —
## refused, AND the host's board unchanged afterwards.
func _test_client_cannot_force_illegal_moves() -> void:
	var s := _state(START)
	var before := s.get_fen()
	var hostile := [
		# [label, from, to, why it must fail]
		["pawn teleports three ranks", "e2", "e5"],
		["rook walks through its own pawn", "a1", "a5"],
		["knight moves like a rook", "b1", "b3"],
		["bishop through a pawn", "c1", "h6"],
		["king marches two squares with no castle", "e1", "e3"],
		["moves a piece that is not there", "e3", "e4"],
		["moves the OPPONENT's pawn", "e7", "e5"],
		["captures its own knight", "a1", "b1"],
		["stands still", "e2", "e2"],
	]
	for h in hostile:
		var from_idx := ChessState.square_index_from_name(str(h[1]))
		var to_idx := ChessState.square_index_from_name(str(h[2]))
		var v := NetProtocol.validate_request(s, NetProtocol.COLOR_WHITE, from_idx, to_idx)
		check("illegal (%s): refused" % str(h[0]), false, bool(v["ok"]))
		check("illegal (%s): reason given" % str(h[0]), true,
				not str(v["reason"]).is_empty())
	check("illegal: host board untouched after 9 hostile requests", before, s.get_fen())
	check("illegal: no move was pushed on the stack", 0, s.move_stack.size())

	# Off the board entirely (a hand-rolled packet, not a click).
	for pair in [[-1, 20], [64, 20], [12, 999], [12, -7]]:
		var v2 := NetProtocol.validate_request(s, NetProtocol.COLOR_WHITE,
				int(pair[0]), int(pair[1]))
		check("illegal (off-board %s): refused" % str(pair), false, bool(v2["ok"]))

	# The subtle one: a geometrically plausible move that would expose the king.
	var pin := _state(PIN_FEN)
	var pin_before := pin.get_fen()
	var pv := NetProtocol.validate_request(pin, NetProtocol.COLOR_WHITE,
			ChessState.square_index_from_name("e2"),
			ChessState.square_index_from_name("d2"))
	check("illegal (pinned rook steps off the pin): refused", false, bool(pv["ok"]))
	check("illegal (pinned rook): board untouched", pin_before, pin.get_fen())
	# ...while the same rook sliding ALONG the pin is perfectly legal.
	var ok_pin := NetProtocol.validate_request(pin, NetProtocol.COLOR_WHITE,
			ChessState.square_index_from_name("e2"),
			ChessState.square_index_from_name("e5"))
	check("legal (pinned rook along the pin): accepted", true, bool(ok_pin["ok"]))


func _test_turn_ownership() -> void:
	var s := _state(START)
	# White to move; the joiner (Black) asks anyway.
	var v := NetProtocol.validate_request(s, NetProtocol.COLOR_BLACK,
			ChessState.square_index_from_name("e7"),
			ChessState.square_index_from_name("e5"))
	check("turn: black cannot move on white's turn", false, bool(v["ok"]))
	check("turn: refusal says whose turn it is", true,
			str(v["reason"]).contains("not your turn"))
	# And white cannot move black's pieces on white's own turn.
	var v2 := NetProtocol.validate_request(s, NetProtocol.COLOR_WHITE,
			ChessState.square_index_from_name("e7"),
			ChessState.square_index_from_name("e5"))
	check("turn: white cannot push a black pawn", false, bool(v2["ok"]))
	# After 1.e4 the roles swap.
	s.apply_move(_find(s, "e2e4"))
	var v3 := NetProtocol.validate_request(s, NetProtocol.COLOR_BLACK,
			ChessState.square_index_from_name("e7"),
			ChessState.square_index_from_name("e5"))
	check("turn: black moves once it is black's turn", true, bool(v3["ok"]))
	var v4 := NetProtocol.validate_request(s, NetProtocol.COLOR_WHITE,
			ChessState.square_index_from_name("d2"),
			ChessState.square_index_from_name("d4"))
	check("turn: white cannot move twice in a row", false, bool(v4["ok"]))


func _test_applied_payload() -> void:
	var s := _state(CAPTURE_FEN)
	var cap = _find(s, "e4d5")
	var before := s.get_fen()
	var payload := NetProtocol.applied_payload(s, cap, 7)
	check("payload: seq carried", 7, int(payload["seq"]))
	check("payload: san carried", str(cap.notation_san), str(payload["san"]))
	check("payload: building it does not move the host's board", before, s.get_fen())
	# The FEN the payload promises is the FEN applying the move produces.
	s.apply_move(cap)
	check("payload: fen_after is the real post-move FEN",
			s.get_fen(), str(payload["fen_after"]))
	var decoded = NetProtocol.decode_move(payload["move"])
	check("payload: move round-trips inside the payload", "e4d5", decoded.to_uci())


# ── Seating, addresses, policy ─────────────────────────────────────────────


func _test_seating() -> void:
	var w := NetProtocol.seat("white")
	check("seat: host white -> joiner black", "false|true",
			"%s|%s" % [w["host"], w["join"]])
	var b := NetProtocol.seat("black")
	check("seat: host black -> joiner white", "true|false",
			"%s|%s" % [b["host"], b["join"]])
	var r0 := NetProtocol.seat("random", false)
	var r1 := NetProtocol.seat("random", true)
	check("seat: random follows the coin (heads)", "false|true",
			"%s|%s" % [r0["host"], r0["join"]])
	check("seat: random follows the coin (tails)", "true|false",
			"%s|%s" % [r1["host"], r1["join"]])
	check("seat: colours are never both the same", true, r1["host"] != r1["join"])
	check("seat: white names White", "White", NetProtocol.color_name(false))
	check("seat: black names Black", "Black", NetProtocol.color_name(true))


func _test_addresses() -> void:
	check("addr: bare host keeps the default port", "10.0.0.4|7777",
			"%s|%s" % NetProtocol.parse_address("10.0.0.4"))
	check("addr: host:port parses", "10.0.0.4|9999",
			"%s|%s" % NetProtocol.parse_address("10.0.0.4:9999"))
	check("addr: whitespace is forgiven", "100.72.4.11|7777",
			"%s|%s" % NetProtocol.parse_address("  100.72.4.11  "))
	check("addr: empty stays empty", "|7777", "%s|%s" % NetProtocol.parse_address(""))
	check("addr: a bracketed v6 literal is not mangled", "::1|7777",
			"%s|%s" % NetProtocol.parse_address("[::1]"))
	var a := NetProtocol.local_addresses()
	var all: Array = (a["tailnet"] as Array) + (a["lan"] as Array)
	var undialable := ""
	for s in all:
		var oc: PackedStringArray = str(s).split(".")
		if str(s).begins_with("127.") or str(s).begins_with("169.254.") \
				or int(oc[3]) == 0 or int(oc[3]) == 255:
			undialable = str(s)
	check("addr: nothing undialable is offered to a friend", "", undialable)
	check("addr: the LAN list is trimmed to something a human can read", true,
			NetProtocol.share_lines(7777).size() <= NetProtocol.SHARE_LAN_MAX + 3)
	for s in a["tailnet"]:
		var oct: PackedStringArray = str(s).split(".")
		check("addr: %s classified as tailnet is in 100.64/10" % s, true,
				int(oct[0]) == 100 and int(oct[1]) >= 64 and int(oct[1]) <= 127)
	check("addr: share_lines always says something", true,
			NetProtocol.share_lines(7777).size() >= 1)
	check("addr: unreachable text names the address", true,
			NetProtocol.unreachable_text("100.1.2.3", 7777).contains("100.1.2.3:7777"))


func _test_undo_policy() -> void:
	check("undo: take-backs are off in a network match", false, NetProtocol.UNDO_ALLOWED)
	check("undo: the gate failsafe is armed", true, NetProtocol.GATE_TIMEOUT_SEC > 0.0)


# ── The cinematic gate ─────────────────────────────────────────────────────


func _test_ply_gate() -> void:
	var g := NetPlyGate.new()
	check("gate: nothing held means requests flow", true, g.accepting())

	g.begin(0, 1000)
	check("gate: holding ply 0", false, g.accepting())
	check("gate: host ack alone does not open it", false,
			g.ack(0, NetPlyGate.ROLE_HOST, 1100))
	check("gate: still closed with one ack", false, g.is_open_for(0))
	check("gate: the host's ack is recorded", true, g.has_ack(NetPlyGate.ROLE_HOST))
	check("gate: a duplicate host ack does not open it", false,
			g.ack(0, NetPlyGate.ROLE_HOST, 1150))
	check("gate: both acks open it exactly once", true,
			g.ack(0, NetPlyGate.ROLE_JOIN, 1200))
	check("gate: open for ply 0", true, g.is_open_for(0))
	check("gate: not open for another ply", false, g.is_open_for(1))
	check("gate: the host may take the next request", true, g.accepting())
	check("gate: acking an already-open gate is a no-op", false,
			g.ack(0, NetPlyGate.ROLE_JOIN, 1300))

	# The late-packet guard: an ack for a position that no longer exists.
	g.begin(1, 2000)
	check("gate: stale ack for ply 0 is dropped", false,
			g.ack(0, NetPlyGate.ROLE_JOIN, 2100))
	check("gate: stale ack left no trace", false, g.has_ack(NetPlyGate.ROLE_JOIN))
	check("gate: an unknown role cannot open it", false,
			g.ack(1, "spectator", 2150))
	check("gate: begin cleared the previous ply's acks", 0, g.acks_in())

	# The failsafe: a peer that hangs mid-duel may delay, never wedge.
	check("gate: does not force open early", false,
			g.tick(2000 + int(NetProtocol.GATE_TIMEOUT_SEC * 1000.0) - 500,
				NetProtocol.GATE_TIMEOUT_SEC))
	check("gate: forces open at the timeout", true,
			g.tick(2000 + int(NetProtocol.GATE_TIMEOUT_SEC * 1000.0) + 10,
				NetProtocol.GATE_TIMEOUT_SEC))
	check("gate: records that it was FORCED, not acked", true, g.forced)
	check("gate: forcing only fires once", false,
			g.tick(2000 + int(NetProtocol.GATE_TIMEOUT_SEC * 1000.0) + 5000,
				NetProtocol.GATE_TIMEOUT_SEC))
	check("gate: forced gate still releases the turn", true, g.accepting())


# ── The transport actually binds ───────────────────────────────────────────


func _test_enet_transport() -> void:
	## Not a protocol test — a "the socket layer we chose is real" test. The
	## honest proof that two machines can play is test_e2e/run_net_e2e.sh.
	var port := 7811
	var a := ENetMultiplayerPeer.new()
	var err_a := a.create_server(port, 1)
	check("enet: server binds port %d" % port, OK, err_a)
	var b := ENetMultiplayerPeer.new()
	print("(the 'Couldn't create an ENet host' error below is the point of the "
		+ "next check — a second bind on a taken port MUST fail)")
	var err_b := b.create_server(port, 1)
	check("enet: a second bind on the same port fails (the 'already hosting' path)",
			true, err_b != OK)
	a.close()
	b.close()
	var c := ENetMultiplayerPeer.new()
	check("enet: client creation to a plausible address succeeds",
			OK, c.create_client("127.0.0.1", port))
	c.close()


# ── Reporting ──────────────────────────────────────────────────────────────


func _short(s: String, width: int) -> String:
	if s.length() <= width:
		return s
	return s.substr(0, width - 3) + "..."


func _print_summary() -> void:
	print("")
	print("%-4s %-58s %-22s %-22s %-6s" % ["#", "Test", "Expected", "Actual", "Pass"])
	print("-".repeat(116))
	var i := 1
	for row in rows:
		print("%-4d %-58s %-22s %-22s %-6s" % [i, _short(row[0], 58),
				_short(row[1], 22), _short(row[2], 22), "PASS" if row[3] else "FAIL"])
		i += 1
	print("-".repeat(116))
	var total := rows.size()
	print("TOTAL: %d  PASSED: %d  FAILED: %d" % [total, total - failures, failures])
	print("RESULT: %s" % ("ALL GREEN" if failures == 0 else "FAILURES PRESENT"))
	quit(1 if failures > 0 else 0)
