class_name CathedralCinematicIntro
extends Node3D
## CathedralCinematicIntro — the arrival of the witness.
##
## After the VS splash the camera FOLLOWS the wyrm — from a distance, the way
## the feather is followed at the top of Forrest Gump — through six shots:
##   1  THE NIGHT     moonlit cathedral on its crag; the dragon crosses high,
##                    a silhouette against the moon; the location card rises.
##   2  THE APPROACH  the wyrm circles the twin towers while the lens holds
##                    off to the west: the whole west front stays in shot.
##   3  THE NEEDLE    falcon-stoop into the OPEN west rose — the dragon door.
##                    We watch it shrink into the lit oculus from behind, then
##                    the lens threads the same hole a beat later and the night
##                    gives way to torchlight in the thickness of the wall.
##   4  THE NAVE      the run, seen down the length of the church: the wyrm
##                    descends away from us past the chandeliers, out to the
##                    aisle and back, a low pass over the board.
##   5  THE PERCH     pull-up, flare, and a Land_Settle onto the Wyrm's
##                    Gallery over the apse arch, the ember rose behind it —
##                    filmed wide from the hall floor, throne in frame.
##   6  THE VIGIL     the ROAR — coals kindle, a distant crack in a big room —
##                    then Perch_Idle, and one continuous crane down past the
##                    throne into the exact gameplay framing. The letterbox
##                    retracts; the fight is on.
##
## Craft contracts this file keeps:
##  * The serpent-wyrm's native forward is +Z (DragonRig header) — flight
##    orientation aligns +Z with the path tangent via Basis.looking_at(-T).
##    look_at() would aim -Z and fly the beast tail-first, which is exactly
##    what the previous intro did.
##  * The gameplay camera is NEVER mutated — this node runs its own Camera3D
##    and hands control back with make_current(), so there is nothing to
##    restore and nothing to get wrong.
##  * The hall's 8-omni torch budget stays full: the wyrm's glow is an
##    OmniLight3D cull-masked to layer 10, which only the cathedral shell
##    (see GreatHall._build_cathedral) receives.
##  * Mobile renderer directional budget: the hall already runs 4
##    directionals — the moon only shines while the hall's Sun is off.
##  * Skippable at any moment (keys or click); auto-skips under the e2e
##    driver (`--e2e*` user args) so synthesized input never fights a shot.
##
## Geometry the flight path cites (tools/blender/build_sanctum_cathedral.py):
## open west rose centre (0, 20.8, -26) oculus r ~3.0; organ finial tips at
## y 20.5 on the axis (hold y >= 21.6 until z > -22); chandeliers at
## x 0, y 14.2, z {-8, 0, 8}, ring r 2.1; hall walls |x|,|z|=12 top y 11.7;
## gallery ledge top (0, 12.2, 13.55).

signal intro_completed

const DragonRigScript := preload("res://src/cinematics/dragon_rig.gd")
const AdaptiveScaleScript := preload("res://src/ui/adaptive_scale.gd")

const TOTAL := 30.5
const T_APPROACH := 5.0     # the night establishing ends
const T_NEEDLE := 11.5      # the wide bomber turn onto final ends
const T_NAVE := 18.0        # the long final + the threading ends
const T_PERCH := 23.5       # the nave run ends
const T_LAND := 24.7        # Land_Settle begins
const T_TOUCH := 25.7       # claws on the gallery stone
const T_ROAR := 26.1
const T_IDLE := 27.9
## The wyrm's own size. Raised from 1.65 (Bert: "the Dragon should be bigger
## than that") — at 2.2 its wingspan is ~12 u against a 26.8 u nave, so it
## barely fits the church it is flying through, which is the whole point of
## putting a dragon in a cathedral.
##
## The ceiling on this number is the ASHFALL, not the architecture: game.gd
## hands the same scale to the DragonSpectator's vigil so the hand-off at the
## seam cannot pop, and the ceremony swells from there to `ceremony_scale`
## 2.25 and `champ_scale` 2.55. Going past those would make the wake SHRINK
## the beast, and re-tuning the ceremony's measured bank radius and hover
## heights is a separate campaign with its own suite.
const DRAGON_SCALE := 2.2

## ── THE FEATHER RULE (Bert, 2026-08-18) ────────────────────────────────────
## The first cut rode the wyrm: at the tower pass the lens sat FOUR units off
## a beast with a ten-unit wingspan, so the creature filled the frame edge to
## edge and neither the flight nor the cathedral could be read. The reference
## is the feather that opens Forrest Gump — the camera follows from a
## distance, drifting on the same air, and the world stays in shot.
##
## Three mechanisms hold that, in order of authority:
##   1. every camera key is authored at a measured stand-off from the wyrm's
##      position at the same instant (the tables below carry the numbers);
##   2. STAND_OFF is then ENFORCED per frame — the lens backs off along its
##      own axis until the range is met, so no spline drift can ever put the
##      camera on the beast's back again;
##   3. `--cine-capture` prints `dist` and `frac` (the wyrm's share of frame
##      width) at every beat, so "far enough" is a measured number, not a
##      feeling. The band is 5-42 % of frame width: the exterior beats run
##      9-19 % and the interior hero beats 27-36 %, which is where "followed
##      from a distance" and "a dragon with presence" both hold at once.
const STAND_OFF_SKY := 22.0     ## exterior: the cathedral must stay in shot
const STAND_OFF_THREAD := 13.0  ## the needle: a trailing follow into the rose
## Interior. This is a FLOOR THE AUTHORED KEYS ALREADY MEET, and it must
## stay one: pushed to 18.5 it started actively re-posing the low pass, and
## backing off along the aim there slid the lens behind the great hall's own
## near wall — the shot became a black wall with a dragon behind it. The net
## catches drift; it does not get to direct.
const STAND_OFF_NAVE := 15.0

## The camera composes against the WORLD, not only against the wyrm: the aim
## sits a fraction off the beast toward the space it is crossing, so the
## architecture holds the frame and the dragon rides off-centre. A feather is
## never the only thing in the shot.
const ANCHOR_SKY := Vector3(0.0, 26.0, -26.0)   # the west front
const ANCHOR_NAVE := Vector3(0.0, 8.0, 2.0)     # the nave floor / the board
const COMPOSE_PULL := 0.18
## Gentle: a drifting observer, not a gun turret. (The first cut ran this at
## 12.0 — locked-on tracking, which is what made the flight read as chaos.)
const LOOK_RATE := 4.5
const FLIGHT_FOV := 58.0        ## wide glass keeps the world around the wyrm

## Flight keys per shot (Catmull-Rom, world space).
##
## Two obstacles the interior legs are routed around, both measured off the
## generator: the ORGAN's centre finial tips out at y 20.5 on the axis at
## z -24.8 (so the wyrm threads the rose at 20.8 and pulls up hard over it),
## and the CHANDELIER chains hang at x 0 from y 15.8 to the vault (so the
## descent down the nave is flown off-axis, out at x -6, and only returns to
## the centre line once it is under them).
const PATH_NIGHT := [
	Vector3(38, 50, -82), Vector3(34, 48, -78), Vector3(14, 42, -64),
	Vector3(-6, 37, -52), Vector3(-16, 34.5, -46), Vector3(-22, 34.5, -40)]
## THE TOWER LEG, re-flown 2026-08-18 (Bert: "when the dragon is close to the
## outside tower, it gets jerky and then does thru the tower"). Both faults
## were real and both are measurable:
##
##   * it STARTED 8.49 u from where the night leg ended — a teleport at the
##     beat seam, and because the heading is taken from the frame's own
##     displacement, that one bad frame also slammed the bank hard over. The
##     jerk and the beat boundary were the same event. Leg endpoints are now
##     shared exactly, and tests/test_cathedral_and_dragon.gd asserts it.
##   * it passed 3.13 u from the north tower's centre line. The tower is 5.5 u
##     of masonry and the wyrm is 12.4 u across, so it needs 11.7 u of centre
##     clearance and had a quarter of that: it flew through the stonework.
##
## The re-flight sweeps WIDE around the west front (never nearer than 13 u to
## either tower) and comes back onto the axis to thread the gap BETWEEN the
## spires, which at this height is 25 u wide — the shot the beat was always
## meant to be. It also rides above the nave ridge cresting (y 39.65) rather
## than through it.
const PATH_APPROACH := [
	Vector3(-22, 34.5, -40), Vector3(-30, 34.0, -33),
	Vector3(-38, 33.0, -40), Vector3(-40, 32.0, -55), Vector3(-33, 31.0, -66),
	Vector3(-18, 30.3, -71), Vector3(-8, 30.1, -71), Vector3(-2, 30.0, -69),
	Vector3(0, 30.0, -67.5), Vector3(0, 30.0, -66)]
## The pull-up after the oculus clears the ORGAN's centre finial (tip y 20.5
## at z -24.8, dead on the axis): at rig scale 2.2 the belly rides ~1.2 under
## the root, so the path has to be a good metre higher than the finial, not a
## hand's breadth.
const PATH_NEEDLE := [
	Vector3(0, 30.0, -66), Vector3(0, 28.2, -57), Vector3(0, 26.2, -48),
	Vector3(0, 24.4, -39), Vector3(0, 23.2, -32), Vector3(0, 22.3, -26.0),
	Vector3(-0.7, 22.6, -21.0), Vector3(-1.8, 22.6, -15.0),
	Vector3(-2.6, 22.2, -10.0)]
## THE NAVE RUN. One long descending curve rather than the hard left it used
## to open with: the old leg turned 74.9 deg in its first frames because it
## had to dodge the z -8 chandelier chain the instant it came through the
## rose. The drift now starts back on the ouverture, so this leg only has to
## continue it. Body clearance at the chains (x 0, y 15.8 up) is what sets
## the x offsets; a wing membrane may still sweep a 0.08 u iron rod, which at
## twenty metres is not a thing anyone can see.
const PATH_NAVE := [
	Vector3(-2.6, 22.2, -10.0), Vector3(-4.5, 21.2, -5.5),
	Vector3(-6.0, 16.5, -0.5), Vector3(-5.0, 12.0, 4.0),
	Vector3(-2.5, 9.2, 7.0), Vector3(0.5, 9.8, 10.0)]
## THE FLARE. This one IS a sharp change of direction, and it should be: the
## gallery sits BEHIND the great hall's own far wall, whose crest is y 11.7,
## so the wyrm has to climb over that crest and settle down onto the ledge at
## 12.2 — the belly clears the stone by 0.5 at the z 12 crossing. Birds pitch
## up hard to land; the smoothness contract in the suite exempts this seam
## for that reason and that reason only.
const PATH_PERCH := [
	Vector3(0.5, 9.8, 10.0), Vector3(1.6, 13.0, 11.6), Vector3(1.2, 14.2, 12.9),
	Vector3(0.4, 13.0, 13.4), Vector3(0.0, 12.2, 13.55)]
const PERCH_POS := Vector3(0.0, 12.2, 13.55)
const LEGS := [PATH_NIGHT, PATH_APPROACH, PATH_NEEDLE, PATH_NAVE, PATH_PERCH]

## ── HOW IT FLIES (Bert, 2026-08-18: "he looks like a robot") ───────────────
## The first cut stepped the SPLINE PARAMETER with time, which is not motion:
## a Catmull-Rom leg covers unequal distance per unit of u, so the wyrm
## surged and stalled between control points for no reason an animal would
## have. It also re-aimed itself with a fixed lerp toward an unbanked
## `looking_at`, then post-multiplied a roll that the next frame's lerp
## immediately fought — a mesh being carried on a stick.
##
## What flies here now:
##   * ARC LENGTH. Each leg is measured once, and the shot's easing shapes
##     DISTANCE against time — so `ease(t, 1.5)` on the stoop is a genuine
##     acceleration and the landing leg genuinely decelerates into the flare.
##   * REAL VELOCITY. Heading comes from the frame's own displacement,
##     slerped, so the body always points where it is actually going.
##   * AERODYNAMIC BANK. Roll is derived from the measured turn rate and
##     damped, then baked into the basis as a rolled UP vector — one
##     construction, nothing fighting it — plus a slow idle roll, because a
##     soaring animal is never perfectly level.
##   * WINGBEAT LIFT. The body rises and falls on the beat of the clip that
##     is actually playing, so the wings look like they are doing the flying.
##   * SECONDARY MOTION. DragonRig.FlightSway leads the head into turns,
##     throws the tail wide, and runs a wave down it (see that class).
const BANK_GAIN := 1.35      ## radians of roll per radian/sec of turn
const BANK_MAX := 0.95       ## ~54 deg: a hard bank, still readable
const BANK_DAMP := 2.6       ## how fast roll answers the turn
const HEADING_DAMP := 5.5    ## how fast the nose answers the velocity
const TURN_DAMP := 4.0       ## smoothing on the measured turn rate
const IDLE_ROLL := 0.055     ## radians of never-quite-level soar
const BEAT_LIFT := 0.16      ## body rise/fall per wingbeat, in rig scales

## Camera keys per shot — every one authored at a measured stand-off from the
## wyrm's position at the same instant (the ranges each leg holds are noted).
const CAM_NIGHT := [Vector3(-46, 6.0, -64), Vector3(-43, 9.0, -60),
	Vector3(-40, 12.0, -56)]                                     # 96 -> 34 u
const CAM_APPROACH := [Vector3(-40, 12, -56), Vector3(-56, 20, -58),
	Vector3(-58, 26, -72), Vector3(-40, 28, -86),
	Vector3(-18, 29, -88)]                                       # 33 -> 28 u
const CAM_NEEDLE := [Vector3(-18, 29, -88), Vector3(-26, 26, -64),
	Vector3(-20, 24, -46), Vector3(-13, 22.8, -38),
	Vector3(-6, 22.4, -34), Vector3(0, 22.1, -31)]               # 28 -> 21 u
## …and the lens follows it through the same hole a beat later: this leg
## crosses the facade at x 0, y ~20.8 — dead centre of the open oculus, whose
## clear radius is 3.0.
## …and once through, the lens SINKS: down the vault, over the hall's open
## wall crest and into the room, so the low pass reads as the wyrm thundering
## overhead against the lit vault instead of a dark shape on a dark wall.
## …and once through, the lens SINKS into the room with it. The key at
## z -12 is load-bearing: that is the great hall's own wall plane, crest
## y 11.7, and a descent that crosses it any lower puts the camera INSIDE
## the masonry (the first cut of this move filmed a wall of stone blocks).
## (Key 1 sits a metre off the axis so the organ's centre finial stops
## rising through the middle of the reveal — the lens still crosses the
## oculus well inside its 3.0 clear radius.)
const CAM_NAVE := [Vector3(0, 22.1, -31), Vector3(1.0, 21.4, -24.0),
	Vector3(1.0, 16.5, -16.5), Vector3(1.6, 12.8, -12.0),
	Vector3(2.2, 9.0, -8.0)]                                     # 15 -> 18 u
const CAM_PERCH := [Vector3(2.2, 9.0, -8.0), Vector3(-2.0, 8.2, -7.0),
	Vector3(-6.5, 7.8, -4.5), Vector3(-8.5, 7.6, -2.0)]          # 15 -> 18 u
const CAM_HOLD := [Vector3(-8.5, 7.6, -2.0), Vector3(-8.0, 7.9, -2.8)]
const CAM_HOME := [Vector3(-8.0, 7.9, -2.8), Vector3(-5.0, 8.6, -5.2)]

var _cam: Camera3D = null                # OUR camera
var _game_cam: Camera3D = null           # the rig's camera (untouched)
var _camera_rig: Node = null
var _home_xform: Transform3D             # gameplay framing to land on

var _dragon_root: Node3D = null
var _dragon_rig: DragonRig = null
var _glow: OmniLight3D = null
var _moon_light: DirectionalLight3D = null
var _sky_rig: Node3D = null
var _snow: GPUParticles3D = null
var _world_env: WorldEnvironment = null
var _hall_env: Environment = null
var _night_env: Environment = null
var _hall_sun: DirectionalLight3D = null

var _ui_layer: CanvasLayer = null
var _top_bar: ColorRect = null
var _bottom_bar: ColorRect = null
var _location_card: Control = null

var _sting: AudioStreamPlayer = null
var _sway: Node = null                # DragonRig.FlightSway (secondary motion)
var _flap := "Fast_Flying"            # the beat clip: Soar when it merged
var _arc: Array = []                  # per leg: cumulative arc-length table

var _is_running := false
var _elapsed := 0.0
var _skipped := false
var _inside := false
var _roared := false
var _landing := false
var _bank := 0.0
var _turn := 0.0                      # smoothed turn rate, rad/sec
var _fwd := Vector3(0, 0, 1)          # smoothed heading (the wyrm's +Z nose)
var _path_pos := Vector3.INF          # last position ON the path (bob excluded)
var _look_smooth := Vector3.ZERO
var _shake := 0.0


func start_cinematic(game_cam: Camera3D) -> void:
	_game_cam = game_cam
	_home_xform = game_cam.global_transform
	_camera_rig = game_cam.get_parent()
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--e2e"):
			_finish_cinematic()   # never fight synthesized input
			return
	if _camera_rig != null:
		_camera_rig.set_process(false)
		_camera_rig.set_process_unhandled_input(false)

	_cam = Camera3D.new()
	_cam.name = "CinematicCam"
	_cam.fov = FLIGHT_FOV
	add_child(_cam)
	_cam.global_position = CAM_NIGHT[0]
	_look_smooth = Vector3(0, 24, -26)
	_cam.look_at(_look_smooth, Vector3.UP)
	_cam.make_current()

	_build_arc_tables()
	_build_night_sky()
	_build_cinematic_ui()
	_spawn_dragon()
	# The witness announces itself: the Dramatic Entrance stinger, held for
	# the roar (self-contained player — freed with this node, no Music churn).
	var sting_path := "res://assets/music/stings/Orchestral_Stinger_Dramatic_Entrance.mp3"
	if ResourceLoader.exists(sting_path):
		_sting = AudioStreamPlayer.new()
		_sting.stream = load(sting_path)
		_sting.volume_db = -2.0
		add_child(_sting)
	Music.duck()
	_is_running = true
	_elapsed = 0.0
	set_process(true)
	set_process_unhandled_input(true)


# ── the world dressing ─────────────────────────────────────────────────────


func _build_night_sky() -> void:
	# Swap the hall's environment for the night exterior; keep a handle to
	# both so the threading frame can swap back in one assignment. Resolved
	# through the parent (the Game node) — current_scene is null when a test
	# harness instances game.tscn by hand.
	_world_env = get_parent().get_node_or_null("WorldEnvironment")
	if _world_env != null:
		_hall_env = _world_env.environment
		_night_env = Environment.new()
		_night_env.background_mode = Environment.BG_COLOR
		_night_env.background_color = Color(0.008, 0.012, 0.028)
		_night_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_night_env.ambient_light_color = Color(0.30, 0.38, 0.58)
		_night_env.ambient_light_energy = 0.28
		_night_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		_night_env.tonemap_exposure = 1.0
		_night_env.glow_enabled = true
		_night_env.glow_intensity = 0.45
		_night_env.glow_bloom = 0.08
		_night_env.fog_enabled = true
		_night_env.fog_light_color = Color(0.045, 0.07, 0.13)
		_night_env.fog_density = 0.0035
		_world_env.environment = _night_env
	# The hall runs 4 directionals (Sun + 3 fills) — the Mobile renderer's
	# budget. The moon replaces the Sun for the exterior, never joins it.
	_hall_sun = get_parent().get_node_or_null("Sun")
	if _hall_sun != null:
		_hall_sun.visible = false
	_moon_light = DirectionalLight3D.new()
	_moon_light.name = "Moonlight"
	_moon_light.light_color = Color(0.60, 0.70, 1.0)
	_moon_light.light_energy = 1.9
	_moon_light.basis = Basis.looking_at(Vector3(-0.35, -0.55, -0.75).normalized())
	add_child(_moon_light)

	# Star dome + moon disc, freed with this node.
	_sky_rig = Node3D.new()
	_sky_rig.name = "NightSky"
	add_child(_sky_rig)
	var star_mesh := QuadMesh.new()
	star_mesh.size = Vector2(0.9, 0.9)
	var star_mat := StandardMaterial3D.new()
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_mat.albedo_color = Color(0.85, 0.9, 1.0)
	star_mat.emission_enabled = true
	star_mat.emission = Color(0.85, 0.9, 1.0)
	star_mat.emission_energy_multiplier = 2.0
	star_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	star_mesh.material = star_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = star_mesh
	mm.instance_count = 420
	var rng := RandomNumberGenerator.new()
	rng.seed = 1988
	for i in mm.instance_count:
		var az := rng.randf() * TAU
		var el := rng.randf_range(0.12, 1.35)
		var r := 290.0
		var p := Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el)) * r
		var s := rng.randf_range(0.5, 1.6)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * s), p))
	var stars := MultiMeshInstance3D.new()
	stars.multimesh = mm
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sky_rig.add_child(stars)
	var moon := MeshInstance3D.new()
	var moon_mesh := SphereMesh.new()
	moon_mesh.radius = 9.0
	moon_mesh.height = 18.0
	var moon_mat := StandardMaterial3D.new()
	moon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	moon_mat.albedo_color = Color(0.92, 0.95, 1.0)
	moon_mat.emission_enabled = true
	moon_mat.emission = Color(0.85, 0.9, 1.0)
	moon_mat.emission_energy_multiplier = 2.6
	moon_mesh.material = moon_mat
	moon.mesh = moon_mesh
	moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	moon.position = Vector3(60, 118, 30)
	_sky_rig.add_child(moon)

	# Thin mountain snow drifting through the exterior shots.
	_snow = DragonRigScript.spawn_emitter(_sky_rig, "NightSnow", {
		"amount": 700, "lifetime": 9.0, "size": 0.10,
		"velocity": Vector2(0.4, 1.4), "spread": 25.0,
		"direction": Vector3(0.25, -1.0, 0.1),
		"gravity": Vector3(0.0, -0.9, 0.0), "grow": 0.8,
		"emission_radius": 70.0,
		"ramp": [[0.0, Color(0.8, 0.86, 1.0, 0.0)],
			[0.15, Color(0.8, 0.86, 1.0, 0.55)],
			[1.0, Color(0.8, 0.86, 1.0, 0.0)]],
		"blend": BaseMaterial3D.BLEND_MODE_ADD, "emission_energy": 0.6,
	})
	_snow.position = Vector3(-30, 55, -50)
	_snow.emitting = true


func _enter_interior() -> void:
	if _inside:
		return
	_inside = true
	if _world_env != null and _hall_env != null:
		_world_env.environment = _hall_env
	if _moon_light != null:
		_moon_light.visible = false
	if _hall_sun != null:
		_hall_sun.visible = true
	if _sky_rig != null:
		_sky_rig.visible = false
	if _snow != null:
		_snow.emitting = false
	if _glow != null:
		_glow.visible = true


func _build_cinematic_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 110
	add_child(_ui_layer)

	var fade := ColorRect.new()
	fade.name = "Curtain"
	fade.color = Color.BLACK
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui_layer.add_child(fade)
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 0.0, 1.2).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(fade.queue_free)

	# Letterbox bars sized by OFFSETS, not minimum size — a bare ColorRect
	# under BOTTOM_WIDE anchors collapses to zero height otherwise (the old
	# intro shipped with no bottom bar for exactly this reason).
	_top_bar = ColorRect.new()
	_top_bar.color = Color.BLACK
	_top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top_bar.offset_bottom = 75.0
	_ui_layer.add_child(_top_bar)
	_bottom_bar = ColorRect.new()
	_bottom_bar.color = Color.BLACK
	_bottom_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bottom_bar.offset_top = -75.0
	_ui_layer.add_child(_bottom_bar)

	_location_card = Control.new()
	_location_card.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_location_card.offset_left = 60
	_location_card.offset_bottom = -95
	_location_card.modulate.a = 0.0
	_ui_layer.add_child(_location_card)
	var loc_vbox := VBoxContainer.new()
	loc_vbox.add_theme_constant_override("separation", 2)
	# The card control is a zero-size anchor point at the bottom-left; the
	# text must grow UP from it or it lays out below the screen edge.
	loc_vbox.position = Vector2(0, -84)
	_location_card.add_child(loc_vbox)
	var loc_title := Label.new()
	loc_title.text = "SANCTUM CATHEDRAL"
	loc_title.add_theme_font_size_override("font_size",
		AdaptiveScaleScript.font(26, _location_card))
	loc_title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	loc_title.add_theme_color_override("font_outline_color", Color.BLACK)
	loc_title.add_theme_constant_override("outline_size", 8)
	loc_vbox.add_child(loc_title)
	var loc_sub := Label.new()
	loc_sub.text = "High Seat of the Nine Hauses"
	loc_sub.add_theme_font_size_override("font_size",
		AdaptiveScaleScript.font(14, _location_card))
	loc_sub.add_theme_color_override("font_color", Color(0.85, 0.82, 0.78))
	loc_sub.add_theme_color_override("font_outline_color", Color.BLACK)
	loc_sub.add_theme_constant_override("outline_size", 4)
	loc_vbox.add_child(loc_sub)

	var skip_lbl := Label.new()
	skip_lbl.text = "Space / Esc / Click — skip"
	skip_lbl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	skip_lbl.offset_right = -36
	skip_lbl.offset_bottom = -82
	skip_lbl.add_theme_font_size_override("font_size", 12)
	skip_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65, 0.8))
	_ui_layer.add_child(skip_lbl)


func _spawn_dragon() -> void:
	_dragon_root = Node3D.new()
	_dragon_root.name = "CinematicDragonRoot"
	add_child(_dragon_root)
	_dragon_rig = DragonRigScript.new()
	_dragon_rig.scale = Vector3.ONE * DRAGON_SCALE
	_dragon_root.add_child(_dragon_rig)
	_dragon_root.global_position = PATH_NIGHT[1]
	# The smooth, asymmetric, overlapping cycle authored in Blender — with a
	# fallback to the asset's own clip if the companion file is missing.
	if _dragon_rig.has_soar():
		_flap = DragonRigScript.SOAR_CLIP
	_dragon_rig.play_loop(_flap, 1.0)
	# The animal on top of the animation: head leads the turns, tail throws
	# wide and waves down its length (DragonRig.FlightSway).
	_sway = _dragon_rig.attach_flight_sway()
	# The wyrm's glow, painted onto the cathedral shell only (layer 10) —
	# the hall's meshes already carry their full 8-omni torch budget.
	_glow = OmniLight3D.new()
	_glow.name = "WyrmGlow"
	_glow.light_color = Color(1.0, 0.52, 0.22)
	_glow.light_energy = 1.15
	_glow.omni_range = 13.0
	_glow.shadow_enabled = false
	_glow.light_cull_mask = 1 << 9
	_glow.visible = false
	_dragon_root.add_child(_glow)


# ── the timeline ───────────────────────────────────────────────────────────


## Measure every leg once: 240 chords per leg, cumulative. This is what turns
## "spline parameter" into "distance flown" (see HOW IT FLIES).
func _build_arc_tables() -> void:
	_arc.clear()
	for leg: Array in LEGS:
		var tbl := PackedFloat32Array()
		tbl.resize(241)
		tbl[0] = 0.0
		var prev := _catmull(leg, 0.0)
		for i in range(1, 241):
			var p := _catmull(leg, float(i) / 240.0)
			tbl[i] = tbl[i - 1] + prev.distance_to(p)
			prev = p
		_arc.append(tbl)


## Spline parameter at `s01` of the leg's TOTAL LENGTH — the inverse of the
## arc table, by binary search.
func _u_at_arc(leg_idx: int, s01: float) -> float:
	if leg_idx < 0 or leg_idx >= _arc.size():
		return clampf(s01, 0.0, 1.0)
	var tbl: PackedFloat32Array = _arc[leg_idx]
	var last := tbl.size() - 1
	var total := tbl[last]
	if total <= 0.0001:
		return clampf(s01, 0.0, 1.0)
	var target := clampf(s01, 0.0, 1.0) * total
	var lo := 0
	var hi := last
	while lo < hi - 1:
		var mid := (lo + hi) / 2
		if tbl[mid] < target:
			lo = mid
		else:
			hi = mid
	var span := tbl[hi] - tbl[lo]
	var f := 0.0 if span <= 0.0001 else (target - tbl[lo]) / span
	return (float(lo) + f) / float(last)


func _catmull(pts: Array, t: float) -> Vector3:
	var n := pts.size()
	var f := clampf(t, 0.0, 0.9999) * (n - 1)
	var i := int(f)
	var u := f - i
	var p0: Vector3 = pts[maxi(i - 1, 0)]
	var p1: Vector3 = pts[i]
	var p2: Vector3 = pts[mini(i + 1, n - 1)]
	var p3: Vector3 = pts[mini(i + 2, n - 1)]
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * u
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u * u
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u * u * u)


func _shot(t: float) -> Array:
	## -> [leg_index (-1 = perched), distance_fraction, cam_pts, cam_u]
	## The dragon term is a fraction of the leg's LENGTH, not of its spline
	## parameter — so these easings shape speed, which is what they read as.
	if t < T_APPROACH:
		var u := t / T_APPROACH
		return [0, u, CAM_NIGHT, ease(u, 0.65)]
	elif t < T_NEEDLE:
		var u := (t - T_APPROACH) / (T_NEEDLE - T_APPROACH)
		return [1, u, CAM_APPROACH, u]
	elif t < T_NAVE:
		# THE OUVERTURE. Steady — a heavy thing already committed to its line,
		# not a falcon accelerating into a target (Bert: "a dragon is more
		# like a b2 bomber, not a f35"). The lens holds its own pace too.
		var u := (t - T_NEEDLE) / (T_NAVE - T_NEEDLE)
		return [2, ease(u, 1.0), CAM_NEEDLE, ease(u, 0.95)]
	elif t < T_PERCH:
		var u := (t - T_NAVE) / (T_PERCH - T_NAVE)
		return [3, ease(u, 0.92), CAM_NAVE, ease(u, 0.8)]
	elif t < T_TOUCH:
		# …and the last leg decelerates into the flare: a landing animal is
		# still fast at the top of the climb and almost stopped at the stone.
		var u := (t - T_PERCH) / (T_TOUCH - T_PERCH)
		return [4, ease(u, 0.45), CAM_PERCH, ease(u, 0.7)]
	elif t < T_IDLE:
		# The roar: hold on the perch — the crane home waits for stillness.
		var u := clampf((t - T_TOUCH) / (T_IDLE - T_TOUCH), 0.0, 1.0)
		return [-1, 1.0, CAM_HOLD, u]
	else:
		var u := clampf((t - T_IDLE) / (TOTAL - T_IDLE), 0.0, 1.0)
		return [-1, 1.0, CAM_HOME, ease(u, 0.45)]


## The stand-off this instant must hold. Exterior legs keep the cathedral in
## shot; the needle is allowed closest because the wyrm is flying AWAY into
## the oculus there (a trailing follow, not a pass).
func _min_standoff(t: float) -> float:
	if t < T_NEEDLE:
		return STAND_OFF_SKY
	if t < T_NAVE:
		return STAND_OFF_THREAD
	return STAND_OFF_NAVE


func _process(delta: float) -> void:
	if not _is_running or _skipped:
		return
	_elapsed += delta
	var t := _elapsed
	if t >= TOTAL + 4.0:   # failsafe: nothing may strand the board
		_finish_cinematic()
		return

	var shot := _shot(t)
	var leg: int = shot[0]
	var s01: float = shot[1]
	var cam_pts: Array = shot[2]
	var cu: float = shot[3]

	# ── the wyrm ──
	if leg >= 0:
		var pts: Array = LEGS[leg]
		var pos := _catmull(pts, _u_at_arc(leg, s01))
		if _path_pos == Vector3.INF:
			_path_pos = pos
		# HEADING from the frame's own displacement — the body points where
		# it is actually going, at the speed the easing actually produced.
		var step := pos - _path_pos
		if step.length() > 0.0005:
			_fwd = _fwd.slerp(step.normalized(),
				clampf(delta * HEADING_DAMP, 0.0, 1.0)).normalized()
		# TURN RATE, measured flat, then damped: the input to the bank and to
		# the head-lead / tail-throw of the secondary motion.
		var flat_step := Vector3(step.x, 0.0, step.z)
		if flat_step.length() > 0.0005 and delta > 0.0001:
			var flat_fwd := Vector3(_fwd.x, 0.0, _fwd.z)
			if flat_fwd.length() > 0.001:
				var raw := flat_fwd.normalized().signed_angle_to(
					flat_step.normalized(), Vector3.UP) / delta
				_turn = lerpf(_turn, clampf(raw, -3.0, 3.0),
					clampf(delta * TURN_DAMP, 0.0, 1.0))
		# THE BANK: rolled into the basis as the up vector, never post-applied.
		var bank_target := clampf(-_turn * BANK_GAIN, -BANK_MAX, BANK_MAX)
		_bank = lerpf(_bank, bank_target, clampf(delta * BANK_DAMP, 0.0, 1.0))
		var roll := _bank + sin(t * 0.63) * IDLE_ROLL
		var up := Vector3.UP.rotated(_fwd, roll)
		if absf(_fwd.dot(up)) < 0.995:
			_dragon_root.global_basis = Basis.looking_at(-_fwd, up)
		_path_pos = pos
		# THE WINGBEAT LIFTS THE BODY. The clip's own playhead drives it, so
		# the rise lands on the downstroke instead of drifting against it.
		_dragon_root.global_position = pos + Vector3.UP * _beat_lift()
		_fly_anim(t)
		if _sway != null:
			_sway.turn = _turn
			_sway.climb = clampf(_fwd.y * 2.2, -1.0, 1.0)
	else:
		_dragon_root.global_position = PERCH_POS
		var face := Basis.looking_at(Vector3(0, 0, 1), Vector3.UP)  # nose -Z→board
		_dragon_root.global_basis = _dragon_root.global_basis.slerp(face,
			clampf(delta * 5.0, 0.0, 1.0))
		if _sway != null:
			# Settling on the stone: the sway eases out over the landing so
			# the vigil pose is the clip's, not a half-applied turn.
			_sway.turn = lerpf(_sway.turn, 0.0, clampf(delta * 2.5, 0.0, 1.0))
			_sway.climb = lerpf(_sway.climb, 0.0, clampf(delta * 2.5, 0.0, 1.0))
			_sway.weight = lerpf(_sway.weight, 0.0, clampf(delta * 1.2, 0.0, 1.0))
		_perch_beats(t)

	# ── the camera ──
	var dragon_pos := _dragon_root.global_position
	var cam_pos: Vector3 = _catmull(cam_pts, cu)
	var look_target: Vector3
	if t >= T_IDLE:
		# The crane home: blend the aim from the wyrm to the board framing.
		var hu := clampf((t - T_IDLE) / (TOTAL - T_IDLE), 0.0, 1.0)
		var home_look := _home_xform.origin - _home_xform.basis.z * 8.0
		look_target = dragon_pos.lerp(home_look, ease(hu, 0.6))
		cam_pos = cam_pos.lerp(_home_xform.origin, ease(hu, 0.55))
	else:
		# Composed against the world (see THE FEATHER RULE): the aim sits a
		# fraction off the wyrm toward the space it is crossing, so the
		# cathedral holds the frame and the beast rides off-centre.
		look_target = dragon_pos.lerp(
			ANCHOR_NAVE if _inside else ANCHOR_SKY, COMPOSE_PULL)
	_look_smooth = _look_smooth.lerp(look_target, clampf(delta * LOOK_RATE, 0.0, 1.0))

	# THE STAND-OFF, ENFORCED. The lens backs off along its own axis until the
	# range is met — spline drift can never put the camera on the beast's back
	# again (the tower pass of the first cut sat 4 u off a 10 u wingspan).
	var aim := _look_smooth - cam_pos
	if aim.length() > 0.01 and t < T_IDLE:
		var d := cam_pos.distance_to(dragon_pos)
		var min_d := _min_standoff(t)
		if d < min_d:
			cam_pos -= aim.normalized() * (min_d - d)

	if _shake > 0.003:
		var s := _shake
		cam_pos += Vector3(sin(t * 71.0), sin(t * 89.0 + 1.7), sin(t * 63.0 + 3.1)) * s
		_shake = lerpf(_shake, 0.0, clampf(delta * 3.2, 0.0, 1.0))
	_cam.global_position = cam_pos
	if _cam.global_position.distance_to(_look_smooth) > 0.05:
		_cam.look_at(_look_smooth, Vector3.UP)
	# Wide glass the whole flight — it is what keeps the world around the
	# wyrm — easing to the gameplay lens only on the crane home.
	var target_fov := _game_cam.fov if t >= T_IDLE else FLIGHT_FOV
	_cam.fov = lerpf(_cam.fov, target_fov, clampf(delta * 2.5, 0.0, 1.0))

	# The night gives way to torchlight when the LENS crosses the facade, not
	# when the wyrm does — the camera trails it through the rose by a beat,
	# and swapping on the beast blacked out the sky while we were still in it.
	if not _inside and _cam.global_position.z > -25.6:
		_enter_interior()

	# ── UI beats ──
	if _location_card != null:
		if t < 1.4:
			_location_card.modulate.a = clampf((t - 0.6) / 0.8, 0.0, 1.0)
		elif t > T_NEEDLE - 0.8:
			_location_card.modulate.a = clampf(1.0 - (t - (T_NEEDLE - 0.8)) / 0.7,
				0.0, 1.0)
	var bar_u := clampf((t - (TOTAL - 1.4)) / 1.2, 0.0, 1.0)
	var bar_h := 75.0 * (1.0 - ease(bar_u, 0.5))
	if _top_bar != null:
		_top_bar.offset_bottom = bar_h
	if _bottom_bar != null:
		_bottom_bar.offset_top = -bar_h

	if t >= TOTAL:
		_finish_cinematic()


## The body's rise and fall on the wingbeat, read off the playhead of
## whatever flap clip is running (0 while gliding — a glider does not beat).
func _beat_lift() -> float:
	if _dragon_rig == null or _dragon_rig.anim == null:
		return 0.0
	var clip := _dragon_rig.anim.current_animation
	if clip != _flap:
		return 0.0
	var len := _dragon_rig.clip_length(clip)
	if len <= 0.01:
		return 0.0
	var phase := fmod(_dragon_rig.anim.current_animation_position, len) / len
	return sin(phase * TAU) * BEAT_LIFT * DRAGON_SCALE


func _fly_anim(t: float) -> void:
	## Wingbeat language: climbs flap, descents tuck into the glide — with a
	## HYSTERESIS BAND on the climb rate, because a threshold compared against
	## a live number chatters between two clips whenever the path is near
	## level, and that chatter is half of what read as robotic.
	if _dragon_rig == null or _dragon_rig.anim == null or _landing:
		return
	if t >= T_LAND:
		_landing = true
		var remain := maxf(T_TOUCH - t, 0.35)
		var clip_len := _dragon_rig.clip_length("Land_Settle")
		if clip_len > 0.05:
			_dragon_rig.play_once("Land_Settle", clip_len / remain)
		return
	if t >= T_PERCH:
		if _dragon_rig.anim.current_animation != "Flying_Idle":
			_dragon_rig.play_loop("Flying_Idle", 0.9, 0.6)   # the flare
		return
	var flapping := _dragon_rig.anim.current_animation == _flap
	var climb := _fwd.y
	if t >= T_NEEDLE and t < T_NAVE:
		# The stoop: wings IN. A falcon does not flap on the way down, and at
		# this scale the wings would not clear the oculus if it did.
		if _dragon_rig.anim.current_animation != "Glide":
			_dragon_rig.play_loop("Glide", 1.35, 0.55)
		return
	# Effort, continuously: the flap quickens with the climb instead of
	# snapping between two authored speeds.
	if flapping:
		if climb < -0.16:
			_dragon_rig.play_loop("Glide", 1.0, 0.7)
		else:
			_dragon_rig.anim.speed_scale = clampf(0.85 + climb * 1.6, 0.7, 1.5)
	else:
		if climb > -0.04:
			_dragon_rig.play_loop(_flap, 1.0, 0.7)
		else:
			_dragon_rig.anim.speed_scale = clampf(0.9 + absf(climb) * 0.5, 0.9, 1.3)


func _perch_beats(t: float) -> void:
	if t >= T_ROAR and not _roared:
		_roared = true
		_dragon_rig.play_once("Roar", 1.0)
		if _sting != null:
			_sting.play()
		_dragon_rig.set_ember_energy(2.6)
		if _glow != null:
			_glow.light_energy = 2.6   # the coals flare with the roar…
		_shake = 0.16
	if _roared and _glow != null and _glow.light_energy > 1.2:
		_glow.light_energy = lerpf(_glow.light_energy, 1.15, 0.05)   # …and bank
	if t >= T_IDLE and _roared \
			and _dragon_rig.anim != null \
			and _dragon_rig.anim.current_animation != "Perch_Idle":
		_dragon_rig.play_loop("Perch_Idle", 0.5, 0.5)
		_dragon_rig.set_ember_energy(0.85)   # settle to the vigil's coals


func _unhandled_input(event: InputEvent) -> void:
	if not _is_running:
		return
	var key_skip: bool = event.is_action_pressed("ui_accept") \
		or event.is_action_pressed("ui_cancel") \
		or (event is InputEventKey and event.pressed and not event.echo)
	var click_skip: bool = event is InputEventMouseButton and event.pressed
	if key_skip or click_skip:
		_skip_cinematic()
		get_viewport().set_input_as_handled()


func _skip_cinematic() -> void:
	if _skipped:
		return
	_skipped = true
	_finish_cinematic()


func _finish_cinematic() -> void:
	_is_running = false
	set_process(false)
	set_process_unhandled_input(false)
	# Restore the world exactly: env, sun, music, camera, rig.
	if _world_env != null and _hall_env != null:
		_world_env.environment = _hall_env
	if _hall_sun != null:
		_hall_sun.visible = true
	if _moon_light != null:
		_moon_light.visible = false
	if _sky_rig != null:
		_sky_rig.visible = false
	Music.unduck()
	if _game_cam != null:
		_game_cam.make_current()
	if _camera_rig != null:
		_camera_rig.set_process(true)
		_camera_rig.set_process_unhandled_input(true)
	if _ui_layer != null:
		_ui_layer.queue_free()
		_ui_layer = null
	# The witness is handed to the DragonSpectator (game.gd reveals it on
	# intro_completed and frees this node) — nothing lingers here.
	intro_completed.emit()
