class_name OrbitCamera
extends Node3D
## Chessmaster-style orbit rig. This node is the pivot (sits near board
## center); the child Camera3D is pushed back along local +Z and looks at
## the pivot. Right-drag orbits, mouse wheel zooms, everything lerps.

@export var target_distance := 11.5
@export var min_distance := 3.5
## Expanded distance & pitch bounds for the soaring Sanctum Gothic Cathedral
@export var max_distance := 26.0
@export var yaw := PI            ## radians; PI = behind the Frost side
@export var pitch := -0.85       ## radians; negative looks down at the board
@export var min_pitch := -1.52   ## Near vertical top-down view
@export var max_pitch := 0.45    ## Look up into soaring vaults and rose window
@export var orbit_sensitivity := 0.008
@export var zoom_step := 1.12
## A two-finger drag moves in screen POINTS like the mouse does, so it wants
## roughly the mouse's sensitivity — a little lower, because a thumb is
## coarser than a cursor and an over-eager camera on a tablet feels broken.
const TOUCH_ORBIT_GAIN := 0.85
## Below this the pinch is finger jitter, not intent.
const PINCH_DEADZONE := 2.0

var _touches: Dictionary = {}          ## finger index -> last known position
var _prev_centroid := Vector2.ZERO
var _prev_spread := 0.0
var _two_finger_ready := false
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
		_orbit_by(event.relative)
	# ── TOUCH ──────────────────────────────────────────────────────────────
	# A finger has no right button and no wheel, so on an iPad the camera was
	# simply immovable: right-drag orbits and the wheel zooms, and a
	# touchscreen offers neither.
	#
	# THE FIRST FIX DID NOT WORK ON THE DEVICE, and Albert found that in one
	# game: it listened for InputEventPanGesture / InputEventMagnifyGesture,
	# which are TRACKPAD events. Godot 4.7 has no
	# `input_devices/pointing/ios/enable_pan_and_scale_gestures` setting at
	# all — the probe says the property does not exist — so on iOS those
	# events are never generated and the handler was dead code that read like
	# a feature.
	#
	# Raw touches are the honest primitive: track every finger, and when
	# EXACTLY TWO are down, their centroid moving is an orbit and the
	# distance between them changing is a zoom. That works on any touch
	# device and depends on no engine setting. A ONE-finger drag is still
	# deliberately untouched — it is how the board is played, and stealing it
	# to move the camera would make the game unplayable to fix the camera.
	elif event is InputEventScreenTouch:
		if event.pressed:
			# A finger we already think is DOWN pressing again, or a third
			# joining, means a release went missing — a Control swallowed it,
			# or the app lost focus mid-gesture. Phantom fingers are worse
			# than a dropped gesture: they make a ONE-finger drag orbit the
			# board while the player is trying to play. Flush and start over.
			if _touches.has(event.index) or _touches.size() >= 2:
				_touches.clear()
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		_two_finger_ready = false      # re-baseline on the next drag
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		_two_finger_update()


## Two fingers: the pair's CENTRE moving is an orbit, the gap between them
## changing is a zoom. Both come off the same event, which is why a pinch
## that also slides orbits at the same time — as it should.
func _two_finger_update() -> void:
	if _touches.size() != 2:
		_two_finger_ready = false
		return
	var pts: Array = _touches.values()
	var a: Vector2 = pts[0]
	var b: Vector2 = pts[1]
	var centroid := (a + b) * 0.5
	var spread := a.distance_to(b)
	if not _two_finger_ready:
		# first frame of this pair: take a baseline, do not jump the camera
		_prev_centroid = centroid
		_prev_spread = spread
		_two_finger_ready = true
		return
	_orbit_by((centroid - _prev_centroid) * TOUCH_ORBIT_GAIN)
	if _prev_spread > PINCH_DEADZONE and absf(spread - _prev_spread) > PINCH_DEADZONE:
		# fingers spreading (ratio > 1) brings the board CLOSER
		target_distance = clampf(target_distance * (_prev_spread / spread),
			min_distance, max_distance)
	_prev_centroid = centroid
	_prev_spread = spread


## Shared by mouse drag and two-finger pan so the two can never drift apart.
func _orbit_by(delta_px: Vector2) -> void:
	_target_yaw = wrapf(_target_yaw - delta_px.x * orbit_sensitivity, -PI, PI)
	_target_pitch = clampf(
		_target_pitch - delta_px.y * orbit_sensitivity, min_pitch, max_pitch
	)


func _process(delta: float) -> void:
	_apply(1.0 - exp(-lerp_speed * delta))


func _apply(weight: float) -> void:
	yaw = lerp_angle(yaw, _target_yaw, weight)
	pitch = lerpf(pitch, _target_pitch, weight)
	_distance = lerpf(_distance, target_distance, weight)
	rotation = Vector3(pitch, yaw, 0.0)
	_camera.position = Vector3(0.0, 0.0, _distance)
