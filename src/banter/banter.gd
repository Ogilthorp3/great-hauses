class_name BanterEngine
extends Node
## Rival-house SMACK TALK. Generates short in-character taunts from the RIVAL
## house at game beats (game start, captures, checks, blunders, endgame).
##
## MODULE CONTRACT (see src/banter/INTEGRATION-banter.md for wiring):
##   var banter := BanterEngine.new()
##   banter.house_id = rival_house_id            # a src/houses/houses.json id
##   add_child(banter)                            # HTTPRequest needs the tree
##   banter.banter_line.connect(_on_banter_line)  # HUD renders the taunt
##   banter.on_beat(BanterEngine.BEAT_GAME_START) # fire-and-forget, per beat
##   banter.note_ply()                            # after every applied half-move
##
## Two paths, one signal:
##   LLM   — DeepSeek over the same OpenAI-compatible endpoint the DS4-Oracle
##           uses (env DS4_CHESS_URL, default http://127.0.0.1:18000). One
##           request per taunt: persona system prompt + beat user prompt,
##           temperature 0.9, max_tokens 60, LLM_TIMEOUT_S budget.
##   pool  — canned fallback from src/banter/banter_lines.json (8+ hand-written
##           lines per house per beat) whenever the LLM is disabled, offline,
##           slow, empty, or repeats itself.
## Either way the taunt arrives via `banter_line(house_id, text, beat)`.
##
## NEVER blocks gameplay: `on_beat()` returns immediately (bool = "a taunt was
## started"); the delivery coroutine runs behind the scenes and emits when the
## line is ready. Rate limiting (MIN_FULLMOVE_GAP full moves between taunts,
## one taunt in flight at a time, blunder/bookend beats always allowed) and
## in-game dedupe (no line repeats within a game) are enforced here, not by
## the caller.

## A taunt is ready. house_id = the speaking (rival) house, beat = the
## BEAT_* that triggered it. Emitted from the delivery coroutine — for the
## pool path that is synchronously inside on_beat(), for the LLM path it is
## whenever the endpoint answers (or the fallback fires). Connect before
## calling on_beat().
signal banter_line(house_id: String, text: String, beat: String)
## A beat produced no line. why: "no_house" | "unknown_beat" | "inflight" |
## "rate_limited" | "pool_exhausted". Debug/e2e evidence only.
signal banter_skipped(beat: String, why: String)

# -- beats -------------------------------------------------------------------
# All beats speak from the RIVAL's point of view (the rival is the speaker):
#   player_captured  the rival captured one of the PLAYER's pieces -> gloat
#   rival_captured   the player captured one of the RIVAL's pieces -> wounded pride
#   check_given      the rival put the PLAYER's king in check      -> menace
#   check_received   the player put the RIVAL's king in check      -> rattled defiance
#   player_blunder   the player blundered (caller supplies the eval swing)
#   player_undo      the player took their move back -> mock the take-back
#   endgame_win      the RIVAL won the game
#   endgame_lose     the RIVAL lost the game

const BEAT_GAME_START := "game_start"
const BEAT_PLAYER_CAPTURED := "player_captured"
const BEAT_RIVAL_CAPTURED := "rival_captured"
const BEAT_CHECK_GIVEN := "check_given"
const BEAT_CHECK_RECEIVED := "check_received"
const BEAT_PLAYER_BLUNDER := "player_blunder"
const BEAT_PLAYER_UNDO := "player_undo"
const BEAT_ENDGAME_WIN := "endgame_win"
const BEAT_ENDGAME_LOSE := "endgame_lose"

const BEATS: Array[String] = [
	BEAT_GAME_START, BEAT_PLAYER_CAPTURED, BEAT_RIVAL_CAPTURED,
	BEAT_CHECK_GIVEN, BEAT_CHECK_RECEIVED, BEAT_PLAYER_BLUNDER,
	BEAT_PLAYER_UNDO, BEAT_ENDGAME_WIN, BEAT_ENDGAME_LOSE,
]

## Beats exempt from the full-move gap: blunders are the best taunts and are
## always allowed; the bookends (start/end) sit outside normal move flow; an
## undo happens outside the move flow too — the take-back IS the moment.
const GAP_EXEMPT: Array[String] = [
	BEAT_GAME_START, BEAT_PLAYER_BLUNDER, BEAT_PLAYER_UNDO,
	BEAT_ENDGAME_WIN, BEAT_ENDGAME_LOSE,
]

# -- LLM configuration (endpoint resolution mirrors src/ai/ds4_opponent.gd) --

const DEFAULT_CHAT_URL := "http://127.0.0.1:18000/v1/chat/completions"
const ENV_URL := "DS4_CHESS_URL"      # base URL / v1 URL / full chat URL all accepted
const ENV_MODEL := "DS4_CHESS_MODEL"
const DEFAULT_MODEL := "deepseek-v4-flash"
const TEMPERATURE := 0.9              # taunts want spice, not accuracy
const MAX_TOKENS := 60
const LLM_TIMEOUT_S := 8.0            # then the canned pool answers instead
const MAX_LINE_CHARS := 90

const MIN_FULLMOVE_GAP := 2           # full moves between taunts (see on_beat)
const LINES_PATH := "res://src/banter/banter_lines.json"

## Voice sheet per archetype (houses.json `archetype` field) — the flavor
## paragraph of the persona system prompt AND the style bible the canned
## pools in banter_lines.json were written against.
const ARCHETYPE_VOICE := {
	"wolf": "cold and laconic; short sentences, winter and snow, the patience of the pack, teeth shown rarely and meant always",
	"lion": "everything is debts and gold; ledgers, interest, payment and collection, the purring menace of a creditor",
	"kraken": "salt and drowning; tides, the crushing deep, brine and wrecks, the sea's slow inevitability",
	"dragon": "fire and ancestry; old blood, generations of flame, ash and embers, dynastic disdain",
	"stag": "storms; thunder, lightning, gales and rising weather, antlered pride under an open sky",
	"rose": "courtly venom; exquisitely polite malice, gardens, thorns and pruning, compliments that cut",
	"sun": "blazing pride; radiance, noon and dawn, light that owns the sky, magnificent vanity",
	"falcon": "honor and heights; the high wind, clean strikes from above, fair play delivered at speed",
	"trout": "rivers and patience; slow water wearing stone, currents, fords and floods, unhurried certainty",
}

# -- knobs -------------------------------------------------------------------

## The RIVAL house doing the taunting — a houses.json id ("goldclaw", ...).
## Must be set before the first on_beat(). Legacy Frost/Ember matches have no
## registry id: leave this empty and every beat is skipped ("no_house").
var house_id := ""
## false = canned pools only, no network (tests, offline builds, user pref).
var llm_enabled := true
## Programmatic endpoint override (lowest precedence is DEFAULT_CHAT_URL,
## then this, then the DS4_CHESS_URL environment variable) — ds4 parity.
var endpoint_override := ""
## Model id sent to the endpoint. Empty = env DS4_CHESS_MODEL else DEFAULT_MODEL.
var model := ""
## Per-taunt LLM budget in seconds; on expiry the canned pool answers.
var llm_timeout_s := LLM_TIMEOUT_S
## Full moves that must pass between taunts (GAP_EXEMPT beats ignore it).
var min_fullmove_gap := MIN_FULLMOVE_GAP

# -- introspection (tests / e2e evidence) ------------------------------------

var last_source := ""      # "llm" | "pool" | ""
var last_error := ""       # last LLM transport/parse error, "" if none
var last_beat := ""
var taunt_count := 0       # banter_line emissions this game
var skip_count := 0        # banter_skipped emissions this game

# -- state -------------------------------------------------------------------

static var _pools: Dictionary = {}   # houses.json id -> {beat -> [lines]}

var _ply := 0
var _fullmove := 1                   # chess convention: starts at 1
var _last_taunt_fullmove := -1000
var _inflight := false
var _used: Dictionary = {}           # line template -> true (in-game dedupe)
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


## Deterministic pool picks (tests).
func seed_rng(s: int) -> void:
	_rng.seed = s


# -- game-flow surface -------------------------------------------------------


## Call after EVERY applied half-move (both sides). Drives the full-move
## clock the rate limiter counts in. Callers that already know the fullmove
## number may instead pass {"fullmove": n} in the on_beat context.
func note_ply() -> void:
	_ply += 1
	@warning_ignore("integer_division")
	_fullmove = _ply / 2 + 1


## Undo support: the take-back removed plies note_ply() already counted.
## Winds the clock back to `ply` and clamps the last-taunt marker so the
## rate limiter can never sit in the future after a revert.
func rewind_ply_clock(ply: int) -> void:
	_ply = maxi(ply, 0)
	@warning_ignore("integer_division")
	_fullmove = _ply / 2 + 1
	_last_taunt_fullmove = mini(_last_taunt_fullmove, _fullmove)


## Fresh game: clears the dedupe set, counters, and the rate-limit clock.
func reset_game() -> void:
	_ply = 0
	_fullmove = 1
	_last_taunt_fullmove = -1000
	_inflight = false
	_used.clear()
	taunt_count = 0
	skip_count = 0
	last_source = ""
	last_error = ""
	last_beat = ""


## Fire a beat. Returns true when a taunt was STARTED (the line itself arrives
## later via banter_line — synchronously for the pool path, asynchronously for
## the LLM path). Never blocks; never awaits. ctx keys (all optional):
##   "piece"          lowercase captured-piece name ("bishop") for the capture
##                    beats — enables the {piece} lines in the canned pools
##                    and names the piece in the LLM prompt
##   "eval_swing_cp"  centipawns the player's blunder handed to the rival
##                    (BEAT_PLAYER_BLUNDER's hook — caller supplies the eval)
##   "fullmove"       explicit fullmove number (else the note_ply() clock)
## Rate rules: at most one taunt in flight; min_fullmove_gap full moves
## between taunts — except GAP_EXEMPT beats (blunders + bookends).
func on_beat(beat: String, ctx: Dictionary = {}) -> bool:
	if house_id.is_empty() or not HouseRegistry.has_house(house_id):
		_skip(beat, "no_house")
		return false
	if not BEATS.has(beat):
		_skip(beat, "unknown_beat")
		return false
	if _inflight:
		_skip(beat, "inflight")
		return false
	var fullmove := int(ctx.get("fullmove", _fullmove))
	if not GAP_EXEMPT.has(beat) and fullmove - _last_taunt_fullmove < min_fullmove_gap:
		_skip(beat, "rate_limited")
		return false
	_inflight = true
	_last_taunt_fullmove = fullmove
	last_beat = beat
	_deliver(beat, ctx)   # un-awaited coroutine: fire and forget
	return true


func _skip(beat: String, why: String) -> void:
	skip_count += 1
	banter_skipped.emit(beat, why)


# -- delivery ----------------------------------------------------------------


func _deliver(beat: String, ctx: Dictionary) -> void:
	var text := ""
	if llm_enabled and is_inside_tree():
		text = await _llm_taunt(beat, ctx)
	elif llm_enabled:
		last_error = "BanterEngine not in the scene tree — LLM path skipped"
	if not text.is_empty() and not _used.has(text):
		_used[text] = true
		last_source = "llm"
	else:
		text = _pick_pool_line(beat, ctx)
		last_source = "pool" if not text.is_empty() else ""
	_inflight = false
	if text.is_empty():
		_skip(beat, "pool_exhausted")
		return
	taunt_count += 1
	banter_line.emit(house_id, text, beat)


## One unused line from the house's pool for this beat, tokens substituted.
## Lines carrying {piece} are only eligible when ctx supplies one. "" when
## the pool is exhausted (dedupe never repeats a line within a game).
func _pick_pool_line(beat: String, ctx: Dictionary) -> String:
	var has_piece: bool = not str(ctx.get("piece", "")).is_empty()
	var eligible: Array[String] = []
	for line in pool_lines(house_id, beat):
		var s := str(line)
		if _used.has(s):
			continue
		if s.contains("{piece}") and not has_piece:
			continue
		eligible.append(s)
	if eligible.is_empty():
		return ""
	var template := eligible[_rng.randi_range(0, eligible.size() - 1)]
	_used[template] = true
	return template.replace("{piece}", str(ctx.get("piece", "")))


# -- canned pools ------------------------------------------------------------


static func _ensure_pools() -> void:
	if not _pools.is_empty():
		return
	var f := FileAccess.open(LINES_PATH, FileAccess.READ)
	if f == null:
		push_error("BanterEngine: cannot open %s" % LINES_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed == null or not parsed is Dictionary or not parsed.has("houses"):
		push_error("BanterEngine: %s is not a valid banter-lines file" % LINES_PATH)
		return
	_pools = parsed["houses"]
	# ...and then whatever the installed HAUS PACKS brought with them. A haus
	# is a folder now (docs/HAUS-PACK.md), and a haus that ships its own voice
	# should speak in it: a pack's "banter" block lands here beside the nine.
	# A pack may also OVERRIDE a shipped house's pool by declaring the same id,
	# which is how a translation or a re-write ships without touching this file.
	var from_packs: Dictionary = HouseRegistry.all_banter_pools()
	for hid in from_packs:
		_pools[hid] = from_packs[hid]


## Force a re-read of banter_lines.json (tests / hot-reload).
static func reload_pools() -> void:
	_pools = {}
	_ensure_pools()


## The canned lines (raw templates) for one house + beat; [] if unknown.
static func pool_lines(hid: String, beat: String) -> Array:
	_ensure_pools()
	var h: Variant = _pools.get(hid, {})
	if not h is Dictionary:
		return []
	var arr: Variant = (h as Dictionary).get(beat, [])
	return (arr as Array).duplicate() if arr is Array else []


## House ids present in banter_lines.json (completeness tests).
static func pool_house_ids() -> Array:
	_ensure_pools()
	return _pools.keys()


# -- prompts -----------------------------------------------------------------


## The persona system prompt for a house: identity sheet (name, archetype
## voice, seat, motto from HouseRegistry) + the hard style rules. Public so
## tests can assert per-archetype correctness.
static func build_system_prompt(hid: String) -> String:
	var h := HouseRegistry.get_house(hid)
	var arch := str(h.get("archetype", ""))
	var voice := str(ARCHETYPE_VOICE.get(arch, "proud, ancient, and dangerous"))
	return (
		"You are the voice of %s, a Great Haus on a battle-chess board.\n" % str(h.get("name", hid))
		+ "Archetype: the %s — %s.\n" % [arch, voice]
		+ "Seat: %s. Motto: %s\n" % [str(h.get("seat", "an old keep")), str(h.get("motto", ""))]
		+ "You taunt the enemy haus at dramatic moments of the game.\n"
		+ "Speak exactly one taunt, at most 90 characters, no quotes, "
		+ "medieval diction, never modern slang, wit over cruelty. "
		+ "Reply with the taunt alone — no preamble, no explanation."
	)


## The beat-specific user prompt. Public for tests.
static func build_beat_prompt(beat: String, ctx: Dictionary = {}) -> String:
	var piece := str(ctx.get("piece", ""))
	match beat:
		BEAT_GAME_START:
			return "The armies are set and the game begins. Issue your opening taunt to the enemy haus."
		BEAT_PLAYER_CAPTURED:
			var what := ("the enemy's %s" % piece) if not piece.is_empty() else "an enemy piece"
			return "You have just captured %s. Gloat, coldly, in your haus's voice." % what
		BEAT_RIVAL_CAPTURED:
			var what := ("your %s" % piece) if not piece.is_empty() else "one of your pieces"
			return "The enemy has just captured %s. Answer with wounded pride — hurt, but unbowed." % what
		BEAT_CHECK_GIVEN:
			return "You have just put the enemy king in check. Menace them."
		BEAT_CHECK_RECEIVED:
			return "The enemy has put your king in check. Answer with rattled defiance."
		BEAT_PLAYER_BLUNDER:
			var swing := float(ctx.get("eval_swing_cp", 0.0)) / 100.0
			var about := (" by about %.1f pawns" % swing) if swing > 0.0 else ""
			return ("The enemy just made a terrible blunder, swinging the game%s " % about
				+ "in your favor. Relish it — blunder taunts are your finest work.")
		BEAT_PLAYER_UNDO:
			return ("The enemy just took their move back, wishing it unmade. "
				+ "Mock the take-back — no army marches backward with honor.")
		BEAT_ENDGAME_WIN:
			return "You have won the war. Deliver the victory line."
		BEAT_ENDGAME_LOSE:
			return "You have lost the war. Concede in character — bitter, proud, promising a return."
	return "React, in character, to the state of the game."


# -- LLM path ----------------------------------------------------------------


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


func _resolved_model() -> String:
	if not model.is_empty():
		return model
	var env := OS.get_environment(ENV_MODEL)
	return env if not env.is_empty() else DEFAULT_MODEL


## One taunt from the endpoint, sanitized; "" on any failure (last_error
## explains) so the caller falls back to the canned pool.
func _llm_taunt(beat: String, ctx: Dictionary) -> String:
	last_error = ""
	var body := JSON.stringify({
		"model": _resolved_model(),
		"messages": [
			{"role": "system", "content": build_system_prompt(house_id)},
			{"role": "user", "content": build_beat_prompt(beat, ctx)},
		],
		"temperature": TEMPERATURE,
		"max_tokens": MAX_TOKENS,
	})
	var raw := await _http_post(chat_url(), body, llm_timeout_s)
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
	var choice: Dictionary = (choices as Array)[0]
	# A reply cut off by the token cap is never a usable taunt: reasoning
	# models burn the budget on chain-of-thought and the "last line" is then
	# truncated meta-text, not a line (seen live 2026-08-08: the caption
	# read "1. The user wants me to act as Haus Goldclaw…"). Fall back.
	if str(choice.get("finish_reason", "")) == "length":
		last_error = "reply truncated (finish_reason=length)"
		return ""
	var msg: Variant = choice.get("message")
	if not (msg is Dictionary):
		last_error = "choice has no message"
		return ""
	var content := str(msg.get("content") if msg.get("content") != null else "")
	return sanitize_line(content)


## Enforce the output contract on whatever the model actually sent: last
## non-empty line only, labels and quote characters stripped, whitespace
## collapsed, clamped to MAX_LINE_CHARS at a word boundary. "" when nothing
## usable remains. Public for tests.
static func sanitize_line(raw: String) -> String:
	var s := raw.strip_edges()
	if s.is_empty():
		return ""
	var lines := s.split("\n", false)
	if lines.is_empty():
		return ""
	s = str(lines[lines.size() - 1]).strip_edges()
	for label in ["taunt:", "line:", "reply:"]:
		if s.to_lower().begins_with(label):
			s = s.substr(label.length()).strip_edges()
	for q in ["\"", "“", "”", "«", "»", "`"]:
		s = s.replace(q, "")
	while s.length() > 1 and (s.begins_with("'") or s.begins_with("‘")):
		s = s.substr(1)
	while s.length() > 1 and (s.ends_with("'") or s.ends_with("’")):
		s = s.left(s.length() - 1)
	s = " ".join(s.split(" ", false))
	if s.length() > MAX_LINE_CHARS:
		s = s.left(MAX_LINE_CHARS)
		var cut := s.rfind(" ")
		if cut > 45:  # only cut at a word boundary in the back half
			s = s.left(cut)
		s = s.rstrip(" ,;:—-.")
	return s.strip_edges()


## One HTTP POST via a throwaway HTTPRequest child (the ds4_opponent.gd
## pattern). Returns the body as UTF-8, "" on any failure (last_error set).
func _http_post(url: String, body: String, timeout_s: float) -> String:
	if not is_inside_tree():
		last_error = "BanterEngine must be add_child()ed before use (HTTPRequest needs the tree)"
		return ""
	var http := HTTPRequest.new()
	http.timeout = clampf(timeout_s, 0.5, 30.0)
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var err := http.request(url, headers, HTTPClient.METHOD_POST, body)
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
