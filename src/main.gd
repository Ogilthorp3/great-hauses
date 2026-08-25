extends Node
## Great Hauses — boot flow controller (the project's main scene).
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
const SELECT_3D_SCENE: PackedScene = preload("res://scenes/house_select_3d.tscn")
const OpeningCinematicScript: Script = preload("res://src/cinematics/opening_cinematic.gd")
const MatchupSplashScript: Script = preload("res://src/ui/matchup_splash.gd")
const PROBE_FLAGS := ["--smoke", "--dump-tree", "--env-fps", "--env-banner-test", "--skip-select"]

## Where the last address a player joined is remembered between sessions.
const NET_PREFS_PATH := "user://net_prefs.cfg"
const DEFAULT_NET_HOUSE := "winterfang"

## The in-engine E2E harness. NOT an autoload any more — see
## `_install_e2e_harness` for why, and for the one rule that keeps it honest.
const E2E_DRIVER_PATH := "res://test_e2e/e2e_driver.gd"

var _select: HouseSelect
var _net: NetMatch = null
var _e2e_harness: Node = null


func _ready() -> void:
	if has_node("/root/Diag"):
		get_node("/root/Diag").log_event("BOOT", "Main scene initialized on %s (renderer: %s)" % [OS.get_name(), ProjectSettings.get_setting("rendering/renderer/rendering_method", "default")])
	RenderingServer.set_default_clear_color(Color(0.02, 0.02, 0.02, 1.0))
	_install_e2e_harness()   # FIRST: everything below may be under test
	# visionOS: stand up XR (phase 1) BEFORE any scene is added
	var _xr_log := FileAccess.open("user://xr_debug.log", FileAccess.WRITE)
	if _xr_log:
		_xr_log.store_line("=== XR DIAGNOSTIC LOG ===")
		_xr_log.store_line("timestamp: %s" % Time.get_datetime_string_from_system())
		_xr_log.store_line("OS.get_name(): %s" % OS.get_name())
		_xr_log.store_line("--- Phase 1: XRSession.start() ---")
	var xr := XRSession.start(get_tree())
	if _xr_log:
		_xr_log.store_line("xr.ok: %s" % str(xr.ok))
	if not xr.ok and OS.get_name() == "visionOS":
		push_error("visionOS XR bring-up failed at '%s': %s" % [xr.step, xr.error])

	var args := OS.get_cmdline_user_args()
	var all_args := OS.get_cmdline_args()
	if _wants_network_cmdline(args) or _wants_network_cmdline(all_args):
		_boot_network_from_cmdline.call_deferred(args if not args.is_empty() else all_args)
		return
	for flag in PROBE_FLAGS:
		if args.has(flag) or all_args.has(flag):
			get_tree().change_scene_to_file.call_deferred(GAME_SCENE)
			return

	if xr.ok:
		if _xr_log:
			_xr_log.store_line("--- Launching 3D House Selection ---")
			_xr_log.close()
		var select_3d = SELECT_3D_SCENE.instantiate()
		select_3d.name = "HouseSelect3D"
		add_child(select_3d)
		_select = select_3d.get_node_or_null("SubViewport/HouseSelect")
		Music.play_menu()
		select_3d.selection_complete.connect(_on_selection_complete)
		if _select:
			_select.net_host_requested.connect(_on_net_host_requested)
			_select.net_join_requested.connect(_on_net_join_requested)
			_select.net_cancelled.connect(_on_net_cancelled)
			_select.net_remembered_address(_load_remembered_address())
		_probe_oracle()
		_probe_jedi_council()
		_probe_maester()
		_disable_offline_unreachable()
		return

	if _xr_log:
		_xr_log.close()

	var is_e2e_or_test := _e2e_harness != null
	if not is_e2e_or_test:
		for a in all_args:
			if str(a).begins_with("--e2e") or a in PROBE_FLAGS:
				is_e2e_or_test = true
				break
	if is_e2e_or_test:
		_setup_house_select()
	else:
		if DisplayServer.get_name() != "headless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		var intro = OpeningCinematicScript.new()
		intro.name = "OpeningCinematic"
		add_child(intro)
		intro.cinematic_completed.connect(_setup_house_select)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11 or (event.alt_pressed and event.keycode == KEY_ENTER):
			var cur := DisplayServer.window_get_mode()
			if cur == DisplayServer.WINDOW_MODE_FULLSCREEN or cur == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			get_viewport().set_input_as_handled()


func _setup_house_select() -> void:
	if _select != null:
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
	_probe_jedi_council()
	_probe_maester()
	_disable_offline_unreachable()


# ── The test harness does not ship ────────────────────────────────────────


## THE HARNESS IS NOT PART OF THE GAME (verifier defect P4, 2026-08-09).
##
## `test_e2e/e2e_driver.gd` used to be a project.godot autoload, so a 90 KB .gdc
## of test code was compiled into the shipped Windows pck — dormant without
## `--e2e` flags, but present, and "dormant" is not a reason to hand a player
## your test rig. Release exports now EXCLUDE `test_e2e/**`
## (export_presets.cfg), which means the autoload's target simply would not
## exist in a release build — an autoload that cannot be instantiated is a boot
## error on the player's first launch.
##
## So the driver registers itself HERE instead, under two conditions that a
## release build can never both satisfy: a `--e2e…` flag on the command line,
## AND the file actually being in this build. A player has neither.
##
## ORDERING, which is load-bearing. As an autoload the driver's `_ready` ran
## BEFORE this scene, and two scenarios depend on that: the oracle mocks
## (`oracle-mock`, `oracle-modes`, `undo`) start an HTTP server and point
## `DS4_CHESS_URL` at it, and the offline scenarios point it at a dead port —
## all before anything here builds a Ds4Opponent. The SceneTree root refuses
## children while the main scene is still being set up, so the node can only
## arrive on the next deferred flush; `_wait_for_e2e_harness` is what keeps the
## oracle preflight behind it.
func _install_e2e_harness() -> void:
	var wanted := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--e2e"):
			wanted = true
			break
	if not wanted:
		return
	if not ResourceLoader.exists(E2E_DRIVER_PATH):
		push_warning("an --e2e flag was passed, but this build ships no test "
			+ "harness (test_e2e/** is excluded from release exports)")
		return
	var script: Script = load(E2E_DRIVER_PATH)
	if script == null:
		push_error("could not load the e2e harness at %s" % E2E_DRIVER_PATH)
		return
	var node: Node = script.new()
	node.name = "E2EDriver"
	_e2e_harness = node
	# /root, not this scene: the driver outlives every change_scene it drives.
	get_tree().root.add_child.call_deferred(node)


## Block until the deferred harness above is actually in the tree (its `_ready`
## has run, its mock server is listening, its env vars are set). A no-op — and
## not even one frame — in a normal launch, because `_e2e_harness` is null.
func _wait_for_e2e_harness() -> void:
	if _e2e_harness == null:
		return
	var guard := 0
	while is_instance_valid(_e2e_harness) and not _e2e_harness.is_inside_tree() \
			and guard < 120:
		guard += 1
		await get_tree().process_frame


func _probe_oracle() -> void:
	await _wait_for_e2e_harness()   # the mock oracle must own DS4_CHESS_URL first
	if not is_instance_valid(_select) or not _select.is_inside_tree():
		return
	var probe := Ds4Opponent.new()
	probe.name = "OracleProbe"
	add_child(probe)
	var up: bool = await probe.ping(5.0)
	if is_instance_valid(_select) and _select.is_inside_tree():
		_select.set_opponent_enabled("ds4_oracle", up,
			"" if up else probe.offline_reason)
	probe.queue_free()


func _probe_jedi_council() -> void:
	await _wait_for_e2e_harness()
	if not is_instance_valid(_select) or not _select.is_inside_tree():
		return
	var probe := JediCouncilOpponent.new()
	probe.name = "JediCouncilProbe"
	add_child(probe)
	var up: bool = await probe.ping(4.0)
	if is_instance_valid(_select) and _select.is_inside_tree():
		_select.set_opponent_enabled("jedi_council", up,
			"" if up else probe.offline_reason)
	probe.queue_free()


## THE HAUS IS NOT ON THE ROAD (iOS, 2026-08-18). The Jedi Council seats are
## LAN services on the Mini and the friend match is a direct peer link; an
## iPad on cellular or a hotel network can reach neither. Left enabled they
## do not fail fast — the council awaits five per-seat timeouts before it
## gives up, which reads as a hung game rather than an absent opponent.
##
## They also drag iOS-specific baggage: a plain-HTTP call to a private
## address needs an ATS exception, and any local-network traffic triggers
## the system permission prompt and needs a usage string in Info.plist.
## Rather than ship that half-configured, the iPad build offers the four
## engine tiers — a complete game of chess that needs nothing but the
## device — and says plainly why the others are dark.
func _disable_offline_unreachable() -> void:
	if not OS.has_feature("ios"):
		return
	if not (is_instance_valid(_select) and _select.is_inside_tree()):
		return
	_select.set_opponent_enabled("jedi_council", false,
		"the Council sits in the haus — it cannot be reached from here")
	_select.set_opponent_enabled("network", false,
		"a friend match needs the haus network")


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

	# Determine rival house
	var rival_id: String = Session.rival_house()
	if rival_id.is_empty():
		var all_houses := HouseRegistry.house_ids()
		for hid in all_houses:
			if hid != house_id:
				rival_id = hid
				break
	if rival_id.is_empty():
		rival_id = "pyre"

	var is_e2e_or_test := _e2e_harness != null
	if not is_e2e_or_test:
		for a in OS.get_cmdline_args():
			if str(a).begins_with("--e2e") or a in PROBE_FLAGS:
				is_e2e_or_test = true
				break

	if is_e2e_or_test:
		get_tree().change_scene_to_file(GAME_SCENE)
		return

	var splash: CanvasLayer = MatchupSplashScript.new()
	splash.setup(house_id, rival_id, opp, chosen_mode)
	add_child(splash)

	if _select != null:
		_select.queue_free()
		_select = null


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
	# The lines are for READING OUT; the primary address is what the copy
	# button puts on the clipboard, so a host never spells an IP down a phone
	# digit by digit again (verifier note, 2026-08-09).
	_select.net_share_lines(NetProtocol.share_lines(port), NetProtocol.primary_address(port))


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
