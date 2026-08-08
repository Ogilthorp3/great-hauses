#!/usr/bin/env bash
# run_e2e.sh — Great Houses in-engine E2E suite.
#
# Steps:
#   preflight  import-artifacts check (the empty-.godot/imported scar) +
#              headless boot with zero SCRIPT ERROR/Parse Error
#   tests      the chess-engine test suite (79 checks) headless — Gate A
#   boot       windowed: scene loads, 32 pieces standing        — Gate B
#   move       windowed: click e2->e4, AI replies within 30 s   — Gate B
#   duel       windowed: scripted capture duel via clicks       — Gate B
#   castle     windowed: O-O by clicks, king+rook views land    — Gate B
#   promote    windowed: promotion by clicks, queen view spawns — Gate B
#   showcase   windowed 30 s zero-error soak + beauty shots     — Gate C
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
# Promotion-ready: a7 pawn promotes on the next move.
PROMOTE_FEN="7k/P7/8/8/8/8/8/K7 w - - 0 1"

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

# ── Engine test suite (Gate A) ─────────────────────────────────────────────
run_tests() {
  local log="$RUN_DIR/engine-tests.log" rc
  note "tests: chess engine suite headless"
  run_with_timeout 300 "$log" "$GODOT" --headless --path "$PROJ" -s res://tests/run_tests.gd
  rc=$?
  if [ "$rc" -eq 0 ] && grep -q 'RESULT: ALL GREEN' "$log"; then
    record tests PASS "$(grep -m1 '^TOTAL:' "$log")"
    return 0
  fi
  record tests FAIL "exit=$rc $(grep -m1 'FAILED:' "$log" || true) (log: $log)"
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
[ ${#STEPS[@]} -eq 0 ] && STEPS=(preflight tests boot move duel castle promote showcase)

SUITE_RC=0
for step in "${STEPS[@]}"; do
  case "$step" in
    preflight) run_preflight || SUITE_RC=1 ;;
    tests)     run_tests     || SUITE_RC=1 ;;
    boot)      run_scenario boot || SUITE_RC=1 ;;
    move)      run_scenario move || SUITE_RC=1 ;;
    duel)      run_scenario duel "--e2e-fen=$DUEL_FEN" || SUITE_RC=1 ;;
    castle)    run_scenario castle "--e2e-fen=$CASTLE_FEN" || SUITE_RC=1 ;;
    promote)   run_scenario promote "--e2e-fen=$PROMOTE_FEN" || SUITE_RC=1 ;;
    showcase)  run_scenario showcase "--e2e-fen=$DUEL_FEN" "--e2e-timeout=55" \
                 || SUITE_RC=1 ;;
    *) note "unknown step '$step' (use preflight|tests|boot|move|duel|castle|promote|showcase)"; SUITE_RC=1 ;;
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
