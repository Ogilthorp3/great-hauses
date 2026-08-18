class_name Musicians
extends Node3D
## THE CONSORT — live music in the hall.
##
## Bert, 2026-08-18: "it would be fun to have people playing music by the game
## (where the dragon was before) — that's how medieval music was done, live
## music!" Which is the right instinct twice over: it is historically how a
## hall got its music, and it makes the game's soundtrack DIEGETIC — the score
## you hear is coming from three people standing in the east aisle.
##
## They stand exactly where the wyrm used to sleep. The east feast table was
## removed long ago "to give the colossal dragon an open court"
## (GreatHall._build_tables), and now that the beast keeps its vigil up on the
## Wyrm's Gallery, that court is empty floor beside the board — the best seat
## in the hall, and in frame from the wide and orbit cameras.
##
## Built from the same KayKit Adventurers rig the pieces use, so they belong
## to this world rather than looking imported: `PieceAssets.shared_anims()`
## supplies the clip library and the pack's own `handslot.*` prop bones carry
## the instruments. The instruments themselves are primitives — a lute, a
## frame drum, a shawm — because at this scale a silhouette is the whole
## story and a modelled soundhole is not.
##
## They cost no lights, no particles and no shadow casters: three skinned
## figures and nine small meshes.

const LUTE_BODY := Color(0.34, 0.19, 0.09)
const LUTE_TRIM := Color(0.72, 0.58, 0.28)
const DRUM_SKIN := Color(0.80, 0.72, 0.58)
const WOOD := Color(0.28, 0.16, 0.08)
const BRASS := Color(0.70, 0.55, 0.22)

## Where the wyrm used to sleep: the open court in the east aisle. Each entry
## is [offset from the stand, yaw, character, instrument, clip].
const CONSORT := [
	[Vector3(0.0, 0.0, -0.95), -1.75, "Rogue_Hooded", "lute", "Idle"],
	[Vector3(0.5, 0.0, 0.25), -1.35, "Mage", "shawm", "Idle"],
	[Vector3(-0.25, 0.0, 1.15), -1.95, "Barbarian", "drum", "Idle"],
]

@export var stand := Vector3(8.3, -0.3, 0.0)   ## GreatHall.dragon_rest(), freed
@export var figure_scale := 0.62               ## a shade under a chess piece

var _players: Array[Dictionary] = []
var _t := 0.0
var _bones_found := 0


func _ready() -> void:
	position = stand
	for i in CONSORT.size():
		_build_player(i, CONSORT[i])
	set_process(not _players.is_empty())


func count() -> int:
	return _players.size()


## How many instruments actually found a hand to hang from (probe).
func instruments_mounted() -> int:
	return _bones_found


func _build_player(i: int, spec: Array) -> void:
	var path := "res://assets/kaykit-adventurers/%s.glb" % str(spec[2])
	if not ResourceLoader.exists(path):
		return
	var root := Node3D.new()
	root.name = "Player%d" % i
	root.position = spec[0] as Vector3
	root.rotation.y = spec[1] as float
	root.scale = Vector3.ONE * figure_scale
	add_child(root)

	var model: Node = (load(path) as PackedScene).instantiate()
	root.add_child(model)
	var skels := model.find_children("*", "Skeleton3D", true, false)
	var skel: Skeleton3D = skels[0] if not skels.is_empty() else null
	# No shadow casting: three figures in an aisle the Sun barely reaches are
	# pure submission cost, and the hall's one shadow cascade is spent on the
	# board (the same call GreatHall makes for its own dressing).
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# The clip library the pieces use, so a musician idles like a person.
	var anims := model.find_children("*", "AnimationPlayer", true, false)
	var player: AnimationPlayer = anims[0] if not anims.is_empty() else null
	if player != null:
		# Reached through the tree rather than by name: PieceAssets is an
		# autoload, and a bare `-s` probe (or any harness that instances the
		# hall by hand) has no autoloads, where a hard reference is a COMPILE
		# error rather than a graceful absence.
		var pa: Node = get_tree().root.get_node_or_null("PieceAssets")
		if pa != null and pa.has_method("shared_anims"):
			var lib: AnimationLibrary = pa.call("shared_anims")
			if lib != null and not player.has_animation_library("kk"):
				player.add_animation_library("kk", lib)
		var clip := _first_clip(player, ["kk/Idle", "kk/Idle_B", "kk/Cheer"])
		if clip != "":
			var a := player.get_animation(clip)
			if a != null:
				a.loop_mode = Animation.LOOP_LINEAR
			player.speed_scale = randf_range(0.85, 1.05)
			player.play(clip)
			player.seek(randf() * 2.0, true)

	var inst := _instrument(str(spec[3]))
	if inst != null and skel != null:
		var bone := skel.find_bone("handslot.r")
		if bone != -1:
			var att := BoneAttachment3D.new()
			att.bone_name = "handslot.r"
			skel.add_child(att)
			att.add_child(inst)
			# The pack's hand bones carry the rig's own scale; a prop parented
			# raw comes through too small to read at 0.6 figure scale.
			inst.scale = Vector3.ONE * 1.9
			_bones_found += 1
		else:
			root.add_child(inst)
	elif inst != null:
		root.add_child(inst)

	_players.append({
		"root": root, "phase": float(i) * 2.1,
		"rate": 1.6 + 0.23 * float(i),      # each keeps their own time
	})


static func _first_clip(player: AnimationPlayer, wanted: Array) -> String:
	for w in wanted:
		if player.has_animation(w):
			return String(w)
	var all := player.get_animation_list()
	for n in all:
		if String(n).to_lower().contains("idle"):
			return String(n)
	return String(all[0]) if not all.is_empty() else ""


static func _mat(c: Color, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


static func _part(mesh: Mesh, c: Color, pos: Vector3, rot := Vector3.ZERO,
		rough := 0.85) -> MeshInstance3D:
	mesh.surface_set_material(0, _mat(c, rough)) if mesh is ArrayMesh \
		else mesh.set("material", _mat(c, rough))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Silhouettes, not luthiery: at 0.6 scale in a torch-lit aisle the shape is
## the entire read.
func _instrument(kind: String) -> Node3D:
	var n := Node3D.new()
	n.name = kind
	match kind:
		"lute":
			var body := SphereMesh.new()
			body.radius = 0.16
			body.height = 0.26
			n.add_child(_part(body, LUTE_BODY, Vector3(0, 0, 0), Vector3(1.2, 0, 0), 0.55))
			var neck := BoxMesh.new()
			neck.size = Vector3(0.05, 0.44, 0.04)
			n.add_child(_part(neck, WOOD, Vector3(0, 0.26, -0.04), Vector3(0.35, 0, 0)))
			var head := BoxMesh.new()
			head.size = Vector3(0.06, 0.10, 0.05)
			n.add_child(_part(head, LUTE_TRIM, Vector3(0, 0.5, -0.10), Vector3(0.9, 0, 0), 0.4))
		"drum":
			var shell := CylinderMesh.new()
			shell.top_radius = 0.19
			shell.bottom_radius = 0.19
			shell.height = 0.10
			n.add_child(_part(shell, WOOD, Vector3(0, 0, 0), Vector3(0, 0, 1.4)))
			var skin := CylinderMesh.new()
			skin.top_radius = 0.175
			skin.bottom_radius = 0.175
			skin.height = 0.11
			n.add_child(_part(skin, DRUM_SKIN, Vector3(0, 0, 0), Vector3(0, 0, 1.4), 0.9))
		"shawm":
			var bore := CylinderMesh.new()
			bore.top_radius = 0.022
			bore.bottom_radius = 0.045
			bore.height = 0.42
			n.add_child(_part(bore, WOOD, Vector3(0, 0.16, 0.0), Vector3(-1.1, 0, 0)))
			var bell := CylinderMesh.new()
			bell.top_radius = 0.10
			bell.bottom_radius = 0.035
			bell.height = 0.12
			n.add_child(_part(bell, BRASS, Vector3(0, -0.02, 0.24), Vector3(-1.1, 0, 0), 0.35))
		_:
			return null
	return n


func _process(delta: float) -> void:
	# Playing is a whole-body thing: a slow rock plus a smaller bob, each
	# musician on their own clock so the three never pulse together — the
	# same reason the coronas' draught uses incommensurate periods.
	_t += delta
	for p in _players:
		var root: Node3D = p["root"]
		if not is_instance_valid(root):
			continue
		var ph: float = p["phase"]
		var rate: float = p["rate"]
		root.rotation.z = sin(_t * rate + ph) * 0.035
		root.position.y = absf(sin(_t * rate * 0.5 + ph)) * 0.022
