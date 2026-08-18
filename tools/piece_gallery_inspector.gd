extends SceneTree

func _init() -> void:
	var root_3d = Node3D.new()
	root.add_child(root_3d)

	var sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.light_energy = 1.4
	sun.basis = Basis.looking_at(Vector3(-0.4, -0.7, -0.6).normalized(), Vector3.UP)
	root_3d.add_child(sun)

	var fill = DirectionalLight3D.new()
	fill.light_color = Color(0.6, 0.7, 0.9)
	fill.light_energy = 0.6
	fill.basis = Basis.looking_at(Vector3(0.5, -0.3, 0.8).normalized(), Vector3.UP)
	root_3d.add_child(fill)

	var cam = Camera3D.new()
	cam.global_position = Vector3(0.0, 2.0, 5.2)
	cam.look_at(Vector3(0.0, 0.6, 0.0), Vector3.UP)
	cam.fov = 44.0
	root_3d.add_child(cam)

	var house_id: String = "winterfang"
	var args = OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--house="):
			house_id = a.trim_prefix("--house=")

	var PieceViewScript = load("res://src/board/piece_view.gd")
	var types = [
		PieceViewScript.Type.PAWN,
		PieceViewScript.Type.KNIGHT,
		PieceViewScript.Type.BISHOP,
		PieceViewScript.Type.ROOK,
		PieceViewScript.Type.QUEEN,
		PieceViewScript.Type.KING
	]

	var spacing: float = 1.05
	var total_w: float = (types.size() - 1) * spacing
	var start_x: float = -total_w * 0.5

	for i in range(types.size()):
		var pv = PieceViewScript.new()
		root_3d.add_child(pv)
		pv.global_position = Vector3(start_x + i * spacing, 0.0, 0.0)
		pv.setup(types[i], 0, house_id)

	var f: int = 0
	while f < 15:
		f += 1
		await process_frame

	var img = root.get_texture().get_image()
	var out_dir = "/Users/bert/.gemini/antigravity-cli/brain/dc426532-efa9-4364-92c2-5a53db738eb2/inspection"
	var out_path = "%s/lineup_%s.png" % [out_dir, house_id]
	img.save_png(out_path)
	print("[PieceGallery] Saved lineup to: ", out_path)
	quit()
