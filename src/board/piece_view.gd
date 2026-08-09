class_name PieceView
extends Node3D
## A Great Houses combatant on the board — a real KayKit character (the
## banner watchtower for the rook, a MOUNTED horse+rider ensemble for the
## knight — ISSUES.md #1), tinted per house, animated from the shared
## Rig_Medium animation libraries (the mount carries no rig at all — it is
## driven procedurally, see below), and COSTUMED in two layers:
##
##   TYPE layer (identical across houses — instant readability):
##     strict height grading (PieceAssets.TYPE_HEIGHT) · signature gear
##     (pawn sword+round shield · knight ON HORSEBACK, sword+kite shield ·
##     bishop staff+tome · queen tiara+bow+quiver · king crown+cape+sword)
##     · an engraved type-glyph ring under every piece — HIDDEN at rest,
##     fading in on mouse hover (set_hovered), staying lit while selected
##     (set_selected also brightens the glyph to beacon energy). ISSUES.md #2.
##   MATERIAL-ROLE layer (2026-08-09 — what a surface is MADE OF):
##     every mesh and material is classified once in PieceAssets.MATERIAL_ROLES
##     and the colour pipeline dispatches on that. KIT (tabard, cloak, hood,
##     shield face, helm, crest, caparison) carries the house and is allowed to
##     be LOUD because it is no longer everywhere; NATURAL (steel, leather,
##     wood, stone, skin, bone, and the horse's own coat) keeps its own
##     material's colours; REGALIA stays metal; HERALDRY keeps its artwork.
##     A KayKit body is painted from one atlas, so it is split per triangle by
##     what the atlas paints it and each half goes down its own path.
##   HOUSE layer (flourish — never changes the type silhouette):
##     the house jersey · helmet crests on knight/queen/king · per-house PAWN
##     half-helms (ISSUES.md #3 — the footman's quieter answer to the crest:
##     it wraps the skull instead of towering over it, and only its rim and
##     motif take the house accent) · sigil decals
##     on shields · the rook's banner + fluttering pennant · the knight's
##     caparison dressed in the house banner cloth (sigil on the flank) ·
##     Tidegrip fields the skeleton cast (same rig, same anims) on a
##     charred-dark horse.
##
## MOUNTED KNIGHT (ISSUES.md #1): the KayKit Knight sits a Quaternius CC0
## horse (fixed transform on the horse root, statically seat-posed — bend
## poses read fine at this poly scale). The horse is a STATIC standing mesh
## (its FBX-lineage rig corrupts in-engine at piece scale — see
## PieceAssets.HORSE) animated procedurally, banner-rook style: idle sway
## on the ensemble, a canter bob on moves (the rider sits still), a horse
## step-in under the rider's Throw for the capture duel, and on death the
## rider slides off through Death_A while the horse keels over sideways.
## Face-to-face duel rotation applies to this PieceView root, so the whole
## ensemble turns as one.
##
## Model-agnostic API (callers touch nothing else):
##   setup(type, side, house_id="") · move_to(world_pos, walk_time) ·
##   play_capture(victim) · die() · spawn_flourish() · set_selected(on) ·
##   set_hovered(on)
## house_id skins the piece with HouseRegistry tints; "" keeps the legacy
## FROST/EMBER consts (fully backward compatible).

signal move_finished
signal died

enum Type { PAWN, ROOK, KNIGHT, BISHOP, QUEEN, KING }
enum House { FROST, EMBER }  # cold grey-blue vs dark crimson

# House Frost = cold grey-blue; House Ember = dark crimson/gold. The legacy
# sides have no houses.json entry, so these two consts serve as BOTH their kit
# colour and their natural whisper — they field the default coat and the
# default charge with them.
const HOUSE_TINT := {
	House.FROST: Color(0.58, 0.7, 0.9),
	House.EMBER: Color(0.85, 0.38, 0.22),
}
const HOUSE_TINT_TOWER := {
	House.FROST: Color(0.52, 0.63, 0.8),
	House.EMBER: Color(0.75, 0.33, 0.2),
}
## Glyph-ring hover fade (ISSUES.md #2): hidden at rest, ~0.15 s in/out.
const RING_FADE_TIME := 0.15

const ANIM_IDLE := "Idle_A"
const ANIM_WALK := "Walking_A"
const ANIM_THROW := "Throw"
const ANIM_HIT := "Hit_A"
const ANIM_DEATH := "Death_A"
const ANIM_SPAWN := "Spawn_Ground"

## Ensemble proportions, tuned BY EYE against the IN-GAME board frame (the
## KayKit cast is chibi — big head, wide shoulders — so a horse scaled to
## "anatomically right" reads as a pony under a giant). Horse-ensemble-local
## units, pre-normalization:
##   HORSE_SCALE  the mount's size against the rider's native size. 0.72 —
##                the destrier is deliberately the BIGGER animal now (its
##                withers out-top the rider's own standing height), because
##                mass below the rider is what says "cavalry" at 50 px.
##   RIDER_POS    the seat: hips sink onto the saddle slab top
##                (3.320·HORSE_SCALE − hips-height 0.39) over the seat
##                center (0.55·HORSE_SCALE) — no float, no gap. 3.320 is the
##                slab top convert_horse.py prints as `seat_top`.
##   MODEL_YAW    stance. A chess piece is read head-on, and head-on a horse
##                is a narrow shape hiding behind its rider — at 30 deg the
##                board showed the mount's RUMP and nothing else, which is
##                how nine armies ended up with "a helmeted torso on four thin
##                legs". Every physical chess set answers this the same way:
##                the knight stands in PROFILE. 74 deg is near-broadside —
##                head one side, tail the other, barrel and caparison flank
##                (sigil included) square to the player.
##   RIDER_COUNTER_YAW
##                ...and the rider twists back out of it, so the man still
##                faces the enemy line while his horse stands across it. A
##                cavalryman turned in the saddle is a real pose, and it is
##                what keeps the capture duel legible: without it a
##                broadside mount would swing the rider 74 deg off the victim
##                he is striking.
## Applied to the Model/Rider, never the ROOT, so duel face-offs (which turn
## the root) still put the knight on his victim.
const KNIGHT_HORSE_SCALE := 0.72
const KNIGHT_RIDER_POS := Vector3(0.0, 2.00, 0.40)
const KNIGHT_MODEL_YAW := 74.0
const KNIGHT_RIDER_COUNTER_YAW := 52.0
## How far the rider tumbles off the saddle when the knight falls
## (ensemble-local; the slide runs while Death_A plays).
const KNIGHT_FALL_OFFSET := Vector3(1.6, -1.55, -0.2)

## Head-bone mount for house crests (crown-attach pattern): sits above the
## crown line so king crest + crown coexist.
const CREST_MOUNT_POS := Vector3(0.0, 1.04, 0.0)
## Head-bone mount for the PAWN half-helm (ISSUES.md #3). 0.095 BELOW the
## crest line, because a crest sits ABOVE the skull while a helm WRAPS it:
## 0.945 is the measured bone-space Y of the skull crown. One transform, no
## scale, no rotation, no per-cast branch — the Drowned Legion's skeleton skull
## sits 0.020 lower and its helm is pre-shifted by exactly that in the
## generator, so both casts mount identically.
const HELM_MOUNT_POS := Vector3(0.0, 0.945, 0.0)
## Chest-bone mount for the king's cape (Skeleton_Rogue cape convention).
const CAPE_MOUNT_POS := Vector3(0.0, 0.04, -0.08)

## ROYAL LEGIBILITY FROM ABOVE (critic defect #3). The gameplay camera looks
## DOWN, so what a player actually sees of a royal is the top of a head — and
## at 5.3 the king's crown sat INSIDE his own skull's silhouette. Winterfang
## therefore fielded a king and a queen who were, at board distance, the same
## large pale-blue dome: "the player cannot find their own king."
##
## The two now differ where the player is looking. The crown is scaled until
## its spiked ring is WIDER THAN THE SKULL — from above the king wears a
## visible spiked halo, from the side a proper crown. The tiara stays inside
## the skull line, a slim band on a bare head. Same prop, opposite reads;
## tests/test_costumes.gd::_test_royal_silhouette measures both against the
## head and fails if they ever converge again.
## ...and the ring is widened again (critic P3, 2026-08-09): "#3 works
## perfectly on the ENEMY army and fails on YOUR army in every frame." From
## the near side the camera looks nearly DOWN the crown's axis, where the
## wearer's own skull dome eats the band and only the points clear it — so the
## points have to clear it by a margin, not by a pixel. Widened here, thickened
## in tools/props/make_crown.py, and given a contrasting metal in
## PieceAssets.crown_scene: three independent fixes, because the near-side read
## had failed once already with only one of them.
const CROWN_SCALE := 7.2
const TIARA_SCALE := Vector3(3.3, 1.9, 3.3)

var piece_type: Type = Type.PAWN
var side: House = House.FROST
## Canonical HouseRegistry id skinning this piece ("" = legacy FROST/EMBER).
var house_id := ""
## Set just before `died` fires — e2e reads it to prove a death anim played.
var death_anim := ""

var _model: Node3D
var _anim: AnimationPlayer  # null for the rook (static tower); the RIDER's for the knight
var _horse: Node3D          # knight only: the mount instance (static mesh)
var _rider: Node3D          # knight only: the seated character instance
var _sway_tween: Tween      # knight only: the procedural idle sway loop
var _home_yaw := 0.0
var _glyph_ring: Node3D
var _glyph_mat: StandardMaterial3D  # per-piece duplicate; brightened on select
var _glyph_tween: Tween
var _ring_meshes: Array[MeshInstance3D] = []  # faded via GeometryInstance3D.transparency
var _ring_fade_tween: Tween
var _ring_shown := false    # target state (true while fading in)
var _mitre_brim: Dictionary = {}   # bishop only: hat MeshInstance3D -> brim surfaces
var _hovered := false
var _is_selected := false


func setup(new_type: Type, new_side: House, new_house_id: String = "") -> void:
	piece_type = new_type
	side = new_side
	house_id = new_house_id
	for child in get_children():
		child.queue_free()
	_anim = null
	_horse = null
	_rider = null
	if _sway_tween != null:
		_sway_tween.kill()
		_sway_tween = null
	_glyph_ring = null
	_glyph_mat = null
	_mitre_brim = {}
	_ring_meshes = []
	_ring_shown = false
	_hovered = false
	_is_selected = false
	if piece_type == Type.ROOK:
		_build_tower()
	elif piece_type == Type.KNIGHT:
		_build_knight()
	else:
		_build_character()
	_build_glyph_ring()
	# Face the enemy line: Frost looks +Z (toward Ember), Ember looks -Z.
	#
	# THE ROOK IS THE EXCEPTION, and it is a costume decision (role pass,
	# 2026-08-09): a watchtower's masonry is STONE, so the tower itself is the
	# same grey in all nine houses and the ONLY thing that says whose rook this
	# is, is the banner down its face. Facing that banner at the enemy meant the
	# player's own rooks showed him their blank back wall — two neutral grey
	# blocks in the corners of his own army. A tower has no facing to lose (it
	# never turns, `_face`/`_face_home` exempt it), so both armies now present
	# the banner to the camera.
	_home_yaw = PI if piece_type == Type.ROOK else (0.0 if side == House.FROST else PI)
	rotation.y = _home_yaw
	# Counter-rotate the ring so the engraved glyph reads upright from the
	# default camera (behind the player at -Z) for BOTH armies.
	if _glyph_ring != null:
		_glyph_ring.rotation.y = -_home_yaw
		if piece_type == Type.ROOK:
			# the watchtower plinth is wider than a character's feet — slide
			# the ring along its own forward axis so the medallion clears it
			_glyph_ring.translate_object_local(Vector3(0.0, 0.0, -0.14))


## Selection feedback: the ring stays lit for the whole selection and the
## engraved glyph warms from engraving to beacon.
func set_selected(selected: bool) -> void:
	_is_selected = selected
	_update_ring_visibility()
	if _glyph_mat == null:
		return
	if _glyph_tween != null:
		_glyph_tween.kill()
	var target := PieceAssets.GLYPH_ENERGY_SELECTED if selected \
			else PieceAssets.GLYPH_ENERGY_REST
	_glyph_tween = create_tween()
	_glyph_tween.tween_property(_glyph_mat, "emission_energy_multiplier",
			target, 0.15).set_trans(Tween.TRANS_SINE)


## Hover feedback (ISSUES.md #2): the type-glyph ring is hidden at rest and
## fades in while the mouse rests on this piece's square — BOTH armies
## reveal (knowing the rival's piece types matters too). game.gd drives it
## from BoardView.square_hovered.
func set_hovered(hovered: bool) -> void:
	if _hovered == hovered:
		return
	_hovered = hovered
	_update_ring_visibility()


## True while the glyph ring is shown (or fading in) — hover or selection.
## Introspection for the costume suite + e2e hover assertions.
func glyph_ring_shown() -> bool:
	return _ring_shown


func _update_ring_visibility() -> void:
	_set_ring_shown(_hovered or _is_selected)


func _set_ring_shown(shown: bool) -> void:
	if _glyph_ring == null or _ring_shown == shown:
		return
	_ring_shown = shown
	if _ring_fade_tween != null:
		_ring_fade_tween.kill()
	_glyph_ring.visible = true
	_ring_fade_tween = create_tween().set_parallel(true)
	for mi in _ring_meshes:
		_ring_fade_tween.tween_property(mi, "transparency",
				0.0 if shown else 1.0, RING_FADE_TIME) \
			.set_trans(Tween.TRANS_SINE)
	if not shown:
		# Fully faded out -> stop rendering the ring at all.
		_ring_fade_tween.chain().tween_callback(func() -> void:
			if not _ring_shown and _glyph_ring != null:
				_glyph_ring.visible = false)


# -- movement --------------------------------------------------------------


func move_to(world_pos: Vector3, walk_time: float = 0.4) -> void:
	## Walk (the tower glides with a slight bob) to a world position.
	## Await it; emits move_finished when the piece arrives.
	var start := position
	if start.distance_to(world_pos) < 0.01:
		move_finished.emit()
		return
	var dir := world_pos - start
	await _face(Vector3(dir.x, 0.0, dir.z))
	if piece_type != Type.KNIGHT and _anim != null:
		_anim.play(ANIM_WALK, 0.2)
	var tw := create_tween()
	if piece_type == Type.ROOK:
		# Static tower: glide with a subtle bob, no walk cycle to play.
		var bobs := maxf(1.0, roundf(dir.length()))
		var glide := func(t: float) -> void:
			position = start.lerp(world_pos, t) \
				+ Vector3.UP * absf(sin(t * PI * bobs)) * 0.05
		tw.tween_method(glide, 0.0, 1.0, walk_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	elif piece_type == Type.KNIGHT:
		# CANTER: the static horse's procedural walk — the ensemble glides
		# under a stride bob with a gentle rocking pitch; the rider rides
		# the rhythm without moving a muscle.
		var strides := maxf(1.0, roundf(dir.length()))
		var canter := func(t: float) -> void:
			position = start.lerp(world_pos, t) \
				+ Vector3.UP * absf(sin(t * PI * strides * 2.0)) * 0.03
			if _model != null:
				_model.rotation.x = sin(t * PI * strides * 4.0) * 0.05
		tw.tween_method(canter, 0.0, 1.0, walk_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		tw.tween_property(self, "position", world_pos, walk_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	if piece_type == Type.KNIGHT:
		if _model != null:
			_model.rotation.x = 0.0
	elif _anim != null:
		_anim.play(ANIM_IDLE, 0.25)
	_face_home()
	move_finished.emit()


func play_capture(victim: PieceView) -> void:
	## The capture duel: face the victim, strike (Throw — the free rig's
	## best attack read — sold with a weapon-trail flash), victim takes the
	## hit and dies. When the await returns the victim is dead and freed.
	## Mounted strike (knight): the horse steps in under the rider's Throw.
	var to_victim := victim.position - position
	await _face(Vector3(to_victim.x, 0.0, to_victim.z))
	victim.face_attacker(position)
	if _anim != null:
		if piece_type == Type.KNIGHT:
			_horse_step(to_victim)   # concurrent step-in while the rider strikes
		_anim.play(ANIM_THROW, 0.1)
		_anim.speed_scale = 1.3
		await get_tree().create_timer(0.5 / 1.3).timeout  # strike release beat
	else:
		await _tower_lunge(to_victim)
	_strike_flash(victim.global_position)
	await victim.die()
	if _anim != null:
		_anim.speed_scale = 1.0
		if piece_type == Type.KNIGHT:
			_reseat_rider()   # back to the still saddle pose, horse idles on
		else:
			_anim.play(ANIM_IDLE, 0.3)


func die() -> void:
	## Hit reaction, death animation, then the corpse sinks into the stone.
	## Emits died (with death_anim set) before freeing. Mounted death
	## (knight): the rider plays Death_A and tumbles out of the saddle while
	## the horse collapses through its own Death clip — same wall budget.
	if _anim != null:
		_anim.play(ANIM_HIT, 0.1)
		_anim.speed_scale = 1.2
		await get_tree().create_timer(PieceAssets.anim_length(ANIM_HIT) / 1.2 - 0.1).timeout
		_anim.speed_scale = 1.0
		_anim.play(ANIM_DEATH, 0.1)
		death_anim = ANIM_DEATH
		if piece_type == Type.KNIGHT:
			_mounted_fall(PieceAssets.anim_length(ANIM_DEATH))   # concurrent
		await get_tree().create_timer(PieceAssets.anim_length(ANIM_DEATH)).timeout
	else:
		death_anim = "Tower_Crumble"
		_drop_banner()   # the banner tears free and falls with the tower
		var fall := create_tween()
		fall.tween_property(self, "rotation:z", rotation.z + PI * 0.28, 0.4) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		await fall.finished
	var sink := create_tween()
	sink.tween_property(self, "position:y", position.y - 1.3, 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await sink.finished
	died.emit()
	queue_free()


func spawn_flourish() -> void:
	## Promotion arrival: Spawn_Ground plus an amber light burst. The
	## mounted knight's rider stays seated — the ensemble gives a hop.
	if piece_type == Type.KNIGHT:
		if _model != null:
			var hop := create_tween()
			hop.tween_property(_model, "position:y", 0.06, 0.16) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			hop.tween_property(_model, "position:y", 0.0, 0.22) \
				.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	elif _anim != null:
		_anim.play(ANIM_SPAWN, 0.05)
	var burst := OmniLight3D.new()
	burst.light_color = Color(1.0, 0.72, 0.35)
	burst.light_energy = 0.0
	burst.omni_range = 2.6
	burst.position = Vector3(0.0, 0.7, 0.0)
	add_child(burst)
	var tw := create_tween()
	tw.tween_property(burst, "light_energy", 4.5, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(burst, "light_energy", 0.0, 0.75) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(burst.queue_free)
	if piece_type != Type.KNIGHT and _anim != null:
		await get_tree().create_timer(PieceAssets.anim_length(ANIM_SPAWN)).timeout
		_anim.play(ANIM_IDLE, 0.3)


func face_attacker(attacker_pos: Vector3) -> void:
	var dir := attacker_pos - position
	_face(Vector3(dir.x, 0.0, dir.z))  # fire-and-forget turn


# -- internals -------------------------------------------------------------


func _face(dir: Vector3) -> void:
	## Smooth-turn to look along dir (world space). Awaitable.
	if dir.length_squared() < 0.0001 or piece_type == Type.ROOK:
		return
	var target_yaw := atan2(dir.x, dir.z)
	if absf(wrapf(target_yaw - rotation.y, -PI, PI)) < 0.05:
		return
	var tw := create_tween()
	tw.tween_property(self, "rotation:y", target_yaw, 0.14).set_trans(Tween.TRANS_SINE)
	await tw.finished


func _face_home() -> void:
	if piece_type == Type.ROOK:
		return
	var tw := create_tween()
	tw.tween_property(self, "rotation:y", _home_yaw, 0.18).set_trans(Tween.TRANS_SINE)


func _horse_step(to_victim: Vector3) -> void:
	## Mounted strike: the horse steps into the blow while the rider throws
	## — the whole ensemble advances and settles back. Fire-and-forget; the
	## step-back plays out under the victim's death.
	var dir := Vector3(to_victim.x, 0.0, to_victim.z).normalized()
	var start := position
	var tw := create_tween()
	tw.tween_property(self, "position", start + dir * 0.2, 0.24) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "position", start, 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _mounted_fall(window: float) -> void:
	## The knight's death, run concurrently with the rider's Death_A: the
	## rider tumbles out of the saddle to the ground on one side while the
	## horse keels over to the other, saddle and caparison riding it down
	## (they live inside the horse scene). The whole-piece sink in die()
	## then swallows the wreck.
	if _sway_tween != null:
		_sway_tween.kill()
		_sway_tween = null
	if _rider != null:
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_rider, "position",
				KNIGHT_RIDER_POS + KNIGHT_FALL_OFFSET, window * 0.55) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(_rider, "rotation:z", -0.4, window * 0.55) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if _horse != null:
		var htw := create_tween().set_parallel(true)
		htw.tween_property(_horse, "rotation:z", 1.35, window * 0.7) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		htw.tween_property(_horse, "position",
				_horse.position + Vector3(-0.35, 0.0, 0.0), window * 0.7) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _reseat_rider() -> void:
	## After a mounted strike the rider settles back into the still saddle
	## pose: blend to a neutral idle frame, freeze it, re-bend the seat.
	if _anim == null:
		return
	_anim.play(ANIM_IDLE, 0.25)
	var tree := get_tree()
	if tree != null:
		await tree.create_timer(0.35).timeout
	if _anim == null or not is_inside_tree():
		return
	_anim.pause()
	_apply_seat_pose()


## The static seat, calibrated against measured bone positions (rider-local,
## hips at y 0.39): knees forward and level with the hips, shins hanging
## down-back with the heels under the knee, thighs splayed outward over the
## barrel, arms down at the reins line.
##   SEAT_THIGH  local-X on upperleg.*  — negative swings the knee forward/up
##   SEAT_SHIN   local-X on lowerleg.*  — positive drops the heel back down
##   SEAT_SPLAY  local-Z on upperleg.*  — NEGATIVE opens the legs outward
## Manual bone poses persist because the rider's player is PAUSED while
## mounted — duel clips (Throw/Hit/Death) override them for exactly as long
## as they play, and _reseat_rider re-applies the seat afterwards.
const SEAT_THIGH := -45.0
const SEAT_SHIN := 50.0
const SEAT_SPLAY := -40.0
const SEAT_UPPERARM := 64.0
const SEAT_LOWERARM := -30.0


func _apply_seat_pose() -> void:
	var skel := _skeleton()
	if skel == null:
		return
	for side_key in ["l", "r"]:
		var flip := 1.0 if side_key == "l" else -1.0
		var seat := {
			"upperleg." + side_key: Quaternion(Vector3.RIGHT, deg_to_rad(SEAT_THIGH))
				* Quaternion(Vector3.BACK, deg_to_rad(SEAT_SPLAY * flip)),
			"lowerleg." + side_key: Quaternion(Vector3.RIGHT, deg_to_rad(SEAT_SHIN)),
			"upperarm." + side_key: Quaternion(Vector3.BACK, deg_to_rad(SEAT_UPPERARM * flip)),
			"lowerarm." + side_key: Quaternion(Vector3.RIGHT, deg_to_rad(SEAT_LOWERARM)),
		}
		for bone_name in seat:
			var idx := skel.find_bone(bone_name)
			if idx != -1:
				skel.set_bone_pose_rotation(idx,
						skel.get_bone_rest(idx).basis.get_rotation_quaternion()
						* seat[bone_name])


func _tower_lunge(to_victim: Vector3) -> void:
	## The rook has no skeleton: sell the strike with a heavy tilt-slam.
	var dir := Vector3(to_victim.x, 0.0, to_victim.z).normalized()
	var start := position
	var tw := create_tween()
	tw.tween_property(self, "position", start + dir * 0.22 + Vector3.UP * 0.12, 0.22) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "position", start, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished


## THE WEAPON TRAIL (critic defect #1, 2026-08-09). This used to be a bare
## 0.85 x 0.22 QuadMesh at 90 % mustard alpha, and every duel screenshot in
## the suite caught it as a filled rectangle over the fighters' heads — the
## "mustard rectangle" three critics read as an unfinished debug panel
## (measured: 433x112 px, 99 % fill, value 0.741 in duel/03; 0.940 in the
## slow-mo frame, where the time dip holds it open even longer).
##
## Three things changed, and each one independently makes a slab impossible:
##  1. SHAPE lives in the alpha now — PieceAssets.strike_trail_texture() paints
##     a tapered arc that reaches zero ink at both ends and falls off across
##     its width, so the mesh's rectangle is never a visible edge.
##  2. The blend is ADDITIVE, so the trail can only add light to what is
##     behind it. It can brighten a helmet; it cannot cover one.
##  3. It is born ALREADY SWEPT — it spawns wider than it is tall and keeps
##     stretching, so it is a streak from its first frame to its last, never
##     an unstretched shape waiting to stretch.
##
## TRAIL_LIFE is the one number NOT tuned toward "faster". At 0.16 s the arc
## was gone before the suite's mid-duel frame and every shipped screenshot
## showed a kill with no blow in it — a strike that does not read as a strike
## is the other half of the defect. 0.50 s with a quad EASE_OUT alpha spends
## most of itself as a dim tail: bright for a beat, then a fading streak the
## frame can still catch. Verified by regenerating all three duel frames.
##
## The quad is `top_level` so its world pose is set directly: the old code
## assigned a BOARD-space midpoint into the attacker's own rotated local
## space, which is what threw the flash off the strike line and left it
## floating over the duellists' heads instead of tracking the blade.
##
## ...and the corrected midpoint then hid the trail INSIDE the fight: at duel
## range the two combatants stand chest to chest, so the exact point between
## them is behind a body from every angle and the first corrected build
## rendered no strike at all. So the arc is pulled TRAIL_LIFT toward the live
## camera along the view ray — still on the blade line, but in front of the
## bodies that line runs through. Billboarded, so that offset always resolves
## to "in front" no matter which camera (board, duel, slow-mo) is looking.
const TRAIL_QUAD_SIZE := Vector2(0.86, 0.46)
const TRAIL_LIFE := 0.50
const TRAIL_LIFT := 0.45   # metres toward the camera, off the duellists' line


func _strike_flash(victim_world: Vector3) -> void:
	## A fast, thin, additive arc of light along the blade's path.
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = TRAIL_QUAD_SIZE
	quad.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = PieceAssets.strike_trail_texture()
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.72, 0.34)
	mat.emission_energy_multiplier = 1.4
	quad.name = "StrikeTrail"   # the name IS its role (PieceAssets.Role.EFFECT)
	quad.material_override = mat
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(quad)
	quad.top_level = true   # world pose, set below — never the attacker's frame
	var mid := (global_position + victim_world) * 0.5 + Vector3(0.0, 0.62, 0.0)
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		mid += (cam.global_position - mid).normalized() * TRAIL_LIFT
	quad.global_position = mid
	quad.rotation = Vector3(0.0, 0.0, randf_range(-0.35, 0.35))
	quad.scale = Vector3(1.05, 0.85, 1.0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(quad, "scale", Vector3(1.55, 0.55, 1.0), TRAIL_LIFE) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, TRAIL_LIFE) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(quad.queue_free)


# -- construction ----------------------------------------------------------


func _build_character() -> void:
	_model = PieceAssets.character_scene(piece_type, house_id).instantiate()
	_model.name = "Model"
	if piece_type == Type.BISHOP:
		_narrow_wizard_brim()   # BEFORE the height measure — it is the tallest mesh
	# Strict height grading: normalize each model's raw height to the type's
	# design height, so pawn<bishop<rook<queen<knight<king holds no matter
	# which cast (adventurer or skeleton) a house fields.
	var raw_h := _raw_model_height(_model)
	_model.scale = Vector3.ONE * (PieceAssets.piece_height(piece_type) / maxf(raw_h, 0.01))
	add_child(_model)
	_anim = AnimationPlayer.new()
	_anim.name = "Anim"
	_model.add_child(_anim)  # root_node ".." = the character scene root
	_anim.add_animation_library("", PieceAssets.shared_anims())
	_dress(_model)
	if piece_type == Type.BISHOP:
		_dress_mitre()   # AFTER the body tint — it repaints the hat's surfaces
	# Gear/crest/crown attach AFTER the body pass — each is dressed on its own
	# role (gear is split, a crest is KIT, a crown is REGALIA and takes no dye).
	_attach_gear()
	if PieceAssets.wants_crest(piece_type):
		_attach_crest()
	if PieceAssets.wants_helm(piece_type):
		_attach_helm()
	if piece_type == Type.KING:
		_attach_crown()
		_attach_cape()
	elif piece_type == Type.QUEEN:
		_attach_tiara()
	_anim.play(ANIM_IDLE)
	# Desynchronize the armies' idles.
	_anim.seek(randf() * PieceAssets.anim_length(ANIM_IDLE))
	_anim.speed_scale = randf_range(0.94, 1.06)


func _build_knight() -> void:
	## The MOUNTED knight (ISSUES.md #1): a horse+rider ensemble under one
	## Model root. The Quaternius horse is a static standing mesh animated
	## procedurally (see the class doc); the KayKit rider (adventurer or
	## Tidegrip skeleton — same casting table) sits a fixed transform in the
	## authored saddle, statically seat-posed. The Model carries the
	## quarter-turn reined stance (KNIGHT_MODEL_YAW) so the ensemble reads
	## as cavalry from the head-on gameplay camera while the ROOT still
	## points at the enemy line (and at duel victims). Height grading
	## normalizes the ENSEMBLE: the rider's helm is the reference point
	## (his crest, like the rook's pennant, is an accent above it).
	_model = Node3D.new()
	_model.name = "Model"
	_model.rotation.y = deg_to_rad(KNIGHT_MODEL_YAW)   # the reined-in stance
	add_child(_model)
	_horse = PieceAssets.HORSE.instantiate()
	_horse.name = "Horse"
	_horse.scale = Vector3.ONE * KNIGHT_HORSE_SCALE
	_model.add_child(_horse)
	_rider = PieceAssets.character_scene(piece_type, house_id).instantiate()
	_rider.name = "Rider"
	_rider.position = KNIGHT_RIDER_POS
	# Twisted in the saddle: the horse stands broadside for the silhouette,
	# the man stays turned toward the enemy line (see KNIGHT_MODEL_YAW).
	_rider.rotation.y = deg_to_rad(-KNIGHT_RIDER_COUNTER_YAW)
	_model.add_child(_rider)
	var raw_h := KNIGHT_RIDER_POS.y + _raw_model_height(_rider)
	_model.scale = Vector3.ONE * (PieceAssets.piece_height(piece_type) / maxf(raw_h, 0.01))
	_anim = AnimationPlayer.new()
	_anim.name = "Anim"
	_rider.add_child(_anim)  # root_node ".." = the rider scene root
	_anim.add_animation_library("", PieceAssets.shared_anims())
	# Costume: rider and mount both go through the same role dispatch, so the
	# man's tabard and the horse's crinet take the house while his plate stays
	# steel and the animal keeps its own COAT (PieceAssets.COAT_PALETTES — a
	# blue horse is a bug, not heraldry). Both carry the knight's rank value
	# trim (TYPE_VALUE_LIFT 0.88), so the ensemble is trimmed as one object and
	# the mount can never drift brighter than the man it carries. The
	# caparison is dressed in the house banner cloth below.
	_dress(_rider)
	_dress(_horse)
	_dress_caparison()
	# Gear/crest attach AFTER the tints so they keep their own colors.
	_attach_gear()
	if PieceAssets.wants_crest(piece_type):
		_attach_crest()
	# The mount breathes (procedural sway, desynced); the rider sits STILL
	# — his player parks on a neutral frame and the seat pose bends him in.
	_start_idle_sway()
	_anim.play(ANIM_IDLE)
	_anim.advance(0.0)
	_anim.pause()
	_apply_seat_pose()


## The static horse's idle: a slow weight-shift sway on the ensemble root,
## randomized per piece so the armies never breathe in lockstep.
func _start_idle_sway() -> void:
	if _sway_tween != null:
		_sway_tween.kill()
	var amp := randf_range(0.010, 0.016)
	var half := randf_range(1.3, 1.8)
	_sway_tween = create_tween().set_loops()
	_sway_tween.tween_property(_model, "rotation:z", amp, half) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_sway_tween.tween_property(_model, "rotation:z", -amp, half) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## HOUSE flourish: the knight's caparison wears the house banner cloth —
## primary-dyed, accent hem, the sigil reading on the horse's flank (the
## same composited texture the rook's banner flies; v=0 is the cloth TOP,
## matching the caparison's UVs). Legacy sides get plain dyed cloth.
func _dress_caparison() -> void:
	var cap := _model.find_child("Caparison", true, false) as MeshInstance3D
	if cap == null:
		return
	var mat := StandardMaterial3D.new()
	if HouseRegistry.has_house(house_id):
		mat.albedo_texture = PieceAssets.banner_texture(house_id)
	else:
		mat.albedo_color = HOUSE_TINT[side].darkened(0.12)
	# The cloth steps down with the ensemble (see _ensemble_trim): the banner's
	# accent hem was the brightest mark left on a trimmed knight.
	var trim := _ensemble_trim()
	mat.albedo_color = Color(mat.albedo_color.r * trim, mat.albedo_color.g * trim,
			mat.albedo_color.b * trim, mat.albedo_color.a)
	mat.roughness = 0.92
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cap.material_override = mat


## TYPE readability (critic defect #2): the mage cast's witch-hat brim is
## roughly TWICE the body width, and the gameplay camera looks down — so every
## bishop on the board was a saucer with a cone in the middle, hiding its own
## face, staff and body. Narrow the brim and lift the crown so the hat reads
## as a hat and the bishop underneath reads as a bishop. Both casts have one
## (`*Hat*`); the reshape is axis-symmetric so it needs no per-cast branch.
##
## The rebuild also SPLITS the hat into cone and brim surfaces (see
## PieceAssets.narrowed_hat_mesh) — remember which is which per mesh, because
## the swap replaces the mesh the split was keyed on.
func _narrow_wizard_brim() -> void:
	for mi: MeshInstance3D in _model.find_children("*Hat*", "MeshInstance3D",
			true, false):
		var narrowed := PieceAssets.narrowed_hat_mesh(mi.mesh)
		_mitre_brim[mi] = PieceAssets.hat_brim_surfaces(mi.mesh)
		mi.mesh = narrowed


## TYPE readability (critic P9, 2026-08-09): the near bishop measured the
## LOWEST value on its own back rank — mean 0.34/0.38 against 0.44-0.55 for
## every other piece — because the mage atlas paints its whole robe and mitre
## one dark navy, and a multiply-tint over a dark texture can only go darker.
## From the high rear camera that is a dark thimble with no internal shape.
##
## The mitre is therefore PAINTED rather than tinted (PieceAssets.painted_material
## drops the atlas entirely): the cone takes the house body color at
## MITRE_CROWN_WEIGHT — lifted clear of the robe but deliberately UNDER the
## royals, a bishop does not out-shine his king — and the brim takes the house
## CHARGE against that cone, which by the charge value law lands darker. One
## dark oval becomes a lit cone inside a contrasting band: a shape with a
## readable break, from directly above as well as from the side.
const MITRE_CROWN_WEIGHT := 0.72


func _dress_mitre() -> void:
	var body: Color = _body_tint()
	var cone := Color(body.r * MITRE_CROWN_WEIGHT, body.g * MITRE_CROWN_WEIGHT,
			body.b * MITRE_CROWN_WEIGHT)
	var band := cone.darkened(0.45)
	if HouseRegistry.has_house(house_id):
		# The charge comes back at a HOUSE colour's own value, which is outside
		# _body_tint() and therefore outside the rank's value correction. Left
		# that way it was the loudest thing on the near back rank — the whole
		# reason the bishop's lift had to invert. It steps down with him.
		var trim := _rank_value()
		var raw := PieceAssets.house_charge_color(house_id, cone)
		band = Color(raw.r * trim, raw.g * trim, raw.b * trim, raw.a)
	for mi: MeshInstance3D in _mitre_brim:
		if not is_instance_valid(mi):
			continue
		var brim: Dictionary = _mitre_brim[mi]
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if src == null:
				continue
			mi.set_surface_override_material(s, PieceAssets.painted_material(
					src, band if brim.has(s) else cone))


## Raw (unscaled) model height: top of the skinned meshes parented directly
## to the Skeleton3D. BoneAttachment3D accessories (hats, hoods) are
## excluded — their mesh AABBs live in bone space, not model space.
func _raw_model_height(model: Node3D) -> float:
	var top := 0.0
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.get_parent() is BoneAttachment3D:
			continue
		top = maxf(top, mi.mesh.get_aabb().end.y)
	return top


func _skeleton() -> Skeleton3D:
	## The CHARACTER's rig — for the mounted knight that is the RIDER's
	## skeleton (the horse has its own; gear/crest/pose never touch it).
	var host: Node3D = _rider if _rider != null else _model
	var skels := host.find_children("*", "Skeleton3D", true, false)
	return null if skels.is_empty() else skels[0]


## Rigid mount on a rig bone (the crown-attach pattern, generalized).
func _bone_mount(bone: String, mount_name: String) -> BoneAttachment3D:
	var skel := _skeleton()
	if skel == null or skel.find_bone(bone) == -1:
		return null
	var att := BoneAttachment3D.new()
	att.name = mount_name
	att.bone_name = bone
	skel.add_child(att)
	return att


## TYPE signature gear: rigid props on the rig's handslot/chest bones.
## Same gear for every house — the type IS the gear.
##
## The gear is DRESSED BY ROLE, and that is the fix for two opposite defects.
##
## It used to be attached after the body tint purely so it would "keep its own
## colors", and every army fielded a fluorescent magenta grimoire, a lime staff
## orb, a salmon shield rim and an orange-tan bow (defects #6/#7, 2026-08-08).
## The answer then was to dye ALL of it flat, which is how the sword, the bow
## and the leather grips ended up house-coloured too — half of the mono-colour
## complaint that this pass exists to answer.
##
## Now each prop goes through the role dispatch. A shield is KIT (a shield is a
## painted charge-board — it is the plate the sigil lands on). A sword, a staff,
## a grimoire, a bow and a quiver are MIXED: their steel stays cold steel and
## their leather stays leather, while the grimoire's magenta cover and the
## staff's lime orb — real dyed surfaces — take the house. The SIGIL DECAL is
## attached last and takes no dye at all: that plate IS heraldry.
func _attach_gear() -> void:
	for spec: Dictionary in PieceAssets.gear_specs(piece_type):
		var att := _bone_mount(spec["bone"], "GearMount_%s" % spec["key"])
		if att == null:
			continue
		var prop: Node3D = (spec["scene"] as PackedScene).instantiate()
		prop.name = "Gear_%s" % spec["key"]
		prop.position = spec["pos"]
		prop.rotation_degrees = spec["rot_deg"]
		prop.scale = Vector3.ONE * float(spec["scl"])
		att.add_child(prop)
		_dress(prop)
		if bool(spec["decal"]) and HouseRegistry.has_house(house_id):
			_attach_sigil_decal(prop, spec)


## HOUSE flourish: the house sigil painted on the shield face.
func _attach_sigil_decal(shield: Node3D, spec: Dictionary) -> void:
	var decal := MeshInstance3D.new()
	decal.name = "SigilDecal"
	var quad := QuadMesh.new()
	var s := float(spec.get("decal_size", 0.5))
	quad.size = Vector2(s, s)
	decal.mesh = quad
	decal.material_override = PieceAssets.sigil_material(house_id)
	decal.position = spec.get("decal_pos", Vector3(0.0, 0.0, 0.2))
	decal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shield.add_child(decal)


## HOUSE flourish: helmet crest on the head bone (knight/queen/king).
##
## A crest is KIT (PieceAssets.MATERIAL_ROLES) — the plume on top of the helm
## is exactly the sort of thing a house paints in its own colour, and it used
## to keep the crest GLB's authored per-house paint instead. That was a quiet
## defect on the dark houses: Hartcrown's primary is #1d1a17, so its stag rode
## into battle in near-black on a near-black skyline. Dressed through the role
## dispatch it takes the jersey, at the ensemble's own value trim.
func _attach_crest() -> void:
	var packed: PackedScene = PieceAssets.crest_scene(house_id)
	if packed == null:
		return
	var att := _bone_mount("head", "CrestMount")
	if att == null:
		return
	var crest: Node3D = packed.instantiate()
	crest.name = "Crest"
	crest.position = CREST_MOUNT_POS
	att.add_child(crest)
	_dress(crest)


## THE ENSEMBLE TRIMS AS ONE (critic defect #3, 2026-08-09). The rank's value
## correction reaches every surface through _dress(), including the two a
## knight wears outside his body — the caparison (house banner cloth) and the
## crest. Left untrimmed they simply became the new brightest marks on the
## ensemble: with the mount fixed, the caparison's accent hem measured 0.788
## and the wolf crest 0.776 against a king at 0.776 — the knight had stopped
## shouting and started tying. The caparison's texture cannot go through the
## role dispatch (it IS the house's artwork), so it takes the trim by hand.
func _ensemble_trim() -> float:
	return _rank_value()


## HOUSE flourish: the PAWN's half-helm on the head bone (ISSUES.md #3) — the
## footman's answer to the royal crest, and deliberately quieter than one: it
## wraps the skull instead of towering over it, and only its rim + motif take
## the house color while the shell stays plain dark iron. Same
## BoneAttachment3D pattern as crest/crown, so the helm tracks idle, walk and
## death animations for free, and — because _raw_model_height skips meshes
## under a BoneAttachment3D — it cannot disturb the height grading.
func _attach_helm() -> void:
	var packed: PackedScene = PieceAssets.pawn_helm_scene(house_id)
	if packed == null:
		return   # legacy FROST/EMBER pawns keep the body they shipped with
	var att := _bone_mount("head", "HelmMount")
	if att == null:
		return
	_doff_bear_hood()
	var helm: Node3D = packed.instantiate()
	helm.name = "Helm"   # NEVER "Crest"/"Crown"/"Tiara" — those names are contracts
	helm.position = HELM_MOUNT_POS
	att.add_child(helm)
	_dress_helm(helm)


## The Barbarian (the pawn body for all eight living houses) ships wearing a
## full bear-skull hood that completely swallows a helm. HIDE it — never free
## it: _raw_model_height measures mesh AABBs regardless of visibility, and the
## hood is the model's TALLEST mesh (top 2.398 vs the bald head's 2.186), so
## removing the node would drop raw_h and silently scale every living-house
## pawn up ~10%, breaking the strict height grading. Hiding changes nothing —
## and the skull underneath is complete front and back, so it leaves no hole.
func _doff_bear_hood() -> void:
	for mi: MeshInstance3D in _model.find_children(
			PieceAssets.BEAR_HOOD_PATTERN, "MeshInstance3D", true, false):
		mi.visible = false


## HOUSE flourish: the pawn's helm, dressed in TWO house colors.
##
## THE DOME USED TO BE PLAIN BLACK IRON, deliberately — "that restraint is
## what keeps a footman humble". At board distance the restraint cost the game
## its pawn ranks: every army's front row was "a row of identical black
## beads", and on the pale houses that black rank "visually belongs to a
## different army than its own back rank" (critic defect #11). Nine houses,
## one helmet.
##
## So the weight is inverted: the DOME carries the house color (dyed dark —
## dark enough that a pawn is still plainly humbler than the crested royal
## behind him) and the rim + motif carry the house CHARGE, the heraldic color
## furthest from that dome (PieceAssets.house_charge_color — the fix for a
## Thornvale rose that was green-on-green and invisible, defect #9). The
## Drowned Legion's dome is dyed darker still: charred, but charred in
## Tidegrip's own green rather than in nobody's black (defect #8).
##
## THE RIM IS NO LONGER THE BRIGHTEST THING ON THE PIECE (critic P8,
## 2026-08-09). "Furthest from the dome" kept electing the house's palest
## heraldic color, so every near piece wore a near-white plate on the very top
## of its silhouette — 0.78 value (peak 0.93) against a 0.59 dome, measured on
## the boot frame. The charge value law now lives in house_charge_color and
## puts the mark UNDER the dome on any helm bright enough to carry it; nothing
## here changed except that the color it hands back is a cut, not a flare.
##
## Materials are found BY NAME, never by surface index.
const HELM_SHELL_WEIGHT := 0.72
const HELM_SHELL_WEIGHT_DROWNED := 0.46


func _dress_helm(helm: Node3D) -> void:
	var body: Color = _tint_for("kit")
	var weight := HELM_SHELL_WEIGHT_DROWNED \
			if house_id == PieceAssets.SKELETON_HOUSE else HELM_SHELL_WEIGHT
	var shell := Color(body.r * weight, body.g * weight, body.b * weight)
	var charge := shell.darkened(0.45)   # legacy sides wear no helm; see _attach_helm
	if HouseRegistry.has_house(house_id):
		charge = PieceAssets.house_charge_color(house_id, shell)
	for mi: MeshInstance3D in helm.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s)
			if not src is StandardMaterial3D:
				continue
			var mat_name := str(src.resource_name)
			if mat_name.begins_with(PieceAssets.HELM_ACCENT_MATERIAL):
				# FLAT dye, not a multiply: the Drowned Legion's helm ships
				# with its accent baked charcoal, and multiplying a charge
				# into that landed #242c27 on a #2c3732 dome — invisible, the
				# very failure this dressing exists to end.
				mi.set_surface_override_material(
					s, PieceAssets.dyed_material(src, charge, 0.92))
			elif mat_name.begins_with(PieceAssets.HELM_IRON_MATERIAL):
				mi.set_surface_override_material(
					s, PieceAssets.dyed_material(src, body, weight))


func _attach_crown() -> void:
	## The king's crown (custom prop — measured numbers from the props'
	## INTEGRATION.md): a BoneAttachment3D on the Rig_Medium `head` bone so
	## the crown tracks idle, walk, and death animations for free. Attached
	## AFTER the body pass; a crown is REGALIA and takes no house dye at all.
	var att := _bone_mount("head", "CrownMount")
	if att == null:
		return
	var crown: Node3D = PieceAssets.crown_scene(_tint_for("kit")).instantiate()
	crown.name = "Crown"
	crown.position = Vector3(0.0, 0.80, 0.0)   # ring at the skull's crown line
	crown.rotation.y = deg_to_rad(-20.0)       # battle-bent point toward the camera
	crown.scale = Vector3.ONE * CROWN_SCALE
	att.add_child(crown)


func _attach_tiara() -> void:
	## The queen's circlet (royal swap 2026-08-08): the same gold/frost crown
	## prop, scaled visibly slimmer and flatter — a light tiara band, never
	## mistakable for the king's full crown at gameplay distance. Named
	## "Tiara" (NOT "Crown") — e2e board-truth proves queens uncrowned by
	## grepping for a node named Crown.
	var att := _bone_mount("head", "TiaraMount")
	if att == null:
		return
	var tiara: Node3D = PieceAssets.crown_scene(_tint_for("kit")).instantiate()
	tiara.name = "Tiara"
	tiara.position = Vector3(0.0, 0.86, 0.0)   # band on the crown of the head
	tiara.scale = TIARA_SCALE                  # slim ring, points flattened
	# The crown GLB's INTERNAL nodes are also named Crown* — rename them or
	# the queen reads "crowned" to every Crown-node check (e2e board-truth,
	# the costume validator). The name IS the contract.
	for child in tiara.find_children("*", "", true, false):
		if str(child.name).containsn("crown"):
			child.name = str(child.name).replacen("crown", "TiaraBand")
	att.add_child(tiara)


## TYPE signature gear (king): the cape, draped from the chest bone.
## Neutral cloth in the GLB; tinted here with the house secondary color
## (palette flourish only — the cape shape is the same for every house).
func _attach_cape() -> void:
	var att := _bone_mount("chest", "CapeMount")
	if att == null:
		return
	var cape: Node3D = PieceAssets.CAPE.instantiate()
	cape.name = "Cape"
	cape.position = CAPE_MOUNT_POS
	att.add_child(cape)
	_dress(cape)   # cape_cloth is KIT — the king wears the jersey, loudly


## TYPE readability: the engraved glyph ring under the piece. Child of the
## PieceView root (not the model) so height grading never rescales it.
## Built HIDDEN (transparency 1, invisible) — hover/selection reveal it.
func _build_glyph_ring() -> void:
	_glyph_ring = PieceAssets.glyph_ring_scene(piece_type).instantiate()
	_glyph_ring.name = "GlyphRing"
	_glyph_ring.position = Vector3(0.0, 0.004, 0.0)
	add_child(_glyph_ring)
	# Per-piece duplicate of the emissive glyph material so selection can
	# brighten THIS ring only; the plate/disc/inlay under it are dressed in
	# the house body color (critic P7 — they shipped near-black and the
	# medallion read as a hole punched in the amber selection tile).
	var body: Color = _body_tint()   # the jersey — the ring is this army's mark
	var plate := {
		PieceAssets.RING_MEDAL_MATERIAL: PieceAssets.RING_MEDAL_WEIGHT,
		PieceAssets.RING_STONE_MATERIAL: PieceAssets.RING_STONE_WEIGHT,
		PieceAssets.RING_INLAY_MATERIAL: PieceAssets.RING_INLAY_WEIGHT,
	}
	for mi: MeshInstance3D in _glyph_ring.find_children("*", "MeshInstance3D", true, false):
		_ring_meshes.append(mi)
		mi.transparency = 1.0   # hidden at rest (ISSUES.md #2)
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s)
			if not src is StandardMaterial3D:
				continue
			var mat_name := str((src as StandardMaterial3D).resource_name)
			if mat_name == PieceAssets.GLYPH_MATERIAL_NAME:
				_glyph_mat = (src as StandardMaterial3D).duplicate()
				_glyph_mat.emission_energy_multiplier = PieceAssets.GLYPH_ENERGY_REST
				# Critic defect #17: engraved WHITE, sitting on the floor
				# under the piece, the glyph rendered as "a white blob half
				# buried in the shadow — a stray specular highlight, not an
				# icon". Two causes, two fixes: it was painted in nobody's
				# color (now the house CHARGE, so it reads as this army's
				# mark), and it was lying inside its own piece's contact
				# shadow (now exempt from receiving one).
				var glyph: Color = body
				if HouseRegistry.has_house(house_id):
					glyph = HouseRegistry.get_colors(house_id)["accent"]
				_glyph_mat.albedo_color = glyph
				_glyph_mat.emission = glyph
				_glyph_mat.disable_receive_shadows = true
				mi.set_surface_override_material(s, _glyph_mat)
			elif plate.has(mat_name):
				var dressed := PieceAssets.dyed_material(
						src as StandardMaterial3D, body, plate[mat_name])
				dressed.disable_receive_shadows = true
				mi.set_surface_override_material(s, dressed)
	_glyph_ring.visible = false


func _build_tower() -> void:
	## The BANNER-ROOK: battle-worn watchtower, house banner down the face,
	## fluttering pennant on top (assets/custom-props/watchtower.glb).
	_model = PieceAssets.WATCHTOWER.instantiate()
	_model.name = "Model"
	var body := _model.find_child("TowerBody", true, false) as MeshInstance3D
	var raw_h := body.mesh.get_aabb().end.y if body != null else 1.35
	_model.scale = Vector3.ONE * (PieceAssets.piece_height(piece_type) / maxf(raw_h, 0.01))
	add_child(_model)
	# The masonry is STONE and the rod is WOOD — natural, so a watchtower is a
	# watchtower in every house and only takes the faint tower whisper. Its
	# house identity is the banner down its face and the pennant on top, both
	# skinned below with the house's own artwork.
	_dress(_model, ["BannerCloth", "Pennant"], _tint_for("tower"))
	_dress_banner()
	_dress_pennant()


func _dress_banner() -> void:
	var banner := _model.find_child("BannerCloth", true, false) as MeshInstance3D
	if banner == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = PieceAssets.banner_texture(house_id)
	mat.roughness = 0.92
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	banner.material_override = mat


func _dress_pennant() -> void:
	var pennant := _model.find_child("Pennant", true, false) as MeshInstance3D
	if pennant == null:
		return
	var cloth: Color = HOUSE_TINT[side]
	if HouseRegistry.has_house(house_id):
		cloth = HouseRegistry.get_colors(house_id)["accent"]
	var mat := ShaderMaterial.new()
	mat.shader = PieceAssets.PENNANT_SHADER
	mat.set_shader_parameter("cloth_color", cloth)
	pennant.material_override = mat


func _drop_banner() -> void:
	## Crumble flourish: the banner tears off and falls with the tower.
	if _model == null:
		return
	var banner := _model.find_child("BannerCloth", true, false) as MeshInstance3D
	var holder := get_parent()
	if banner == null or holder == null:
		return
	var xform := banner.global_transform
	banner.get_parent().remove_child(banner)
	holder.add_child(banner)
	banner.global_transform = xform
	var mat := banner.material_override as StandardMaterial3D
	if mat != null:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var tw := banner.create_tween().set_parallel(true)
	tw.tween_property(banner, "position:y", banner.position.y - 0.55, 0.7) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(banner, "rotation:x", banner.rotation.x - 0.9, 0.7)
	if mat != null:
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.7)
	tw.chain().tween_callback(banner.queue_free)


## THE TYPE VALUE LADDER — per-rank corrections to the house tint's VALUE.
##
## The house tint is one color for a whole army, but a rank's cast decides how
## much of it survives: a mage painted one dark navy comes out darker than his
## own army no matter what you multiply into him, and a knight who arrives as
## a man PLUS a horse comes out as twice the lit surface of anybody else. Both
## are TYPE facts, like the height grading, and both are corrected on the same
## axis the grading uses — one number per rank, applied in HSV with hue and
## SATURATION untouched so this can never become a way to smuggle a piece out
## of its house. (The palette envelope measures hue; it would catch us.)
##
## BISHOP 1.18 (critic P9, 2026-08-09): the mage cast is painted one dark navy
## from hem to hat and measured the dimmest piece on the near back rank in
## both files — mean value 0.34 and 0.38 against 0.42-0.55 for everyone else.
##
## KNIGHT 0.88 (critic defect #3, 2026-08-09) — the correction pointing DOWN,
## and the first one to. The mounted ensemble is the only rank that fields two
## bodies, and at rider-weight 1.0 its rider ALREADY ties the king's peak
## (measured: rider head 0.777/0.780 against a king at 0.776) while the horse
## beside him ran 0.784-0.875 across an area the size of two pieces. A rank
## that ties the crown and then doubles its area does not read as cavalry, it
## reads as the brightest object on the board — which is the king's job. The
## trim buys the crown its hierarchy back: the whole ensemble, rider and mount
## together, now peaks a clear step under the king.
## QUEEN 0.95 (role pass, 2026-08-09). The Rogue_Hooded cast is a full hooded
## ROBE, which under the role rule is one enormous KIT surface — so the rank
## that used to be the darkest piece on the board became the loudest, and her
## peak passed the king's (measured on the boot frame: queen p90 0.878 against
## a king at 0.867). A queen is allowed to blaze; she is not allowed to out-top
## the crown. The trim puts the king back on top by a clear step and leaves her
## far-side median at 0.40, comfortably inside her rank's band — the black-hole
## win from the last pass is untouched.
## BISHOP 0.90 (role pass, 2026-08-09) — the correction INVERTED, because the
## thing it corrected for is gone. It existed because the mage cast is painted
## one dark navy from hem to hat and a multiply-tint over dark navy can only go
## darker (P9: mean value 0.34 against 0.42-0.55 for the rest of the rank).
## Under the role rule his robe is KIT — it takes the jersey at full strength
## instead of multiplying into the atlas — and his hair takes a black-point
## lift instead. Left at 1.18 on top of that he swung the other way and became
## the BRIGHTEST piece on his own back rank (median 0.694 against a king at
## 0.612, measured on the boot frame). A bishop does not out-shine his king in
## either direction.
const TYPE_VALUE_LIFT := {
	Type.BISHOP: 0.90,
	Type.KNIGHT: 0.88,
	Type.QUEEN: 0.95,
}

## THE QUEEN'S TONE FLOOR (critic defect #2, 2026-08-09) — a VALUE fix that is
## deliberately NOT a tint change, because her hue win from the last pass is
## kept intact. See PieceAssets.QUEEN_TONE_FLOOR for the mechanism and the
## measurement; the constant lives there because it operates on the texture.
## THE BISHOP'S HAIR (role pass, 2026-08-09). The mage atlas paints his hair
## and hood in near-BLACK — #181818, #202020, #282028, together 44 % of the
## texels his head mesh lands on — and the role rule correctly calls near-black
## NATURAL, so the old army-wide dye no longer lifts it. From the gameplay
## camera, which looks down at the top of a head, that turned the near bishop
## back into the dark thimble P9 fought: median value 0.20 against a rank
## running 0.36-0.65. His mitre is fine; it is his SCALP that vanishes. So his
## natural half gets the same black-point lift the queen's does — value, and
## only value.
const TYPE_TONE_FLOOR := {
	Type.QUEEN: PieceAssets.QUEEN_TONE_FLOOR,
	Type.BISHOP: 0.24,
}


## THE JERSEY: the colour every KIT surface on this piece is painted in — the
## house's `tints.kit`, with the rank's value correction applied. Tabard,
## cloak, hood, shield face, helm, crest, the mitre paint and the glyph plate
## all take it, and NOTHING else does: steel, leather, skin, bone, wood and the
## horse's coat go through _natural() instead. (Legacy FROST/EMBER sides have
## no house entry and keep their two consts.)
func _body_tint() -> Color:
	var kit: Color = _tint_for("kit")
	var lift: float = _rank_value()
	if is_equal_approx(lift, 1.0):
		return kit
	return Color.from_hsv(kit.h, kit.s, minf(1.0, kit.v * lift), kit.a)


## This rank's value correction — see TYPE_VALUE_LIFT. Applied to kit AND
## natural surfaces alike, so a rank steps as one object.
func _rank_value() -> float:
	return TYPE_VALUE_LIFT.get(piece_type, 1.0)


## The rank's texture black-point lift — see TYPE_TONE_FLOOR.
func _tone_floor() -> float:
	return TYPE_TONE_FLOOR.get(piece_type, 0.0)


## A house tint by role ("kit" / "piece" / "tower"): HouseRegistry colors when
## a house id was given, the legacy FROST/EMBER consts otherwise.
func _tint_for(role: String) -> Color:
	if house_id.is_empty():
		return HOUSE_TINT_TOWER[side] if role == "tower" else HOUSE_TINT[side]
	return HouseRegistry.get_house_tint(house_id, role)


## The natural coat this house's mount wears — never a house hue.
func _coat() -> Dictionary:
	return PieceAssets.coat_palette(house_id)


# -- role dispatch ---------------------------------------------------------
#
# THE REPLACEMENT FOR "DYE EVERYTHING" (owner critique, 2026-08-09: "too much
# mono color, should be like a hockey team jersey — colors of the team/house,
# but NOT everywhere"). Every surface is CLASSIFIED first
# (PieceAssets.MATERIAL_ROLES) and only then coloured:
#
#   KIT       -> the house jersey, confidently saturated
#   NATURAL   -> its own material's colours, plus a faint house whisper
#   MIXED     -> the mesh is split per triangle by what the atlas paints it,
#                and each half goes down one of the two paths above
#   REGALIA   -> untouched metal (the crown and tiara dress themselves)
#   HERALDRY  -> untouched artwork (sigil, banner, caparison, pennant, ring)
#   EFFECT    -> owns its own light
#
# An UNCLASSIFIED surface is left undressed on purpose: PieceAssets.classify
# has already shouted, and the role gate fails on it. Silently dyeing the
# unknown case is the exact habit that produced nine monochrome armies.


## Dress every mesh under `root`. `skip_names` are left completely alone (the
## banner and pennant, which are re-skinned by hand with the house artwork);
## `whisper` overrides the tint natural surfaces take a hint of — the rook's
## masonry uses the tower tint, everything else the piece tint.
func _dress(root: Node, skip_names: Array = [], whisper: Color = Color.BLACK) -> void:
	var cast_tint := whisper if whisper != Color.BLACK else _tint_for("piece")
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.name in skip_names:
			continue
		_dress_mesh(mi, cast_tint)


func _dress_mesh(mi: MeshInstance3D, cast_tint: Color) -> void:
	var probe := mi.mesh.surface_get_material(0) as StandardMaterial3D
	var probe_name := "" if probe == null else str(probe.resource_name)
	if PieceAssets.classify(str(mi.name), probe_name)["role"] == PieceAssets.Role.MIXED:
		_dress_split_mesh(mi, cast_tint)
		return
	for s in mi.mesh.get_surface_count():
		var src := mi.get_active_material(s) as StandardMaterial3D
		if src == null:
			continue
		_apply_role(mi, s, src, PieceAssets.classify(
				str(mi.name), str(src.resource_name)), cast_tint)


## A MIXED mesh: swap in the role-split variant (KIT triangles and NATURAL
## triangles on separate surfaces — see PieceAssets.role_split_mesh) and paint
## the two halves apart. The split never moves a vertex, so the mesh AABB the
## height grading measures is bit-identical to the source's.
func _dress_split_mesh(mi: MeshInstance3D, cast_tint: Color) -> void:
	var src_mesh := mi.mesh
	var split := PieceAssets.role_split_mesh(src_mesh)   # populates the roles
	var roles: Dictionary = PieceAssets.split_surface_roles(src_mesh)
	mi.mesh = split
	for s in split.get_surface_count():
		var src := split.surface_get_material(s) as StandardMaterial3D
		if src == null:
			continue
		var role: int = roles.get(s, PieceAssets.Role.NATURAL)
		if role == PieceAssets.Role.KIT:
			mi.set_surface_override_material(s, PieceAssets.kit_material(
					src, _tint_for("kit"), _rank_value()))
		else:
			mi.set_surface_override_material(s, PieceAssets.natural_material(
					src, PieceAssets.Stuff.ATLAS, cast_tint, _rank_value(),
					_tone_floor()))


func _apply_role(mi: MeshInstance3D, s: int, src: StandardMaterial3D,
		cls: Dictionary, cast_tint: Color) -> void:
	var role: int = cls["role"]
	var stuff: int = cls["stuff"]
	if role == PieceAssets.Role.KIT:
		mi.set_surface_override_material(s, PieceAssets.kit_material(
				src, _tint_for("kit"), _rank_value()))
	elif role == PieceAssets.Role.NATURAL:
		if stuff == PieceAssets.Stuff.COAT:
			mi.set_surface_override_material(s, PieceAssets.coat_material(
					src, _coat(), _rank_value()))
		else:
			mi.set_surface_override_material(s, PieceAssets.natural_material(
					src, stuff, cast_tint, _rank_value(), _tone_floor()))
	# REGALIA / HERALDRY / EFFECT dress themselves; UNCLASSIFIED is left bare
	# so the role gate can find it.
