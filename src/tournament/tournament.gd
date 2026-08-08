class_name Tournament
extends RefCounted
## Single-elimination war for the throne — nine Great Houses, headless-testable.
##
## Bracket shape (9 contenders: the player's house + 8 seeded rivals):
##   Round 0  Play-In        rivals[6] vs rivals[7] (the two lowest seeds)
##   Round 1  Quarterfinals  player vs play-in winner · r1v6 · r2v5 · r3v4
##   Round 2  Semifinals
##   Round 3  Grand Final
## The player fights one match per round (3 wins to the throne). Matches not
## involving the player resolve deterministically: the better seed (lower
## rivals[] index) advances. If the player falls, the rest of the bracket
## plays out and a rival is crowned.
##
## API: current_opponent() · report_result(win) · bracket_state() ·
## is_champion() · is_over() — state persists to user://tournament.json on
## every mutation (save_path is overridable for tests).

const DEFAULT_SAVE_PATH := "user://tournament.json"
const ROUND_NAMES: Array[String] = ["Play-In", "Quarterfinals", "Semifinals", "Grand Final"]
const SAVE_VERSION := 1

var save_path := DEFAULT_SAVE_PATH
var player_house := ""
var rivals: Array[String] = []   # seed order: rivals[0] = strongest rival
var rounds: Array = []           # Array of rounds; round = Array of {"a","b","winner"}
var champion := ""
var player_alive := true


# -- lifecycle --------------------------------------------------------------


## Build a fresh bracket and persist it. rival_ids must be exactly 8 house
## ids in seed order; pass [] to seed from HouseRegistry order (all houses
## minus the player's). Returns null on invalid input.
static func create(player_house_id: String, rival_ids: Array = [],
		path: String = DEFAULT_SAVE_PATH) -> Tournament:
	var seeds: Array[String] = []
	if rival_ids.is_empty():
		seeds = seeded_rivals(player_house_id)
	else:
		for r in rival_ids:
			seeds.append(str(r))
	if seeds.size() != 8 or player_house_id.is_empty() or seeds.has(player_house_id):
		push_error("Tournament.create: need a player house + exactly 8 distinct rivals")
		return null
	var t := Tournament.new()
	t.save_path = path
	t.player_house = player_house_id
	t.rivals = seeds
	t._build_bracket()
	t._advance()
	t.save()
	return t


## The other 8 houses in HouseRegistry file order (= seed order).
static func seeded_rivals(player_house_id: String) -> Array[String]:
	var out: Array[String] = []
	for id in HouseRegistry.house_ids():
		if id != player_house_id:
			out.append(id)
	return out


## Load a persisted tournament; null if missing or corrupt.
static func load_saved(path: String = DEFAULT_SAVE_PATH) -> Tournament:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed == null or not parsed is Dictionary:
		return null
	var d: Dictionary = parsed
	if int(d.get("version", -1)) != SAVE_VERSION:
		return null
	if not (d.has("player_house") and d.has("rivals") and d.has("rounds")):
		return null
	if (d["rivals"] as Array).size() != 8:
		return null
	var t := Tournament.new()
	t.save_path = path
	t.player_house = str(d["player_house"])
	for r in d["rivals"]:
		t.rivals.append(str(r))
	for round_data in d["rounds"]:
		var matches: Array = []
		for m in round_data:
			matches.append({"a": str(m["a"]), "b": str(m["b"]), "winner": str(m["winner"])})
		t.rounds.append(matches)
	t.champion = str(d.get("champion", ""))
	t.player_alive = bool(d.get("player_alive", true))
	return t


func save() -> void:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		push_error("Tournament.save: cannot write %s" % save_path)
		return
	f.store_string(JSON.stringify(_to_dict(), "\t"))


static func clear_saved(path: String = DEFAULT_SAVE_PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# -- public API -------------------------------------------------------------


## House id the player must face next; "" if the war is over (won or lost).
func current_opponent() -> String:
	var m := _player_pending_match()
	if m.is_empty():
		return ""
	return str(m["b"]) if str(m["a"]) == player_house else str(m["a"])


## Record the player's match result and let the rest of the round play out.
## Returns false (no-op) if the player has no pending match.
func report_result(win: bool) -> bool:
	var m := _player_pending_match()
	if m.is_empty():
		return false
	var opponent := str(m["b"]) if str(m["a"]) == player_house else str(m["a"])
	m["winner"] = player_house if win else opponent
	if not win:
		player_alive = false
	_advance()
	save()
	return true


## Deep-copy snapshot of the whole war, safe to mutate.
func bracket_state() -> Dictionary:
	return {
		"player_house": player_house,
		"rivals": rivals.duplicate(),
		"round_names": ROUND_NAMES.duplicate(),
		"rounds": rounds.duplicate(true),
		"champion": champion,
		"player_alive": player_alive,
		"complete": is_over(),
	}


func is_champion() -> bool:
	return not champion.is_empty() and champion == player_house


func is_over() -> bool:
	return not champion.is_empty()


# -- internals --------------------------------------------------------------


func _build_bracket() -> void:
	rounds = [
		[_match(rivals[6], rivals[7])],
		[
			_match(player_house, ""),  # awaits the play-in winner
			_match(rivals[0], rivals[5]),
			_match(rivals[1], rivals[4]),
			_match(rivals[2], rivals[3]),
		],
		[_match("", ""), _match("", "")],
		[_match("", "")],
	]


static func _match(a: String, b: String) -> Dictionary:
	return {"a": a, "b": b, "winner": ""}


func _player_pending_match() -> Dictionary:
	if is_over() or not player_alive:
		return {}
	for round_matches: Array in rounds:
		for m: Dictionary in round_matches:
			if str(m["winner"]).is_empty() \
					and (str(m["a"]) == player_house or str(m["b"]) == player_house):
				return m
	return {}


## Resolve everything that can resolve without the player: simulate
## rival-vs-rival matches, feed winners forward, crown a champion when the
## final is decided. Stops at the player's next undecided match.
func _advance() -> void:
	for r in rounds.size():
		for i in (rounds[r] as Array).size():
			var m: Dictionary = rounds[r][i]
			if str(m["winner"]).is_empty():
				if str(m["a"]).is_empty() or str(m["b"]).is_empty():
					return  # awaiting a feed that can't exist yet — bug guard
				if str(m["a"]) == player_house or str(m["b"]) == player_house:
					return  # the player's fight — wait for report_result
				m["winner"] = _sim_winner(str(m["a"]), str(m["b"]))
			_feed(r, i, str(m["winner"]))


func _feed(r: int, i: int, winner: String) -> void:
	if r == 0:
		rounds[1][0]["b"] = winner        # play-in winner meets the player
	elif r < rounds.size() - 1:
		@warning_ignore("integer_division")
		var m: Dictionary = rounds[r + 1][i / 2]
		if i % 2 == 0:
			m["a"] = winner
		else:
			m["b"] = winner
	else:
		champion = winner


## Deterministic simulation: the better seed (lower rivals[] index) advances.
func _sim_winner(a: String, b: String) -> String:
	return a if rivals.find(a) < rivals.find(b) else b


func _to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"player_house": player_house,
		"rivals": rivals,
		"rounds": rounds,
		"champion": champion,
		"player_alive": player_alive,
	}
