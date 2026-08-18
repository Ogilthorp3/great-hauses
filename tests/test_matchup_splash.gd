extends SceneTree
## Headless unit test suite for Matchup Versus Loading Splash Screen.

var passed := 0
var failed := 0

func _initialize() -> void:
	_main()

func _main() -> void:
	print("\n=== Great Hauses Chess — Matchup Versus Splash Screen Suite ===")
	await _test_matchup_splash_instantiation()
	print("---")
	if failed == 0:
		print("SPLASH SCREEN OK — all %d checks passed" % passed)
		quit(0)
	else:
		print("SPLASH SCREEN FAILED — %d of %d checks failed" % [failed, passed + failed])
		quit(1)

func check(desc: String, expected, got) -> void:
	if expected == got:
		passed += 1
		print("PASS %s (expected %s, got %s)" % [desc, str(expected), str(got)])
	else:
		failed += 1
		print("FAIL %s (expected %s, got %s)" % [desc, str(expected), str(got)])

func _test_matchup_splash_instantiation() -> void:
	var splash_script := load("res://src/ui/matchup_splash.gd")
	var splash = splash_script.new()
	splash.setup("winterfang", "pyre", {"label": "Seasoned Tactician"}, "tournament")
	root.add_child(splash)
	await process_frame

	check("splash: node created and added to tree", true, is_instance_valid(splash))
	check("splash: player house is winterfang", "winterfang", splash._player_house_id)
	check("splash: rival house is pyre", "pyre", splash._rival_house_id)
	check("splash: loading bar created", true, splash._loading_bar != null)
	check("splash: status label exists", true, splash._status_label != null)

	splash.queue_free()
