# The VFX Moment System — Design

**Date:** 2026-08-10
**Status:** Approved for planning
**Sits on:** `docs/superpowers/specs/2026-08-10-great-hauses-visionos-design.md` (the immersive port)
**Position in the sequence:** **Plan 4/5 work.** It sits on top of the duel director, after the
camera inversion of that spec's §5.2. The *policy* layer specified here is deliberately built
first, because it is pure logic and it is testable today on macOS, with no shader, no headset
and no rendered frame.

Every claim below cites a file:line. Claims that could not be reproduced from disk are marked
as unknowns in §10 rather than asserted. Where the three area designs that fed this spec
disagreed, one was chosen and the reason is stated inline.

---

## 1. The problem

A capture in Great Hauses looks up its choreography in a constant dictionary:
`KILL_STYLES` (`src/board/piece_view.gd:120-127`) maps each of the six `Type` values
(`:62`) to exactly one of six style strings, and `play_capture` (`:559`) reads it at `:561`
with no other input. Six pieces, six kills, forever. `KILL_VARIANTS := 3` (`:129`) buys three
approach/timing shuffles per style — picked at `:562-563` by a bare, unseeded
`randi() % KILL_VARIANTS` — but a variant is a speed and a lean, not a different event. The
only thing that genuinely varies is the **caption**: `pick_kill_line` (`src/cinematics/duel_director.gd:331`)
filters a weighted JSON pool (`src/cinematics/kill_lines.json`), prefers a piece-pinned entry
65 % of the time (`:344-345`) and draws at random. So the player learns the whole vocabulary in
about four captures: *knight ⇒ charge, queen ⇒ arrow, rook ⇒ grind*, with a rotating line of
text on top. Nothing is ever withheld, so nothing can ever arrive. The owner's brief — *"I just
want the special effects to be specials and that they surprise you from time to time, they
alternate depending of the situation in the game"* — names three properties, and the current
system has none of them. **Special** means most captures must stay ordinary, or nothing is
special by contrast. **Surprising** means the player cannot predict which capture will be big
*or which big thing they will get* — two independent axes, both of which must move.
**Situational** means the big moment is *earned* by what actually happened on the board: what
the capture cost, what history it settled, how good the move was, how improbable it was.

---

## 2. Decision — three tiers, three units

**Three tiers**, as chosen by the owner:

| Tier | What it is | Rate | Implementation |
|---|---|---|---|
| **0** | Today's kill, untouched | ~3 in 4 | `KILL_STYLES` + `KILL_VARIANTS` exactly as shipped |
| **1** | A modest flourish *around* the shipped kill | ~1 in 4 | catalogue entry, beats added around the strike |
| **2** | The showstopper | ~1 in 15 | catalogue entry, deeper beats + time dilation |

**Three units**, all `RefCounted`, all pure, none of them touching a `Node`, an autoload or the
rendering server — the idiom `src/minigame/blast_grid.gd:1` and `src/minigame/king_ai.gd`
established and that `tests/test_minigame.gd:5-9` exists to exercise ("*RefCounted state
machines ticked with a float, with no Node, no autoload and no rendering server anywhere in
them*").

| Unit | File (new) | Contract |
|---|---|---|
| **Context** | `src/cinematics/moment_context.gd` + `src/cinematics/capture_ledger.gd` | `situation(state, move, turn_moves, ledger, victim_rec) -> Dictionary` — the board's facts about one capture |
| **Score** | `src/cinematics/moment_score.gd` | `score(sit) -> {notability: float, lead: String, tag: String}` — four scorers folded into one number |
| **Governor** | `src/cinematics/moment_governor.gd` | `decide(notability, candidates) -> {tier, variant, …}` — pacing, novelty, determinism |

Everything downstream of the governor — the catalogue's beats, the shaders, the stage that
plays them — is **Plan 5** and is scoped but not built here (§7, §11).

**Why the policy layer first, deliberately.** All three units are pure functions over
dictionaries. `ChessState` (`src/chess/ChessState.gd:1-2`) and `ChessAI` (`src/chess/ChessAI.gd:1-2`)
are themselves `RefCounted`, and `ChessAI.choose_move_sync` (`:169`) is synchronous, so a
headless `-s` script can play forty complete AI-vs-AI games and score every capture in one run.
That means the owner's "1 in 4" and "1 in 15" can be *measured* before a single shader exists —
and if the pacing feels wrong, it is a constant that moves, not an art rewrite. The third area
design reached the same conclusion in its own closing risk: *"Shipping the pure half first…
would prove the 1-in-4 / 1-in-15 feel on real games before a single shader is written."*

---

## 3. The seam

### 3.1 Where the facts are gathered

`_execute_ply` (`src/game.gd:897`) is the single funnel for **every** ply — the player's, the
AI's (`_ai_ply`, `:879`), the Oracle's, and the network's (`_on_net_move_applied`, `:749`).
One hook covers all four. It already does exactly what the context needs, in exactly the right
order:

```
game.gd:902   state.apply_move(move)        # board is now POST-capture
game.gd:906   _refresh_turn_moves()         # _turn_moves = the DEFENDER's legal replies
game.gd:907   await _animate_move(move, …)  # → play_duel at game.gd:973
```

So at duel time `state.turn` (`ChessState.gd:87`) is the **victim's** side, `state.in_check()`
(`:635`) therefore means *this capture gave check*, and `_turn_moves` (`game.gd:129`, filled by
`state.legal_moves(true)` at `:999`) is the defender's complete, **pin-aware** legal reply list —
already computed and already paid for. Three of the most valuable signals in §4 are free.

The gather goes **between `:906` and `:907`**, and the result rides the `meta` dictionary
`_duel_meta` (`:939`) already builds and `play_duel` (`:973`) already accepts.

### 3.2 Where the verdict is consumed

`duel_director.gd:4` states the director's contract verbatim: *"Pure presentation: it never
touches game state."* Nothing in this design violates it. The director learns nothing about
moments; `game.gd` reads the verdict out of the governor and hands the resulting beats to the
stage, which wraps the strike callable that `game.gd:974` already passes
(`func(): await mover.play_capture(victim)`). **The stage always calls the strike it was
handed.** A moment can therefore never break a kill, never break the `death_style` contract
(`piece_view.gd:343`) that `_impact_shake` (`duel_director.gd:474-481`) duck-reads to find the
instant of the blow, and never change board state.

### 3.3 What is deliberately not hooked

**Checkmating captures are excluded from the moment system entirely.** `play_checkmate`
(`duel_director.gd:227`) is a separate, longer cinematic that already *is* the showstopper; a
tier-2 duel immediately followed by the checkmate sequence is two showstoppers back to back.
The first area design raised this as an open question; it is closed here by exclusion. If
`replies == 0 and gives_check`, the governor is not consulted and tier 0 plays.

---

## 4. The situational context

`moment_context.gd` is pure: `(state, move, turn_moves, ledger, victim_rec) -> Dictionary`.
Cost class: **free** = already computed elsewhere, **O(1)** = a handful of array reads,
**O(64)** = one board sweep. Everything below is computed once per capture, on a frame that is
about to spend several seconds playing a cinematic.

### 4.1 Identity and value

| key | source | cost |
|---|---|---|
| `ply` | `state.move_stack.size()` (`ChessState.gd:93`), post-apply | free |
| `a_char` | `move.piece` (`ChessMove.gd:25`) | free |
| `v_char` | `move.captured_piece` (`ChessMove.gd:17`) — **null for en passant**, fall back to the ledger's record | free |
| `a_white` | `not ChessState.piece_color(a_char)` (`:73` — lowercase is black) | free |
| `av`, `vv` | `VALUE[char.to_lower()]` = `{p:100, n:320, b:330, r:500, q:900}` — **verbatim** `ChessAI.get_piece_value` (`ChessAI.gd:205-219`) | free |

`ChessAI.get_piece_value` returns `0` for a king (`:207-208` falls through to `:219`). The
context therefore never asks it for one; king captures are flagged, not valued.

### 4.2 Material and phase — one O(64) sweep

One pass over `state.pieces` (`ChessState.gd:77`) produces `mat_w`, `mat_b` (kings excluded),
and `type_left` (piece char → count). From those, `O(1)`:

- `phase` = `clampf((mat_w + mat_b) / 8000.0, 0, 1)` — 8000 is both full armies minus kings.
- `mat_diff` signed to the attacker; `mat_diff_before` = `mat_diff + vv` (only two pieces
  changed this ply, so no second sweep is needed); `lead_flip` = the sign crossed zero.
- `victim_type_left` = `type_left.get(v_char, 0)` — **zero means this was the last one**.

### 4.3 Threat — three signals for free

| key | source | cost |
|---|---|---|
| `gives_check` | `state.in_check()` (`ChessState.gd:635`), post-apply | O(1) |
| `replies` | `turn_moves.size()` | **free** |
| `recapture_min` | `min(VALUE[m.piece])` over `m in turn_moves where m.to_square == move.to_square`; `-1` if none | **free** |
| `recapturable` | `recapture_min >= 0` | **free** |
| `exch` | `vv - (av if recapturable else 0)` | O(1) |
| `dist` | Chebyshev over `square_get_file`/`square_get_rank` (`ChessState.gd:44,48`) | O(1) |

**`recapturable` is derived from the legal move list, never from `is_square_attacked`
(`ChessState.gd:558`) — and this is a rule, not an optimisation.** `is_square_attacked` reports
a defender that may be **pinned and unable to legally move**. Two of the three area designs
independently flagged the same consequence: an effect that points at a piece which cannot
recapture is an effect that *lies about the position*, which is worse than no effect. The legal
list is both correct and free. Anyone "optimising" this back to `is_square_attacked`
reintroduces the defect.

**`exch` is a one-ply heuristic, deliberately.** It is `ChessAI`'s own capture ordering
heuristic (`ChessAI.gd:320-321`: `bonus += get_piece_value(move.captured_piece) -
get_piece_value(moving_piece)`) with the refinement that the attacker's value is only subtracted
when a *legal* recapture exists. `PxP` defended → `0`. `QxP` recapturable → `-800` (a sacrifice).
`NxQ` recapturable → `+580` (a steal). A deeper static exchange evaluation was proposed by one
design and is **rejected**: a truncated multi-ply stand-pat grades a routine defended pawn trade
as a win, and the accurate version is ~30 lines of new code feeding a number that is then
squashed into one of three tiers.

### 4.4 Special-move flags — all free from `ChessMove`

`en_passant` (`ChessMove.gd:18`), `promotes` (`move.promotion != null`, `:15`),
`underpromotion`, `a_is_king`, `a_is_pawn`, `v_is_queen`. Also `is_castling` and
`captured_square` (`:27-30`), the latter being correct for en passant where `to_square` is not.

### 4.5 The ledger — the only new state

`ChessState` knows the position. It does not know that *this* knight is the one that took your
queen on move 14, and that fact is the entire STORY scorer. `capture_ledger.gd` records it from
move data only — no `Node`, no `PieceView` — so it runs headless:

```
record  = {uid, char, born_ply, moves, kills, victims:[{char, ply, uid}]}
ledger  = {plies, captures:[…], _at: square -> record, _undo: […]}
```

`note_move(move)` is called after `state.apply_move` and returns the retired victim's record.
It handles promotion by rewriting `char` **without resetting `born_ply`** (a pawn that marched
the whole board and then killed something has exactly the story worth telling) and moves the
rook's record on castling.

Reset points already exist: `reset_from(state)` beside `_spawn_from_state` (`game.gd:519`),
and `rewind_to(state.move_stack.size())` inside `_perform_undo` (`game.gd:1062`), next to the
`_refresh_turn_moves()` that path already performs.

**En passant is why the ledger earns its keep on day one:** `move.captured_piece` is `null` for
e.p. (`ChessMove.gd:17` says so in the comment), so the ledger's record is the only place the
victim's actual char survives.

Derived, all free or O(kills): `v_age` (plies since `born_ply`), `v_moves` (0 = it never left
its birth square), `v_kills`, `revenge_char`/`revenge_gap` (the attacker's most valuable piece
this victim killed, and how long ago), `a_kills_before`, `streak` (consecutive trailing captures
by the attacker's colour), `first_blood`.

### 4.6 Cut from the context, with reasons

- **Discovered and double check.** The first area design proposed detecting them by writing
  `null` into `state.pieces[move.to_square]`, re-asking `is_square_attacked`, and restoring two
  statements later. It is the most cinematic pair of events in chess and it is **cut for v1**:
  it mutates the authoritative board for a cosmetic signal, and `ChessAI.choose_move` already
  runs a search on `WorkerThreadPool` (`ChessAI.gd:146,152`). It searches a *duplicate* today,
  so there is no live race today — but a signal that is only safe by accident of a neighbour's
  current implementation is not safe. It can return as a pure function over `state.duplicate()`
  (`ChessState.gd:99`) if playtest asks for it, paying the copy.
- **A Stockfish evaluation of the move.** `game.gd:912` already runs `_sample_blunder`
  detached, and it would be the best possible SKILL signal. It cannot be used: it is `await`-based
  across process frames, and `play_duel` fires on the same frame at `game.gd:973`, so the tier
  must be known *before* the first frame of the cinematic. Blocking on it stalls the board on
  every capture. `exch` + `replies` + `gives_check` are synchronous and sufficient.
- **`state.get_result()`.** `_execute_ply` already pays for it once at `game.gd:913`, and it is
  expensive: `ChessState.gd:717` regenerates the full legal move list, then `:848`
  `is_threefold_repetition` → `is_nfold_repetition` duplicates the board and unwinds the whole
  move stack. The context never calls it. Mate and stalemate come from `replies == 0` paired
  with `in_check()`, for free.
- **`notate_moves` / SAN parsing.** `ChessState.gd:892` plays and undoes every legal move to
  place `+`/`#`. Already paid once at `game.gd:999`. And **never parse check out of SAN** —
  `move.notation_san` is `null` on the `generate_legal_moves(false)` path, which is why
  `game.gd:914` falls back to UCI. Ask the engine.

---

## 5. The four scorers

`moment_score.gd`, all `static`, uniform signature `f(sit) -> {score: float, tag: String}`,
folded by `score(sit) -> {notability: float, lead: String, tag: String}`.

**All four are deterministic.** The surprise the owner asked for comes from the governor's gate
and its pacing, not from noise here. A deterministic scorer is the only kind that can be tested
against a distribution, and it is what makes two networked peers agree without a wire change
(§6.4).

### 5.1 STAKES — what the capture costs

```
v    = vv / 900.0                       # pawn .11 · N .36 · B .37 · R .56 · Q 1.0
amp  = 1.0 + 0.6 * (1.0 - phase)        # a rook in a bare endgame counts 1.48x
s    = v * amp
  + 0.25 if victim_type_left == 0 and vv >= 320   # the LAST knight
  + 0.10 if victim_type_left == 0                 # ...is not the last pawn
  + 0.30 if lead_flip
return clampf(s, 0.0, 0.85)             # THE CEILING IS LOAD-BEARING
```

**The 0.85 ceiling is doing real work.** STAKES is the *dense* signal — every capture has a
victim value — so without a clamp, `v * amp` exceeds 1.0 for any queen taken below `phase 0.4`,
and "showstopper" degenerates into "whenever a queen dies". If someone later removes it because
it looks arbitrary, the tier-2 rate roughly doubles and the feature reverts to the thing the
owner complained about.

Tags, first match: `lead_flip` · `last_queen` · `last_of_kind` · `bare_board` (`phase < 0.35`) ·
`queen` · `rook` · `minor` · `pawn`.

### 5.2 STORY — grudges and streaks

A rule table. Take the **max** matched score, add `0.15` per *additional* matched rule (this is
where "he took your knight AND he is on a three-kill run" compounds), clamp to 1.0.

| tag | condition | score |
|---|---|---|
| `revenge_kin` | `revenge_char != "" and same piece type as attacker` | 0.80 |
| `nemesis` | `v_kills >= 3` | 0.78 |
| `revenge_named` | `revenge_char != "" and VALUE[revenge_char] >= 320` | 0.75 |
| `streak` | `streak >= 3` | 0.70 |
| `veteran` | `v_age >= 40` (twenty full moves) | 0.65 |
| `butcher` | `a_kills_before >= 2` | 0.58 |
| `revenge_any` | `revenge_char != ""` | 0.52 |
| `statue` | `v_moves == 0 and ply >= 40` | 0.50 |
| `first_blood` | `first_blood` | 0.45 |

### 5.3 SKILL — when the move was good

```
base = 0.75 if exch >= 500            # a rook or better, for nothing
     | 0.60 if exch >= 300            # a minor, for nothing
     | 0.45 if exch >= 100            # won a pawn, or traded up
     | 0.15 if exch >= 0              # the even trade — the ordinary capture
     | (0.90 if replies <= 3 else 0.70 if gives_check else 0.05)   # the sacrifice
base += 0.15 if gives_check
base += 0.15 if replies <= 2          # the noose
base += 0.05 if en_passant            # you have to see it to play it
return clampf(base, 0.0, 1.0)
```

The sacrifice branch is the point: **giving material away is skill only if something comes
back.** With a check or a near-forced reply it scores 0.70–0.90; without either it scores 0.05,
because that is a blunder and it is not a brilliancy. This branch will occasionally be wrong in
both directions — a positional sacrifice with no immediate tactic scores as a blunder — and no
cheap synchronous fix exists (§4.6). It is the accepted cost of not waiting on Stockfish.

Tags: `sacrifice` · `theft` · `noose` · `clean` · `even`.

### 5.4 RARITY — the improbable

**Max** of the matched rules, never summed: a rare thing is rare once.

| tag | condition | score |
|---|---|---|
| `underpromotion` | `promotes and underpromotion` | 1.00 |
| `en_passant` | `en_passant` | 0.90 |
| `promo_capture` | `promotes` | 0.85 |
| `pawn_takes_queen` | `a_is_pawn and v_is_queen` | 0.80 |
| `king_kills` | `a_is_king` | 0.65 |
| `long_shot` | `dist >= 6 and a_char in "qQbBrR"` | 0.55 |
| `queen_hunt` | `v_is_queen and av <= 500` | 0.50 |
| `queen_trade` | `v_is_queen` | 0.35 |

The rates implied by these scores are estimated from general chess experience, **not** measured
against this game's own AI (§10.4). The self-play calibration run in §9 produces the real
per-tag frequencies and the numbers get one pass against them.

### 5.5 The fold

```
W    = {stakes: 0.75, story: 0.85, skill: 1.00, rarity: 0.95}
lead = argmax_k (W[k] * parts[k].score)
notability = clampf(lead_w + 0.30 * mean(the other three weighted), 0.0, 1.0)
```

**Max-plus-support, not a weighted sum.** A sum requires three mediocre reasons to equal one
great one — which is precisely the failure the owner described, because nothing is ever allowed
to be decisive on its own. A queen sacrifice is a showstopper *by itself*; it must not need the
victim to also carry a grudge. The strongest reason sets the level and the others add 30 % of
their average. The fold also yields an `argmax`, which is the diagnostic that makes a
bad-feeling game falsifiable (§9.6, §10.1).

Weights: SKILL and RARITY get near-full authority because they are **sparse** — they sit at
zero on an ordinary capture, so they cannot inflate the base rate, and they are exactly the two
things the owner named. STAKES is discounted to 0.75 *and* clamped because it is dense. STORY
sits between, and is the one most likely to be wrong after an undo or a mid-game FEN load,
because it is the only scorer whose inputs are ledger-derived.

### 5.6 The scorer→governor contract

**`notability` is one float in `[0,1]`, aimed at roughly uniform over the captures of a
game.** This is the single most important interface decision in the document, and it was
contested: one design had the scorer return a rich verdict dictionary the picker interprets,
another had it emit integer "heat points" the picker thresholds. **The float wins**, because
the governor's whole job is a *rate*, and a rate can only be calibrated against a distribution.
If the governor read raw semantics — centipawns, piece values, streak counters — then every
future re-tune of the scorer would silently move the owner's 1-in-4 and 1-in-15, and no test
could tell you it had happened.

`lead` and `tag` ride along as **metadata**, never consumed by the tier arithmetic: they are
what a catalogue entry pins against (`requires: ["lead:rarity"]`) and what a playtest log
prints. `reason` **template strings were cut from both designs that proposed them** —
`kill_lines.json` is already the caption authoring surface (`duel_director.gd:331`,
`format_line` at `:353`), and a second one is scope the owner did not ask for.

---

## 6. The governor

`moment_governor.gd`, `RefCounted`, no `Node`, no `Time`, no `Engine`, no frames.

```gdscript
func decide(notability: float, candidates: Dictionary) -> Dictionary
# candidates := {1: [{id, weight}, …], 2: [{id, weight}, …]}, ALREADY FILTERED
#               for applicability by the caller
# returns     {tier, variant, reason, notability, relative, index, novelty}
```

`candidates` arrives pre-filtered. The governor never inspects piece types: **applicability is
the catalogue's job, novelty is the governor's**. That split is what lets the tier sequence be
pinned in a test that knows nothing about VFX (§9.11), which in turn is what stops every art
commit from re-baselining the pacing tests.

`reason` (`quiet`/`merit`/`forced`/`starved`) and `novelty`
(`unseen`/`decayed`/`unblocked`/`exhausted`) cost nothing and answer the only question a
playtest ever asks — *why did that fire?*

### 6.1 Why not a fixed threshold

A fixed threshold on the score gives the owner's rates for exactly one score distribution. A
quiet endgame never crosses it; a bloodbath crosses it every capture. Worse, it makes tier 2
*predictable* — the player learns "queen takes queen = big one" and the surprise is dead on the
second occurrence. A pure random draw fixes predictability but permits two showstoppers back to
back and permits a whole game with none, both of which the owner ruled out by asking for tiers
*with rates*. One area design proposed fixed thresholds (`t1 = 0.42`, `t2 = 0.72`); it is
**rejected** in favour of the reservoir below, on the strength of the drift argument in §5.6 —
the scorer is a sibling unit that will churn, and a threshold governor's rates move silently
when it does.

### 6.2 The mechanism — a reservoir grants permission, a merit gate spends it

Two accumulators, one per tier. Every capture adds its notability to both. When a reservoir
crosses its threshold the tier becomes **available** — that is *permission*, not a firing. The
merit gate then decides whether *this particular capture* is worth spending it on.

That split is the whole design. The **reservoir** owns pacing: after a fire it drains, so the
next one must be re-earned, and cooldown and pity are largely emergent rather than bolted on.
The **merit gate** owns surprise and desert: an available governor can pass on capture N and take
N+2, and it strongly prefers the better capture.

```
mean  = (PRIOR_W * PRIOR_MEAN + sum_notability) / (PRIOR_W + n)   # this game's own scale
scale = clampf(mean / PRIOR_MEAN, SCALE_LO, SCALE_HI)
t1, t2 = T1_BASE * scale * jitter1,  T2_BASE * scale * jitter2
rel   = clampf(notability / (2 * mean), 0, 1)                     # notable FOR THIS GAME

# tier 2 first (it outranks tier 1), then tier 1, each through the same gate:
d = n - last_fire
if d >= COOL and (reservoir >= t or d >= SOFT):
    u     = clampf((d - SOFT) / (HARD - SOFT), 0, 1)       # soft pity ramp
    merit = (M_FLOOR + (1 - M_FLOOR) * pow(rel, M_EXP)) if reservoir >= t else 0.0
    if rng.randf() < merit + (1 - merit) * u:
        fire
```

- **The drift correction** (`mean`, `scale`) is why the rates survive a scorer re-tune. A
  half-game prior holds calibration steady through the opening, where the sample is too small to
  trust, and yields to the game's real texture in the back half, where a showstopper is most
  likely to land. `SCALE_LO/HI` are guards against a pathological scorer, not tuning knobs;
  the compensation is deliberately **partial**, because full normalisation would give a quiet
  game exactly as many flourishes as a bloodbath and erase the dynamic range the flourishes
  exist to express.
- **`rel`, not raw notability, feeds the gate.** In a bloodbath a routine capture must not read
  as special; in a quiet game a modest one should. This is the "*they alternate depending of the
  situation in the game*" clause, mechanised.
- **The merit floor** is why a plain-looking capture can still pop — the owner's "surprise you
  from time to time". The exponent is why a great one usually does. Tier 2 uses a low floor and
  a square: strongly earned, occasionally an ambush.
- **Pity is a ramp, not a timer.** Past `SOFT` captures of drought the gate opens progressively
  and reaches certainty at `HARD`, so the system spends the window shopping for the best capture
  in it rather than firing on whichever one happens to sit at the deadline. `HARD2` is the hard
  promise: *no window of `HARD2` captures passes without a showstopper*. The governor cannot
  know a game's length in advance, so this is the strongest statement a causal system can make —
  and it is also the stronger property, because it holds for a game of any length.
- **Jitter** multiplies each threshold by `U(1-J, 1+J)`, drawn at `reset_game()` and redrawn on
  every fire. A reservoir with steady increments fires on a *schedule*; a player who plays five
  games learns "there's one just past the middle", which is rare-but-predictable — the exact
  failure the brief asks us to avoid. Drawing at reset is what disperses the *first* fire, which
  is the only one most games show and therefore the perceivable one.
- **On a fire the reservoir zeroes** and both `last_fire` marks update (a tier 2 also pays tier
  1's debt — the moment is spent).
- **`_commit` resolves the variant before it drains anything.** If the catalogue cannot supply
  the tier, demote **without draining** — a showstopper the VFX layer cannot render must not
  spend the budget, or a thin catalogue silently starves the whole game.

### 6.3 Novelty — the second axis

Rarity randomises *when*. Novelty randomises *what*. A 1-in-15 event you can name in advance
has stopped being a surprise and become a reward. Both axes must move or the second showstopper
of the session is merely the first one again, on schedule.

The pigeonhole arithmetic is blunt. With a uniform random pick from a pool of 6, five flourishes
in a game contain a repeat **90.7 %** of the time; from a pool of 4, **100 %**. That is the
feature failing in its first game, and no amount of tuning the tier rates touches it.

The picker, per tier, over `{seen: id -> count}` and `{recent: [ids]}`, both cleared by
`reset_game()`:

1. **Stage 0** — hard-block the last `BLOCK` fired ids, weight unseen variants `NOVELTY_UNSEEN×`,
   decay repeats as `1/(1+count)`.
2. **Stage 1** — drop the block, keep the novelty weighting (the block exhausted the pool).
3. **Stage 2** — base weights only (everything seen and blocked).
4. **Fallback** — first of pool, reported as `novelty: "exhausted"`, which is the signal that the
   catalogue is too thin.

`BLOCK` is clamped to `pool.size() - 1`. Blocking the last 2 of a pool of 2 deadlocks the picker
into the fallback every time and throws the whole memory away; the clamp is the difference
between strict alternation and random-again (§9.9 tests exactly this).

**Applicability always outranks novelty.** A variant absent from `candidates[tier]` is not in
the pool, and a zero base weight is a hard exclusion at every stage. Novelty can reorder the
applicable set; it can never reach outside it. This is the rule that stops "surprising" from
degrading into "wrong".

**Requirement handed to the catalogue:** ≥ 6 tier-1 variants and ≥ 5 tier-2 variants applicable
to a typical capture (§7.3).

### 6.4 Determinism

**Two seeded `RandomNumberGenerator` members**, mirroring `Banter`'s idiom exactly (`src/banter/banter.gd:148`
`var _rng`, `:151-152` `_init` randomizes, `:155-157` `seed_rng`) so the governor reads as a
sibling and not a stranger:

- `_gate` — tier decisions and threshold jitter.
- `_pick` — variant selection, seeded `seed ^ <odd constant>`.

**Two streams, not one, and this is load-bearing.** A test that pins the *tier sequence* must
not break when the catalogue grows a variant. With one stream, adding a seventh flourish shifts
every subsequent gate draw and the pinned sequence dies — meaning the pacing tests would be
re-baselined on every art commit, and a re-baselined test proves nothing.

The gate stream's draw count per `decide()` is a function of governor state only, never of the
candidate arrays. Two consequences enforced in code: jitter is redrawn only *inside* `_commit`
after the variant resolves, and `reason` is derived arithmetically, never by a second draw.
**A diagnostic that consumes randomness is a diagnostic that changes the outcome.**

Single-player seeds randomly and **prints the seed at game start**, matching this project's
existing evidence habit (`PROMOTION PLAYED …`, `game.gd:992`), so a game that felt wrong can be
replayed exactly.

**Multiplayer.** The scorer is deterministic, so both peers compute the same notability from the
same broadcast move — `_on_net_move_applied` (`game.gd:749`) funnels into the same `_execute_ply`.
The *governor* is not deterministic without a shared seed. `net_match.gd:65` carries `start_fen`,
set for the host at `:216` and read off the wire by the joiner at `:377`, so `hash(start_fen)`
gives agreement with no protocol change — but it also makes every match from the standard
opening position identical. A per-match nonce needs **one field** added to the handshake
dictionaries at `net_match.gd:363` and `:396`. Multiplayer is out of scope for visionOS build 1
(port spec §7), so this is a named gap with a named fix, not a blocker.

**Take-backs.** `game.gd:112` already keeps `_undo_checkpoints` of `{stack, san, banter_ply}`,
popped in `_perform_undo` (`:1062-1063`). The governor joins that dictionary via
`snapshot()`/`restore()` — ~12 scalars plus both RNG **states** (`RandomNumberGenerator.state`,
not `.seed`; restoring the seed rewinds the whole stream and makes the replay diverge). An
undone capture returns its spent showstopper to the budget and un-sees its variant.

### 6.5 The constants, and how much to trust them

Sixteen tuned constants: `PRIOR_MEAN`, `PRIOR_W`, `SCALE_LO`, `SCALE_HI`, `T1_BASE`, `T2_BASE`,
`COOL1`, `COOL2`, `SOFT1`, `HARD1`, `SOFT2`, `HARD2`, `M1_FLOOR`, `M1_EXP`, `M2_FLOOR`,
`M2_EXP`, plus `JITTER`, `BLOCK` and `NOVELTY_UNSEEN`.

**The source design reported a 20 000-game simulation sweep producing 1/4.40 and 1/14.73 against
the owner's 1-in-4 and 1-in-15. That simulation does not exist in this repository and its numbers
are not reproducible from disk.** They are recorded here as the *provenance of the starting
values*, not as a measured property of anything. The starting values are: `T1_BASE 1.40`,
`T2_BASE 5.60`, `COOL1 2`, `COOL2 5`, `SOFT1/HARD1 4/7`, `SOFT2/HARD2 10/16`,
`M1_FLOOR/EXP 0.25/1.5`, `M2_FLOOR/EXP 0.08/2.0`, `JITTER 0.30`, `PRIOR_MEAN 0.5`,
`PRIOR_W 12`, `SCALE_LO/HI 0.6/1.6`, `BLOCK 2`, `NOVELTY_UNSEEN 3.5`.

**The correctness of every one of them is a test, not an opinion** (§9). When the measured rates
drift, move `T1_BASE`/`T2_BASE` — not the scorer weights. The weights encode what matters; the
thresholds encode how often.

### 6.6 Cut from the governor

- **`QUIET_BEFORE_2`** (veto a showstopper on the capture right after a flourish). Its own
  design measured the cost at 1/15.26 → 1/15.87 — a 0.6 % effect. A constant that small is a
  playtest question, not a design element.
- **`CARRY`** (partial reservoir drain, banking surplus). Zeroing is simpler and one fewer
  interaction to reason about. Re-add if a bloody stretch feels under-served.
- **`persist_novelty`** (cross-game memory). Off by default in its own design, untested at
  session scale, and it makes the first game of a session behave differently from the fifth.
- **Tag-based anti-repetition** ("don't fire the same reason twice running"). Variant-level
  novelty already covers the observable case; a second memory over `tag` is a mechanism with no
  named failure to prevent.

---

## 7. The catalogue

### 7.1 Shape

One file, `src/cinematics/moments.json`, mirroring `kill_lines.json`'s conventions exactly: a
leading `_readme` documenting the vocabulary (as `kill_lines.json:2` does), a flat array of
entries, and the same `"attacker"`/`"victim"` piece pins with the same values that
`pick_kill_line` filters on (`duel_director.gd:335-339`).

```jsonc
{
  "_readme": "Moment catalogue. Tier 0 = the six shipped KILL_STYLES, untouched. Tier 1 ≈ 1 in 4, tier 2 ≈ 1 in 15. 'requires'/'any_of'/'forbids' name keys in the situation dict (moment_context.gd). 'attacker'/'victim' pin to a piece name exactly as kill_lines.json does. Beat times are WALL seconds relative to 'anchor'; anchor 'impact' is the frame the victim's death_style goes non-empty — the same instant DuelDirector._impact_shake watches (duel_director.gd:474-481). Every fx name must exist in the stage registry; tests/test_moments.gd fails the build otherwise.",
  "version": 1,
  "moments": [
    {
      "id": "haus_answers",
      "tier": 1,
      "weight": 6,
      "any_of": ["grudge", "first_blood", "revenge_square"],
      "budget_ms": 0.30,
      "beats": [
        {"at": 0.00, "anchor": "impact", "fx": "sdf_field",
         "args": {"plane": "floor", "at": "victim", "shape": "ring",
                  "radius_m": 0.95, "thickness": 0.14, "life": 0.45,
                  "color": "$attacker.primary", "fill": 0.06}},
        {"at": 0.10, "fx": "dust", "args": {"at": "victim", "amount": 10}}
      ]
    }
  ]
}
```

Filter semantics, deliberately identical in spirit to `pick_kill_line`: `requires` (all),
`any_of` (at least one), `forbids` (none), plus the piece pins. Survivors go to the governor as
`candidates[tier]`. If nothing survives at a tier, fall to the tier below — and **tier 0 is
always available, so a capture can never fail to play**.

### 7.2 The primitives

A closed vocabulary. Five of the useful ones **already exist as parameterised functions** and
become catalogue primitives with a rename, not a rewrite:

| `fx` | Backing | Status |
|---|---|---|
| `strike_arc` | `piece_view._strike_flash(world, opts{height,scale,life,tilt,tint,at})` (`piece_view.gd:1291`) | exists, already opts-driven |
| `dust` | `_dust_puff` (`piece_view.gd:1533`) | exists |
| `embers` | `_ember_wisps` (`piece_view.gd:1611`) | exists |
| `char` | `_die_burning` (`piece_view.gd:1465`) | exists — a material path, zero draw calls |
| `time` / `shake` | `duel_slow_scale`/`duel_slow_hold_wall` (`duel_director.gd:64,61`), `impact_shake_mult`/`_wall` (`:84-85`) | exist as `@export`s |
| `sdf_field` | **new shader** — one quad, fragment remaps UV to world metres; `shape` ∈ ring/disc/cross/chevrons | `assets/vfx/shock_ring.gdshader:5-6,17-19` and `ground_glow.gdshader:5-7` are already this primitive twice over — same `render_mode unshaded, blend_add, depth_draw_never, …`, same `length(UV - vec2(0.5)) * 2.0` idiom, same `radius`/`thickness`/`amount`/`energy` uniform names |
| `ribbon` | **new** — instanced strip, `(t, side)` per vertex expanded to world position in the **vertex** shader, with a `front` advancing at constant m/s | ~40 lines |

**Camera and time are already data-driven per duel.** `duel_director.gd:58-89` exports the whole
staging surface. A tier-2 that wants a deeper dilation pushes `duel_slow_scale` and restores it —
with **no new director code at all**. The push must be applied by the **caller, before**
`play_duel`, because `play_duel` launches the strike callable at `duel_director.gd:172-176` and
only then reads `duel_slow_scale` at `:179`; a stage that set it from inside the callable would
usually win that race and would silently lose it the day an `await` is added above.

The restore must be asserted on the normal, skip and freed-mid-cinematic paths — a stuck
`duel_fov` is the same class of shipping bug the director already has an entire time-scale
hygiene doctrine about (`duel_director.gd:7-8`: *"all awaitable sequences restore
Engine.time_scale, camera and audio pitch on EVERY exit path"*).

### 7.3 Size of the first slate

Set by §6.3's pigeonhole arithmetic, not by taste: **≥ 6 tier-1 and ≥ 5 tier-2 entries
applicable to a typical capture.** To make that satisfiable without nine variants per piece
type, catalogue entries are **signal-keyed, not piece-keyed** — piece pins are used only where
the choreography demands it (the ranged ranks, `piece_view.gd:159` `RANGED_STYLES`). That
resolves the tension between the two designs that set catalogue requirements: one asked for six
variants *per piece type*, which is a 36-entry authoring ask; signal-keyed entries mean the pool
is large for every capture.

One area design proposed a further nine per-haus tier-2 "signatures" plus a haus-pack extension
path (`hauses/<id>/moments.json`). **Both are cut from this spec.** Nine more entries do not
make the system more surprising once the pool clears the pigeonhole floor, and untrusted JSON
driving the renderer needs a validation story that does not exist yet.

---

## 8. The frame budget

The port spec's §8 sets the arithmetic: stereo doubles fragment cost **and** the target moves
from 60 Hz to 90 Hz (11.1 ms), so `docs/PERF.md`'s numbers are roughly a third-budget —
**about 5.6 ms**, on Godot's Mobile renderer, the only one visionOS immersive supports.

**Every millisecond in this section is an estimate from a stated model, not a measurement.**
`docs/PERF.md:3-20` opens with the reason that distinction matters here: a co-tenant Godot
instance on the same GPU took ~90 % of the frame budget, two separate agents mistook that
contention for a defect, and it cost this project two agent-hours and a wrong doctrine that was
then baked into the docs. **No number below may be quoted as fact until the perf driver measures
it on hardware with a `PERF COTENANT` line printed beside it.**

The model: **1 FSE (full-screen equivalent) = 1.8 ms** for a ~25-instruction unlit
alpha-blended shader across both eyes on a tile GPU; fill ≈ `coverage × overdraw × 1.8 ms`;
particles ≈ 0.002 ms each plus their coverage; draw-call CPU ≈ 0.02 ms each. Declared caps:
**tier 1 ≤ 0.50 ms, tier 2 ≤ 1.80 ms**, and **≤ 4 new draw calls per moment**.

Every `budget_ms` in the catalogue is a **declared** number that §9 turns into a falsifiable
gate: a `moments` arm in `test_e2e/perf_driver.gd` plays each entry in isolation on the real
board and fails if measured added milliseconds exceed the declaration × 1.25.

**In stereo, depth does half the work.** Effects that need heavy shading to read as volume on a
flat screen read as volume for free when each eye sees them correctly. Sparks with real
parallax beat a raymarched cloud. That is why the two new primitives are an SDF quad and an
instanced ribbon strip.

### 8.1 Explicitly forbidden at this budget

Named so a future implementer does not reach for them:

1. **Raymarched volumetrics.** A reference using 72 raymarch steps × 5 octaves of 3D noise was
   assessed and rejected as an order-of-magnitude overrun. No moment may sample 3D noise in a
   loop; a burn front is `smoothstep` on an SDF.
2. **Screen-space refraction / heat shimmer during a duel.** `assets/vfx/heat_shimmer.gdshader`
   exists, and `assets/vfx/dracarys.gd:74` calls that layer "*the single most expensive layer —
   first thing to drop*". It forces a screen-texture read, which on a tile GPU is a resolve, and
   in stereo it is two.
3. **Any new `Light3D`.** The hall's 8-omni budget is full. `assets/vfx/dracarys.gd:14` states it
   as a standing rule ("*this file NEVER creates a Light3D. The hall's…*") and
   `assets/vfx/ground_glow.gdshader:1-4` is the sanctioned workaround ("*the no-Light3D firelight
   cheat … the hall's 8-omni budget is FULL*"). Firelight is HDR emissive plus additive quads.
4. **Shadows from any effect.** `cast_shadow = SHADOW_CASTING_SETTING_OFF` on every node the
   stage parents; the existing kit already does this everywhere.
5. **Screen-space post** — motion blur, DOF, SSR, SSAO, SSIL, volumetric fog. Several are
   unavailable on Mobile and the rest are per-pixel-per-eye.
6. **Full-screen overlay quads** — colour flashes, vignettes, letterboxing, speed lines. On a
   flat screen these are free drama; in a headset they are *on your face*, a comfort hazard, and
   100 % fill × 2. **Every moment is world-anchored and bounded by the board.**
7. **Moving the eye.** No cuts, no teleports, no induced rotation, no forced FOV change — the
   camera *is* the player's head (port spec §5.2). Tier-2 drama comes from time dilation and
   world-space framing only. Any entry using `duel_fov`/`swoop_wall` must declare an XR fallback.
8. **Geometry near the head.** Nothing renders closer than ~0.5 m to the viewer or crosses their
   forward vector at speed.
9. **Particle excess.** ≤ ~120 particles per effect, ≤ 2 simultaneous emitters, **no
   `trail_enabled`** (it rebuilds geometry every frame), no collision, no attractors, no
   sub-emitters. Use a `ribbon` where a trail is wanted — that is what the primitive is for.
10. **Anything created at moment time.** No `load()`, no per-beat material construction, no
    texture generation. A material duplicate triggers shader-variant compilation, i.e. a hitch on
    the frame of the best capture in the game. The stage prewarms every material and mesh once at
    match load and pools them.
11. **`Engine.time_scale` below 0.10 or slow-mo longer than ~1.2 s wall — and the honest note
    that goes with it: slow motion does not reduce GPU cost.** A tier 2 at 0.12 for 1.0 s wall is
    ~90 frames of the effect at full per-frame price. The instinct to "make it cheaper by slowing
    it down" is exactly backwards and it will be reached for.
12. **Anything that pushes a duel past ~6 s wall.** `test_e2e/e2e_driver.gd:2372` fails a run at
    `wall > 7.0` with the message "*the duel ran %.2f s (budget is ~5.5 s, failsafe 8 s)*", and
    the director's own failsafe is `failsafe_wall_sec := 8.0` (`duel_director.gd:76`). A tier 2
    that adds 2.5 s to a queen capture does not look slow — it turns the suite red. **Added wall
    time is capped at 1.5 s and asserted statically over the JSON**, not left to convention.
13. **Stacking.** `duel_director` already serialises via `_active` (`:138`); the stage refuses to
    start a second moment while one is live and hard-stops everything when `is_active()` goes
    false (the skip path, `:145-150`).

---

## 9. Testing

Three suites, one per unit, all `extends SceneTree`, headless `-s`, exit 0/1, all following the
house pattern: a `MIN_EXPECTED_CHECKS` floor (`tests/test_cinematics.gd:29,68-69` — a
hard-erroring test aborts silently and its caller carries on as if it passed), a documented
**why** on every assertion, and **negative controls that must go red**.

### 9.1 Context and scorers — `tests/test_moment_score.gd`

- **Rule assertions.** Hand-built FENs, one per rule, asserting the exact `tag` and a score band:
  en passant, promotion capture, last-queen, lead-flip, veteran, revenge (a scripted 12-ply
  game), sacrifice-with-check versus sacrifice-without.
- **The context never mutates the board.** `state.get_fen()` (`ChessState.gd:269`) is
  byte-identical before and after `situation()`, and `situation()` never calls `get_result()`.
- **`_turn_moves` freshness.** The three best free signals all depend on the move list belonging
  to the post-capture `state.turn`. A refactor that moved `_refresh_turn_moves()` (`game.gd:906`)
  after `_animate_move` would silently invert `replies` and `recapturable` with **no error**, so
  `situation()` asserts that every passed move's `from_square` holds a piece of that colour.
- **Distribution.** 40 `ChessAI` self-play games at MEDIUM via `choose_move_sync`
  (`ChessAI.gd:169`), scoring every capture; print the notability histogram and the tag
  histogram so a regression names itself.

### 9.2–9.15 The governor — `tests/test_moment_governor.gd`

Each property is written so a **do-nothing** governor (always tier 0), a **coin-flip** governor
(uniform random tier) and a **threshold** governor (`tier = 2 if s > 0.93 …`) all fail at least
one. `MIN_EXPECTED_CHECKS` ≈ 95.

| # | Property | Why it is here |
|---|---|---|
| 1 | **Tier-1 rate** in `[0.20, 0.29]` over 4 000 games of 15–30 captures, notability `Uniform(0,1)` | the owner's 1-in-4, as a measured rate with a band, not a vibe. Kills do-nothing |
| 2 | **Tier-2 rate** in `[0.055, 0.085]` | the owner's 1-in-15. Kills do-nothing and coin-flip |
| 3 | **Cooldown is absolute** — no two tier-2 within `COOL2`, no two tier-1 within `COOL1`, over ~90 000 captures. A single violation fails | an invariant, not a rate. Kills coin-flip |
| 4 | **Pity is absolute** — max observed gap (and gap from game start to first fire) ≤ `HARD2`; 100 % of 4 000 games of exactly 16 captures contain a tier 2 | "once or twice per game" is a guarantee. Kills the threshold governor, which goes dry whenever the scorer runs cold |
| 5 | **Rate survives scorer drift** — repeat 1–2 with `Beta(2,8)` (mean 0.20) and `Beta(8,2)` (mean 0.80); tier-2 share stays in `[0.05, 0.09]` in both | **the property a threshold governor cannot pass**, and the one that protects the owner's rates from every future scorer re-tune |
| 6 | **Merit is real** — mean notability of tier-2 captures exceeds tier-0 by ≥ 0.12; tier-1 exceeds tier-0 by ≥ 0.10 | this is the assertion that STAKES/STORY/SKILL/RARITY actually earn the moment rather than decorate it. Kills coin-flip |
| 7 | **Anti-metronome** — tier-2 gap standard deviation ≥ 1.9 captures; 5th-to-95th-percentile spread of the *first* fire's position ≥ 5 captures. **Negative control: rerun with `JITTER = 0.0` and require both to go red** | the only way to prove the jitter constant is doing work rather than sitting in the file |
| 8 | **Novelty beats chance** — pool of 6, 5 fires/game: < 30 % of games contain a repeat. **Negative control: `NOVELTY_UNSEEN = 1.0`, `BLOCK = 0` must exceed 80 %.** Plus: pool of 3, 12 forced fires, no variant twice within any 3-fire window | §6.3's pigeonhole arithmetic, as a gate |
| 9 | **Novelty degrades, never deadlocks** — pool of exactly 2, 20 forced fires: strict alternation, valid id every time. Pool of 1: 20 fires, all `novelty: "exhausted"` | proves the `BLOCK` clamp clamps rather than starves |
| 10 | **Determinism** — same seed + same 500-capture sequence ⇒ byte-identical `(tier, variant)` sequence; seeds 1 apart ⇒ *different* tier sequences | the second half guards against a seed that silently fails to take |
| 11 | **The tier sequence is catalogue-independent** — same seed, same notability sequence, 4-variant vs 9-variant catalogue ⇒ identical tier sequence, different variant sequence | the two-stream design under test; without it, every art commit re-baselines 1–7 |
| 12 | **Wall-clock independence** — identical across two runs and with `Engine.time_scale` set to 0.15 between calls | pins "no `Time`, no frames, no globals" as an executable contract rather than a comment. The director sets `time_scale` for real (`duel_director.gd:64`) |
| 13 | **Starvation demotes without spending** — a governor primed at the pity ceiling handed `{2: [], 1: [x]}` returns tier 1 `reason: "starved"`, and the *next* capture with a non-empty tier-2 pool fires tier 2 | an empty catalogue costs a frame of budget, not a whole showstopper |
| 14 | **Take-back is exact** — snapshot at capture 20, run 20 more, restore, re-run: identical sequence. Snapshot before a tier-2 fire, restore, assert reservoir/`last_fire`/`seen` are pre-fire | kills any implementation storing the RNG *seed* instead of its *state* |
| 15 | **Degenerate scorers do not explode** — notability constant 0.0 and 1.0: tier-2 share in `[0.04, 0.12]`, no cooldown violation, no game over 3. `NAN`, `INF`, `-5.0` clamp and do not crash | the scorer is another module and its bugs must not take the cinematics with them |

### 9.16 The catalogue — `tests/test_moments.gd`

- **Every `fx` exists** in the stage registry. A typo in JSON must fail the build, not fail
  silently at the moment of the best capture in the game.
- **Every entry is reachable** — construct a situation satisfying each entry's
  `requires`/`any_of`/`forbids`/pins. An unreachable entry is dead art.
- **Pool floors hold** — ≥ 6 tier-1 and ≥ 5 tier-2 applicable to a typical capture (§7.3).
- **Budgets are declared** and within caps (tier 1 ≤ 0.50 ms, tier 2 ≤ 1.80 ms).
- **Static concurrency gate** — sum each beat's declared `fill` over overlapping
  `[at, at+life)` windows; fail if any instant exceeds the tier cap. Authoring that overspends is
  caught at test time, not on a headset.
- **Wall-time gate** — sum each entry's beat span; fail above 1.5 s added (§8.1 item 12).
- **The director's exports always restore** — apply then restore on the normal, skip and
  freed-mid-cinematic paths leaves every `@export` at its captured value, the same discipline
  `tests/test_cinematics.gd` already enforces for `Engine.time_scale`.

**No CI on the visionOS target** (port spec §9). The catalogue's perf arm runs on macOS hardware
with the co-tenancy control from `docs/PERF.md:3-20`, and the device numbers are a manual gate.

---

## 10. Risks and honest unknowns

1. **The governor's calibration is simulated, not played — and the simulation is not in this
   repo (§6.5).** Worse, every synthetic distribution used to derive the constants assumes
   independent draws, and real capture notability is *autocorrelated*: exchanges come in pairs,
   endgames go quiet, a queen trade is usually followed by another capture on the same square.
   Autocorrelation will move the realised rates, most likely by inflating the reservoir in bursts.
   **The first thing to do with the real scorer is dump 200 self-play games of notability to a
   file and re-run the sweep against that**, before believing any headline rate.
2. **Metronome residue.** The pacing guarantees — never two within `COOL2`, never a dry window of
   `HARD2` — mathematically preclude true Poisson timing. Jitter disperses the gaps; it does not
   randomise them. A player who plays ten games in a sitting may still feel that the first
   showstopper arrives "somewhere past the middle". **No test in §9 will catch this**, because
   property 7 passes by construction. It shows up only in a multi-game playtest with the printed
   seed, asking specifically: *could you feel when one was coming?*
3. **Pity landing on a nothing capture.** The soft ramp is what keeps forced fires from landing
   on whatever sits at the deadline, but the merit floor makes an unearned tier 2 possible *by
   design*, and pity makes it inevitable eventually. Detection is built in: log every tier 2 as
   `MOMENT tier=2 reason=… rel=…`; if `reason == "forced"` exceeds ~15 % of tier-2s across a
   session, or mean `relative` drops below 0.55, the **scorer's** dynamic range is too flat — and
   the log is what distinguishes that from a governor fault.
4. **The rarity frequency estimates are experience, not measurement** (§5.4). They get one pass
   against the self-play histogram from §9.1.
5. **Tier 1 becoming wallpaper.** At 1-in-4.4, a 30-capture game shows ~7 flourishes. If the
   flourish is even slightly too loud, seven is six too many — and the governor will look like the
   culprit when the real problem is VFX amplitude. The giveaway is a playtester describing tier 1
   and tier 2 in the same words. `T1_BASE` is deliberately isolated so the fix is one line.
6. **Effect lifetimes can still overlap.** The governor guarantees no two moments *start* on the
   same capture. It has no visibility into how long an effect *runs*, so two tails can share
   frames on a tile GPU at 90 Hz. That latch belongs to the stage — one effect owns the frame
   budget — and is not covered by anything in §9.
7. **`piece_view.gd:562-563` picks `kill_variant` with a bare, unseeded
   `randi() % KILL_VARIANTS`** on the presentation path of a networked, replayable game. **Two
   peers already animate different variants of the same kill today.** `kill_variant_force`
   (`:352`) is the existing test seam that could hand the choice to the governor. This is a
   pre-existing defect this design *surfaces*, not one it introduces — and until it is fixed, a
   green governor determinism test (§9 property 10) must **not** be read as "the capture
   presentation is deterministic".
8. **The ledger's undo stack grows for the whole game** — one `_at` snapshot per ply. Small in
   absolute terms; on visionOS memory is tighter than on desktop. If it matters, store an inverse
   operation per ply instead of a snapshot.
9. **Sixteen tuned constants is a lot of surface.** Each moves one behaviour and each is
   isolated, but a future maintainer tuning `T2_BASE` without re-running the sweep drifts the
   rates silently. The mitigation is that §9's properties 1–7 are rate assertions with explicit
   bands, so a bad tune goes red rather than shipping — **and that only works if the suite stays
   in the gate rather than being run by hand.**
10. **Every millisecond in §8 is an estimate from a stated model** (§8's opening). Nothing there
    is a device measurement, and `docs/PERF.md:3-20` records what this project already paid for
    treating an unmeasured frame number as fact.
11. **Sigil art quality is unverified.** Any catalogue entry that renders a haus charge assumes a
    clean, high-contrast silhouette with sane alpha. Some of the nine will not have one, and the
    effect will look broken for exactly those hauses.

---

## 11. Out of scope

- **Captions.** `kill_lines.json` + `pick_kill_line` (`duel_director.gd:331`) already vary the
  text and are not touched. Both designs that proposed a second, moment-authored caption surface
  were cut (§5.6).
- **Checkmating captures** (§3.3) — `play_checkmate` (`duel_director.gd:227`) is the showstopper
  already.
- **Discovered/double check detection** (§4.6), a deeper SEE (§4.3), and any Stockfish-derived
  skill signal (§4.6).
- **Per-haus tier-2 signatures and haus-pack-supplied moments** (§7.3).
- **Cross-game novelty memory, `QUIET_BEFORE_2`, reservoir carry, tag anti-repetition** (§6.6).
- **The stage, the two shaders and the authored catalogue entries** — Plan 5. This spec
  specifies their contract, their budget and their gate; it does not build them.
- **A multiplayer match nonce** (§6.4) — one field at `net_match.gd:363,396`, and multiplayer is
  out of scope for visionOS build 1 per the port spec §7.
- **Any behaviour change to tier 0.** All six `KILL_STYLES` stay and stay untouched. The pawn's
  `stab` carries a shipped-frame interpenetration fix and the knight's `charge` carries three
  corrections earned from a bad reel frame. The stage's contract — *it always calls the strike it
  was handed and only adds beats around it* — is what keeps those 18 shipped kills and the
  `death_style` contract (`piece_view.gd:343`) that `_impact_shake` (`duel_director.gd:474-481`)
  depends on intact.

---

## 12. Definition of done — the policy layer

Plan 4 ships when:

1. `tests/test_moment_score.gd`, `tests/test_moment_governor.gd` and `tests/test_moments.gd` are
   green, with their `MIN_EXPECTED_CHECKS` floors met.
2. Governor properties 1–7 (§9) pass **with their negative controls red**.
3. A 200-game self-play dump exists and the constants have been re-swept against it (§10.1), with
   the observed tier-1 and tier-2 rates printed.
4. Nothing in `src/cinematics/duel_director.gd` has changed except, at most, the one caption seam
   — and `tests/test_cinematics.gd` is still green at its existing floor of 95 checks.
5. `test_e2e` green on macOS, including the `kills` scenario's `wall > 7.0` gate
   (`test_e2e/e2e_driver.gd:2372`).
6. `tools/build/build.sh all` still passes for Windows and macOS.

**EETISMAD:** E2E-tested (three headless suites + the macOS e2e net) · In docs (this spec plus
the catalogue `_readme`) · Merged · And Deployed — deployment for the policy layer means the
governor is wired into `game.gd:906` and printing its seed and its verdicts, with tier 1 and
tier 2 both mapped to tier-0 beats until Plan 5 gives them their own. **That is the shape of the
first ship: the pacing is provably right on real games before a single shader is written.**
