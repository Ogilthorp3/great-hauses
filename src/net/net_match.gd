class_name NetMatch
extends Node
## Great Houses — head-to-head transport. One player HOSTS (their instance is
## authoritative and owns the ChessState); the other JOINS by address. Godot 4
## high-level multiplayer over ENetMultiplayerPeer: no third-party server, no
## relay of ours, nothing to run but the game.
##
## WHERE THIS NODE LIVES. It parks itself at `/root/NetMatch`, NOT in a scene,
## because the connection is opened in the Hall of Banners and must survive
## `change_scene_to_file` into the match. Same NodePath on both machines is
## also what makes the RPCs resolve. It is created at runtime (`NetMatch.ensure`)
## rather than added to project.godot's autoload list, so a single-player boot
## carries none of it.
##
## THE SHAPE (stolen from ds4-chess-bridge/ds4_chess_bot.py, which proved it on
## this machine, then rewritten for GDScript):
##   * authoritative server — the host's board is the only board,
##   * per-move validation — every request is checked against the host's own
##     legal-move list before anything moves (NetProtocol.validate_request),
##   * generation guards — every packet carries the ply `seq` it was written
##     for, and a packet for a dead position is dropped, not applied,
##   * an explicit readiness handshake — here it gates on CINEMATICS, so a
##     capture duel plays out fully on BOTH screens before the turn advances.
##
## What this node deliberately does NOT do: it never touches the board, the
## views, or the camera. It hands `game.gd` validated move payloads and lets
## the presentation layer animate them.

const NODE_NAME := "NetMatch"

enum State {
	IDLE,        ## nothing open
	HOSTING,     ## server up, waiting for a friend
	CONNECTING,  ## dialling the host
	IN_MATCH,    ## both seated, play in progress
	FAILED,      ## could not connect / could not host — `detail` says why
	CLOSED,      ## the other side left, or we hung up
}

## Every transition carries a line meant for a human, not a log parser.
signal state_changed(state: int, detail: String)
## Both sides seated; carries {seq, fen, your_color, your_house, their_house,
## white_house, black_house}.
signal match_ready(info: Dictionary)
## A validated ply — {seq, move, fen_after, san}. Both sides get the same one.
signal move_applied(payload: Dictionary)
## The host refused OUR request, with the reason it refused it.
signal move_rejected(reason: String)
## Both sides finished watching ply `seq`; turn flow may advance.
signal gate_opened(seq: int, forced: bool)
signal opponent_left(reason: String)
## Our board disagrees with the host's after applying a ply. Loud, never silent.
signal desync(detail: String)
## Joiner side: the host has not answered our move request yet (see
## net_request_clock.gd). `slow` = say so, board still held; `stalled` = give
## the board back and offer the way out; `recovered` = it answered after all.
signal request_slow(seq: int)
signal request_stalled(seq: int)
signal request_recovered(seq: int)

var is_host := false
var my_color := NetProtocol.COLOR_WHITE
var my_house := ""
var their_house := ""
var start_fen := ""
var state: int = State.IDLE
var detail := ""
var port: int = NetProtocol.DEFAULT_PORT
var address := ""

## The ply counter both sides agree on. Every request carries it; a request
## for any other ply is a packet from a dead position.
var seq := 0
## e2e / diagnostics evidence — read by the driver, never by game logic.
var applied_count := 0
var rejected_count := 0
var last_reject_reason := ""
var gate_forced_count := 0
## e2e / diagnostics evidence for the request deadline (P1).
var request_slow_count := 0
var request_stalled_count := 0
## e2e / diagnostics evidence for the hardened RPC guards (P2/P3): packets that
## were dropped because of WHO sent them or WHEN.
var refused_packet_count := 0
var last_refused_packet := ""

var _peer: ENetMultiplayerPeer = null
var _client_id := 0                  ## host side: the joiner's peer id
## host side: the peer that completed the handshake and OWNS the other seat.
## Nothing but this peer may request a move or ack a ply (P2/P3).
var _seated_peer := 0
var _state_ref = null                ## host side: game.gd's authoritative ChessState
var _gate := NetPlyGate.new()
## joiner side: the deadline on a move request the host has not answered (P1).
var _req := NetRequestClock.new()
var _connect_deadline_ms := 0
var _hello_sent := false


# ── Lifecycle ──────────────────────────────────────────────────────────────

## The one way to get a NetMatch: it is a child of the SceneTree root so it
## outlives every scene change.
static func ensure(tree: SceneTree) -> NetMatch:
	var existing := get_active(tree)
	if existing != null:
		return existing
	var n := NetMatch.new()
	n.name = NODE_NAME
	tree.root.add_child(n)
	if not n.is_inside_tree():
		# The SceneTree root refuses children while a scene is being set up
		# ("parent node is busy setting up children"), and a Node outside the
		# tree has no `multiplayer` to bind a peer to — the failure then shows
		# up as a baffling "null instance" when the socket is created.
		# Callers must reach NetMatch from a deferred call or a signal, never
		# from inside _ready (see main.gd's deferred command-line boot).
		push_error("NetMatch.ensure() was called while the scene tree was blocked — "
			+ "defer the call")
		n.free()
		return null
	return n


static func get_active(tree: SceneTree) -> NetMatch:
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(NODE_NAME) as NetMatch


## True when a match is actually being played over the wire. `game.gd` asks
## this before every single-player assumption (AI reply, take-back, rematch).
func is_active() -> bool:
	return state == State.IN_MATCH


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if state == State.CONNECTING and _connect_deadline_ms > 0 and now > _connect_deadline_ms:
		_connect_deadline_ms = 0
		_fail(NetProtocol.unreachable_text(address, port))
		return
	# The cinematic gate's failsafe: a peer stuck mid-duel may delay the match,
	# never freeze it. Host arbitrates, so only the host ticks the clock.
	if is_host and state == State.IN_MATCH and _gate.tick(now, NetProtocol.GATE_TIMEOUT_SEC):
		gate_forced_count += 1
		push_warning("NetMatch: ply %d gate forced open — the other side never " \
			% _gate.seq + "reported finishing the cinematic")
		_rpc_gate_open.rpc(_gate.seq, true)
		gate_opened.emit(_gate.seq, true)
	tick_requests(now)


## The joiner's request deadline (P1), split out from `_process` so a test can
## drive it on a clock it controls instead of on twenty seconds of wall time.
func tick_requests(now_ms: int) -> void:
	if is_host or state != State.IN_MATCH:
		return
	match _req.tick(now_ms, NetProtocol.REQUEST_SLOW_SEC, NetProtocol.REQUEST_TIMEOUT_SEC):
		NetRequestClock.PHASE_SLOW:
			request_slow_count += 1
			request_slow.emit(_req.seq)
		NetRequestClock.PHASE_STALLED:
			request_stalled_count += 1
			push_warning("NetMatch: the host never answered the request for ply %d "
				% _req.seq + "— handing the board back")
			request_stalled.emit(_req.seq)


## True while a move request is outstanding and past its deadline — the board
## has been handed back but nothing has been played.
func request_is_stalled() -> bool:
	return _req.stalled()


## True while a move request is late but still held (the HUD says so).
func request_is_slow() -> bool:
	return _req.phase == NetRequestClock.PHASE_SLOW


## Hang up and remove the node. Safe to call twice.
func shutdown() -> void:
	if _peer != null:
		_peer.close()
		_peer = null
	if multiplayer != null:
		multiplayer.multiplayer_peer = null
	_state_ref = null
	_req.clear()
	state = State.CLOSED
	if is_inside_tree():
		# Rename BEFORE queue_free: the node lives until the end of the frame,
		# and `ensure()` looking up /root/NetMatch in the meantime would hand
		# back the corpse (the second Host attempt would rebind a dead socket).
		name = "NetMatchClosed"
		queue_free()


# ── Opening a room ─────────────────────────────────────────────────────────

## Host a match. `side` is "white" | "black" | "random". Returns false (and
## sets FAILED with a readable detail) when the port cannot be opened.
func host_match(house_id: String, side: String, listen_port: int = NetProtocol.DEFAULT_PORT,
		fen: String = "") -> bool:
	is_host = true
	my_house = house_id
	port = listen_port
	start_fen = fen
	var seats := NetProtocol.seat(side, randi() % 2 == 1)
	my_color = bool(seats["host"])
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, 1)
	if err != OK:
		_peer = null
		_fail(NetProtocol.host_bind_failed_text(port))
		return false
	multiplayer.multiplayer_peer = _peer
	_set_state(State.HOSTING, "waiting for your friend to join…")
	return true


## Join a hosted match. `addr_text` may carry ":port".
func join_match(house_id: String, addr_text: String,
		fallback_port: int = NetProtocol.DEFAULT_PORT) -> bool:
	is_host = false
	my_house = house_id
	var parsed := NetProtocol.parse_address(addr_text, fallback_port)
	address = str(parsed[0])
	port = int(parsed[1])
	if address.is_empty():
		_fail("type the address your friend gave you (it looks like 100.x.y.z)")
		return false
	_hello_sent = false
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address, port)
	if err != OK:
		_peer = null
		_fail(NetProtocol.unreachable_text(address, port))
		return false
	multiplayer.multiplayer_peer = _peer
	_connect_deadline_ms = Time.get_ticks_msec() \
		+ int(NetProtocol.CONNECT_TIMEOUT_SEC * 1000.0)
	_set_state(State.CONNECTING, "reaching %s:%d…" % [address, port])
	return true


## The host's authoritative board. `game.gd` hands it over on match start;
## every request is validated against THIS and nothing else.
func attach_state(chess_state) -> void:
	_state_ref = chess_state


# ── Peer plumbing ──────────────────────────────────────────────────────────

func _on_peer_connected(id: int) -> void:
	if not is_host:
		return
	_client_id = id
	_set_state(State.HOSTING, "your friend is here — dressing the hall…")


func _on_peer_disconnected(id: int) -> void:
	if not is_host or id != _client_id:
		return
	_client_id = 0
	_seated_peer = 0
	_leave("your friend's game closed the connection")


func _on_connected_to_server() -> void:
	_connect_deadline_ms = 0
	if _hello_sent:
		return
	_hello_sent = true
	_set_state(State.CONNECTING, "connected — telling the host which banner you fly…")
	_rpc_hello.rpc_id(1, NetProtocol.PROTOCOL_VERSION, my_house)


func _on_connection_failed() -> void:
	_connect_deadline_ms = 0
	_fail(NetProtocol.unreachable_text(address, port))


func _on_server_disconnected() -> void:
	_leave("the host's game closed, or the network dropped")


func _set_state(s: int, why: String) -> void:
	state = s
	detail = why
	state_changed.emit(s, why)


func _fail(why: String) -> void:
	if _peer != null:
		_peer.close()
		_peer = null
	if multiplayer != null:
		multiplayer.multiplayer_peer = null
	_set_state(State.FAILED, why)


func _leave(why: String) -> void:
	var was_playing := state == State.IN_MATCH or state == State.HOSTING \
		or state == State.CONNECTING
	_req.clear()   # a pending request cannot be answered by a peer that is gone
	_set_state(State.CLOSED, why)
	if was_playing:
		opponent_left.emit(why)


# ── Handshake ──────────────────────────────────────────────────────────────

## A packet arrived that the host will not act on because of WHO sent it or
## WHEN. Recorded (never silent) and dropped — never answered, because an
## answer is itself a lever a bad packet could pull.
func _refuse_packet(what: String) -> void:
	refused_packet_count += 1
	last_refused_packet = what
	push_warning("NetMatch: dropped %s" % what)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_hello(their_protocol: int, house_id: String) -> void:
	if not is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	# P2 (verifier, 2026-08-09). `_rpc_hello` is any_peer with no state guard,
	# so a SECOND hello from the live client mid-match walked straight through
	# here and reset the host's match state: seq back to 0, the gate re-armed,
	# both seats re-dealt, under a game already in progress. A hello is the
	# handshake — it is only meaningful BEFORE the match starts, and only from a
	# peer that does not already hold a seat. Anything else is dropped, and
	# dropped SILENTLY: replying `_rpc_refused` to the seated joiner would make
	# it `_fail()` its own live match, which is the same bug facing the other way.
	var dropped := NetProtocol.hello_admission(
		state == State.HOSTING, _seated_peer, _client_id, sender)
	if dropped != NetProtocol.ADMIT_OK:
		_refuse_packet("a hello from peer %d — %s" % [sender, dropped])
		return
	if their_protocol != NetProtocol.PROTOCOL_VERSION:
		var why := NetProtocol.protocol_mismatch_text(their_protocol)
		_rpc_refused.rpc_id(sender, why)
		_fail(why)
		return
	_seated_peer = sender
	their_house = house_id
	seq = 0
	_gate.begin(-1, Time.get_ticks_msec())
	var white_house := my_house if my_color == NetProtocol.COLOR_WHITE else their_house
	var black_house := their_house if my_color == NetProtocol.COLOR_WHITE else my_house
	_rpc_match_start.rpc_id(sender, {
		"protocol": NetProtocol.PROTOCOL_VERSION,
		"seq": seq,
		"fen": start_fen,
		"your_color": not my_color,
		"white_house": white_house,
		"black_house": black_house,
	})
	_seat_and_announce(white_house, black_house)


@rpc("authority", "call_remote", "reliable")
func _rpc_match_start(info: Dictionary) -> void:
	if is_host:
		return
	my_color = bool(info.get("your_color", NetProtocol.COLOR_BLACK))
	seq = int(info.get("seq", 0))
	start_fen = str(info.get("fen", ""))
	var white_house := str(info.get("white_house", ""))
	var black_house := str(info.get("black_house", ""))
	their_house = black_house if my_color == NetProtocol.COLOR_WHITE else white_house
	_gate.begin(-1, Time.get_ticks_msec())
	_seat_and_announce(white_house, black_house)


@rpc("authority", "call_remote", "reliable")
func _rpc_refused(why: String) -> void:
	_fail(why)


func _seat_and_announce(white_house: String, black_house: String) -> void:
	_set_state(State.IN_MATCH, "%s (%s) vs %s (%s)" % [
		my_house, NetProtocol.color_name(my_color),
		their_house, NetProtocol.color_name(not my_color)])
	match_ready.emit({
		"seq": seq,
		"fen": start_fen,
		"your_color": my_color,
		"your_house": my_house,
		"their_house": their_house,
		"white_house": white_house,
		"black_house": black_house,
		"is_host": is_host,
	})


# ── Moves ──────────────────────────────────────────────────────────────────

## The ONE way a ply enters the match, called identically on both machines.
## The host short-circuits into its own validator; the joiner puts a request
## on the wire and waits to be told what happened.
func request_move(move) -> void:
	if not is_active() or move == null:
		return
	var promo := "" if move.promotion == null else str(move.promotion).to_lower()
	if is_host:
		# The host answers itself synchronously — there is no wire to lose it on,
		# so there is nothing to put on a deadline.
		_handle_request(1, seq, int(move.from_square), int(move.to_square), promo)
	else:
		# P1: from this instant the host OWES us an answer. If it never comes,
		# `tick_requests` says so and hands the board back — the joiner never
		# sits on a frozen board again.
		begin_request_deadline(seq, Time.get_ticks_msec())
		_rpc_request_move.rpc_id(1, seq, int(move.from_square), int(move.to_square), promo)


## Start the answer deadline for a request that has just gone on the wire.
## `request_move` calls it the instant the packet leaves. `tests/test_net.gd`
## calls it too, and then never delivers the packet — which is exactly the
## failure being covered: a request the host never answers.
func begin_request_deadline(s: int, now_ms: int) -> void:
	_req.arm(s, now_ms)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_move(req_seq: int, from_idx: int, to_idx: int, promo: String) -> void:
	if not is_host:
		return
	# P3's sibling: `_handle_request` derives the mover's COLOUR from the sender
	# id, so an unseated peer would be handed the joiner's side of the board.
	var sender := multiplayer.get_remote_sender_id()
	var why := NetProtocol.seat_admission(_seated_peer, sender)
	if why != NetProtocol.ADMIT_OK:
		_refuse_packet("a move request from peer %d — %s" % [sender, why])
		return
	_handle_request(sender, req_seq, from_idx, to_idx, promo)


## HOST AUTHORITY, in one function. Nothing a client sends can move a piece
## except by passing every check here.
func _handle_request(sender_id: int, req_seq: int, from_idx: int, to_idx: int,
		promo: String) -> void:
	if not is_active():
		_reject(sender_id, NetProtocol.match_not_running_text())
		return
	if req_seq != seq:
		# Generation guard: a request written for a position that has already
		# been played past. Dropping it is the whole point.
		_reject(sender_id, NetProtocol.stale_request_text())
		return
	if not _gate.accepting():
		_reject(sender_id, NetProtocol.gate_held_text())
		return
	var mover_color := my_color if sender_id == 1 else not my_color
	var verdict := NetProtocol.validate_request(_state_ref, mover_color, from_idx, to_idx, promo)
	if not bool(verdict["ok"]):
		_reject(sender_id, str(verdict["reason"]))
		return
	var payload := NetProtocol.applied_payload(_state_ref, verdict["move"], seq)
	_rpc_move_applied.rpc(payload)
	_consume_applied(payload)


func _reject(sender_id: int, reason: String) -> void:
	rejected_count += 1
	last_reject_reason = reason
	if sender_id == 1:
		move_rejected.emit(reason)     # the host refused its own click
	else:
		_rpc_move_rejected.rpc_id(sender_id, seq, reason)


@rpc("authority", "call_remote", "reliable")
func _rpc_move_applied(payload: Dictionary) -> void:
	if is_host:
		return
	if int(payload.get("seq", -1)) != seq:
		push_warning("NetMatch: dropped a move_applied for ply %d (holding %d)"
			% [int(payload.get("seq", -1)), seq])
		return
	_consume_applied(payload)


@rpc("authority", "call_remote", "reliable")
func _rpc_move_rejected(_rej_seq: int, reason: String) -> void:
	if is_host:
		return
	_answered()
	rejected_count += 1
	last_reject_reason = reason
	move_rejected.emit(reason)


## The host answered — disarm the deadline, and if we had already told the
## player something was wrong, tell them it is not any more (P1).
func _answered() -> void:
	var was_late := _req.phase == NetRequestClock.PHASE_SLOW \
		or _req.phase == NetRequestClock.PHASE_STALLED
	var s := _req.seq
	if _req.clear() and was_late:
		request_recovered.emit(s)


func _consume_applied(payload: Dictionary) -> void:
	_answered()
	applied_count += 1
	var played: int = int(payload.get("seq", seq))
	seq = played + 1
	# The gate now holds the PLY JUST PLAYED: both sides must report they have
	# finished watching it (duel included) before the next request is taken.
	_gate.begin(played, Time.get_ticks_msec())
	move_applied.emit(payload)


## "I have finished animating ply `s` — cinematic and all." Called by game.gd
## at the end of `_execute_ply`, on both machines.
func ack_ply(s: int) -> void:
	if not is_active():
		return
	if is_host:
		if _gate.ack(s, NetPlyGate.ROLE_HOST, Time.get_ticks_msec()):
			_rpc_gate_open.rpc(s, false)
			gate_opened.emit(s, false)
	else:
		_rpc_ack_ply.rpc_id(1, s)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_ack_ply(s: int) -> void:
	if not is_host:
		return
	# P3 (verifier, 2026-08-09). This is the cinematic barrier's other half: an
	# ack here is a claim that A PARTICULAR PLAYER has finished watching a duel,
	# and the host was taking that claim on the packet's word. Godot names the
	# sender, so use it — only the peer actually seated in the joiner's chair
	# may ack the joiner's side, and it may only ack the ply the gate is
	# holding (NetPlyGate drops the rest). A forged or extra ack cannot open the
	# gate early and cut a duel off on the other player's screen.
	var sender := multiplayer.get_remote_sender_id()
	var why := NetProtocol.seat_admission(_seated_peer, sender)
	if why != NetProtocol.ADMIT_OK:
		_refuse_packet("a cinematic ack for ply %d from peer %d — %s" % [s, sender, why])
		return
	if _gate.ack(s, NetPlyGate.ROLE_JOIN, Time.get_ticks_msec()):
		_rpc_gate_open.rpc(s, false)
		gate_opened.emit(s, false)


@rpc("authority", "call_remote", "reliable")
func _rpc_gate_open(s: int, forced: bool) -> void:
	if is_host:
		return
	if forced:
		gate_forced_count += 1
	_gate.opened = true
	_gate.seq = s
	gate_opened.emit(s, forced)


## Has the gate for ply `s` opened? game.gd blocks its turn flow on this.
func gate_is_open(s: int) -> bool:
	return _gate.is_open_for(s)


## Report a FEN disagreement. Loud on both sides — a chess client that
## silently diverges is worse than one that stops.
func report_desync(local_fen: String, host_fen: String) -> void:
	var why := "the two boards disagree (yours %s, the host's %s)" % [local_fen, host_fen]
	push_error("NetMatch desync — " + why)
	desync.emit(why)
