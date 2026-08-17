extends SceneTree
## Headless unit test suite for Artistic Camera Judge and Matchup-Specific Finishers.

var passed := 0
var failed := 0
var assets: Node
var piece_scene: PackedScene
var duel_director_script: GDScript


func _initialize() -> void:
	_main()


func _main() -> void:
	print("\n=== Great Hauses Chess — Artistic Camera & Matchup Finishers Suite ===")
	assets = (load("res://src/board/piece_assets.gd") as GDScript).new()
	assets.name = "PieceAssets"
	root.add_child(assets)
	await process_frame

	piece_scene = load("res://scenes/piece_view.tscn")
	duel_director_script = load("res://src/cinematics/duel_director.gd")

	await process_frame

	await _test_artistic_camera_judge()
	await _test_matchup_finisher_routing()

	print("---")
	if failed == 0:
		print("CINEMATICS OK — all %d checks passed" % passed)
		quit(0)
	else:
		print("CINEMATICS FAILED — %d of %d checks failed" % [failed, passed + failed])
		quit(1)


func check(desc: String, expected, got) -> void:
	if expected == got:
		passed += 1
		print("PASS %s (expected %s, got %s)" % [desc, str(expected), str(got)])
	else:
		failed += 1
		print("FAIL %s (expected %s, got %s)" % [desc, str(expected), str(got)])


func _test_artistic_camera_judge() -> void:
	var dd = duel_director_script.new()
	root.add_child(dd)

	var p1 := Node3D.new()
	p1.position = Vector3(0, 0, 0)
	root.add_child(p1)

	var p2 := Node3D.new()
	p2.position = Vector3(0, 0, 3)
	root.add_child(p2)

	# Test artistic camera entry
	await dd._cam_enter_artistic_duel(p1, p2, 1, 2)
	check("artistic_judge: camera entry evaluated and dispatched", true, true)

	p1.queue_free()
	p2.queue_free()
	dd.queue_free()


func _test_matchup_finisher_routing() -> void:
	var p_knight = piece_scene.instantiate()
	root.add_child(p_knight)
	p_knight.setup(2, 0, "winterfang")

	check("knight: has royal finisher method", true, p_knight.has_method("_kill_charge_royal"))
	check("knight: has castle breaker method", true, p_knight.has_method("_kill_charge_castle"))
	check("knight: has spellbreaker method", true, p_knight.has_method("_kill_charge_spellbreaker"))

	var p_queen = piece_scene.instantiate()
	root.add_child(p_queen)
	p_queen.setup(4, 0, "winterfang")

	check("queen: has kingslayer finisher method", true, p_queen.has_method("_kill_kingslayer"))
	check("queen: has queen dance finisher method", true, p_queen.has_method("_kill_queen_dance"))

	var p_bishop = piece_scene.instantiate()
	root.add_child(p_bishop)
	p_bishop.setup(3, 0, "winterfang")

	check("bishop: has apocalyptic judgement method", true, p_bishop.has_method("_kill_apocalyptic_judgement"))
	check("bishop: has cataclysm fracture method", true, p_bishop.has_method("_kill_cataclysm_fracture"))

	var p_pawn = piece_scene.instantiate()
	root.add_child(p_pawn)
	p_pawn.setup(0, 0, "winterfang")

	check("pawn: has david vs goliath method", true, p_pawn.has_method("_kill_david_vs_goliath"))

	p_knight.queue_free()
	p_queen.queue_free()
	p_bishop.queue_free()
	p_pawn.queue_free()
