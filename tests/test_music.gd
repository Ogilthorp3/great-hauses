extends SceneTree

# Headless test suite for the music module (src/audio/).
# Run: /Applications/Godot.app/Contents/MacOS/Godot --headless --path <project> -s res://tests/test_music.gd
# Exit code 0 = all green, 1 = failures.
#
# Uses its own settings file (user://settings_test_music.json) so a real
# player profile is never touched, and removes it when done.

const MM := preload("res://src/audio/music_manager.gd")
const MC := preload("res://src/audio/credits.gd")

const TEST_SETTINGS := "user://settings_test_music.json"

var rows := []
var failures := 0
var _mark := 0


func _initialize() -> void:
	_main()


func _main() -> void:
	print("=== Great Houses Music — headless test suite ===")
	_mark = Time.get_ticks_msec()
	_cleanup_settings()
	_test_playlists_and_files()
	_test_loop_flags()
	var manager: MusicManager = await _make_manager()
	_test_instantiation(manager)
	_test_modes_and_decks(manager)
	_test_sting(manager)
	_test_duck_math(manager)
	_test_game_end(manager)
	_test_volume_math()
	await _test_settings_roundtrip(manager)
	await _test_mute_and_m_key()
	_test_credits()
	_cleanup_settings()
	_print_summary()


## Helpers ##

func check(test_name: String, expected, actual) -> void:
	var now := Time.get_ticks_msec()
	var ms := now - _mark
	_mark = now
	var ok := str(expected) == str(actual)
	if not ok:
		failures += 1
	rows.push_back([test_name, str(expected), str(actual), ok, ms])


func _make_manager() -> MusicManager:
	var m: MusicManager = MM.new()
	m.settings_path = TEST_SETTINGS
	root.add_child(m)
	if not m.is_inside_tree():
		# During _initialize the root hasn't entered the tree yet — one frame
		# later the pending child gets ENTER_TREE + _ready.
		await process_frame
	return m


func _all_tracks() -> Array:
	var all := []
	all.append_array(MM.MENU_TRACKS)
	all.append_array(MM.GAME_TRACKS)
	all.append_array(MM.STING_TRACKS)
	all.append_array([MM.VICTORY_TRACK, MM.DEFEAT_TRACK, MM.CHAMPIONSHIP_TRACK])
	return all


func _cleanup_settings() -> void:
	if FileAccess.file_exists(TEST_SETTINGS):
		DirAccess.remove_absolute(TEST_SETTINGS)


## Tests ##

func _test_playlists_and_files() -> void:
	check("playlist: menu has 2 tracks", 2, MM.MENU_TRACKS.size())
	check("playlist: game has 3 tracks", 3, MM.GAME_TRACKS.size())
	check("playlist: 2 duel stingers", 2, MM.STING_TRACKS.size())
	check("playlist: 10 unique tracks total", 10, _all_tracks().size())
	for path in _all_tracks():
		var short: String = path.get_file()
		check("file exists: %s" % short, true, ResourceLoader.exists(path))
		var stream := load(path) as AudioStream
		check("imports as AudioStream: %s" % short, true, stream != null)
		if stream != null:
			check("has duration: %s" % short, true, stream.get_length() > 1.0)


func _test_loop_flags() -> void:
	# Gameplay tracks import-loop (never a silent hall); one-shots don't.
	for path in MM.GAME_TRACKS:
		var stream = load(path)
		check("loop=true baked: %s" % path.get_file(), true, stream.loop)
	var one_shots := []
	one_shots.append_array(MM.MENU_TRACKS)
	one_shots.append_array(MM.STING_TRACKS)
	one_shots.append_array([MM.VICTORY_TRACK, MM.DEFEAT_TRACK, MM.CHAMPIONSHIP_TRACK])
	for path in one_shots:
		var stream = load(path)
		check("loop=false baked: %s" % path.get_file(), false, stream.loop)


func _test_instantiation(manager: MusicManager) -> void:
	check("manager: in tree", true, manager.is_inside_tree())
	check("manager: survives pause", Node.PROCESS_MODE_ALWAYS, manager.process_mode)
	check("manager: Music bus created", true, AudioServer.get_bus_index("Music") != -1)
	check("manager: default volume 70", 70, manager.get_volume())
	check("manager: starts unmuted", false, manager.is_muted())
	check("manager: idle mode", "", manager.current_mode())
	check("manager: decks on Music bus", "Music", manager.live_deck().bus)
	check("manager: sting on Music bus", "Music", manager.sting_player().bus)


func _test_modes_and_decks(manager: MusicManager) -> void:
	manager.play_menu()
	check("menu: mode set", "menu", manager.current_mode())
	check("menu: deck playing", true, manager.live_deck().playing)
	check("menu: track from menu playlist", true,
			MM.MENU_TRACKS.has(manager.live_deck().stream.resource_path))
	var menu_deck := manager.live_deck()
	manager.play_game()
	check("game: mode set", "game", manager.current_mode())
	check("game: deck swapped (crossfade pair)", false, manager.live_deck() == menu_deck)
	check("game: deck playing", true, manager.live_deck().playing)
	check("game: track from game playlist", true,
			MM.GAME_TRACKS.has(manager.live_deck().stream.resource_path))
	var deck_before := manager.live_deck()
	var track_before: String = deck_before.stream.resource_path
	manager.play_game()   # idempotent — same mode must not restart/reshuffle
	check("game: play_game idempotent (mode)", "game", manager.current_mode())
	check("game: play_game idempotent (deck)", true,
			manager.live_deck() == deck_before
			and manager.live_deck().stream.resource_path == track_before)


func _test_sting(manager: MusicManager) -> void:
	manager.sting_duel()
	check("sting: player playing", true, manager.sting_player().playing)
	check("sting: from sting list", true,
			MM.STING_TRACKS.has(manager.sting_player().stream.resource_path))
	check("sting: full volume over music", 0.0, manager.sting_player().volume_db)
	check("sting: gameplay deck still playing", true, manager.live_deck().playing)


func _test_duck_math(manager: MusicManager) -> void:
	check("duck: starts level", 0.0, manager.playlist_level_db())
	check("duck: starts unducked", false, manager.is_ducked())
	manager.duck()
	check("duck: DUCK_DB is -8", -8.0, MM.DUCK_DB)
	check("duck: level target -8 dB", MM.DUCK_DB, manager.playlist_level_db())
	check("duck: is_ducked", true, manager.is_ducked())
	manager.duck()   # idempotent — no double-dip
	check("duck: idempotent at -8", MM.DUCK_DB, manager.playlist_level_db())
	manager.unduck()
	check("duck: unduck restores 0 dB", 0.0, manager.playlist_level_db())
	check("duck: unducked flag", false, manager.is_ducked())


func _test_game_end(manager: MusicManager) -> void:
	manager.game_over(true)
	check("victory: mode over", "over", manager.current_mode())
	check("victory: fanfare playing", true, manager.fanfare_player().playing)
	check("victory: RandomMind theme", MM.VICTORY_TRACK,
			manager.fanfare_player().stream.resource_path)
	manager.play_game()
	manager.game_over(false)
	check("defeat: Agnus Dei X", MM.DEFEAT_TRACK,
			manager.fanfare_player().stream.resource_path)
	manager.play_game()
	manager.championship()
	check("championship: Fanfare for Space", MM.CHAMPIONSHIP_TRACK,
			manager.fanfare_player().stream.resource_path)
	manager.stop_all(0.0)
	check("stop_all: mode cleared", "", manager.current_mode())
	check("stop_all: deck stopped", false, manager.live_deck().playing)
	check("stop_all: fanfare stopped", false, manager.fanfare_player().playing)


func _test_volume_math() -> void:
	check("volume: 100 -> 0 dB", 0.0, MM.volume_to_db(100))
	check("volume: 0 -> silence floor", -60.0, MM.volume_to_db(0))
	var db70 := MM.volume_to_db(70)
	check("volume: 70 ~ -3.1 dB", true, absf(db70 - (-3.098)) < 0.01)
	check("volume: monotonic 30<80", true, MM.volume_to_db(30) < MM.volume_to_db(80))


func _test_settings_roundtrip(manager: MusicManager) -> void:
	# Seed a foreign key first — the manager must merge, never clobber.
	var f := FileAccess.open(TEST_SETTINGS, FileAccess.WRITE)
	f.store_string(JSON.stringify({"graphics_quality": "high"}))
	f.close()
	manager.set_volume(42)
	manager.set_muted(true)
	var g := FileAccess.open(TEST_SETTINGS, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(g.get_as_text())
	g.close()
	check("settings: volume persisted", 42, int(data.get("music_volume", -1)))
	check("settings: mute persisted", true, bool(data.get("music_muted", false)))
	check("settings: foreign key preserved", "high", data.get("graphics_quality", ""))
	var reloaded: MusicManager = await _make_manager()
	check("settings: volume round-trips", 42, reloaded.get_volume())
	check("settings: mute round-trips", true, reloaded.is_muted())
	reloaded.queue_free()
	manager.set_muted(false)
	manager.set_volume(70)


func _test_mute_and_m_key() -> void:
	var manager: MusicManager = await _make_manager()
	check("mute: starts from saved state", false, manager.is_muted())
	manager.toggle_mute()
	check("mute: toggle on", true, manager.is_muted())
	check("mute: bus muted", true,
			AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")))
	var m_key := InputEventKey.new()
	m_key.keycode = KEY_M
	m_key.pressed = true
	manager._unhandled_key_input(m_key)
	check("mute: M key toggles off", false, manager.is_muted())
	check("mute: bus unmuted", false,
			AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")))
	var cmd_m := InputEventKey.new()
	cmd_m.keycode = KEY_M
	cmd_m.pressed = true
	cmd_m.meta_pressed = true
	manager._unhandled_key_input(cmd_m)
	check("mute: Cmd+M ignored", false, manager.is_muted())
	manager.queue_free()


func _test_credits() -> void:
	var text := MC.get_credits_text()
	check("credits: non-empty", true, text.length() > 100)
	check("credits: mentions Kevin MacLeod", true, text.contains("Kevin MacLeod"))
	check("credits: mentions CC BY", true, text.contains("CC BY"))
	check("credits: attribution license line", true,
			text.contains("Creative Commons: By Attribution 4.0"))
	check("credits: stinger author credited", true, text.contains("Thor Arisland"))
	var short := MC.get_credits_short()
	check("credits: short non-empty", true, short.length() > 20)
	check("credits: short mentions MacLeod + CC BY", true,
			short.contains("Kevin MacLeod") and short.contains("CC BY"))
	check("credits: short is one line", false, short.contains("\n"))


## Reporting ##

func _short(s: String, width: int) -> String:
	if s.length() <= width:
		return s
	return s.substr(0, width - 3) + "..."


func _print_summary() -> void:
	print("")
	print("%-4s %-46s %-22s %-22s %-6s %8s" % ["#", "Test", "Expected", "Actual", "Pass", "ms"])
	print("-".repeat(112))
	var i := 1
	for row in rows:
		print("%-4d %-46s %-22s %-22s %-6s %8d" % [i, _short(row[0], 46), _short(row[1], 22),
				_short(row[2], 22), "PASS" if row[3] else "FAIL", row[4]])
		i += 1
	print("-".repeat(112))
	var total := rows.size()
	print("TOTAL: %d  PASSED: %d  FAILED: %d" % [total, total - failures, failures])
	print("RESULT: %s" % ("ALL GREEN" if failures == 0 else "FAILURES PRESENT"))
	quit(1 if failures > 0 else 0)
