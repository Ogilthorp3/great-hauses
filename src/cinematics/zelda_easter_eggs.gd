class_name ZeldaEasterEggs
extends Node
## Zelda & Retro Easter Eggs Suite for Great Hauses Chess.
##
## 1. Z-E-L-D-A / Konami Code -> 8-Note Zelda Secret Chime & Secret Haus of Courage (Hyrule)
## 2. Triple-Click King -> "It's dangerous to go alone! Take this." + Master Blade spawn
## 3. Rapid Rage Clicks (7x) / 'C' Key -> Cucco Revenge Attack with drifting feathers

const SECRET_CHIME_FREQS: Array[float] = [
	783.99,  # G5
	739.99,  # F#5
	622.25,  # D#5
	440.00,  # A4
	415.30,  # G#4
	659.25,  # E5
	830.61,  # G#5
	1046.50  # C6
]

const ITEM_FANFARE_FREQS: Array[float] = [
	554.37,  # C#5
	587.33,  # D5
	659.25,  # E5
	880.00   # A5
]

static var _secret_chime_stream: AudioStreamWAV = null
static var _fanfare_stream: AudioStreamWAV = null
static var _cucco_stream: AudioStreamWAV = null

# Input tracking
var _key_buffer: String = ""
var _konami_progress: int = 0
const KONAMI_SEQUENCE: Array[Key] = [
	KEY_UP, KEY_UP, KEY_DOWN, KEY_DOWN,
	KEY_LEFT, KEY_RIGHT, KEY_LEFT, KEY_RIGHT,
	KEY_B, KEY_A
]

var _king_click_times: Array[float] = []
var _rage_click_times: Array[float] = []

var _master_sword_node: Node3D = null
var _cucco_active := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Synthesize the authentic 8-note Zelda Secret Sound in pure 16-bit PCM.
static func get_secret_chime_stream() -> AudioStreamWAV:
	if _secret_chime_stream != null:
		return _secret_chime_stream
	_secret_chime_stream = _synthesize_melody(SECRET_CHIME_FREQS, 0.12, 0.04, true)
	return _secret_chime_stream


## Synthesize the 4-note Zelda Item Fanfare.
static func get_fanfare_stream() -> AudioStreamWAV:
	if _fanfare_stream != null:
		return _fanfare_stream
	_fanfare_stream = _synthesize_melody(ITEM_FANFARE_FREQS, 0.18, 0.08, true)
	return _fanfare_stream


## Synthesize a retro 8-bit Cucco cluck.
static func get_cucco_stream() -> AudioStreamWAV:
	if _cucco_stream != null:
		return _cucco_stream
	var sample_rate := 22050
	var dur := 0.28
	var total_samples := int(sample_rate * dur)
	var data := PackedByteArray()
	data.resize(total_samples * 2)

	for i in total_samples:
		var t := float(i) / float(sample_rate)
		# Frequency modulation for bird cluck: 400Hz -> 850Hz -> 300Hz
		var f := 420.0 + sin(t * 45.0) * 220.0 + sin(t * 120.0) * 110.0
		var env := sin(clampf(t / dur, 0.0, 1.0) * PI)
		# Square/triangle hybrid for retro chiptune cluck
		var phase := fposmod(t * f, 1.0)
		var val: float = (1.0 if phase < 0.5 else -1.0) * 0.4 + sin(t * f * TAU) * 0.6
		var sample := int(clampf(val * env * 0.7, -1.0, 1.0) * 32767.0)

		data.encode_s16(i * 2, sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	_cucco_stream = stream
	return _cucco_stream


static func _synthesize_melody(notes: Array[float], note_len: float, gap: float, bell: bool) -> AudioStreamWAV:
	var sample_rate := 22050
	var total_dur := (note_len + gap) * notes.size() + 0.6
	var total_samples := int(sample_rate * total_dur)
	var data := PackedByteArray()
	data.resize(total_samples * 2)

	for n_idx in notes.size():
		var freq: float = notes[n_idx]
		var start_time := float(n_idx) * (note_len + gap)
		var start_sample := int(start_time * sample_rate)
		var note_samples := int((note_len + 0.35) * sample_rate)

		for i in note_samples:
			var s_idx := start_sample + i
			if s_idx >= total_samples:
				break
			var t := float(i) / float(sample_rate)
			var env := exp(-t * 6.5) # Bell decay
			var w1 := sin(t * freq * TAU)
			var w2 := sin(t * freq * 2.0 * TAU) * 0.45
			var w3 := sin(t * freq * 3.0 * TAU) * 0.20
			var w4 := sin(t * freq * 4.0 * TAU) * 0.10
			var sample_val := (w1 + w2 + w3 + w4) * env * 0.42

			# Mix with existing data in buffer
			var prev_s: int = data.decode_s16(s_idx * 2)
			var mixed := clampf(float(prev_s) / 32767.0 + sample_val, -1.0, 1.0)
			data.encode_s16(s_idx * 2, int(mixed * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream


## Play any procedural sound effect
static func play_sound(parent: Node, stream: AudioStreamWAV, pitch: float = 1.0, vol_db: float = 0.0) -> void:
	if parent == null or stream == null or not parent.is_inside_tree():
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.pitch_scale = pitch
	player.volume_db = vol_db
	player.bus = "Master"
	parent.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


## Feed key event from UI or Game
func handle_key_input(event: InputEventKey, host: Node) -> bool:
	if not event.pressed or event.echo:
		return false

	# 1. Konami Code Tracker
	if _konami_progress < KONAMI_SEQUENCE.size() and event.keycode == KONAMI_SEQUENCE[_konami_progress]:
		_konami_progress += 1
		if _konami_progress == KONAMI_SEQUENCE.size():
			_konami_progress = 0
			trigger_zelda_secret(host, "KONAMI CODE!")
			return true
	else:
		_konami_progress = (1 if event.keycode == KONAMI_SEQUENCE[0] else 0)

	# 2. Text sequence tracker ("ZELDA")
	if event.unicode > 0:
		var ch := char(event.unicode).to_lower()
		if not ch.is_empty():
			_key_buffer += ch
			if _key_buffer.length() > 16:
				_key_buffer = _key_buffer.substr(_key_buffer.length() - 16)
			if _key_buffer.ends_with("zelda"):
				_key_buffer = ""
				trigger_zelda_secret(host, "TRIFORCE SECRET!")
				return true
			elif _key_buffer.ends_with("cucco"):
				_key_buffer = ""
				trigger_cucco_attack(host)
				return true
			elif _key_buffer.ends_with("falcon") or _key_buffer.ends_with("wookiee") or _key_buffer.ends_with("dejarik"):
				_key_buffer = ""
				trigger_holochess_secret(host)
				return true

	# 3. Direct cheat key 'C' in debug/easter mode
	if event.keycode == KEY_C and event.is_command_or_control_pressed():
		trigger_cucco_attack(host)
		return true

	return false


## Register a piece click for triple-click King and rage-click detectors
func handle_piece_clicked(piece_type: int, is_player_king: bool, host: Node) -> void:
	var now := Time.get_ticks_msec() / 1000.0

	# Clean old clicks
	while not _rage_click_times.is_empty() and now - _rage_click_times[0] > 1.8:
		_rage_click_times.pop_front()
	_rage_click_times.append(now)

	# 7 rapid clicks -> Cucco Storm
	if _rage_click_times.size() >= 7:
		_rage_click_times.clear()
		trigger_cucco_attack(host)
		return

	if is_player_king or piece_type == 5: # King piece
		while not _king_click_times.is_empty() and now - _king_click_times[0] > 2.0:
			_king_click_times.pop_front()
		_king_click_times.append(now)

		if _king_click_times.size() >= 3:
			_king_click_times.clear()
			trigger_master_sword(host)


## Trigger Secret Chime & Haus Hyrule Unlock
func trigger_zelda_secret(host: Node, subtitle: String = "THE SECRET OF HYRULE") -> void:
	_ensure_hyrule_registered()

	if host != null and host.is_inside_tree():
		play_sound(host, get_secret_chime_stream(), 1.0, 3.0)
		_show_retro_banner(host, "★ %s ★" % subtitle, "Haus of Courage is with you.")

	# If in HouseSelect, inject Hyrule Haus into UI ring
	if host is HouseSelect or (host != null and host.get_parent() is HouseSelect):
		var hs: HouseSelect = host if host is HouseSelect else host.get_parent()
		if not hs._house_ids.has("hyrule"):
			hs._house_ids.append("hyrule")
			hs._rebuild_ring()
			hs._set_ring_index(hs._house_ids.size() - 1)


## Register Haus Hyrule with Zelda Triforce sigil banner into HouseRegistry
static func _ensure_hyrule_registered() -> void:
	if HouseRegistry._by_id.has("hyrule"):
		return
	var hyrule_data: Dictionary = {
		"id": "hyrule",
		"name": "Haus Hyrule",
		"archetype": "courage",
		"seat": "Temple of Time",
		"motto": "Courage need not be remembered, for it is never forgotten.",
		"colors": {
			"primary": "#10782b",
			"secondary": "#f5c518",
			"accent": "#205493"
		},
		"tints": {
			"piece": "#a8e6b0",
			"tower": "#8ec498",
			"kit": "#10782b",
			"saturation": 0.40
		},
		"coat": "white_grey",
		"sigil": "res://assets/sigils/hyrule.png",
		"crest": "res://assets/custom-props/crests/crest_hyrule.glb"
	}
	HouseRegistry._by_id["hyrule"] = hyrule_data
	HouseRegistry._order.append("hyrule")


## Trigger Millennium Falcon Dejarik HoloChess Secret
func trigger_holochess_secret(host: Node) -> void:
	if host == null or not host.is_inside_tree():
		return

	# If host has HoloChessGamification, activate it
	var hc: Node = host.get_node_or_null("HoloChessGamification")
	var board_node: Node3D = host.get_node_or_null("Board")
	if hc != null and board_node != null:
		if hc.has_method("toggle_holochess_mode"):
			hc.call("toggle_holochess_mode", board_node)

	play_sound(host, get_fanfare_stream(), 0.9, 3.0)
	_show_retro_banner(host, "★ LET THE WOOKIEE WIN ★", "Dejarik Holographic Battle Matrix Active")


## Trigger Master Sword drop and fanfare
func trigger_master_sword(host: Node) -> void:
	if host == null or not host.is_inside_tree():
		return
	play_sound(host, get_fanfare_stream(), 1.0, 4.0)
	_show_retro_banner(host, "IT'S DANGEROUS TO GO ALONE!", "TAKE THIS. 🗡️")

	# Spawn Master Blade in 3D scene
	var scene_root := host.get_tree().current_scene if host.get_tree() != null else host
	if _master_sword_node != null and is_instance_valid(_master_sword_node):
		_master_sword_node.queue_free()

	_master_sword_node = _build_master_sword()
	scene_root.add_child(_master_sword_node)
	_master_sword_node.global_position = Vector3(0.0, 5.0, 0.0)

	# Animate sword dropping into board center
	var tw := host.create_tween().set_parallel(true)
	tw.tween_property(_master_sword_node, "global_position", Vector3(0.0, 0.15, 0.0), 0.8)\
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_master_sword_node, "rotation:y", TAU * 2.0, 0.8)


## Trigger Cucco Revenge Flurry
func trigger_cucco_attack(host: Node) -> void:
	if _cucco_active or host == null or not host.is_inside_tree():
		return
	_cucco_active = true

	play_sound(host, get_cucco_stream(), 1.0, 5.0)
	# Double cluck
	var timer := host.get_tree().create_timer(0.22)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(host) and host.is_inside_tree():
			play_sound(host, get_cucco_stream(), 1.18, 5.0)
	)

	_show_retro_banner(host, "BEWARE THE CUCCO'S WRATH!", "An angry flock swarms the hall! 🐔")

	# Spawn feather flurry
	var scene_root := host.get_tree().current_scene if host.get_tree() != null else host
	var flurry := _build_feather_flurry()
	scene_root.add_child(flurry)
	flurry.global_position = Vector3(0.0, 4.5, 0.0)

	var reset_timer := host.get_tree().create_timer(5.0)
	reset_timer.timeout.connect(func() -> void:
		_cucco_active = false
		if is_instance_valid(flurry):
			flurry.queue_free()
	)


## Create a retro Zelda-style proclamation banner overlay
func _show_retro_banner(parent: Node, title: String, subtitle: String) -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 120
	parent.add_child(canvas)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.15
	panel.anchor_bottom = 0.15
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.06, 0.94)
	style.border_color = Color(0.95, 0.82, 0.25, 1.0)
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.content_margin_left = 32
	style.content_margin_right = 32
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	style.shadow_color = Color(0, 0, 0, 0.7)
	style.shadow_size = 12
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)

	var lbl_title := Label.new()
	lbl_title.text = title
	lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_title.add_theme_color_override("font_color", Color(1.0, 0.90, 0.35))
	lbl_title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(lbl_title)

	var lbl_sub := Label.new()
	lbl_sub.text = subtitle
	lbl_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_sub.add_theme_color_override("font_color", Color(0.85, 0.95, 0.88))
	lbl_sub.add_theme_font_size_override("font_size", 16)
	vbox.add_child(lbl_sub)

	panel.add_child(vbox)
	canvas.add_child(panel)

	# Fade in and out
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.8, 0.8)
	panel.pivot_offset = panel.size * 0.5

	var tw := parent.create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.25)
	tw.parallel().tween_property(panel, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(3.2)
	tw.tween_property(panel, "modulate:a", 0.0, 0.4)
	tw.tween_callback(canvas.queue_free)


## Construct the procedural 3D Master Sword
static func _build_master_sword() -> Node3D:
	var root := Node3D.new()
	root.name = "MasterSwordSecret"

	# Blade (Glowing cyan-steel)
	var blade_mesh := BoxMesh.new()
	blade_mesh.size = Vector3(0.08, 1.4, 0.02)
	var blade_mat := StandardMaterial3D.new()
	blade_mat.albedo_color = Color(0.85, 0.95, 1.0)
	blade_mat.metallic = 0.9
	blade_mat.roughness = 0.15
	blade_mat.emission_enabled = true
	blade_mat.emission = Color(0.2, 0.7, 1.0) * 1.8
	var blade_inst := MeshInstance3D.new()
	blade_inst.mesh = blade_mesh
	blade_inst.material_override = blade_mat
	blade_inst.position.y = 0.7
	root.add_child(blade_inst)

	# Crossguard (Hylian Purple-Blue with wings)
	var guard_mesh := BoxMesh.new()
	guard_mesh.size = Vector3(0.42, 0.08, 0.08)
	var guard_mat := StandardMaterial3D.new()
	guard_mat.albedo_color = Color(0.18, 0.22, 0.48)
	guard_mat.metallic = 0.8
	guard_mat.roughness = 0.3
	var guard_inst := MeshInstance3D.new()
	guard_inst.mesh = guard_mesh
	guard_inst.material_override = guard_mat
	guard_inst.position.y = 1.42
	root.add_child(guard_inst)

	# Triforce Gem on Crossguard (Gold)
	var gem_mesh := PrismMesh.new()
	gem_mesh.size = Vector3(0.09, 0.09, 0.09)
	var gem_mat := StandardMaterial3D.new()
	gem_mat.albedo_color = Color(1.0, 0.84, 0.0)
	gem_mat.emission_enabled = true
	gem_mat.emission = Color(1.0, 0.84, 0.0) * 3.0
	var gem_inst := MeshInstance3D.new()
	gem_inst.mesh = gem_mesh
	gem_inst.material_override = gem_mat
	gem_inst.position = Vector3(0.0, 1.42, 0.05)
	root.add_child(gem_inst)

	# Hilt / Grip (Green-wrapped leather)
	var hilt_mesh := CylinderMesh.new()
	hilt_mesh.top_radius = 0.03
	hilt_mesh.bottom_radius = 0.03
	hilt_mesh.height = 0.38
	var hilt_mat := StandardMaterial3D.new()
	hilt_mat.albedo_color = Color(0.12, 0.42, 0.22)
	var hilt_inst := MeshInstance3D.new()
	hilt_inst.mesh = hilt_mesh
	hilt_inst.material_override = hilt_mat
	hilt_inst.position.y = 1.63
	root.add_child(hilt_inst)

	# Pommel (Gold)
	var pommel_mesh := SphereMesh.new()
	pommel_mesh.radius = 0.055
	pommel_mesh.height = 0.11
	var pommel_inst := MeshInstance3D.new()
	pommel_inst.mesh = pommel_mesh
	pommel_inst.material_override = gem_mat
	pommel_inst.position.y = 1.84
	root.add_child(pommel_inst)

	return root


## Construct a procedural drifting feather flurry
static func _build_feather_flurry() -> Node3D:
	var container := Node3D.new()
	container.name = "CuccoFlurry"

	var count := 32
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var feather_mat := StandardMaterial3D.new()
	feather_mat.albedo_color = Color(0.98, 0.98, 0.94)
	feather_mat.roughness = 0.9
	feather_mat.emission_enabled = true
	feather_mat.emission = Color(1.0, 0.95, 0.8) * 0.4

	for i in count:
		var feather := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2(0.18, 0.35)
		feather.mesh = mesh
		feather.material_override = feather_mat
		container.add_child(feather)

		var start_pos := Vector3(
			rng.randf_range(-4.0, 4.0),
			rng.randf_range(2.0, 5.0),
			rng.randf_range(-4.0, 4.0)
		)
		feather.position = start_pos

		var tw := container.create_tween().set_loops()
		var drop_dur := rng.randf_range(2.0, 4.0)
		var end_pos := Vector3(start_pos.x + rng.randf_range(-1.2, 1.2), 0.1, start_pos.z + rng.randf_range(-1.2, 1.2))
		tw.tween_property(feather, "position", end_pos, drop_dur).from(start_pos)
		tw.parallel().tween_property(feather, "rotation:y", TAU * rng.randf_range(1.0, 3.0), drop_dur)
		tw.parallel().tween_property(feather, "rotation:z", 0.5 * sin(float(i)), drop_dur)

	return container
