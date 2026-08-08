class_name Session
extends RefCounted
## Cross-scene carrier for the player's choices — static, no autoload.
##
## main.gd fills it from the Hall of Banners (house select) and game.gd reads
## it on every match start. Statics survive change_scene, so the tournament
## bracket rides along between rounds. Plain data + one RefCounted
## (Tournament) only — no Resources (see piece_assets.gd shutdown note).

static var configured := false
static var player_house := ""
static var opponent: Dictionary = {}   # HouseSelect opponent Dictionary shape
static var mode := ""                  # "tournament" | "single"
static var tournament: Tournament = null


static func apply_selection(house_id: String, opp: Dictionary, chosen_mode: String) -> void:
	player_house = house_id
	opponent = opp.duplicate()
	mode = chosen_mode
	configured = true
	if mode == "tournament":
		var t := Tournament.load_saved()
		if t == null or t.is_over() or t.player_house != house_id:
			Tournament.clear_saved()
			t = Tournament.create(house_id)
		tournament = t
	else:
		tournament = null


## The house the player faces in the CURRENT match ("" only if a finished
## tournament leaked through — callers fall back to the first seeded rival).
static func rival_house() -> String:
	if not configured:
		return ""
	if mode == "tournament" and tournament != null:
		return tournament.current_opponent()
	var rivals := Tournament.seeded_rivals(player_house)
	return rivals[0] if not rivals.is_empty() else ""


static func reset() -> void:
	configured = false
	player_house = ""
	opponent = {}
	mode = ""
	tournament = null
