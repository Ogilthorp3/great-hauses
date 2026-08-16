class_name HoloChessGamification
extends Node
## HoloChessGamification — Gamified Millennium Falcon Dejarik Hologram Mode,
## living animated piece idles & fidgets, victory flourishes, floating combat badges,
## and arcade combo momentum for Great Hauses.
##
## Multiplatform: Fully optimized for macOS, Windows, and visionOS spatial immersion.

signal holochess_mode_toggled(enabled: bool)
signal combat_badge_spawned(text: String, world_pos: Vector3, color: Color)
signal combo_updated(streak: int, title: String)

var is_holochess_active := false
var combo_streak := 0
var last_kill_time_ms := 0
const COMBO_WINDOW_MS := 45000  # 45 seconds combo window

# Projector and visual nodes
var _projector_root: Node3D = null
var _pylons: Array[Node3D] = []
var _holo_beams: Array[MeshInstance3D] = []

# Idle and fidget tracking
var _idle_time := 0.0
var _piece_phases: Dictionary = {}  # Node3D -> float phase
var _threatened_pieces: Array = []

# Floating badges layer
var _badge_layer: CanvasLayer = null
var _hud_meter: Control = null
var _hud_meter_label: Label = null
var _hud_streak_label: Label = null


func _ready() -> void:
	_build_ui()


func _process(delta: float) -> void:
	_idle_time += delta
	_update_living_idles(delta)
	_update_holo_effects(delta)


# ── 1. PROCEDURAL SOUND SYNTHESIS (Zero disk dependencies) ───────────────────

## Synthesize retro Dejarik Holo-Projector hum / startup stinger
static func get_holo_startup_stream() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 1.2
	var total_samples := int(sample_rate * duration)
	var byte_array := PackedByteArray()
	byte_array.resize(total_samples * 2)

	for i in range(total_samples):
		var t := float(i) / float(sample_rate)
		# Ascending holographic laser frequencies + sub-bass hum
		var freq := 220.0 + (t * t * 680.0)
		var s1 := sin(TAU * freq * t)
		var s2 := sin(TAU * (freq * 1.5) * t) * 0.4
		var hum := sin(TAU * 55.0 * t) * 0.5
		var env := clampf(t / 0.1, 0.0, 1.0) * clampf((duration - t) / 0.3, 0.0, 1.0)
		var sample := (s1 + s2 + hum) * env * 0.55
		var s16 := int(clampf(sample, -1.0, 1.0) * 32767.0)
		byte_array.encode_s16(i * 2, s16)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = byte_array
	return stream


## Synthesize Dejarik Alien Monster Roar / Critical Slam
static func get_alien_roar_stream() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.95
	var total_samples := int(sample_rate * duration)
	var byte_array := PackedByteArray()
	byte_array.resize(total_samples * 2)

	for i in range(total_samples):
		var t := float(i) / float(sample_rate)
		# Frequency modulation for gargling beast roar
		var mod := sin(TAU * 45.0 * t) * 70.0
		var freq := maxf(80.0 + mod - (t * 40.0), 30.0)
		var noise := (randf() * 2.0 - 1.0) * 0.35
		var wave := sin(TAU * freq * t) + noise
		var env := clampf(t / 0.08, 0.0, 1.0) * clampf((duration - t) / 0.4, 0.0, 1.0)
		var sample := wave * env * 0.65
		var s16 := int(clampf(sample, -1.0, 1.0) * 32767.0)
		byte_array.encode_s16(i * 2, s16)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = byte_array
	return stream


## Synthesize Arcade Combat Badge Pop
static func get_badge_pop_stream() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.35
	var total_samples := int(sample_rate * duration)
	var byte_array := PackedByteArray()
	byte_array.resize(total_samples * 2)

	for i in range(total_samples):
		var t := float(i) / float(sample_rate)
		var freq := 880.0 - (t * 500.0)
		var s1 := sin(TAU * freq * t)
		var s2 := sin(TAU * (freq * 2.0) * t) * 0.3
		var env := exp(-t * 9.0)
		var sample := (s1 + s2) * env * 0.6
		var s16 := int(clampf(sample, -1.0, 1.0) * 32767.0)
		byte_array.encode_s16(i * 2, s16)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = byte_array
	return stream


func play_audio(stream: AudioStreamWAV, vol_db: float = 0.0) -> void:
	if stream == null or not is_inside_tree():
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = vol_db
	player.autoplay = true
	add_child(player)
	player.finished.connect(func(): player.queue_free())


# ── 2. LIVING BOARD GAME IDLE & FIDGET SYSTEM ─────────────────────────────────

func register_piece(pv: Node3D) -> void:
	if pv != null and is_instance_valid(pv) and not _piece_phases.has(pv):
		_piece_phases[pv] = randf() * TAU


func unregister_piece(pv: Node3D) -> void:
	_piece_phases.erase(pv)


func _update_living_idles(delta: float) -> void:
	# Subtle procedural breathing & weapon stance micro-sways
	for pv in _piece_phases.keys():
		if pv == null or not is_instance_valid(pv):
			continue
		var phase: float = _piece_phases.get(pv, 0.0)
		phase += delta * 1.8
		_piece_phases[pv] = phase

		# Gentle vertical breathing (1-2mm) and lateral micro-sway
		if not pv.has_meta("is_moving") and not pv.has_meta("is_dueling"):
			var breath_y := sin(phase) * 0.006
			var sway_rot := cos(phase * 0.5) * 0.012
			var mesh_node: Node3D = pv.get_node_or_null("MeshRoot")
			if mesh_node != null and is_instance_valid(mesh_node):
				mesh_node.position.y = breath_y
				mesh_node.rotation.z = sway_rot


func trigger_check_alert(king_view: Node3D, defenders: Array) -> void:
	## When king is in check, pieces adopt alarmed defensive postures!
	if king_view != null and is_instance_valid(king_view):
		var tw := king_view.create_tween()
		tw.tween_property(king_view, "scale", Vector3(1.12, 0.92, 1.12), 0.12)
		tw.tween_property(king_view, "scale", Vector3(1.0, 1.0, 1.0), 0.18)
		# Procedural shudder
		for i in range(4):
			tw.tween_property(king_view, "position:x", king_view.position.x + (0.04 if i % 2 == 0 else -0.04), 0.04)
		tw.tween_property(king_view, "position:x", king_view.position.x, 0.06)

	for d in defenders:
		var node: Node3D = d as Node3D
		if node != null and is_instance_valid(node):
			var tw_d := node.create_tween()
			if tw_d != null:
				tw_d.tween_property(node, "rotation:x", -0.08, 0.15)  # brace forward
				tw_d.tween_property(node, "rotation:x", 0.0, 0.3)


# ── 3. VICTORY CELEBRATIONS (POST-KILL FLOURISHES) ────────────────────────────

func play_victory_flourish(winner: Node3D) -> void:
	if winner == null or not is_instance_valid(winner):
		return

	var p_type: int = winner.get("piece_type") if "piece_type" in winner else 0
	var base_pos := winner.position

	match p_type:
		0: # PAWN
			# Triumphant hop + weapon brandish
			var tw := winner.create_tween()
			tw.tween_property(winner, "position:y", base_pos.y + 0.28, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(winner, "rotation:y", winner.rotation.y + PI * 0.25, 0.14)
			tw.tween_property(winner, "position:y", base_pos.y, 0.16).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(winner, "rotation:y", winner.rotation.y, 0.16)

		2: # KNIGHT
			# Mount rears up 40 degrees on hind legs with heroic stomp
			var tw := winner.create_tween()
			tw.tween_property(winner, "rotation:x", winner.rotation.x - deg_to_rad(38.0), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(winner, "position:y", base_pos.y + 0.35, 0.22)
			tw.tween_interval(0.12)
			tw.tween_property(winner, "rotation:x", winner.rotation.x, 0.18).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(winner, "position:y", base_pos.y, 0.18)

		3: # BISHOP
			# Levitation & radiant mystic pulse
			var tw := winner.create_tween()
			tw.tween_property(winner, "position:y", base_pos.y + 0.45, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(winner, "rotation:y", winner.rotation.y + TAU, 0.45)
			tw.tween_property(winner, "position:y", base_pos.y, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

		1: # ROOK
			# Heavy earth-shaking ground slam
			var tw := winner.create_tween()
			tw.tween_property(winner, "scale", Vector3(0.85, 1.25, 0.85), 0.15)
			tw.tween_property(winner, "scale", Vector3(1.22, 0.82, 1.22), 0.12)
			tw.tween_property(winner, "scale", Vector3(1.0, 1.0, 1.0), 0.18)

		4: # QUEEN
			# 360 spin pirouette and bow
			var tw := winner.create_tween()
			tw.tween_property(winner, "rotation:y", winner.rotation.y + TAU, 0.38).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(winner, "position:y", base_pos.y + 0.2, 0.19)
			tw.tween_property(winner, "position:y", base_pos.y, 0.19)

		5: # KING
			# Imperial raise
			var tw := winner.create_tween()
			tw.tween_property(winner, "scale", Vector3(1.15, 1.15, 1.15), 0.2)
			tw.tween_interval(0.2)
			tw.tween_property(winner, "scale", Vector3(1.0, 1.0, 1.0), 0.2)


# ── 4. DEJARIK HOLOCHESS PROJECTOR MODE ───────────────────────────────────────

func toggle_holochess_mode(parent_board: Node3D) -> bool:
	is_holochess_active = not is_holochess_active
	holochess_mode_toggled.emit(is_holochess_active)

	if is_holochess_active:
		play_audio(get_holo_startup_stream(), 2.0)
		_build_projector_pylons(parent_board)
		spawn_combat_badge("★ HOLOCHESS MATRIX ONLINE ★", Vector3(0, 1.2, 0), Color(0.2, 0.9, 1.0))
	else:
		_teardown_projector_pylons()
		spawn_combat_badge("Hologram Projector Standby", Vector3(0, 1.2, 0), Color(0.8, 0.8, 0.8))

	return is_holochess_active


func _build_projector_pylons(parent_board: Node3D) -> void:
	if _projector_root != null and is_instance_valid(_projector_root):
		_projector_root.queue_free()

	_projector_root = Node3D.new()
	_projector_root.name = "HoloProjectorRoot"
	parent_board.add_child(_projector_root)
	_pylons.clear()
	_holo_beams.clear()

	# 4 Corner projector nodes around the chess table
	var corners = [
		Vector3(-4.4, 0.1, -4.4),
		Vector3(4.4, 0.1, -4.4),
		Vector3(4.4, 0.1, 4.4),
		Vector3(-4.4, 0.1, 4.4)
	]

	for i in range(corners.size()):
		var c: Vector3 = corners[i]
		var pylon := Node3D.new()
		pylon.position = c
		_projector_root.add_child(pylon)
		_pylons.append(pylon)

		# Pylon emitter base
		var base_mesh := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.18
		cyl.bottom_radius = 0.24
		cyl.height = 0.28
		base_mesh.mesh = cyl
		
		var mat_base := StandardMaterial3D.new()
		mat_base.albedo_color = Color(0.12, 0.18, 0.26)
		mat_base.metallic = 0.9
		mat_base.roughness = 0.3
		mat_base.emission_enabled = true
		mat_base.emission = Color(0.2, 0.85, 1.0)
		mat_base.emission_energy_multiplier = 2.5
		base_mesh.material_override = mat_base
		pylon.add_child(base_mesh)

		# Hologram conical light beam aiming towards board center
		var beam := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.05
		cone.bottom_radius = 3.5
		cone.height = 4.2
		beam.mesh = cone
		beam.position = Vector3(0, 2.1, 0)
		
		var mat_beam := StandardMaterial3D.new()
		mat_beam.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat_beam.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat_beam.albedo_color = Color(0.15, 0.75, 1.0, 0.08)
		mat_beam.cull_mode = BaseMaterial3D.CULL_DISABLED
		beam.material_override = mat_beam
		pylon.add_child(beam)
		_holo_beams.append(beam)


func _teardown_projector_pylons() -> void:
	if _projector_root != null and is_instance_valid(_projector_root):
		var pr := _projector_root
		_projector_root = null
		if pr.get_parent() != null:
			pr.get_parent().remove_child(pr)
		pr.queue_free()
	_pylons.clear()
	_holo_beams.clear()


func _update_holo_effects(delta: float) -> void:
	if not is_holochess_active or _holo_beams.is_empty():
		return
	var flicker := 0.07 + sin(_idle_time * 18.0) * 0.02 + (randf() * 0.015)
	for b in _holo_beams:
		if b != null and is_instance_valid(b):
			var mat: StandardMaterial3D = b.material_override
			if mat != null:
				mat.albedo_color.a = flicker


# ── 5. ARCADE COMBO & FLOATING COMBAT BADGES ──────────────────────────────────

func record_capture(tier: int, mover_name: String, victim_name: String, world_pos: Vector3) -> void:
	var now := Time.get_ticks_msec()
	if now - last_kill_time_ms < COMBO_WINDOW_MS:
		combo_streak += 1
	else:
		combo_streak = 1
	last_kill_time_ms = now

	# Dynamic combat badge titles
	var badge_text := ""
	var badge_color := Color(1.0, 0.9, 0.4)

	match tier:
		2:
			badge_text = "★ SHOWSTOPPER SLAM! ★"
			badge_color = Color(1.0, 0.25, 0.25)
			play_audio(get_alien_roar_stream(), 1.5)
		1:
			badge_text = "⚡ FLANK STRIKE! ⚡"
			badge_color = Color(0.3, 0.85, 1.0)
			play_audio(get_badge_pop_stream(), 0.0)
		_:
			if combo_streak >= 3:
				badge_text = "🔥 COMBO x%d! 🔥" % combo_streak
				badge_color = Color(1.0, 0.6, 0.1)
			else:
				badge_text = "⚔ CRITICAL HIT! ⚔"
				badge_color = Color(0.9, 0.9, 0.9)
			play_audio(get_badge_pop_stream(), -2.0)

	spawn_combat_badge(badge_text, world_pos, badge_color)
	_update_hud_meter(tier)


func spawn_combat_badge(text: String, world_pos: Vector3, color: Color) -> void:
	combat_badge_spawned.emit(text, world_pos, color)
	if _badge_layer == null or not is_inside_tree():
		return

	var cam := get_viewport().get_camera_3d()
	var screen_pos := Vector2(get_viewport().size.x * 0.5, get_viewport().size.y * 0.35)
	if cam != null and is_instance_valid(cam):
		if not cam.is_position_behind(world_pos):
			screen_pos = cam.unproject_position(world_pos)

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.08, 0.95))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = screen_pos - Vector2(150, 40)
	label.custom_minimum_size = Vector2(300, 40)
	_badge_layer.add_child(label)

	# Floating rise and fade tween
	var tw := label.create_tween()
	tw.tween_property(label, "position:y", label.position.y - 70.0, 1.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(label, "scale", Vector3(1.2, 1.2, 1.2), 0.15)
	tw.tween_property(label, "scale", Vector3(1.0, 1.0, 1.0), 0.15)
	tw.parallel().tween_property(label, "modulate:a", 0.0, 0.6).set_delay(0.5)
	tw.tween_callback(label.queue_free)


func _build_ui() -> void:
	_badge_layer = CanvasLayer.new()
	_badge_layer.name = "HoloChessArcadeLayer"
	add_child(_badge_layer)

	_hud_meter = Control.new()
	_hud_meter.name = "MomentumMeter"
	_hud_meter.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hud_meter.position = Vector2(-280, -90)
	_badge_layer.add_child(_hud_meter)

	_hud_streak_label = Label.new()
	_hud_streak_label.text = "⚔ BATTLE MOMENTUM"
	_hud_streak_label.add_theme_font_size_override("font_size", 14)
	_hud_streak_label.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0))
	_hud_streak_label.add_theme_constant_override("outline_size", 4)
	_hud_meter.add_child(_hud_streak_label)

	_hud_meter_label = Label.new()
	_hud_meter_label.text = "READY FOR BATTLE"
	_hud_meter_label.position.y = 20
	_hud_meter_label.add_theme_font_size_override("font_size", 18)
	_hud_meter_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	_hud_meter_label.add_theme_constant_override("outline_size", 5)
	_hud_meter.add_child(_hud_meter_label)


func _update_hud_meter(tier: int) -> void:
	if _hud_meter_label == null:
		return
	var title := "STRIKE x%d" % combo_streak
	if combo_streak >= 4:
		title = "🔥 UNSTOPPABLE x%d! 🔥" % combo_streak
	elif combo_streak >= 2:
		title = "⚡ RAMPAGE x%d! ⚡" % combo_streak
	elif tier == 2:
		title = "★ SHOWSTOPPER! ★"

	_hud_meter_label.text = title
	combo_updated.emit(combo_streak, title)

	var tw := _hud_meter.create_tween()
	tw.tween_property(_hud_meter, "scale", Vector3(1.15, 1.15, 1.15), 0.1)
	tw.tween_property(_hud_meter, "scale", Vector3(1.0, 1.0, 1.0), 0.15)
