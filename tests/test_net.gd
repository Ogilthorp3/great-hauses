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
#   * THE REQUEST DEADLINE (verifier defect P1): a request the host never
#     answers stops being a frozen board — the clock says "late", then hands
#     the board back, and a late answer still un-does the whole thing,
#   * THE RPC GUARDS (verifier defects P2/P3): a second hello mid-match cannot
#     reset the host's state, and only the seated peer can ack the cinematic
#     gate or request a move,
#   * take-backs are off online, and the addresses/ports a human types — or
#     PASTES, commentary and all — parse.

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
	print("=== Great Hauses — head-to-head network test suite ===")
	_test_move_wire()
	_test_validator_accepts()
	_test_client_cannot_force_illegal_moves()
	_test_turn_ownership()
	_test_applied_payload()
	_test_seating()
	_test_addresses()
	_test_undo_policy()
	_test_refusal_texts()
	_test_ply_gate()
	_test_request_clock()
	_test_enet_transport()


## The last two tests stand a REAL NetMatch up in the tree (they drive its own
## `_rpc_*` methods and its own deadline), and the SceneTree root refuses
## children while it is still being set up — so they run on the first frame
## instead of inside `_initialize`.
func _process(_delta: float) -> bool:
	_test_dropped_request_recovers()
	_test_rpc_guards()
	_print_summary()
	return true


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

	# -- THE PASTED LINE (verifier note, 2026-08-09). The host panel prints an
	# address followed by the one line that says when to use it, and people
	# select the whole line, because that is what a line is. Every one of these
	# used to be handed to ENet verbatim and fail as "could not reach <line>".
	for line in NetProtocol.share_lines(7777):
		if not line.contains(":7777"):
			continue                     # the "no network address found" line
		var round_trip: Array = NetProtocol.parse_address(line)
		check("addr: our OWN share line pastes back cleanly (%s)" % line, 7777,
				int(round_trip[1]))
		check("addr: ...and yields a bare address (%s)" % line, false,
				str(round_trip[0]).contains(" "))
	check("addr: a pasted LAN line loses its commentary", "10.0.0.10|7777",
			"%s|%s" % NetProtocol.parse_address("10.0.0.10:7777   ·  same Wi-Fi — try this one first"))
	check("addr: a pasted tailnet line loses its commentary", "100.107.112.118|7777",
			"%s|%s" % NetProtocol.parse_address(
				"100.107.112.118:7777   (tailnet — works from anywhere)"))
	check("addr: the OLD share format still pastes", "192.168.1.24|7777",
			"%s|%s" % NetProtocol.parse_address("192.168.1.24:7777   (same Wi-Fi / LAN)"))
	check("addr: a sentence around the address is forgiven", "10.0.0.10|7777",
			"%s|%s" % NetProtocol.parse_address("Send your friend: 10.0.0.10:7777"))
	check("addr: a non-default port survives the paste", "10.0.0.10|9001",
			"%s|%s" % NetProtocol.parse_address("10.0.0.10:9001  ·  same Wi-Fi"))
	check("addr: a portless paste keeps the default", "10.0.0.10|7777",
			"%s|%s" % NetProtocol.parse_address("10.0.0.10   ·  same Wi-Fi"))
	check("addr: a trailing full stop is not part of the address", "10.0.0.10|7777",
			"%s|%s" % NetProtocol.parse_address("10.0.0.10."))
	check("addr: quotes around a pasted address are forgiven", "10.0.0.10|7777",
			"%s|%s" % NetProtocol.parse_address("\"10.0.0.10\""))
	check("addr: a non-breaking space from a clipboard is forgiven", "10.0.0.10|7777",
			"%s|%s" % NetProtocol.parse_address(String.chr(0x00A0) + "10.0.0.10" + String.chr(0x00A0)))
	check("addr: a pasted newline does not become a hostname", "10.0.0.10|7777",
			"%s|%s" % NetProtocol.parse_address("10.0.0.10:7777\n"))
	check("addr: a bare hostname typed by hand still works", "manoir|7777",
			"%s|%s" % NetProtocol.parse_address("manoir"))
	check("addr: prose with no address in it yields nothing to dial", "|7777",
			"%s|%s" % NetProtocol.parse_address("same Wi-Fi"))

	# -- THE ORDER (verifier note, 2026-08-09). Same-Wi-Fi first, because it is
	# the case that needs nothing set up; the tailnet line has to SAY what it
	# needs rather than lead the list by being the cleverest option.
	var entries := NetProtocol.share_entries(7777)
	check("share: every entry says WHEN to use it", true, entries.all(
			func(e): return not str(e["when"]).is_empty()))
	var kinds: Array[String] = []
	for e in entries:
		kinds.append(str(e["kind"]))
	var first_tailnet := kinds.find("tailnet")
	var last_lan := kinds.rfind("lan")
	if first_tailnet >= 0 and last_lan >= 0:
		check("share: no tailnet address is offered above a same-Wi-Fi one",
				true, first_tailnet > last_lan)
	if first_tailnet >= 0:
		check("share: the tailnet line says what it needs", true,
				str(entries[first_tailnet]["when"]).contains("tailnet"))
	if last_lan >= 0:
		check("share: the first line is the one to try first", true,
				str(entries[0]["when"]).contains("first"))
	check("share: the copy button copies the first line's address, exactly",
			str(entries[0]["address"]), NetProtocol.primary_address(7777))
	check("share: the copied address is dialable text, not a sentence", true,
			NetProtocol.primary_address(7777).is_empty()
			or str(NetProtocol.parse_address(NetProtocol.primary_address(7777))[0])
				== NetProtocol.primary_address(7777).split(":")[0])
	# The ranking rule that demoted a VM bridge below the real Wi-Fi.
	check("share: a virtual interface name is recognised as virtual", false,
			NetProtocol._iface_is_real("bridge100"))
	check("share: a VM host interface is recognised as virtual", false,
			NetProtocol._iface_is_real("vmenet0"))
	check("share: the tailscale tunnel is recognised as virtual", false,
			NetProtocol._iface_is_real("utun0"))
	check("share: Windows' virtual switch is recognised as virtual", false,
			NetProtocol._iface_is_real("vEthernet (Default Switch)"))
	check("share: real Wi-Fi is not demoted", true, NetProtocol._iface_is_real("en1"))
	check("share: a Windows 'Wi-Fi' adapter is not demoted", true,
			NetProtocol._iface_is_real("Wi-Fi"))

	# -- What a player must be told BEFORE they press anything.
	check("words: the prerequisite names both routes", true,
			NetProtocol.prerequisite_text().contains("Wi-Fi")
			and NetProtocol.prerequisite_text().contains("tailnet"))
	check("words: the firewall note tells them which button to click", true,
			NetProtocol.firewall_text().contains("Allow"))
	check("words: the stalled notice offers the way out", true,
			NetProtocol.request_stalled_text().contains("Hall of Banners"))


func _test_undo_policy() -> void:
	check("undo: take-backs are off in a network match", false, NetProtocol.UNDO_ALLOWED)
	check("undo: the gate failsafe is armed", true, NetProtocol.GATE_TIMEOUT_SEC > 0.0)


## THE FLAKY GATE, PINNED (verifier defect P5's second face, 2026-08-09).
##
## The two-instance e2e's wrong-turn probe fires while the OPPONENT legitimately
## owns the move, so it races the opponent's ply and has TWO correct answers: it
## arrives first and the validator says "not your turn", or the ply beats it and
## the generation guard says "an earlier position". Demanding only the first made
## a CORRECT game fail about one run in three (and cascade into the other
## instance). The probe accepts both now — which means a reword of either string
## could silently drift that gate back into flakiness, so both are pinned HERE,
## headless, together with the driver's accepted list.
func _test_refusal_texts() -> void:
	var stale := NetProtocol.stale_request_text()
	var wrong := NetProtocol.wrong_turn_text()
	check("refuse: the wrong-turn text is what the validator returns", wrong,
			str(NetProtocol.validate_request(_state(START), NetProtocol.COLOR_BLACK,
				ChessState.square_index_from_name("e7"),
				ChessState.square_index_from_name("e5"))["reason"]))
	check("refuse: every refusal is a sentence, not a code", true,
			stale.length() > 20 and wrong.length() > 10)
	check("refuse: the gate-held text names the duel", true,
			NetProtocol.gate_held_text().contains("duel"))

	# The e2e probe must accept BOTH outcomes of that race. Read its source and
	# say so out loud — this is the assertion that keeps the gate a gate.
	var driver := FileAccess.get_file_as_string("res://test_e2e/e2e_driver.gd")
	if driver.is_empty():
		check("refuse: the e2e driver is readable from this build", true, false)
		return
	# The probe call is `_net_illegal_probe(game, netm, "wrong-turn", "b7", "b6",
	# [...])` — take the window after the label and read the list it passes.
	var at := driver.find("\"wrong-turn\", \"b7\", \"b6\",")
	check("refuse: the wrong-turn probe is where the test thinks it is", true, at > 0)
	var probe_call := driver.substr(at, 160) if at > 0 else ""
	check("refuse: the wrong-turn probe accepts the validator's answer", true,
			probe_call.contains("not your turn"))
	check("refuse: ...AND the generation guard's answer (the 1-in-3 flake)", true,
			probe_call.contains("earlier position"))
	check("refuse: both accepted strings really are the host's own", true,
			wrong.contains("not your turn") and stale.contains("earlier position"))


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


# ── P1: the request deadline (the freeze) ──────────────────────────────────


func _test_request_clock() -> void:
	## The pure clock first: nothing fires early, each hand fires exactly once.
	var slow := NetProtocol.REQUEST_SLOW_SEC
	var stall := NetProtocol.REQUEST_TIMEOUT_SEC
	check("clock: the deadlines are ordered and armed", true, slow > 0.0 and stall > slow)

	var c := NetRequestClock.new()
	check("clock: idle until a request goes out", false, c.waiting())
	check("clock: an idle clock never fires", NetRequestClock.NO_CHANGE,
			c.tick(999_999, slow, stall))

	c.arm(4, 1000)
	check("clock: armed for the ply it was sent for", 4, c.seq)
	check("clock: waiting for an answer", true, c.waiting())
	check("clock: silent one second in", NetRequestClock.NO_CHANGE,
			c.tick(2000, slow, stall))
	check("clock: silent right up to the slow mark", NetRequestClock.NO_CHANGE,
			c.tick(1000 + int(slow * 1000.0) - 1, slow, stall))
	check("clock: says 'late' at the slow mark", NetRequestClock.PHASE_SLOW,
			c.tick(1000 + int(slow * 1000.0), slow, stall))
	check("clock: says it exactly once", NetRequestClock.NO_CHANGE,
			c.tick(1000 + int(slow * 1000.0) + 500, slow, stall))
	check("clock: still holding the board while merely late", false, c.stalled())
	check("clock: gives the board back at the timeout", NetRequestClock.PHASE_STALLED,
			c.tick(1000 + int(stall * 1000.0), slow, stall))
	check("clock: stalled", true, c.stalled())
	check("clock: gives it back exactly once", NetRequestClock.NO_CHANGE,
			c.tick(1000 + int(stall * 1000.0) + 60_000, slow, stall))

	# An answer disarms it, and a re-armed clock starts clean.
	check("clock: an answer disarms a stalled clock", true, c.clear())
	check("clock: nothing left waiting", false, c.waiting())
	check("clock: clearing an idle clock reports nothing to announce", false, c.clear())
	c.arm(5, 10_000)
	check("clock: the new request gets its own full budget",
			NetRequestClock.NO_CHANGE, c.tick(10_000 + int(slow * 1000.0) - 1, slow, stall))

	# A process loop that stalled long enough to cross BOTH marks reports the
	# state that matters, and never announces "late" after "gave up".
	var j := NetRequestClock.new()
	j.arm(1, 0)
	check("clock: one very late tick reports STALLED, not SLOW",
			NetRequestClock.PHASE_STALLED, j.tick(int(stall * 1000.0) + 5000, slow, stall))
	check("clock: and nothing follows it", NetRequestClock.NO_CHANGE,
			j.tick(int(stall * 1000.0) + 9000, slow, stall))

	# An answer that beats the deadline says nothing at all.
	var q := NetRequestClock.new()
	q.arm(2, 0)
	check("clock: a prompt answer never fires the slow hand", NetRequestClock.NO_CHANGE,
			q.tick(int(slow * 1000.0) - 10, slow, stall))
	check("clock: a prompt answer disarms it quietly", true, q.clear())


## THE TEST THE BRIEF ASKED FOR: drop a joiner's request on the floor — the
## host never answers it — and prove the client RECOVERS instead of freezing.
## `busy` here stands in for game.gd's own flag, wired the way game.gd wires it:
## raised when the request leaves, and lowered only by something the transport
## says. Before the deadline existed, nothing ever lowered it again.
func _test_dropped_request_recovers() -> void:
	var net := NetMatch.new()
	net.name = "NetMatchDroppedRequest"
	root.add_child(net)
	if not net.is_inside_tree():
		check("P1: a NetMatch can be stood up for the test", true, false)
		return
	net.is_host = false                       # the joiner is the side that waits
	net.state = NetMatch.State.IN_MATCH

	var busy := [true]                        # game.gd::_play_turn just set this
	var said: Array[String] = []
	var panel := [""]                         # what the player would be reading
	net.request_slow.connect(func(_s: int) -> void:
		said.append("slow")
		panel[0] = NetProtocol.request_slow_text())
	net.request_stalled.connect(func(_s: int) -> void:
		said.append("stalled")
		busy[0] = false                       # game.gd hands the board back
		panel[0] = NetProtocol.request_stalled_text())
	net.request_recovered.connect(func(_s: int) -> void:
		said.append("recovered")
		panel[0] = "")

	var slow_ms := int(NetProtocol.REQUEST_SLOW_SEC * 1000.0)
	var stall_ms := int(NetProtocol.REQUEST_TIMEOUT_SEC * 1000.0)
	net.begin_request_deadline(3, 0)          # ...and the packet is never delivered
	net.tick_requests(slow_ms - 1)
	check("P1: nothing is said before the request is even late", 0, said.size())
	check("P1: the board is still held while the answer may yet come", true, busy[0])

	net.tick_requests(slow_ms + 1)
	check("P1: the player is told the answer is late", "slow", "|".join(said))
	check("P1: the late notice is a sentence, not a code", true,
			panel[0].contains("hasn't answered"))
	check("P1: being late does not yet hand the board back", true, busy[0])
	check("P1: it is said once, not once per frame", 1, net.request_slow_count)
	net.tick_requests(slow_ms + 2000)
	check("P1: still once", 1, net.request_slow_count)

	net.tick_requests(stall_ms + 1)
	check("P1: THE FREEZE IS OVER — the board is handed back", false, busy[0])
	check("P1: the transitions in order", "slow|stalled", "|".join(said))
	check("P1: and a way forward is named", true,
			panel[0].contains("Hall of Banners"))
	check("P1: the stall was counted once", 1, net.request_stalled_count)
	net.tick_requests(stall_ms + 60_000)
	check("P1: a stalled request is not re-announced forever", 1, net.request_stalled_count)

	# The host wakes up late: the notice comes down by itself.
	net._rpc_move_rejected(3, "that move was for an earlier position")
	check("P1: a late answer is not lost", "slow|stalled|recovered", "|".join(said))
	check("P1: the notice comes down when the host answers", "", panel[0])
	check("P1: nothing is left waiting", false, net.request_is_stalled())
	net.tick_requests(stall_ms + 120_000)
	check("P1: a disarmed clock stays quiet", "slow|stalled|recovered", "|".join(said))

	# A request the host answers promptly is completely silent.
	var quiet := [0]
	net.request_slow.connect(func(_s: int) -> void: quiet[0] += 1)
	net.request_stalled.connect(func(_s: int) -> void: quiet[0] += 1)
	net.begin_request_deadline(4, 500_000)
	net.tick_requests(500_000 + slow_ms - 10)
	net._rpc_move_rejected(4, "not your turn")
	net.tick_requests(500_000 + stall_ms + 10_000)
	check("P1: a prompt answer produces no warnings at all", 0, quiet[0])

	# The HOST never arms this clock: it answers its own click synchronously.
	var h := NetMatch.new()
	h.name = "NetMatchHostClock"
	root.add_child(h)
	h.is_host = true
	h.state = NetMatch.State.IN_MATCH
	h.begin_request_deadline(0, 0)
	h.tick_requests(stall_ms + 10_000)
	check("P1: the host never stalls on its own request", 0, h.request_stalled_count)
	h.free()
	net.free()

	# A signal nobody listens to is a fix nobody ships. A headless suite cannot
	# stand up the 3D match scene, so assert the wiring where it is written —
	# the two-instance e2e proves it runs.
	var src := FileAccess.get_file_as_string("res://src/game.gd")
	check("P1: game.gd listens for a late request", true,
			src.contains("net.request_slow.connect"))
	check("P1: game.gd listens for a stalled request", true,
			src.contains("net.request_stalled.connect"))
	check("P1: game.gd listens for the late answer that undoes it", true,
			src.contains("net.request_recovered.connect"))
	check("P1: and the stall handler hands the board back", true,
			src.contains("_on_net_request_stalled") and src.contains("_net_stalled = true"))
	check("P1: Esc is a way out of a host that stopped answering", true,
			src.contains("or _net_stalled:"))


# ── P2 / P3: who may say what, and when ────────────────────────────────────


func _test_rpc_guards() -> void:
	## The rules, every branch (pure — no socket needed).
	check("admit: a first hello from the connected peer seats it",
			NetProtocol.ADMIT_OK, NetProtocol.hello_admission(true, 0, 2, 2))
	check("admit: a hello once the match has started is refused (P2)",
			"the match has already started",
			NetProtocol.hello_admission(false, 0, 2, 2))
	check("admit: a hello from a peer when someone is already seated is refused (P2)",
			"a peer already holds that seat",
			NetProtocol.hello_admission(true, 2, 2, 2))
	check("admit: a hello that claims to be the host itself is refused",
			"the sender is not a remote peer",
			NetProtocol.hello_admission(true, 0, 2, 1))
	check("admit: a hello with no sender at all is refused",
			"the sender is not a remote peer",
			NetProtocol.hello_admission(true, 0, 2, 0))
	check("admit: a hello from a peer that never connected is refused",
			"that peer is not the one that connected",
			NetProtocol.hello_admission(true, 0, 2, 9))
	check("admit: the seated peer may speak for its seat",
			NetProtocol.ADMIT_OK, NetProtocol.seat_admission(2, 2))
	check("admit: another peer may not speak for that seat (P3)",
			"that peer holds no seat", NetProtocol.seat_admission(2, 9))
	check("admit: nobody may speak for an empty seat (P3)",
			"nobody holds that seat yet", NetProtocol.seat_admission(0, 2))

	## ...and the real host, refusing the real packets. Calling an @rpc method
	## directly is exactly a packet whose sender the host cannot vouch for
	## (get_remote_sender_id() is 0), which is the shape of a forged one.
	var host := NetMatch.new()
	host.name = "NetMatchGuards"
	root.add_child(host)
	if not host.is_inside_tree():
		check("P2/P3: a host NetMatch can be stood up for the test", true, false)
		return
	host.is_host = true
	host.state = NetMatch.State.IN_MATCH
	host._client_id = 2
	host._seated_peer = 2
	host.seq = 7
	host.their_house = "ashwyrm"
	host.my_house = "winterfang"
	# A match in progress: ply 6 played, both sides finished watching it.
	host._gate.begin(6, 0)
	host._gate.ack(6, NetPlyGate.ROLE_HOST, 1)
	host._gate.ack(6, NetPlyGate.ROLE_JOIN, 2)
	check("P2: the match is genuinely in progress before the hostile hello",
			true, host.gate_is_open(6))

	# THE VERIFIER'S PACKET: a second hello, mid-match, from a live client.
	host._rpc_hello(NetProtocol.PROTOCOL_VERSION, "goldclaw")
	check("P2: the ply counter was NOT reset", 7, host.seq)
	check("P2: the seats were NOT re-dealt", "ashwyrm", host.their_house)
	check("P2: the cinematic gate was NOT re-armed", true, host.gate_is_open(6))
	check("P2: the match is still running", NetMatch.State.IN_MATCH, host.state)
	check("P2: the packet was dropped, and recorded", 1, host.refused_packet_count)
	check("P2: recorded with the reason", true,
			host.last_refused_packet.contains("already started"))

	# P3: a forged ack must not open the gate under the other player's duel.
	host._gate.begin(8, 0)
	host._gate.ack(8, NetPlyGate.ROLE_HOST, 10)   # we finished; the joiner has not
	check("P3: the gate is closed with only the host's ack", false, host.gate_is_open(8))
	host._rpc_ack_ply(8)
	check("P3: a forged ack does NOT open the gate early", false, host.gate_is_open(8))
	check("P3: the joiner's ack slot is still empty", false,
			host._gate.has_ack(NetPlyGate.ROLE_JOIN))
	check("P3: the forged ack was dropped, and recorded", 2, host.refused_packet_count)
	check("P3: the host still refuses the next request until the duel is watched",
			false, host._gate.accepting())

	# ...and the same rule guards the move request, whose sender decides which
	# ARMY the packet is allowed to move.
	host._rpc_request_move(8, ChessState.square_index_from_name("e2"),
			ChessState.square_index_from_name("e4"), "")
	check("P3: a move request from an unseated peer is dropped",
			3, host.refused_packet_count)
	check("P3: it never reached the validator", 0, host.applied_count)
	host.free()


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
