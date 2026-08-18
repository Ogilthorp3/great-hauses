extends Node
## Capture driver for the cathedral fly-in. Installed by game.gd ONLY under
## `--cine-capture=<abs dir>` (the same runtime-gated pattern as --smoke and
## --dump-tree — the harness never ships in a normal launch). Rides the
## cinematic's own clock, saves a frame at every story beat, then two
## post-handoff gameplay frames showing the vigil wyrm on its gallery.
##
## Run (a real window opens; don't touch input):
##   godot --path . res://scenes/game.tscn -- --cine-capture=/tmp/cine_frames

var out_dir := "/tmp/cine_frames"

const BEATS := [
	[1.8, "01_night_establishing"],
	[4.4, "02_night_dragon_card"],
	[6.8, "03_tower_circle"],
	[9.2, "04_west_front"],
	[11.0, "05_turn_to_the_rose"],
	[12.6, "06_stoop"],
	[14.2, "07_into_the_oculus"],
	[16.0, "08_nave_reveal"],
	[18.0, "09_chandelier_descent"],
	[20.4, "10_board_pass"],
	[22.6, "11_climb_to_gallery"],
	[24.0, "12_landing"],
	[25.2, "13_roar"],
	[27.4, "14_crane_home"],
	[28.8, "15_handoff_seam"],
]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run()


func _run() -> void:
	var intro: Node = get_parent().get_node_or_null("CathedralCinematicIntro")
	print("[capture] intro node: ", intro)
	if intro == null:
		print("[capture] NO INTRO — aborting")
		get_tree().quit(1)
		return
	for beat in BEATS:
		var t: float = beat[0]
		while is_instance_valid(intro) and intro._is_running \
				and intro._elapsed < t:
			await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		_snap("%s.png" % beat[1])
		var measure := "(intro finished)"
		if is_instance_valid(intro):
			measure = _framing(intro)
		print("[capture] %-24s t=%.1f  %s" % [beat[1], t, measure])
		if not is_instance_valid(intro) or not intro._is_running:
			break
	while is_instance_valid(intro) and intro._is_running:
		await get_tree().process_frame
	for i in 30:
		await get_tree().process_frame
	_snap("16_gameplay_after.png")
	print("[capture] 16_gameplay_after")
	for i in 90:
		await get_tree().process_frame
	_snap("17_gameplay_settled.png")
	print("[capture] 17_gameplay_settled")
	print("[capture] COMPLETE")
	get_tree().quit(0)


func _snap(fname: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(fname))


## THE FEATHER MEASURE. How far the lens is standing off, and what share of
## the frame the wyrm actually occupies — the number that decides whether a
## shot "follows from a distance" or rides the beast.
##
## The envelope is the POSED SKELETON, not the mesh AABB: a skinned
## MeshInstance3D reports bounds padded for every deformation the skin can
## reach, which over-reported this creature by roughly 2.5x and flagged shots
## that read perfectly well on the frame. Bone origins are where the animal
## actually is this instant. (Bones sit inside the skin, so the wing membrane
## and tail fin read a little wider than the number — it is a floor, and a
## consistent one.)
##
## Band the shots are tuned to: 0.05 - 0.42 of frame width. The ceiling moved
## up from 0.30 when the wyrm itself grew (rig scale 1.65 -> 2.2, Bert:
## "the Dragon should be bigger than that") — the interior hero beats now sit
## at 0.27-0.36 on purpose, with the architecture still holding the frame
## around them. Above the ceiling the creature is eating the church; below
## the floor it is a speck on the lens. The threading of the oculus is the
## one designed exception at ~0.49: the wyrm is framed INSIDE the rose wheel
## there, and filling that aperture is the shot.
func _framing(intro: Node) -> String:
	var cam: Camera3D = intro.get("_cam")
	var rig: Node3D = intro.get("_dragon_root")
	if cam == null or rig == null or not is_instance_valid(rig):
		return "(no rig)"
	var box := AABB()
	var first := true
	for sk: Skeleton3D in rig.find_children("*", "Skeleton3D", true, false):
		for b in sk.get_bone_count():
			var p: Vector3 = sk.global_transform * sk.get_bone_global_pose(b).origin
			if first:
				box = AABB(p, Vector3.ZERO)
				first = false
			else:
				box = box.expand(p)
	if first:
		for mi: MeshInstance3D in rig.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh == null:
				continue
			var world := mi.global_transform * mi.get_aabb()
			box = world if first else box.merge(world)
			first = false
	if first:
		return "(no rig geometry)"
	var vp := get_viewport().get_visible_rect().size
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var any := false
	for c in 8:
		var corner := box.get_endpoint(c)
		if cam.is_position_behind(corner):
			continue
		var p := cam.unproject_position(corner)
		lo = lo.min(p)
		hi = hi.max(p)
		any = true
	if not any:
		return "off-camera"
	var dist := cam.global_position.distance_to(box.get_center())
	var wf := (hi.x - lo.x) / vp.x
	var hf := (hi.y - lo.y) / vp.y
	var flag := ""
	if wf > 0.42:
		flag = "  <-- TOO CLOSE"
	elif wf < 0.02:
		# The establishing beat rides deliberately near this floor: the
		# feather starts as a speck in a wide sky too.
		flag = "  <-- speck"
	return "dist=%5.1f  frac=%.2fw/%.2fh%s" % [dist, wf, hf, flag]
