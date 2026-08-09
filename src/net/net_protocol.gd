class_name NetProtocol
extends RefCounted
## Great Houses — head-to-head wire protocol (pure data + pure rules).
##
## Nothing in this file touches the scene tree, a socket, or a signal: it is
## the part of head-to-head play that can be proven headless in
## `tests/test_net.gd`. `net_match.gd` is the transport that carries these
## dictionaries; `game.gd` is the presentation that animates them.
##
## THE ONE RULE — HOST AUTHORITY. The host's ChessState is the only board that
## exists. A joiner never applies its own move: it sends a REQUEST, and the
## host either broadcasts the applied move (with the full move metadata both
## sides need to animate it) or rejects it with a reason a human can read. A
## client that asks for an illegal move gets nothing but the reason — see
## `validate_request`, and the "illegal move from client" test that proves it.
##
## Wire shapes (every one a plain Dictionary — Godot RPC serialises these):
##
##   hello        {protocol, house}                        joiner  -> host
##   match_start  {protocol, seq, fen, your_color,
##                 white_house, black_house}               host    -> joiner
##   move_request {seq, from, to, promo}                   joiner  -> host
##   move_applied {seq, move, fen_after, san}              host    -> both
##   move_rejected{seq, reason}                            host    -> joiner
##   ply_ack      {seq}                                    joiner  -> host
##   gate_open    {seq}                                    host    -> both
##
## `move` is `encode_move`'s dictionary: every ChessMove field, including the
## presentation metadata (captured_square, rook_from/rook_to, en_passant),
## because the receiving side animates a capture duel from it without ever
## re-deriving the position.

## Bumped whenever a wire shape changes. Mismatched builds refuse to play
## rather than desync three moves in.
const PROTOCOL_VERSION := 1

## TCP/UDP port ENet binds. Documented in the runbook for the port-forward
## fallback; LAN and tailnet play need no forwarding at all.
const DEFAULT_PORT := 7777

## Take-backs are OFF in a network match. There is no correct single-player
## answer to "rewind the board under my opponent's hand" — the honest one is
## to disable the control and say so in the HUD (game.gd does exactly that).
const UNDO_ALLOWED := false

## How long the host will wait for the joiner's "I finished watching the
## cinematic" ack before it opens the turn gate anyway. A wedged peer may
## DELAY the game; it may never freeze it forever.
const GATE_TIMEOUT_SEC := 25.0

## How long a joiner waits for ENet to reach the host before it gives up and
## says so in words. ENet's own failure notice can take much longer.
const CONNECT_TIMEOUT_SEC := 12.0

const COLOR_WHITE := false
const COLOR_BLACK := true


# ── Move encoding ──────────────────────────────────────────────────────────

## Every ChessMove field, flattened for the wire. The presentation metadata
## rides along deliberately: the receiver animates the duel from THIS, so a
## capture looks identical on both screens without either side re-deriving it.
static func encode_move(move) -> Dictionary:
	if move == null:
		return {}
	return {
		"from": int(move.from_square),
		"to": int(move.to_square),
		"promo": null if move.promotion == null else str(move.promotion),
		"captured_piece": null if move.captured_piece == null else str(move.captured_piece),
		"en_passant": bool(move.en_passant),
		"lose_castling": [bool(move.lose_castling[0]), bool(move.lose_castling[1]),
			bool(move.lose_castling[2]), bool(move.lose_castling[3])],
		"prev_ep_target": null if move.prev_ep_target == null else int(move.prev_ep_target),
		"prev_halfmove_clock": int(move.prev_halfmove_clock),
		"san": null if move.notation_san == null else str(move.notation_san),
		"piece": str(move.piece),
		"is_castling": bool(move.is_castling),
		"castle_kingside": bool(move.castle_kingside),
		"rook_from": int(move.rook_from),
		"rook_to": int(move.rook_to),
		"captured_square": int(move.captured_square),
	}


## Rebuild a ChessMove from the wire. Returns null when the dictionary is not
## a move (a malformed packet must never become a half-applied move).
static func decode_move(d: Dictionary):
	if d == null or not d.has("from") or not d.has("to"):
		return null
	var m := ChessMove.new()
	m.from_square = int(d["from"])
	m.to_square = int(d["to"])
	m.promotion = null if d.get("promo") == null else str(d["promo"])
	m.captured_piece = null if d.get("captured_piece") == null else str(d["captured_piece"])
	m.en_passant = bool(d.get("en_passant", false))
	var lc: Array = d.get("lose_castling", [false, false, false, false])
	m.lose_castling = [bool(lc[0]), bool(lc[1]), bool(lc[2]), bool(lc[3])]
	m.prev_ep_target = null if d.get("prev_ep_target") == null else int(d["prev_ep_target"])
	m.prev_halfmove_clock = int(d.get("prev_halfmove_clock", -1))
	m.notation_san = null if d.get("san") == null else str(d["san"])
	m.piece = str(d.get("piece", ""))
	m.is_castling = bool(d.get("is_castling", false))
	m.castle_kingside = bool(d.get("castle_kingside", false))
	m.rook_from = int(d.get("rook_from", -1))
	m.rook_to = int(d.get("rook_to", -1))
	m.captured_square = int(d.get("captured_square", -1))
	return m


# ── Host authority: the validator ──────────────────────────────────────────

## THE GATE A CLIENT CANNOT WALK AROUND.
##
## `state` is the HOST's own ChessState. `mover_color` is the colour the
## requesting peer owns — derived from the host's own seating chart, NEVER
## from anything the packet claims. Returns
##     {"ok": true,  "move": ChessMove, "reason": ""}
##  or {"ok": false, "move": null,      "reason": "<human-readable>"}
##
## The state is never mutated here: a rejected request leaves the board
## byte-identical (tests/test_net.gd asserts the FEN before and after).
static func validate_request(state, mover_color: bool, from_idx: int,
		to_idx: int, promo: String = "") -> Dictionary:
	if state == null:
		return _no("there is no position to move in")
	if from_idx < 0 or from_idx > 63 or to_idx < 0 or to_idx > 63:
		return _no("square index out of range (%d -> %d)" % [from_idx, to_idx])
	if from_idx == to_idx:
		return _no("a move must leave the square it started on")
	if bool(state.turn) != mover_color:
		return _no("it is not your turn")
	var piece = state.pieces[from_idx]
	if piece == null:
		return _no("no piece stands on %s" % ChessMove.square_name(from_idx))
	if ChessState.piece_color(piece) != mover_color:
		return _no("%s carries your opponent's banner" % ChessMove.square_name(from_idx))
	var want := promo.to_lower()
	var fallback = null
	for m in state.legal_moves(true):
		if m.from_square != from_idx or m.to_square != to_idx:
			continue
		if m.promotion == null:
			return {"ok": true, "move": m, "reason": ""}
		if fallback == null:
			fallback = m
		if want.is_empty():
			want = "q"
		if str(m.promotion).to_lower() == want:
			return {"ok": true, "move": m, "reason": ""}
	if fallback != null:
		# The squares are legal, only the promotion piece was unknown — take
		# the queen rather than refusing a move the player clearly meant.
		return {"ok": true, "move": fallback, "reason": ""}
	return _no("%s%s is not a legal move in this position" % [
		ChessMove.square_name(from_idx), ChessMove.square_name(to_idx)])


static func _no(reason: String) -> Dictionary:
	return {"ok": false, "move": null, "reason": reason}


## The full `move_applied` payload for a validated move: the move metadata
## plus the FEN the board MUST hold once both sides have applied it. The
## receiver compares its own FEN against this and shouts if they differ — a
## silent desync is the one failure mode a chess client must never have.
static func applied_payload(state, move, seq: int) -> Dictionary:
	var probe = state.duplicate(false)
	probe.play_move(move.duplicate())
	return {
		"seq": seq,
		"move": encode_move(move),
		"fen_after": str(probe.get_fen()),
		"san": str(move.notation_san) if move.notation_san != null else move.to_uci(),
	}


# ── Seating ────────────────────────────────────────────────────────────────

## Resolve the host's requested side into concrete colours.
## `side` is "white" | "black" | "random"; `rng_pick` decides the coin toss
## (injected so the test can pin it). Returns {host, join} colours where
## false = White, true = Black (ChessState's own convention).
static func seat(side: String, rng_pick: bool = false) -> Dictionary:
	var host_color := COLOR_WHITE
	match side.to_lower():
		"black":
			host_color = COLOR_BLACK
		"random":
			host_color = rng_pick
		_:
			host_color = COLOR_WHITE
	return {"host": host_color, "join": not host_color}


static func color_name(c: bool) -> String:
	return "Black" if c else "White"


# ── Reachability ───────────────────────────────────────────────────────────

## Every IPv4 address a friend could dial, split by how they'd reach it.
## Returns {"tailnet": [...], "lan": [...]}.
##
## Tailscale hands out CGNAT space (the 100.64/10 range). An address from that
## block is the most useful one in this list: a friend on the same tailnet — or on a
## node the tailnet owner invited — reaches it from anywhere with no port
## forwarding, no relay of ours, and no firewall change. The LAN addresses
## are for two people on one Wi-Fi.
static func local_addresses() -> Dictionary:
	var out := {"tailnet": [], "lan": []}
	for a in IP.get_local_addresses():
		var s := str(a)
		var parts := s.split(".")
		if parts.size() != 4:
			continue                      # IPv6 — ENet dials v4 here
		if s.begins_with("127.") or s.begins_with("169.254."):
			continue                      # loopback / link-local: nobody can dial these
		# A .0 or .255 host part is a network/broadcast address, not a machine.
		# A dev box is full of them (VM bridges, container networks) and every
		# one printed on the Host panel is a wrong number a friend will try.
		var last := int(parts[3])
		if last == 0 or last == 255:
			continue
		if int(parts[0]) == 100 and int(parts[1]) >= 64 and int(parts[1]) <= 127:
			out["tailnet"].append(s)
		else:
			out["lan"].append(s)
	return out


## How many LAN addresses the Host panel will read out. A developer machine can
## have eight; a person needs the two or three that might be their Wi-Fi.
const SHARE_LAN_MAX := 3


## The address line a human should send their friend, best option first.
static func share_lines(port: int) -> Array[String]:
	var addrs := local_addresses()
	var lines: Array[String] = []
	for a in addrs["tailnet"]:
		lines.append("%s:%d   (tailnet — works from anywhere)" % [a, port])
	var lan: Array = addrs["lan"]
	for i in mini(lan.size(), SHARE_LAN_MAX):
		lines.append("%s:%d   (same Wi-Fi / LAN)" % [lan[i], port])
	if lan.size() > SHARE_LAN_MAX:
		lines.append("…and %d more local addresses" % (lan.size() - SHARE_LAN_MAX))
	if lines.is_empty():
		lines.append("no network address found — is Wi-Fi on?")
	return lines


## Split "host", "host:port", or "" into [address, port]. An empty or
## portless address falls back to DEFAULT_PORT. IPv6 literals in brackets are
## understood so a pasted address is never silently mangled.
static func parse_address(text: String, fallback_port: int = DEFAULT_PORT) -> Array:
	var s := text.strip_edges()
	if s.is_empty():
		return ["", fallback_port]
	if s.begins_with("["):
		var close := s.find("]")
		if close > 0:
			var host := s.substr(1, close - 1)
			var rest := s.substr(close + 1)
			if rest.begins_with(":") and rest.substr(1).is_valid_int():
				return [host, int(rest.substr(1))]
			return [host, fallback_port]
	var colon := s.rfind(":")
	if colon > 0 and s.count(":") == 1 and s.substr(colon + 1).is_valid_int():
		return [s.substr(0, colon), int(s.substr(colon + 1))]
	return [s, fallback_port]


# ── Human-readable failures ────────────────────────────────────────────────
# Every one of these is what the player SEES. "ERR_CANT_CONNECT" tells a
# person nothing they can act on; "is the host's game open?" tells them the
# next thing to try.

static func unreachable_text(address: String, port: int) -> String:
	return ("could not reach %s:%d — is your friend's game open and waiting, "
		+ "and are you both on the same Wi-Fi or the same tailnet?") % [address, port]


static func host_bind_failed_text(port: int) -> String:
	return ("could not open port %d — another copy of the game may already be "
		+ "hosting. Close it and try again.") % port


static func protocol_mismatch_text(theirs: int) -> String:
	return ("your friend is running a different version of Great Houses "
		+ "(their protocol %d, yours %d) — you both need the same build.") % [
			theirs, PROTOCOL_VERSION]
