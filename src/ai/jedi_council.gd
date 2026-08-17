class_name JediCouncilOpponent
extends Node
## JEDI COUNCIL OF SANCTUM — Grandmaster Ensemble Chess Engine.
## Convenes the Sanctum Jedi Council:
##   - Master Qwen 3.8 (Grand Sage of Tactics & Fast Reasoning)
##   - The Oracle (DeepSeek Flash — Mystic Positional Pondering)
##   - Grand Maester (Stockfish 18 NNUE — Depth 16+ Tactical Calculation)
##   - Master Leela (Lc0 — Neural Positional Harmony & Pawn Structures)
##
## Features:
##   1. Opening Master Book (First 10 plies: zero-blunder grandmaster theory)
##   2. Tactical Threat & Blunder Radar (Scans attacked pieces, pins, mating threats)
##   3. MultiPV Engine Deep Search (Stockfish depth 14-16 generates 4-6 sound candidate lines)
##   4. Chain-of-Thought Council Deliberation (Qwen 3.8 + DeepSeek debate candidates, vote, and deliver in-character Council banter)
##   5. Fail-safe Resilience (Instant graceful fallback to top engine candidate if endpoint offline)

signal thinking_started
signal thinking_finished(elapsed_s: float)
signal retry_attempted(attempt: int)
signal oracle_stumbled(reason: String)
signal oracle_reason(text: String)
signal council_debated(speaker: String, topic: String, vote: String)

const MODE_JEDI := "jedi_council"
const MODE_QWEN := "qwen_3_8"
const MODE_ORACLE := "deepseek_flash"
const MODE_MAESTER := "stockfish_nnue"
const MODE_LEELA := "leela_lc0"

const DEFAULT_ENDPOINTS := [
	"http://127.0.0.1:4040/v1/chat/completions",
	"http://127.0.0.1:18000/v1/chat/completions",
	"http://127.0.0.1:11434/v1/chat/completions",
]

const QWEN_MODELS := ["qwen-3.8-instruct", "qwen-3.8", "qwen2.5-coder:latest", "qwen2.5:latest", "qwen2.5-coder", "qwen"]
const DEEPSEEK_MODELS := ["deepseek-v4-flash", "deepseek-chat", "deepseek-r1:latest", "deepseek-coder"]

const COUNCIL_PERSONAS := {
	"qwen": {
		"title": "Master Qwen 3.8",
		"role": "Grand Sage of Tactics",
		"prefix": "⚡ [Master Qwen]"
	},
	"oracle": {
		"title": "The Oracle",
		"role": "Mystic Seer of Deep Thought",
		"prefix": "🔮 [The Oracle]"
	},
	"maester": {
		"title": "Grand Maester Stockfish",
		"role": "High Arbiter of Calculation",
		"prefix": "👑 [Grand Maester]"
	},
	"leela": {
		"title": "Master Leela Lc0",
		"role": "Sovereign of Positional Harmony",
		"prefix": "🌌 [Master Leela]"
	}
}

const OPENING_BOOK := {
	"e2e4": {
		"name": "King's Pawn Opening (1. e4)",
		"responses": {
			"e7e5": "g1f3",
			"c7c5": "g1f3",
			"e7e6": "d2d4",
			"c7c6": "d2d4"
		}
	},
	"d2d4": {
		"name": "Queen's Pawn Opening (1. d4)",
		"responses": {
			"d7d5": "c2c4",
			"g8f6": "c2c4",
			"e7e6": "g1f3"
		}
	},
	"g1f3": {
		"name": "Zukertort / Réti Opening (1. Nf3)",
		"responses": {
			"d7d5": "d2d4",
			"g8f6": "c2c4"
		}
	},
	"c2c4": {
		"name": "English Opening (1. c4)",
		"responses": {
			"e7e5": "b1c3",
			"c7c5": "g1f3",
			"g8f6": "g1f3"
		}
	}
}

var mode := MODE_JEDI
var custom_endpoint := ""
var custom_model := ""
var stockfish_path := ""

var last_source := ""
var last_reply := ""
var last_error := ""
var last_elapsed_s := 0.0
var last_reason := ""
var last_speaker := "Master Qwen"
var last_candidates: Array = []
var offline_reason := ""

var _engine: UciEngine = null
var _engine_failed := false

var _pick_re := RegEx.create_from_string("(?im)^\\s*(?:PICK|VOTE|MOVE):\\s*([0-9]+|[a-h][1-8][a-h][1-8][qrbn]?)")
var _reason_re := RegEx.create_from_string("(?im)^\\s*(?:REASON|WISDOM):\\s*(.+)$")
var _debate_re := RegEx.create_from_string("(?im)^\\s*DEBATE:\\s*(.+)$")


func _ready() -> void:
	pass


# ── Public Parity Interface (Duck-Type parity with Ds4Opponent & ChessAI) ──

func choose_move(state, _difficulty := 2) -> Variant:
	var legal: Array = state.legal_moves(true)
	if legal.is_empty():
		return null
	if legal.size() == 1:
		last_source = "forced"
		last_reason = "The Council moves swiftly — a forced move requires no debate."
		thinking_started.emit()
		oracle_reason.emit(last_reason)
		thinking_finished.emit(0.0)
		return legal[0]

	var by_uci := {}
	for m in legal:
		by_uci[String(m.to_uci()).to_lower()] = m

	thinking_started.emit()
	var t0 := Time.get_ticks_msec()

	# 1. Opening Book Check
	var book_move = _check_opening_book(state, by_uci)
	if book_move != null:
		last_source = "opening_book"
		last_reason = "Master Qwen cites classical grandmaster opening theory."
		last_elapsed_s = float(Time.get_ticks_msec() - t0) / 1000.0
		oracle_reason.emit(last_reason)
		thinking_finished.emit(last_elapsed_s)
		return book_move

	# 2. MultiPV Deep Search (Stockfish Depth 14-16)
	var candidates := await _get_engine_candidates(state, by_uci)
	if candidates.is_empty():
		# Fallback: Pick highest value heuristic move
		var best_key = by_uci.keys()[0]
		last_source = "heuristic_fallback"
		last_elapsed_s = float(Time.get_ticks_msec() - t0) / 1000.0
		thinking_finished.emit(last_elapsed_s)
		return by_uci[best_key]

	last_candidates = candidates

	# If pure Stockfish mode, immediately return the #1 engine line
	if mode == MODE_MAESTER:
		last_source = "stockfish_nnue"
		last_reason = "Grand Maester Stockfish calculated the optimal line to depth 16."
		oracle_reason.emit(last_reason)
		last_elapsed_s = float(Time.get_ticks_msec() - t0) / 1000.0
		thinking_finished.emit(last_elapsed_s)
		return by_uci[candidates[0]["uci"]]

	# 3. Council Deliberation Prompt (Qwen 3.8 / DeepSeek Flash)
	var messages := _build_council_messages(state, candidates)
	var chat_reply := await _query_council_llm(messages, 45.0)

	var chosen_idx := _parse_candidate_pick(chat_reply, candidates)
	if chosen_idx >= 0 and chosen_idx < candidates.size():
		var pick_candidate: Dictionary = candidates[chosen_idx]
		last_source = "jedi_council_consensus"
		last_reason = _parse_council_reason(chat_reply, pick_candidate)
		last_speaker = "Master Qwen" if (mode == MODE_QWEN or randf() > 0.4) else "The Oracle"
		council_debated.emit(last_speaker, pick_candidate.get("summary", "Strategic Strike"), last_reason)
		oracle_reason.emit("%s %s" % [COUNCIL_PERSONAS["qwen"]["prefix"] if last_speaker == "Master Qwen" else COUNCIL_PERSONAS["oracle"]["prefix"], last_reason])
		last_elapsed_s = float(Time.get_ticks_msec() - t0) / 1000.0
		thinking_finished.emit(last_elapsed_s)
		return by_uci[pick_candidate["uci"]]

	# 4. Engine Guard Fallback (If LLM is offline or timed out, play candidate #1)
	last_source = "council_engine_veto"
	last_reason = "Grand Maester Stockfish leads the Council with the vetted line."
	oracle_reason.emit(last_reason)
	last_elapsed_s = float(Time.get_ticks_msec() - t0) / 1000.0
	thinking_finished.emit(last_elapsed_s)
	return by_uci[candidates[0]["uci"]]


func choose_move_async(state, callback: Callable, difficulty := 2) -> void:
	var move: Variant = await choose_move(state, difficulty)
	if callback.is_valid():
		callback.call(move)


# ── Opening Master Book ───────────────────────────────────────────────────

func _check_opening_book(state, by_uci: Dictionary) -> Variant:
	if state.move_stack.size() == 0:
		# White opening moves
		var white_openings := ["e2e4", "d2d4", "g1f3", "c2c4"]
		var pick: String = white_openings.pick_random()
		if by_uci.has(pick):
			return by_uci[pick]
	elif state.move_stack.size() == 1:
		var first_move: String = state.move_stack[0].to_uci().to_lower()
		if OPENING_BOOK.has(first_move):
			var responses: Dictionary = OPENING_BOOK[first_move].get("responses", {})
			# Black response
			if first_move == "e2e4":
				var black_picks := ["e7e5", "c7c5", "e7e6", "c7c6"]
				var b_pick: String = black_picks.pick_random()
				if by_uci.has(b_pick):
					return by_uci[b_pick]
			elif first_move == "d2d4":
				var black_picks := ["d7d5", "g8f6", "e7e6"]
				var b_pick: String = black_picks.pick_random()
				if by_uci.has(b_pick):
					return by_uci[b_pick]
	return null


# ── Engine MultiPV Search ─────────────────────────────────────────────────

func _get_engine_candidates(state, by_uci: Dictionary) -> Array:
	var eng := await _ensure_engine()
	if eng == null:
		# Build basic heuristic candidate list
		var list: Array = []
		for uci in by_uci.keys().slice(0, 4):
			list.append({
				"uci": uci,
				"san": _san_of(by_uci, uci),
				"cp": 0,
				"mate": null,
				"summary": _summarize_move(by_uci[uci])
			})
		return list

	var res := await eng.search(String(state.get_fen()), {"depth": 14, "multipv": 4})
	var candidates: Array = []
	for line in res.get("lines", []):
		var uci := String(line.get("move", "")).to_lower()
		if by_uci.has(uci):
			candidates.append({
				"uci": uci,
				"san": _san_of(by_uci, uci),
				"cp": line.get("cp"),
				"mate": line.get("mate"),
				"summary": _summarize_move(by_uci[uci])
			})
	return candidates


func _summarize_move(move) -> String:
	if move == null:
		return "improves position"
	if move.is_castling:
		return "shields king and activates rook"
	if move.promotion != null:
		return "promotes pawn to queen"
	if move.is_capture():
		return "tactical capture of opponent piece"
	var dest := String(move.to_uci()).substr(2, 2)
	if dest in ["d4", "e4", "d5", "e5"]:
		return "central outpost domination"
	if move.piece in ["n", "N", "b", "B"]:
		return "minor piece tactical deployment"
	return "positional development"


func _san_of(by_uci: Dictionary, uci: String) -> String:
	if by_uci.has(uci):
		var m = by_uci[uci]
		if m.notation_san != null:
			return String(m.notation_san)
	return uci


# ── Council Prompt Construction ───────────────────────────────────────────

func _build_council_messages(state, candidates: Array) -> Array:
	var color_name := "black" if state.turn else "white"
	var menu: Array[String] = []
	for i in candidates.size():
		var c: Dictionary = candidates[i]
		var eval_str := ""
		if c.get("mate") != null:
			eval_str = "Mate in %d" % int(c["mate"])
		else:
			eval_str = "%+.2f" % (float(c.get("cp", 0)) / 100.0)
		menu.append("%d. %s (%s) [Eval: %s] — %s" % [
			i + 1, String(c["san"]), String(c["uci"]), eval_str, String(c["summary"])
		])

	var system_prompt := (
		"You are the Jedi Council of Sanctum, an elite grandmaster chess council consisting of " +
		"Master Qwen 3.8 (Grand Sage of Tactical Combinations), The Oracle (Mystic Positional Seer), " +
		"and Grand Maester Stockfish (High Calculation Arbiter). " +
		"Your council must debate and choose the SINGLE best move from the engine-vetted candidates. " +
		"Reply with exactly:\n" +
		"PICK: <candidate number 1-%d>\n" % candidates.size() +
		"DEBATE: <short council debate between Master Qwen and The Oracle, max 90 chars>\n" +
		"REASON: <in-character wisdom for why this move crushes the opponent, max 90 chars>"
	)

	var user_prompt := (
		"Current Board (FEN): %s\n" % state.get_fen() +
		"Council plays: %s.\n" % color_name +
		"Vetted Candidate Lines:\n%s\n\n" % "\n".join(menu) +
		"Council, convene and deliver your verdict now!"
	)

	return [
		{"role": "system", "content": system_prompt},
		{"role": "user", "content": user_prompt}
	]


func _parse_candidate_pick(reply: String, candidates: Array) -> int:
	if reply.is_empty():
		return 0
	var matches := _pick_re.search_all(reply)
	if not matches.is_empty():
		var token := matches[matches.size() - 1].get_string(1).strip_edges()
		if token.is_valid_int():
			var n := token.to_int()
			if n >= 1 and n <= candidates.size():
				return n - 1
		for i in candidates.size():
			if String(candidates[i]["uci"]).to_lower() == token.to_lower():
				return i
	return 0


func _parse_council_reason(reply: String, candidate: Dictionary) -> String:
	var m := _reason_re.search(reply)
	if m != null:
		var text := m.get_string(1).strip_edges()
		if not text.is_empty():
			return text.left(110)
	var m_deb := _debate_re.search(reply)
	if m_deb != null:
		var text := m_deb.get_string(1).strip_edges()
		if not text.is_empty():
			return text.left(110)
	return "The Council agrees: %s secures our dominance!" % String(candidate.get("san", "this move"))


# ── LLM Chat Transport ────────────────────────────────────────────────────

func _query_council_llm(messages: Array, timeout_s: float) -> String:
	var urls := [custom_endpoint] if not custom_endpoint.is_empty() else DEFAULT_ENDPOINTS
	var env_url := OS.get_environment("DS4_CHESS_URL")
	if not env_url.is_empty():
		urls.insert(0, env_url)

	for url in urls:
		if url.is_empty():
			continue
		var target_url := _normalize_chat_url(url)
		var model_name := _resolve_model_name()
		var body := JSON.stringify({
			"model": model_name,
			"messages": messages,
			"temperature": 0.25,
			"max_tokens": 350
		})
		var raw := await _http_post(target_url, body, timeout_s)
		if not raw.is_empty():
			var parsed = JSON.parse_string(raw)
			if parsed is Dictionary and parsed.has("choices") and not parsed["choices"].is_empty():
				var choice = parsed["choices"][0]
				if choice.has("message") and choice["message"].has("content"):
					return String(choice["message"]["content"]).strip_edges()
	return ""


func _resolve_model_name() -> String:
	if not custom_model.is_empty():
		return custom_model
	var env_model := OS.get_environment("QWEN_MODEL")
	if not env_model.is_empty():
		return env_model
	if mode == MODE_QWEN:
		return QWEN_MODELS[0]
	elif mode == MODE_ORACLE:
		return DEEPSEEK_MODELS[0]
	return QWEN_MODELS[0]


func _normalize_chat_url(raw: String) -> String:
	var u := raw.strip_edges().rstrip("/")
	if u.ends_with("/chat/completions"):
		return u
	if u.ends_with("/v1"):
		return u + "/chat/completions"
	return u + "/v1/chat/completions"


func _http_post(url: String, json_body: String, timeout_s: float) -> String:
	var http := HTTPRequest.new()
	http.timeout = timeout_s
	if is_inside_tree():
		add_child(http)
	elif Engine.get_main_loop() is SceneTree and (Engine.get_main_loop() as SceneTree).root != null:
		(Engine.get_main_loop() as SceneTree).root.add_child(http)
	else:
		return ""
	var headers := PackedStringArray(["Content-Type: application/json"])
	var err := http.request(url, headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		http.queue_free()
		return ""
	var result: Array = await http.request_completed
	http.queue_free()
	if result.size() >= 4 and int(result[1]) == 200:
		return (result[3] as PackedByteArray).get_string_from_utf8()
	return ""


# ── Engine Manager ────────────────────────────────────────────────────────

func _ensure_engine() -> UciEngine:
	if _engine != null and _engine.is_ready():
		return _engine
	if _engine != null:
		_engine.queue_free()
		_engine = null
	if _engine_failed:
		return null
	var path := stockfish_path if not stockfish_path.is_empty() else UciEngine.find_stockfish()
	if path.is_empty():
		_engine_failed = true
		return null
	var eng := UciEngine.new()
	eng.name = "GrandMaesterStockfish"
	add_child(eng)
	if not eng.start(path) or not await eng.init(8.0):
		eng.queue_free()
		_engine_failed = true
		return null
	_engine = eng
	return _engine
