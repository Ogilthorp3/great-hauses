class_name OrbitCamera
extends Node3D
## Chessmaster-style orbit rig. This node is the pivot (sits near board
## center); the child Camera3D is pushed back along local +Z and looks at
## the pivot. Right-drag orbits, mouse wheel zooms, everything lerps.

@export var target_distance := 11.5
@export var min_distance := 4.0
## Clamped so the camera can never back out through the great hall's walls
## at shallow pitch (env module's framing note: safe ceiling ~13).
@export var max_distance := 13.0
@export var yaw := PI            ## radians; PI = behind the Frost side
@export var pitch := -0.85       ## radians; negative looks down at the board
@export var min_pitch := -1.35
@export var max_pitch := -0.12
@export var orbit_sensitivity := 0.008
@export var zoom_step := 1.12
@export var lerp_speed := 12.0

var _target_yaw := 0.0
var _target_pitch := 0.0
var _distance := 0.0
var _dragging := false

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	_target_yaw = yaw
	_target_pitch = pitch
	_distance = target_distance
	_apply(1.0)  # snap to the starting pose


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				_dragging = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					target_distance = clampf(target_distance / zoom_step, min_distance, max_distance)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					target_distance = clampf(target_distance * zoom_step, min_distance, max_distance)
	elif event is InputEventMouseMotion and _dragging:
		_target_yaw = wrapf(_target_yaw - event.relative.x * orbit_sensitivity, -PI, PI)
		_target_pitch = clampf(
			_target_pitch - event.relative.y * orbit_sensitivity, min_pitch, max_pitch
		)


func _process(delta: float) -> void:
	_apply(1.0 - exp(-lerp_speed * delta))


func _apply(weight: float) -> void:
	yaw = lerp_angle(yaw, _target_yaw, weight)
	pitch = lerpf(pitch, _target_pitch, weight)
	_distance = lerpf(_distance, target_distance, weight)
	rotation = Vector3(pitch, yaw, 0.0)
	_camera.position = Vector3(0.0, 0.0, _distance)
