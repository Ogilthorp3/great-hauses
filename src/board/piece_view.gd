class_name PieceView
extends Node3D
## A Great Hauses combatant on the board — a real KayKit character (the
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
## on the ensemble, a canter bob on moves (the rider sits still), a full
## gather-and-GALLOP for the capture duel (_kill_charge), and on death the
## rider slides off through Death_A while the horse keels over sideways.
## Face-to-face duel rotation applies to this PieceView root, so the whole
## ensemble turns as one.
##
## SIX RANKS, SIX WAYS TO KILL (2026-08-09): pawn stab · knight charge ·
## bishop fire-bolt (no contact) · rook grind · queen arrow · king execution,
## each with three variants, each answered by its own victim death. The table
## and the reasoning are at KILL_STYLES; the choreography is under "the six
## kills"; the retargeting judgement call is on play_capture.
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
const ANIM_HIT_B := "Hit_B"
const ANIM_DEATH := "Death_A"
const ANIM_DEATH_B := "Death_B"
const ANIM_SPAWN := "Spawn_Ground"

## EVERY RANK KILLS IN ITS OWN HAND (owner brief, 2026-08-09: "different
## killing animations so it's not boring"). Until today every capture was the
## same three beats — walk in, `Throw`, victim `Hit_A` then `Death_A` — so the
## tenth duel of a game was frame-for-frame the first. Now the kill is a
## property of the TYPE, and it is the type's own GEAR that decides it:
##
##   PAWN      stab       steps inside the guard, sword low, quick and brutal
##   KNIGHT    charge     the horse gathers and gallops; the victim is
##                        trampled and LAUNCHED, never cut
##   BISHOP    bolt       NO CONTACT — he gives ground, raises the staff, and
##                        a bolt of fire crosses the gap (the dracarys kit)
##   ROOK      grind      the tower does not walk: it rolls OVER him. Dust.
##   QUEEN     arrow      she looses from where she stands; it takes him in
##                        the chest
##   KING      execution  a slow two-handed raise, one downward blow
##
## Each has KILL_VARIANTS approach/timing/follow-through variants, and the
## victim answers with its own variety (Hit_A/Hit_B, Death_A/Death_B, the
## direction he falls), so two duels of the same rank still differ.
##
## The clips are the KayKit Rig_Medium library the cast already ships with
## (Throw · Hit_A/B · Death_A/B) driven at different speeds and combined with
## PROCEDURAL motion — lunges, gathers, gallops, launches, squash. Cross-vendor
## retargeting of the Quaternius Universal library was evaluated and declined
## (see the KILL SIGNATURES note above `play_capture`).
const KILL_STAB := "stab"
const KILL_CHARGE := "charge"
const KILL_BOLT := "bolt"
const KILL_GRIND := "grind"
const KILL_ARROW := "arrow"
const KILL_EXECUTION := "execution"
const KILL_STYLES := {
	Type.PAWN: KILL_STAB,
	Type.ROOK: KILL_GRIND,
	Type.KNIGHT: KILL_CHARGE,
	Type.BISHOP: KILL_BOLT,
	Type.QUEEN: KILL_ARROW,
	Type.KING: KILL_EXECUTION,
}
## Approach/timing/follow-through variants per style — see each _kill_* func.
const KILL_VARIANTS := 3

## ── THE RANGED RANKS DO NOT WALK INTO THEIR OWN KILL (owner, 2026-08-09) ───
##
## "The Queen should kill with her arrow at a distance and the bishop too with
## his magic staff."
##
## Chess moves a capturing piece ONTO its victim's square, and the presentation
## followed the rule: game.gd walks every attacker to `victim - dir * 0.55`,
## THEN plays the duel there. For four ranks that is the whole point — a stab, a
## charge, a grind and an execution all happen at arm's length. For the two that
## kill at range it is backwards, and it is why the queen never read as an
## archer no matter how well the bow was drawn: she closed to half a square
## before nocking. An archer who walks up to you is not an archer; a mage who
## comes close enough to touch you is not casting.
##
## The order these two now play, and the engine is not involved in any of it:
##   1. the attacker HOLDS its own square and turns to face across the board,
##   2. it looses / casts, and the shaft or the bolt crosses the REAL distance
##      between the two squares — four squares look like four squares, and the
##      flight scales with them (_loose_arrow, _kill_bolt),
##   3. the victim dies where he stands,
##   4. and only then does the attacker walk in and take the square.
##
## Step 4 is not new code: it is game.gd's own `move_to(target)` after the duel,
## which was always there. All that changed is that step 1's APPROACH walk no
## longer happens for these two — see `move_to`. Board state, move application,
## FEN and the wire are untouched: this is presentation ORDER, decided from the
## piece's own rank, so both machines in a head-to-head animate it identically
## from the same broadcast move.
const RANGED_STYLES: Array[String] = [KILL_ARROW, KILL_BOLT]

## Nothing loosed or cast may leave the frame with less than this much air in
## it. With the approach suppressed a real capture is at least one square away
## and this never fires; it is the floor for the two cases that would otherwise
## still be point-blank — a capture on the very next square, and any caller that
## stands the duellists up by hand (the e2e kills bench does exactly that).
const RANGED_MIN_GAP := 1.65
## …and the most ground a ranged rank will ever give to reach that floor.
const RANGED_GIVE_MAX := 1.15


## True for the ranks that kill at range (queen · bishop). Static so the
## director and the suites can ask about a TYPE without standing one up.
static func rank_is_ranged(pt: int) -> bool:
	return str(KILL_STYLES.get(pt, KILL_STAB)) in RANGED_STYLES


## Is `p` the centre of a board square? BoardView lays its tiles on a
## TILE_SIZE grid whose centres sit at half-tile offsets, so every legal
## destination satisfies this and the duel's approach mark — `target - dir *
## STAND_OFF` for a unit `dir` and a stand-off strictly inside one tile — can
## never satisfy it. That is the whole test: a `move_to` that is NOT to a
## square is the duel approach, whoever asked for it and whatever stand-off
## they used. tests/test_kill_styles.gd proves both halves over all 64 squares
## and all eight directions.
static func _is_board_square(p: Vector3) -> bool:
	var half := BoardView.TILE_SIZE * 0.5
	return is_zero_approx(fposmod(p.x + half, BoardView.TILE_SIZE)) \
		and is_zero_approx(fposmod(p.z + half, BoardView.TILE_SIZE))

## TWO FIGHTERS MUST READ AS TWO FIGURES — the closest a kill may bring two
## bodies, in world units, centre to centre.
##
## game.gd walks every capturing piece to `target - dir * 0.55`, and the pawn's
## stab then stepped another 0.30 INSIDE that. A quarter of a world unit between
## two chibi bodies whose helms alone are ~0.3 across is not a duel, it is one
## silhouette: the shipped frame (kills/02_kill_pawn, 2026-08-09) came back as
## "a tangle of interpenetrating meshes — the blue pawn's helm inside the gold
## pawn's torso", and the showcase reel picked that frame. It is also the kill a
## player sees more than any other, because a pawn taking a pawn is the most
## frequent capture in chess.
##
## So no kill CLOSES any more. The ones that used to now WIND UP and lunge to a
## line they may not cross — the blade arrives, the man does not — and the
## follow-through carries them apart again. The floor is per-killer because a
## destrier is not a man: STAND_OFF is a body plus a blade, MOUNTED_STAND_OFF
## adds the horse's chest and head in front of the rider.
##
## Both numbers were settled by rendering the six kills and LOOKING at them
## (render → look → adjust), which is the only instrument that answers "do these
## two read as two men". Anything that changes them must re-render kills/.
const STAND_OFF := 0.66
const MOUNTED_STAND_OFF := 0.92
## How far the ensemble gathers BACKWARD before a charge. A mounted charge is
## the run, not the contact: at the old 0.34 the horse covered 0.13 world units
## between gather and impact, which is a shuffle no amount of camera can sell.
const KNIGHT_CHARGE_GATHER := 1.05
## How far a crushed body is driven along its own back as the weight lands, so
## it comes to rest CLEAR of the footprint that killed it (see _die_crushed).
const CRUSH_SHOVE := 0.44

## How the VICTIM goes down. Passed by the killer to die(); the empty string
## is the legacy path (Hit_A -> Death_A), which stays byte-for-byte what it
## was because checkmate and the costume suite both call `die()` bare.
const DEATH_BLADE := "blade"
const DEATH_LAUNCH := "launch"
const DEATH_BURN := "burn"
const DEATH_CRUSH := "crush"
const DEATH_ARROW := "arrow"
const DEATH_CRUMBLE := "crumble"

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

## ── A CREST MAY NOT SWALLOW THE BAND (critic blocker, 2026-08-09) ──────────
##
## "Winterfang's queen wears no tiara": measured on the shipped gameplay frame,
## ZERO pixels of either regalia tone. Reproduced off the meshes rather than off
## the frame — ray-cast every tiara triangle toward the gameplay camera and count
## the ones the crest does not block (tests/test_costumes.gd::_test_royal_band_reads,
## and it is the same instrument here):
##
##   winterfang 0.0 %  ·  duskfire 55.6 %  ·  thornvale 68.5 %  ·  tidegrip 74.0 %
##   silverbrook 79.6 %  ·  swiftcrest 84.7 %  ·  ashwyrm 87.4 %  ·  goldclaw 89.6 %
##   hartcrown 90.4 %                                     (near-army direction)
##
## The cause was not the tiara. It was that Winterfang's crest is the one pack
## whose crest is a DRAPE — a wolf pelt hanging off the skull — so where the other
## eight sit ON the head (their lowest geometry lands at bone y 0.96..1.06, at or
## above the skull crown at 0.945) hers hung down to y 0.63 and the band at
## y 0.86..1.09 lived INSIDE it. It is also the tallest by far (0.99 against
## 0.22..0.54), which is the same fact from the other end.
##
## So a crest is now FITTED rather than trusted: measured on instantiation, scaled
## down if it is taller than the rank's headroom allows, and lifted until its
## lowest geometry stands on the crest line. One rule, applied to all nine, and
## eight of them barely move — the outlier is the only thing that had to.
## The band stays exactly where it was: a tiara belongs on a head, and moving it
## up to escape a crest is how you get a circlet floating in mid-air.
const CREST_FLOOR_Y := 1.10        ## no crest geometry below this (bone space)
const CREST_MAX_HEIGHT := 0.62     ## …and none taller than the tallest of the nine
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
## It is the NAME OF THE CLIP that played (or "Tower_Crumble"), which is the
## contract game.gd's death_log and the costume suite both read; the FLAVOUR
## of the death lives in death_style beside it.
var death_anim := ""
## How this piece went down ("" until it dies): DEATH_BLADE/LAUNCH/BURN/
## CRUSH/ARROW/CRUMBLE. e2e reads it to prove a signature kill landed.
var death_style := ""
## The kill this piece last performed (KILL_STAB…KILL_EXECUTION) and which
## variant of it fired. Set by play_capture BEFORE the first beat, so a test
## can read them the moment the strike callable starts.
var kill_style := ""
var kill_variant := -1
## TEST SEAM: pin the next kill's variant (-1 = pick at random, which is the
## only thing gameplay ever does). The suites walk all three variants of all
## six kills with this; nothing in src/ writes it.
var kill_variant_force := -1

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
var _bolt: Node3D           # bishop only: the DracarysVFX kit, built on the first bolt


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
	_bolt = null
	kill_style = ""
	kill_variant = -1
	death_style = ""
	death_anim = ""
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
	# THE ARCHER HOLDS HER GROUND (see RANGED_STYLES). A ranged rank asked to
	# walk to a point that is not a square is being walked into its own kill —
	# it turns to face the fight instead, and stays where it is. The walk that
	# takes the square still happens: it is the caller's NEXT move_to, after the
	# victim is down, and it is to a real square so it runs normally.
	if rank_is_ranged(piece_type) and not _is_board_square(world_pos):
		await _face(Vector3(dir.x, 0.0, dir.z))
		move_finished.emit()
		return
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


## KILL SIGNATURES — the capture duel, dispatched on the attacker's TYPE.
##
## Face the victim (the director holds that lock through the strike), then run
## the rank's own choreography; when the await returns the victim is dead and
## freed. `kill_style` / `kill_variant` are set BEFORE the first beat so a test
## reading them from inside the strike callable sees the truth.
##
## ON RETARGETING (evaluated 2026-08-09, declined). The Quaternius Universal
## Animation Library ships the clips this brief describes by name —
## Sword_Attack, Spell_Simple_Shoot, Hit_Chest — but it is a DIFFERENT RIG:
## different bone names, different rest pose, different root scale, and this
## project has already been bitten once by cross-vendor skinning (the horse,
## whose FBX-lineage rig corrupts in-engine at piece scale — PieceAssets.HORSE
## — and which we ship as a STATIC mesh animated procedurally for exactly that
## reason). A retarget pass is a bone-map plus a rest-pose reconciliation plus
## a per-clip QA sweep across five casts and nine houses, and it buys clips we
## can approximate: `Throw` at 2.1x IS a fast stab, `Throw` at 0.5x IS a heavy
## two-handed raise. So the variety is bought with SPEED, PROCEDURAL MOTION and
## VFX instead — which is also the pattern the banner-rook and the mount
## already prove out. If a later pass wants true per-type clips, do the retarget
## as its own turn with its own gate; it is not a free rider on this one.
func play_capture(victim: PieceView) -> void:
	var to_victim := victim.position - position
	kill_style = str(KILL_STYLES.get(piece_type, KILL_STAB))
	kill_variant = kill_variant_force if kill_variant_force >= 0 \
		else randi() % KILL_VARIANTS
	await _face(Vector3(to_victim.x, 0.0, to_victim.z))
	victim.face_attacker(position)
	match piece_type:
		Type.KNIGHT:
			await _kill_charge(victim)
		Type.BISHOP:
			await _kill_bolt(victim)
		Type.ROOK:
			await _kill_grind(victim)
		Type.QUEEN:
			await _kill_arrow(victim)
		Type.KING:
			await _kill_execution(victim)
		_:
			await _kill_stab(victim)


## Hit reaction, death animation, then the corpse sinks into the stone.
## Emits died (with death_anim set) before freeing.
##
## `style` is the killer's signature (DEATH_* above). The BARE call — which is
## what the checkmate cinematic and the costume suite make — is deliberately
## unchanged: Hit_A, Death_A, sink, death_anim "Death_A". Everything new hangs
## off an explicit style, so nothing that already depended on this contract can
## be surprised by a randomised clip.
func die(style: String = "") -> void:
	death_style = style
	if _anim == null:
		# The watchtower does not bleed; it comes down. (Also the path any
		# rig-less stand-in takes.)
		if death_style.is_empty():
			death_style = DEATH_CRUMBLE
		death_anim = "Tower_Crumble"
		_drop_banner()   # the banner tears free and falls with the tower
		var fall := create_tween()
		fall.tween_property(self, "rotation:z", rotation.z + PI * 0.28, 0.4) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		await fall.finished
	else:
		match style:
			DEATH_BURN:
				await _die_burning()
			DEATH_LAUNCH:
				await _die_launched()
			DEATH_CRUSH:
				await _die_crushed()
			"":
				await _die_struck(ANIM_HIT, 1.2, ANIM_DEATH, 1.0, 0.0)
			_:
				var clip := _victim_death_clip()
				await _die_struck(_victim_hit_clip(style), randf_range(1.15, 1.5),
					clip, _victim_death_speed(clip), randf_range(-0.42, 0.42))
	await _sink()
	died.emit()
	queue_free()


# ── the six kills ─────────────────────────────────────────────────────────


## PAWN — THE LUNGE. It used to be "he steps INSIDE the guard", and inside the
## guard is where two chibi bodies become one lump of geometry (see STAND_OFF).
## The verb is the same brutal one; the staging is the opposite. He drops back
## into a low guard — which opens real ground, so what follows is a MOVEMENT and
## not a nudge — then throws himself forward behind the point and stops at the
## stand-off line. The reach is the blade's; the bodies never touch.
## Variants: 0 straight thrust · 1 off-line (he slips to a flank first) ·
## 2 the double tap (a jab short, a beat, then the one that lands).
func _kill_stab(victim: PieceView) -> void:
	var dir := _flat_dir_to(victim)
	var home := position
	var flank := Vector3.ZERO
	if kill_variant == 1:
		flank = dir.cross(Vector3.UP).normalized() * (0.24 if randf() < 0.5 else -0.24)
	var guard := home - dir * 0.30 + flank
	var mark := _mark_off(victim, STAND_OFF) + flank
	if _anim != null:
		_anim.play(ANIM_THROW, 0.04)
		_anim.speed_scale = 1.9 if kill_variant == 0 else 2.1
	var wind := create_tween()
	wind.tween_property(self, "position", guard, 0.16) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await wind.finished
	if kill_variant == 2:
		# The feint: a short jab that stops well short, then the real one.
		var feint := create_tween()
		feint.tween_property(self, "position", guard.lerp(mark, 0.45), 0.09) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		await feint.finished
		await _beat(0.1)
	var lunge := create_tween()
	lunge.tween_property(self, "position", mark, 0.11) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await lunge.finished
	# The arc lands ON him, not halfway back to the man who threw it — the gap
	# between the two is the whole point of the staging above.
	_strike_flash(victim.global_position, {"height": 0.36, "scale": 0.78, "life": 0.36,
		"at": global_position.lerp(victim.global_position, 0.74)})
	await victim.die(DEATH_BLADE)
	_settle_attacker()
	var back := create_tween()
	back.tween_property(self, "position", home, 0.22) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await back.finished


## KNIGHT — THE MOUNTED CHARGE, sold by the ENSEMBLE rather than by the horse's
## legs. The mount is a static mesh (PieceAssets.HORSE — its rig corrupts at
## piece scale), so a gallop can never come from the animal itself; it has to
## come from everything around it. Three things do the work, and the shipped
## charge had none of them:
##
##  1. THE HORSE TURNS ONTO HIM. At rest the mount stands broadside to the root
##     (KNIGHT_MODEL_YAW) so a chess piece reads as cavalry from the head-on
##     gameplay camera. But the duel camera films ACROSS the duel line, and
##     broadside-to-the-root is square to THAT lens: the shipped frame was a
##     horse facing the camera with all four legs planted and a rider looking
##     past his own victim. A charging horse points where it charges — the
##     ensemble squares up for the run (which puts the animal in true PROFILE
##     for the duel camera, the shot that sells a charge) and re-seats after.
##  2. A REAL RUN. It gathers a full KNIGHT_CHARGE_GATHER backwards and covers
##     that ground in the same third of a second the old 0.13-unit shuffle took,
##     so the speed is in the picture even in one frame.
##  3. DUST AND CARRY. Hooves scuff at the gather, throw a bank on the run, and
##     the ensemble carries a stride PAST the man it rode down before wheeling
##     home — a charge that stops dead on contact is a step.
##
## The victim is TRAMPLED and launched, never cut.
## Variants: 0 straight down the file · 1 a wide approach that converges ·
## 2 a deeper rear-up and a heavier slam.
func _kill_charge(victim: PieceView) -> void:
	var dir := _flat_dir_to(victim)
	var home := position
	var flank := dir.cross(Vector3.UP).normalized()
	_mount_yaw(0.0, 0.0, 0.22)   # concurrent: horse and rider square onto him
	var gather := home - dir * (KNIGHT_CHARGE_GATHER + (0.22 if kill_variant == 2 else 0.0)) \
		+ flank * (0.34 if kill_variant == 1 else 0.0)
	var rear := create_tween().set_parallel(true)
	rear.tween_property(self, "position", gather, 0.26) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if _model != null:
		rear.tween_property(_model, "rotation:x", -0.32 if kill_variant == 2 else -0.16,
			0.26).set_trans(Tween.TRANS_QUAD)
	await rear.finished
	_dust_puff(global_position, 18, 0.42)   # the hooves dig in
	if _anim != null:
		_anim.play(ANIM_THROW, 0.04)   # the sword comes out, extended
		_anim.speed_scale = 1.6
	var impact := _mark_off(victim, MOUNTED_STAND_OFF)
	var from := position
	var run := maxf(from.distance_to(impact), 0.01)
	var strides := maxf(2.0, roundf(run * 2.2))
	var scuffed := {"n": 0}
	var charge := create_tween()
	var gallop := func(t: float) -> void:
		position = from.lerp(impact, t) \
			+ Vector3.UP * absf(sin(t * PI * strides)) * 0.08
		if _model != null:
			_model.rotation.x = sin(t * PI * strides * 2.0) * 0.1 - 0.05 * (1.0 - t)
		# Dust thrown BEHIND the run, at two marks along it — the trail is what
		# says "this covered ground" in a single frame.
		if t > 0.32 and int(scuffed["n"]) < 1:
			scuffed["n"] = 1
			_dust_puff(from.lerp(impact, 0.3), 14, 0.5)
		elif t > 0.66 and int(scuffed["n"]) < 2:
			scuffed["n"] = 2
			_dust_puff(from.lerp(impact, 0.62), 14, 0.55)
	charge.tween_method(gallop, 0.0, 1.0, 0.34 if kill_variant == 2 else 0.32) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await charge.finished
	if _model != null:
		_model.rotation.x = 0.0
	_strike_flash(victim.global_position, {"height": 0.8, "scale": 1.35, "life": 0.44,
		"at": global_position.lerp(victim.global_position, 0.7)})
	_dust_puff(victim.global_position, 30, 0.72)   # hooves on stone
	# The trample and the carry-through run TOGETHER: he is thrown off his feet
	# while the ensemble is still moving over the ground he stood on.
	var gone := _fell(victim, DEATH_LAUNCH)
	var carry := create_tween()
	carry.tween_property(self, "position", impact + dir * 0.26, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await carry.finished
	await _await_death(gone, victim)
	_settle_attacker()
	_mount_yaw(KNIGHT_MODEL_YAW, -KNIGHT_RIDER_COUNTER_YAW, 0.3)   # back to the reins
	var wheel := create_tween()
	wheel.tween_property(self, "position", home, 0.36) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await wheel.finished


## Turn the mounted ensemble: the horse to `model_deg` off the root's forward,
## the rider to `rider_deg` off the horse. Fire-and-forget, so it runs under
## whatever beat calls it. A no-op on every rank that is not cavalry.
## The two rest values are KNIGHT_MODEL_YAW / -KNIGHT_RIDER_COUNTER_YAW; a
## charge takes both to zero (everyone points at the victim) and puts them back.
func _mount_yaw(model_deg: float, rider_deg: float, sec: float) -> void:
	if piece_type != Type.KNIGHT:
		return
	var tw := create_tween().set_parallel(true)
	if _model != null:
		tw.tween_property(_model, "rotation:y", deg_to_rad(model_deg), sec) \
			.set_trans(Tween.TRANS_SINE)
	if _rider != null:
		tw.tween_property(_rider, "rotation:y", deg_to_rad(rider_deg), sec) \
			.set_trans(Tween.TRANS_SINE)


## BISHOP — NO CONTACT. He gives ground rather than closing, raises the staff,
## and a bolt of fire crosses the gap; the victim burns where he stands. The
## fire is the DRACARYS kit (assets/vfx/dracarys.gd) at bolt scale — the same
## instrument the wyrm breathes with, wired the same way (tune BEFORE
## add_child; the kit builds itself in _ready).
## Variants: 0 one bolt · 1 two pulses · 2 a high bolt that falls onto him.
func _kill_bolt(victim: PieceView) -> void:
	var dir := _flat_dir_to(victim)
	var home := position
	# HE CASTS FROM WHERE HE STANDS (see RANGED_STYLES). The old fixed
	# half-step back existed only because the caller had already marched him
	# onto his victim; it now fires only when something really has parked him
	# inside his own spell.
	var give := _ranged_give_ground(victim) * (0.62 if kill_variant == 2 else 1.0)
	var stand := home - dir * give
	var give_ground := create_tween()
	give_ground.tween_property(self, "position", stand, 0.24 if give > 0.01 else 0.02) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# THE BOLT MUST CROSS THE BOARD IT IS FIRED ACROSS. The kit bakes `reach`
	# into its shaders at build time, so the range is measured HERE, before the
	# staff comes up, from the gap the shot actually has to cover.
	_prepare_bolt(_flat_gap_to(victim) - give)
	if _anim != null:
		_anim.play(ANIM_THROW, 0.05)   # the staff comes up
		_anim.speed_scale = 1.15
	await give_ground.finished
	await _beat(0.2)
	var chest := victim.global_position + Vector3.UP * _chest_height(victim)
	# …AND IT MUST BE HELD LONG ENOUGH TO CROSS IT. The kit's `reach` is how far
	# the torrent gets; the DURATION is how long it is on screen, and a bolt
	# thrown across four squares in the same 0.42 s a one-square bolt takes
	# arrives as a flash rather than as a shot. Same law as the arrow's flight
	# (_loose_arrow), same shape: proportional, floored at the old value so a
	# point-blank cast is unchanged, and capped so the hall is never just lit.
	var span := clampf(_flat_gap_to(victim) / RANGED_MIN_GAP, 1.0, 2.2)
	match kill_variant:
		1:
			_fire_bolt(chest, 0.24 * span)
			await _beat_wall(0.34)
			_fire_bolt(chest, 0.3 * span)
		2:
			var high := chest + Vector3.UP * 1.0
			_fire_bolt(high, 0.5 * span)
			await _sweep_bolt(high, chest, 0.22 * span)
		_:
			_fire_bolt(chest, 0.42 * span)
	await _beat_wall(0.16 * span)
	await victim.die(DEATH_BURN)
	_stop_bolt()
	_settle_attacker()
	if give > 0.01:
		var ret := create_tween()
		ret.tween_property(self, "position", home, 0.26) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await ret.finished


## ROOK — THE GRIND, and THE CRUSH IS ON SCREEN NOW. A watchtower has no arms:
## it comes forward over the square and what is standing on it goes under it.
##
## The shipped frame (kills/05_kill_rook, 2026-08-09) was "a tower alone on a
## square with no victim, no crush and no debris" — the whole verb was invisible,
## for three compounding reasons, each fixed here or in _die_crushed:
##   * the tower ROLLED ONTO the man and stopped on top of him, so the only
##     witness to the kill was hidden under the thing that did it. He is DRIVEN
##     ALONG the tower's line now (_die_crushed's shove) and comes to rest just
##     beyond its leading face, flattened on the stone in full view;
##   * the death squashed him to a 12 % pancake — nothing left to see at duel
##     distance. He is laid out, not erased;
##   * one puff of dust in the middle of a tower is one puff of dust. The bite
##     throws a LOW WIDE BANK across the leading face (_dust_bank), and the
##     tower shudders as the weight comes down — the masonry judder is doubled
##     at the moment of contact and it drops into its own footing after.
## Dust, not blood — and the tower still ends the duel standing on the square it
## took (test_kill_styles asserts exactly that).
## Variants: 0 a steady roll · 1 a heavy lean into it · 2 rise, then drop on
## him first and grind through.
func _kill_grind(victim: PieceView) -> void:
	var dir := _flat_dir_to(victim)
	var home := position
	var over := victim.position
	var stop := over + dir * 0.1
	if kill_variant == 2:
		var rise := create_tween()
		rise.tween_property(self, "position", home + Vector3.UP * 0.16, 0.16) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		rise.tween_property(self, "position", home, 0.1) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		await rise.finished
		_dust_bank(global_position, dir, 12)
	var lean: float = 0.15 if kill_variant == 1 else 0.08
	var start := position
	var bite := {"hit": false}
	var grind := create_tween()
	var roll := func(u: float) -> void:
		position = start.lerp(stop, u) + Vector3.UP * absf(sin(u * PI * 3.0)) * 0.03
		# The judder doubles from the moment the leading face takes the man.
		var shake: float = 0.02 if not bool(bite["hit"]) else 0.045
		rotation.z = sin(u * PI * 7.0) * shake         # masonry judder
		rotation.x = -lean * sin(u * PI)               # it leans into the weight
	grind.tween_method(roll, 0.0, 1.0, 0.62 if kill_variant == 1 else 0.55) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _beat(0.22)   # the shadow reaches him
	bite["hit"] = true
	# The bank is thrown across the LEADING FACE, on the near side of the man —
	# in front of the mass, where the eye is already looking.
	_dust_bank(victim.global_position - dir * 0.2, dir, 16)
	var gone := _fell(victim, DEATH_CRUSH)
	await grind.finished
	rotation.x = 0.0
	rotation.z = 0.0
	# It settles into its own footing: a short drop, and the last of the dust.
	var settle := create_tween()
	settle.tween_property(self, "position", stop - Vector3.UP * 0.05, 0.09) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	settle.tween_property(self, "position", stop, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_dust_bank(global_position, dir, 16)
	await settle.finished
	await _await_death(gone, victim)


## QUEEN — THE BOW. She never closes: she draws, looses, and the arrow takes him
## in the chest.
##
## THE ARROW LANDS BEFORE HE FALLS, and until 2026-08-09 it did not. The shipped
## frame (kills/06_kill_queen) caught "arrows hanging in mid-air BEHIND an
## already-fallen victim" — the timing read inverted, the kill read as a
## coincidence. Two causes, both closed:
##   * variant 2 loosed its first arrow FIRE-AND-FORGET and only awaited the
##     second, so one shaft was still in the air when the man went down. Both
##     are awaited now: arrow, arrow, a beat, THEN the fall;
##   * every shaft flew at a chest point sampled once, before the shot, so an
##     arrow that arrived a frame late arrived where the chest USED to be and
##     stuck to nothing. _loose_arrow re-reads the victim's live chest every
##     frame — it follows him down and buries itself in the body.
## Variants: 0 a flat fast shot · 1 a lobbed arc · 2 two shafts, the second on
## the heels of the first.
##
## AND THE BOW IS DRAWN WHILE SHE DOES IT — see _bow_draw for why the shot had
## no drawn bow in it at all until 2026-08-09, and for the measurement.
func _kill_arrow(victim: PieceView) -> void:
	# SHE OPENS THE RANGE FIRST. game.gd walks every capturing piece to
	# `target - dir*0.55`, which puts an archer close enough to hand the man
	# her arrow — and a bow shot with no flight in it is just a stab with a
	# strange prop. She gives ground while she draws (and takes it back after),
	# so the arrow is in the air long enough to be seen.
	var dir := _flat_dir_to(victim)
	var home := position
	var draw := _bow_draw(victim)   # limbs up, arrow on the string
	var give := _ranged_give_ground(victim)
	var open_range := create_tween()
	open_range.tween_property(self, "position", home - dir * give,
		0.26 if give > 0.01 else 0.02) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if _anim != null:
		_anim.play(ANIM_THROW, 0.05)   # draw and loose
		_anim.speed_scale = 1.0 if kill_variant == 1 else 1.3
	await open_range.finished
	# The windup has run; park the clip on its archer pose (BOW_DRAW_FRAME) and
	# hold there. _settle_attacker's Idle is what lets her move again.
	if _anim != null and _anim.current_animation == ANIM_THROW:
		_anim.seek(BOW_DRAW_FRAME, true)
		_anim.pause()
	await _beat(0.16)   # HELD at full draw — the beat the silhouette lives in
	draw["nocked"] = false   # the string is empty from here: the shaft is flying
	if kill_variant == 2:
		await _loose_arrow(victim, 0.0, Vector3(randf_range(-0.07, 0.07), 0.1, 0.0))
		draw["nocked"] = true    # the second shaft, on the heels of the first
		await _beat(0.1)
		draw["nocked"] = false
	await _loose_arrow(victim, 0.34 if kill_variant == 1 else 0.0)
	draw["nocked"] = true   # …and she has already drawn again
	await _beat(0.12)   # the shaft is IN him, and read, before he goes
	await victim.die(DEATH_ARROW)
	_settle_attacker()
	if give > 0.01:
		var close_range := create_tween()
		close_range.tween_property(self, "position", home, 0.24) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await close_range.finished
	draw["live"] = false   # …and only now does the bow go back to her side


## KING — THE EXECUTION. Two hands, a slow raise the eye has time to read,
## and one downward blow that ends it.
## Variants: 0 straight overhead · 1 a step into it · 2 a side sweep taken
## across the body (the victim spins as he falls).
func _kill_execution(victim: PieceView) -> void:
	var dir := _flat_dir_to(victim)
	var home := position
	if _anim != null:
		_anim.play(ANIM_THROW, 0.06)
		_anim.speed_scale = 0.5        # THE RAISE — deliberately slow
	if kill_variant == 1:
		# THE STEP STOPS AT THE STAND-OFF LINE. It used to be a flat +0.24 from
		# wherever he happened to be standing, which on gameplay's 0.55 approach
		# put a king 0.31 world units from his victim — the pawn's
		# interpenetration defect, one rank up and not yet photographed. A blow
		# needs the room to fall through; the two bodies do not need to touch.
		var step := create_tween()
		step.tween_property(self, "position", _mark_off(victim, STAND_OFF), 0.36) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _beat(0.55)
	if _anim != null:
		_anim.speed_scale = 2.6        # THE BLOW
	await _beat(0.12)
	if kill_variant == 2:
		_strike_flash(victim.global_position,
			{"height": 0.62, "scale": 1.35, "life": 0.5, "tilt": 0.1})
	else:
		_strike_flash(victim.global_position,
			{"height": 0.78, "scale": 1.2, "life": 0.5, "tilt": PI * 0.5})
	_dust_puff(victim.global_position, 16, 0.6)
	await victim.die(DEATH_BLADE if kill_variant == 2 else DEATH_CRUSH)
	_settle_attacker()
	if kill_variant == 1:
		var back := create_tween()
		back.tween_property(self, "position", home, 0.26) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		await back.finished


# ── kill plumbing ─────────────────────────────────────────────────────────


func _settle_attacker() -> void:
	if _anim == null:
		return
	_anim.speed_scale = 1.0
	if piece_type == Type.KNIGHT:
		_reseat_rider()   # back to the still saddle pose, horse idles on
	else:
		_anim.play(ANIM_IDLE, 0.3)


func _flat_dir_to(victim: Node3D) -> Vector3:
	var d := victim.position - position
	d.y = 0.0
	return d.normalized() if d.length() > 0.001 else Vector3.FORWARD


## Flat board distance to the victim — the length of the shot, in squares.
func _flat_gap_to(victim: Node3D) -> float:
	var d := victim.position - position
	d.y = 0.0
	return d.length()


## How far back a ranged rank steps before it shoots: ZERO whenever the shot
## already has RANGED_MIN_GAP of air in it, which — with the approach walk
## suppressed — is every real capture beyond the adjacent square. She holds her
## square; she does not retreat from a fight she is winning at range.
func _ranged_give_ground(victim: Node3D) -> float:
	return clampf(RANGED_MIN_GAP - _flat_gap_to(victim), 0.0, RANGED_GIVE_MAX)


## NOTE `_flat_gap_to` is GONE. Its only caller was the charge's old
## `impact = home + dir * max(gap - 0.42, 0.06)` — a distance measured from
## where the attacker happened to be standing, which is exactly the reasoning
## _mark_off replaces: the stand-off is a property of the VICTIM's square, not
## of the killer's approach. Leaving a second way to compute a strike point
## behind is how two kills end up disagreeing about where a body is.


## THE STAND-OFF LINE: the point `d` world units short of the victim, on the
## duel line, at this attacker's own height. Every kill that used to close on a
## body now stops here instead — see STAND_OFF for the frame that earned the
## rule. It is an absolute mark, not a step: a lunge that overshoots its target
## by a hand still lands on the line.
func _mark_off(victim: Node3D, d: float) -> Vector3:
	var dir := _flat_dir_to(victim)
	var v := victim.position
	return Vector3(v.x - dir.x * d, position.y, v.z - dir.z * d)


## Where an arrow is aiming THIS frame: the victim's chest, live.
func _arrow_aim(victim: PieceView, offset: Vector3) -> Vector3:
	if not is_instance_valid(victim):
		return global_position
	return victim.global_position + Vector3.UP * _chest_height(victim) + offset


## Roughly where a piece's chest is, in world units above its feet — the
## height grading makes this a per-type number, not a constant.
func _chest_height(piece: PieceView) -> float:
	return PieceAssets.piece_height(piece.piece_type) * 0.62


## A scaled beat (bends with the duel's slow-mo, like every other tween here).
func _beat(sec: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	await tree.create_timer(sec).timeout


## A WALL-CLOCK beat — for the dracarys kit only, which runs its own timeline
## on Time.get_ticks_usec and is immune to the time_scale the duel bends.
## Waiting on a scaled timer for a wall-clock effect drifts them apart.
func _beat_wall(sec: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	await tree.create_timer(sec, true, false, true).timeout


## Start a death concurrently with the attacker's follow-through; returns a
## flag dict to hand to _await_death.
func _fell(victim: PieceView, style: String) -> Dictionary:
	var gone := {"v": false}
	victim.died.connect(func() -> void: gone["v"] = true, CONNECT_ONE_SHOT)
	victim.die(style)   # fire and forget — the caller waits on the flag
	return gone


func _await_death(gone: Dictionary, victim: PieceView) -> void:
	while not bool(gone["v"]) and is_instance_valid(victim):
		var tree := get_tree()
		if tree == null:
			return
		await tree.process_frame


func _sink() -> void:
	var sink := create_tween()
	sink.tween_property(self, "position:y", position.y - 1.3, 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await sink.finished


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


## NOTE the old `_horse_step` (a 0.2-unit step-in under the rider's Throw) and
## `_tower_lunge` (a tilt-slam for the rig-less rook) are GONE — `_kill_charge`
## and `_kill_grind` are what those two beats grew into, and leaving the
## originals behind as dead code would have left two ways to strike with the
## same piece.


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


## `opts` shapes the arc per KILL (all optional, defaults = the numbers this
## trail was tuned to): "height" metres above the fighters' feet · "scale"
## overall size · "life" seconds · "tilt" radians (PI/2 = the king's vertical
## chop) · "tint" emission colour · "at" a world point to anchor the arc on
## INSTEAD of the midpoint between the fighters (the queen's arrow strikes
## where it lands, which is not halfway to the man who shot it).
func _strike_flash(victim_world: Vector3, opts: Dictionary = {}) -> void:
	## A fast, thin, additive arc of light along the blade's path.
	var height: float = float(opts.get("height", 0.62))
	var size: float = float(opts.get("scale", 1.0))
	var life: float = float(opts.get("life", TRAIL_LIFE))
	var tilt: float = float(opts.get("tilt", randf_range(-0.35, 0.35)))
	var tint: Color = opts.get("tint", Color(1.0, 0.72, 0.34))
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = TRAIL_QUAD_SIZE * size
	quad.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = PieceAssets.strike_trail_texture()
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.85)
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 1.4
	quad.name = "StrikeTrail"   # the name IS its role (PieceAssets.Role.EFFECT)
	quad.material_override = mat
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(quad)
	quad.top_level = true   # world pose, set below — never the attacker's frame
	var mid: Vector3 = opts.get("at", (global_position + victim_world) * 0.5) \
		+ Vector3(0.0, height, 0.0)
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		mid += (cam.global_position - mid).normalized() * TRAIL_LIFT
	quad.global_position = mid
	quad.rotation = Vector3(0.0, 0.0, tilt)
	quad.scale = Vector3(1.05, 0.85, 1.0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(quad, "scale", Vector3(1.55, 0.55, 1.0), life) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, life) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(quad.queue_free)


# ── the victim's side ─────────────────────────────────────────────────────
#
# The other half of "so the tenth duel does not look like the first": a
# repeated kill still varies because the man taking it answers differently —
# which of the two hit reactions he plays, which of the two death clips, how
# fast, and which way he falls. The LEGACY bare die() is exempt on purpose
# (see die()); everything here is reached only through an explicit style.


func _victim_hit_clip(style: String) -> String:
	if style == DEATH_ARROW:
		return ANIM_HIT   # taken in the chest — the short recoil, always
	return ANIM_HIT if randf() < 0.5 else ANIM_HIT_B


func _victim_death_clip() -> String:
	return ANIM_DEATH if randf() < 0.6 else ANIM_DEATH_B


## Death_B is 2.63 s against Death_A's 0.80 — a duel cannot spend that, so
## when it is drawn it is played fast enough to land in the same ~0.8-1.1 s
## window. (Measured the hard way: left at 1.0x it pushed a single stab to
## 4.2 s wall, past the budget the whole cinematic is built around.)
func _victim_death_speed(clip: String) -> float:
	if clip == ANIM_DEATH_B:
		return randf_range(2.35, 2.75)
	return randf_range(0.95, 1.2)


## The standard fall: a hit reaction, then a death clip, with `fall_yaw`
## twisting the MODEL (never the root — the director's face-lock owns the
## root's yaw through the strike and would overwrite it) so bodies do not all
## drop along the same line.
func _die_struck(hit_clip: String, hit_speed: float, death_clip: String,
		death_speed: float, fall_yaw: float) -> void:
	if not hit_clip.is_empty():
		_anim.play(hit_clip, 0.1)
		_anim.speed_scale = hit_speed
		await _beat(maxf(PieceAssets.anim_length(hit_clip) / hit_speed - 0.1, 0.05))
	if _model != null and not is_zero_approx(fall_yaw):
		_model.rotation.y += fall_yaw
	_anim.speed_scale = death_speed
	_anim.play(death_clip, 0.1)
	death_anim = death_clip
	var window := PieceAssets.anim_length(death_clip) / death_speed
	if piece_type == Type.KNIGHT:
		_mounted_fall(window)   # concurrent: rider off the saddle, horse over
	await _beat(window)


## TRAMPLED. No hit reaction — he is off his feet before he can take one:
## Death_A plays while the ensemble that hit him throws him back and over.
## Death_A specifically, because a launch is a SHORT beat and because the
## mounted-capture contract (test_costumes) reads this clip name.
func _die_launched() -> void:
	death_anim = ANIM_DEATH
	_anim.speed_scale = 1.15
	_anim.play(ANIM_DEATH, 0.05)
	var window := PieceAssets.anim_length(ANIM_DEATH) / 1.15
	if piece_type == Type.KNIGHT:
		_mounted_fall(window)
	# He faces his killer (face_attacker + the director's lock), so his own
	# BACK is the direction he is thrown.
	var away := -global_transform.basis.z
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.BACK
	var p0 := global_position
	var spin := randf_range(-0.5, 0.5)
	var tw := create_tween().set_parallel(true)
	var arc := func(u: float) -> void:
		global_position = p0 + away * (0.78 * u) + Vector3.UP * (sin(u * PI) * 0.4)
	tw.tween_method(arc, 0.0, 1.0, window * 0.8) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if _model != null:
		tw.tween_property(_model, "rotation:x", -1.25, window * 0.8) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(_model, "rotation:y", _model.rotation.y + spin, window * 0.8)
	await _beat(window)


## CRUSHED under the tower (or under the king's blow): he collapses and then the
## weight lands — dust goes up, and there is no blood in it at all.
##
## HE IS DRIVEN OUT FROM UNDER IT. Twice over, this death used to leave nothing
## to look at: the weight came down on the man's own square, and the man was
## squashed to a 12 % pancake ON that square — so the rook's kill frame shipped
## as a tower standing alone with no victim anywhere in it. He now goes down
## ALONG HIS OWN BACK (he faces his killer, so -Z is the way the mass throws
## him) far enough to clear the footprint, and he is LAID OUT rather than
## erased: a body-length silhouette on the stone is what reads at duel distance.
func _die_crushed() -> void:
	death_anim = ANIM_DEATH
	_anim.speed_scale = 1.5
	_anim.play(ANIM_DEATH, 0.05)
	if piece_type == Type.KNIGHT:
		_mounted_fall(PieceAssets.anim_length(ANIM_DEATH) / 1.5)
	# The direction the weight throws him: away from whoever he is facing.
	var away := -global_transform.basis.z
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.BACK
	var p0 := global_position
	await _beat(0.14)
	if _model != null:
		var flat := Vector3(_model.scale.x * 1.24, _model.scale.y * 0.34,
			_model.scale.z * 1.24)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_model, "scale", flat, 0.26) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(_model, "rotation:y",
			_model.rotation.y + randf_range(-0.3, 0.3), 0.26)
		var shove := func(u: float) -> void:
			global_position = p0 + away * (CRUSH_SHOVE * u)
		tw.tween_method(shove, 0.0, 1.0, 0.26) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_dust_bank(global_position, away, 12)
		await tw.finished
	else:
		await _beat(0.26)


## BURNED. The bishop's bolt does not touch him: it lights him. Every surface
## spikes white-hot, the flesh chars to charcoal as he goes down, and thin
## embers come off the body — the dragon's incineration beat (dragon_spectator
## ._incinerate) at duel scale and duel budget.
##
## Materials are DUPLICATED before they are written: PieceAssets hands out
## cached, shared materials, and charring one in place would char every piece
## of that house wearing it.
const CHAR_COLOR := Color(0.07, 0.06, 0.06)
const CHAR_FLASH := Color(1.0, 0.86, 0.5)


func _die_burning() -> void:
	death_anim = ANIM_DEATH
	var mats := _burnable_materials()
	var flash := func(f: float) -> void:
		for e in mats:
			var m: StandardMaterial3D = e[0]
			if is_instance_valid(m):
				m.emission_enabled = true
				# Capped at 1.9, not the wyrm's 3.2: over that the man stops
				# being a man on fire and becomes a white cut-out of one.
				m.emission = CHAR_FLASH * (0.25 + 1.65 * f)
	var lit := create_tween()
	lit.tween_method(flash, 0.0, 1.0, 0.18).set_trans(Tween.TRANS_QUAD)
	await lit.finished
	_ember_wisps()
	_anim.speed_scale = 1.05
	_anim.play(ANIM_DEATH, 0.06)
	var window := PieceAssets.anim_length(ANIM_DEATH) / 1.05
	if piece_type == Type.KNIGHT:
		_mounted_fall(window)
	var char_it := func(f: float) -> void:
		for e in mats:
			var m: StandardMaterial3D = e[0]
			if is_instance_valid(m):
				m.albedo_color = (e[1] as Color).lerp(CHAR_COLOR, f)
				m.emission = CHAR_FLASH * (1.2 * (1.0 - f))   # the glow cools
	var burn := create_tween()
	burn.tween_method(char_it, 0.0, 1.0, window).set_trans(Tween.TRANS_SINE)
	await burn.finished


## Every surface on this piece, duplicated so the fire owns its own copy.
## Returns [[material, original_albedo], ...].
func _burnable_materials() -> Array:
	var mats: Array = []
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if mi.material_override is StandardMaterial3D:
			var m: StandardMaterial3D = (mi.material_override as StandardMaterial3D).duplicate()
			mi.material_override = m
			mats.append([m, m.albedo_color])
			continue
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s)
			if src is StandardMaterial3D:
				var m2: StandardMaterial3D = (src as StandardMaterial3D).duplicate()
				mi.set_surface_override_material(s, m2)
				mats.append([m2, m2.albedo_color])
	return mats


# ── kill VFX (particles and props only — NEVER a Light3D) ─────────────────
#
# The hall's eight omnis are the eight torches and the suites assert it, so
# every effect below sells its light the way dracarys.gd does: emissive,
# unshaded, additive geometry. Nothing here creates a lamp.


## A one-shot puff of stone dust — hooves, a tower's weight, a king's blow.
##
## DUST IS A HAZE, NOT A DOME. The first cut fired 30 half-opaque billboards
## from one point with the emitter's explosiveness at 0.85, and the frames came
## back with a white hemisphere sitting on the flagstones beside the fighters —
## the same "flat bright shape a critic reads as an unfinished debug panel"
## the weapon trail already paid for once. So: fewer of them, a quarter of the
## alpha, thrown wide enough to separate, and spawned a hand's height off the
## floor so the ground plane stops cutting them into a flat-bottomed dome.
func _dust_puff(world_pos: Vector3, amount: int, spread_scale: float) -> void:
	var p := GPUParticles3D.new()
	p.name = "KillDust"
	p.amount = clampi(int(round(amount * 0.5)), 4, 20)
	p.lifetime = 0.85
	p.one_shot = true
	p.explosiveness = 0.55
	p.randomness = 0.8
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 72.0
	pm.initial_velocity_min = 0.9 * spread_scale
	pm.initial_velocity_max = 2.1 * spread_scale
	pm.gravity = Vector3(0.0, -0.9, 0.0)
	pm.damping_min = 1.4
	pm.damping_max = 2.8
	pm.scale_min = 0.1
	pm.scale_max = 0.26
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.16
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	ramp.colors = PackedColorArray([
		Color(0.58, 0.55, 0.5, 0.2), Color(0.5, 0.47, 0.44, 0.12),
		Color(0.45, 0.43, 0.4, 0.0)])
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	pm.color_ramp = ramp_tex
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.34, 0.34)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_dot()
	quad.material = mat
	p.draw_pass_1 = quad
	p.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 4, 4))
	_spawn_world_effect(p, world_pos + Vector3.UP * 0.1, 1.8)
	p.emitting = true


## A LOW WIDE BANK of it — what a mass coming down actually throws, and what a
## single puff in the middle of a watchtower cannot be. Three emitters spread
## ACROSS the line of travel (so the bank is wider than the thing that made it)
## rather than one bigger emitter, because "one bigger emitter" is precisely the
## white hemisphere _dust_puff's own note was written about: the per-puff tuning
## that keeps dust a haze is preserved, and only the footprint grows.
func _dust_bank(world_pos: Vector3, along: Vector3, amount: int) -> void:
	var side := along.cross(Vector3.UP)
	side = side.normalized() if side.length() > 0.01 else Vector3.RIGHT
	for i in 3:
		_dust_puff(world_pos + side * (float(i) - 1.0) * 0.52
			+ along * randf_range(-0.11, 0.11), amount, 0.6)


## A soft round particle mask — dust with a hard rectangular edge is a
## rectangle, which is the exact defect the weapon trail already paid for.
func _soft_dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([
		Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 64
	t.height = 64
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t


## Thin embers coming off a burning body — the only thing that says "fire"
## once the jet has cut.
func _ember_wisps() -> void:
	var p := GPUParticles3D.new()
	p.name = "BurnEmbers"
	p.amount = 26
	p.lifetime = 1.1
	p.explosiveness = 0.1
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 24.0
	pm.initial_velocity_min = 0.25
	pm.initial_velocity_max = 0.7
	pm.gravity = Vector3(0.0, 0.35, 0.0)   # embers RISE
	pm.scale_min = 0.02
	pm.scale_max = 0.05
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.18
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	ramp.colors = PackedColorArray([
		Color(3.0, 1.5, 0.5, 1.0), Color(2.0, 0.6, 0.15, 0.8),
		Color(0.6, 0.15, 0.05, 0.0)])
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	ramp_tex.use_hdr = true   # or every colour clamps to 1.0 and nothing blooms
	pm.color_ramp = ramp_tex
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.08, 0.08)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_dot()
	quad.material = mat
	p.draw_pass_1 = quad
	p.visibility_aabb = AABB(Vector3(-1.5, -0.5, -1.5), Vector3(3, 3.5, 3))
	_spawn_world_effect(p, global_position + Vector3.UP * _chest_height(self), 2.2)
	p.emitting = true


## Park a fire-and-forget effect in WORLD space (never under a piece that is
## about to sink into the stone or walk away) and free it after `life`.
func _spawn_world_effect(node: Node3D, world_pos: Vector3, life: float) -> void:
	var holder := get_parent()
	if holder == null:
		holder = self
	holder.add_child(node)
	node.global_position = world_pos
	var tree := get_tree()
	if tree == null:
		return
	var t := tree.create_timer(life, true, false, true)   # wall clock: it must always die
	t.timeout.connect(func() -> void:
		if is_instance_valid(node):
			node.queue_free())


## THE QUEEN'S ARROW. A shaft with a head, flown from the bow to the chest —
## awaitable, so "the arrow lands, THEN he falls" is a sequence and not a
## coincidence. `arc` lifts the flight for the lobbed variant.
##
## IT STAYS IN HIM. The flight is ~0.2 s and the frames that matter (the
## suite's, and the player's memory of the kill) are of the fall AFTER it, so
## an arrow that despawns on contact leaves a man who simply fell over. On
## impact it is re-parented to the victim and rides the body down — and is
## freed with him, since he owns it now.
##
## IT AIMS AT THE MAN, NOT AT A REMEMBERED POINT. The target used to be sampled
## once by the caller; a shaft that arrived after he had begun to move arrived
## where his chest had been, and hung there. It now re-reads his live chest every
## frame of the flight, so the arrow cannot miss a man who is standing still and
## cannot orphan itself off one who is not. `offset` nudges the aim (the second
## shaft of a double), `arc` lifts the flight for the lobbed variant.
func _loose_arrow(victim: PieceView, arc: float, offset: Vector3 = Vector3.ZERO) -> void:
	var bow := find_child("Gear_bow", true, false) as Node3D
	var from := bow.global_position if bow != null \
		else global_position + Vector3.UP * _chest_height(self)
	var shaft := _make_arrow()
	var holder := get_parent()
	if holder == null:
		holder = self
	holder.add_child(shaft)
	# The aim is LIVE: `last` is only the memory of it, for the frame after he
	# is freed.
	var last := {"t": _arrow_aim(victim, offset)}
	# FOUR SQUARES MUST TAKE LONGER THAN ONE. The old ceiling was 0.26 s, which
	# a shot of 1.9 squares already hit — so with the approach walk gone and the
	# queen loosing across the board, every distance would have arrived in the
	# same quarter second and the flight would have read as a teleport. The
	# ceiling is the SHOT's, not the tween's: a full-board shaft spends ~0.5 s,
	# and because this tween is scaled it spends four times that in wall clock
	# under the duel's slow-mo, which is the beat the whole cinematic is for.
	var flight := clampf(from.distance_to(last["t"]) * 0.105, 0.12, 0.50)
	var fly := create_tween()
	var travel := func(u: float) -> void:
		if not is_instance_valid(shaft):
			return
		if is_instance_valid(victim) and not victim.is_queued_for_deletion():
			last["t"] = _arrow_aim(victim, offset)
		var target: Vector3 = last["t"]
		var p := from.lerp(target, u) + Vector3.UP * (sin(u * PI) * arc)
		var nxt := from.lerp(target, minf(u + 0.05, 1.0)) \
			+ Vector3.UP * (sin(minf(u + 0.05, 1.0) * PI) * arc)
		var dir := nxt - p
		if dir.length() > 0.0001:
			# The cylinder's long axis is +Y — build the basis so that +Y runs
			# down the flight path (look_at would point -Z, which is the wrong
			# axis for a shaft).
			var ay := dir.normalized()
			var ax := ay.cross(Vector3.UP)
			if ax.length() < 0.001:
				ax = ay.cross(Vector3.FORWARD)
			ax = ax.normalized()
			shaft.global_transform = Transform3D(
				Basis(ax, ay, ax.cross(ay).normalized()), p)
		else:
			shaft.global_position = p
	fly.tween_method(travel, 0.0, 1.0, flight).set_trans(Tween.TRANS_LINEAR)
	await fly.finished
	var target: Vector3 = last["t"]
	# Anchored ON the chest it hit — a flash halfway back to the archer is not
	# an impact, it is a decoration.
	_strike_flash(target, {"at": target, "height": 0.0, "scale": 0.45,
		"life": 0.26, "tint": Color(1.0, 0.86, 0.6)})
	if not is_instance_valid(shaft):
		return
	if is_instance_valid(victim) and not victim.is_queued_for_deletion():
		# IT RIDES HIS CHEST BONE, NOT HIS FEET.
		#
		# This used to re-parent to the victim's ROOT, and a PieceView's root
		# does not move when the man dies — the death clip animates the skeleton
		# inside the model. So the body went down and the arrow stayed exactly
		# where the chest had been: a shaft hanging in the air a body's height
		# above a corpse, which is the "arrows hang in mid-air BEHIND an
		# already-fallen victim" the critic read as inverted timing. Mounted on
		# the rig's chest bone (the quiver's own mount, and the crown-attach
		# pattern generally) it falls with him, and it is freed with him.
		var xf := shaft.global_transform
		var host: Node3D = victim._bone_mount("chest", "ArrowMount")
		if host == null:
			host = victim
		shaft.get_parent().remove_child(shaft)
		host.add_child(shaft)
		shaft.global_transform = xf
		# Buried to the fletching rather than resting on the surface: a shaft
		# that only touches a man reads as a shaft floating beside him.
		shaft.global_position -= xf.basis.y.normalized() * 0.07
	else:
		shaft.queue_free()


## ONE ARROW, built once and used twice: the shaft on the string at full draw
## and the shaft in flight are the same object, so a critic can never catch the
## nocked one and the loosed one disagreeing about what an arrow looks like.
## Long axis +Y, head at +0.17, fletching at the tail; unparented.
func _make_arrow() -> MeshInstance3D:
	var shaft := MeshInstance3D.new()
	shaft.name = "Arrow"
	# Scaled to the CAST, not to a real arrow: these fighters are 0.78-1.2 world
	# units tall, so a 0.42 m shaft crossed the frame like a spear. Nudged up
	# from 0.24 x 0.008 on 2026-08-09: at the duel camera's distance that was a
	# 15-pixel splinter, and an arrow nobody can find is not the queen's
	# signature — it is a man who fell over for no visible reason.
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.011
	cyl.bottom_radius = 0.011
	cyl.height = 0.3
	shaft.mesh = cyl
	# LIGHT WOOD, NOT NEAR-BLACK. The shaft was 0.22,0.16,0.1 — against a dark
	# leather torso on a dark square it was invisible, so a kill whose whole
	# signature is the arrow shipped a frame with no arrow findable in it. Pale
	# ash reads against both armies and both colours of flagstone.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.48, 0.3)
	mat.roughness = 0.85
	shaft.material_override = mat
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var head := MeshInstance3D.new()
	head.name = "ArrowHead"
	var tip := CylinderMesh.new()
	tip.top_radius = 0.0
	tip.bottom_radius = 0.023
	tip.height = 0.085
	head.mesh = tip
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.6, 0.62, 0.66)
	hmat.metallic = 0.9
	hmat.roughness = 0.35
	head.material_override = hmat
	head.position = Vector3(0.0, 0.17, 0.0)
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shaft.add_child(head)
	_fletch(shaft)   # the tail the eye actually finds at duel distance
	return shaft


## A basis whose +Y runs along `dir` — the shaft's own long axis. (look_at
## would aim -Z, which is the wrong axis for a cylinder.)
static func _shaft_basis(dir: Vector3) -> Basis:
	var ay := dir.normalized()
	var ax := ay.cross(Vector3.UP)
	if ax.length() < 0.001:
		ax = ay.cross(Vector3.FORWARD)
	ax = ax.normalized()
	return Basis(ax, ay, ax.cross(ay).normalized())


## ── THE DRAW (critic blocker, 2026-08-09) ─────────────────────────────────
##
## "The single most legible thing about an archer is the drawn bow in profile."
## There was no drawn bow. `Gear_bow` is a rigid mount on the `handslot.l` bone
## and the queen's kill borrows the shared `Throw` clip, which is an OVERHAND
## THROW — so through the whole shot the bow lay HORIZONTAL across her shins at
## the height the throw happens to leave her off hand (measured on the shipped
## kills/06_kill_queen: limbs across the frame at ankle level, string below the
## boots). No camera angle rescues that, because the shape was never there: the
## rank that kills at range was reading as a woman standing next to a bow.
##
## The rig cannot be asked for the pose — the pack ships no archery clip, and a
## cross-vendor retarget is the excursion play_capture already declined. So the
## PROP is driven instead, which is cheap and exact: while the shot is live this
## overrides the bow's global BASIS only (never its position — it stays in her
## fist, carried by the animation) so the limbs stand UP and the bow's plane
## contains the shot line. The bow mesh is 1.98 model units from tip to tip,
## about the queen's own height, so upright it is the largest readable shape in
## the frame — which is what an archer's silhouette is supposed to be.
##
## Bow axes, measured off `bow_withString.gltf` at its mount: long axis local Z
## (length 1.984), riser depth local X (0.494, the limbs sweeping back toward
## -X), thin in local Y (0.156). So local Z -> world UP and local X -> the shot
## direction puts the limbs vertical, the string toward the archer and the plane
## edge-on to nobody.
##
## The nocked arrow is the SAME `_make_arrow()` the loose flies, drawn back over
## `BOW_DRAW_WALL` and hidden the instant she looses — so "the arrow leaves the
## string" is one object moving, not two objects swapping.
##
## AND THE NEXT SHAFT IS ALREADY ON THE STRING. The override, and the nock,
## outlive the loose on purpose, and this is the part that decides whether the
## kill reads at all: the frame the suite ships (and the one a player remembers)
## is taken while the VICTIM IS FALLING, roughly a second after the arrow left.
## An archer photographed in that second is not empty-handed — she has drawn
## again and is covering the field. Without it the shipped frame is a cloaked
## figure standing beside a bow, which is the defect in one sentence; with it,
## every frame from the first beat of the kill to the last carries the drawn
## bow in profile. The bow only goes back to her side when she closes the range.
##
## …AND THE CLIP IS PARKED WHILE SHE AIMS. The bow rides `handslot.l`, so where
## it sits in the frame is decided by the borrowed throw, and the throw leaves
## her off hand DOWN: at the clip's end (which is where the shipped frame caught
## it) the hand is at bone y 0.637 and z -0.019 — a bow across her shins, over
## her own dark cloak, which is the low-contrast squiggle the first re-render
## still shipped. Sampled across the whole 1.367 s clip, the hand is highest and
## furthest forward at t = 0.55 (y 0.842, z +0.392 — a fifth of a body up and
## half a body forward of where it ends), which is the one pose in the clip that
## is ALSO an archer's: arm out, weight forward. So the clip runs its windup and
## then HOLDS there for the aim, the loose and the re-nock, and only resumes when
## she settles. An archer at full draw is meant to be still; and it puts the bow
## out over open flagstone instead of over her own robe.
##
## The last of it is a LIFT. The bow is 1.98 model units tip to tip — about the
## queen's own height — so hung off a hand that even the clip's best pose leaves
## at 0.40 of her height, its lower limb ends BELOW the flagstones and the arrow
## crosses her at the belt. Raised by 0.13 of her height the whole bow stands
## clear of the stone and the shaft crosses her chest, at the cost of her fist
## sitting on the lower limb instead of dead on the grip — which is a hand ON a
## bow either way, and reads as one at duel distance.
const BOW_DRAW_PULL := 0.30      ## how far the nock comes back from the grip
const BOW_DRAW_WALL := 0.30      ## wall seconds from nocked to full draw
const BOW_DRAW_FRAME := 0.55     ## the `Throw` clip's own archer pose (seconds)
const BOW_DRAW_LIFT := 0.13      ## x piece height: the lower limb clears the floor


## Start the draw. Returns a handle: set `nocked` false at the loose, `live`
## false to give the bow back to the animation. Safe on a piece with no bow
## (every rank but the queen) — the handle is inert.
func _bow_draw(victim: PieceView) -> Dictionary:
	var bow := find_child("Gear_bow", true, false) as Node3D
	var state := {"live": bow != null, "nocked": bow != null}
	if bow == null:
		return state
	var nock := _make_arrow()
	nock.name = "NockedArrow"
	add_child(nock)
	nock.top_level = true   # driven in world space, like the loosed shaft
	# The prop inherits the model's height-grading scale; an orthonormal basis
	# would strip it and ship a bow twice the queen's size.
	var gear_scale: float = bow.global_basis.get_scale().x
	var mount := bow.get_parent() as Node3D   # the BoneAttachment3D = her fist
	var lift := Vector3.UP * (PieceAssets.piece_height(piece_type) * BOW_DRAW_LIFT)
	var t0 := Time.get_ticks_msec()
	# A raised bow may never outlive its duel: an abandoned kill (a freed
	# victim, a torn-down scene) must hand the prop back on its own.
	var deadline := t0 + 12000
	var runner := func() -> void:
		var pull_t0 := t0
		var was_nocked := true
		while bool(state["live"]) and is_instance_valid(self) and is_instance_valid(bow) \
				and Time.get_ticks_msec() < deadline:
			var aim := _arrow_aim(victim, Vector3.ZERO) \
				if is_instance_valid(victim) and not victim.is_queued_for_deletion() \
				else global_position + Vector3.UP * _chest_height(self)
			var grip := (mount.global_position if is_instance_valid(mount)
				else bow.global_position) + lift
			var flat := Vector3(aim.x - grip.x, 0.0, aim.z - grip.z)
			var fwd := flat.normalized() if flat.length() > 0.001 \
				else global_transform.basis.z.normalized()
			# limbs up (local Z -> UP), riser toward the target (local X -> fwd)
			bow.global_basis = Basis(fwd * gear_scale,
				Vector3.UP.cross(fwd).normalized() * gear_scale,
				Vector3.UP * gear_scale)
			bow.global_position = grip
			var nocked := bool(state["nocked"])
			if nocked and not was_nocked:
				pull_t0 = Time.get_ticks_msec()   # a fresh shaft, drawn again
			was_nocked = nocked
			if is_instance_valid(nock):
				nock.visible = nocked
				if nocked:
					var shot := (aim - grip)
					shot = shot.normalized() if shot.length() > 0.001 else fwd
					var u := clampf(float(Time.get_ticks_msec() - pull_t0)
						/ (BOW_DRAW_WALL * 1000.0), 0.0, 1.0)
					var pull := BOW_DRAW_PULL * (1.0 - pow(1.0 - u, 3.0))
					nock.global_transform = Transform3D(_shaft_basis(shot),
						grip - shot * (pull - 0.15))
			var tree := get_tree()
			if tree == null:
				return
			await tree.process_frame
		if is_instance_valid(nock):
			nock.queue_free()
	runner.call()
	return state


## THE FLETCHING. Two crossed vanes at the tail — the part of an arrow that is
## always OUTSIDE the man, and the part the eye finds first. A buried shaft is a
## dark line against dark leather; a pale cross standing off his chest is
## unmistakably an arrow, at duel distance, in one frame.
func _fletch(shaft: MeshInstance3D) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.93, 0.91, 0.86)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 2:
		var vane := MeshInstance3D.new()
		vane.name = "Fletch%d" % i
		var q := QuadMesh.new()
		q.size = Vector2(0.075, 0.05)
		vane.mesh = q
		vane.material_override = mat
		vane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The shaft's long axis is +Y; the vanes lie ALONG it at the tail.
		vane.position = Vector3(0.0, -0.115, 0.0)
		vane.rotation = Vector3(PI * 0.5, PI * 0.5 * float(i), 0.0)
		shaft.add_child(vane)


# ── the bishop's bolt (DRACARYS at staff scale) ────────────────────────────
#
# The kit is model-independent: it aims from any Node3D and re-reads that
# node's GLOBAL transform every frame, so a marker on the staff tip makes the
# bolt track the raise. Two hard-won wiring rules are honoured here:
#   1. TUNE BEFORE add_child — the kit bakes these into shaders, gradients and
#      particle materials in _build(), which runs from its own _ready();
#   2. bind NOTHING. No camera (no shake) and no WorldEnvironment (no exposure
#      lift): a capture is not a ceremony, and the duel already owns the
#      camera and the clock.
# It is built lazily, under the staff raise (never on the ignition frame) and
# freed at the end of the kill, so a board of bishops costs nothing until one
# of them actually kills.
const DracarysScript := preload("res://assets/vfx/dracarys.gd")


## `gap` is the distance the bolt has to travel (see _kill_bolt). The kit bakes
## `reach` into shaders and particle materials in its own _ready(), so it can
## only be set BEFORE add_child — which is why the range is an argument rather
## than something the caller nudges later. Floored at the old 1.6 so a
## point-blank cast looks exactly as it always did, and capped well inside the
## hall: a bolt is a staff's shot, never the wyrm's breath.
func _prepare_bolt(gap: float = 1.6) -> void:
	if _bolt != null and is_instance_valid(_bolt):
		return
	var fx: Node3D = DracarysScript.new()
	fx.name = "StaffBolt"
	fx.reach = clampf(gap * 1.12, 1.6, 8.5)
	fx.torrent_spread = 6.0
	# 0.30, not the kit's 1.0 and not the wyrm's 0.40. This is a ONE-METRE shot
	# fired between two figures 0.8 m tall in a dark hall: at 0.34 the first
	# frames came back with the victim a featureless white silhouette and the
	# far wall lit orange — the same "hot core is fine, the ROOM stays a dark
	# stone hall" line dragon_spectator draws, at a tenth of the range.
	fx.intensity = 0.3
	fx.ember_tail = 0.6
	fx.ash_tail = 0.4
	fx.heat_shimmer_enabled = false  # a 1.5 m bolt has no heat haze worth a pass
	fx.environment_lift_enabled = false
	fx.auto_punch = false
	fx.floor_y = global_position.y
	add_child(fx)                    # AFTER the tuning — see above
	_bolt = fx


func _staff_muzzle() -> Node3D:
	var staff := find_child("Gear_staff", true, false) as Node3D
	if staff == null:
		return null
	var existing := staff.get_node_or_null("StaffTip") as Node3D
	if existing != null:
		return existing
	# The tip is the highest point of the prop in WORLD space at the moment we
	# look (the staff is held, so its local axes are not the world's), stored
	# back as a local offset so it then tracks the animation.
	var best := -INF
	var top := staff.global_position
	for mi: MeshInstance3D in staff.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var ab := mi.mesh.get_aabb()
		for i in 8:
			var c: Vector3 = mi.global_transform * (ab.position + Vector3(
				ab.size.x * float(i & 1),
				ab.size.y * float((i >> 1) & 1),
				ab.size.z * float((i >> 2) & 1)))
			if c.y > best:
				best = c.y
				top = c
	var tip := Node3D.new()
	tip.name = "StaffTip"
	staff.add_child(tip)
	tip.global_position = top
	return tip


func _fire_bolt(target: Vector3, duration: float) -> void:
	if _bolt == null or not is_instance_valid(_bolt):
		return
	var muzzle := _staff_muzzle()
	if muzzle != null:
		_bolt.start(muzzle, target, duration)
	else:
		_bolt.start(global_position + Vector3.UP * PieceAssets.piece_height(piece_type),
			target, duration)


## Variant 2: the bolt comes down out of the air onto him. Wall clock — the
## kit's own timeline is wall clock and the two must not drift apart.
func _sweep_bolt(from_aim: Vector3, to_aim: Vector3, sec: float) -> void:
	var muzzle := _staff_muzzle()
	if _bolt == null or not is_instance_valid(_bolt) or muzzle == null:
		await _beat_wall(sec)
		return
	var t0 := Time.get_ticks_msec()
	while true:
		var u := clampf(float(Time.get_ticks_msec() - t0) / (sec * 1000.0), 0.0, 1.0)
		if is_instance_valid(_bolt) and _bolt.is_active():
			_bolt.aim(muzzle, from_aim.lerp(to_aim, u * u))
		if u >= 1.0:
			return
		var tree := get_tree()
		if tree == null:
			return
		await tree.process_frame


## The bolt is done: clear it instantly (hard_stop is idempotent and restores
## everything the kit ever touched) and give the node back.
func _stop_bolt() -> void:
	if _bolt == null or not is_instance_valid(_bolt):
		_bolt = null
		return
	_bolt.hard_stop()
	_bolt.queue_free()
	_bolt = null


func _exit_tree() -> void:
	## A piece freed mid-bolt must not leave a torrent behind.
	_stop_bolt()


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
	_fit_crest(crest)
	att.add_child(crest)
	_dress(crest)


## Sit the crest ON the head instead of around it — see CREST_FLOOR_Y for the
## measurement. Uniform scale first (so a tall crest keeps its proportions),
## then the lift that puts its lowest vertex on the crest line. A crest whose
## mesh cannot be measured keeps the plain mount, exactly as before.
func _fit_crest(crest: Node3D) -> void:
	crest.position = CREST_MOUNT_POS
	var box := _mesh_bounds(crest)
	if box.size.y <= 0.0001:
		return
	var s := minf(1.0, CREST_MAX_HEIGHT / box.size.y)
	crest.scale = Vector3.ONE * s
	crest.position.y = CREST_FLOOR_Y - box.position.y * s


## Union AABB of every mesh under `node`, in `node`'s OWN space (its own
## transform excluded — this is measured before the node is mounted).
static func _mesh_bounds(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var chain := mi.transform
		var p := mi.get_parent()
		while p != null and p != node:
			chain = (p as Node3D).transform * chain
			p = p.get_parent()
		var box: AABB = chain * mi.mesh.get_aabb()
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out


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
