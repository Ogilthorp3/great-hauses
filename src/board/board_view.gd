class_name BoardView
extends Node3D
## The 8x8 stone board. Owns the tile meshes, square<->world mapping, mouse
## picking (physics-less: camera ray vs the board-top plane), and the
## selection / legal-move highlight quads. Emits square_clicked(sq) on
## left click; sq.x = file (a..h -> 0..7), sq.y = rank (1..8 -> 0..7).

signal square_clicked(sq: Vector2i)

const BOARD_SIZE := 8
const TILE_SIZE := 1.0
const TILE_HEIGHT := 0.22

# Torch-lit great hall: desaturated, moody stone.
const DARK_STONE := Color(0.13, 0.12, 0.115)
const LIGHT_STONE := Color(0.36, 0.33, 0.3)
const PLINTH_STONE := Color(0.07, 0.065, 0.06)
const SELECT_COLOR := Color(0.85, 0.55, 0.2)   # ember amber
const MARKER_COLOR := Color(0.45, 0.62, 0.66)  # cold steel

var _select_quad: MeshInstance3D
var _markers_root: Node3D
var _marker_pool: Array[MeshInstance3D] = []


func _ready() -> void:
	_build_board()
	_build_highlights()


# -- square <-> world ------------------------------------------------------


func square_to_world(sq: Vector2i) -> Vector3:
	## Center of the tile's top face (board centered on this node's origin).
	return Vector3(
		(float(sq.x) - BOARD_SIZE * 0.5 + 0.5) * TILE_SIZE,
		TILE_HEIGHT,
		(float(sq.y) - BOARD_SIZE * 0.5 + 0.5) * TILE_SIZE
	)


func world_to_square(world: Vector3) -> Vector2i:
	return Vector2i(
		int(floor(world.x / TILE_SIZE + BOARD_SIZE * 0.5)),
		int(floor(world.z / TILE_SIZE + BOARD_SIZE * 0.5))
	)


func is_on_board(sq: Vector2i) -> bool:
	return sq.x >= 0 and sq.x < BOARD_SIZE and sq.y >= 0 and sq.y < BOARD_SIZE


func pick_square(screen_pos: Vector2) -> Variant:
	## Vector2i of the square under screen_pos, or null. No physics bodies:
	## casts the camera ray against the board-top plane.
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var origin := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var hit: Variant = Plane(Vector3.UP, TILE_HEIGHT).intersects_ray(origin, dir)
	if hit == null:
		return null
	var sq := world_to_square(hit)
	return sq if is_on_board(sq) else null


# -- input -----------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var sq: Variant = pick_square(event.position)
		if sq != null:
			square_clicked.emit(sq)


# -- highlights ------------------------------------------------------------


func set_selected(sq: Variant) -> void:
	## Vector2i to highlight a square, null to hide the highlight.
	if sq == null:
		_select_quad.visible = false
		return
	var pos := square_to_world(sq)
	_select_quad.position = Vector3(pos.x, TILE_HEIGHT + 0.012, pos.z)
	_select_quad.visible = true


func show_legal_moves(squares: Array[Vector2i]) -> void:
	for m in _markers_root.get_children():
		m.visible = false
	while _marker_pool.size() < squares.size():
		var q := _flat_quad(Vector2(0.34, 0.34), MARKER_COLOR, 0.5)
		_marker_pool.append(q)
		_markers_root.add_child(q)
	for i in squares.size():
		var q := _marker_pool[i]
		var pos := square_to_world(squares[i])
		q.position = Vector3(pos.x, TILE_HEIGHT + 0.012, pos.z)
		q.visible = true


func clear_highlights() -> void:
	_select_quad.visible = false
	for m in _markers_root.get_children():
		m.visible = false


# -- construction ----------------------------------------------------------


func _build_board() -> void:
	var dark := _stone_material(DARK_STONE)
	var light := _stone_material(LIGHT_STONE)
	var tile_mesh := BoxMesh.new()
	tile_mesh.size = Vector3(TILE_SIZE, TILE_HEIGHT, TILE_SIZE)
	var tiles := Node3D.new()
	tiles.name = "Tiles"
	add_child(tiles)
	for rank in BOARD_SIZE:
		for file in BOARD_SIZE:
			var mi := MeshInstance3D.new()
			mi.mesh = tile_mesh
			mi.material_override = dark if (file + rank) % 2 == 0 else light
			var top := square_to_world(Vector2i(file, rank))
			mi.position = Vector3(top.x, TILE_HEIGHT * 0.5, top.z)
			mi.name = "Tile_%d_%d" % [file, rank]
			tiles.add_child(mi)
	var plinth := MeshInstance3D.new()
	var plinth_mesh := BoxMesh.new()
	plinth_mesh.size = Vector3(BOARD_SIZE * TILE_SIZE + 0.7, 0.3, BOARD_SIZE * TILE_SIZE + 0.7)
	plinth.mesh = plinth_mesh
	plinth.material_override = _stone_material(PLINTH_STONE)
	plinth.position = Vector3(0.0, -0.15, 0.0)
	plinth.name = "Plinth"
	add_child(plinth)


func _build_highlights() -> void:
	_select_quad = _flat_quad(Vector2(0.96, 0.96), SELECT_COLOR, 0.55)
	_select_quad.name = "SelectionQuad"
	_select_quad.visible = false
	add_child(_select_quad)
	_markers_root = Node3D.new()
	_markers_root.name = "MoveMarkers"
	add_child(_markers_root)


func _stone_material(albedo: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = 0.92
	m.metallic = 0.0
	return m


func _flat_quad(size: Vector2, color: Color, alpha: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = size
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 1.4
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
