#!/usr/bin/env bash
# run_e2e.sh — Great Houses in-engine E2E suite.
#
# Steps:
#   preflight   import-artifacts check (the empty-.godot/imported scar) +
#               headless boot with zero SCRIPT ERROR/Parse Error
#   tests       ALL headless suites — engine (79), tournament, cinematics
#               time-restore, DS4 opponent (mock+live, 3 modes),
#               UciEngine/stockfish client, music (104), banter (93),
#               dragon spectator/ASHFALL, duel face-off, costumes
#               (273 — mounted knights and pawn helms included),
#               head-to-head protocol (110 — host authority, the
#               illegal-move-from-client refusal, the cinematic
#               gate)                                             — Gate A
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
#   promote     windowed: promotion by clicks, queen view spawns — Gate B
#   slowmo      windowed: duel director activation, time dip, skip-on-click
#   tournament  windowed: 3 scripted mates to the throne, bracket + banner
#               re-dress asserts, championship panel
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
# Every windowed scenario navigates the Hall of Banners (house select) by
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
# Castling-ready: White can O-O immediately (the h2 pawn keeps material legal).
CASTLE_FEN="4k3/8/8/8/8/8/7P/4K2R w K - 0 1"
# En-passant-ready: Black just double-stepped d7d5 past the e5 pawn; exd6
# e.p. is the only capture, and Black keeps ONLY the king so nothing can
# recapture — the visual end-state (pawn d6, d5+e5 empty) is unambiguous.
EP_FEN="4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2"
# Promotion-ready: a7 pawn promotes on the next move.
PROMOTE_FEN="7k/P7/8/8/8/8/8/K7 w - - 0 1"
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
# king's own escape) and the mated house leaves three pawns standing —
# fuel for the ASHFALL pyre.
DRAGON_FEN="6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1"

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

run_suite() {  # <name> <res://script>  (suite exits 0 = green)
  local name="$1" script="$2"
  local log="$RUN_DIR/suite-$name.log" rc
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
  if [ "$rc" -eq 0 ]; then
    record "$name" PASS "exit 0"
    return 0
  fi
  record "$name" FAIL "exit=$rc (log: $log)"
  return 1
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
  board-moves move duel castle enpassant promote slowmo music banter \
  dragon-live tournament oracle-mock oracle-modes undo net-hall fullgame showcase)

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
      run_suite costumes-suite res://tests/test_costumes.gd || SUITE_RC=1
      run_suite net-suite res://tests/test_net.gd || SUITE_RC=1
      ;;
    boot)      run_scenario boot || SUITE_RC=1 ;;
    orientation) run_scenario orientation "--debug-coords" || SUITE_RC=1 ;;
    board-truth) run_scenario board-truth || SUITE_RC=1 ;;
    board-moves) run_scenario board-moves "--e2e-fen=$BOARD_FEN" || SUITE_RC=1 ;;
    move)      run_scenario move || SUITE_RC=1 ;;
    duel)      run_scenario duel "--e2e-fen=$DUEL_FEN" || SUITE_RC=1 ;;
    castle)    run_scenario castle "--e2e-fen=$CASTLE_FEN" || SUITE_RC=1 ;;
    enpassant) run_scenario enpassant "--e2e-fen=$EP_FEN" || SUITE_RC=1 ;;
    promote)   run_scenario promote "--e2e-fen=$PROMOTE_FEN" || SUITE_RC=1 ;;
    slowmo)    run_scenario slowmo "--e2e-fen=$DUEL_FEN" || SUITE_RC=1 ;;
    music)     run_scenario music "--e2e-fen=$DUEL_FEN" || SUITE_RC=1 ;;
    banter)    run_scenario banter "--e2e-fen=$BANTER_FEN" || SUITE_RC=1 ;;
    dragon-live) run_scenario dragon-live "--e2e-fen=$DRAGON_FEN" \
                   "--e2e-timeout=90" || SUITE_RC=1 ;;
    tournament) SCENARIO_TIMEOUT=170 run_scenario tournament \
                  "--e2e-fen=$TOURN_FEN" "--e2e-timeout=150" || SUITE_RC=1 ;;
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
    showcase)  SCENARIO_TIMEOUT=170 run_scenario showcase "--e2e-fen=$DUEL_FEN" \
                 "--e2e-timeout=150" || SUITE_RC=1 ;;
                 # 45 s soak + tableau is ~56 s alone but needs headroom at
                 # the tail of a full sequential run (watchdogged at 90 s
                 # under end-of-suite load, 2026-08-08)
    *) note "unknown step '$step' (use preflight|tests|boot|orientation|board-truth|board-moves|move|duel|castle|enpassant|promote|slowmo|music|banter|dragon-live|tournament|oracle-mock|oracle-modes|undo|net-hall|fullgame|showcase)"; SUITE_RC=1 ;;
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
