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
## [offset, yaw, character, instrument]. Ranger and Rogue read as travelling
## players; the Barbarian was bare-chested and read as a raider with a bucket.
const CONSORT := [
	[Vector3(0.0, 0.0, -0.80), -1.75, "Ranger", "lute"],
	[Vector3(0.42, 0.0, 0.18), -1.35, "Rogue_Hooded", "shawm"],
	[Vector3(-0.22, 0.0, 0.95), -1.95, "Mage", "drum"],
]

## Which hand each instrument lives in. A lute and a drum are HELD in the
## left and worked with the right (that right arm is what the modifier
## animates); a shawm is held up to the mouth in the right.
const INSTRUMENT_BONE := {"lute": "handslot.l", "drum": "handslot.l",
	"shawm": "handslot.r"}

@export var stand := Vector3(8.3, -0.3, 0.0)   ## GreatHall.dragon_rest(), freed
@export var figure_scale := 0.42               ## players, not giants: well under a piece

var _players: Array[Dictionary] = []
var _notes: Array[Dictionary] = []
var _t := 0.0

## THE NOTES (Bert: "have some little music signs over them to show there are
## playing"). Little glowing notes that rise off the consort, drift, and fade.
## A pool, not a particle system: three players at two notes each is six
## meshes that never allocate again, and the shapes have to be NOTES rather
## than the round sprites a GPUParticles emitter would give us.
const NOTES_EACH := 2
const NOTE_RISE := 0.95        ## how high one climbs before it is gone
const NOTE_LIFE := 2.6         ## seconds, and its own drift is seeded from it
var _bones_found := 0


func _ready() -> void:
	position = stand
	for i in CONSORT.size():
		_build_player(i, CONSORT[i])
	for i in _players.size():
		for k in NOTES_EACH:
			_spawn_note(i, float(k) / float(NOTES_EACH))
	set_process(not _players.is_empty())


## One glowing note: a slurred head and a stem, which is the whole read at
## this size. Its own material, so it can fade without touching its siblings.
func _spawn_note(player_index: int, t0: float) -> void:
	var n := Node3D.new()
	n.name = "Note%d_%d" % [player_index, _notes.size()]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.95, 0.72, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.88, 0.55)
	mat.emission_energy_multiplier = 2.6
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.disable_receive_shadows = true
	var head := SphereMesh.new()
	head.radius = 0.038
	head.height = 0.056
	head.material = mat
	var hi := MeshInstance3D.new()
	hi.mesh = head
	hi.rotation = Vector3(0.0, 0.0, 0.42)
	hi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(hi)
	var stem := BoxMesh.new()
	stem.size = Vector3(0.012, 0.13, 0.012)
	stem.material = mat
	var si := MeshInstance3D.new()
	si.mesh = stem
	si.position = Vector3(0.032, 0.075, 0.0)
	si.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(si)
	add_child(n)
	_notes.append({
		"node": n, "mat": mat, "player": player_index,
		"t": t0 * NOTE_LIFE, "drift": Vector3.ZERO, "spin": 0.0,
	})
	_reseed_note(_notes[-1])


func _reseed_note(note: Dictionary) -> void:
	note["drift"] = Vector3(randf_range(-0.20, 0.20), 0.0, randf_range(-0.16, 0.16))
	note["spin"] = randf_range(-0.9, 0.9)


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
		var clip := _first_clip(player, ["kk/Idle_A", "kk/Idle_B", "kk/Idle"])
		if clip != "":
			var a := player.get_animation(clip)
			if a != null:
				a.loop_mode = Animation.LOOP_LINEAR
			player.speed_scale = randf_range(0.85, 1.05)
			player.play(clip)
			player.seek(randf() * 2.0, true)

	var kind := str(spec[3])
	var inst := _instrument(kind)
	if inst != null and skel != null:
		var bone_name: String = INSTRUMENT_BONE.get(kind, "handslot.r")
		var bone := skel.find_bone(bone_name)
		if bone != -1:
			var att := BoneAttachment3D.new()
			att.bone_name = bone_name
			skel.add_child(att)
			att.add_child(inst)
			# The pack's hand bones carry the rig's own scale; a prop parented
			# raw comes through too small to read at 0.6 figure scale.
			inst.scale = Vector3.ONE * 1.9
			# HOW IT IS CARRIED. The pack's handslot bones point a prop the
			# way a sword wants to go, which is not how any of these want to
			# go: the lute lies across the body with its neck up and out, the
			# drum turns its head toward the beating hand, the shawm tips up
			# to the mouth.
			match kind:
				"lute":
					inst.rotation = Vector3(-0.35, 0.0, -0.95)
					inst.position = Vector3(0.06, 0.04, 0.0)
				"drum":
					inst.rotation = Vector3(0.0, 0.0, -0.55)
					inst.position = Vector3(0.05, 0.02, 0.02)
				_:
					inst.rotation = Vector3(-0.55, 0.0, 0.25)
					inst.position = Vector3(0.0, 0.05, 0.02)
			_bones_found += 1
		else:
			root.add_child(inst)
	elif inst != null:
		root.add_child(inst)

	# AND THEY PLAY. The pack ships Idle_A but nothing that looks like music,
	# so the arms are driven here — same discipline as DragonRig.FlightSway:
	# a SkeletonModifier3D that runs after the AnimationPlayer and rides on
	# top of whatever clip is playing.
	var motion: PlayMotion = null
	if skel != null:
		motion = PlayMotion.new()
		motion.name = "PlayMotion"
		motion.kind = kind
		motion.tempo = 2.15                       # one common pulse…
		motion.phase = float(i) * 0.7             # …struck at their own moment
		skel.add_child(motion)
		motion.build(skel)
	_players.append({
		"root": root, "phase": float(i) * 2.1,
		"rate": 1.6 + 0.23 * float(i),      # each keeps their own time
		"motion": motion,
	})


## THE PLAYING ARM. Post-multiplies the clip's pose, so an idling body keeps
## its weight-shift and breathing while the working limb does the music.
## Angles are small: the read comes from the RHYTHM being visible at fifteen
## metres, not from the throw of the joint.
class PlayMotion:
	extends SkeletonModifier3D

	var kind := "lute"
	var tempo := 2.1          ## beats per second
	var phase := 0.0
	var weight := 1.0

	var _upper_r := -1
	var _lower_r := -1
	var _upper_l := -1
	var _head := -1
	var _chest := -1
	var _t := 0.0

	func build(sk: Skeleton3D) -> void:
		if sk == null:
			return
		_upper_r = sk.find_bone("upperarm.r")
		_lower_r = sk.find_bone("lowerarm.r")
		_upper_l = sk.find_bone("upperarm.l")
		_head = sk.find_bone("head")
		_chest = sk.find_bone("chest")

	func _bend(sk: Skeleton3D, idx: int, e: Vector3) -> void:
		if idx == -1:
			return
		sk.set_bone_pose_rotation(idx, sk.get_bone_pose_rotation(idx)
			* Quaternion.from_euler(e * weight))

	func _process_modification_with_delta(delta: float) -> void:
		var sk := get_skeleton()
		if sk == null or weight <= 0.001:
			return
		_t += delta
		var d := PI / 180.0
		var beat := _t * tempo * TAU + phase
		match kind:
			"lute":
				# a strum: the forearm sweeps across the body, fast down and
				# slower back, which is what a stroke actually is
				var strum := sin(beat)
				var sharp: float = signf(strum) * pow(absf(strum), 0.6)
				_bend(sk, _lower_r, Vector3(0.0, 0.0, sharp * 26.0 * d))
				_bend(sk, _upper_r, Vector3(sharp * 7.0 * d, 0.0, 0.0))
				_bend(sk, _upper_l, Vector3(0.0, 0.0, 4.0 * d))
			"drum":
				# a beat: the whole arm lifts and drops, and the drop is the
				# fast half — hang time on the lift is the entire read
				var lift := 0.5 - 0.5 * cos(beat)
				var hit: float = pow(lift, 0.45)
				_bend(sk, _upper_r, Vector3(-hit * 34.0 * d, 0.0, 0.0))
				_bend(sk, _lower_r, Vector3(-hit * 20.0 * d, 0.0, 0.0))
			_:
				# a shawm: both hands stay up, the player rocks and the
				# fingers do what fingers do — sell it with breath, not arms
				_bend(sk, _upper_r, Vector3(-52.0 * d, 0.0, 0.0))
				_bend(sk, _lower_r, Vector3(-38.0 * d, 0.0, 0.0))
				_bend(sk, _upper_l, Vector3(-44.0 * d, 0.0, 0.0))
				_bend(sk, _chest, Vector3(sin(beat * 0.5) * 2.5 * d, 0.0, 0.0))
		# everyone nods to the same pulse — that is what makes them a consort
		_bend(sk, _head, Vector3(sin(beat) * 3.4 * d, sin(beat * 0.5) * 2.0 * d, 0.0))
		if kind != "shawm":
			_bend(sk, _chest, Vector3(0.0, 0.0, sin(beat * 0.5) * 2.2 * d))


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
	# …and the notes they are making
	for note in _notes:
		var n: Node3D = note["node"]
		if not is_instance_valid(n):
			continue
		note["t"] = float(note["t"]) + delta
		var u: float = fmod(float(note["t"]), NOTE_LIFE) / NOTE_LIFE
		if u < delta / NOTE_LIFE:          # wrapped: a new note, new drift
			_reseed_note(note)
		var src: Node3D = _players[int(note["player"])]["root"]
		var base: Vector3 = src.position + Vector3(0.0, 0.62, 0.0)
		n.position = base + (note["drift"] as Vector3) * u \
			+ Vector3.UP * (NOTE_RISE * u)
		n.rotation.z = float(note["spin"]) * u
		# in fast, out slow — a note is heard before it is gone
		var a: float = clampf(u / 0.18, 0.0, 1.0) * clampf((1.0 - u) / 0.55, 0.0, 1.0)
		var mat: StandardMaterial3D = note["mat"]
		mat.albedo_color.a = a
		n.scale = Vector3.ONE * (0.75 + 0.35 * u)
