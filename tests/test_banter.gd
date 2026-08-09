extends SceneTree

# Headless test for the rival-house SMACK TALK module (src/banter/banter.gd).
# Run: /Applications/Godot.app/Contents/MacOS/Godot --headless --path <project> -s res://tests/test_banter.gd
# Exit code 0 = all green, 1 = failures.
#
# Coverage:
#  * pool completeness — every house x beat has >=8 canned lines, all <=90
#    chars, unique within a house, {piece} the only token
#  * persona prompts — per-archetype voice + the hard style rules
#  * sanitize_line contract
#  * rate limiter — 2-full-move gap, one in flight, blunder/bookends exempt
#  * dedupe — no repeated line within a game, pool exhaustion, reset_game
#  * fallback — dead endpoint -> canned pool (green offline)
#  * LLM path — tiny in-process mock server (same pattern as
#    test_ds4_opponent.gd): request body, quote stripping, clamping,
#    dupe-from-LLM -> pool

const BE := preload("res://src/banter/banter.gd")
const LONG_REPLY := "Hear me, small king of a small hall: your fields are ash, your songs are borrowed, your walls lean, your knights doze, and your banners beg the wind for mercy it does not carry."

var rows := []
var failures := 0
var _mark := 0

# -- mock server state (test_ds4_opponent.gd pattern) --
var _server: TCPServer
var _mock_running := false
var _mock_replies: Array = []    # queued chat contents
var _mock_requests: Array = []   # parsed JSON bodies of every /chat/completions call


func _initialize() -> void:
	_main()


func _main() -> void:
	print("=== Rival-house banter — headless test suite ===")
	_mark = Time.get_ticks_msec()
	var saved_env := OS.get_environment(BE.ENV_URL)

	_test_pool_completeness()
	_test_persona_prompts()
	_test_beat_prompts()
	_test_sanitize()
	_test_rate_limiter()
	_test_dedupe_and_reset()
	await _test_fallback_dead_endpoint()
	await _test_llm_mock()

	OS.set_environment(BE.ENV_URL, saved_env)
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


func _make_engine(node_name: String):
	var e = BE.new()
	e.name = node_name
	root.add_child(e)
	return e


func _wait_lines(got: Array, count: int, timeout_ms := 12000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while got.size() < count and Time.get_ticks_msec() < deadline:
		await process_frame
	return got.size() >= count


func _print_summary() -> void:
	print("")
	print("%-52s %-14s %-14s %-6s %s" % ["test", "expected", "actual", "ok", "ms"])
	for row in rows:
		print("%-52s %-14s %-14s %-6s %d" % [row[0], row[1].left(14), row[2].left(14), "PASS" if row[3] else "FAIL", row[4]])
	print("")
	print("%d checks, %d failures" % [rows.size(), failures])
	quit(0 if failures == 0 else 1)


# -- pool completeness -------------------------------------------------------


func _test_pool_completeness() -> void:
	var ids := HouseRegistry.house_ids()
	check("pool: registry has the nine houses", 9, ids.size())
	var missing := 0
	for hid in ids:
		if not BE.pool_house_ids().has(hid):
			missing += 1
	check("pool: every registry house present", 0, missing)
	check("pool: no orphan houses in json", ids.size(), BE.pool_house_ids().size())

	var short_pairs := 0
	var long_lines := 0
	var dupes := 0
	var bad_tokens := 0
	var total := 0
	for hid in ids:
		var seen := {}
		for beat in BE.BEATS:
			var lines: Array = BE.pool_lines(hid, beat)
			if lines.size() < 8:
				short_pairs += 1
				print("  SHORT POOL: %s/%s has %d lines" % [hid, beat, lines.size()])
			for l in lines:
				total += 1
				var s := str(l)
				if s.replace("{piece}", "bishop").length() > BE.MAX_LINE_CHARS:
					long_lines += 1
					print("  LONG LINE (%d): %s" % [s.length(), s])
				if seen.has(s):
					dupes += 1
					print("  DUP LINE: %s" % s)
				seen[s] = true
				if s.replace("{piece}", "").contains("{"):
					bad_tokens += 1
					print("  BAD TOKEN: %s" % s)
	check("pool: every house x beat has >=8 lines", 0, short_pairs)
	check("pool: all lines <=90 chars substituted", 0, long_lines)
	check("pool: no duplicate lines within a house", 0, dupes)
	check("pool: {piece} is the only token", 0, bad_tokens)
	check("pool: total >= 320 lines", true, total >= 320)
	print("pool: %d canned lines across %d houses x %d beats" % [total, ids.size(), BE.BEATS.size()])


# -- persona prompts ---------------------------------------------------------


func _test_persona_prompts() -> void:
	const RULE_BITS := ["one taunt", "90 characters", "no quotes",
		"medieval diction", "never modern slang", "wit over cruelty"]
	var bad_identity := 0
	var bad_rules := 0
	var prompts := {}
	for hid in HouseRegistry.house_ids():
		var h := HouseRegistry.get_house(hid)
		var p: String = BE.build_system_prompt(hid)
		prompts[hid] = p
		var arch := str(h.get("archetype", ""))
		if not (p.contains(str(h.get("name", ""))) and p.contains(str(h.get("motto", "")))
				and p.contains(arch) and p.contains(str(BE.ARCHETYPE_VOICE.get(arch, "?")))):
			bad_identity += 1
			print("  BAD PERSONA: %s" % hid)
		for bit in RULE_BITS:
			if not p.contains(bit):
				bad_rules += 1
				print("  MISSING RULE '%s' in %s" % [bit, hid])
	check("persona: identity sheet per house", 0, bad_identity)
	check("persona: style rules in every prompt", 0, bad_rules)
	# The spec's voice per archetype, asserted verbatim.
	check("persona: wolf is laconic", true, str(prompts["winterfang"]).contains("laconic"))
	check("persona: lion is debts and gold", true, str(prompts["goldclaw"]).contains("debts and gold"))
	check("persona: kraken is salt and drowning", true, str(prompts["tidegrip"]).contains("salt and drowning"))
	check("persona: dragon is fire and ancestry", true, str(prompts["ashwyrm"]).contains("fire and ancestry"))
	check("persona: stag is storms", true, str(prompts["hartcrown"]).contains("storms"))
	check("persona: rose is courtly venom", true, str(prompts["thornvale"]).contains("courtly venom"))
	check("persona: sun is pride", true, str(prompts["duskfire"]).contains("pride"))
	check("persona: falcon is honor and heights", true, str(prompts["swiftcrest"]).contains("honor and heights"))
	check("persona: trout is rivers and patience", true, str(prompts["silverbrook"]).contains("rivers and patience"))
	check("persona: prompts differ across houses", true,
		str(prompts["winterfang"]) != str(prompts["goldclaw"]))


func _test_beat_prompts() -> void:
	var p: String = BE.build_beat_prompt(BE.BEAT_PLAYER_CAPTURED, {"piece": "bishop"})
	check("prompt: capture names the piece", true, p.contains("bishop"))
	check("prompt: capture asks for gloat", true, p.to_lower().contains("gloat"))
	p = BE.build_beat_prompt(BE.BEAT_PLAYER_BLUNDER, {"eval_swing_cp": 300})
	check("prompt: blunder carries the eval swing", true, p.contains("3.0 pawns"))
	p = BE.build_beat_prompt(BE.BEAT_RIVAL_CAPTURED)
	check("prompt: pieceless capture still works", true, p.contains("one of your pieces"))
	p = BE.build_beat_prompt(BE.BEAT_ENDGAME_LOSE)
	check("prompt: lose concedes in character", true, p.contains("lost"))


# -- sanitize ----------------------------------------------------------------


func _test_sanitize() -> void:
	check("sanitize: strips double quotes", "Bow.", BE.sanitize_line("\"Bow.\""))
	check("sanitize: strips smart quotes", "Bow before the tide.",
		BE.sanitize_line("“Bow before the tide.”"))
	check("sanitize: takes last line and drops label", "The river rises.",
		BE.sanitize_line("Let me think.\nTAUNT: The river rises."))
	check("sanitize: collapses whitespace", "spaced out words",
		BE.sanitize_line("  spaced   out  words  "))
	check("sanitize: empty stays empty", "", BE.sanitize_line("   \n  "))
	var clamped: String = BE.sanitize_line(LONG_REPLY)
	check("sanitize: clamps to 90", true, clamped.length() <= 90 and clamped.length() > 0)
	check("sanitize: clamp ends on a whole word", false, clamped.ends_with(" "))


# -- rate limiter ------------------------------------------------------------


func _test_rate_limiter() -> void:
	var e = BE.new()
	e.llm_enabled = false
	e.house_id = "winterfang"
	e.seed_rng(7)
	var got: Array = []
	var skips: Array = []
	e.banter_line.connect(func(h: String, t: String, b: String) -> void: got.append([h, t, b]))
	e.banter_skipped.connect(func(_b: String, why: String) -> void: skips.append(why))

	check("rate: game_start accepted", true, e.on_beat(BE.BEAT_GAME_START))
	check("rate: pool line emitted synchronously", 1, got.size())
	check("rate: source is pool", "pool", e.last_source)
	check("rate: capture at fullmove 1 blocked", false,
		e.on_beat(BE.BEAT_PLAYER_CAPTURED, {"piece": "pawn"}))
	check("rate: skip reason rate_limited", "rate_limited", skips.back())
	e.note_ply()
	e.note_ply()   # fullmove 2 — gap still 1 < 2
	check("rate: capture at fullmove 2 blocked", false,
		e.on_beat(BE.BEAT_PLAYER_CAPTURED, {"piece": "pawn"}))
	e.note_ply()
	e.note_ply()   # fullmove 3 — gap 2 >= 2
	check("rate: capture at fullmove 3 allowed", true,
		e.on_beat(BE.BEAT_PLAYER_CAPTURED, {"piece": "pawn"}))
	check("rate: second beat same move blocked", false, e.on_beat(BE.BEAT_CHECK_GIVEN))
	check("rate: blunder always allowed", true,
		e.on_beat(BE.BEAT_PLAYER_BLUNDER, {"eval_swing_cp": 250}))
	check("rate: ctx fullmove override respected", true,
		e.on_beat(BE.BEAT_CHECK_GIVEN, {"fullmove": 99}))
	check("rate: endgame beat exempt from gap", true, e.on_beat(BE.BEAT_ENDGAME_LOSE))
	check("rate: undo beat exempt from gap", true, e.on_beat(BE.BEAT_PLAYER_UNDO))
	check("rate: unknown beat refused", false, e.on_beat("intermission"))
	check("rate: six taunts delivered", 6, got.size())
	check("rate: taunt_count tracks", 6, e.taunt_count)
	# The take-back clock rewind: winding the ply clock back can never leave
	# the last-taunt marker in the future (the limiter would deadlock).
	e.rewind_ply_clock(2)   # back to fullmove 2 after taunting at 99
	check("rate: rewound clock allows the next gap-kept beat", true,
		e.on_beat(BE.BEAT_CHECK_GIVEN, {"fullmove": 4}))

	var mute = BE.new()   # no house set -> every beat refused
	mute.llm_enabled = false
	check("rate: houseless engine refuses", false, mute.on_beat(BE.BEAT_GAME_START))
	var wrong = BE.new()
	wrong.llm_enabled = false
	wrong.house_id = "house_atreides"   # not in houses.json
	check("rate: unknown house refused", false, wrong.on_beat(BE.BEAT_GAME_START))
	mute.free()
	wrong.free()
	e.free()


# -- dedupe / exhaustion / reset --------------------------------------------


func _test_dedupe_and_reset() -> void:
	var e = BE.new()
	e.llm_enabled = false
	e.house_id = "goldclaw"
	e.min_fullmove_gap = 0
	e.seed_rng(42)
	var got: Array = []
	var skips: Array = []
	e.banter_line.connect(func(_h: String, t: String, _b: String) -> void: got.append(t))
	e.banter_skipped.connect(func(_b: String, why: String) -> void: skips.append(why))

	for i in 8:
		e.on_beat(BE.BEAT_PLAYER_BLUNDER)
	check("dedupe: 8 blunder lines emitted", 8, got.size())
	var uniq := {}
	for t in got:
		uniq[t] = true
	check("dedupe: all 8 unique", 8, uniq.size())
	var pool: Array = BE.pool_lines("goldclaw", BE.BEAT_PLAYER_BLUNDER)
	var from_pool := 0
	for t in got:
		if pool.has(t):
			from_pool += 1
	check("dedupe: every line from the canned pool", 8, from_pool)
	e.on_beat(BE.BEAT_PLAYER_BLUNDER)   # 9th — pool spent
	check("dedupe: 9th exhausts the pool", "pool_exhausted", skips.back())
	check("dedupe: no 9th line", 8, got.size())

	e.reset_game()
	check("dedupe: reset clears counters", 0, e.taunt_count)
	check("dedupe: pool replenished after reset", true, e.on_beat(BE.BEAT_PLAYER_BLUNDER))
	check("dedupe: line after reset", 9, got.size())

	# {piece} lines only when the context carries a piece.
	var e2 = BE.new()
	e2.llm_enabled = false
	e2.house_id = "goldclaw"
	e2.min_fullmove_gap = 0
	e2.seed_rng(9)
	var got2: Array = []
	var skips2: Array = []
	e2.banter_line.connect(func(_h: String, t: String, _b: String) -> void: got2.append(t))
	e2.banter_skipped.connect(func(_b: String, why: String) -> void: skips2.append(why))
	for i in 8:
		e2.on_beat(BE.BEAT_PLAYER_CAPTURED, {"piece": "bishop"})
	check("token: 8 capture lines with piece ctx", 8, got2.size())
	var residue := 0
	var substituted := 0
	for t in got2:
		if str(t).contains("{piece}"):
			residue += 1
		if str(t).contains("bishop"):
			substituted += 1
	check("token: no {piece} residue", 0, residue)
	check("token: bishop substituted in", true, substituted >= 1)

	var e3 = BE.new()   # no piece in ctx -> token lines ineligible (5 of 8 remain)
	e3.llm_enabled = false
	e3.house_id = "goldclaw"
	e3.min_fullmove_gap = 0
	var got3: Array = []
	var skips3: Array = []
	e3.banter_line.connect(func(_h: String, t: String, _b: String) -> void: got3.append(t))
	e3.banter_skipped.connect(func(_b: String, why: String) -> void: skips3.append(why))
	for i in 6:
		e3.on_beat(BE.BEAT_PLAYER_CAPTURED)
	check("token: pieceless ctx skips token lines", 5, got3.size())
	check("token: pieceless 6th exhausts", "pool_exhausted", skips3.back())
	var braces := 0
	for t in got3:
		if str(t).contains("{"):
			braces += 1
	check("token: pieceless lines carry no braces", 0, braces)
	e.free()
	e2.free()
	e3.free()


# -- fallback: LLM unreachable ----------------------------------------------


func _test_fallback_dead_endpoint() -> void:
	var dead := TCPServer.new()
	dead.listen(0, "127.0.0.1")
	var dead_port := dead.get_local_port()
	dead.stop()
	OS.set_environment(BE.ENV_URL, "http://127.0.0.1:%d" % dead_port)

	var e = _make_engine("DeadOracleBanter")
	e.house_id = "tidegrip"
	e.llm_timeout_s = 2.0
	while not e.is_inside_tree():
		await process_frame
	var got: Array = []
	e.banter_line.connect(func(h: String, t: String, b: String) -> void: got.append([h, t, b]))

	check("fallback: beat accepted", true, e.on_beat(BE.BEAT_CHECK_GIVEN, {"fullmove": 10}))
	check("fallback: does not block (async)", 0, got.size())
	var arrived: bool = await _wait_lines(got, 1, 10000)
	check("fallback: line arrived", true, arrived)
	if arrived:
		check("fallback: source is pool", "pool", e.last_source)
		check("fallback: last_error explains", true, not str(e.last_error).is_empty())
		check("fallback: line from canned pool", true,
			BE.pool_lines("tidegrip", BE.BEAT_CHECK_GIVEN).has(got[0][1]))
		check("fallback: house carried", "tidegrip", got[0][0])
	e.queue_free()


# -- LLM path against the mock server ---------------------------------------


func _test_llm_mock() -> void:
	_server = TCPServer.new()
	var err := _server.listen(0, "127.0.0.1")
	check("llm: mock server listens", "OK", error_string(err))
	if err != OK:
		return
	var port := _server.get_local_port()
	OS.set_environment(BE.ENV_URL, "http://127.0.0.1:%d" % port)
	_mock_running = true
	_pump_mock()

	var e = _make_engine("MockOracleBanter")
	e.house_id = "winterfang"
	e.seed_rng(3)
	while not e.is_inside_tree():
		await process_frame
	var got: Array = []
	e.banter_line.connect(func(h: String, t: String, b: String) -> void: got.append([h, t, b]))

	# 1. clean taunt, quotes stripped, request body correct
	_mock_requests.clear()
	_mock_replies = ["\"The wolf grins at your gate tonight.\""]
	check("llm: beat accepted", true, e.on_beat(BE.BEAT_GAME_START))
	var ok: bool = await _wait_lines(got, 1)
	check("llm: line arrived", true, ok)
	if ok:
		check("llm: source llm", "llm", e.last_source)
		check("llm: quotes stripped", "The wolf grins at your gate tonight.", got[0][1])
		check("llm: house carried", "winterfang", got[0][0])
		check("llm: beat carried", BE.BEAT_GAME_START, got[0][2])
	check("llm: one request", 1, _mock_requests.size())
	if _mock_requests.size() == 1:
		var body: Dictionary = _mock_requests[0]
		check("llm: temperature 0.9", 0.9, body.get("temperature"))
		check("llm: max_tokens 60", 60, int(body.get("max_tokens", 0)))
		var msgs: Array = body.get("messages", [])
		check("llm: system+user messages", 2, msgs.size())
		if msgs.size() == 2:
			var sys := str((msgs[0] as Dictionary).get("content", ""))
			check("llm: system carries the persona", true, sys.contains("Haus Winterfang"))
			check("llm: system carries the voice", true, sys.contains("laconic"))
			check("llm: system carries the rules", true, sys.contains("wit over cruelty"))
			var user := str((msgs[1] as Dictionary).get("content", ""))
			check("llm: user prompt is the beat", true, user.contains("game begins"))

	# 2. over-long reply clamped; blunder prompt carries the swing
	_mock_requests.clear()
	_mock_replies = [LONG_REPLY]
	e.on_beat(BE.BEAT_PLAYER_BLUNDER, {"eval_swing_cp": 300})
	ok = await _wait_lines(got, 2)
	check("llm: long reply arrived", true, ok)
	if ok:
		check("llm: long reply clamped <=90", true, str(got[1][1]).length() <= BE.MAX_LINE_CHARS)
	if _mock_requests.size() == 1:
		var user2 := str(((_mock_requests[0].get("messages", []) as Array).back() as Dictionary).get("content", ""))
		check("llm: blunder prompt carries 3.0 pawns", true, user2.contains("3.0 pawns"))

	# 3. an LLM line repeating itself falls back to the pool (dedupe)
	_mock_replies = ["Winter answers twice.", "Winter answers twice."]
	e.on_beat(BE.BEAT_ENDGAME_WIN)
	ok = await _wait_lines(got, 3)
	check("llm: dupe setup line arrived", true, ok)
	if ok:
		check("llm: dupe setup from llm", "llm", e.last_source)
	e.on_beat(BE.BEAT_ENDGAME_LOSE)
	ok = await _wait_lines(got, 4)
	check("llm: dupe fell back to pool", true,
		ok and e.last_source == "pool" and str(got[3][1]) != "Winter answers twice.")
	if ok:
		check("llm: dupe fallback from the lose pool", true,
			BE.pool_lines("winterfang", BE.BEAT_ENDGAME_LOSE).has(got[3][1]))

	# 4. a second beat while one is in flight is dropped
	_mock_replies = ["The pack waits for no second call."]
	e.on_beat(BE.BEAT_PLAYER_BLUNDER)
	check("llm: overlapping beat dropped", false, e.on_beat(BE.BEAT_ENDGAME_WIN))
	ok = await _wait_lines(got, 5)
	check("llm: in-flight taunt still lands", true, ok)

	_mock_running = false
	_server.stop()
	e.queue_free()


# -- tiny canned HTTP/1.1 server on TCPServer (test_ds4_opponent.gd) ---------


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
	var body_text := raw.slice(header_end, header_end + content_len).get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(body_text)
	_mock_requests.append(parsed if parsed is Dictionary else {})
	var content := "The board is mine."
	if not _mock_replies.is_empty():
		content = _mock_replies.pop_front()
	var response_body := JSON.stringify({
		"id": "chatcmpl-mock",
		"object": "chat.completion",
		"model": "deepseek-v4-flash-mock",
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
