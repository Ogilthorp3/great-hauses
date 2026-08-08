extends SceneTree

# Headless unit tests for src/tournament/tournament.gd.
# Run: /Applications/Godot.app/Contents/MacOS/Godot --headless --path <project> \
#          -s res://tests/test_tournament.gd
# Exit code 0 = all green, 1 = failures.

const SAVE := "user://test_tournament.json"

var rows := []
var failures := 0

# Explicit seeds keep expectations readable: h1 = strongest rival … h8 = weakest.
var player := "winterfang"
var seeds := ["h1", "h2", "h3", "h4", "h5", "h6", "h7", "h8"]


func _initialize() -> void:
	print("=== Great Houses — tournament bracket test suite ===")
	Tournament.clear_saved(SAVE)
	_test_seeded_rivals()
	_test_create_and_playin()
	_test_win_path()
	_test_persistence()
	_test_loss_path()
	_test_after_over()
	_test_bad_loads()
	Tournament.clear_saved(SAVE)
	_print_summary()


func check(test_name: String, expected, actual) -> void:
	var ok := str(expected) == str(actual)
	if not ok:
		failures += 1
	rows.push_back([test_name, str(expected), str(actual), ok])


## Tests ##


func _test_seeded_rivals() -> void:
	var r := Tournament.seeded_rivals("winterfang")
	check("seeds: 8 rivals from registry", 8, r.size())
	check("seeds: player excluded", false, r.has("winterfang"))
	check("seeds: registry order kept", "goldclaw", r[0])
	var all_ids := HouseRegistry.house_ids()
	check("seeds: registry has 9 houses", 9, all_ids.size())


func _test_create_and_playin() -> void:
	var t := Tournament.create(player, seeds, SAVE)
	check("create: returns a tournament", true, t != null)
	check("create: 4 rounds", 4, t.bracket_state()["rounds"].size())
	var st := t.bracket_state()
	check("create: play-in is h7 vs h8", "h7h8",
			str(st["rounds"][0][0]["a"]) + str(st["rounds"][0][0]["b"]))
	check("create: play-in auto-resolved to h7", "h7", str(st["rounds"][0][0]["winner"]))
	check("create: QF opponent is play-in winner", "h7", t.current_opponent())
	check("create: not champion yet", false, t.is_champion())
	check("create: not over yet", false, t.is_over())
	check("create: rejects 7 rivals", true, Tournament.create(player, ["a", "b", "c", "d", "e", "f", "g"], SAVE) == null)
	check("create: rejects player among rivals", true, Tournament.create("h1", seeds, SAVE) == null)


func _test_win_path() -> void:
	var t := Tournament.create(player, seeds, SAVE)
	check("win: QF vs h7", "h7", t.current_opponent())
	check("win: QF result accepted", true, t.report_result(true))
	check("win: SF vs h1 (top seed won through)", "h1", t.current_opponent())
	t.report_result(true)
	check("win: final vs h2", "h2", t.current_opponent())
	t.report_result(true)
	check("win: champion is the player", true, t.is_champion())
	check("win: war is over", true, t.is_over())
	check("win: no opponent after the throne", "", t.current_opponent())
	check("win: champion recorded", player, t.bracket_state()["champion"])
	# bracket_state must be a deep copy
	var st := t.bracket_state()
	st["rounds"][3][0]["winner"] = "usurper"
	check("win: bracket_state is a deep copy", player, t.bracket_state()["rounds"][3][0]["winner"])


func _test_persistence() -> void:
	var t := Tournament.create(player, seeds, SAVE)
	t.report_result(true)  # QF won; SF pending
	check("persist: save file exists", true, FileAccess.file_exists(SAVE))
	var loaded := Tournament.load_saved(SAVE)
	check("persist: load returns a tournament", true, loaded != null)
	check("persist: player house survives", player, loaded.player_house)
	check("persist: rivals survive in order", str(seeds), str(loaded.rivals))
	check("persist: mid-war opponent survives", "h1", loaded.current_opponent())
	check("persist: play-in result survives", "h7",
			str(loaded.bracket_state()["rounds"][0][0]["winner"]))
	loaded.report_result(true)
	loaded.report_result(true)
	check("persist: loaded bracket plays to the throne", true, loaded.is_champion())
	var reloaded := Tournament.load_saved(SAVE)
	check("persist: champion survives reload", true, reloaded.is_champion())


func _test_loss_path() -> void:
	var t := Tournament.create(player, seeds, SAVE)
	check("loss: QF result accepted", true, t.report_result(false))
	check("loss: player eliminated", false, t.bracket_state()["player_alive"])
	check("loss: not champion", false, t.is_champion())
	check("loss: war still resolves", true, t.is_over())
	check("loss: top seed takes the throne", "h1", t.bracket_state()["champion"])
	check("loss: no opponent when eliminated", "", t.current_opponent())


func _test_after_over() -> void:
	var t := Tournament.create(player, seeds, SAVE)
	t.report_result(true)
	t.report_result(true)
	t.report_result(true)
	check("over: report after throne is a no-op", false, t.report_result(true))
	check("over: champion unchanged", player, t.bracket_state()["champion"])


func _test_bad_loads() -> void:
	check("load: missing file is null", true, Tournament.load_saved("user://no_such_bracket.json") == null)
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string("{not valid json")
	f = null
	check("load: corrupt file is null", true, Tournament.load_saved(SAVE) == null)
	f = FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 99, "player_house": "x", "rivals": [], "rounds": []}))
	f = null
	check("load: wrong version is null", true, Tournament.load_saved(SAVE) == null)


## Reporting ##


func _print_summary() -> void:
	print("")
	print("%-4s %-44s %-22s %-22s %-6s" % ["#", "Test", "Expected", "Actual", "Pass"])
	print("-".repeat(102))
	var i := 1
	for row in rows:
		print("%-4d %-44s %-22s %-22s %-6s" % [i, _short(row[0], 44), _short(row[1], 22),
				_short(row[2], 22), "PASS" if row[3] else "FAIL"])
		i += 1
	print("-".repeat(102))
	print("TOTAL: %d  PASSED: %d  FAILED: %d" % [rows.size(), rows.size() - failures, failures])
	print("RESULT: %s" % ("ALL GREEN" if failures == 0 else "FAILURES PRESENT"))
	quit(1 if failures > 0 else 0)


func _short(s: String, width: int) -> String:
	if s.length() <= width:
		return s
	return s.substr(0, width - 3) + "..."
