extends SceneTree

# Headless integration test for the DS4-ORACLE opponent (src/ai/ds4_opponent.gd).
# Run: /Applications/Godot.app/Contents/MacOS/Godot --headless --path <project> -s res://tests/test_ds4_opponent.gd
# Exit code 0 = all green, 1 = failures.
#
# Two paths, BOTH implemented:
#  * live  — if the real endpoint (default http://127.0.0.1:18000, override
#            DS4_CHESS_URL) answers ping() within 5 s: one real move from the
#            starting position, asserted legal.
#  * mock  — always runs: a tiny in-process HTTP server (TCPServer) replays
#            canned OpenAI-style completions, covering ping, clean move,
#            corrective retry, random-move fallback + oracle_stumbled, and
#            the "Oracle sleeps" preflight failure. Green offline.

const Ds4OpponentScript := preload("res://src/ai/ds4_opponent.gd")
const CS := preload("res://src/chess/ChessState.gd")

const MOCK_MODEL := "deepseek-v4-flash-mock"

var rows := []
var failures := 0
var _mark := 0

# -- mock server state --
var _server: TCPServer
var _mock_running := false
var _mock_replies: Array = []    # queued chat contents; falls back to "MOVE: e2e4"
var _mock_requests: Array = []   # parsed JSON bodies of every /chat/completions call


func _initialize() -> void:
	_main()


func _main() -> void:
	print("=== DS4-ORACLE opponent — headless integration test ===")
	_mark = Time.get_ticks_msec()
	var saved_env := OS.get_environment(Ds4OpponentScript.ENV_URL)

	# Live path: only when the real endpoint answers the preflight within 5 s.
	var live_opp: Ds4OpponentScript = await _make_opponent("LiveOracle")
	var live: bool = await live_opp.ping(5.0)
	if live:
		print("live endpoint reachable at %s — running live move test" % live_opp.chat_url())
		await _test_live_move(live_opp)
	else:
		print("live endpoint unreachable (%s) — mock-only run (green offline path)" % live_opp.offline_reason)
	live_opp.queue_free()

	await _run_mock_suite()

	OS.set_environment(Ds4OpponentScript.ENV_URL, saved_env)
	_print_summary()


# -- helpers (same style as run_tests.gd) -----------------------------------


func check(test_name: String, expected, actual) -> void:
	var now := Time.get_ticks_msec()
	var ms := now - _mark
	_mark = now
	var ok := str(expected) == str(actual)
	if not ok:
		failures += 1
	rows.push_back([test_name, str(expected), str(actual), ok, ms])


func _make_opponent(node_name: String) -> Ds4OpponentScript:
	var o: Ds4OpponentScript = Ds4OpponentScript.new()
	o.name = node_name
	root.add_child(o)
	while not o.is_inside_tree():  # during _initialize the tree isn't live yet
		await process_frame
	return o


func _is_legal_uci(state, uci: String) -> bool:
	return state.move_from_uci(uci) != null


func _print_summary() -> void:
	print("")
	print("%-46s %-14s %-14s %-6s %s" % ["test", "expected", "actual", "ok", "ms"])
	for row in rows:
		print("%-46s %-14s %-14s %-6s %d" % [row[0], row[1].left(14), row[2].left(14), "PASS" if row[3] else "FAIL", row[4]])
	print("")
	print("%d checks, %d failures" % [rows.size(), failures])
	quit(0 if failures == 0 else 1)


# -- live path --------------------------------------------------------------


func _test_live_move(opp: Ds4OpponentScript) -> void:
	var state = CS.new()
	var move: Variant = await opp.choose_move(state)
	check("live: move returned", true, move != null)
	if move != null:
		check("live: move is legal from startpos", true, _is_legal_uci(state, move.to_uci()))
		check("live: source is llm*", true, String(opp.last_source).begins_with("llm"))
		state.apply_move(move)
		check("live: state advanced to black", true, state.turn)
		print("live: the Oracle played %s (%s, %.1fs)" % [move.to_uci(), opp.last_source, opp.last_elapsed_s])


# -- mock path --------------------------------------------------------------


func _run_mock_suite() -> void:
	_server = TCPServer.new()
	var err := _server.listen(0, "127.0.0.1")
	check("mock: server listens", "OK", error_string(err))
	if err != OK:
		return
	var port := _server.get_local_port()
	OS.set_environment(Ds4OpponentScript.ENV_URL, "http://127.0.0.1:%d" % port)
	_mock_running = true
	_pump_mock()

	var opp: Ds4OpponentScript = await _make_opponent("MockOracle")
	var started := [0]
	var finished: Array = []
	var stumbles: Array = []
	opp.thinking_started.connect(func() -> void: started[0] += 1)
	opp.thinking_finished.connect(func(elapsed_s: float) -> void: finished.append(elapsed_s))
	opp.oracle_stumbled.connect(func(reason: String) -> void: stumbles.append(reason))

	# 1. preflight against the mock
	var ok: bool = await opp.ping(5.0)
	check("mock: ping true", true, ok)
	check("mock: model adopted from list", MOCK_MODEL, opp.model)

	# 2. clean MAX-THINKING move
	_mock_requests.clear()
	_mock_replies = [
		"Candidates: e2e4 grabs the center; g1f3 develops; d2d4 also fights " +
		"for the center. e2e4 opens lines fastest and is the strongest here.\n" +
		"MOVE: e2e4",
	]
	var state = CS.new()
	var move: Variant = await opp.choose_move(state)
	check("mock: clean move uci", "e2e4", move.to_uci() if move != null else "null")
	check("mock: clean move source", "llm", opp.last_source)
	check("mock: thinking_started fired", 1, started[0])
	check("mock: thinking_finished fired", 1, finished.size())
	check("mock: elapsed sane", true, opp.last_elapsed_s >= 0.0 and opp.last_elapsed_s < 120.0)
	check("mock: one chat request", 1, _mock_requests.size())
	if _mock_requests.size() == 1:
		var body: Dictionary = _mock_requests[0]
		check("mock: temperature 0.3", 0.3, body.get("temperature"))
		check("mock: max_tokens 3072", 3072, int(body.get("max_tokens", 0)))  # JSON numbers arrive as float
		var msgs: Array = body.get("messages", [])
		check("mock: system+user messages", 2, msgs.size())
		check("mock: system prompt demands MOVE line", true,
			msgs.size() > 0 and String(msgs[0].get("content", "")).contains("MOVE: <uci>"))
		check("mock: user prompt carries FEN", true,
			msgs.size() > 1 and String(msgs[1].get("content", "")).contains(state.get_fen().get_slice(" ", 0)))
		check("mock: user prompt lists legal moves", true,
			msgs.size() > 1 and String(msgs[1].get("content", "")).contains("g1f3"))

	# 3. corrective retry: first reply unusable, second legal
	_mock_requests.clear()
	_mock_replies = [
		"The stars are unclear tonight; the raven brings no move.",
		"On reflection, the knight strikes first.\nMOVE: g1f3",
	]
	state = CS.new()
	move = await opp.choose_move(state)
	check("mock: retry move uci", "g1f3", move.to_uci() if move != null else "null")
	check("mock: retry source", "llm-retry1", opp.last_source)
	check("mock: two chat requests", 2, _mock_requests.size())
	if _mock_requests.size() == 2:
		var msgs2: Array = _mock_requests[1].get("messages", [])
		check("mock: corrective convo grows to 4", 4, msgs2.size())
		check("mock: corrective message scolds", true,
			msgs2.size() == 4 and String(msgs2[3].get("content", "")).contains("could not be used"))

	# 4. fallback: every reply unusable -> random legal move, loudly flagged
	_mock_requests.clear()
	_mock_replies = ["??", "??", "??", "??"]
	state = CS.new()
	move = await opp.choose_move(state)
	check("mock: fallback returns a move", true, move != null)
	if move != null:
		check("mock: fallback move is legal", true, _is_legal_uci(state, move.to_uci()))
	check("mock: fallback source", "fallback", opp.last_source)
	check("mock: fallback used 4 attempts", 4, _mock_requests.size())
	check("mock: oracle_stumbled fired once", 1, stumbles.size())
	check("mock: stumble carries the HUD line", true,
		stumbles.size() == 1 and String(stumbles[0]).contains(Ds4OpponentScript.STUMBLE_TEXT))

	# 5. the Oracle sleeps: preflight against a dead port
	var dead := TCPServer.new()
	dead.listen(0, "127.0.0.1")
	var dead_port := dead.get_local_port()
	dead.stop()
	OS.set_environment(Ds4OpponentScript.ENV_URL, "http://127.0.0.1:%d" % dead_port)
	ok = await opp.ping(2.0)
	check("mock: dead-port ping false", false, ok)
	check("mock: offline reason says Oracle sleeps", true,
		String(opp.offline_reason).contains(Ds4OpponentScript.OFFLINE_TEXT))

	_mock_running = false
	_server.stop()
	opp.queue_free()


# -- tiny canned HTTP/1.1 server on TCPServer -------------------------------


func _pump_mock() -> void:
	while _mock_running:
		if _server.is_connection_available():
			var peer := _server.take_connection()
			await _handle_conn(peer)
		await process_frame


func _handle_conn(peer: StreamPeerTCP) -> void:
	peer.set_no_delay(true)
	var raw := PackedByteArray()
	var deadline := Time.get_ticks_msec() + 5000
	var header_end := -1
	var content_len := 0
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		var n := peer.get_available_bytes()
		if n > 0:
			var chunk: Array = peer.get_data(n)
			if chunk[0] == OK:
				raw.append_array(chunk[1])
		if header_end < 0:
			header_end = _find_header_end(raw)
			if header_end >= 0:
				content_len = _parse_content_length(raw.slice(0, header_end).get_string_from_utf8())
		if header_end >= 0 and raw.size() >= header_end + content_len:
			break
		await process_frame
	if header_end < 0:
		peer.disconnect_from_host()
		return
	var request_line := raw.slice(0, header_end).get_string_from_utf8().get_slice("\r\n", 0)
	var path := request_line.get_slice(" ", 1)
	var response_body: String
	if path.ends_with("/models"):
		response_body = JSON.stringify({
			"object": "list",
			"data": [{"id": MOCK_MODEL, "object": "model"}],
		})
	else:
		var body_text := raw.slice(header_end, header_end + content_len).get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(body_text)
		_mock_requests.append(parsed if parsed is Dictionary else {})
		var content := "MOVE: e2e4"
		if not _mock_replies.is_empty():
			content = _mock_replies.pop_front()
		response_body = JSON.stringify({
			"id": "chatcmpl-mock",
			"object": "chat.completion",
			"model": MOCK_MODEL,
			"choices": [{
				"index": 0,
				"message": {"role": "assistant", "content": content},
				"finish_reason": "stop",
			}],
			"usage": {"prompt_tokens": 0, "completion_tokens": 0},
		})
	var body_bytes := response_body.to_utf8_buffer()
	var head := ("HTTP/1.1 200 OK\r\n" +
		"Content-Type: application/json\r\n" +
		"Content-Length: %d\r\n" % body_bytes.size() +
		"Connection: close\r\n\r\n")
	peer.put_data(head.to_utf8_buffer())
	peer.put_data(body_bytes)
	for i in 8:  # let the client drain before we hang up
		peer.poll()
		await process_frame
	peer.disconnect_from_host()


func _find_header_end(raw: PackedByteArray) -> int:
	for i in range(0, raw.size() - 3):
		if raw[i] == 13 and raw[i + 1] == 10 and raw[i + 2] == 13 and raw[i + 3] == 10:
			return i + 4
	return -1


func _parse_content_length(headers: String) -> int:
	for line in headers.split("\r\n"):
		if line.to_lower().begins_with("content-length:"):
			return int(line.get_slice(":", 1).strip_edges())
	return 0
