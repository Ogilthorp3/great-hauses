extends SceneTree

func _init() -> void:
	var game_scene = load("res://scenes/game.tscn")
	var game = game_scene.instantiate()
	root.add_child(game)

	var intro = game.get_node_or_null("CathedralCinematicIntro")
	print("[test_cinematic] Intro node: ", intro)

	var out_dir = "/Users/bert/.gemini/antigravity-cli/brain/dc426532-efa9-4364-92c2-5a53db738eb2/inspection"

	# Capture progression
	var times = [0.8, 2.5, 4.8, 7.8, 9.5, 11.5]
	var names = ["cinematic_01_spires", "cinematic_02_portal_dive", "cinematic_03_nave_glide", "cinematic_04_organ_ascent", "cinematic_05_organ_roar", "cinematic_06_board_arrival"]

	for i in range(times.size()):
		var target_t: float = times[i]
		while intro != null and is_instance_valid(intro) and intro._elapsed < target_t:
			await process_frame
		
		# Wait 2 frames for render
		await process_frame
		await process_frame
		
		var img = root.get_texture().get_image()
		var out_path = "%s/%s.png" % [out_dir, names[i]]
		img.save_png(out_path)
		print("[test_cinematic] Captured: ", out_path)

	print("[test_cinematic] Complete!")
	quit()
