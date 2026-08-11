#!/usr/bin/env bash
# run_e2e.sh — Great Hauses in-engine E2E suite.
#
# Steps:
#   preflight   import-artifacts check (the empty-.godot/imported scar) +
#               headless boot with zero SCRIPT ERROR/Parse Error
#   tests       ALL headless suites — engine (79), tournament, cinematics
#               time-restore, DS4 opponent (mock+live, 3 modes),
#               UciEngine/stockfish client, music (104), banter (93),
#               dragon spectator/ASHFALL, duel face-off, SIGNATURE KILLS
#               (18 — three variants of each rank's kill), costumes
#               (273 — mounted knights and pawn helms included),
#               head-to-head protocol (216 — host authority, the
#               illegal-move-from-client refusal, the cinematic
#               gate), PROMOTION (94 — all four choices, the knight's
#               check, the rook that avoids the queen's stalemate,
#               undo back to the pawn, host authority over the
#               promotion piece), the MINIGAME rules (98 — blast shape,
#               blackstone, chains, boons, the wyrm's ring, 27 AI-vs-AI
#               matches) and the DRAW-SEAM WIRING (88 — which draws go to the
#               arena, the two difficulty enums agreeing 1:1, the survivors
#               harvested from a real stalemate, the contract shape on every
#               refusal, and the three music tiers being one 60.000 s loop)
#               and the visionOS XR BRING-UP state machine (46 — the exact
#               find/initialize/use_xr/origin/near order, every silent-
#               failure step reported by name with a non-empty diagnostic,
#               a second bring_up on an already-up session genuinely
#               skipping initialize()/the setters rather than merely
#               reporting ok, the once-only guard's own test reset proven
#               to work so no later case runs against a stuck guard,
#               set_origin_current/set_near FAILURE reported as step
#               "origin"/"near" instead of silently latching ok=true on a
#               missing rig (2026-08-10: the 6th silent-green this plan
#               produced — bring-up reported success while doing nothing),
#               that failure NOT latching the once-only guard so a later
#               bring_up with a real rig still runs for real, and the REAL
#               XRSession._set_origin_current/_set_near helpers — not just
#               VisionOSBoot's handling of a fake false return — proven to
#               report false on this host's genuinely empty "xr_origin"/
#               "xr_camera" groups, the real origin setter proven by a
#               WRITE-BACK the engine does not force, and the two values
#               nothing else names: INTERFACE_NAME == "visionOS" and
#               project.godot's xr/shaders/enabled, without which the Mobile
#               renderer ships a build that cannot draw a stereo frame),
#               and the XR RIG AND ITS TWO CALL SITES (35 — Task 5b plus the
#               ordering fix: scenes/game.tscn's XROrigin3D/XRCamera3D
#               resolve by the exact "xr_origin"/"xr_camera" groups
#               xr_session.gd looks up, the camera's near plane already
#               clears VisionOSBoot.MIN_NEAR, neither node is `current` in
#               the saved scene — the origin read from the .tscn's TEXT,
#               because an XROrigin3D does not retain that property pre-tree
#               and the property read could not fail — the pre-existing
#               CameraRig/Camera3D untouched and still the one current
#               camera, and then the part no .tscn check can cover: the real
#               main.tscn mounted into a real tree, proving main.gd._ready()
#               EXECUTED phase 1 (not merely contains the text — a call
#               moved into a never-invoked function used to pass), and the
#               real game.tscn mounted twice, once with its near plane
#               deliberately broken to 0.01 so only a real bind can repair
#               it, and once with the rig removed so a bind that reports
#               success without touching a node comes back red)  — Gate A
#
#               The two counts above are ENFORCED, not decorative: both XR
#               suites print ASSERTIONS=<n> and run_suite fails on a
#               mismatch. They had drifted to half the real number before a
#               2026-08-10 audit noticed.
#   boot        windowed: select flows to game, 32 pieces, banners+HUD dyed
#   orientation windowed: --debug-coords labeled overlay from the default
#               player camera, saved as labeled.png — the permanent
#               human-auditable orientation artifact           — Gate B
#   board-truth windowed: startpos board vs HUMAN truth, convention-
#               independent — visual squares by screen geometry, colors
#               sampled from rendered pixels (a1 dark, queen on light),
#               royals by rendered position, White seated near; engine
#               tile-node parity kept as a crosscheck            — Gate B
#   board-moves windowed: clicks visual d1/e1 BY SCREEN POSITION; highlights
#               must equal the hand-derived queen/king movesets  — Gate B
#   move        windowed: click e2->e4, AI replies within 30 s  — Gate B
#   duel        windowed: scripted capture duel via clicks      — Gate B
#   castle      windowed: O-O by clicks; king STANDS on visual g1,
#               rook on visual f1                                — Gate B
#   enpassant   windowed: exd6 e.p. by screen clicks; pawn lands visual d6,
#               captured pawn vanishes from visual d5            — Gate B
#   promote     windowed: THE PROMOTION PICKER — all four pieces taken in one
#               run (click a piece model · hotkey · arrow keys · Esc for the
#               default queen), each undone back to the pawn; asserts the
#               knight's CHECK, the rook AVOIDING the stalemate the queen
#               causes, the right model + flourish per choice, and the draw
#               card + draw taunt + bracket seam at the end   — Gate B
#   slowmo      windowed: duel director activation, time dip, skip-on-click
#   kills       windowed: SIX RANKS, SIX KILLS — one duel per piece type under
#               the real director; asserts each signature style fires, the
#               victim dies of it, the clock restores and no lamp is added,
#               and saves a frame of every kill
#   tournament  windowed: 3 scripted mates to the throne, bracket + banner
#               re-dress asserts, championship panel
#   trial       windowed: THE TRIAL BY FIRE — a real stalemate drops both kings
#               into the arena and the bracket finally gets a winner. Asserts
#               the arena is built from the survivors of that war and seated on
#               the squares the MATCH calls by the same names, the player's
#               king walking on synthesized keys, a keg burning a crate while
#               the wyrm still sleeps, a boon changing a king, the dragon's
#               ring closing, a king falling, the score climbing fuse -> kegs
#               -> dragon, and the verdict reaching Tournament.report_result()
#               — then board, HUD, camera and time_scale handed back.
#               ALL FUSES AND SPEEDS ARE THE SHIPPING ONES. The single thing
#               the test moves is the wyrm's PATIENCE: once the organic beats
#               are in it brings `sudden_death_at` forward instead of waiting
#               out 70 s, because a king who dies at second 11 ends the duel
#               59 seconds before the dragon is due and the module's own notes
#               put that at roughly one run in three. What the ring then does
#               is entirely the game's own code — only the alarm clock moves.
#               Measured 5/5 PASS, 28 steps, ~23 s.
#   trial-concede windowed: the SKIP path — Esc inside the arena costs the
#               round and nothing else (it must not quit the process, which is
#               what Esc does when the same scene runs standalone), and the
#               card must not claim a king fell in a fight nobody took
#   trial-win   windowed: the ADVANCE path — the one branch a scripted duel
#               cannot be relied on to produce. The cause of the rival king's
#               death is injected through the grid's own kill; everything
#               after it is real. Asserts the bracket advances, player_alive
#               holds, and the card offers "Ride to the …" instead of sending
#               the winner home
#   oracle-mock windowed: DS4-Oracle (Pure) vs in-driver canned HTTP mock
#   oracle-modes windowed: Counseled Oracle — mock proposes a blunder, real
#               stockfish counsel rejects it, revised move plays
#   undo        windowed: take-back insurance vs the mock Oracle in
#               tournament mode — full-round revert (FEN + view census
#               byte-identical, captured pawn resurrects), mid-think undo
#               discards the mock's delayed late reply without desync,
#               3-undo tournament limit disables the button      — Gate B
#   music       windowed: menu/game playlists, M mute on the Music bus,
#               duel duck −8 dB + stinger, unduck on settle
#   banter      windowed: rival taunts in the HUD — accent color, first-blood
#               capture beat, 2-fullmove rate limit held (pool path, dead
#               LLM port)
#   dragon-live windowed: spectator perched + fed, reactions gated under the
#               duel cam, scripted mate → ASHFALL burns the losers, clock +
#               views restored, victory flow reached
#   net-hall    windowed: the Play a Friend door — banner, "Play a Friend",
#               Host (side choice, a real listening socket, the addresses to
#               share), Esc hangs up, then a join to a dead port shows the
#               human-readable "could not reach …" line
#   fullgame    windowed: complete two-rook-ladder game, sync + time_scale
#               hygiene every ply                                — Gate D
#
# HEAD-TO-HEAD is a SEPARATE runner: ./run_net_e2e.sh launches TWO Godot
# instances that play a real game against each other and diffs their per-ply
# FENs. It is not part of this suite because it needs two windows side by side.
#   showcase    windowed 45 s zero-error soak + beauty shots + the
#               championship throne-room tableau                 — Gate C
#
# Every windowed scenario navigates the Hall of Banners (haus select) by
# synthesized clicks first — the select screen IS part of the tested flow.
#
# Scenario launches are WINDOWED (screenshots need rendering) — a game
# window briefly appears; don't touch mouse/keyboard while it's up. Each
# launch uses an isolated $HOME so real user:// data is never touched.
#
# Usage:  ./run_e2e.sh                 # full suite
#         ./run_e2e.sh boot duel      # subset

set -u

GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(dirname "$SCRIPT_DIR")"
ART_ROOT="$PROJ/test_e2e/artifacts"
RUN_ROOT="$ART_ROOT/runs"
STAMP=$(date +%Y%m%d-%H%M%S)
RUN_DIR="$RUN_ROOT/$STAMP"
SCENARIO_TIMEOUT=100   # outer kill; the in-game driver's own watchdog is tighter
SUITE_START=$(date +%s)

# The duel/showcase position: after 1.e4 d5 White has exactly one capture
# (exd5) — a clean scripted duel two squares from board center.
DUEL_FEN="rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2"
# The six-kills position: both armies keep a full pawn wall and their kings,
# and the four middle ranks are EMPTY — the duellists the scenario stands up
# (outside game.views) have the centre of the board to themselves, and with no
# capture on offer the engine sits quietly on the player's turn throughout.
KILLS_FEN="4k3/pppppppp/8/8/8/8/PPPPPPPP/4K3 w - - 0 1"
# Castling-ready: White can O-O immediately (the h2 pawn keeps material legal).
CASTLE_FEN="4k3/8/8/8/8/8/7P/4K2R w K - 0 1"
# En-passant-ready: Black just double-stepped d7d5 past the e5 pawn; exd6
# e.p. is the only capture, and Black keeps ONLY the king so nothing can
# recapture — the visual end-state (pawn d6, d5+e5 empty) is unambiguous.
EP_FEN="4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2"
# THE PROMOTION PROBLEM (Albert's bug). White Kb5, Pc7, Ph6 · Black Ka7, Ph7
# (wedged behind h6 — it has no move). All four promotions are legal from c7
# and all four are different games: c8=Q STALEMATES Black, c8=R does not (only
# the rook avoids it), c8=N gives CHECK where the queen gives none, c8=B does
# neither. The scenario takes all four, one at a time, undoing back to the pawn
# in between. Verified headless by tests/test_promotion.gd.
PROMOTE_FEN="8/k1P4p/7P/1K6/8/8/8/8 w - - 0 1"
# Tournament rounds: Ra8# is mate-in-1 (Kg6 seals the king, rook takes the
# back rank) — one scripted click-mate per bracket round.
TOURN_FEN="6k1/8/6K1/8/8/8/8/R7 w - - 0 1"
# Fullgame: two rooks ladder-mate the bare king — a complete multi-move
# game with a checkmate cinematic at the end (Gate D).
FULLGAME_FEN="8/8/8/4k3/8/8/8/RR2K3 w - - 0 1"
# Counseled-oracle scenario: Black (the Oracle) to move; d8d2 (Qxd2+??)
# trades queen for pawn — the scripted blunder counsel must catch — while
# d8d7 is sound (verified: d8d2 ≈ -522 cp vs best 0 cp at depth 12).
COUNSEL_FEN="3qk3/8/8/8/8/8/3P4/3QK3 b - - 0 1"
# Board-moves scenario: White to move with Qd1+Ke1, O-O legal (O-O-O is
# blocked by the queen herself on d1 — asserted as such); d2/e2 pawns block
# the short rays; the queen keeps the long a4 diagonal.
BOARD_FEN="r3k2r/8/8/8/8/8/3PP3/R2QK2R w KQkq - 0 1"
# Banter scenario: White captures NOW (exd5/Qxd5) and again two plies later
# (Qxh5 — the black h-pawn is wedged behind h4, the black king can never
# defend it): first-blood taunt at fullmove 1, rate-limited gloat at 2.
BANTER_FEN="k7/8/8/3p3p/4P2P/8/8/3QK3 w - - 0 1"
# Dragon-live scenario: Ra8# is mate-in-1 (back rank, f7/g7/h7 lock the
# king's own escape) and the mated haus leaves three pawns standing —
# fuel for the ASHFALL pyre.
DRAGON_FEN="6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1"
# THE TRIAL BY FIRE position — a stalemate-in-1 that leaves an ARMY standing.
# White Ra1 + Kh6; every other pawn is frozen head-to-head (a6/a5, c6/c5,
# e6/e5, b4/b3, d4/d3, f4/f3 — no captures, no pushes), so after Ra1-g1 the
# black king has g7/g8 covered by the rook, h7 by the white king, and no pawn
# can move: STALEMATE. 13 pieces are still on the board when it happens, which
# is the point — the arena inherits a real crate field rather than two kings in
# an empty room. Verified against this engine before the scenario was written
# (the first two candidates were NOT stalemates, which is why this is measured
# and not reasoned).
TRIAL_FEN="7k/8/p1p1p2K/P1P1P3/1p1p1p2/1P1P1P2/8/R7 w - - 0 1"

mkdir -p "$RUN_DIR" "$ART_ROOT"

NAMES=()
RESULTS=()
DETAILS=()

note()   { printf '[e2e] %s\n' "$*"; }
record() { NAMES+=("$1"); RESULTS+=("$2"); DETAILS+=("$3"); }

# run_with_timeout <secs> <logfile> <cmd...>   (macOS has no coreutils timeout)
run_with_timeout() {
  local secs="$1" log="$2"; shift 2
  ( exec "$@" >"$log" 2>&1 ) &
  local pid=$! waited=0
  while kill -0 "$pid" 2>/dev/null; do
    sleep 1
    waited=$((waited + 1))
    if [ "$waited" -ge "$secs" ]; then
      note "TIMEOUT after ${secs}s — killing pid $pid"
      kill -9 "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      return 124
    fi
  done
  wait "$pid"
}

# ── Preflight ──────────────────────────────────────────────────────────────
run_preflight() {
  local rc n_scn
  local ilog="$RUN_DIR/preflight-import.log"
  note "preflight: (re)importing assets headless"
  run_with_timeout 240 "$ilog" "$GODOT" --headless --path "$PROJ" --import
  rc=$?
  if [ "$rc" -ne 0 ]; then
    record preflight FAIL "--import exited $rc (log: $ilog)"
    return 1
  fi
  # The empty-.godot/imported scar: every GLB must have produced a .scn.
  n_scn=$(ls "$PROJ/.godot/imported" 2>/dev/null | grep -c '\.scn$')
  if [ "${n_scn:-0}" -lt 9 ]; then
    record preflight FAIL "only ${n_scn:-0} imported .scn files (need 9: 5 characters + 2 anim libs + 2 tower parts)"
    return 1
  fi
  note "preflight: import artifacts OK ($n_scn scenes)"

  local h="$RUN_DIR/home-preflight"; mkdir -p "$h"
  local blog="$RUN_DIR/preflight-boot.log"
  note "preflight: headless boot (--quit) checking for script/parse errors"
  HOME="$h" run_with_timeout 90 "$blog" "$GODOT" --headless --path "$PROJ" --quit
  rc=$?
  if [ "$rc" -ne 0 ]; then
    record preflight FAIL "headless boot exited $rc (log: $blog)"
    return 1
  fi
  if grep -Eq 'SCRIPT ERROR|Parse Error' "$blog"; then
    record preflight FAIL "headless boot printed SCRIPT ERROR/Parse Error (log: $blog)"
    return 1
  fi
  record preflight PASS "imported=$n_scn scenes · headless boot clean"
}

# ── Headless test suites (Gate A) ──────────────────────────────────────────
run_tests() {
  local log="$RUN_DIR/engine-tests.log" rc
  note "tests: chess engine suite headless"
  run_with_timeout 300 "$log" "$GODOT" --headless --path "$PROJ" -s res://tests/run_tests.gd
  rc=$?
  if grep -Eq 'Parse Error|Failed to load script' "$log"; then
    record engine-tests FAIL "suite failed to compile — no checks ran (log: $log)"
    return 1
  fi
  if [ "$rc" -eq 0 ] && grep -q 'RESULT: ALL GREEN' "$log"; then
    record engine-tests PASS "$(grep -m1 '^TOTAL:' "$log")"
    return 0
  fi
  record engine-tests FAIL "exit=$rc $(grep -m1 'FAILED:' "$log" || true) (log: $log)"
  return 1
}

run_suite() {  # <name> <res://script> [expected-assertions]  (suite exits 0 = green)
  local name="$1" script="$2" want="${3:-}"
  local log="$RUN_DIR/suite-$name.log" rc got
  note "tests: $name suite headless"
  run_with_timeout 300 "$log" "$GODOT" --headless --path "$PROJ" -s "$script"
  rc=$?
  # A suite script that fails to COMPILE never runs a single check — and
  # `godot -s` still exits 0, so the exit code alone would record PASS on a
  # suite that did nothing (2026-08-08: a typo in test_costumes.gd reported
  # green). Parse failures are their own FAIL lane.
  if grep -Eq 'Parse Error|Failed to load script' "$log"; then
    record "$name" FAIL "suite failed to compile — no checks ran (log: $log)"
    return 1
  fi
  if [ "$rc" -ne 0 ]; then
    record "$name" FAIL "exit=$rc (log: $log)"
    return 1
  fi
  # An assertion COUNT, checked, for suites that print one. Exit 0 says
  # "nothing that ran went red"; it says nothing about how much ran. This
  # header's own counts for the two XR suites had drifted to roughly half the
  # real number (2026-08-10 adversarial audit) — describing a version of those
  # files that no longer existed — and nothing noticed, because a number in a
  # comment is not a check. Now the suite prints ASSERTIONS=<n> and a
  # mismatch with the count written above is a FAIL, so the header cannot
  # drift again and neither can a silently gutted suite.
  if [ -n "$want" ]; then
    got=$(grep -Eo '^ASSERTIONS=[0-9]+' "$log" | tail -1 | cut -d= -f2)
    if [ "$got" != "$want" ]; then
      record "$name" FAIL "assertion count drifted: run_e2e.sh's header says $want, the suite ran ${got:-none} (log: $log)"
      return 1
    fi
  fi
  record "$name" PASS "exit 0${want:+, $want assertions}"
  return 0
}

# ── One windowed scenario launch ───────────────────────────────────────────
run_scenario() {  # <name> [extra user args...]
  local name="$1"; shift
  local log="$RUN_DIR/scenario-$name.log"
  local h="$RUN_DIR/home-$name"; mkdir -p "$h"
  local art="$ART_ROOT/$name"
  rm -rf "$art"; mkdir -p "$art"
  note "scenario '$name': windowed game launch (a game window will appear briefly)"
  HOME="$h" run_with_timeout "$SCENARIO_TIMEOUT" "$log" \
    "$GODOT" --path "$PROJ" --resolution 1280x720 --position 80,80 \
    -- "--e2e=$name" "--e2e-artifacts=$art" "$@"
  local rc=$? steps
  steps=$(grep -c '^E2E PASS' "$log")
  if grep -Eq 'SCRIPT ERROR|Parse Error' "$log"; then
    record "$name" FAIL "SCRIPT ERROR/Parse Error in run log (log: $log)"
    return 1
  fi
  if [ "$rc" -eq 0 ] && ! grep -q '^E2E FAIL' "$log"; then
    record "$name" PASS "$steps steps · artifacts: $art"
    return 0
  fi
  local why
  why=$(grep -m1 '^E2E FAIL' "$log" || echo "exit=$rc, no E2E FAIL line")
  record "$name" FAIL "$why (log: $log)"
  return 1
}

# ── Main ───────────────────────────────────────────────────────────────────
if [ ! -x "$GODOT" ]; then note "Godot binary missing: $GODOT"; exit 2; fi
STEPS=("$@")
[ ${#STEPS[@]} -eq 0 ] && STEPS=(preflight tests boot orientation board-truth \
  board-moves move duel castle enpassant promote slowmo kills music banter \
  dragon-live tournament trial trial-concede trial-win oracle-mock oracle-modes undo \
  net-hall fullgame showcase)

SUITE_RC=0
for step in "${STEPS[@]}"; do
  case "$step" in
    preflight) run_preflight || SUITE_RC=1 ;;
    tests)
      run_tests || SUITE_RC=1
      run_suite tournament-suite res://tests/test_tournament.gd || SUITE_RC=1
      run_suite cinematics-suite res://tests/test_cinematics.gd || SUITE_RC=1
      run_suite ds4-suite res://tests/test_ds4_opponent.gd || SUITE_RC=1
      run_suite uci-suite res://tests/test_uci_engine.gd || SUITE_RC=1
      run_suite music-suite res://tests/test_music.gd || SUITE_RC=1
      run_suite banter-suite res://tests/test_banter.gd || SUITE_RC=1
      run_suite dragon-suite res://tests/test_dragon.gd || SUITE_RC=1
      run_suite duel-facing-suite res://tests/test_duel_facing.gd || SUITE_RC=1
      run_suite kill-styles-suite res://tests/test_kill_styles.gd || SUITE_RC=1
      run_suite costumes-suite res://tests/test_costumes.gd || SUITE_RC=1
      run_suite net-suite res://tests/test_net.gd || SUITE_RC=1
      run_suite promotion-suite res://tests/test_promotion.gd || SUITE_RC=1
      run_suite minigame-suite res://tests/test_minigame.gd || SUITE_RC=1
      run_suite trial-wiring-suite res://tests/test_trial_wiring.gd || SUITE_RC=1
      # The two XR suites carry their expected assertion count (see run_suite
      # and this file's header): exit 0 alone would not notice a suite that
      # quietly stopped running half its checks.
      run_suite visionos-boot-suite res://tests/test_visionos_boot.gd 46 || SUITE_RC=1
      run_suite xr-rig-suite res://tests/test_xr_rig.gd 35 || SUITE_RC=1
      ;;
    boot)      run_scenario boot || SUITE_RC=1 ;;
    orientation) run_scenario orientation "--debug-coords" || SUITE_RC=1 ;;
    board-truth) run_scenario board-truth || SUITE_RC=1 ;;
    board-moves) run_scenario board-moves "--e2e-fen=$BOARD_FEN" || SUITE_RC=1 ;;
    move)      run_scenario move || SUITE_RC=1 ;;
    duel)      run_scenario duel "--e2e-fen=$DUEL_FEN" || SUITE_RC=1 ;;
    castle)    run_scenario castle "--e2e-fen=$CASTLE_FEN" || SUITE_RC=1 ;;
    enpassant) run_scenario enpassant "--e2e-fen=$EP_FEN" || SUITE_RC=1 ;;
    promote)   SCENARIO_TIMEOUT=200 run_scenario promote "--e2e-fen=$PROMOTE_FEN" \
                 "--e2e-timeout=180" || SUITE_RC=1 ;;
                 # four promotions, each with its 2.2 s flourish, an AI reply
                 # and a take-back in between
    slowmo)    run_scenario slowmo "--e2e-fen=$DUEL_FEN" || SUITE_RC=1 ;;
    kills)     SCENARIO_TIMEOUT=170 run_scenario kills "--e2e-fen=$KILLS_FEN" \
                 "--e2e-timeout=150" || SUITE_RC=1 ;;
                 # six duels back to back, each with its own ~5.5 s cinematic
    music)     run_scenario music "--e2e-fen=$DUEL_FEN" || SUITE_RC=1 ;;
    banter)    run_scenario banter "--e2e-fen=$BANTER_FEN" || SUITE_RC=1 ;;
    dragon-live) run_scenario dragon-live "--e2e-fen=$DRAGON_FEN" \
                   "--e2e-timeout=90" || SUITE_RC=1 ;;
    tournament) SCENARIO_TIMEOUT=170 run_scenario tournament \
                  "--e2e-fen=$TOURN_FEN" "--e2e-timeout=150" || SUITE_RC=1 ;;
    trial)     SCENARIO_TIMEOUT=260 run_scenario trial "--e2e-fen=$TRIAL_FEN" \
                 "--e2e-timeout=240" || SUITE_RC=1 ;;
                 # a REAL-PACED duel: the wyrm does not lose patience for 70 s
                 # and then eats the arena a ring at a time. Shortening the
                 # fuse for the test would be testing a mode nobody ships.
    trial-concede) SCENARIO_TIMEOUT=120 run_scenario trial-concede \
                 "--e2e-fen=$TRIAL_FEN" "--e2e-timeout=100" || SUITE_RC=1 ;;
                 # the skip path — Esc costs the round, never the process
    trial-win) SCENARIO_TIMEOUT=120 run_scenario trial-win \
                 "--e2e-fen=$TRIAL_FEN" "--e2e-timeout=100" || SUITE_RC=1 ;;
                 # the ADVANCE path: the bracket moves on and the card must
                 # offer the next round instead of sending the winner home
    oracle-mock) run_scenario oracle-mock "--e2e-timeout=80" || SUITE_RC=1 ;;
    oracle-modes) run_scenario oracle-modes "--e2e-fen=$COUNSEL_FEN" \
                   "--e2e-timeout=90" || SUITE_RC=1 ;;
    undo)      SCENARIO_TIMEOUT=170 run_scenario undo "--e2e-fen=$DUEL_FEN" \
                 "--e2e-timeout=150" || SUITE_RC=1 ;;
                 # 4 scripted duel rounds + a 4 s held oracle reply
    fullgame)  SCENARIO_TIMEOUT=230 run_scenario fullgame \
                 "--e2e-fen=$FULLGAME_FEN" "--e2e-timeout=210" || SUITE_RC=1 ;;
    net-hall)  SCENARIO_TIMEOUT=120 run_scenario net-hall "--e2e-timeout=100" \
                 || SUITE_RC=1 ;;
                 # the unreachable-host error takes ENet's own connect timeout
    ## THE PERFORMANCE GATE. Not part of the default sequence: it is the one
    ## step whose numbers a co-tenant can invalidate, so it is opt-in
    ## (`./run_e2e.sh perf`) and it refuses to measure beside another Godot
    ## on this project rather than producing a number nobody can trust. Its
    ## deterministic ceilings (draw calls, primitives, the match-load stall)
    ## are enforced even on a busy machine; the frame-timing ones are skipped
    ## and SAID to be skipped.
    perf)      "$SCRIPT_DIR/run_perf.sh" gate || SUITE_RC=1
               record perf "$([ "$SUITE_RC" -eq 0 ] && echo PASS || echo FAIL)" \
                 "run_perf.sh gate (ceilings enforced; see its own run dir)" ;;
    showcase)  SCENARIO_TIMEOUT=170 run_scenario showcase "--e2e-fen=$DUEL_FEN" \
                 "--e2e-timeout=150" || SUITE_RC=1 ;;
                 # 45 s soak + tableau is ~56 s alone but needs headroom at
                 # the tail of a full sequential run (watchdogged at 90 s
                 # under end-of-suite load, 2026-08-08)
    *) note "unknown step '$step' (use preflight|tests|boot|orientation|board-truth|board-moves|move|duel|castle|enpassant|promote|slowmo|kills|music|banter|dragon-live|tournament|trial|trial-concede|trial-win|oracle-mock|oracle-modes|undo|net-hall|fullgame|showcase|perf)"; SUITE_RC=1 ;;
  esac
done

ELAPSED=$(( $(date +%s) - SUITE_START ))
echo
echo "════════════ E2E SUMMARY (${ELAPSED}s, logs: $RUN_DIR) ════════════"
printf '%-11s %-6s %s\n' "STEP" "RESULT" "DETAIL"
for i in "${!NAMES[@]}"; do
  printf '%-11s %-6s %s\n' "${NAMES[$i]}" "${RESULTS[$i]}" "${DETAILS[$i]}"
done
echo "═══════════════════════════════════════════════════════════════════"
exit "$SUITE_RC"
