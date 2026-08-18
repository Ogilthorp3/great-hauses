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
	[1.5, "01_night_establishing"],
	[3.8, "02_night_dragon_card"],
	[6.5, "03_tower_bank"],
	[8.6, "04_between_spires"],
	[10.3, "05_stoop"],
	[11.7, "06_threading_reveal"],
	[13.5, "07_nave_high"],
	[15.2, "08_chandelier_slalom"],
	[16.9, "09_low_board_pass"],
	[18.8, "10_flare"],
	[20.8, "11_landing"],
	[22.1, "12_roar"],
	[24.3, "13_crane_home"],
	[25.3, "14_handoff_seam"],
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
		print("[capture] %s  (t=%.1f)" % [beat[1], t])
		if not is_instance_valid(intro) or not intro._is_running:
			break
	while is_instance_valid(intro) and intro._is_running:
		await get_tree().process_frame
	for i in 30:
		await get_tree().process_frame
	_snap("15_gameplay_after.png")
	print("[capture] 15_gameplay_after")
	for i in 90:
		await get_tree().process_frame
	_snap("16_gameplay_settled.png")
	print("[capture] 16_gameplay_settled")
	print("[capture] COMPLETE")
	get_tree().quit(0)


func _snap(fname: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(fname))
