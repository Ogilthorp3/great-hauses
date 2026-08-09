class_name NetProtocol
extends RefCounted
## Great Hauses — head-to-head wire protocol (pure data + pure rules).
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
##                promo is "" or one of PROMOTION_PIECES ("q"/"r"/"b"/"n") —
##                the piece the joiner's promotion picker chose. The host
##                SELECTS it out of its own legal-move list; it never builds
##                a move from what the packet claims (see validate_request).
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

## THE REQUEST DEADLINE (verifier defect P1, 2026-08-09). A joiner's move is a
## request the HOST answers; before these existed, an unanswered request left
## the board `busy` forever with nothing on screen. `SLOW` is when we say the
## answer is late; `TIMEOUT` is when we hand the board back and offer the way
## out. See src/net/net_request_clock.gd.
const REQUEST_SLOW_SEC := 6.0
const REQUEST_TIMEOUT_SEC := 20.0

const COLOR_WHITE := false
const COLOR_BLACK := true

## The four pieces a pawn may become, in the order the picker shows them
## (src/ui/promotion_picker.gd). Queen leads because queen is what every
## silent path — an Esc, a timeout, an empty or unreadable `promo` field on
## the wire — falls back to.
const PROMOTION_PIECES: Array[String] = ["q", "r", "b", "n"]


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
		return _no(wrong_turn_text())
	var piece = state.pieces[from_idx]
	if piece == null:
		return _no("no piece stands on %s" % ChessMove.square_name(from_idx))
	if ChessState.piece_color(piece) != mover_color:
		return _no("%s carries your opponent's banner" % ChessMove.square_name(from_idx))
	# THE PROMOTION PIECE IS THE CLIENT'S CHOICE, AND THE HOST'S DECISION.
	# `want` only ever SELECTS among moves the host generated itself — the
	# returned ChessMove is always one of `state.legal_moves()`, never a move
	# assembled from the packet. A client therefore cannot promote to anything
	# this board did not already consider legal, whatever it puts on the wire.
	# Exact match or nothing: "n" is a knight, "nq" and "knight" are neither.
	# (No prefix-taking — a client that sends junk gets the documented default,
	# not this file's best guess at what the junk meant.)
	var want := promo.strip_edges().to_lower()
	if not PROMOTION_PIECES.has(want):
		want = ""      # unknown, empty or hostile -> the queen, named below
	var queen_move = null
	var any_promo = null
	for m in state.legal_moves(true):
		if m.from_square != from_idx or m.to_square != to_idx:
			continue
		if m.promotion == null:
			return {"ok": true, "move": m, "reason": ""}
		var promoted := str(m.promotion).to_lower()
		if any_promo == null:
			any_promo = m
		if promoted == "q":
			queen_move = m
		if not want.is_empty() and promoted == want:
			return {"ok": true, "move": m, "reason": ""}
	if queen_move != null:
		# The squares are legal, only the promotion piece was unknown — take
		# the QUEEN BY NAME rather than refusing a move the player clearly
		# meant. (This used to hand back "the first promotion the generator
		# produced", which is the queen only for as long as nobody reorders
		# ChessState.generate_pawn_move_list.)
		return {"ok": true, "move": queen_move, "reason": ""}
	if any_promo != null:
		return {"ok": true, "move": any_promo, "reason": ""}
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


# ── Host-side packet admission: WHO may say WHAT, and WHEN ─────────────────
#
# Godot's `@rpc("any_peer")` means exactly what it says: any connected peer may
# invoke the method, at any moment, with any arguments. Three of ours were
# taking the packet's word for things only the HOST knows (verifier defects
# P2/P3, 2026-08-09). These are the rules, pure so `tests/test_net.gd` can walk
# every branch of them without a socket; `net_match.gd` calls them and drops
# whatever they refuse.

## Returned when the packet may be acted on.
const ADMIT_OK := ""


## A `hello` is the HANDSHAKE. It re-deals both seats, resets `seq` to 0 and
## re-arms the cinematic gate — which is fine exactly once, before the match
## starts. A second hello from a live client mid-match used to walk straight
## through and reset the host's match state under a game in progress.
static func hello_admission(before_match: bool, seated_peer: int,
		connected_peer: int, sender: int) -> String:
	if not before_match:
		return "the match has already started"
	if seated_peer != 0:
		return "a peer already holds that seat"
	if sender <= 1:
		return "the sender is not a remote peer"
	if sender != connected_peer:
		return "that peer is not the one that connected"
	return ADMIT_OK


## Anything that speaks FOR the joiner's seat — a move request, or the "I have
## finished watching the duel" ack that opens the cinematic gate. Only the peer
## that actually completed the handshake holds that seat.
static func seat_admission(seated_peer: int, sender: int) -> String:
	if seated_peer == 0:
		return "nobody holds that seat yet"
	if sender != seated_peer:
		return "that peer holds no seat"
	return ADMIT_OK


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

## Interface-name fragments that mean "this is not the network your friend is
## on": virtual switches, VM bridges, container bridges, tunnels, AirDrop.
##
## A development Mac answers `IP.get_local_addresses()` with SIX dialable-looking
## v4 addresses, and only ONE of them is the Wi-Fi. The old ranking printed them
## ip-allow: the scar, quoted — a VM-bridge address this code must NOT offer
## in kernel order, so the host read out `10.10.10.1` (a VM bridge) as the "best"
## LAN address — a wrong number the friend then tried, twice, before anyone
## suspected the list. Interface names are the honest signal, and Godot hands
## them over in `IP.get_local_interfaces()`.
const VIRTUAL_IFACE_HINTS: Array[String] = [
	"bridge", "vmenet", "vmnet", "vnic", "vboxnet", "virbr", "docker", "veth",
	"utun", "tun", "tap", "awdl", "llw", "anpi", "ap1", "gif", "stf",
	"vethernet", "hyper-v", "vmware", "loopback", "tailscale", "zt",
]


## Is `name` an interface a friend could plausibly reach this machine on?
static func _iface_is_real(iface_name: String) -> bool:
	var n := iface_name.to_lower()
	for hint in VIRTUAL_IFACE_HINTS:
		if n.contains(hint):
			return false
	return true


## Can a friend type this address at all? Loopback, link-local, and the
## network/broadcast ends of a subnet are wrong numbers by construction, and a
## dev box is full of them.
static func _is_dialable_v4(s: String) -> bool:
	var parts := s.split(".")
	if parts.size() != 4:
		return false                      # IPv6 — ENet dials v4 here
	if s.begins_with("127.") or s.begins_with("169.254."):
		return false
	for p in parts:
		if not str(p).is_valid_int():
			return false
	var last := int(parts[3])
	return last != 0 and last != 255


static func _is_tailnet_v4(s: String) -> bool:
	var parts := s.split(".")
	if parts.size() != 4:
		return false
	return int(parts[0]) == 100 and int(parts[1]) >= 64 and int(parts[1]) <= 127


## Every IPv4 address a friend could dial, split by how they'd reach it AND
## ordered best-first inside each list. Returns {"tailnet": [...], "lan": [...]}.
##
## Tailscale hands out CGNAT space (the 100.64/10 range): a friend who is on the
## same tailnet reaches that address from anywhere, with no port forwarding and
## no relay of ours. The LAN addresses are for two people on one Wi-Fi — which
## is the case that needs no setup at all, and therefore the one that goes first
## on the panel (see `share_entries`).
##
## LAN ranking, cheapest signal first:
##   1. a physical interface (en0/en1/eth0/"Wi-Fi") beats a virtual one,
##   2. a client host part beats `.1` — your Mac is a client on the Wi-Fi; `.1`
##      is the router, or the host end of a VM bridge.
## The scan behind `local_addresses` — LAN entries still carrying their rank,
## so `share_entries` can tell "this is the Wi-Fi" from "this is a VM bridge".
## Returns {"tailnet": [String], "lan_ranked": [[rank:int, address:String]]}.
static func _scan_interfaces() -> Dictionary:
	var tailnet: Array = []
	var seen: Array = []
	var ranked: Array = []          # [rank, order, address]
	var order := 0
	for iface in IP.get_local_interfaces():
		var iface_name := str(iface.get("name", "")) + " " + str(iface.get("friendly", ""))
		var real := _iface_is_real(iface_name)
		for a in iface.get("addresses", []):
			var s := str(a)
			if not _is_dialable_v4(s) or seen.has(s):
				continue
			seen.append(s)
			if _is_tailnet_v4(s):
				tailnet.append(s)
				continue
			var rank := 0 if real else 2
			if int(s.split(".")[3]) == 1:
				rank += 1               # `.1` is the router / bridge end, not you
			ranked.append([rank, order, s])
			order += 1
	if ranked.is_empty() and tailnet.is_empty():
		# Belt and braces: a platform where get_local_interfaces() comes back
		# empty must still offer whatever addresses it does know, unranked.
		for a in IP.get_local_addresses():
			var s := str(a)
			if not _is_dialable_v4(s):
				continue
			if _is_tailnet_v4(s):
				tailnet.append(s)
			else:
				ranked.append([1, order, s])
				order += 1
	ranked.sort_custom(func(x, y):
		if int(x[0]) != int(y[0]):
			return int(x[0]) < int(y[0])
		return int(x[1]) < int(y[1]))
	var lan_ranked: Array = []
	for r in ranked:
		lan_ranked.append([int(r[0]), str(r[2])])
	return {"tailnet": tailnet, "lan_ranked": lan_ranked}


static func local_addresses() -> Dictionary:
	var scan := _scan_interfaces()
	var lan: Array = []
	for e in scan["lan_ranked"]:
		lan.append(str(e[1]))
	return {"tailnet": scan["tailnet"], "lan": lan}


## How many LAN addresses the Host panel will read out. A developer machine can
## have eight; a person needs the two or three that might be their Wi-Fi.
const SHARE_LAN_MAX := 3


## The addresses to send a friend, best-first, each with WHEN to use it.
## Returns [{address, when, kind}] — `address` is exactly what goes in the
## joiner's box, `when` is the one line that tells a human which to pick.
##
## ORDER (verifier note, 2026-08-09): same-Wi-Fi first. The tailnet address is
## the more powerful one and it used to lead the list, so a host read out a
## 100.x address to a friend who was never on the tailnet — an address that
## cannot work, presented as the best option. Same Wi-Fi needs nothing set up;
## the tailnet line now says out loud what it needs.
static func share_entries(port: int) -> Array[Dictionary]:
	var scan := _scan_interfaces()
	var out: Array[Dictionary] = []
	# If ANY address sits on a real interface, the virtual ones are not offered
	# ip-allow: the three bridge addresses this filter exists to SUPPRESS
	# at all. On this dev Mac that is six candidates down to one: `10.10.10.1`,
	# ip-allow: same — quoted evidence, resolves to nothing and reaches nothing
	# `192.168.105.1` and `10.0.5.1` are VM/Thunderbolt bridges that a friend can
	# never reach, and every one of them printed on the panel is a wrong number
	# somebody is going to try. When nothing looks real, everything is offered —
	# a bad guess must never leave a host with no address to send.
	var lan: Array = []
	var have_real := false
	for e in scan["lan_ranked"]:
		if int(e[0]) <= 1:
			have_real = true
			break
	for e in scan["lan_ranked"]:
		if have_real and int(e[0]) > 1:
			continue
		lan.append(str(e[1]))
	for i in mini(lan.size(), SHARE_LAN_MAX):
		out.append({
			"address": "%s:%d" % [lan[i], port],
			"when": "same Wi-Fi — try this one first" if i == 0 else "same Wi-Fi",
			"kind": "lan",
		})
	for a in scan["tailnet"]:
		out.append({
			"address": "%s:%d" % [a, port],
			"when": "from anywhere, if you are both on the tailnet",
			"kind": "tailnet",
		})
	if out.is_empty():
		out.append({
			"address": "",
			"when": "no network address found — is Wi-Fi on?",
			"kind": "none",
		})
	return out


## The one address a host should send if they only send one — the copy button
## puts exactly this on the clipboard. "" when the machine is offline.
static func primary_address(port: int) -> String:
	var entries := share_entries(port)
	return str(entries[0]["address"]) if not entries.is_empty() else ""


## The address lines a human reads off the Host panel, best option first.
static func share_lines(port: int) -> Array[String]:
	var lines: Array[String] = []
	for e in share_entries(port):
		if str(e["address"]).is_empty():
			lines.append(str(e["when"]))
		else:
			lines.append("%s   ·  %s" % [str(e["address"]), str(e["when"])])
	return lines


# ── Parsing what a human actually pastes ───────────────────────────────────
# ip-allow: a quoted example of the game's own share line — documentation
# The host panel prints "10.0.0.10:7777   ·  same Wi-Fi — try this one first".
# People select the WHOLE LINE and paste it, because that is what a line is.
# Before this, that pasted line went to ENet verbatim and came back as "could
# not reach <the whole line, commentary and all>" — which reads like a wrong
# address, not like a parsing problem (verifier note, 2026-08-09).

## Characters that only ever START commentary on a shared line.
const _COMMENTARY_MARKS: Array[String] = ["(", "—", "–", "·", "←", "→", "#", "|"]


static func _strip_wrappers(token: String) -> String:
	var t := token.strip_edges()
	while not t.is_empty() and "\"'<«`".contains(t[0]):
		t = t.substr(1)
	while not t.is_empty() and "\"'>»`,;.!?:".contains(t[t.length() - 1]):
		t = t.substr(0, t.length() - 1)
	return t.strip_edges()


## Split "host", "host:port", a pasted share line, or "" into [address, port].
## An empty or portless address falls back to DEFAULT_PORT. IPv6 literals in
## brackets are understood so a pasted address is never silently mangled.
static func parse_address(text: String, fallback_port: int = DEFAULT_PORT) -> Array:
	# Clipboards carry non-breaking spaces and newlines; neither is a hostname.
	var s := text.replace(String.chr(0x00A0), " ").replace("\n", " ") \
		.replace("\r", " ").replace("\t", " ").strip_edges()
	if s.is_empty():
		return ["", fallback_port]
	if s.begins_with("["):
		var close := s.find("]")
		if close > 0:
			var host := s.substr(1, close - 1)
			var rest := s.substr(close + 1).strip_edges()
			if rest.begins_with(":") and rest.substr(1).is_valid_int():
				return [host, int(rest.substr(1))]
			return [host, fallback_port]
	# Cut trailing commentary, then pick the first token that can BE an address.
	for mark in _COMMENTARY_MARKS:
		var at := s.find(mark)
		if at > 0:
			s = s.substr(0, at)
	var tokens := s.split(" ", false)
	var candidate := ""
	if tokens.size() == 1:
		candidate = _strip_wrappers(tokens[0])      # a bare hostname, typed by hand
	else:
		for t in tokens:
			var c := _strip_wrappers(t)
			if c.contains("."):                     # an IPv4 literal or an FQDN
				candidate = c
				break
	if candidate.is_empty():
		return ["", fallback_port]
	var colon := candidate.rfind(":")
	if colon > 0 and candidate.count(":") == 1 and candidate.substr(colon + 1).is_valid_int():
		return [candidate.substr(0, colon), int(candidate.substr(colon + 1))]
	return [candidate, fallback_port]


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


# The host's three refusals of a request it will not even look at. They live
# here, next to the validator's own reasons, because the two-instance e2e's
# wrong-turn probe RACES the opponent's ply and must accept either
# `wrong_turn_text` or `stale_request_text` — a reword in one place used to be
# able to drift that gate back into flakiness silently, so both are pinned by
# tests/test_net.gd.

## The generation guard: a request written for a position already played past.
static func stale_request_text() -> String:
	return "that move was for an earlier position — the board has moved on"


## The validator's answer when the requester does not own the move.
static func wrong_turn_text() -> String:
	return "it is not your turn"


## The cinematic barrier is still holding the previous ply.
static func gate_held_text() -> String:
	return "hold on — the duel is still playing on your opponent's screen"


static func match_not_running_text() -> String:
	return "the match is not running"


static func protocol_mismatch_text(theirs: int) -> String:
	return ("your friend is running a different version of Great Hauses "
		+ "(their protocol %d, yours %d) — you both need the same build.") % [
			theirs, PROTOCOL_VERSION]


## The move went out and the host has not answered yet. Said while the board is
## still held: the move may land a second from now.
static func request_slow_text() -> String:
	return "your friend's game hasn't answered yet — waiting…"


## The host never answered. Said while HANDING THE BOARD BACK, with the way out
## named in the same breath — this is the sentence that replaced a frozen screen.
static func request_stalled_text() -> String:
	return ("Your friend's game stopped answering.\nYour move was never played. "
		+ "Keep waiting if you like — or return to the Hall of Banners.")


static func request_recovered_text() -> String:
	return "your friend's game answered — the match goes on"


# ── What to say BEFORE anything can go wrong ───────────────────────────────
# Both of these used to exist only inside a failure message, which is the one
# place a person reads them too late (verifier notes, 2026-08-09).

## On the Play a Friend panel, before Host or Join is ever pressed.
static func prerequisite_text() -> String:
	return ("Before you start: you must both be on the SAME Wi-Fi — "
		+ "or both on the same tailnet.")


## On the Host panel, before the gates open. macOS asks on the first host, and
## Windows Defender asks too; the dialog looks exactly like something is wrong.
static func firewall_text() -> String:
	return ("Your Mac (or Windows Defender) will ask whether to allow incoming "
		+ "network connections — click Allow. Without it your friend cannot "
		+ "reach you, and it looks just like a wrong address.")
