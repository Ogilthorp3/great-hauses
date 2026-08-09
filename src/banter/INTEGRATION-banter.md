# Integrating the rival-haus banter module (`src/banter/`)

Status: the module is **complete and headless-tested** (93/93 checks,
`tests/test_banter.gd`) but **wired to nothing** — by design. This note is
the full wiring plan for whoever integrates it into `game.gd` / the HUD.
No scene changes are required anywhere: the module is pure code, built at
runtime like the rest of the HUD.

Files:

| File | Role |
|---|---|
| `src/banter/banter.gd` | `BanterEngine` (Node) — beats in, `banter_line` out |
| `src/banter/banter_lines.json` | 576 canned lines: 9 hauses x 8 beats x 8 |
| `tests/test_banter.gd` | headless suite (pools, personas, limiter, dedupe, LLM mock) |

## The 30-second version

```gdscript
# game.gd — members
const BanterScript := preload("res://src/banter/banter.gd")
var banter: BanterScript = null

# game.gd::_ready(), after _resolve_identity():
if not rival_house_id.is_empty() and HouseRegistry.has_house(rival_house_id):
    banter = BanterScript.new()
    banter.name = "Banter"
    banter.house_id = rival_house_id          # the rival speaks
    add_child(banter)                          # BEFORE the first beat (HTTP needs the tree)
    banter.banter_line.connect(_on_banter_line)
    banter.on_beat(BanterScript.BEAT_GAME_START)
```

Every call is fire-and-forget: `on_beat()` returns immediately; the line
arrives later on the `banter_line` signal (instantly for canned lines,
within ~8 s for LLM lines). **Never `await` a beat.**

## API surface

### Signals

```gdscript
signal banter_line(house_id: String, text: String, beat: String)
signal banter_skipped(beat: String, why: String)   # debug/e2e evidence only
```

- `banter_line` — render `text` in the HUD. `house_id` is the rival (useful
  for color/name), `beat` is which moment triggered it. Emitted
  synchronously from inside `on_beat()` when the canned pool answers, or
  asynchronously when the LLM answers — connect **before** the first beat.
- `banter_skipped(beat, why)` — `why` is one of `no_house`, `unknown_beat`,
  `inflight`, `rate_limited`, `pool_exhausted`. Nothing to render; counters
  `taunt_count` / `skip_count` are e2e evidence, same idea as
  `oracle_think_count`.

### Beats (all from the RIVAL's point of view)

| Constant | Fire when | Voice |
|---|---|---|
| `BEAT_GAME_START` | match begins | opening challenge |
| `BEAT_PLAYER_CAPTURED` | the rival captured a **player** piece | gloat |
| `BEAT_RIVAL_CAPTURED` | the player captured a **rival** piece | wounded pride |
| `BEAT_CHECK_GIVEN` | the rival checks the player's king | menace |
| `BEAT_CHECK_RECEIVED` | the player checks the rival's king | rattled defiance |
| `BEAT_PLAYER_BLUNDER` | eval swing says the player blundered | relish (always allowed) |
| `BEAT_ENDGAME_WIN` | the rival won | triumph |
| `BEAT_ENDGAME_LOSE` | the rival lost | bitter, proud concession |

### Context dictionary (`on_beat(beat, ctx)`)

- `"piece"` — lowercase piece name (`"pawn"`, `"rook"`, `"knight"`,
  `"bishop"`, `"queen"`) for the two capture beats. Unlocks the `{piece}`
  canned lines and names the piece in the LLM prompt. Omit it and the
  module still works (token lines are just skipped).
- `"eval_swing_cp"` — centipawns handed over by the blunder
  (`BEAT_PLAYER_BLUNDER`'s hook — the **caller** supplies the eval; the
  module never runs an engine).
- `"fullmove"` — explicit fullmove number; otherwise the module's own
  `note_ply()` clock is used.

### Rate limiting / dedupe (enforced inside the module — do not duplicate)

- Min **2 full moves** between taunts (`min_fullmove_gap`, tweakable).
- **One taunt in flight** at a time; overlapping beats are dropped
  (`inflight`). Consequence: if one move produces both a capture and a
  check, fire the capture beat first — it is the better line — and let the
  check beat be dropped.
- `BEAT_PLAYER_BLUNDER` and the bookends (`game_start`, `endgame_*`)
  bypass the move gap. Blunder taunts are the best ones; they always land.
- **No line repeats within a game** (canned templates and LLM lines both).
  A fully spent pool goes silent (`pool_exhausted`) rather than repeat.
- `reset_game()` clears everything. `game.gd` rematches via
  `reload_current_scene()`, which rebuilds the node anyway — only call
  `reset_game()` if you ever reuse one instance across matches.

## Wiring plan for game.gd (exact anchors)

### 1. Fullmove clock — `_execute_ply()`

Call `note_ply()` once per applied half-move, right after
`state.apply_move(move)`:

```gdscript
func _execute_ply(move) -> void:
    var mover_is_ember: bool = state.turn
    _record_san(move)
    state.apply_move(move)
    if banter != null:
        banter.note_ply()                      # <— the rate limiter's clock
    _refresh_turn_moves()
    await _animate_move(move, mover_is_ember)
    ...
```

### 2. Capture + check beats — `_execute_ply()`, after the animation

Fire **after** `await _animate_move(...)` so the banter caption does not
fight the DuelDirector's slow-mo kill-line caption (both are short reads;
sequential beats read better than simultaneous ones):

```gdscript
    await _animate_move(move, mover_is_ember)
    _fire_banter_beats(move, mover_is_ember)
    if state.get_result() != ChessState.RESULT.ONGOING:
        _finish_game()
```

```gdscript
const PIECE_NAME := {
    "p": "pawn", "r": "rook", "n": "knight", "b": "bishop", "q": "queen", "k": "king",
}

func _fire_banter_beats(move, mover_is_ember: bool) -> void:
    if banter == null or game_over:
        return
    var san: String = str(move.notation_san) if move.notation_san != null else ""
    if move.is_capture():
        var piece := str(PIECE_NAME.get(str(move.captured_piece).to_lower(), ""))
        var beat: String = BanterScript.BEAT_PLAYER_CAPTURED if mover_is_ember \
            else BanterScript.BEAT_RIVAL_CAPTURED
        banter.on_beat(beat, {"piece": piece})
        return   # capture outranks check; the engine would drop the 2nd anyway
    if san.ends_with("+"):
        var beat := BanterScript.BEAT_CHECK_GIVEN if mover_is_ember \
            else BanterScript.BEAT_CHECK_RECEIVED
        banter.on_beat(beat)
```

Notes:
- `mover_is_ember == true` means the RIVAL moved (same convention as
  `_duel_meta`). Rival captures player piece -> `player_captured` (gloat).
- SAN `"+"` suffix is the existing check signal in this codebase (`state`
  has no public `in_check()`); `"#"` (mate) is deliberately NOT a check
  beat — the endgame beats own it.
- `move.captured_piece` is the engine's piece char (`"r"`, `"N"`, ...);
  map through `PIECE_NAME` and pass lowercase.

### 3. Endgame beats — `_finish_game()`

```gdscript
func _finish_game() -> void:
    game_over = true
    ...
    var player_won := result == ChessState.RESULT.CHECKMATE and state.turn
    if banter != null:
        if result == ChessState.RESULT.CHECKMATE:
            banter.on_beat(BanterScript.BEAT_ENDGAME_LOSE if player_won \
                else BanterScript.BEAT_ENDGAME_WIN)
        # draws: no beat (no pools for draws — silence beats a wrong-register line)
```

Remember the perspective flip: the module speaks for the rival, so the
player winning fires `BEAT_ENDGAME_LOSE`.

### 4. The blunder hook — caller supplies the eval swing

The module deliberately has **no engine**; it taunts when told. Two ready
options, in order of preference:

a. **Stockfish sampling (best signal).** When `UciEngine.find_stockfish()`
   is non-empty, keep a shallow `UciEngine` (depth 8–10 is plenty) and
   around the **player's** ply compare evals from the player's
   perspective: `eval_before` (position before their move, them to move)
   vs `eval_after` (after their move, sign-flipped). If
   `eval_before - eval_after >= 150` cp:

   ```gdscript
   banter.on_beat(BanterScript.BEAT_PLAYER_BLUNDER,
       {"eval_swing_cp": eval_before - eval_after})
   ```

   Run it detached (fire a coroutine after `_execute_ply`); blunder beats
   are gap-exempt so late detection still lands. Reuse the search plumbing
   from `ds4_opponent.gd::_engine_search` / `_score_value`.

b. **Counseled/maester Oracle for free.** When `Session.opponent` runs the
   Oracle in counseled mode, `_counsel_review` already computes `delta` cp
   for the ORACLE's proposals — that is rival-blunder data, not player
   data, so do NOT reuse it for `player_blunder`. It is listed here only
   so nobody wires it in backwards. For player blunders use (a), or skip
   the beat entirely — the module is fully functional without it.

Threshold suggestion: 150 cp (matches `COUNSEL_CP_THRESHOLD`); consider
300+ cp = "always taunt", 150–300 = taunt only if the RNG feels like it,
to keep blunder taunts special.

### 5. HUD rendering — `_build_hud()` + handler

Recommended: a bottom-LEFT caption label, mirroring `_oracle_caption`
(bottom-right) so the two voices never overlap, tinted with the rival's
heraldic color:

```gdscript
var _banter_caption: Label    # member

# in _build_hud(), after _oracle_caption:
_banter_caption = Label.new()
_banter_caption.name = "BanterCaption"
_banter_caption.visible = false
_banter_caption.add_theme_font_size_override("font_size", 14)
_banter_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
_banter_caption.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
_banter_caption.offset_left = 16
_banter_caption.offset_top = -64
_banter_caption.offset_right = 420
_banter_caption.offset_bottom = -10
hud.add_child(_banter_caption)

func _on_banter_line(house_id: String, text: String, _beat: String) -> void:
    if _banter_caption == null:
        return
    var accent: Color = HouseRegistry.get_colors(house_id)["accent"]
    _banter_caption.add_theme_color_override("font_color", accent)
    _banter_caption.text = "%s: “%s”" % [_house_name(house_id), text]
    _banter_caption.visible = true
    get_tree().create_timer(6.0).timeout.connect(func() -> void:
        if is_instance_valid(_banter_caption) \
                and _banter_caption.text.ends_with("“%s”" % text):
            _banter_caption.visible = false)
```

(The show-for-6s + only-hide-if-unchanged pattern is copied from
`_on_oracle_reason` — same reasoning.)

Cinematic etiquette: beats are fired after `_animate_move`'s await, so
capture banter appears as the duel resolves. If you would rather hard-gate
it, check `duel_director.is_active()` in `_on_banter_line` and hold the
line in a 1-deep queue until the director releases.

### 6. Endpoint / config

- LLM endpoint resolution is **identical to the Oracle's**
  (`ds4_opponent.gd`): env `DS4_CHESS_URL` > `endpoint_override` property >
  `http://127.0.0.1:18000/v1/chat/completions`. Model: env
  `DS4_CHESS_MODEL` > `model` property > `deepseek-v4-flash`. One tunnel
  serves both features.
- `temperature 0.9`, `max_tokens 60`, `llm_timeout_s 8.0` — after the
  timeout (or any transport/parse error, or an empty/duplicate reply) the
  canned pool answers instead. The game never notices the difference.
- Offline/no-tunnel play needs **zero configuration** — the failed request
  eats up to 8 s in the background (gameplay never waits on it) and the
  canned line still arrives. For a snappier offline feel, or a user
  setting ("Rival banter: canned only"), set `llm_enabled = false` —
  canned lines then arrive instantly and synchronously. Optional polish:
  reuse the Oracle's `ping()` result from haus select — if the Oracle is
  offline, set `banter.llm_enabled = false` too.
- Legacy Frost/Ember skin (`player_house_id == ""`): skip creating the
  engine entirely (the guard in the 30-second version does this). The
  registry hauses are the only voices.

### 7. Do / don't

- DO connect `banter_line` before the first `on_beat` (pool lines emit
  synchronously).
- DO pass `"piece"` on capture beats — the best canned lines use it.
- DON'T `await` `on_beat()`; it is not a coroutine from the caller's side.
- DON'T autoload BanterEngine; it is a per-match child of the game scene.
- DON'T call `on_beat` for draws or stalemates; there are no draw pools.
- DON'T add a second rate limiter in game.gd — skip logic lives in the
  module and `banter_skipped` tells you why a beat went silent.
- DON'T edit `banter_lines.json` casually: every haus x beat must keep
  >= 8 lines, <= 90 chars (after `{piece}` substitution), unique within
  the haus, `{piece}` the only token — `tests/test_banter.gd` enforces
  all of it.

## e2e suggestions (for whoever owns test_e2e/)

- `banter.taunt_count >= 1` after a scripted capture exchange, and
  `banter.last_beat`/`last_source` as evidence, mirroring how
  `oracle_think_count`/`oracle_stumble_count` are asserted today.
- A `--e2e-fen` position one move from mate: assert the endgame beat fires
  and the HUD caption node becomes visible.
- Keep `DS4_CHESS_URL` pointed at a dead port in e2e (the fallback path is
  deterministic and offline-green; the LLM path is already covered by the
  mock server in `tests/test_banter.gd`).

## Test commands

```bash
# module suite (offline-green, includes an in-process mock LLM server)
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s res://tests/test_banter.gd

# boot must stay script-error-free
/Applications/Godot.app/Contents/MacOS/Godot --headless --quit --path .
```

Both were green at module hand-off (93/93 checks; engine suite 79/79
untouched).
