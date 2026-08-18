extends SceneTree

func _init() -> void:
	var root_node = Control.new()
	root_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(root_node)
	
	var splash = load("res://src/ui/matchup_splash.gd").new()
	root_node.add_child(splash)
	splash.setup("winterfang", "swiftcrest", {"desc": "A forgiving duel for aspiring commanders (~1200 Elo)"}, "tournament")
	
	# Wait for layout & render 3 frames, then capture
	var timer = 0
	while timer < 10:
		timer += 1
		await process_frame
		
	var img = root.get_texture().get_image()
	img.save_png("/Users/bert/.gemini/antigravity-cli/brain/dc426532-efa9-4364-92c2-5a53db738eb2/inspection/clean_symmetric_vs.png")
	print("[GodotRenderer] Saved clean_symmetric_vs.png successfully!")
	quit()
