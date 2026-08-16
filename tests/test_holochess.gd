extends SceneTree
## Headless unit test suite for HoloChessGamification engine.

const HoloChessScript := preload("res://src/cinematics/holochess_gamification.gd")

var passed := 0
var failed := 0


func _init() -> void:
	print("\n=== Great Hauses — HoloChess Gamification Unit Suite ===")
	_test_sound_synthesis()
	_test_combo_and_badges()
	_test_projector_pylons()
	_test_living_idles()
	print("---")
	if failed == 0:
		print("HOLOCHESS OK — all %d checks passed" % passed)
		quit(0)
	else:
		print("HOLOCHESS FAILED — %d of %d checks failed" % [failed, passed + failed])
		quit(1)


func check(desc: String, expected, got) -> void:
	if expected == got:
		passed += 1
		print("PASS %s (expected %s, got %s)" % [desc, str(expected), str(got)])
	else:
		failed += 1
		print("FAIL %s (expected %s, got %s)" % [desc, str(expected), str(got)])


func _test_sound_synthesis() -> void:
	var startup := HoloChessScript.get_holo_startup_stream()
	check("startup: stream synthesized", true, startup != null)
	check("startup: format 16-bit", AudioStreamWAV.FORMAT_16_BITS, startup.format)
	check("startup: has audio buffer", true, startup.data.size() > 500)

	var roar := HoloChessScript.get_alien_roar_stream()
	check("roar: stream synthesized", true, roar != null)
	check("roar: has audio buffer", true, roar.data.size() > 500)

	var pop := HoloChessScript.get_badge_pop_stream()
	check("pop: stream synthesized", true, pop != null)
	check("pop: has audio buffer", true, pop.data.size() > 200)


func _test_combo_and_badges() -> void:
	var hc = HoloChessScript.new()
	root.add_child(hc)

	check("combo: starts at 0", 0, hc.combo_streak)

	# 1st capture: Tier 0
	hc.record_capture(0, "Pawn", "Pawn", Vector3(0, 0, 0))
	check("combo: streak is 1", 1, hc.combo_streak)

	# 2nd capture within window: Tier 1
	hc.record_capture(1, "Knight", "Bishop", Vector3(1, 0, 1))
	check("combo: streak is 2", 2, hc.combo_streak)

	# 3rd capture within window: Tier 2 Showstopper
	hc.record_capture(2, "Queen", "Queen", Vector3(2, 0, 2))
	check("combo: streak is 3", 3, hc.combo_streak)

	hc.queue_free()


func _test_projector_pylons() -> void:
	var hc = HoloChessScript.new()
	var dummy_board := Node3D.new()
	root.add_child(dummy_board)
	root.add_child(hc)

	check("holo: initially inactive", false, hc.is_holochess_active)

	var active := hc.toggle_holochess_mode(dummy_board)
	check("holo: now active", true, active)
	check("holo: projector root created", true, dummy_board.has_node("HoloProjectorRoot"))

	var proj_root: Node3D = dummy_board.get_node("HoloProjectorRoot")
	check("holo: 4 projector corner pylons built", 4, proj_root.get_child_count())

	var inactive := hc.toggle_holochess_mode(dummy_board)
	check("holo: toggled off", false, inactive)
	check("holo: projector root freed", false, dummy_board.has_node("HoloProjectorRoot"))

	hc.queue_free()
	dummy_board.queue_free()


func _test_living_idles() -> void:
	var hc = HoloChessScript.new()
	root.add_child(hc)

	var dummy_piece := Node3D.new()
	var mesh_root := Node3D.new()
	mesh_root.name = "MeshRoot"
	dummy_piece.add_child(mesh_root)
	root.add_child(dummy_piece)

	hc.register_piece(dummy_piece)
	check("idles: piece registered", true, hc._piece_phases.has(dummy_piece))

	hc._update_living_idles(0.016)
	check("idles: phase advanced", true, hc._piece_phases.get(dummy_piece, 0.0) > 0.0)

	hc.unregister_piece(dummy_piece)
	check("idles: piece unregistered", false, hc._piece_phases.has(dummy_piece))

	dummy_piece.queue_free()
	hc.queue_free()
