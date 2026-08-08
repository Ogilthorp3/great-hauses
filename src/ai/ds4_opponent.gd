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
##   "MOVE: <uci>" line, fall back to the last legal move token anywhere in
##   the reply (UCI or SAN, tolerant of x/+/#/! capture-and-check noise —
##   see _extract_uci); up to MAX_RETRIES corrective retries on
##   illegal/unparseable output; final fallback = random legal move,
##   flagged via oracle_stumbled.
##
## Three selectable modes (`mode`), all sharing the surface above:
##   pure       the historic behavior — the LLM alone, MAX thinking.
##   counseled  the LLM proposes; Stockfish (UciEngine, depth 12) reviews the
##              proposal against its own best. A proposal losing more than
##              COUNSEL_CP_THRESHOLD cp triggers a reconsideration prompt
##              (up to MAX_RECONSIDERATIONS); exhausted counsel plays
##              Stockfish's 3rd-ranked move — the quiet save — flagged via
##              oracle_stumbled with the softer HEEDS_TEXT line.
##   maester    Stockfish MultiPV 4 (depth 14) builds four candidates with
##              evals + one-line summaries; the LLM picks one and gives a
##              short in-character reason (oracle_reason signal). Unreachable
##              LLM (MAESTER_TIMEOUT_S budget) -> Stockfish's top move, reason
##              MAESTER_SLEEP_REASON. Always strong.
## Stockfish autodetects via UciEngine.find_stockfish(); when missing,
## counseled/maester degrade to pure (logged) — the UI additionally greys
## the maester entry out via HouseSelect.set_oracle_mode_enabled.

## Emitted when a move request begins (HUD: show THINKING_TEXT shimmer + timer).
signal thinking_started
## Emitted when the move request ends, however it ended. elapsed_s = wall time.
signal thinking_finished(elapsed_s: float)
## Emitted before each corrective retry request (attempt is 1-based).
signal retry_attempted(attempt: int)
## Emitted when every LLM attempt failed and a RANDOM legal move was played.
## HUD must surface STUMBLE_TEXT when this fires — except counseled saves,
## whose reason carries HEEDS_TEXT and gets the softer HUD line.
signal oracle_stumbled(reason: String)
## Maester mode: the Oracle's short in-character reason for its pick.
## HUD shows it as a caption under the move list for ~6 s.
signal oracle_reason(text: String)

const DEFAULT_CHAT_URL := "http://127.0.0.1:18000/v1/chat/completions"
const ENV_URL := "DS4_CHESS_URL"      # base URL / v1 URL / full chat URL all accepted
const ENV_MODEL := "DS4_CHESS_MODEL"
const DEFAULT_MODEL := "deepseek-v4-flash"

# MAX THINKING configuration
const TEMPERATURE := 0.3
const MAX_RETRIES := 3          # corrective retries after the first attempt
const MOVE_TIMEOUT_S := 120.0   # hard wall-clock budget per move -> fallback

# Adaptive thinking budget — the model fills whatever max_tokens it is
# given, so trivial positions must not get the full 3072-token pondering
# budget (2026-08-08 latency scar: every pure move took ~2 min flat).
# Scaled by branching factor; corrective retries escalate one tier so a
# truncated small-budget reply cannot spiral into the random fallback.
const TOKENS_FEW := 512         # <= FEW_MOVES_MAX legal moves
const TOKENS_SOME := 1024       # <= SOME_MOVES_MAX legal moves
const TOKENS_FULL := 3072       # open positions — MAX thinking
const FEW_MOVES_MAX := 5
const SOME_MOVES_MAX := 15
const TOKENS_MAESTER_PICK := 300   # maester picks among 4 vetted candidates —
								   # it chooses, it does not analyze raw
const TOKENS_RECONSIDER := 768     # counseled reconsideration rounds

# Advisor (Stockfish) configuration
const MODE_PURE := "pure"
const MODE_COUNSELED := "counseled"
const MODE_MAESTER := "maester"
const COUNSEL_DEPTH := 12       # counseled: review depth for proposal vs best
const COUNSEL_CP_THRESHOLD := 150.0   # cp loss vs best that triggers counsel
const MAX_RECONSIDERATIONS := 2       # counseled: extra chances after the first proposal
const MAESTER_DEPTH := 14       # maester: MultiPV candidate depth
const MAESTER_MULTIPV := 4
const MAESTER_TIMEOUT_S := 90.0 # maester: LLM pick budget before the engine moves
								# (90 s, not the drafted 30: the live DeepSeek
								# max-thinking brain spends ~60 s reasoning even
								# on a two-line pick — measured 2026-08-08)
const MAX_REASON_CHARS := 100

# UI strings (opponent-select + HUD copy lives here so every screen agrees)
const DISPLAY_NAME := "DS4-Oracle"
const THINKING_TEXT := "The Oracle ponders…"
const STUMBLE_TEXT := "The Oracle stumbles"
const OFFLINE_TEXT := "the Oracle sleeps (tunnel down?)"
const HEEDS_TEXT := "The Oracle heeds counsel"
const MAESTER_SLEEP_REASON := "The Maester moves for the sleeping Oracle."
const FORCED_TEXT := "The Oracle need not ponder."
const MODE_LABELS := {
	MODE_PURE: "Pure Oracle",
	MODE_COUNSELED: "Counseled Oracle",
	MODE_MAESTER: "Oracle + Grand Maester",
}

## Programmatic endpoint override (lowest precedence is DEFAULT_CHAT_URL,
## then this, then the DS4_CHESS_URL environment variable).
var endpoint_override := ""
## Model id sent to the endpoint. Empty = auto (env DS4_CHESS_MODEL, else
## DEFAULT_MODEL; ping() adopts the first served model when ours is unknown).
var model := ""
## Oracle mode: MODE_PURE | MODE_COUNSELED | MODE_MAESTER.
var mode := MODE_PURE
## Explicit stockfish path; "" = UciEngine.find_stockfish() autodetect.
var stockfish_path := ""

# Introspection (read after a call; the test suite asserts on these)
var last_source := ""          # "llm" | "llm-retryN" | "fallback" | "counseled[-rN|-save]" | "maester[-fallback]"
var last_reply := ""           # raw text of the last LLM reply
var last_error := ""           # last transport/parse error, "" if none
var last_elapsed_s := 0.0      # wall time of the last choose_move
var last_reason := ""          # maester: the in-character reason emitted
var last_candidates: Array = []   # maester: [{uci, san, cp, mate, summary}] rank order
var available_models: Array[String] = []   # from the last successful ping()
var offline_reason := ""       # OFFLINE_TEXT (+ detail) after a failed ping()

var _engine: UciEngine = null
var _engine_failed := false

# MOVE: line — capture whatever token follows; normalization decides legality.
var _move_line_re := RegEx.create_from_string("(?i)MOVE:\\s*`?([^`\\s]+)`?")
# Bare-UCI shape after normalization (x/annotation noise already stripped).
var _bare_uci_re := RegEx.create_from_string("^[a-h][1-8][a-h][1-8][qrbn]?$")


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
	if legal.size() == 1:
		# Forced move — play it immediately, no LLM round-trip.
		last_source = "forced"
		last_error = ""
		last_candidates = []
		last_reason = FORCED_TEXT
		thinking_started.emit()
		oracle_reason.emit(FORCED_TEXT)
		last_elapsed_s = 0.0
		thinking_finished.emit(0.0)
		return legal[0]
	var by_uci := {}
	for m in legal:
		by_uci[String(m.to_uci()).to_lower()] = m
	var by_san := _san_index(by_uci)
	last_source = ""
	last_error = ""
	last_reason = ""
	last_candidates = []
	thinking_started.emit()
	var t0 := Time.get_ticks_msec()
	var chosen: Variant = null
	match await _effective_mode():
		MODE_COUNSELED:
			chosen = await _choose_counseled(state, by_uci, by_san, t0)
		MODE_MAESTER:
			chosen = await _choose_maester(state, by_uci, by_san, t0)
		_:
			chosen = await _choose_pure(by_uci, by_san, _build_messages(state, by_uci.keys()), t0)
	last_elapsed_s = float(Time.get_ticks_msec() - t0) / 1000.0
	thinking_finished.emit(last_elapsed_s)
	return chosen


## The historic pure-LLM behavior: corrective-retry loop, then the loudly
## flagged random fallback.
func _choose_pure(by_uci: Dictionary, by_san: Dictionary, messages: Array, t0: int) -> Variant:
	var r := await _llm_uci_loop(messages, by_uci, by_san, t0, MOVE_TIMEOUT_S,
		_tokens_for(by_uci.size()))
	var uci := String(r["uci"])
	if not uci.is_empty():
		var attempt := int(r["attempts"]) - 1
		last_source = "llm" if attempt == 0 else "llm-retry%d" % attempt
		return by_uci[uci]
	# Final fallback: random legal move, loudly flagged.
	last_source = "fallback"
	var keys := _sorted_keys(by_uci)
	var chosen = by_uci[keys.pick_random()]
	var reason := "%s — no legal move from the endpoint after %d attempts (%s); played random %s" \
		% [STUMBLE_TEXT, 1 + MAX_RETRIES, last_error if not last_error.is_empty() else "unusable replies", chosen.to_uci()]
	push_warning(reason)
	oracle_stumbled.emit(reason)
	return chosen


## The corrective-retry LLM loop shared by pure and counseled modes.
## Appends the assistant reply (and any corrective user message) to
## `messages` so counsel can continue the conversation. Each retry escalates
## max_tokens one tier (a truncated small-budget reply must not spiral).
## Returns {"uci": String ("" if none usable), "attempts": int}.
func _llm_uci_loop(messages: Array, by_uci: Dictionary, by_san: Dictionary, t0: int,
		budget_s: float, max_tokens := TOKENS_FULL) -> Dictionary:
	var tokens := max_tokens
	for attempt in range(1 + MAX_RETRIES):
		var remaining := budget_s - float(Time.get_ticks_msec() - t0) / 1000.0
		if remaining <= 1.0:
			last_error = "move budget (%.0fs) exhausted" % budget_s
			return {"uci": "", "attempts": attempt}
		if attempt > 0:
			retry_attempted.emit(attempt)
			tokens = mini(tokens * 2, TOKENS_FULL)
		var text := await _chat(messages, remaining, tokens)
		last_reply = text
		var uci := _extract_uci(text, by_uci, by_san)
		if not uci.is_empty():
			messages.append({"role": "assistant", "content": text})
			return {"uci": uci, "attempts": attempt + 1}
		messages.append({"role": "assistant", "content": text if not text.is_empty() else "(no reply)"})
		messages.append({"role": "user", "content":
			"Your previous reply could not be used: it did not contain a legal " +
			"UCI move. You MUST end your reply with exactly one line " +
			"'MOVE: <uci>' choosing verbatim from this legal move list: " +
			", ".join(_sorted_keys(by_uci))})
	return {"uci": "", "attempts": 1 + MAX_RETRIES}


## Callback-style wrapper: fires the request and calls `callback(move)` when
## done (move is a ChessMove or null). Non-blocking for the caller.
func choose_move_async(state, callback: Callable, difficulty := 2) -> void:
	var move: Variant = await choose_move(state, difficulty)
	if callback.is_valid():
		callback.call(move)


# -- counseled mode ----------------------------------------------------------


## The LLM proposes as in pure mode; Stockfish reviews each proposal at
## COUNSEL_DEPTH against its own best. Proposals losing more than
## COUNSEL_CP_THRESHOLD cp draw a reconsideration prompt (up to
## MAX_RECONSIDERATIONS); exhausted counsel plays the engine's 3rd-ranked
## move — the quiet save — via the stumble path with the softer HEEDS_TEXT.
func _choose_counseled(state, by_uci: Dictionary, by_san: Dictionary, t0: int) -> Variant:
	var messages := _build_messages(state, by_uci.keys())
	var review := {}
	var proposed_any := false
	for round_i in range(1 + MAX_RECONSIDERATIONS):
		var toks := _tokens_for(by_uci.size()) if round_i == 0 else TOKENS_RECONSIDER
		var r := await _llm_uci_loop(messages, by_uci, by_san, t0, MOVE_TIMEOUT_S, toks)
		var uci := String(r["uci"])
		if uci.is_empty():
			break   # endpoint unusable — counsel saves below
		proposed_any = true
		review = await _counsel_review(state, uci)
		if review.is_empty() or float(review.get("delta", 0.0)) <= COUNSEL_CP_THRESHOLD:
			# Sound proposal (or the advisor hiccuped — trust the Oracle).
			last_source = "counseled" if round_i == 0 else "counseled-r%d" % round_i
			return by_uci[uci]
		if round_i < MAX_RECONSIDERATIONS:
			messages.append({"role": "user", "content":
				"Your move %s loses material/position: %s. Choose again — legal moves: %s"
				% [_san_of(by_uci, uci), String(review.get("reason", "")),
					", ".join(_sorted_keys(by_uci))]})
	# The quiet save: the engine's 3rd-ranked move (its best when the Oracle
	# never even produced a proposal).
	var save_uci := ""
	if proposed_any:
		save_uci = String(review.get("third", ""))
	if save_uci.is_empty() or not by_uci.has(save_uci):
		var res := await _engine_search(state, {"depth": COUNSEL_DEPTH, "multipv": 3})
		var lines: Array = res.get("lines", [])
		if not lines.is_empty():
			var rank := mini(2, lines.size() - 1) if proposed_any else 0
			save_uci = String(lines[rank].get("move", ""))
	if save_uci.is_empty() or not by_uci.has(save_uci):
		# No engine either — behave like the pure fallback.
		return await _choose_pure(by_uci, by_san, _build_messages(state, by_uci.keys()), t0)
	last_source = "counseled-save"
	var reason := "%s — counsel exhausted; the quiet save %s (%s)" \
		% [HEEDS_TEXT, _san_of(by_uci, save_uci),
			last_error if not last_error.is_empty() else "proposals kept losing ground"]
	push_warning(reason)
	oracle_stumbled.emit(reason)
	return by_uci[save_uci]


## Review one proposal: {best, delta (cp, mover's perspective), third,
## reason}. {} when the engine is unavailable or the search failed.
func _counsel_review(state, prop_uci: String) -> Dictionary:
	var fen: String = state.get_fen()
	var res := await _engine_search(state, {"depth": COUNSEL_DEPTH, "multipv": 3}, fen)
	var lines: Array = res.get("lines", [])
	if lines.is_empty():
		return {}
	var best: Dictionary = lines[0]
	var prop_line := {}
	for l in lines:
		if String(l.get("move", "")) == prop_uci:
			prop_line = l
	if prop_line.is_empty():
		var pr := await _engine_search(state,
			{"depth": COUNSEL_DEPTH, "searchmoves": [prop_uci]}, fen)
		var plines: Array = pr.get("lines", [])
		if plines.is_empty():
			return {}
		prop_line = plines[0]
	var delta := _score_value(best) - _score_value(prop_line)
	var third := String(lines[mini(2, lines.size() - 1)].get("move", ""))
	return {
		"best": String(best.get("move", "")),
		"delta": delta,
		"third": third,
		"reason": _delta_reason(best, prop_line, delta),
	}


## UCI score -> comparable value in cp from the mover's perspective
## (mates dominate every cp swing).
func _score_value(line: Dictionary) -> float:
	if line.get("mate") != null:
		var m := int(line["mate"])
		return (100000.0 - m) if m > 0 else (-100000.0 - m)
	return float(line.get("cp") if line.get("cp") != null else 0)


func _delta_reason(best: Dictionary, prop: Dictionary, delta: float) -> String:
	if prop.get("mate") != null and int(prop["mate"]) < 0:
		return "it walks into a forced mate in %d" % absi(int(prop["mate"]))
	if best.get("mate") != null and int(best["mate"]) > 0:
		return "it lets a forced mate in %d slip away" % int(best["mate"])
	return "it concedes about %.1f pawns versus %s" % [delta / 100.0, String(best.get("move", "?"))]


func _san_of(by_uci: Dictionary, uci: String) -> String:
	if by_uci.has(uci):
		var m = by_uci[uci]
		if m.notation_san != null:
			return String(m.notation_san)
	return uci


# -- maester mode ------------------------------------------------------------


var _pick_re := RegEx.create_from_string("(?i)PICK:\\s*([0-9]+)")
var _reason_re := RegEx.create_from_string("(?i)REASON:\\s*(.+)")


## Stockfish MultiPV builds the candidates; the LLM picks one and narrates.
## Every playable outcome is engine-vetted — the maester never blunders.
func _choose_maester(state, by_uci: Dictionary, by_san: Dictionary, t0: int) -> Variant:
	var res := await _engine_search(state,
		{"depth": MAESTER_DEPTH, "multipv": MAESTER_MULTIPV})
	var candidates: Array = []
	for l in res.get("lines", []):
		var uci := String(l.get("move", ""))
		if not by_uci.has(uci):
			continue
		candidates.append({
			"uci": uci,
			"san": _san_of(by_uci, uci),
			"cp": l.get("cp"),
			"mate": l.get("mate"),
			"summary": _candidate_summary(by_uci, uci),
		})
	if candidates.is_empty():
		# Engine died mid-session — degrade to the pure oracle.
		push_warning("maester: no engine candidates — degrading to pure oracle")
		return await _choose_pure(by_uci, by_san, _build_messages(state, by_uci.keys()), t0)
	last_candidates = candidates
	var text := await _chat(_build_maester_messages(state, candidates),
		MAESTER_TIMEOUT_S, TOKENS_MAESTER_PICK)
	last_reply = text
	var pick := _parse_pick(text, candidates)
	if pick >= 0:
		last_source = "maester"
		last_reason = _parse_reason(text)
		oracle_reason.emit(last_reason)
		return by_uci[candidates[pick]["uci"]]
	# Unreachable / timed out / unusable reply: the engine's top move.
	last_source = "maester-fallback"
	last_reason = MAESTER_SLEEP_REASON
	oracle_reason.emit(last_reason)
	return by_uci[candidates[0]["uci"]]


func _build_maester_messages(state, candidates: Array) -> Array:
	var color_name := "black" if state.turn else "white"
	var menu: Array[String] = []
	for i in candidates.size():
		var c: Dictionary = candidates[i]
		menu.append("%d. %s (%s) %s — %s" % [i + 1, String(c["san"]), String(c["uci"]),
			_eval_text(c), String(c["summary"])])
	var system := (
		"You are the Oracle, a mystic chess sage. Your Grand Maester (a strong " +
		"chess engine) has vetted %d candidate moves — all are sound. " % candidates.size() +
		"Pick the ONE that best fits your style and give a short in-character " +
		"reason. Reply with exactly two lines:\nPICK: <number>\nREASON: <your " +
		"reason, at most %d characters>" % MAX_REASON_CHARS)
	var user := (
		"Position (FEN): %s\n" % state.get_fen() +
		"You play: %s. It is your move.\n" % color_name +
		"The Maester's candidates:\n%s\n" % "\n".join(menu) +
		"Reply now:\nPICK: <number>\nREASON: <in-character, max %d chars>" % MAX_REASON_CHARS)
	return [{"role": "system", "content": system}, {"role": "user", "content": user}]


func _eval_text(c: Dictionary) -> String:
	if c.get("mate") != null:
		var m := int(c["mate"])
		return ("mate in %d" % m) if m > 0 else ("mated in %d" % absi(m))
	return "%+.2f" % (float(c.get("cp") if c.get("cp") != null else 0) / 100.0)


## One-line positional summary derived from the move itself.
func _candidate_summary(by_uci: Dictionary, uci: String) -> String:
	var m = by_uci.get(uci)
	if m == null:
		return "improves the position"
	var san := _san_of(by_uci, uci)
	if m.is_castling:
		return "tucks the king behind the wall"
	if m.promotion != null:
		return "crowns a new piece on the last rank"
	if m.is_capture() and san.ends_with("+"):
		return "wins material with check"
	if m.is_capture():
		return "wins or trades material"
	if san.ends_with("#"):
		return "delivers checkmate"
	if san.ends_with("+"):
		return "harries the enemy king"
	var dest := uci.substr(2, 2)
	if dest in ["d4", "e4", "d5", "e5"]:
		return "stakes a claim in the center"
	if san.begins_with("N") or san.begins_with("B"):
		return "develops a piece toward the fight"
	return "improves the position quietly"


func _parse_pick(text: String, candidates: Array) -> int:
	if text.is_empty():
		return -1
	var matches := _pick_re.search_all(text)
	if not matches.is_empty():
		var n := int(matches[matches.size() - 1].get_string(1))
		if n >= 1 and n <= candidates.size():
			return n - 1
	# Fall back to a stated UCI/SAN move that matches a candidate — through
	# the same noise-tolerant extractor the move loop uses.
	var cand_ucis := {}
	var cand_sans := {}
	for i in candidates.size():
		var cu := String(candidates[i]["uci"])
		cand_ucis[cu] = i
		var san := String(candidates[i]["san"])
		cand_sans[san] = cu
		var stripped := _strip_san_noise(san)
		if not cand_sans.has(stripped):
			cand_sans[stripped] = cu
	var uci := _extract_uci(text, cand_ucis, cand_sans)
	if not uci.is_empty():
		return int(cand_ucis[uci])
	return -1


func _parse_reason(text: String) -> String:
	var m := _reason_re.search(text)
	var reason := m.get_string(1).strip_edges() if m != null else ""
	if reason.is_empty():
		reason = "The Maester's counsel stands."
	return reason.left(MAX_REASON_CHARS)


# -- advisor engine ----------------------------------------------------------


## Resolve the mode actually playable right now: counseled/maester degrade to
## pure (logged) when stockfish is missing or refuses to start.
func _effective_mode() -> String:
	if mode == MODE_COUNSELED or mode == MODE_MAESTER:
		if await _ensure_engine() == null:
			push_warning("stockfish unavailable — '%s' mode degrades to pure oracle" % mode)
			return MODE_PURE
	return mode if MODE_LABELS.has(mode) else MODE_PURE


## Lazy-start the UciEngine child (one engine per opponent, shared by every
## move). null when stockfish is unavailable; failure is remembered so a
## missing binary costs one probe, not one per move.
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
	eng.name = "Maester"
	add_child(eng)
	if not eng.start(path) or not await eng.init(8.0):
		eng.queue_free()
		_engine_failed = true
		return null
	_engine = eng
	return _engine


## One engine search from `state` (or an explicit fen). {} on any failure.
func _engine_search(state, opts: Dictionary, fen := "") -> Dictionary:
	var eng := await _ensure_engine()
	if eng == null:
		return {}
	return await eng.search(fen if not fen.is_empty() else String(state.get_fen()), opts)


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


## Pull one legal move out of LLM output and return its UCI (by_uci key).
## Prefers 'MOVE: xxxx' lines (last one wins), then scans every reply token
## last-to-first so the final stated move wins. Tolerates the notations
## models actually emit: capture 'x' ("e4xd5"), SAN ("exd5", "Nxd5+", "O-O"),
## check/annotation suffixes (+ # ! ?), backticks/quotes, and mixed case
## (promotion suffix either case). SAN matching needs `by_san` from
## _san_index; without it only UCI-shaped tokens resolve. "" if none.
## (2026-08-08 scar: the old bare-UCI-only regexes silently dropped every
## capture written as "e4xd5"/"exd5"/"Nxd5+", and the corrective retry then
## steered the Oracle to a quieter, cleanly formatted move — systematic
## capture censorship by the parser.)
func _extract_uci(text: String, by_uci: Dictionary, by_san: Dictionary = {}) -> String:
	if text.is_empty():
		return ""
	var matches := _move_line_re.search_all(text)
	for i in range(matches.size() - 1, -1, -1):
		var uci := _resolve_move_token(matches[i].get_string(1), by_uci, by_san)
		if not uci.is_empty():
			return uci
	var toks := text.replace("\n", " ").replace("\t", " ").split(" ", false)
	for i in range(toks.size() - 1, -1, -1):
		var uci := _resolve_move_token(toks[i], by_uci, by_san)
		if not uci.is_empty():
			return uci
	return ""


const _TOKEN_TRIM := "`'\"()[]{}<>,.;:*_"

## Normalize one reply token and match it against the legal set: bare or
## x-noised UCI first (case-tolerant), then SAN — exact, then with x/+/#/!/?
## noise stripped, then case-insensitive where unambiguous. by_uci key or "".
func _resolve_move_token(tok: String, by_uci: Dictionary, by_san: Dictionary) -> String:
	var t := tok.strip_edges()
	while t.length() > 0 and _TOKEN_TRIM.contains(t.left(1)):
		t = t.substr(1)
	while t.length() > 0:
		var last := t.right(1)
		if _TOKEN_TRIM.contains(last) or last in ["+", "#", "!", "?"]:
			t = t.left(t.length() - 1)
		else:
			break
	if t.is_empty():
		return ""
	var u := t.to_lower().replace("x", "")
	if _bare_uci_re.search(u) != null and by_uci.has(u):
		return u
	if by_san.is_empty():
		return ""
	var s := t.replace("0-0-0", "O-O-O").replace("0-0", "O-O")
	for cand in [s, _strip_san_noise(s)]:
		if by_san.has(cand):
			return String(by_san[cand])
	var ci := "ci:" + _strip_san_noise(s).to_lower()
	if by_san.has(ci):
		return String(by_san[ci])
	return ""


## SAN lookup table for _extract_uci: exact SAN, noise-stripped SAN, and —
## where unambiguous — a case-insensitive form under "ci:"-prefixed keys
## (ambiguous lowercase forms like pawn "bxc4" vs bishop "Bxc4" are dropped).
func _san_index(by_uci: Dictionary) -> Dictionary:
	var by_san := {}
	var ci_seen := {}
	for uci in by_uci:
		var m = by_uci[uci]
		if m.notation_san == null:
			continue
		var san := String(m.notation_san)
		if not by_san.has(san):
			by_san[san] = uci
		var stripped := _strip_san_noise(san)
		if not by_san.has(stripped):
			by_san[stripped] = uci
		var ci := "ci:" + stripped.to_lower()
		if ci_seen.has(ci):
			by_san.erase(ci)   # ambiguous once lowercased — require exact case
		else:
			ci_seen[ci] = true
			by_san[ci] = uci
	return by_san


static func _strip_san_noise(s: String) -> String:
	var out := s.replace("x", "")
	while out.length() > 0 and out.right(1) in ["+", "#", "!", "?"]:
		out = out.left(out.length() - 1)
	return out


func _sorted_keys(d: Dictionary) -> Array:
	var keys := d.keys()
	keys.sort()
	return keys


## Thinking budget for a position with `n_moves` legal moves.
func _tokens_for(n_moves: int) -> int:
	if n_moves <= FEW_MOVES_MAX:
		return TOKENS_FEW
	if n_moves <= SOME_MOVES_MAX:
		return TOKENS_SOME
	return TOKENS_FULL


# -- transport --------------------------------------------------------------


func _chat(messages: Array, timeout_s: float, max_tokens := TOKENS_FULL) -> String:
	var body := JSON.stringify({
		"model": _resolved_model(),
		"messages": messages,
		"temperature": TEMPERATURE,
		"max_tokens": max_tokens,
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
