class_name BoardView
extends Node3D
## The 8x8 stone board. Owns the tile meshes, square<->world mapping, mouse
## picking (physics-less: camera ray vs the board-top plane), and the
## selection / legal-move highlight quads. Emits square_clicked(sq) on
## left click.
##
## Board-space convention (set by game.sq_of, the only producer):
##   sq.x = 7 - (file-1)  — h..a -> 0..7, so file h sits at world -X and
##          file a at +X; the default camera (orbit yaw = PI, behind the
##          player) flips screen X back, so files READ a..h left-to-right.
##   sq.y = rank-1        — 1..8 -> 0..7, rank 1 nearest the player (-Z).
## Anything deriving true file/rank from sq must un-mirror x (see
## _build_board's tile parity — the 2026-08-08 "queen not on her color" scar).

signal square_clicked(sq: Vector2i)
## The square under the mouse changed. `sq` is a Vector2i, or null when the
## cursor left the board. Fed by throttled mouse-motion picking (same
## physics-less camera-ray path as clicks); game.gd drives the hover-only
## glyph rings from it.
signal square_hovered(sq)

const BOARD_SIZE := 8
const TILE_SIZE := 1.0
const TILE_HEIGHT := 0.22
## Re-pick on mouse motion at most this often — hover is cosmetic, one pick
## per frame-ish is plenty.
const HOVER_THROTTLE_MS := 30

# Torch-lit great hall: desaturated, moody stone. The light/dark SPLIT is
# wide on purpose (ISSUES.md #15): the hall is dim and distance-fogged, so a
# narrow albedo split collapses into one grey mush through the empty middle
# of the board. Lighting multiplies both stones equally — only the ratio
# survives the gloom, so the ratio carries the checker.
const DARK_STONE := Color(0.105, 0.098, 0.094)
const LIGHT_STONE := Color(0.5, 0.468, 0.425)
const PLINTH_STONE := Color(0.07, 0.065, 0.06)
## Ember amber, brightened — the selection now spends its light on the FRAME
## instead of flooding the tile face (see _select_frame_texture).
const SELECT_COLOR := Color(1.0, 0.68, 0.26)
const MARKER_COLOR := Color(0.58, 0.79, 0.86)   # cold steel
const CAPTURE_COLOR := Color(0.94, 0.36, 0.24)  # blood on the stone

## Highlight geometry. The move dot is small and centered; the capture
## reticle is a ring inscribed in the tile, so it frames the victim standing
## on it instead of hiding under him.
const MARKER_SIZE := 0.42
const CAPTURE_SIZE := 0.94
const SELECT_SIZE := 0.96
## Marker/selection art is drawn into small runtime textures once — a
## RECOGNISABLE shape (rune dot, target ring, tile frame) instead of the flat
## untextured squares that read as missing-texture nameplates (ISSUES.md #5).
const HL_TEX_SIZE := 96

var _select_quad: MeshInstance3D
var _markers_root: Node3D
var _marker_pool: Array[MeshInstance3D] = []
var _hover_sq: Variant = null       # Vector2i or null — last emitted hover
var _last_hover_pick_ms := 0
var _move_mesh: PlaneMesh
var _capture_mesh: PlaneMesh
var _move_mat: StandardMaterial3D
var _capture_mat: StandardMaterial3D


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
	return pick_square_ray(origin, dir)


var occupied_squares: Array[Vector2i] = []


func set_occupied_squares(sqs: Array) -> void:
	occupied_squares.clear()
	for s in sqs:
		if s is Vector2i:
			occupied_squares.append(s)


func pick_square_ray(ray_origin: Vector3, ray_dir: Vector3) -> Variant:
	## 3D volumetric ray picking for gaze & pinch on visionOS and XR.
	## Tests 3D piece volumes ONLY on occupied squares (where pieces actually stand),
	## then falls back to the board-top plane for empty destination tiles.
	var local_orig := global_transform.affine_inverse() * ray_origin
	var local_dir := global_transform.basis.inverse() * ray_dir.normalized()

	# 1. Test 3D piece cylinders ONLY on squares with actual living pieces
	var best_sq: Variant = null
	var best_t: float = 1e9
	var o_xz := Vector2(local_orig.x, local_orig.z)
	var d_xz := Vector2(local_dir.x, local_dir.z)
	var d_len_sq := d_xz.length_squared()

	if d_len_sq > 1e-6 and not occupied_squares.is_empty():
		for sq in occupied_squares:
			var center3 := square_to_world(sq)
			var c_xz := Vector2(center3.x, center3.z)
			var v := c_xz - o_xz
			var t_val := v.dot(d_xz) / d_len_sq
			if t_val <= 0.0 or t_val >= best_t:
				continue
			var closest_xz := o_xz + d_xz * t_val
			var dist_sq := (closest_xz - c_xz).length_squared()
			if dist_sq <= (0.48 * 0.48):
				var y_at_t := local_orig.y + local_dir.y * t_val
				if y_at_t >= TILE_HEIGHT - 0.05 and y_at_t <= TILE_HEIGHT + 1.6:
					best_t = t_val
					best_sq = sq

	if best_sq != null:
		return best_sq

	# 2. Fall back to flat board plane for empty destination tiles
	var denom := Vector3.UP.dot(local_dir)
	if absf(denom) > 1e-5:
		var t_plane := (TILE_HEIGHT - local_orig.y) / denom
		if t_plane > 0.0:
			var hit := local_orig + local_dir * t_plane
			var sq := world_to_square(hit)
			if is_on_board(sq):
				return sq

	return null


# -- input -----------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if event.get_class() == "InputEventSpatial":
		var ray_orig = event.get("selection_ray_origin")
		var ray_dir = event.get("selection_ray_direction")
		var phase = event.get("phase")
		if ray_orig != null and ray_dir != null:
			# Transform spatial ray from tracking space to world space via XROrigin3D
			var xr_orig: Node3D = get_tree().get_first_node_in_group("xr_origin")
			var world_orig: Vector3 = ray_orig
			var world_dir: Vector3 = ray_dir
			if xr_orig != null and is_instance_valid(xr_orig):
				world_orig = xr_orig.global_transform * ray_orig
				world_dir = (xr_orig.global_transform.basis * ray_dir).normalized()

			var sq: Variant = pick_square_ray(world_orig, world_dir)
			if sq != null:
				if sq != _hover_sq:
					_hover_sq = sq
					square_hovered.emit(sq)
				if phase == 0:  # PHASE_ACTIVE (pinch down)
					square_clicked.emit(sq)
			else:
				if _hover_sq != null:
					_hover_sq = null
					square_hovered.emit(null)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var sq: Variant = pick_square(event.position)
		if sq != null:
			square_clicked.emit(sq)
	elif event is InputEventMouseMotion:
		var now := Time.get_ticks_msec()
		if now - _last_hover_pick_ms < HOVER_THROTTLE_MS:
			return
		_last_hover_pick_ms = now
		var hov: Variant = pick_square(event.position)
		if hov != _hover_sq:
			_hover_sq = hov
			square_hovered.emit(hov)


# -- highlights ------------------------------------------------------------


func set_selected(sq: Variant) -> void:
	## Vector2i to highlight a square, null to hide the highlight.
	if sq == null:
		_select_quad.visible = false
		return
	var pos := square_to_world(sq)
	_select_quad.position = Vector3(pos.x, TILE_HEIGHT + 0.012, pos.z)
	_select_quad.visible = true


func show_legal_moves(squares: Array[Vector2i], captures: Array[Vector2i] = []) -> void:
	## `captures` is the subset of `squares` that would take an enemy piece —
	## those get the red target ring, the quiet moves get the steel rune dot.
	## The two must be visually different: telling "I may step here" from "I
	## may kill here" is the whole point of the highlight layer.
	for m in _markers_root.get_children():
		m.visible = false
	while _marker_pool.size() < squares.size():
		var q := MeshInstance3D.new()
		q.name = "MoveMarker%d" % _marker_pool.size()
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_marker_pool.append(q)
		_markers_root.add_child(q)
	for i in squares.size():
		var q := _marker_pool[i]
		var is_capture := captures.has(squares[i])
		q.mesh = _capture_mesh if is_capture else _move_mesh
		q.material_override = _capture_mat if is_capture else _move_mat
		var pos := square_to_world(squares[i])
		# The capture ring rides lower — it wraps a piece's feet, the dot sits
		# on empty stone.
		q.position = Vector3(pos.x, TILE_HEIGHT + (0.008 if is_capture else 0.014), pos.z)
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
	for row in BOARD_SIZE:      # sq.y: rank-1
		for col in BOARD_SIZE:  # sq.x: 7-(file-1) — MIRRORED file (header note)
			var mi := MeshInstance3D.new()
			mi.mesh = tile_mesh
			# Engine truth: a1 is DARK ⇔ (file0+rank0) even. col mirrors the
			# file (col = 7-file0), which flips parity — so in board space the
			# dark squares are the ODD (col+row) ones. Coloring by even
			# (col+row) painted every tile inverted: a1 light, queen on dark.
			mi.material_override = dark if (col + row) % 2 == 1 else light
			var top := square_to_world(Vector2i(col, row))
			mi.position = Vector3(top.x, TILE_HEIGHT * 0.5, top.z)
			mi.name = "Tile_%d_%d" % [col, row]
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
	_move_mesh = PlaneMesh.new()
	_move_mesh.size = Vector2(MARKER_SIZE, MARKER_SIZE)
	_capture_mesh = PlaneMesh.new()
	_capture_mesh.size = Vector2(CAPTURE_SIZE, CAPTURE_SIZE)
	_move_mat = _highlight_material(MARKER_COLOR, 0.95, _move_dot_texture())
	_capture_mat = _highlight_material(CAPTURE_COLOR, 0.95, _capture_ring_texture())

	var select_mesh := PlaneMesh.new()
	select_mesh.size = Vector2(SELECT_SIZE, SELECT_SIZE)
	_select_quad = MeshInstance3D.new()
	_select_quad.name = "SelectionQuad"
	_select_quad.mesh = select_mesh
	_select_quad.material_override = _highlight_material(
		SELECT_COLOR, 0.95, _select_frame_texture())
	_select_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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


func _highlight_material(color: Color, alpha: float, tex: Texture2D) -> StandardMaterial3D:
	## UNSHADED on purpose: the highlight layer is UI drawn in world space. It
	## must not take the pieces' cast shadow — a black shadow ellipse punched
	## through a bright selection tile was the worst instance of ISSUES.md #17.
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m


# -- highlight art (procedural, built once at boot) -------------------------


static func _band(d: float, lo: float, hi: float, feather: float) -> float:
	## 1.0 inside [lo, hi], feathered to 0 outside — one soft-edged ring band.
	return minf(smoothstep(lo - feather, lo, d), 1.0 - smoothstep(hi, hi + feather, d))


static func _alpha_texture(alphas: PackedFloat32Array) -> ImageTexture:
	var img := Image.create(HL_TEX_SIZE, HL_TEX_SIZE, true, Image.FORMAT_RGBA8)
	for y in HL_TEX_SIZE:
		for x in HL_TEX_SIZE:
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0,
				clampf(alphas[y * HL_TEX_SIZE + x], 0.0, 1.0)))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _move_dot_texture() -> ImageTexture:
	## Quiet move: a filled rune dot inside a crisp ring — small, centered,
	## unmistakably an indicator rather than a blank nameplate.
	var a := PackedFloat32Array()
	a.resize(HL_TEX_SIZE * HL_TEX_SIZE)
	for y in HL_TEX_SIZE:
		for x in HL_TEX_SIZE:
			var u := (float(x) + 0.5) / HL_TEX_SIZE - 0.5
			var v := (float(y) + 0.5) / HL_TEX_SIZE - 0.5
			var r := sqrt(u * u + v * v) * 2.0        # 1.0 at the quad edge
			var ring := _band(r, 0.60, 0.80, 0.09) * 0.95
			var core := (1.0 - smoothstep(0.30, 0.44, r)) * 0.85
			a[y * HL_TEX_SIZE + x] = maxf(ring, core)
	return _alpha_texture(a)


static func _capture_ring_texture() -> ImageTexture:
	## Capture: a target ring inscribed in the tile — it FRAMES the enemy
	## standing there (a dot would vanish under his feet), with a faint wash
	## inside so the doomed square reads at a glance.
	var a := PackedFloat32Array()
	a.resize(HL_TEX_SIZE * HL_TEX_SIZE)
	for y in HL_TEX_SIZE:
		for x in HL_TEX_SIZE:
			var u := (float(x) + 0.5) / HL_TEX_SIZE - 0.5
			var v := (float(y) + 0.5) / HL_TEX_SIZE - 0.5
			var r := sqrt(u * u + v * v) * 2.0
			var ring := _band(r, 0.76, 0.90, 0.05) * 0.95
			# four crosshair ticks on the axes — reads as a reticle, not a halo
			var tick_x := _band(r, 0.62, 0.76, 0.03) \
				* (1.0 - smoothstep(0.02, 0.06, absf(v))) * 0.8
			var tick_y := _band(r, 0.62, 0.76, 0.03) \
				* (1.0 - smoothstep(0.02, 0.06, absf(u))) * 0.8
			var wash := (1.0 - smoothstep(0.55, 0.80, r)) * 0.16
			a[y * HL_TEX_SIZE + x] = maxf(maxf(ring, wash), maxf(tick_x, tick_y))
	return _alpha_texture(a)


## Where the medallion sits, in the same 0..1 half-extent coordinate the
## squircle below is drawn in: the hover/selection glyph ring (pieces lane)
## is a DARK disc covering roughly the middle 60% of the tile.
const MEDALLION_EXTENT := 0.62


static func _select_frame_texture() -> ImageTexture:
	## Selection: a squircle frame hugging the tile, a warm collar just
	## OUTSIDE the glyph medallion, and almost nothing under the medallion
	## itself.
	##
	## ISSUES.md #17 residual: the type-glyph medallion is a near-black disc,
	## and the old flat 0.34 amber wash ran straight underneath it — a dark
	## disc dropped on a bright amber field reads as a hole punched in the
	## board, not as an emblem (measured 4.6:1 medallion-to-field on the
	## shipped frame). The medallion's own material belongs to the pieces
	## lane; the LIGHT it sits in is ours, so the light moved: the amber now
	## rings the medallion instead of lying under it. The dark icon then sits
	## on plain stone (where every other dark icon in this game already
	## works) and the collar + frame carry "this square is selected".
	var a := PackedFloat32Array()
	a.resize(HL_TEX_SIZE * HL_TEX_SIZE)
	for y in HL_TEX_SIZE:
		for x in HL_TEX_SIZE:
			var u := absf((float(x) + 0.5) / HL_TEX_SIZE - 0.5) * 2.0
			var v := absf((float(y) + 0.5) / HL_TEX_SIZE - 0.5) * 2.0
			# p-norm squircle: square-ish frame with rounded corners
			var m: float = pow(pow(u, 6.0) + pow(v, 6.0), 1.0 / 6.0)
			var border := _band(m, 0.80, 0.95, 0.035) * 1.0
			# A dark moat where the medallion's rim lands: the amber must NOT
			# be at its brightest exactly where the black disc ends, or the
			# disc reads as a hole cut in a lit plate.
			var moat := _band(m, MEDALLION_EXTENT, 0.80, 0.09) * 0.09
			# Whisper of amber under the medallion — enough to say the square
			# is claimed, far too little to make a plate out of it.
			var wash := (1.0 - smoothstep(0.42, MEDALLION_EXTENT, m)) * 0.06
			a[y * HL_TEX_SIZE + x] = maxf(border, maxf(moat, wash))
	return _alpha_texture(a)
