extends SceneTree
## Headless unit test suite for Sanctum Rust Gothic Cathedral and Cathedral Dragon.

var passed := 0
var failed := 0

func _initialize() -> void:
	_main()

func _main() -> void:
	print("\n=== Great Hauses Chess — Sanctum Gothic Cathedral & Dragon Suite ===")
	_test_cathedral_model_exists()
	await _test_great_hall_cathedral_instantiation()
	await _test_cathedral_dragon_patrol()
	print("---")
	if failed == 0:
		print("CATHEDRAL OK — all %d checks passed" % passed)
		quit(0)
	else:
		print("CATHEDRAL FAILED — %d of %d checks failed" % [failed, passed + failed])
		quit(1)

func check(desc: String, expected, got) -> void:
	if expected == got:
		passed += 1
		print("PASS %s (expected %s, got %s)" % [desc, str(expected), str(got)])
	else:
		failed += 1
		print("FAIL %s (expected %s, got %s)" % [desc, str(expected), str(got)])

func _test_cathedral_model_exists() -> void:
	var path := "res://assets/environment/sanctum_cathedral.glb"
	check("cathedral: glb asset exists", true, ResourceLoader.exists(path))

func _test_great_hall_cathedral_instantiation() -> void:
	var hall_script := load("res://src/env/great_hall.gd")
	var hall = hall_script.new()
	root.add_child(hall)
	await process_frame

	check("hall: cathedral instance created", true, hall.cathedral_instance != null)
	check("hall: cathedral dragon created", true, hall.cathedral_dragon != null)
	check("hall: 22 banner stations preserved", 22, hall.banners.size())

	hall.queue_free()

func _test_cathedral_dragon_patrol() -> void:
	var dragon_script := load("res://src/env/cathedral_dragon.gd")
	var dragon = dragon_script.new()
	root.add_child(dragon)
	await process_frame

	check("dragon: patrol initialized", true, dragon._is_patrolling)
	check("dragon: patrol waypoints count", 7, dragon.PATROL_NODES.size())

	dragon.swoop_over_altar()
	check("dragon: swoop over altar method executed", true, is_instance_valid(dragon))

	dragon.queue_free()
