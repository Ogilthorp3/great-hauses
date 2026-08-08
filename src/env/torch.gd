class_name Torch
extends Node3D
## A wall-mounted torch: KayKit bracket mesh + warm OmniLight3D + small
## emissive ember at the flame tip, with a cheap two-sine + noise flicker.
##
## Orientation: the bracket sticks out along this node's LOCAL +Z, so place
## the node on a wall/pillar face with +Z pointing into the room.
##
## All torches share the imported mesh resource (instantiating the same
## PackedScene reuses mesh + material) — only the light is per-instance.

const TORCH_SCENE: PackedScene = preload("res://assets/kaykit-dungeon/torch_mounted.gltf")

@export var base_energy := 2.7
@export var light_color := Color(1.0, 0.58, 0.28)
@export var light_range := 7.5
## Flicker amplitude as a fraction of base_energy (subtle by default).
@export var flicker_amount := 0.1

static var _ember_mesh: SphereMesh  # shared across all torches

var _light: OmniLight3D
var _phase := 0.0
var _time := 0.0
var _wander := 0.0  # slow random-walk component so no two cycles look alike


func _ready() -> void:
	_phase = randf() * TAU
	var model := TORCH_SCENE.instantiate()
	add_child(model)
	# Flame tip of torch_mounted sits ~(0, 0.55, 0.42) in local space.
	var tip := Vector3(0.0, 0.55, 0.42)
	_light = OmniLight3D.new()
	_light.name = "FlameLight"
	_light.light_color = light_color
	_light.light_energy = base_energy
	_light.omni_range = light_range
	_light.omni_attenuation = 1.6
	_light.shadow_enabled = false  # 8+ shadowed omnis would sink mobile perf
	_light.position = tip
	add_child(_light)
	var ember := MeshInstance3D.new()
	ember.name = "Ember"
	if _ember_mesh == null:
		_ember_mesh = SphereMesh.new()
		_ember_mesh.radius = 0.07
		_ember_mesh.height = 0.15
		_ember_mesh.radial_segments = 8
		_ember_mesh.rings = 4
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.62, 0.2)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.5, 0.15)
		m.emission_energy_multiplier = 2.4
		_ember_mesh.material = m
	ember.mesh = _ember_mesh
	ember.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ember.position = tip + Vector3(0.0, 0.04, 0.0)
	add_child(ember)


func _process(delta: float) -> void:
	_time += delta
	# Two incommensurate sines + a bounded random walk: organic, never strobing.
	_wander = clampf(_wander + (randf() - 0.5) * 2.4 * delta, -1.0, 1.0)
	var s := sin(_time * 7.3 + _phase) * 0.6 \
		+ sin(_time * 12.7 + _phase * 1.7) * 0.25 \
		+ _wander * 0.35
	_light.light_energy = base_energy * (1.0 + s * flicker_amount)
