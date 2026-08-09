#!/usr/bin/env bash
# run_net_e2e.sh — THE head-to-head gate: two real Godot instances on this Mac
# play a real game against each other.
#
# A green unit suite (tests/test_net.gd) proves the protocol. It does NOT prove
# that two machines can play, so this script exists: it launches one --net-host
# and one --net-join process side by side, drives both through the synthesized
# input driver (real clicks on the real board), and then does the thing that
# actually catches desync — it DIFFS the FEN each instance printed after every
# single ply. If the two boards ever disagreed by one move, the diff says so
# and this script fails.
#
# The scripted game (see NET_FEN in test_e2e/e2e_driver.gd) walks:
#   a normal move each way · a CAPTURE (the slow-motion duel, both screens)
#   · an UNDERPROMOTION chosen on the JOINER through the promotion picker,
#     which has to survive the trip to the HOST'S validator (and is
#     load-bearing: a queen on that square would check White and make the
#     scripted mate illegal) · a CHECKMATE.
# Both instances also probe HOST AUTHORITY live: the joiner asks the host for
# illegal moves (wrong turn, illegal geometry) and must be refused with a
# reason while both boards stand still.
#
# Two windows appear side by side for ~2 minutes. Don't touch the mouse or
# keyboard while they're up, and don't let another window cover them (macOS
# stops drawing occluded windows and the screenshots go stale).
#
# Usage:  ./run_net_e2e.sh [--port N] [--keep]
#
# Artifacts: test_e2e/artifacts/net-host/*.png, .../net-join/*.png
# Logs:      test_e2e/artifacts/runs/<stamp>/scenario-net-{host,join}.log

set -u

GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(dirname "$SCRIPT_DIR")"
ART_ROOT="$PROJ/test_e2e/artifacts"
RUN_DIR="$ART_ROOT/runs/net-$(date +%Y%m%d-%H%M%S)"

PORT=7777
HOST_HOUSE="winterfang"     # White, hosts
JOIN_HOUSE="ashwyrm"        # Black, joins
# THE POSITION IS NOT DUPLICATED HERE. It used to be, and on 2026-08-09 the
# scripted game grew an underpromotion: the driver's const moved, this copy did
# not, and both instances played the old position until they walked off the end
# of their own move list. One source of truth — read it out of the driver, which
# is also what tests/test_promotion.gd walks move by move.
NET_FEN=$(sed -n 's/^const NET_FEN := "\(.*\)"$/\1/p' "$PROJ/test_e2e/e2e_driver.gd")
if [ -z "$NET_FEN" ]; then
  echo "[net-e2e] could not read NET_FEN out of test_e2e/e2e_driver.gd"; exit 2
fi
INSTANCE_TIMEOUT=210        # outer kill; the in-game watchdog is tighter
E2E_TIMEOUT=190

while [ $# -gt 0 ]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    *) echo "unknown flag '$1' (use --port N)"; exit 2 ;;
  esac
done

mkdir -p "$RUN_DIR"
note() { printf '[net-e2e] %s\n' "$*"; }

if [ ! -x "$GODOT" ]; then note "Godot binary missing: $GODOT"; exit 2; fi

HOST_LOG="$RUN_DIR/scenario-net-host.log"
JOIN_LOG="$RUN_DIR/scenario-net-join.log"
HOST_ART="$ART_ROOT/net-host"
JOIN_ART="$ART_ROOT/net-join"
rm -rf "$HOST_ART" "$JOIN_ART"
mkdir -p "$HOST_ART" "$JOIN_ART"
HOST_HOME="$RUN_DIR/home-host"; mkdir -p "$HOST_HOME"
JOIN_HOME="$RUN_DIR/home-join"; mkdir -p "$JOIN_HOME"

# Never inherit a half-dead listener from a previous run.
if command -v lsof >/dev/null 2>&1 && lsof -nP -iUDP:"$PORT" >/dev/null 2>&1; then
  note "WARNING: something is already bound to UDP $PORT — the host may fail to open it"
fi

note "launching HOST (White, $HOST_HOUSE) on port $PORT"
HOME="$HOST_HOME" "$GODOT" --path "$PROJ" --resolution 720x405 --position 30,90 \
  -- "--e2e=net-host" "--e2e-artifacts=$HOST_ART" "--e2e-timeout=$E2E_TIMEOUT" \
     "--net-host" "--net-side=white" "--net-house=$HOST_HOUSE" \
     "--net-port=$PORT" "--e2e-fen=$NET_FEN" \
  >"$HOST_LOG" 2>&1 &
HOST_PID=$!

sleep 8   # let the host finish booting and bind the port before anyone dials

note "launching JOIN (Black, $JOIN_HOUSE) -> 127.0.0.1:$PORT"
HOME="$JOIN_HOME" "$GODOT" --path "$PROJ" --resolution 720x405 --position 790,90 \
  -- "--e2e=net-join" "--e2e-artifacts=$JOIN_ART" "--e2e-timeout=$E2E_TIMEOUT" \
     "--net-join=127.0.0.1" "--net-house=$JOIN_HOUSE" "--net-port=$PORT" \
  >"$JOIN_LOG" 2>&1 &
JOIN_PID=$!

# Wait for both, with an outer kill. Only ever kills the two pids WE started.
waited=0
while kill -0 "$HOST_PID" 2>/dev/null || kill -0 "$JOIN_PID" 2>/dev/null; do
  sleep 1
  waited=$((waited + 1))
  if [ "$waited" -ge "$INSTANCE_TIMEOUT" ]; then
    note "TIMEOUT after ${waited}s — killing the two instances this script started"
    kill -9 "$HOST_PID" "$JOIN_PID" 2>/dev/null
    break
  fi
done
wait "$HOST_PID" 2>/dev/null; HOST_RC=$?
wait "$JOIN_PID" 2>/dev/null; JOIN_RC=$?

FAILED=0
fail() { note "FAIL: $*"; FAILED=1; }

# ── Per-instance verdicts ──────────────────────────────────────────────────
for pair in "host:$HOST_LOG:$HOST_RC" "join:$JOIN_LOG:$JOIN_RC"; do
  who="${pair%%:*}"; rest="${pair#*:}"; log="${rest%:*}"; rc="${rest##*:}"
  steps=$(grep -c '^E2E PASS' "$log" 2>/dev/null || echo 0)
  if grep -Eq 'SCRIPT ERROR|Parse Error' "$log"; then
    fail "$who printed SCRIPT ERROR/Parse Error (log: $log)"
  fi
  if grep -q '^E2E FAIL' "$log"; then
    fail "$who: $(grep -m1 '^E2E FAIL' "$log")"
  elif [ "$rc" -ne 0 ]; then
    fail "$who exited $rc with no E2E FAIL line (log: $log)"
  else
    note "$who OK — $steps steps passed"
  fi
done

# ── The cross-instance check: did the two boards ever disagree? ────────────
grep '^E2E NETFEN' "$HOST_LOG" | sed 's/^E2E NETFEN //' > "$RUN_DIR/fens-host.txt"
grep '^E2E NETFEN' "$JOIN_LOG" | sed 's/^E2E NETFEN //' > "$RUN_DIR/fens-join.txt"
N_HOST=$(wc -l < "$RUN_DIR/fens-host.txt" | tr -d ' ')
N_JOIN=$(wc -l < "$RUN_DIR/fens-join.txt" | tr -d ' ')
note "plies logged: host=$N_HOST join=$N_JOIN"
if [ "${N_HOST:-0}" -lt 5 ] || [ "${N_JOIN:-0}" -lt 5 ]; then
  fail "expected 5 synchronised plies per instance, got host=$N_HOST join=$N_JOIN"
fi
if ! diff -u "$RUN_DIR/fens-host.txt" "$RUN_DIR/fens-join.txt" > "$RUN_DIR/fen-diff.txt"; then
  fail "THE TWO BOARDS DIVERGED — see $RUN_DIR/fen-diff.txt"
  head -20 "$RUN_DIR/fen-diff.txt"
else
  note "every ply's FEN matched on both instances:"
  sed 's/^/         /' "$RUN_DIR/fens-host.txt"
fi

HOST_FINAL=$(grep -m1 '^E2E NETFINAL' "$HOST_LOG" | sed 's/^E2E NETFINAL //')
JOIN_FINAL=$(grep -m1 '^E2E NETFINAL' "$JOIN_LOG" | sed 's/^E2E NETFINAL //')
if [ -z "$HOST_FINAL" ] || [ "$HOST_FINAL" != "$JOIN_FINAL" ]; then
  fail "final positions differ: host='$HOST_FINAL' join='$JOIN_FINAL'"
else
  note "final position agreed on both: $HOST_FINAL"
fi

# ── Screenshots from BOTH instances ────────────────────────────────────────
for d in "$HOST_ART" "$JOIN_ART"; do
  n=$(ls "$d"/*.png 2>/dev/null | wc -l | tr -d ' ')
  if [ "${n:-0}" -lt 3 ]; then
    fail "only ${n:-0} screenshots in $d (want the seat, the duel and the mate)"
  else
    note "$(basename "$d"): $n screenshots"
    ls "$d" | sed 's/^/         /'
  fi
done

echo
echo "════════════ HEAD-TO-HEAD E2E ($RUN_DIR) ════════════"
if [ "$FAILED" -eq 0 ]; then
  echo "RESULT: GREEN — two instances played a real game, boards identical every ply"
else
  echo "RESULT: RED — see the failures above"
fi
echo "═════════════════════════════════════════════════════════════════"
exit "$FAILED"
