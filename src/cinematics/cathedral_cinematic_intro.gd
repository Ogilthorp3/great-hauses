class_name CathedralCinematicIntro
extends Node3D
## CathedralCinematicIntro — the arrival of the witness.
##
## After the VS splash the player follows the wyrm through six shots:
##   1  THE NIGHT     moonlit cathedral on its crag; the dragon crosses high,
##                    a silhouette against the moon; the location card rises.
##   2  THE APPROACH  chase cam around the north tower, up between the spires.
##   3  THE NEEDLE    falcon-stoop into the OPEN west rose — the dragon door —
##                    threading the oculus; the camera follows it through and
##                    the night swaps to torchlight in the wall's thickness.
##   4  THE NAVE      the run: down the vaults, slaloming the chandeliers,
##                    one low pass over the board while the camera drops to
##                    the stones and watches it thunder overhead.
##   5  THE PERCH     pull-up, flare, and a Land_Settle onto the Wyrm's
##                    Gallery over the apse arch, the ember rose behind it.
##   6  THE VIGIL     the ROAR — coals kindle — then Perch_Idle, and one
##                    continuous crane down past the throne into the exact
##                    gameplay framing. The letterbox retracts; the fight is on.
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

const TOTAL := 25.5
const T_APPROACH := 4.2
const T_NEEDLE := 9.0
const T_THREAD := 11.15     # the frame the wyrm crosses the facade plane
const T_NAVE := 12.0
const T_PERCH := 17.5
const T_LAND := 20.2        # Land_Settle begins
const T_TOUCH := 21.2       # claws on the gallery stone
const T_ROAR := 21.6
const T_IDLE := 23.2
const DRAGON_SCALE := 1.65  # == DragonSpectator.dragon_scale: seamless swap

## Flight keys per shot (Catmull-Rom, world space).
const PATH_NIGHT := [
	Vector3(38, 50, -82), Vector3(34, 48, -78), Vector3(14, 42, -64),
	Vector3(-6, 37, -52), Vector3(-16, 34.5, -46), Vector3(-22, 34.5, -40)]
const PATH_APPROACH := [
	Vector3(-16, 34.5, -46), Vector3(-24, 34.8, -36), Vector3(-23, 34.0, -29),
	Vector3(-13, 37.0, -27), Vector3(0, 40.5, -28)]
const PATH_NEEDLE := [
	Vector3(0, 40.5, -28), Vector3(0, 31, -31), Vector3(0, 24.2, -30),
	Vector3(0, 21.7, -26.8), Vector3(0, 21.6, -23.5)]
const PATH_NAVE := [
	Vector3(0, 21.6, -23.5), Vector3(-2.0, 17.5, -14), Vector3(-3.4, 13.2, -8.5),
	Vector3(2.8, 10.5, -2.0), Vector3(0.4, 7.2, 3.5), Vector3(-1.2, 6.0, 6.5)]
const PATH_PERCH := [
	Vector3(-1.2, 6.0, 6.5), Vector3(0.6, 9.0, 9.5), Vector3(0.0, 13.6, 10.6),
	Vector3(0.0, 12.9, 12.4), Vector3(0.0, 12.2, 13.55)]
const PERCH_POS := Vector3(0.0, 12.2, 13.55)

## Camera keys per shot.
const CAM_NIGHT := [Vector3(-58, 3.5, -76), Vector3(-54, 7.0, -72),
	Vector3(-50, 10.0, -68)]
const CAM_APPROACH := [Vector3(-30, 29, -52), Vector3(-33, 33, -36),
	Vector3(-20, 39, -22), Vector3(-7, 43, -27)]
const CAM_NEEDLE := [Vector3(0, 45, -34), Vector3(-0.8, 27, -33.5),
	Vector3(-1.7, 20.4, -30.0), Vector3(-2.2, 18.9, -21.5)]
const CAM_NAVE := [Vector3(-2.2, 18.9, -21.5), Vector3(0, 17.5, -13),
	Vector3(4.8, 9.5, -5.0), Vector3(-4.5, 3.4, 8.6)]
const CAM_PERCH := [Vector3(-4.5, 3.4, 8.6), Vector3(-6.6, 5.2, 10.4),
	Vector3(-6.8, 9.4, 8.2), Vector3(-4.0, 13.0, 8.8)]
const CAM_HOLD := [Vector3(-4.0, 13.0, 8.8), Vector3(-3.6, 13.0, 8.4)]
const CAM_HOME := [Vector3(-3.6, 13.0, 8.4), Vector3(-2.4, 12.6, 3.2)]

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
var _is_running := false
var _elapsed := 0.0
var _skipped := false
var _inside := false
var _roared := false
var _landing := false
var _bank := 0.0
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
	_cam.fov = 55.0
	add_child(_cam)
	_cam.global_position = CAM_NIGHT[0]
	_look_smooth = Vector3(0, 24, -26)
	_cam.look_at(_look_smooth, Vector3.UP)
	_cam.make_current()

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
	_dragon_rig.play_loop("Fast_Flying", 1.15)
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
	## -> [dragon_pts, dragon_u, cam_pts, cam_u]
	if t < T_APPROACH:
		var u := t / T_APPROACH
		return [PATH_NIGHT, u, CAM_NIGHT, ease(u, 0.65)]
	elif t < T_NEEDLE:
		var u := (t - T_APPROACH) / (T_NEEDLE - T_APPROACH)
		return [PATH_APPROACH, u, CAM_APPROACH, u]
	elif t < T_NAVE:
		var u := (t - T_NEEDLE) / (T_NAVE - T_NEEDLE)
		return [PATH_NEEDLE, ease(u, 1.6), CAM_NEEDLE, ease(u, 1.5)]
	elif t < T_PERCH:
		var u := (t - T_NAVE) / (T_PERCH - T_NAVE)
		return [PATH_NAVE, u, CAM_NAVE, ease(u, 0.8)]
	elif t < T_TOUCH:
		var u := (t - T_PERCH) / (T_TOUCH - T_PERCH)
		return [PATH_PERCH, ease(u, 0.55), CAM_PERCH, ease(u, 0.7)]
	elif t < T_IDLE:
		# The roar: hold on the perch — the crane home waits for stillness.
		var u := clampf((t - T_TOUCH) / (T_IDLE - T_TOUCH), 0.0, 1.0)
		return [null, 1.0, CAM_HOLD, u]
	else:
		var u := clampf((t - T_IDLE) / (TOTAL - T_IDLE), 0.0, 1.0)
		return [null, 1.0, CAM_HOME, ease(u, 0.45)]


func _process(delta: float) -> void:
	if not _is_running or _skipped:
		return
	_elapsed += delta
	var t := _elapsed
	if t >= TOTAL + 4.0:   # failsafe: nothing may strand the board
		_finish_cinematic()
		return

	var shot := _shot(t)
	var dragon_pts: Variant = shot[0]
	var du: float = shot[1]
	var cam_pts: Array = shot[2]
	var cu: float = shot[3]

	# ── the wyrm ──
	if dragon_pts != null:
		var pos: Vector3 = _catmull(dragon_pts, du)
		var ahead: Vector3 = _catmull(dragon_pts, du + 0.012)
		var tangent := (ahead - pos)
		if tangent.length() > 0.001:
			tangent = tangent.normalized()
			# +Z is the wyrm's nose: -Z looks back along the tangent.
			var target := Basis.looking_at(-tangent, Vector3.UP)
			_dragon_root.global_basis = _dragon_root.global_basis.slerp(target,
				clampf(delta * 7.0, 0.0, 1.0))
			# Banking from the horizontal turn rate.
			var flat := Vector3(tangent.x, 0.0, tangent.z)
			var flat_ahead_v := _catmull(dragon_pts, du + 0.05) - pos
			var flat_ahead := Vector3(flat_ahead_v.x, 0.0, flat_ahead_v.z)
			if flat.length() > 0.01 and flat_ahead.length() > 0.01:
				var turn := flat.signed_angle_to(flat_ahead.normalized(), Vector3.UP)
				_bank = lerpf(_bank, clampf(turn * 6.0, -0.85, 0.85),
					clampf(delta * 4.0, 0.0, 1.0))
			_dragon_root.rotate_object_local(Vector3(0, 0, 1), _bank)
		_dragon_root.global_position = pos
		_fly_anim(t, tangent if dragon_pts != null else Vector3.FORWARD)
	else:
		_dragon_root.global_position = PERCH_POS
		var face := Basis.looking_at(Vector3(0, 0, 1), Vector3.UP)  # nose -Z→board
		_dragon_root.global_basis = _dragon_root.global_basis.slerp(face,
			clampf(delta * 5.0, 0.0, 1.0))
		_perch_beats(t)

	# The needle: swap night for torchlight as the wyrm crosses the facade.
	if not _inside and _dragon_root.global_position.z > -25.4:
		_enter_interior()

	# ── the camera ──
	var cam_pos: Vector3 = _catmull(cam_pts, cu)
	var look_target: Vector3
	if t < T_APPROACH:
		look_target = _dragon_root.global_position.lerp(Vector3(0, 24, -26), 0.35)
	elif t >= T_IDLE:
		# The crane home: blend the aim from the wyrm to the board framing.
		var hu := clampf((t - T_IDLE) / (TOTAL - T_IDLE), 0.0, 1.0)
		var home_look := _home_xform.origin - _home_xform.basis.z * 8.0
		look_target = _dragon_root.global_position.lerp(home_look, ease(hu, 0.6))
		cam_pos = cam_pos.lerp(_home_xform.origin, ease(hu, 0.55))
	else:
		look_target = _dragon_root.global_position \
			+ _dragon_root.global_basis.z * 1.2 + Vector3.UP * 0.4
	# Aim tracking: languid on the establishing shots, locked-on through the
	# nave run and the perch (the first captures aimed at walls while the
	# wyrm exited frame-top — the lag was this constant).
	var look_rate := 6.5 if t < T_NAVE else 12.0
	_look_smooth = _look_smooth.lerp(look_target, clampf(delta * look_rate, 0.0, 1.0))
	if _shake > 0.003:
		var s := _shake
		cam_pos += Vector3(sin(t * 71.0), sin(t * 89.0 + 1.7), sin(t * 63.0 + 3.1)) * s
		_shake = lerpf(_shake, 0.0, clampf(delta * 3.2, 0.0, 1.0))
	_cam.global_position = cam_pos
	if _cam.global_position.distance_to(_look_smooth) > 0.05:
		_cam.look_at(_look_smooth, Vector3.UP)
	# FOV: wide in flight, tightening onto the perch, home fov at the seam.
	var target_fov := 55.0
	if t >= T_IDLE:
		target_fov = _game_cam.fov
	elif t > T_PERCH:
		target_fov = 46.0
	_cam.fov = lerpf(_cam.fov, target_fov, clampf(delta * 2.5, 0.0, 1.0))

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


func _fly_anim(t: float, tangent: Vector3) -> void:
	## Wingbeat language: climbs flap, descents tuck into the glide.
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
			_dragon_rig.play_loop("Flying_Idle", 1.0, 0.45)   # the flare
		return
	var climbing := tangent.y > 0.12
	var diving := tangent.y < -0.30
	if t >= T_NEEDLE and t < T_NAVE:
		if _dragon_rig.anim.current_animation != "Glide":
			_dragon_rig.play_loop("Glide", 1.5, 0.3)   # the stoop: wings in
	elif climbing:
		if _dragon_rig.anim.current_animation != "Fast_Flying":
			_dragon_rig.play_loop("Fast_Flying", 1.25, 0.35)
	elif diving:
		if _dragon_rig.anim.current_animation != "Glide":
			_dragon_rig.play_loop("Glide", 1.1, 0.4)
	else:
		if _dragon_rig.anim.current_animation != "Fast_Flying":
			_dragon_rig.play_loop("Fast_Flying", 0.95, 0.5)


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
