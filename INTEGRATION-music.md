# MUSIC module — integration notes

Module status: **built, imported, 104/104 headless tests green, zero project
files modified.** Everything below is the integrator's wiring — the module
itself never touches `game.gd`, `game.tscn`, `project.godot`, `main.tscn`,
or `test_e2e/`.

## What shipped

| Path | What |
|------|------|
| `src/audio/music_manager.gd` | `MusicManager` (Node) — playlists, crossfades, stings, fanfares, duck, volume/mute persistence, M-key mute |
| `src/audio/credits.gd` | `MusicCredits` — static attribution text (CC BY display duty) |
| `tests/test_music.gd` | headless suite (104 checks) — run: `Godot --headless --path . -s res://tests/test_music.gd` |
| `assets/music/**` | 10 licensed tracks + per-file `.license.txt` + `CREDITS.md` + `licenses/` (~39 MB, ≤45 MB budget) |

## 1. Autoload registration (the ONE project.godot line)

```ini
[autoload]
Music="*res://src/audio/music_manager.gd"
```

Name it **`Music`**, not `MusicManager` — an autoload sharing its script's
`class_name` hides the global class (same reason `PieceAssets`'s script has
no class_name). Place it before `E2EDriver` so the driver can reference it.
After registering, re-run `./test_e2e/run_e2e.sh preflight` — the autoload
adds four `AudioStreamPlayer`s at boot and must stay script-error clean.

## 2. The six call points

### 1) `Music.play_menu()` — menu playlist (shuffle, 2 s crossfade)
`src/main.gd` → `_ready()`, right after `add_child(_select)`. The probe-flag
branch (`--smoke` etc.) returns before this line, so CI boots stay silent.
Returning to the Hall of Banners re-enters `main._ready()` → menu music
resumes for free. `play_menu()` is idempotent.

### 2) `Music.play_game()` — gameplay playlist (shuffle, crossfade, ducking)
`src/game.gd` → `_ready()` (line ~75), e.g. right after `_dress_hall()`.
Idempotent; crossfades out whatever the menu left playing.

### 3) `Music.sting_duel()` + 4) `Music.duck()` / `Music.unduck()`
Wire the DuelDirector's own signals in `src/game.gd` → `_ready()`, next to
the existing `duel_director.victory_panel_requested.connect(...)` (~line 89):

```gdscript
duel_director.cinematic_started.connect(func(kind: String) -> void:
	Music.duck()
	if kind == "duel":
		Music.sting_duel())
duel_director.cinematic_finished.connect(func(_kind: String) -> void:
	Music.unduck())
```

`cinematic_started` kinds are `"duel"`, `"promotion"`, `"checkmate"`,
`"championship"` — all four duck the playlist by −8 dB (stings/fanfares are
NOT ducked, they ride on top); only `"duel"` also fires a random stinger at
the slow-mo start. `unduck()` on `cinematic_finished` restores 0 dB.

Note: DuelDirector's `_audio_capture()` pitch-bends every AudioStreamPlayer
it finds during slow-mo — the music (and a mid-duel sting) dropping in pitch
with `Engine.time_scale` is by design, and the manager's own fades/rotation
run on ignore-time-scale tweens/timers so they never crawl during slow-mo.

### 5) `Music.game_over(won)` / `Music.championship()` — the verdict pieces
`src/game.gd` → `_show_match_end(player_won, base_text)` (~line 468) is the
single spot where win/loss AND the champion branch are both known. At its
top:

```gdscript
var champ := Session.configured and Session.mode == "tournament" \
		and Session.tournament != null and Session.tournament.is_champion()
if champ:
	Music.championship()   # Fanfare for Space — the throne is won
else:
	Music.game_over(player_won)  # Medieval Victory Theme / Agnus Dei X
```

(Alternative: `Music.game_over(player_won)` in `_finish_game()` and
`Music.championship()` beside `start_championship_tableau()` — works, but
the fanfare would restart when the championship branch fires; the
`_show_match_end` single point is cleaner.) Playlists fade out (1.5 s) under
the fanfare automatically.

### 6) `MusicCredits` — the CC-BY attribution (REQUIRED, not cosmetic)
`src/ui/house_select.gd` → `_build_footer()` (~line 528): the existing
`_footer` label is rewritten per phase, so add a second dim label beside it:

```gdscript
var credits := Label.new()
credits.name = "MusicCredits"
credits.text = MusicCredits.get_credits_short()   # one line
credits.add_theme_font_size_override("font_size", 11)
credits.add_theme_color_override("font_color", TEXT_DIM)
credits.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
add_child(credits)
```

`MusicCredits.get_credits_text()` is the full multi-line block for a proper
credits screen later. CC BY 4.0 tracks (7 of 10, Kevin MacLeod + the
Orchestral Stinger) legally require this display.

## Extra API (no wiring needed)

- **M key** mutes/unmutes — handled inside the manager via
  `_unhandled_key_input` (plain M only; Cmd/Ctrl/Alt+M ignored).
- `Music.set_volume(0..100)` / `get_volume()` — for a future settings pane;
  default 70; maps to dB on a runtime-created `Music` bus.
- Volume + mute persist to `user://settings.json` — read-merge-write, other
  keys in the file are never clobbered.
- `Music.stop_all(fade := 1.0)` — fade everything to the −60 dB floor and
  stop (scene teardown, cutscenes).

## Import flags (documented per spec)

- The three `assets/music/game/*.mp3.import` files carry `loop=true` under
  `[params]` (baked into `.godot/imported/*.mp3str` at import — verified by
  test rows "loop=true baked"). Rationale: if playlist rotation is ever
  lost, the hall never falls silent mid-siege; normal rotation crossfades
  2 s before track end so the loop point is never heard.
- Menu, stings, fanfare, defeat: `loop=false` (one-shots / rotation only).
- Both `--import` passes exited 0 (the exit-code scar) and
  `test_e2e/run_e2e.sh preflight` passes with the audio in the tree
  (31 imported scenes, headless boot clean).

## Track map

| Slot | Track(s) |
|------|----------|
| Menu (shuffle) | Teller of the Tales · Minstrel Guild |
| Gameplay (shuffle, loop, duckable) | Achaidh Cheide · Lord of the Land · Skye Cuillin |
| Duel stings (random pick) | Orchestral Stinger – Dramatic Entrance · Dark Stinger 1 |
| Victory | Medieval: Victory Theme |
| Defeat | Agnus Dei X |
| Championship | Fanfare for Space |
