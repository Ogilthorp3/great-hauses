extends Node
## perf_boot.gd — the ONLY reason this scene exists.
##
## The perf harness must be in the tree before the game boots, and it must
## outlive every change_scene the run drives. e2e_driver.gd solves that by
## being installed from src/main.gd; the perf harness deliberately does NOT
## touch main.gd, so it gets its own boot scene instead and is reached with
##     Godot --path <proj> --scene res://test_e2e/perf_boot.tscn
##
## Consequences that matter for honesty:
##   * a normal launch never loads this file, so the harness cannot cost the
##     player a single instruction;
##   * `main.tscn` boots exactly as it always does, one frame later — the
##     measured run is the REAL boot flow, not a rigged one.

const PERF_DRIVER := "res://test_e2e/perf_driver.gd"
const MAIN_SCENE := "res://scenes/main.tscn"


func _ready() -> void:
	var script: Script = load(PERF_DRIVER)
	if script == null:
		push_error("perf harness missing at %s" % PERF_DRIVER)
		get_tree().quit(2)
		return
	var node: Node = script.new()
	node.name = "PerfDriver"
	# /root, not this scene: the driver outlives the swap into main.tscn.
	get_tree().root.add_child.call_deferred(node)
	await get_tree().process_frame
	get_tree().change_scene_to_file(MAIN_SCENE)
