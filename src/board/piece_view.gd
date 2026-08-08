class_name PieceView
extends Node3D
## Placeholder piece renderer for Great Houses.
## Simple distinct primitives per piece type, tinted per side. These bodies
## get replaced by real character models later — keep callers on this
## model-agnostic API only:
##   setup(type, side) · move_to(world_pos, walk_time) ·
##   play_capture(victim) · die()

signal move_finished
signal died

enum Type { PAWN, ROOK, KNIGHT, BISHOP, QUEEN, KING }
enum House { FROST, EMBER }  # cold grey-blue vs dark crimson

const SIDE_ALBEDO := {
	House.FROST: Color(0.47, 0.53, 0.62),
	House.EMBER: Color(0.4, 0.12, 0.11),
}

var piece_type: Type = Type.PAWN
var side: House = House.FROST


func setup(new_type: Type, new_side: House) -> void:
	piece_type = new_type
	side = new_side
	for child in get_children():
		child.queue_free()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = SIDE_ALBEDO[side]
	mat.roughness = 0.7
	mat.metallic = 0.08
	match piece_type:
		Type.PAWN:
			_add_cylinder(0.13, 0.18, 0.42, Vector3(0, 0.21, 0), mat)
		Type.ROOK:
			_add_box(Vector3(0.4, 0.72, 0.4), Vector3(0, 0.36, 0), mat)
			_add_box(Vector3(0.48, 0.1, 0.48), Vector3(0, 0.77, 0), mat)
		Type.KNIGHT:
			_add_box(Vector3(0.3, 0.62, 0.3), Vector3(0, 0.31, 0), mat)
			_add_box(Vector3(0.3, 0.26, 0.52), Vector3(0, 0.72, 0.11), mat)
		Type.BISHOP:
			_add_cylinder(0.02, 0.24, 0.85, Vector3(0, 0.425, 0), mat)
		Type.QUEEN:
			_add_cylinder(0.15, 0.24, 0.92, Vector3(0, 0.46, 0), mat)
			_add_sphere(0.16, Vector3(0, 1.0, 0), mat)
		Type.KING:
			_add_cylinder(0.16, 0.25, 1.0, Vector3(0, 0.5, 0), mat)
			_add_box(Vector3(0.07, 0.32, 0.07), Vector3(0, 1.18, 0), mat)
			_add_box(Vector3(0.26, 0.07, 0.07), Vector3(0, 1.2, 0), mat)


func move_to(world_pos: Vector3, walk_time: float = 0.4) -> void:
	## Walk (glide, for now) to a world position. Await it; emits
	## move_finished when the piece arrives.
	var tw := create_tween()
	tw.tween_property(self, "position", world_pos, walk_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	move_finished.emit()


func play_capture(victim: PieceView) -> void:
	## Placeholder combat beat: a short lunge, then the victim dies.
	## Real character animations replace the body of this method; the
	## contract stays: when the await returns, the victim is dead and freed.
	var start := position
	var strike := start.lerp(victim.position, 0.6)
	var tw := create_tween()
	tw.tween_property(self, "position", strike, 0.12) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "position", start, 0.2) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished
	await victim.die()


func die() -> void:
	## Placeholder death: topple and sink, then free. Emits died first.
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "rotation:z", rotation.z + PI * 0.55, 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "position:y", position.y - 0.3, 0.45).set_delay(0.1)
	await tw.finished
	died.emit()
	queue_free()


# -- primitive builders ----------------------------------------------------


func _add_box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	add_child(mi)


func _add_cylinder(
	top_radius: float, bottom_radius: float, height: float, pos: Vector3, mat: Material
) -> void:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	add_child(mi)


func _add_sphere(radius: float, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
