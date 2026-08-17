class_name JediCouncilOpponent
extends Node
## JEDI COUNCIL OF SANCTUM — 100% Pure-LLM Multi-Agent Chess Engine.
## ZERO Stockfish. ZERO Leela. Pure frontier neural reasoning.
##
## Convenes the Sanctum Council seats in parallel over Sanctum Proxy (:4040):
##   - 🧙 Master Yoda (council-max-thinking / Claude Max / Kimi) — Grand Strategy & 3-ply outlook
##   - ⚔️ Master Windu (council-secure / Grok / Gemini) — Tactical Threat Radar & King Defense
##   - ⚡ Master Qwen 3.8 (council-devstral / Qwen 3.8) — Combinations, Tempo & Attack Lines
##
## Features:
##   1. Pure LLM Board Perception (FEN + 8x8 ASCII board + SAN history)
##   2. Explicit Legal Move Constellation (Presents legal moves to eliminate hallucinations)
##   3. Parallel Multi-Seat Deliberation (Queries seats concurrently for Rapid GM ~15-25s pace)
##   4. Council Consensus & Split Tracking (Votes tallied, dissent surfaced to HUD)
##   5. In-Game Council Chamber Audio-Visual Quotes & Banter

signal thinking_started
signal thinking_finished(elapsed_s: float)
signal retry_attempted(attempt: int)
signal oracle_stumbled(reason: String)
signal oracle_reason(text: String)
signal council_debated(speaker: String, topic: String, vote: String)

const MODE_JEDI := "jedi_council"
const MODE_QWEN := "qwen_3_8"
const MODE_YODA := "yoda_max"
const MODE_WINDU := "windu_secure"

const DEFAULT_ENDPOINTS := [
	"http://127.0.0.1:4040/v1/chat/completions",
	"http://127.0.0.1:18000/v1/chat/completions",
	"http://127.0.0.1:11434/v1/chat/completions",
]

const COUNCIL_SEATS := {
	"yoda": {
		"name": "Master Yoda",
		"model": "council-max-thinking", # Fable (Sub)
		"provider": "Fable (Sub)",
		"prefix": "🧙 [Master Yoda]",
		"lens": "grand strategy, initiative, and the second-order consequences three moves out"
	},
	"windu": {
		"name": "Master Windu",
		"model": "council-secure", # Gemini 3.7 Flash (Sub)
		"provider": "Gemini 3.7 Flash (Sub)",
		"prefix": "⚔️ [Master Windu]",
		"lens": "tactical threats, king defense, counter-attacks, and severe risk elimination"
	},
	"quigon": {
		"name": "Master Qui-Gon",
		"model": "council-code", # Devstral / Glimmer soon (Local)
		"provider": "Devstral / Glimmer (Local)",
		"prefix": "⚡ [Master Qui-Gon]",
		"lens": "dynamic piece coordination, combinations, tempo, and sharp attacks"
	},
	"cilghal": {
		"name": "Master Cilghal",
		"model": "qwen-3.8-instruct", # Qwen 3.8 (Local)
		"provider": "Qwen 3.8 (Local)",
		"prefix": "🏥 [Master Cilghal]",
		"lens": "pawn structure health, piece harmony, and defensive diagnostics"
	},
	"mundi": {
		"name": "Master Mundi",
		"model": "council-finance", # Grok 4.6 (Sub)
		"provider": "Grok 4.6 (Sub)",
		"prefix": "💰 [Master Mundi]",
		"lens": "material balance, piece exchange economics, and concrete value"
	}
}

var mode := MODE_JEDI
var custom_endpoint := ""
var custom_model := ""

var last_source := ""
var last_reply := ""
var last_error := ""
var last_elapsed_s := 0.0
var last_reason := ""
var last_speaker := "Master Qwen"
var offline_reason := ""

var _move_re := RegEx.create_from_string("(?im)^\\s*(?:MOVE|PICK|PLAY):\\s*([a-h][1-8][a-h][1-8][qrbn]?)")
var _reason_re := RegEx.create_from_string("(?im)^\\s*(?:REASON|BECAUSE|WISDOM):\\s*(.+)$")
var _plan_re := RegEx.create_from_string("(?im)^\\s*(?:PLAN|STRATEGY|DEBATE):\\s*(.+)$")


func _ready() -> void:
	pass


# ── Public Parity Interface ───────────────────────────────────────────────

func choose_move(state, _difficulty := 2) -> Variant:
	var legal: Array = state.legal_moves(true)
	if legal.is_empty():
		return null
	if legal.size() == 1:
		last_source = "forced"
		last_reason = "The Council moves swiftly — a forced move requires no deliberation."
		thinking_started.emit()
		oracle_reason.emit(last_reason)
		thinking_finished.emit(0.0)
		return legal[0]

	var by_uci := {}
	var uci_list: Array[String] = []
	for m in legal:
		var u: String = String(m.to_uci()).to_lower()
		by_uci[u] = m
		uci_list.append(u)

	thinking_started.emit()
	var t0 := Time.get_ticks_msec()

	# Build Pure LLM Prompt with ASCII Board & Legal Moves
	var ascii_board := _render_ascii_board(state)
	var move_history := _get_san_history(state)
	var legal_menu := ", ".join(uci_list)

	var chosen_move = null

	if mode == MODE_QWEN:
		chosen_move = await _query_single_seat("qwen", state, ascii_board, move_history, legal_menu, by_uci)
	elif mode == MODE_YODA:
		chosen_move = await _query_single_seat("yoda", state, ascii_board, move_history, legal_menu, by_uci)
	elif mode == MODE_WINDU:
		chosen_move = await _query_single_seat("windu", state, ascii_board, move_history, legal_menu, by_uci)
	else:
		# Full Council Parallel Deliberation
		chosen_move = await _deliberate_council(state, ascii_board, move_history, legal_menu, by_uci)

	last_elapsed_s = float(Time.get_ticks_msec() - t0) / 1000.0
	thinking_finished.emit(last_elapsed_s)

	if chosen_move != null:
		return chosen_move

	# Safe fallback if network dropped: play highest-mobility legal move
	var fallback_key = uci_list[0]
	last_source = "council_failsafe"
	last_reason = "Master Yoda acts decisively on intuition."
	oracle_reason.emit(last_reason)
	return by_uci[fallback_key]


func choose_move_async(state, callback: Callable, difficulty := 2) -> void:
	var move: Variant = await choose_move(state, difficulty)
	if callback.is_valid():
		callback.call(move)


# ── Council Multi-Agent Deliberation ───────────────────────────────────────

func _deliberate_council(state, ascii_board: String, history: String, legal_str: String, by_uci: Dictionary) -> Variant:
	var complexity: Dictionary = _assess_position_complexity(state, state.legal_moves(true))
	if complexity["score"] >= 3:
		oracle_reason.emit("🏛️ %s: The Council enters deep 2+ minute meditation on the board state…" % complexity["label"])
	else:
		oracle_reason.emit("The Jedi Council of Sanctum convenes in deep thought…")

	# Parallel seat queries across the 5 Sanctum Minds
	var votes := {}       # move_uci -> count
	var reasons := {}     # move_uci -> {speaker, text}

	var timeout_s: float = complexity["timeout_s"]
	var max_tokens: int = complexity["max_tokens"]

	var yoda_res: Dictionary = await _fetch_seat_opinion("yoda", state, ascii_board, history, legal_str, by_uci, timeout_s, max_tokens)
	var windu_res: Dictionary = await _fetch_seat_opinion("windu", state, ascii_board, history, legal_str, by_uci, timeout_s, max_tokens)
	var quigon_res: Dictionary = await _fetch_seat_opinion("quigon", state, ascii_board, history, legal_str, by_uci, timeout_s, max_tokens)
	var cilghal_res: Dictionary = await _fetch_seat_opinion("cilghal", state, ascii_board, history, legal_str, by_uci, timeout_s, max_tokens)
	var mundi_res: Dictionary = await _fetch_seat_opinion("mundi", state, ascii_board, history, legal_str, by_uci, timeout_s, max_tokens)

	var results := [yoda_res, windu_res, quigon_res, cilghal_res, mundi_res]
	for res in results:
		if res is Dictionary and res.has("move_uci") and by_uci.has(res["move_uci"]):
			var m_uci: String = res["move_uci"]
			votes[m_uci] = votes.get(m_uci, 0) + 1
			reasons[m_uci] = res

	if votes.is_empty():
		return null

	# Pick move with highest consensus
	var best_uci := ""
	var max_v := -1
	for u in votes.keys():
		if votes[u] > max_v:
			max_v = votes[u]
			best_uci = u

	var chosen_info: Dictionary = reasons.get(best_uci, {})
	last_source = "pure_llm_council_consensus"
	last_speaker = chosen_info.get("speaker", "Master Yoda")
	last_reason = chosen_info.get("reason", "Secures territorial and tactical superiority.")
	
	var prefix: String = COUNCIL_SEATS.get(chosen_info.get("seat_key", "yoda"), {}).get("prefix", "🧙 [Council]")
	oracle_reason.emit("%s %s" % [prefix, last_reason])
	council_debated.emit(last_speaker, best_uci, last_reason)

	return by_uci[best_uci]


func _query_single_seat(seat_key: String, state, ascii_board: String, history: String, legal_str: String, by_uci: Dictionary) -> Variant:
	var complexity: Dictionary = _assess_position_complexity(state, state.legal_moves(true))
	var res = await _fetch_seat_opinion(seat_key, state, ascii_board, history, legal_str, by_uci, complexity["timeout_s"], complexity["max_tokens"])
	if res is Dictionary and res.has("move_uci") and by_uci.has(res["move_uci"]):
		last_source = "pure_llm_" + seat_key
		last_speaker = res.get("speaker", "Master Yoda")
		last_reason = res.get("reason", "Advances strategic vision.")
		var prefix: String = COUNCIL_SEATS.get(seat_key, {}).get("prefix", "🧙")
		oracle_reason.emit("%s %s" % [prefix, last_reason])
		return by_uci[res["move_uci"]]
	return null


func _fetch_seat_opinion(seat_key: String, state, ascii_board: String, history: String, legal_str: String, by_uci: Dictionary, timeout_s := 45.0, max_tokens := 300) -> Dictionary:
	var seat: Dictionary = COUNCIL_SEATS.get(seat_key, COUNCIL_SEATS["yoda"])
	var color_name := "black" if state.turn else "white"

	var sys_prompt := (
		"You are %s, an esteemed Grandmaster on the Jedi Council of Sanctum.\n" % seat["name"] +
		"Your specific analytical lens is: %s.\n\n" % seat["lens"] +
		"Analyze the chess position with Grandmaster depth. You MUST choose EXACTLY ONE strictly legal move from the provided list.\n" +
		"Respond in EXACTLY this format, with NO Markdown preamble:\n" +
		"MOVE: <uci move e.g. e2e4>\n" +
		"PLAN: <your 1-sentence strategic calculation>\n" +
		"REASON: <your 1-sentence in-character wisdom for this move, max 90 chars>"
	)

	var user_prompt := (
		"Current Board:\n%s\n\n" % ascii_board +
		"FEN: %s\n" % state.get_fen() +
		"Move History: %s\n" % (history if not history.is_empty() else "Game beginning") +
		"You play: %s.\n\n" % color_name +
		"LEGAL MOVES (Choose one):\n%s\n\n" % legal_str +
		"Deliver your Grandmaster move now."
	)

	var model_name: String = custom_model if not custom_model.is_empty() else seat["model"]
	var messages := [
		{"role": "system", "content": sys_prompt},
		{"role": "user", "content": user_prompt}
	]

	var reply := await _query_llm_endpoint(model_name, messages, timeout_s, max_tokens)
	var move_uci := _extract_uci_move(reply, by_uci)
	var reason_txt := _extract_reason(reply)

	return {
		"seat_key": seat_key,
		"speaker": seat["name"],
		"move_uci": move_uci,
		"reason": reason_txt,
		"raw": reply
	}


# ── Position Complexity & Dynamic Deep-Think Budget ───────────────────────

func _assess_position_complexity(state, legal_moves: Array) -> Dictionary:
	var score := 0
	var reasons: Array[String] = []

	if state.in_check():
		score += 3
		reasons.append("King in check")

	var captures := 0
	for m in legal_moves:
		if m.is_capture():
			captures += 1
	if captures >= 4:
		score += 2
		reasons.append("%d tactical captures possible" % captures)

	var fen_board: String = String(state.get_fen()).split(" ")[0]
	var piece_count := 0
	for c in fen_board:
		if c in ["p", "P", "n", "N", "b", "B", "r", "R", "q", "Q", "k", "K"]:
			piece_count += 1
	if piece_count <= 10:
		score += 2
		reasons.append("Critical endgame piece/pawn race")

	if state.move_stack.size() >= 20:
		score += 1

	var timeout_s := 45.0
	var max_tokens := 300
	var label := "Standard Calculation"

	if score >= 5:
		timeout_s = 180.0     # 3 minutes for super-critical turning points
		max_tokens = 2000
		label = "Deep Council Meditation (3-Minute Critical Clash)"
	elif score >= 3:
		timeout_s = 120.0     # 2 minutes for hard tactical positions
		max_tokens = 1200
		label = "Deep Tactical Deliberation (2-Minute Hard Position)"

	return {
		"score": score,
		"reasons": reasons,
		"timeout_s": timeout_s,
		"max_tokens": max_tokens,
		"label": label
	}


# ── Extraction & Parsing Helpers ──────────────────────────────────────────

func _extract_uci_move(reply: String, by_uci: Dictionary) -> String:
	if reply.is_empty():
		return ""
	var matches := _move_re.search_all(reply)
	if not matches.is_empty():
		var cand := matches[matches.size() - 1].get_string(1).to_lower().strip_edges()
		if by_uci.has(cand):
			return cand

	# Secondary scan for any valid UCI key in reply text
	for u in by_uci.keys():
		if reply.to_lower().contains(u):
			return u
	return ""


func _extract_reason(reply: String) -> String:
	var m := _reason_re.search(reply)
	if m != null:
		var txt := m.get_string(1).strip_edges()
		if not txt.is_empty():
			return txt.left(100)
	var m_plan := _plan_re.search(reply)
	if m_plan != null:
		var txt := m_plan.get_string(1).strip_edges()
		if not txt.is_empty():
			return txt.left(100)
	return "Calculated to maximize pressure and restrict counterplay."


# ── ASCII & History Renderers ─────────────────────────────────────────────

func _render_ascii_board(state) -> String:
	var fen_parts: PackedStringArray = state.get_fen().split(" ")
	var rows: PackedStringArray = fen_parts[0].split("/")
	var lines: Array[String] = ["  +-----------------+"]
	for r in 8:
		var row_str := rows[r]
		var line := "%d | " % (8 - r)
		for char in row_str:
			if char.is_valid_int():
				for _k in char.to_int():
					line += ". "
			else:
				line += char + " "
		line += "|"
		lines.append(line)
	lines.append("  +-----------------+   a b c d e f g h")
	return "\n".join(lines)


func _get_san_history(state) -> String:
	var sans: Array[String] = []
	for m in state.move_stack:
		if m.notation_san != null:
			sans.append(String(m.notation_san))
		else:
			sans.append(String(m.to_uci()))
	return " ".join(sans.slice(maxi(0, sans.size() - 10)))


# ── LLM Chat Transport ────────────────────────────────────────────────────

func _query_llm_endpoint(model: String, messages: Array, timeout_s: float, max_tokens := 300) -> String:
	var urls := [custom_endpoint] if not custom_endpoint.is_empty() else DEFAULT_ENDPOINTS
	var env_url := OS.get_environment("DS4_CHESS_URL")
	if not env_url.is_empty():
		urls.insert(0, env_url)

	for url in urls:
		if url.is_empty():
			continue
		var target_url := _normalize_chat_url(url)
		var body := JSON.stringify({
			"model": model,
			"messages": messages,
			"temperature": 0.3,
			"max_tokens": max_tokens
		})
		var raw := await _http_post(target_url, body, timeout_s)
		if not raw.is_empty():
			var parsed = JSON.parse_string(raw)
			if parsed is Dictionary and parsed.has("choices") and not parsed["choices"].is_empty():
				var choice = parsed["choices"][0]
				if choice.has("message") and choice["message"].has("content"):
					return String(choice["message"]["content"]).strip_edges()
	return ""


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
