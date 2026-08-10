class_name MusicManager
extends Node
## Layered music director for Great Hauses — menu/gameplay playlists, duel
## stings, victory/defeat/championship fanfares, ducking and persisted volume.
##
## Designed to run as an autoload named "Music" (NOT "MusicManager" — an
## autoload sharing its script's class_name hides the global class):
##     Music="*res://src/audio/music_manager.gd"
##
## Architecture:
## - Two "deck" AudioStreamPlayers crossfade playlist tracks (2 s, tweened
##   volume_db with a -60 dB silence floor — no pops, no hard cuts).
## - A dedicated sting player fires duel stingers OVER the gameplay deck.
## - A dedicated fanfare player carries victory/defeat/championship pieces.
## - All four route through a runtime-created "Music" bus; master music
##   volume (0-100) and mute live on that bus and persist to
##   user://settings.json (read-merge-write; other keys are preserved).
## - duck()/unduck() lower ONLY the playlist decks by DUCK_DB (-8 dB) so
##   dialogue/cinematics read over the underscore while stings stay hot.
## - Playlist advancement is wall-clock scheduled (ignore_time_scale timers)
##   so the DuelDirector's Engine.time_scale dips never stall rotation.
##   Note: DuelDirector pitch-bends every AudioStreamPlayer it finds during
##   slow-mo — music (and a mid-duel sting) dropping in pitch is by design.
##
## No other scene or script is modified: the M-key mute toggle is handled
## here via _unhandled_key_input, and every entry point below is a plain
## call for the integrator (see INTEGRATION-music.md).

const SETTINGS_PATH_DEFAULT := "user://settings.json"
const BUS_NAME := "Music"

const CROSSFADE := 2.0          ## playlist crossfade, seconds
const END_FADE := 1.5           ## playlist fade-out on game end, seconds
const DUCK_DB := -8.0           ## cinematic duck applied to playlist decks
const DUCK_FADE := 0.35         ## duck/unduck ramp, seconds
const SILENCE_DB := -60.0       ## fade floor — players stop here, never 0-cut
const DEFAULT_VOLUME := 70      ## first-run master music volume (0-100)

const MENU_TRACKS: Array[String] = [
	"res://assets/music/menu/Teller_of_the_Tales.mp3",
	"res://assets/music/menu/Minstrel_Guild.mp3",
]
const GAME_TRACKS: Array[String] = [
	"res://assets/music/game/Achaidh_Cheide.mp3",
	"res://assets/music/game/Lord_of_the_Land.mp3",
	"res://assets/music/game/Skye_Cuillin.mp3",
]
const STING_TRACKS: Array[String] = [
	"res://assets/music/stings/Orchestral_Stinger_Dramatic_Entrance.mp3",
	"res://assets/music/stings/Dark_Stinger_1.mp3",
]
const VICTORY_TRACK := "res://assets/music/fanfare/Medieval_Victory_Theme.mp3"
const DEFEAT_TRACK := "res://assets/music/defeat/Agnus_Dei_X.mp3"
const CHAMPIONSHIP_TRACK := "res://assets/music/fanfare/Fanfare_for_Space.mp3"

## ── TRIAL BY FIRE: three tiers of ONE loop, played at once ─────────────────
## "Medieval music meets Kraftwerk" — original, licence-free (see
## assets/music/trial/Trial_By_Fire.license.txt). All three files are the SAME
## 60.000 s / 128 BPM loop rendered with progressively more layers switched on,
## which is why they are not a playlist and never crossfade as TRACKS: all
## three start in the SAME FRAME and only their VOLUMES move. Nothing re-seeks,
## so a tier change cannot drop a beat and the three can never drift apart —
## the escalation is a mix move, exactly as the stems were rendered for.
const TRIAL_TIERS: Array[String] = [
	"res://assets/music/trial/Trial_By_Fire_Tier1_Fuse.wav",    # 0 — the fuse
	"res://assets/music/trial/Trial_By_Fire_Tier2_Kegs.wav",    # 1 — the kegs
	"res://assets/music/trial/Trial_By_Fire_Tier3_Dragon.wav",  # 2 — the wyrm
]
const TRIAL_TIER_NAMES: Array[String] = ["fuse", "kegs", "dragon"]
const TRIAL_FADE := 0.9         ## tier-to-tier volume ramp, seconds
const TRIAL_OUT := 1.2          ## default fade when the trial ends

## Overridable before add_child() so tests never touch the real settings file.
var settings_path := SETTINGS_PATH_DEFAULT

var _decks: Array[AudioStreamPlayer] = []
var _live := 0                       # index into _decks of the audible deck
var _sting_player: AudioStreamPlayer
var _fanfare_player: AudioStreamPlayer

var _mode := ""                      # "" | "menu" | "game" | "over"
var _bag: Array[String] = []         # shuffle bag for the active playlist
var _last_track := ""                # avoids back-to-back repeats across bags
var _seq := 0                        # invalidates scheduled crossfades
var _fade_tween: Tween
var _duck_tween: Tween
var _duck_db := 0.0                  # 0.0 or DUCK_DB — playlist decks only

var _volume := DEFAULT_VOLUME        # 0-100
var _muted := false

# -- Trial by Fire layers (built on first use, freed when the trial ends) --
var _trial_players: Array[AudioStreamPlayer] = []
var _trial_tier := -1                # -1 = the trial is not playing
var _trial_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # music survives tree pause
	_load_settings()
	_ensure_bus()
	for i in 2:
		var deck := AudioStreamPlayer.new()
		deck.name = "Deck%d" % i
		deck.bus = BUS_NAME
		deck.volume_db = SILENCE_DB
		add_child(deck)
		_decks.append(deck)
	_sting_player = AudioStreamPlayer.new()
	_sting_player.name = "Sting"
	_sting_player.bus = BUS_NAME
	add_child(_sting_player)
	_fanfare_player = AudioStreamPlayer.new()
	_fanfare_player.name = "Fanfare"
	_fanfare_player.bus = BUS_NAME
	add_child(_fanfare_player)
	_apply_bus_state()


func _exit_tree() -> void:
	# Release AudioServer playbacks before engine teardown: a deck still
	# playing at quit leaks its AudioStreamPlaybackMP3 + AudioStreamMP3 pair
	# (ObjectDB warning on every boot log). Streams are also dropped so the
	# resource itself can be reclaimed.
	var was_playing := false
	for p in [_sting_player, _fanfare_player] + Array(_decks) + Array(_trial_players):
		if p != null and is_instance_valid(p):
			was_playing = was_playing or p.playing
			p.stop()
			p.stream = null
	if was_playing:
		# stop() only MARKS the playback for deletion; the audio thread frees
		# it on its next mix pass. Give it one beat, or exit wins the race.
		OS.delay_msec(120)


## ── Public API ─────────────────────────────────────────────────────────────

func play_menu() -> void:
	if _mode == "menu":
		return
	_start_playlist("menu", MENU_TRACKS)


func play_game() -> void:
	if _mode == "game":
		return
	_start_playlist("game", GAME_TRACKS)


## Fires a random duel stinger over whatever is playing (slow-mo start beat).
func sting_duel() -> void:
	var path: String = STING_TRACKS[randi() % STING_TRACKS.size()]
	_sting_player.stream = load(path)
	_sting_player.pitch_scale = 1.0   # fresh sting even if a cinematic reset was missed
	_sting_player.volume_db = 0.0
	_sting_player.play()


## Game end: playlist fades to silence, the verdict piece takes the hall.
func game_over(won: bool) -> void:
	_end_playlist()
	_play_fanfare(VICTORY_TRACK if won else DEFEAT_TRACK)


## Tournament won: the big brass — call INSTEAD of game_over on the final mate.
func championship() -> void:
	_end_playlist()
	_play_fanfare(CHAMPIONSHIP_TRACK)


## ── Trial by Fire ─────────────────────────────────────────────────────────
##
## Take the hall for the king-duel. The gameplay playlist fades out (the arena
## gets its own music, not a bed under it) and all three tiers start together;
## `tier` is which one is audible. Idempotent: calling it twice only moves the
## tier, so a retried trial cannot stack two sets of layers.
func play_trial(tier: int = 0) -> void:
	if not _trial_players.is_empty():
		trial_tier(tier)
		return
	_end_playlist()
	for i in TRIAL_TIERS.size():
		var stream := load(TRIAL_TIERS[i]) as AudioStream
		if stream == null:
			push_warning("MusicManager: could not load %s" % TRIAL_TIERS[i])
			_teardown_trial()
			return
		var p := AudioStreamPlayer.new()
		p.name = "Trial%d_%s" % [i + 1, TRIAL_TIER_NAMES[i]]
		p.bus = BUS_NAME
		p.stream = stream
		p.volume_db = SILENCE_DB
		add_child(p)
		_trial_players.append(p)
	# THE SAMPLE LOCK: every layer starts in this one frame, before any await.
	# Start them apart and the loops phase against each other for the rest of
	# the duel, which is the one failure a "layered" mix cannot survive.
	for p in _trial_players:
		p.play()
	_trial_tier = -1
	trial_tier(tier, 0.35)   # a short lift in, not a 0.9 s swell from silence


## Move the mix to `tier` (0 fuse · 1 kegs · 2 dragon). Only volumes move.
func trial_tier(tier: int, fade: float = TRIAL_FADE) -> void:
	if _trial_players.is_empty():
		return
	var want := clampi(tier, 0, _trial_players.size() - 1)
	if want == _trial_tier:
		return
	_trial_tier = want
	_kill_tween(_trial_tween)
	if is_inside_tree():
		_trial_tween = _make_tween().set_parallel(true)
		for i in _trial_players.size():
			_trial_tween.tween_property(_trial_players[i], "volume_db",
				0.0 if i == want else SILENCE_DB, fade)
	else:
		for i in _trial_players.size():
			_trial_players[i].volume_db = 0.0 if i == want else SILENCE_DB


## The trial is over: fade the layers out and release them. Safe to call when
## no trial is running, and safe to call twice.
func stop_trial(fade: float = TRIAL_OUT) -> void:
	if _trial_players.is_empty():
		return
	_trial_tier = -1
	_kill_tween(_trial_tween)
	if fade <= 0.0 or not is_inside_tree():
		_teardown_trial()
		return
	var doomed := _trial_players
	_trial_players = []
	_trial_tween = _make_tween().set_parallel(true)
	for p in doomed:
		_trial_tween.tween_property(p, "volume_db", SILENCE_DB, fade)
	_trial_tween.chain().tween_callback(func() -> void:
		for p in doomed:
			if is_instance_valid(p):
				p.stop()
				p.stream = null
				p.queue_free())


## -1 when no trial is playing; otherwise the audible tier.
func current_trial_tier() -> int:
	return _trial_tier


func trial_players() -> Array[AudioStreamPlayer]:
	return _trial_players


func _teardown_trial() -> void:
	_kill_tween(_trial_tween)
	for p in _trial_players:
		if is_instance_valid(p):
			p.stop()
			p.stream = null
			p.queue_free()
	_trial_players = []
	_trial_tier = -1


## Cinematic duck: playlist decks dip by DUCK_DB; stings/fanfares stay hot.
func duck() -> void:
	_set_duck(DUCK_DB)


func unduck() -> void:
	_set_duck(0.0)


## Fade everything out and stop. `fade` seconds, floor SILENCE_DB, then stop.
func stop_all(fade := 1.0) -> void:
	_seq += 1
	_mode = ""
	_bag.clear()
	_kill_tween(_fade_tween)
	_kill_tween(_duck_tween)
	_duck_db = 0.0
	# The trial's layers are owned separately (they are created and freed per
	# duel) — hand them their own teardown rather than leaving three looping
	# players behind a "stop everything" call.
	_teardown_trial()
	var players: Array[AudioStreamPlayer] = []
	players.append_array(_decks)
	players.append(_sting_player)
	players.append(_fanfare_player)
	if fade <= 0.0 or not is_inside_tree():
		for p in players:
			p.stop()
			p.volume_db = SILENCE_DB
		return
	_fade_tween = _make_tween().set_parallel(true)
	for p in players:
		if p.playing:
			_fade_tween.tween_property(p, "volume_db", SILENCE_DB, fade)
	_fade_tween.chain().tween_callback(func() -> void:
		for p in players:
			p.stop())


## ── Volume / mute (persisted) ──────────────────────────────────────────────

func set_volume(v: int) -> void:
	_volume = clampi(v, 0, 100)
	_apply_bus_state()
	_save_settings()


func get_volume() -> int:
	return _volume


func set_muted(m: bool) -> void:
	_muted = m
	_apply_bus_state()
	_save_settings()


func is_muted() -> bool:
	return _muted


func toggle_mute() -> void:
	set_muted(not _muted)


## Master volume slider position (0-100) → bus dB. 100 → 0 dB, 0 → floor.
static func volume_to_db(v: int) -> float:
	if v <= 0:
		return SILENCE_DB
	return maxf(linear_to_db(clampi(v, 0, 100) / 100.0), SILENCE_DB)


## M mutes/unmutes — handled inside the manager so game.gd stays untouched.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode != KEY_M or key.ctrl_pressed or key.meta_pressed or key.alt_pressed:
		return
	toggle_mute()
	get_viewport().set_input_as_handled()


## ── Introspection (used by tests and debug HUDs) ───────────────────────────

func current_mode() -> String:
	return _mode


func is_ducked() -> bool:
	return _duck_db != 0.0


## Full-level target (dB) the live playlist deck fades toward: 0 or DUCK_DB.
func playlist_level_db() -> float:
	return _duck_db


func live_deck() -> AudioStreamPlayer:
	return _decks[_live] if _decks.size() > 0 else null


func sting_player() -> AudioStreamPlayer:
	return _sting_player


func fanfare_player() -> AudioStreamPlayer:
	return _fanfare_player


## ── Playlist internals ─────────────────────────────────────────────────────

func _start_playlist(mode: String, tracks: Array[String]) -> void:
	_mode = mode
	_bag = tracks.duplicate()
	_bag.shuffle()
	_fanfare_out()
	_crossfade_to(_draw_from_bag(tracks), CROSSFADE)


func _draw_from_bag(tracks: Array[String]) -> String:
	if _bag.is_empty():
		_bag = tracks.duplicate()
		_bag.shuffle()
		# No immediate repeat across bag refills (only possible with 2+ tracks).
		if _bag.size() > 1 and _bag[0] == _last_track:
			_bag.push_back(_bag.pop_front())
	var path: String = _bag.pop_front()
	_last_track = path
	return path


func _crossfade_to(path: String, dur: float) -> void:
	_seq += 1
	var stream := load(path) as AudioStream
	if stream == null:
		push_warning("MusicManager: could not load %s" % path)
		return
	var incoming := _decks[1 - _live]
	var outgoing := _decks[_live]
	_live = 1 - _live
	incoming.stream = stream
	incoming.volume_db = SILENCE_DB
	incoming.play()
	_kill_tween(_fade_tween)
	if is_inside_tree():
		_fade_tween = _make_tween().set_parallel(true)
		_fade_tween.tween_property(incoming, "volume_db", _duck_db, dur)
		if outgoing.playing:
			_fade_tween.tween_property(outgoing, "volume_db", SILENCE_DB, dur)
			_fade_tween.chain().tween_callback(outgoing.stop)
	else:
		incoming.volume_db = _duck_db
		outgoing.stop()
	_schedule_next_track(stream, _seq)


## Wall-clock rotation: crossfade into the next draw CROSSFADE seconds before
## this track ends. Game tracks are ALSO import-looped (loop=true) as a net —
## if the timer is ever lost the hall never falls silent mid-siege.
func _schedule_next_track(stream: AudioStream, seq: int) -> void:
	if not is_inside_tree():
		return
	var wait := maxf(stream.get_length() - CROSSFADE, 1.0)
	var timer := get_tree().create_timer(wait, true, false, true)  # ignore_time_scale
	timer.timeout.connect(func() -> void:
		if seq != _seq or _mode not in ["menu", "game"]:
			return
		var tracks := MENU_TRACKS if _mode == "menu" else GAME_TRACKS
		_crossfade_to(_draw_from_bag(tracks), CROSSFADE))


func _end_playlist() -> void:
	_seq += 1
	_mode = "over"
	_bag.clear()
	_kill_tween(_fade_tween)
	if is_inside_tree():
		_fade_tween = _make_tween().set_parallel(true)
		for deck in _decks:
			if deck.playing:
				_fade_tween.tween_property(deck, "volume_db", SILENCE_DB, END_FADE)
		_fade_tween.chain().tween_callback(func() -> void:
			for deck in _decks:
				deck.stop())
	else:
		for deck in _decks:
			deck.stop()
			deck.volume_db = SILENCE_DB


func _play_fanfare(path: String) -> void:
	var stream := load(path) as AudioStream
	if stream == null:
		push_warning("MusicManager: could not load %s" % path)
		return
	_fanfare_player.stream = stream
	_fanfare_player.volume_db = SILENCE_DB
	_fanfare_player.play()
	if is_inside_tree():
		var t := _make_tween()
		t.tween_property(_fanfare_player, "volume_db", 0.0, 0.5)
	else:
		_fanfare_player.volume_db = 0.0


func _fanfare_out() -> void:
	if not _fanfare_player or not _fanfare_player.playing:
		return
	if is_inside_tree():
		var t := _make_tween()
		t.tween_property(_fanfare_player, "volume_db", SILENCE_DB, CROSSFADE)
		t.tween_callback(_fanfare_player.stop)
	else:
		_fanfare_player.stop()


func _set_duck(target_db: float) -> void:
	if is_equal_approx(_duck_db, target_db):
		return
	_duck_db = target_db
	_kill_tween(_duck_tween)
	var deck := live_deck()
	if deck == null:
		return
	if is_inside_tree() and deck.playing:
		_duck_tween = _make_tween()
		_duck_tween.tween_property(deck, "volume_db", _duck_db, DUCK_FADE)
	elif deck.playing:
		deck.volume_db = _duck_db


## ── Bus / settings internals ───────────────────────────────────────────────

func _ensure_bus() -> void:
	if AudioServer.get_bus_index(BUS_NAME) != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, BUS_NAME)
	AudioServer.set_bus_send(idx, "Master")


func _apply_bus_state() -> void:
	var idx := AudioServer.get_bus_index(BUS_NAME)
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, volume_to_db(_volume))
	AudioServer.set_bus_mute(idx, _muted)


func _load_settings() -> void:
	var data := _read_settings()
	_volume = clampi(int(data.get("music_volume", DEFAULT_VOLUME)), 0, 100)
	_muted = bool(data.get("music_muted", false))


## Read-merge-write: only OUR keys change; everything else in the file stays.
func _save_settings() -> void:
	var data := _read_settings()
	data["music_volume"] = _volume
	data["music_muted"] = _muted
	var f := FileAccess.open(settings_path, FileAccess.WRITE)
	if f == null:
		push_warning("MusicManager: cannot write %s (%s)"
				% [settings_path, error_string(FileAccess.get_open_error())])
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()


func _read_settings() -> Dictionary:
	if not FileAccess.file_exists(settings_path):
		return {}
	var f := FileAccess.open(settings_path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}


## ── Small helpers ──────────────────────────────────────────────────────────

func _make_tween() -> Tween:
	# Wall-clock tweens: fades must not crawl inside DuelDirector slow-mo.
	return create_tween().set_ignore_time_scale(true)


func _kill_tween(t: Tween) -> void:
	if t != null and t.is_valid():
		t.kill()
