extends Node
## Great Houses — boot flow controller (the project's main scene).
##
## Boots into the Hall of Banners (house select). When the player completes a
## selection, fills Session and swaps to the game scene. Dev/CI probe flags
## (--smoke, --dump-tree, --env-fps, --env-banner-test, --skip-select) bypass
## the select screen and drive game.tscn directly with legacy defaults, so
## every pre-existing probe keeps working unchanged.
##
## DS4-Oracle preflight: pings the oracle endpoint in the background and greys
## the opponent entry out ("the Oracle sleeps") when the tunnel is down.
##
## HEAD-TO-HEAD. This file is the integrator for "Play a Friend": the Hall owns
## the panel, src/net owns the socket, and the two are wired together here.
## The connection is opened while the Hall is still on screen and the NetMatch
## node lives at /root, so it survives the swap into game.tscn.
##
## Head-to-head command line (after "--", used by the two-instance e2e and
## handy for a quick LAN game):
##   --net-host                 host a match on this machine
##   --net-join=<addr[:port]>   join a hosted match
##   --net-port=<n>             port (default 7777)
##   --net-side=white|black|random   the HOST's side (default white)
##   --net-house=<house_id>     which banner this machine flies
##   --e2e-fen=<fen>            HOST only — the position both sides start from

const GAME_SCENE := "res://scenes/game.tscn"
const SELECT_SCENE: PackedScene = preload("res://scenes/house_select.tscn")
const PROBE_FLAGS := ["--smoke", "--dump-tree", "--env-fps", "--env-banner-test", "--skip-select"]

## Where the last address a player joined is remembered between sessions.
const NET_PREFS_PATH := "user://net_prefs.cfg"
const DEFAULT_NET_HOUSE := "winterfang"

var _select: HouseSelect
var _net: NetMatch = null


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if _wants_network_cmdline(args):
		# DEFERRED on purpose: the SceneTree root will not accept a child while
		# the main scene is still being set up, and NetMatch has to live at
		# /root to survive the swap into the match.
		_boot_network_from_cmdline.call_deferred(args)
		return
	for flag in PROBE_FLAGS:
		if args.has(flag):
			get_tree().change_scene_to_file.call_deferred(GAME_SCENE)
			return
	_select = SELECT_SCENE.instantiate()
	_select.name = "HouseSelect"
	add_child(_select)
	Music.play_menu()   # after the probe-flag early return — CI boots stay silent
	_select.selection_complete.connect(_on_selection_complete)
	_select.net_host_requested.connect(_on_net_host_requested)
	_select.net_join_requested.connect(_on_net_join_requested)
	_select.net_cancelled.connect(_on_net_cancelled)
	_select.net_remembered_address(_load_remembered_address())
	_probe_oracle()
	_probe_maester()


func _probe_oracle() -> void:
	var probe := Ds4Opponent.new()
	probe.name = "OracleProbe"
	add_child(probe)
	var up: bool = await probe.ping(5.0)
	if is_instance_valid(_select) and _select.is_inside_tree():
		_select.set_opponent_enabled("ds4_oracle", up,
			"" if up else probe.offline_reason)
	probe.queue_free()


func _probe_maester() -> void:
	## The maester needs Stockfish; without it the entry greys out.
	## (Counseled stays selectable — it degrades to pure at runtime, logged.)
	if UciEngine.find_stockfish().is_empty():
		_select.set_oracle_mode_enabled("maester", false,
			"the Grand Maester is abroad (stockfish not installed)")


func _on_selection_complete(house_id: String, opp: Dictionary, chosen_mode: String) -> void:
	if chosen_mode == "network":
		return   # the network path seats itself in _on_match_ready
	Session.apply_selection(house_id, opp, chosen_mode)
	# Let the "rides to war" banner breathe before the hall doors open.
	await get_tree().create_timer(0.75).timeout
	get_tree().change_scene_to_file(GAME_SCENE)


# ── Head-to-head: the Hall's panel wired to the socket ─────────────────────


func _on_net_host_requested(side: String) -> void:
	var house := _select.selected_house
	var port := _cmdline_port(OS.get_cmdline_user_args())
	_net = _fresh_net()
	if _net == null:
		_select.net_status("could not open a room right now — try again")
		_select.net_release()
		return
	_net.state_changed.connect(_on_net_state_changed)
	_net.match_ready.connect(_on_match_ready.bind(house))
	if not _net.host_match(house, side, port, _cmdline_fen(OS.get_cmdline_user_args())):
		return   # state_changed already carried the reason to the panel
	_select.net_share_lines(NetProtocol.share_lines(port))


func _on_net_join_requested(addr: String) -> void:
	var house := _select.selected_house
	var port := _cmdline_port(OS.get_cmdline_user_args())
	_net = _fresh_net()
	if _net == null:
		_select.net_status("could not dial out right now — try again")
		_select.net_release()
		return
	_net.state_changed.connect(_on_net_state_changed)
	_net.match_ready.connect(_on_match_ready.bind(house))
	if _net.join_match(house, addr, port):
		_save_remembered_address(addr)


func _on_net_cancelled() -> void:
	if _net != null and is_instance_valid(_net):
		_net.shutdown()
	_net = null


func _on_net_state_changed(state: int, why: String) -> void:
	if not is_instance_valid(_select) or not _select.is_inside_tree():
		return
	_select.net_status(why)
	if state == NetMatch.State.FAILED or state == NetMatch.State.CLOSED:
		_select.net_release()   # the player may try again
		_net = null


func _on_match_ready(info: Dictionary, house_id: String) -> void:
	Session.apply_network(info, house_id)
	print("NET MATCH READY role=%s color=%s house=%s rival=%s fen=%s" % [
		Session.net_role, NetProtocol.color_name(Session.net_my_color),
		Session.player_house, Session.net_rival_house,
		Session.net_start_fen if not Session.net_start_fen.is_empty() else "<startpos>"])
	if is_instance_valid(_select) and _select.is_inside_tree():
		_select.net_status("Both banners are raised — riding to the hall…")
		_select.finish_network()
		await get_tree().create_timer(0.6).timeout
	get_tree().change_scene_to_file(GAME_SCENE)


func _fresh_net() -> NetMatch:
	## One live connection at a time: a second Host attempt must not leave the
	## first listening socket bound to the port it is about to ask for.
	var old := NetMatch.get_active(get_tree())
	if old != null:
		old.shutdown()
	return NetMatch.ensure(get_tree())


# ── Head-to-head: the command-line path (two-instance e2e, quick LAN games) ─


func _wants_network_cmdline(args: PackedStringArray) -> bool:
	if args.has("--net-host"):
		return true
	for a in args:
		if a.begins_with("--net-join="):
			return true
	return false


func _boot_network_from_cmdline(args: PackedStringArray) -> void:
	var want_host := args.has("--net-host")
	var join_addr := ""
	var house := DEFAULT_NET_HOUSE
	var side := "white"
	for a in args:
		if a.begins_with("--net-join="):
			join_addr = a.substr(11)
		elif a.begins_with("--net-house="):
			house = a.substr(12)
		elif a.begins_with("--net-side="):
			side = a.substr(11)
	var port := _cmdline_port(args)
	_net = _fresh_net()
	if _net == null:
		push_error("could not open a network match — no NetMatch node")
		return
	_net.state_changed.connect(_print_net_state)
	_net.match_ready.connect(_on_match_ready.bind(house))
	if want_host:
		_net.host_match(house, side, port, _cmdline_fen(args))
	else:
		_join_with_retries(house, join_addr, port)


func _print_net_state(_s: int, why: String) -> void:
	print("NET STATE %s" % why)


## Command-line joiners race the host's boot (two processes launched seconds
## apart), so a first refusal is normal, not fatal: dial again a few times on
## the SAME NetMatch node — its NodePath is what the RPCs resolve through, so
## it must not be rebuilt between attempts. The Hall's Join button does NOT do
## this: a human wants the error, not a silent retry loop.
func _join_with_retries(house: String, addr: String, port: int, attempts := 6) -> void:
	for i in attempts:
		if _net == null or not is_instance_valid(_net):
			return
		_net.join_match(house, addr, port)
		var deadline := Time.get_ticks_msec() \
			+ int((NetProtocol.CONNECT_TIMEOUT_SEC + 2.0) * 1000.0)
		while Time.get_ticks_msec() < deadline:
			if _net == null or not is_instance_valid(_net):
				return
			if _net.state == NetMatch.State.IN_MATCH:
				return
			if _net.state == NetMatch.State.FAILED:
				break
			await get_tree().process_frame
		if _net.state == NetMatch.State.IN_MATCH:
			return
		print("NET STATE retrying the join (%d/%d)" % [i + 1, attempts])
		await get_tree().create_timer(2.0).timeout
	print("NET STATE gave up dialling %s:%d" % [addr, port])


func _cmdline_port(args: PackedStringArray) -> int:
	for a in args:
		if a.begins_with("--net-port="):
			return int(a.substr(11))
	return NetProtocol.DEFAULT_PORT


func _cmdline_fen(args: PackedStringArray) -> String:
	for a in args:
		if a.begins_with("--e2e-fen="):
			return a.substr(10)
	return ""


# ── Remembering the address (the one thing nobody wants to retype) ─────────


func _load_remembered_address() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(NET_PREFS_PATH) != OK:
		return ""
	return str(cfg.get_value("net", "last_address", ""))


func _save_remembered_address(addr: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(NET_PREFS_PATH)   # keep whatever else is in there
	cfg.set_value("net", "last_address", addr)
	cfg.save(NET_PREFS_PATH)
