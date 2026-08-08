extends Node
## Great Houses — boot flow controller (the project's main scene).
##
## Boots into the Hall of Banners (house select). When the player completes a
## selection, fills Session and swaps to the game scene. Dev/CI probe flags
## (--smoke, --dump-tree, --env-fps, --env-banner-test, --skip-select) bypass
## the select screen and drive game.tscn directly with legacy defaults, so
## every pre-existing probe keeps working unchanged.
##
## DS4-Oracle preflight: pings the oracle endpoint in the background and greys
## the opponent entry out ("the Oracle sleeps") when the tunnel is down.

const GAME_SCENE := "res://scenes/game.tscn"
const SELECT_SCENE: PackedScene = preload("res://scenes/house_select.tscn")
const PROBE_FLAGS := ["--smoke", "--dump-tree", "--env-fps", "--env-banner-test", "--skip-select"]

var _select: HouseSelect


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for flag in PROBE_FLAGS:
		if args.has(flag):
			get_tree().change_scene_to_file.call_deferred(GAME_SCENE)
			return
	_select = SELECT_SCENE.instantiate()
	_select.name = "HouseSelect"
	add_child(_select)
	_select.selection_complete.connect(_on_selection_complete)
	_probe_oracle()


func _probe_oracle() -> void:
	var probe := Ds4Opponent.new()
	probe.name = "OracleProbe"
	add_child(probe)
	var up: bool = await probe.ping(5.0)
	if is_instance_valid(_select) and _select.is_inside_tree():
		_select.set_opponent_enabled("ds4_oracle", up,
			"" if up else probe.offline_reason)
	probe.queue_free()


func _on_selection_complete(house_id: String, opp: Dictionary, chosen_mode: String) -> void:
	Session.apply_selection(house_id, opp, chosen_mode)
	# Let the "rides to war" banner breathe before the hall doors open.
	await get_tree().create_timer(0.75).timeout
	get_tree().change_scene_to_file(GAME_SCENE)
