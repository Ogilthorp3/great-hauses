class_name JediCouncilOpponent
extends Node
## JEDI COUNCIL OF SANCTUM — 100% Pure-LLM Multi-Agent Chess Engine.
## ZERO Stockfish. ZERO Leela. Pure frontier neural reasoning.
##
## Powered by Multi-Agent Debate (MAD) & Extended Chain-of-Thought (CoT):
##   - Phase 1 (Propose): 🧙 Master Yoda (Grand Strategy) & ⚡ Master Qui-Gon (Tactics) propose candidates in parallel.
##   - Phase 2 (Critique): ⚔️ Master Windu (Tactical Inquisitor) red-teams the proposals for hanging pieces and counter-traps.
##   - Phase 3 (Synthesize): 🧙 Master Yoda (Chief Grandmaster) evaluates the debate and executes the verified winning move.
##
## Features:
##   1. Pure LLM Board Perception (FEN + 8x8 ASCII board + SAN history)
##   2. Semantic Legal Move Annotations (Translates UCI moves into checks, captures, center control, developments)
##   3. Inverted CoT Prompting (Forces threat analysis, candidate calculations & blunder scan BEFORE the move token)
##   4. 3-Phase Multi-Agent Debate (MAD) Architecture with live HUD debate broadcasts

signal thinking_started
signal thinking_finished(elapsed_s: float)
signal retry_attempted(attempt: int)
signal oracle_stumbled(reason: String)
signal oracle_reason(text: String)
signal council_debated(speaker: String, topic: String, vote: String)

const THINKING_TEXT := "The Jedi Council ponders…"
const FORCED_TEXT := "The Council moves swiftly — a forced move requires no deliberation."

const MODE_JEDI := "jedi_council"
const MODE_QWEN := "qwen_3_8"
const MODE_YODA := "yoda_max"
const MODE_WINDU := "windu_secure"

const DEFAULT_ENDPOINTS := [
	"https://127.0.0.1:4040/v1/chat/completions",
	"http://127.0.0.1:4040/v1/chat/completions",
	"http://127.0.0.1:18000/v1/chat/completions",
	"http://127.0.0.1:11434/v1/chat/completions",
]

const COUNCIL_SEATS := {
	"yoda": {
		"name": "Master Yoda",
		"model": "council-max-thinking", # Fable / Kimi / Claude Max (Sub)
		"provider": "Fable (Sub)",
		"prefix": "🧙 [Master Yoda]",
		"lens": "grand strategy, pawn structure, initiative, and 3-ply positional outlook"
	},
	"windu": {
		"name": "Master Windu",
		"model": "council-secure", # Gemini 3.7 Flash / Grok (Sub)
		"provider": "Gemini 3.7 Flash (Sub)",
		"prefix": "⚔️ [Master Windu]",
		"lens": "tactical threat radar, king defense, hanging pieces, and counter-attack elimination"
	},
	"quigon": {
		"name": "Master Qui-Gon",
		"model": "council-code", # Devstral / Glimmer (Local/Sub)
		"provider": "Devstral / Glimmer (Local)",
		"prefix": "⚡ [Master Qui-Gon]",
		"lens": "dynamic piece coordination, combinations, sacrifices, tempo, and sharp attacks"
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
var last_speaker := "Master Yoda"
var offline_reason := ""

var _move_re := RegEx.create_from_string("(?im)^\\s*(?:MOVE|PICK|PLAY|PREFERRED|RECOMMENDED):\\s*([a-h][1-8][a-h][1-8][qrbn]?)")
var _reason_re := RegEx.create_from_string("(?im)^\\s*(?:REASON|BECAUSE|WISDOM):\\s*(.+)$")
var _plan_re := RegEx.create_from_string("(?im)^\\s*(?:PLAN|STRATEGY|DEBATE|SYNTHESIS):\\s*(.+)$")
var _critique_re := RegEx.create_from_string("(?im)^\\s*(?:CRITIQUE|BLUNDER_WARNING|WARNING):\\s*(.+)$")


func _ready() -> void:
	pass


# ── Preflight & Public Parity Interface ────────────────────────────────────

## Connection preflight: probes Sanctum Proxy endpoints. Returns true when reachable.
## On failure, offline_reason carries the UI reason to disable the Jedi Council in HouseSelect.
func ping(timeout_s := 3.0) -> bool:
	offline_reason = ""
	var urls: Array[String] = []
	if not custom_endpoint.is_empty():
		urls.append(custom_endpoint)
	else:
		var env_url := OS.get_environment("DS4_CHESS_URL")
		if not env_url.is_empty():
			urls.append(env_url)
		for u in DEFAULT_ENDPOINTS:
			urls.append(u)

	for url in urls:
		if url.is_empty():
			continue
		var health_url: String = _to_health_url(url)
		var raw := await _http_get(health_url, timeout_s)
		if not raw.is_empty():
			var parsed = JSON.parse_string(raw)
			if parsed is Dictionary and (parsed.get("status") == "healthy" or parsed.has("providers") or parsed.has("seats")):
				_log_council("[PREFLIGHT] Jedi Council probe SUCCESS at %s" % health_url)
				return true
		# Secondary probe: check /v1/models
		var models_url: String = _to_models_url(url)
		var r_mod := await _http_get(models_url, timeout_s)
		if not r_mod.is_empty():
			var parsed_m = JSON.parse_string(r_mod)
			if parsed_m is Dictionary and (parsed_m.has("data") or parsed_m.has("choices")):
				_log_council("[PREFLIGHT] Jedi Council probe SUCCESS at %s" % models_url)
				return true

	offline_reason = "the Council sits in Sanctum (proxy unreachable)"
	_log_council("[PREFLIGHT] Jedi Council probe FAILED — %s" % offline_reason)
	return false


func _to_health_url(raw: String) -> String:
	var clean := raw.strip_edges().rstrip("/")
	for suffix in ["/v1/chat/completions", "/chat/completions", "/v1", "/models"]:
		if clean.ends_with(suffix):
			clean = clean.left(clean.length() - suffix.length())
			break
	return clean + "/health"


func _to_models_url(raw: String) -> String:
	var clean := raw.strip_edges().rstrip("/")
	for suffix in ["/v1/chat/completions", "/chat/completions", "/v1/health", "/health"]:
		if clean.ends_with(suffix):
			clean = clean.left(clean.length() - suffix.length())
			break
	return clean + "/v1/models"


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

	# Build rich board perception with ASCII board & semantic move annotations
	var ascii_board := _render_ascii_board(state)
	var move_history := _get_san_history(state)
	var legal_menu := _annotate_legal_moves(state, legal)

	var chosen_move = null

	if mode == MODE_QWEN:
		chosen_move = await _query_single_seat("quigon", state, ascii_board, move_history, legal_menu, by_uci)
	elif mode == MODE_YODA:
		chosen_move = await _query_single_seat("yoda", state, ascii_board, move_history, legal_menu, by_uci)
	elif mode == MODE_WINDU:
		chosen_move = await _query_single_seat("windu", state, ascii_board, move_history, legal_menu, by_uci)
	else:
		# Full 3-Phase Council Multi-Agent Deliberation
		chosen_move = await _deliberate_council(state, ascii_board, move_history, legal_menu, by_uci)

	last_elapsed_s = float(Time.get_ticks_msec() - t0) / 1000.0
	thinking_finished.emit(last_elapsed_s)

	if chosen_move != null:
		return chosen_move

	# When the Council is unreachable, DO NOT fall back to blind moves or ChessAI.
	# Fail honestly and loudly.
	last_source = "council_unreachable"
	last_reason = "The Jedi Council of Sanctum has lost connection to the Force."
	_log_council("[OFFLINE] Council deliberation failed — no fallback move returned.")
	oracle_stumbled.emit("The Jedi Council of Sanctum is unreachable.")
	return null


func choose_move_async(state, callback: Callable, difficulty := 2) -> void:
	var move: Variant = await choose_move(state, difficulty)
	if callback.is_valid():
		callback.call(move)


# ── 3-Phase Council Multi-Agent Debate (MAD) ───────────────────────────────

func _deliberate_council(state, ascii_board: String, history: String, legal_str: String, by_uci: Dictionary) -> Variant:
	var complexity: Dictionary = _assess_position_complexity(state, state.legal_moves(true))
	var timeout_s: float = complexity["timeout_s"]
	var max_tokens: int = complexity["max_tokens"]

	_log_council("=== COUNCIL DEBATE START === FEN: %s" % state.get_fen())

	if complexity["score"] >= 3:
		oracle_reason.emit("🏛️ %s: The Council enters deep meditation on the board state…" % complexity["label"])
	else:
		oracle_reason.emit("🏛️ The Jedi Council of Sanctum convenes to debate candidate lines…")

	# ── Phase 1: Candidate Proposals (Yoda & Qui-Gon) ──
	var yoda_prop: Dictionary = await _propose_candidate("yoda", state, ascii_board, history, legal_str, by_uci, timeout_s, max_tokens)
	var quigon_prop: Dictionary = await _propose_candidate("quigon", state, ascii_board, history, legal_str, by_uci, timeout_s, max_tokens)

	var proposals: Array[Dictionary] = []
	if not yoda_prop.is_empty() and yoda_prop.has("preferred_uci") and by_uci.has(yoda_prop["preferred_uci"]):
		proposals.append(yoda_prop)
		_log_council("🧙 [Yoda Proposal] %s: \"%s\"" % [yoda_prop["preferred_uci"], yoda_prop.get("reason", "")])
		oracle_reason.emit("🧙 [Master Yoda] Proposes %s: \"%s\"" % [yoda_prop["preferred_uci"], yoda_prop.get("reason", "A strategic advance.")])
		council_debated.emit("Master Yoda", yoda_prop["preferred_uci"], yoda_prop.get("reason", ""))

	if not quigon_prop.is_empty() and quigon_prop.has("preferred_uci") and by_uci.has(quigon_prop["preferred_uci"]):
		proposals.append(quigon_prop)
		_log_council("⚡ [Qui-Gon Proposal] %s: \"%s\"" % [quigon_prop["preferred_uci"], quigon_prop.get("reason", "")])
		oracle_reason.emit("⚡ [Master Qui-Gon] Proposes %s: \"%s\"" % [quigon_prop["preferred_uci"], quigon_prop.get("reason", "A dynamic tactical line.")])
		council_debated.emit("Master Qui-Gon", quigon_prop["preferred_uci"], quigon_prop.get("reason", ""))

	if proposals.is_empty():
		# If both parallel queries failed, fallback to single seat
		_log_council("⚠️ Phase 1 proposals empty — falling back to single seat query")
		return await _query_single_seat("yoda", state, ascii_board, history, legal_str, by_uci)

	# ── Phase 2: Adversarial Red-Team Critique (Master Windu) ──
	oracle_reason.emit("⚔️ [Master Windu] Stress-testing proposed candidate moves for tactical flaws…")
	var windu_critique: Dictionary = await _critique_candidates(proposals, state, ascii_board, history, legal_str, by_uci, timeout_s, max_tokens)
	if not windu_critique.is_empty():
		var windu_txt: String = windu_critique.get("wisdom", windu_critique.get("reason", "The defense is vigilant."))
		_log_council("⚔️ [Windu Critique] Rec: %s | Warning: \"%s\"" % [windu_critique.get("recommended_uci", ""), windu_txt])
		oracle_reason.emit("⚔️ [Master Windu] %s" % windu_txt)
		council_debated.emit("Master Windu", windu_critique.get("recommended_uci", ""), windu_txt)

	# ── Phase 3: Grandmaster Synthesis (Master Yoda) ──
	oracle_reason.emit("🧙 [Master Yoda] Synthesizing council arguments and rendering verdict…")
	var final_verdict: Dictionary = await _synthesize_verdict(proposals, windu_critique, state, ascii_board, history, legal_str, by_uci, timeout_s, max_tokens)

	var chosen_uci: String = ""
	if final_verdict.has("move_uci") and by_uci.has(final_verdict["move_uci"]):
		chosen_uci = final_verdict["move_uci"]
		last_speaker = "Master Yoda"
		last_reason = final_verdict.get("reason", "The Council executes the chosen harmony.")
	elif windu_critique.has("recommended_uci") and by_uci.has(windu_critique["recommended_uci"]):
		chosen_uci = windu_critique["recommended_uci"]
		last_speaker = "Master Windu"
		last_reason = windu_critique.get("wisdom", "Tactical necessity dictates this move.")
	elif not proposals.is_empty():
		chosen_uci = proposals[0].get("preferred_uci", "")
		last_speaker = proposals[0].get("speaker", "Master Yoda")
		last_reason = proposals[0].get("reason", "Advances territorial control.")

	if by_uci.has(chosen_uci):
		last_source = "pure_llm_council_debate"
		_log_council("🏆 [Verdict] Chosen: %s by %s | \"%s\"" % [chosen_uci, last_speaker, last_reason])
		oracle_reason.emit("🧙 [Council Verdict] %s: %s" % [chosen_uci, last_reason])
		council_debated.emit(last_speaker, chosen_uci, last_reason)
		return by_uci[chosen_uci]

	return null


# ── Council Multi-Agent Roles ──────────────────────────────────────────────

func _propose_candidate(seat_key: String, state, ascii_board: String, history: String, legal_str: String, by_uci: Dictionary, timeout_s: float, max_tokens: int) -> Dictionary:
	var seat: Dictionary = COUNCIL_SEATS.get(seat_key, COUNCIL_SEATS["yoda"])
	var color_name := "black" if state.turn else "white"

	var sys_prompt := (
		"You are %s, an esteemed Grandmaster on the Jedi Council of Sanctum.\n" % seat["name"] +
		"Your analytical lens is: %s.\n\n" % seat["lens"] +
		"Analyze the chess position with Grandmaster depth. You MUST propose promising candidate moves strictly from the legal list.\n" +
		"Follow this structured thinking process:\n" +
		"1. Identify the opponent's threats, active pieces, and King safety.\n" +
		"2. Select your top 2 candidate moves.\n" +
		"3. Formulate your strategic plan and in-character wisdom (max 90 chars).\n\n" +
		"Respond in this EXACT format:\n" +
		"ASSESSMENT: <your analysis of the position>\n" +
		"CANDIDATES:\n" +
		"1. MOVE: <uci> | PLAN: <why this move is strong>\n" +
		"2. MOVE: <uci> | PLAN: <alternative candidate>\n" +
		"PREFERRED: <best uci move e.g. e2e4>\n" +
		"REASON: <1-sentence in-character wisdom for this move, max 90 chars>"
	)

	var user_prompt := (
		"Current Board:\n%s\n\n" % ascii_board +
		"FEN: %s\n" % state.get_fen() +
		"Move History: %s\n" % (history if not history.is_empty() else "Game beginning") +
		"You play: %s.\n\n" % color_name +
		"LEGAL MOVES:\n%s\n\n" % legal_str +
		"Propose your candidate moves now."
	)

	var model_name: String = custom_model if not custom_model.is_empty() else seat["model"]
	var messages := [
		{"role": "system", "content": sys_prompt},
		{"role": "user", "content": user_prompt}
	]

	var reply := await _query_llm_endpoint(model_name, messages, timeout_s, max_tokens)
	var pref_uci := _extract_uci_move(reply, by_uci)
	var reason_txt := _extract_reason(reply)

	return {
		"seat_key": seat_key,
		"speaker": seat["name"],
		"preferred_uci": pref_uci,
		"reason": reason_txt,
		"raw": reply
	}


func _critique_candidates(proposals: Array[Dictionary], state, ascii_board: String, history: String, legal_str: String, by_uci: Dictionary, timeout_s: float, max_tokens: int) -> Dictionary:
	var seat: Dictionary = COUNCIL_SEATS["windu"]
	var color_name := "black" if state.turn else "white"

	var prop_summary: Array[String] = []
	for p in proposals:
		prop_summary.append("• %s proposed %s: \"%s\"" % [p.get("speaker", "Master"), p.get("preferred_uci", "unknown"), p.get("reason", "")])

	var sys_prompt := (
		"You are Master Mace Windu, the Tactical Inquisitor and Guardian of the Jedi Council.\n" +
		"Your duty is to RUTHLESSLY CRITIQUE and RED-TEAM candidate moves proposed by fellow Council members.\n\n" +
		"CRITIQUE GUIDELINES:\n" +
		"1. For each proposed move, calculate the opponent's most forcing counter-attacks (checks, captures, pins, forks).\n" +
		"2. Check if the proposed move hangs any piece or weakens King safety.\n" +
		"3. Identify which candidate is tactically sound vs which is a tactical blunder.\n" +
		"4. Recommend the single safest, most lethal tactical move.\n\n" +
		"Respond in this EXACT format:\n" +
		"CRITIQUE: <your tactical refutations and counter-calculation for each candidate>\n" +
		"BLUNDER_WARNING: <specific warnings on hanging pieces, or 'No tactical blunders detected'>\n" +
		"RECOMMENDED: <best legal uci move>\n" +
		"WISDOM: <1-sentence in-character Windu warning or battle assessment, max 90 chars>"
	)

	var user_prompt := (
		"Proposed Moves under Review:\n%s\n\n" % "\n".join(prop_summary) +
		"Current Board:\n%s\n\n" % ascii_board +
		"FEN: %s\n" % state.get_fen() +
		"Move History: %s\n" % (history if not history.is_empty() else "Game beginning") +
		"You play: %s.\n\n" % color_name +
		"LEGAL MOVES:\n%s\n\n" % legal_str +
		"Deliver your tactical red-team critique now."
	)

	var model_name: String = custom_model if not custom_model.is_empty() else seat["model"]
	var messages := [
		{"role": "system", "content": sys_prompt},
		{"role": "user", "content": user_prompt}
	]

	var reply := await _query_llm_endpoint(model_name, messages, timeout_s, max_tokens)
	var rec_uci := _extract_uci_move(reply, by_uci)
	var wisdom_txt := _extract_reason(reply)

	return {
		"seat_key": "windu",
		"speaker": "Master Windu",
		"recommended_uci": rec_uci,
		"wisdom": wisdom_txt,
		"raw": reply
	}


func _synthesize_verdict(proposals: Array[Dictionary], critique: Dictionary, state, ascii_board: String, history: String, legal_str: String, by_uci: Dictionary, timeout_s: float, max_tokens: int) -> Dictionary:
	var seat: Dictionary = COUNCIL_SEATS["yoda"]
	var color_name := "black" if state.turn else "white"

	var debate_log: Array[String] = []
	for p in proposals:
		debate_log.append("• %s Proposal: %s (\"%s\")" % [p.get("speaker", "Master"), p.get("preferred_uci", ""), p.get("reason", "")])
	if not critique.is_empty():
		debate_log.append("• Master Windu Critique: Recommended %s (\"%s\")" % [critique.get("recommended_uci", ""), critique.get("wisdom", "")])

	var sys_prompt := (
		"You are Master Yoda, Grand Master of the Jedi Council of Sanctum.\n" +
		"You hold the final, binding judgment for the Council.\n\n" +
		"SYNTHESIS INSTRUCTIONS:\n" +
		"1. Review the proposed candidates and Master Windu's tactical red-team critique.\n" +
		"2. Reject any candidate that walks into opponent counter-strikes or hangs material.\n" +
		"3. Balance grand strategy, piece activity, and King defense to select the single best move.\n\n" +
		"Respond in this EXACT format (with the MOVE token on the LAST line):\n" +
		"SYNTHESIS: <your final calculation balancing strategic harmony and tactical defense>\n" +
		"PLAN: <1-sentence strategic direction>\n" +
		"REASON: <1-sentence in-character Yoda wisdom, max 90 chars>\n" +
		"MOVE: <uci move e.g. e2e4>"
	)

	var user_prompt := (
		"Council Deliberation Summary:\n%s\n\n" % "\n".join(debate_log) +
		"Current Board:\n%s\n\n" % ascii_board +
		"FEN: %s\n" % state.get_fen() +
		"Move History: %s\n" % (history if not history.is_empty() else "Game beginning") +
		"You play: %s.\n\n" % color_name +
		"LEGAL MOVES:\n%s\n\n" % legal_str +
		"Deliver the Council's final move now."
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
		"seat_key": "yoda",
		"speaker": "Master Yoda",
		"move_uci": move_uci,
		"reason": reason_txt,
		"raw": reply
	}


func _query_single_seat(seat_key: String, state, ascii_board: String, history: String, legal_str: String, by_uci: Dictionary) -> Variant:
	var complexity: Dictionary = _assess_position_complexity(state, state.legal_moves(true))
	var seat: Dictionary = COUNCIL_SEATS.get(seat_key, COUNCIL_SEATS["yoda"])
	var color_name := "black" if state.turn else "white"

	var sys_prompt := (
		"You are %s, an esteemed Grandmaster on the Jedi Council of Sanctum.\n" % seat["name"] +
		"Your analytical lens is: %s.\n\n" % seat["lens"] +
		"Analyze the chess position step-by-step BEFORE choosing your move:\n" +
		"1. Identify opponent threats and King safety.\n" +
		"2. Calculate 2 candidate moves.\n" +
		"3. Verify that your chosen move does not hang pieces or walk into mate.\n\n" +
		"Respond in this EXACT format (with the MOVE token on the LAST line):\n" +
		"ASSESSMENT: <your step-by-step tactical calculation>\n" +
		"PLAN: <1-sentence strategic direction>\n" +
		"REASON: <1-sentence in-character wisdom for this move, max 90 chars>\n" +
		"MOVE: <uci move e.g. e2e4>"
	)

	var user_prompt := (
		"Current Board:\n%s\n\n" % ascii_board +
		"FEN: %s\n" % state.get_fen() +
		"Move History: %s\n" % (history if not history.is_empty() else "Game beginning") +
		"You play: %s.\n\n" % color_name +
		"LEGAL MOVES:\n%s\n\n" % legal_str +
		"Deliver your Grandmaster move now."
	)

	var model_name: String = custom_model if not custom_model.is_empty() else seat["model"]
	var messages := [
		{"role": "system", "content": sys_prompt},
		{"role": "user", "content": user_prompt}
	]

	var reply := await _query_llm_endpoint(model_name, messages, complexity["timeout_s"], complexity["max_tokens"])
	var move_uci := _extract_uci_move(reply, by_uci)
	var reason_txt := _extract_reason(reply)

	if by_uci.has(move_uci):
		last_source = "pure_llm_" + seat_key
		last_speaker = seat["name"]
		last_reason = reason_txt
		var prefix: String = seat.get("prefix", "🧙")
		oracle_reason.emit("%s %s" % [prefix, last_reason])
		council_debated.emit(last_speaker, move_uci, last_reason)
		return by_uci[move_uci]
	return null


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

	var timeout_s := 35.0
	var max_tokens := 1200
	var label := "Standard Council Deliberation (~15-25s)"

	if score >= 5:
		timeout_s = 60.0     # Deep meditation for critical turning points
		max_tokens = 3000
		label = "Deep Council Meditation (~30s Critical Clash)"
	elif score >= 3:
		timeout_s = 45.0
		max_tokens = 2000
		label = "Deep Tactical Deliberation (~20-25s Tension)"

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
		# Take the LAST match in the text (which corresponds to the final MOVE: after thinking)
		for i in range(matches.size() - 1, -1, -1):
			var cand := matches[i].get_string(1).to_lower().strip_edges()
			if by_uci.has(cand):
				return cand

	# Secondary scan for any valid UCI key in reply text (from end to start)
	var lines := reply.split("\n")
	for i in range(lines.size() - 1, -1, -1):
		var line := lines[i].to_lower()
		for u in by_uci.keys():
			if line.contains(u):
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
	var m_crit := _critique_re.search(reply)
	if m_crit != null:
		var txt := m_crit.get_string(1).strip_edges()
		if not txt.is_empty():
			return txt.left(100)
	return "Calculated to maximize pressure and restrict counterplay."


# ── Semantic Legal Move Annotator ──────────────────────────────────────────

func _annotate_legal_moves(state, legal_moves: Array) -> String:
	var lines: Array[String] = []
	for m in legal_moves:
		var uci: String = String(m.to_uci()).to_lower()
		var desc := _describe_move_tactically(state, m)
		lines.append("• %s (%s)" % [uci, desc])
	return "\n".join(lines)


func _describe_move_tactically(_state, m) -> String:
	var piece_name: String = _piece_name(m.piece)
	var from_sq: String = ChessMove.square_name(m.from_square)
	var to_sq: String = ChessMove.square_name(m.to_square)

	if m.is_castling:
		return "Castles Kingside (O-O)" if m.castle_kingside else "Castles Queenside (O-O-O)"

	var details: Array[String] = []
	if m.is_capture():
		var victim: String = _piece_name(str(m.captured_piece)) if m.captured_piece != null else "Pawn"
		details.append("Captures %s on %s" % [victim, to_sq])
	else:
		details.append("Move %s %s->%s" % [piece_name, from_sq, to_sq])

	if m.promotion != null:
		details.append("Promotes to %s" % _piece_name(str(m.promotion)))

	# Check for central control
	if to_sq in ["d4", "e4", "d5", "e5"]:
		details.append("Controls Center %s" % to_sq)

	# Check if SAN notation has '+' (check) or '#' (mate)
	if m.notation_san != null:
		var s: String = String(m.notation_san)
		if s.ends_with("#"):
			details.append("CHECKMATE")
		elif s.ends_with("+"):
			details.append("GIVES CHECK")

	return ", ".join(details)


func _piece_name(p: String) -> String:
	match p.to_upper():
		"P": return "Pawn"
		"N": return "Knight"
		"B": return "Bishop"
		"R": return "Rook"
		"Q": return "Queen"
		"K": return "King"
		_: return "Piece"


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

func _query_llm_endpoint(model: String, messages: Array, timeout_s: float, max_tokens := 1200) -> String:
	var urls: Array[String] = []
	if not custom_endpoint.is_empty():
		urls.append(custom_endpoint)
	else:
		var env_url := OS.get_environment("DS4_CHESS_URL")
		if not env_url.is_empty():
			urls.append(env_url)
		for u in DEFAULT_ENDPOINTS:
			urls.append(u)

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
				if choice.has("message") and choice["message"] is Dictionary:
					var msg: Dictionary = choice["message"]
					var content := String(msg.get("content", "") if msg.get("content") != null else "")
					var reasoning := String(msg.get("reasoning_content", "") if msg.get("reasoning_content") != null else (msg.get("reasoning", "") if msg.get("reasoning") != null else ""))
					var combined := (reasoning + "\n" + content).strip_edges()
					if not combined.is_empty():
						return combined
					return content.strip_edges()
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
	http.set_tls_options(TLSOptions.client_unsafe())
	if is_inside_tree():
		add_child(http)
	elif Engine.get_main_loop() is SceneTree and (Engine.get_main_loop() as SceneTree).root != null:
		(Engine.get_main_loop() as SceneTree).root.add_child(http)
	else:
		return ""
	var headers := PackedStringArray(["Content-Type: application/json"])
	var err := http.request(url, headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		_log_council("[HTTP ERR] request() failed with %d for %s" % [err, url])
		http.queue_free()
		return ""
	var result: Array = await http.request_completed
	http.queue_free()
	if result.size() >= 4:
		var code: int = int(result[1])
		if code == 200:
			return (result[3] as PackedByteArray).get_string_from_utf8()
		else:
			var err_body := (result[3] as PackedByteArray).get_string_from_utf8().left(200)
			_log_council("[HTTP %d] on %s: %s" % [code, url, err_body])
	return ""


func _http_get(url: String, timeout_s: float) -> String:
	var http := HTTPRequest.new()
	http.timeout = timeout_s
	http.set_tls_options(TLSOptions.client_unsafe())
	if is_inside_tree():
		add_child(http)
	elif Engine.get_main_loop() is SceneTree and (Engine.get_main_loop() as SceneTree).root != null:
		(Engine.get_main_loop() as SceneTree).root.add_child(http)
	else:
		return ""
	var err := http.request(url, PackedStringArray(), HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		return ""
	var result: Array = await http.request_completed
	http.queue_free()
	if result.size() >= 4 and int(result[1]) == 200:
		return (result[3] as PackedByteArray).get_string_from_utf8()
	return ""


func _log_council(text: String) -> void:
	var line := "[%s] %s" % [Time.get_time_string_from_system(), text]
	print(line)
	var fa := FileAccess.open("user://council_debate.log", FileAccess.READ_WRITE if FileAccess.file_exists("user://council_debate.log") else FileAccess.WRITE)
	if fa != null:
		fa.seek_end()
		fa.store_line(line)
		fa.close()



