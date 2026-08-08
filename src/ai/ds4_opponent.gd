extends Node
class_name Ds4Opponent
## DS4-ORACLE — MAX-THINKING LLM opponent (DeepSeek-V4-Flash over an
## OpenAI-compatible endpoint, normally the SSH tunnel to the MBP at
## http://127.0.0.1:18000).
##
## Duck-type parity with ChessAI so game.gd can swap them:
##   var move = await opponent.choose_move(state, difficulty)  # ChessMove or null
## (difficulty is accepted and ignored — the Oracle has one gear: MAX.)
## A callback-style wrapper is also provided:
##   opponent.choose_move_async(state, func(move): ...)
##
## Unlike ChessAI (RefCounted), this is a Node: HTTPRequest children need a
## place in the scene tree. The integrator must add_child() it before use.
##
## Prompt / parse / retry design ported from the proven
## ~/Projects/godot-lab/ds4-chess-bridge/ds4_chess_bot.py (our code):
##   FEN + SAN history + explicit legal move list; prefer a final
##   "MOVE: <uci>" line, fall back to the last legal UCI token anywhere in
##   the reply; up to MAX_RETRIES corrective retries on illegal/unparseable
##   output; final fallback = random legal move, flagged via oracle_stumbled.

## Emitted when a move request begins (HUD: show THINKING_TEXT shimmer + timer).
signal thinking_started
## Emitted when the move request ends, however it ended. elapsed_s = wall time.
signal thinking_finished(elapsed_s: float)
## Emitted before each corrective retry request (attempt is 1-based).
signal retry_attempted(attempt: int)
## Emitted when every LLM attempt failed and a RANDOM legal move was played.
## HUD must surface STUMBLE_TEXT when this fires.
signal oracle_stumbled(reason: String)

const DEFAULT_CHAT_URL := "http://127.0.0.1:18000/v1/chat/completions"
const ENV_URL := "DS4_CHESS_URL"      # base URL / v1 URL / full chat URL all accepted
const ENV_MODEL := "DS4_CHESS_MODEL"
const DEFAULT_MODEL := "deepseek-v4-flash"

# MAX THINKING configuration
const TEMPERATURE := 0.3
const MAX_TOKENS := 3072
const MAX_RETRIES := 3          # corrective retries after the first attempt
const MOVE_TIMEOUT_S := 120.0   # hard wall-clock budget per move -> fallback

# UI strings (opponent-select + HUD copy lives here so every screen agrees)
const DISPLAY_NAME := "DS4-Oracle"
const THINKING_TEXT := "The Oracle ponders…"
const STUMBLE_TEXT := "The Oracle stumbles"
const OFFLINE_TEXT := "the Oracle sleeps (tunnel down?)"

## Programmatic endpoint override (lowest precedence is DEFAULT_CHAT_URL,
## then this, then the DS4_CHESS_URL environment variable).
var endpoint_override := ""
## Model id sent to the endpoint. Empty = auto (env DS4_CHESS_MODEL, else
## DEFAULT_MODEL; ping() adopts the first served model when ours is unknown).
var model := ""

# Introspection (read after a call; the test suite asserts on these)
var last_source := ""          # "llm" | "llm-retryN" | "fallback" | ""
var last_reply := ""           # raw text of the last LLM reply
var last_error := ""           # last transport/parse error, "" if none
var last_elapsed_s := 0.0      # wall time of the last choose_move
var available_models: Array[String] = []   # from the last successful ping()
var offline_reason := ""       # OFFLINE_TEXT (+ detail) after a failed ping()

var _move_line_re := RegEx.create_from_string("(?i)MOVE:\\s*`?([a-h][1-8][a-h][1-8][qrbn]?)`?")
var _uci_re := RegEx.create_from_string("\\b([a-h][1-8][a-h][1-8][qrbnQRBN]?)\\b")


# -- endpoint resolution ----------------------------------------------------


static func normalize_chat_url(raw: String) -> String:
	## Accepts "http://host:port", ".../v1" or a full ".../chat/completions".
	var url := raw.strip_edges().rstrip("/")
	if url.ends_with("/chat/completions"):
		return url
	if url.ends_with("/v1"):
		return url + "/chat/completions"
	return url + "/v1/chat/completions"


func chat_url() -> String:
	var env := OS.get_environment(ENV_URL)
	if not env.is_empty():
		return normalize_chat_url(env)
	if not endpoint_override.is_empty():
		return normalize_chat_url(endpoint_override)
	return DEFAULT_CHAT_URL


func models_url() -> String:
	return chat_url().replace("/chat/completions", "/models")


func _resolved_model() -> String:
	if not model.is_empty():
		return model
	var env := OS.get_environment(ENV_MODEL)
	return env if not env.is_empty() else DEFAULT_MODEL


# -- preflight --------------------------------------------------------------


## Connection preflight: GET <base>/v1/models. Returns true when the endpoint
## answers with a model list. On failure, offline_reason carries the UI copy
## ("the Oracle sleeps (tunnel down?)") for the opponent-select screen to
## grey the DS4-Oracle entry out with. Awaitable; never throws.
func ping(timeout_s := 5.0) -> bool:
	offline_reason = ""
	var r := await _http_get(models_url(), timeout_s)
	if r.is_empty():
		offline_reason = "%s — %s" % [OFFLINE_TEXT, last_error]
		return false
	var parsed: Variant = JSON.parse_string(r)
	if not (parsed is Dictionary) or not (parsed.get("data") is Array):
		last_error = "model list malformed"
		offline_reason = "%s — %s" % [OFFLINE_TEXT, last_error]
		return false
	available_models.clear()
	for entry in parsed["data"]:
		if entry is Dictionary and entry.get("id") is String:
			available_models.append(entry["id"])
	# Adopt a served model when ours is unset/unknown (tunnel serves one brain).
	if not available_models.is_empty() and not available_models.has(_resolved_model()):
		model = available_models[0]
	return true


# -- move selection ---------------------------------------------------------


## ChessAI-parity surface: awaitable, returns a ChessMove minted by `state`
## (SAN-notated) or null if the game is already over. `_difficulty` is
## accepted for drop-in swap with ChessAI.choose_move and ignored.
func choose_move(state, _difficulty := 2) -> Variant:
	var legal: Array = state.legal_moves(true)  # SAN-notated, parity with ChessAI output
	if legal.is_empty():
		return null
	var by_uci := {}
	for m in legal:
		by_uci[String(m.to_uci()).to_lower()] = m
	last_source = ""
	last_error = ""
	thinking_started.emit()
	var t0 := Time.get_ticks_msec()
	var messages := _build_messages(state, by_uci.keys())
	var chosen: Variant = null
	for attempt in range(1 + MAX_RETRIES):
		var remaining := MOVE_TIMEOUT_S - float(Time.get_ticks_msec() - t0) / 1000.0
		if remaining <= 1.0:
			last_error = "move budget (%.0fs) exhausted" % MOVE_TIMEOUT_S
			break
		if attempt > 0:
			retry_attempted.emit(attempt)
		var text := await _chat(messages, remaining)
		last_reply = text
		var uci := _extract_uci(text, by_uci)
		if not uci.is_empty():
			last_source = "llm" if attempt == 0 else "llm-retry%d" % attempt
			chosen = by_uci[uci]
			break
		messages.append({"role": "assistant", "content": text if not text.is_empty() else "(no reply)"})
		messages.append({"role": "user", "content":
			"Your previous reply could not be used: it did not contain a legal " +
			"UCI move. You MUST end your reply with exactly one line " +
			"'MOVE: <uci>' choosing verbatim from this legal move list: " +
			", ".join(_sorted_keys(by_uci))})
	if chosen == null:
		# Final fallback: random legal move, loudly flagged.
		last_source = "fallback"
		var keys := _sorted_keys(by_uci)
		chosen = by_uci[keys.pick_random()]
		var reason := "%s — no legal move from the endpoint after %d attempts (%s); played random %s" \
			% [STUMBLE_TEXT, 1 + MAX_RETRIES, last_error if not last_error.is_empty() else "unusable replies", chosen.to_uci()]
		push_warning(reason)
		oracle_stumbled.emit(reason)
	last_elapsed_s = float(Time.get_ticks_msec() - t0) / 1000.0
	thinking_finished.emit(last_elapsed_s)
	return chosen


## Callback-style wrapper: fires the request and calls `callback(move)` when
## done (move is a ChessMove or null). Non-blocking for the caller.
func choose_move_async(state, callback: Callable, difficulty := 2) -> void:
	var move: Variant = await choose_move(state, difficulty)
	if callback.is_valid():
		callback.call(move)


# -- prompt (ported from ds4_chess_bot.py build_move_prompt) ----------------


func _build_messages(state, legal_ucis: Array) -> Array:
	var color_name := "black" if state.turn else "white"
	var sans: Array[String] = []
	for m in state.move_stack:
		sans.append(String(m.notation_san) if m.notation_san != null else m.to_uci())
	var history := "none (starting position)"
	if not sans.is_empty():
		var pairs: Array[String] = []
		for i in range(0, sans.size(), 2):
			var row := "%d. %s" % [i / 2 + 1, sans[i]]
			if i + 1 < sans.size():
				row += " %s" % sans[i + 1]
			pairs.append(row)
		history = " ".join(pairs)
	var legal_sorted := legal_ucis.duplicate()
	legal_sorted.sort()
	var system := (
		"You are the Oracle, a master chess engine playing a live game. " +
		"Think step by step: identify the 3-5 most promising candidate moves " +
		"from the provided legal move list, analyze each briefly (tactics, " +
		"captures, threats, king safety, piece activity), compare them, and " +
		"pick the strongest. THEN end your reply with exactly one final line " +
		"in the format 'MOVE: <uci>' where <uci> is one move taken verbatim " +
		"from the provided legal move list (UCI notation, e.g. e2e4 or " +
		"e7e8q). The MOVE line must be the last line of your reply.")
	var user := (
		"Position (FEN): %s\n" % state.get_fen() +
		"You play: %s. It is your move.\n" % color_name +
		"Moves so far (SAN): %s\n" % history +
		"Legal moves (UCI): %s\n" % ", ".join(legal_sorted) +
		"Analyze the candidates step by step, then reply with the final line:\n" +
		"MOVE: <uci>")
	return [{"role": "system", "content": system}, {"role": "user", "content": user}]


## Pull one legal UCI move out of LLM output. Prefers 'MOVE: xxxx' lines;
## scans matches last-to-first so the final stated move wins. "" if none.
func _extract_uci(text: String, by_uci: Dictionary) -> String:
	if text.is_empty():
		return ""
	for rx in [_move_line_re, _uci_re]:
		var matches := (rx as RegEx).search_all(text)
		for i in range(matches.size() - 1, -1, -1):
			var tok: String = matches[i].get_string(1).to_lower()
			if by_uci.has(tok):
				return tok
	return ""


func _sorted_keys(d: Dictionary) -> Array:
	var keys := d.keys()
	keys.sort()
	return keys


# -- transport --------------------------------------------------------------


func _chat(messages: Array, timeout_s: float) -> String:
	var body := JSON.stringify({
		"model": _resolved_model(),
		"messages": messages,
		"temperature": TEMPERATURE,
		"max_tokens": MAX_TOKENS,
	})
	var raw := await _http_request(chat_url(), HTTPClient.METHOD_POST, body, timeout_s)
	if raw.is_empty():
		return ""
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		last_error = "response is not JSON"
		return ""
	var choices: Variant = parsed.get("choices")
	if not (choices is Array) or (choices as Array).is_empty() \
			or not ((choices as Array)[0] is Dictionary):
		last_error = "response has no choices"
		return ""
	var msg: Variant = ((choices as Array)[0] as Dictionary).get("message")
	if not (msg is Dictionary):
		last_error = "choice has no message"
		return ""
	var content := String(msg.get("content") if msg.get("content") != null else "")
	# Reasoning-capable servers may put the text in reasoning_content.
	var extra := String(msg.get("reasoning_content")
		if msg.get("reasoning_content") != null else
		(msg.get("reasoning") if msg.get("reasoning") != null else ""))
	return (content + "\n" + extra).strip_edges()


func _http_get(url: String, timeout_s: float) -> String:
	return await _http_request(url, HTTPClient.METHOD_GET, "", timeout_s)


## One HTTP round-trip via a throwaway HTTPRequest child. Returns the body as
## a UTF-8 string, or "" on any failure (last_error explains). Requires this
## node to be inside the scene tree.
func _http_request(url: String, method: int, body: String, timeout_s: float) -> String:
	if not is_inside_tree():
		last_error = "Ds4Opponent must be add_child()ed before use (HTTPRequest needs the tree)"
		push_error(last_error)
		return ""
	var http := HTTPRequest.new()
	http.timeout = clampf(timeout_s, 1.0, MOVE_TIMEOUT_S)
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var err := http.request(url, headers, method, body)
	if err != OK:
		last_error = "request() failed: %s" % error_string(err)
		http.queue_free()
		return ""
	var r: Array = await http.request_completed
	http.queue_free()
	var result: int = r[0]
	var code: int = r[1]
	var bytes: PackedByteArray = r[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		last_error = "transport error %d on %s" % [result, url] \
			+ (" (timeout)" if result == HTTPRequest.RESULT_TIMEOUT else "")
		return ""
	if code != 200:
		last_error = "HTTP %d on %s" % [code, url]
		return ""
	return bytes.get_string_from_utf8()
