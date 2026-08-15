class_name HouseSelect3D
extends Node3D
## HouseSelect3D — 3D Immersive Hall of Banners for visionOS / XR.
##
## Hosts the 2D HouseSelect inside a high-resolution SubViewport and projects
## it onto a 3D curved panel floating in front of the player. Forwards spatial
## pinch / gaze / touch / keyboard events to the UI and routes selection_complete
## into Session and game.tscn.

signal selection_complete(house_id: String, opponent: Dictionary, mode: String)

@onready var origin: XROrigin3D = $XROrigin3D
@onready var camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var viewport: SubViewport = $SubViewport
@onready var panel_mesh: MeshInstance3D = $PanelMesh
@onready var house_select: HouseSelect = $SubViewport/HouseSelect

var _quad_size := Vector2(2.56, 1.44)
var _last_press_pos := Vector2.ZERO


func _ready() -> void:
	if OS.get_name() == "visionOS" or XRServer.primary_interface != null:
		origin.current = true
		camera.current = true

	# Wire SubViewport material override
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = viewport.get_texture()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	panel_mesh.material_override = mat

	# Connect signals from embedded HouseSelect
	house_select.selection_complete.connect(_on_selection_complete)
	house_select.house_chosen.connect(_on_house_chosen)


var _frame_count := 0

func _process(_delta: float) -> void:
	_frame_count += 1
	if _frame_count % 30 == 0 and is_instance_valid(viewport):
		var img := viewport.get_texture().get_image()
		if img:
			img.save_png("user://screenshot_latest.png")


func _on_house_chosen(house_id: String) -> void:
	# Preview house colors / sound
	pass


func _on_selection_complete(house_id: String, opp: Dictionary, mode: String) -> void:
	selection_complete.emit(house_id, opp, mode)


func _unhandled_input(event: InputEvent) -> void:
	# Forward visionOS gaze / pinch spatial events
	if event.get_class() == "InputEventSpatial":
		var ray_orig = event.get("selection_ray_origin")
		var ray_dir = event.get("selection_ray_direction")
		var phase = event.get("phase")
		if ray_orig != null and ray_dir != null:
			var is_press: bool = (phase == 0) # PHASE_ACTIVE
			forward_pointer_ray(ray_orig, ray_dir, is_press)
	elif is_instance_valid(viewport):
		viewport.push_input(event)


func forward_pointer_ray(ray_origin: Vector3, ray_dir: Vector3, is_press: bool) -> void:
	# Ray-plane intersection with the 3D panel at panel_mesh.global_transform
	var plane_normal = -panel_mesh.global_transform.basis.z
	var plane_pos = panel_mesh.global_position
	var denom = plane_normal.dot(ray_dir)
	if absf(denom) < 1e-5:
		return
	var t = (plane_pos - ray_origin).dot(plane_normal) / denom
	if t <= 0.0:
		return
	var hit_point = ray_origin + ray_dir * t
	var local_hit = panel_mesh.global_transform.affine_inverse() * hit_point

	# Check quad bounds
	var half_w = _quad_size.x * 0.5
	var half_h = _quad_size.y * 0.5
	if absf(local_hit.x) > half_w or absf(local_hit.y) > half_h:
		return

	# Map [-half, +half] to [0, viewport_size]
	var u = (local_hit.x + half_w) / _quad_size.x
	var v = 1.0 - ((local_hit.y + half_h) / _quad_size.y)
	var vp_x = u * viewport.size.x
	var vp_y = v * viewport.size.y
	var mouse_pos = Vector2(vp_x, vp_y)

	var motion = InputEventMouseMotion.new()
	motion.position = mouse_pos
	motion.global_position = mouse_pos
	viewport.push_input(motion)

	if is_press:
		var click_down = InputEventMouseButton.new()
		click_down.position = mouse_pos
		click_down.global_position = mouse_pos
		click_down.button_index = MOUSE_BUTTON_LEFT
		click_down.pressed = true
		viewport.push_input(click_down)

		var click_up = InputEventMouseButton.new()
		click_up.position = mouse_pos
		click_up.global_position = mouse_pos
		click_up.button_index = MOUSE_BUTTON_LEFT
		click_up.pressed = false
		viewport.push_input(click_up)
