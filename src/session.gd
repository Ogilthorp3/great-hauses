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
static var mode := ""                  # "tournament" | "single" | "network"
static var tournament: Tournament = null

## -- head-to-head (mode == "network") -------------------------------------
## Filled by main.gd from NetMatch.match_ready BEFORE the scene swap, so
## game.gd knows which colour it is playing and which banner flies opposite
## before it spawns a single piece. `net_start_fen` lets the HOST's --e2e-fen
## reach the joiner: the host's position is the only position.
static var net_role := ""              # "" | "host" | "join"
static var net_my_color := false       # false = White (ChessState convention)
static var net_rival_house := ""
static var net_start_fen := ""


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


## Seat both players for a head-to-head match. `info` is NetMatch's
## `match_ready` payload — the HOST's seating chart, which both machines
## adopt verbatim so there is exactly one answer to "who is White".
static func apply_network(info: Dictionary, house_id: String) -> void:
	player_house = house_id
	net_my_color = bool(info.get("your_color", false))
	net_rival_house = str(info.get("their_house", ""))
	net_start_fen = str(info.get("fen", ""))
	net_role = "host" if bool(info.get("is_host", false)) else "join"
	opponent = {
		"kind": "network",
		"level": "friend",
		"label": "A Friend — %s" % ("hosting" if net_role == "host" else "joined"),
	}
	mode = "network"
	tournament = null
	configured = true


static func is_network() -> bool:
	return configured and mode == "network"


## The house the player faces in the CURRENT match ("" only if a finished
## tournament leaked through — callers fall back to the first seeded rival).
static func rival_house() -> String:
	if not configured:
		return ""
	if mode == "network":
		return net_rival_house
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
	net_role = ""
	net_my_color = false
	net_rival_house = ""
	net_start_fen = ""
