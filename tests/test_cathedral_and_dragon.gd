extends SceneTree
## Headless suite for the Sanctum Cathedral shell (rebuilt 2026-08-17).
##
## Contract under test:
##  * the GLB exists and instantiates under GreatHall;
##  * the shell casts NO shadows (the Sun must reach the board exactly as it
##    did before the cathedral existed) and every mesh carries layer 10, the
##    channel the fly-in's cull-masked WyrmGlow paints;
##  * the Wyrm's Gallery anchor sits above the hall's 11.7 wall crest with a
##    clear sightline to the board over that crest (the perch the fly-in
##    lands on and the spectator's vigil rest);
##  * the ambient patrol dragon is GONE — one wyrm, the spectator;
##  * the hall's 22 banner stations survive the rebuild untouched.

var passed := 0
var failed := 0


func _initialize() -> void:
	_main()


func _main() -> void:
	print("\n=== Great Hauses Chess — Sanctum Cathedral Suite ===")
	_test_cathedral_model_exists()
	await _test_great_hall_cathedral()
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
		print("PASS %s" % desc)
	else:
		failed += 1
		print("FAIL %s (expected %s, got %s)" % [desc, str(expected), str(got)])


func _test_cathedral_model_exists() -> void:
	var path := "res://assets/environment/sanctum_cathedral.glb"
	check("cathedral: glb asset exists", true, ResourceLoader.exists(path))


func _test_great_hall_cathedral() -> void:
	var hall_script := load("res://src/env/great_hall.gd")
	var hall = hall_script.new()
	root.add_child(hall)
	await process_frame

	check("hall: cathedral instance created", true, hall.cathedral_instance != null)
	check("hall: ambient patrol dragon retired", false,
		hall.get("cathedral_dragon") != null)
	check("hall: 22 banner stations preserved", 22, hall.banners.size())

	var meshes: Array = []
	if hall.cathedral_instance != null:
		meshes = hall.cathedral_instance.find_children(
			"*", "MeshInstance3D", true, false)
	check("cathedral: shell has meshes", true, meshes.size() >= 10)
	var all_shadowless := true
	var all_layer10 := true
	for mi in meshes:
		if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			all_shadowless = false
		if (mi.layers & (1 << 9)) == 0:
			all_layer10 = false
	check("cathedral: casts no shadows (Sun reaches the board)", true,
		all_shadowless)
	check("cathedral: meshes carry layer 10 (WyrmGlow channel)", true,
		all_layer10)

	# The gallery anchor: above the hall wall crest (11.7), behind the far
	# wall plane (z > 12), and the board-to-perch sightline clears the crest.
	var g: Vector3 = hall.wyrm_gallery_rest()
	check("gallery: above the wall crest", true, g.y > 11.7)
	check("gallery: behind the far wall", true, g.z > 12.0)
	var body := g + Vector3.UP * 1.5   # the wyrm's mass centre on the ledge
	var crest_y: float = body.y * (12.0 / body.z)
	check("gallery: sightline to the board clears the crest", true,
		crest_y > 11.7)

	hall.queue_free()
