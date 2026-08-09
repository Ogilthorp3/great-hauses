#!/usr/bin/env bash
# run_perf.sh — Great Houses performance harness (the regression gate).
#
# THE INSTRUMENT LIES UNTIL PROVEN OTHERWISE.
#
# This project has already been burned once by a benchmark that was the
# problem: an e2e run that takes screenshots does a SYNCHRONOUS framebuffer
# readback per shot (~100 MB at 6K), which stalled frames to single digits.
# That number was read as a game defect and "fixed" by halving the render
# resolution. So this runner:
#
#   * takes NO screenshots in any measuring step (`contaminated` exists only
#     to reproduce the trap on demand, as evidence);
#   * runs each configuration TWICE by default so reproducibility is shown,
#     not asserted;
#   * REFUSES to measure while another Godot is running on this project (an
#     e2e suite or a second agent's window is a GPU co-tenant, and a number
#     taken through one is not a number). `--force` overrides, and the log
#     records that it was forced;
#   * clocks frames on the wall clock inside the engine, never on
#     `_process(delta)` — every cinematic here bends `Engine.time_scale`;
#   * verifies the ACTUAL framebuffer pixel count against the target and
#     fails loudly on a mismatch, because "1080p" on a HiDPI Mac is 2x what
#     the flag says.
#
# Steps:
#   preflight     --import (exit code CHECKED) + import-artifact census
#   1080p         perf scenario, ~1920x1080 real pixels, windowed   x2
#   6k            perf scenario, native 6016x3384 real pixels        x2
#   contaminated  6k WITH screenshots — the documented trap, never a number
#   ablate-1080p  controlled A/B sweep at 1080p (measured cost ranking)
#   ablate-6k     controlled A/B sweep at 6K
#
# THERE IS NO 60 Hz WALL. THERE IS A NEIGHBOUR.
#
# This header used to assert a "60 Hz macOS presentation wall" — that
# `--disable-vsync` cannot defeat macOS presentation pacing, so every
# millisecond here is a display measurement and no optimization can move it.
# It cited one empty-scene run reading 16.535 ms/frame as proof.
#
# That was not a wall. It was the owner's live Godot game rendering on the
# same GPU. Same binary, same scene, same window, one variable:
#
#     owner's live game RUNNING     ~60 fps / 16.67 ms
#     owner's live game SUSPENDED   232-339 fps / 3-4 ms  (1080p AND 6K)
#
# The 232-339 fps runs are in test_e2e/artifacts/perf/ from 2026-08-09 07:55
# to 08:10, and one of them recorded the mechanism in its own cotenants.txt:
# a `kill -CONT <pid>` sleeper, i.e. the neighbour had been SIGSTOPped to get
# a quiet machine. DO NOT DO THAT — see the rule below.
#
# Consequences, and they are the whole point of this file:
#   * milliseconds ARE real and ARE reported. They are comparable only
#     between runs whose PERF COTENANT blocks match.
#   * draws / prims stay the ranking for anything geometric: they are
#     deterministic and a busy GPU cannot move them.
#   * drops (>= 25 ms) is the stutter the player feels. Its floor is NOT
#     zero — run `./run_perf.sh noise` and read the instrument's own cost.
#
# THE RULE: never take a timing measurement without recording what else was
# rendering, and never quiet the machine by suspending or killing a process
# you did not start. The owner's game is the owner's.
#
# PERF_LOAD IS RETIRED. It supersampled the 3D target to lift the frame clear
# of the (imaginary) refresh wall so that a GEOMETRY A/B could be read in ms.
# Supersampling multiplies FILL and leaves draw calls, primitives, skinning
# and shadow submission untouched — so it measured the wrong axis by
# construction, and the 5.12 ms it attributed to the sun's cascade was a fill
# number wearing a geometry label. To read a geometry change, read prims.
#
# Env knobs:
#   PERF_ABL=a,b,c   sweep only these ablation levers (default: all ten)
#
# Usage:
#   ./run_perf.sh                       # preflight 1080p 6k contaminated
#   ./run_perf.sh noise                 # the instrument's own floor + control
#   ./run_perf.sh load                  # the match-load stall, 4 transitions
#   ./run_perf.sh vfx                   # the dracarys torrent / ashfall
#   ./run_perf.sh gate                  # the regression gate (exit 1 on breach)
#   ./run_perf.sh ablate-6k --force
#   PERF_ABL=pssm4 ./run_perf.sh ablate-1080p --once
#
# Logs land in test_e2e/artifacts/perf/<stamp>/ and the summary prints the
# per-phase table straight out of them.

set -u

GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(dirname "$SCRIPT_DIR")"
OUT_ROOT="$PROJ/test_e2e/artifacts/perf"
STAMP=$(date +%Y%m%d-%H%M%S)
RUN_DIR="$OUT_ROOT/$STAMP"

# The measured position: after 1.e4 d5, all 32 fighters are still standing and
# White has exactly one capture (exd5) — a full board AND an immediate duel
# cinematic, which is what makes this one scenario cover both the steady state
# and the worst moment.
PERF_FEN="rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2"

# THE CEREMONY'S POSITION. Mate-in-1 (Ra1-a8#) with three loser pawns still
# standing, so the ashfall has bodies to burn — the same FEN the dragon-live
# e2e scenario uses, for the same reason. Rxa8# ends it, the checkmate
# cinematic runs, and the dracarys torrent chains off the king's death.
VFX_FEN="6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1"

# macOS reports window sizes in POINTS; this display draws 2 device pixels per
# point. --resolution therefore takes half the pixels we actually want. The
# harness measures the real framebuffer and this script asserts it, so if the
# scale ever changes the run FAILS instead of quietly measuring the wrong thing.
CONTENT_SCALE=2
W1080=$((1920 / CONTENT_SCALE)); H1080=$((1080 / CONTENT_SCALE))
W6K=$((6016 / CONTENT_SCALE));   H6K=$((3384 / CONTENT_SCALE))
PX_1080=$((1920 * 1080))
PX_6K=$((6016 * 3384))

REPEATS=2
FORCE=0
GATED=0
STEPS=()
for a in "$@"; do
  case "$a" in
    --force)   FORCE=1 ;;
    --once)    REPEATS=1 ;;
    --gate)    GATED=1 ;;
    *)         STEPS+=("$a") ;;
  esac
done
[ ${#STEPS[@]} -eq 0 ] && STEPS=(preflight 1080p 6k contaminated)
## `gate` is the regression step: the shortest run that still exercises the
## board, the match load and the steady state, with the ceilings enforced.
if [ "${STEPS[0]}" = "gate" ]; then
  STEPS=(preflight noise load 1080p)
  REPEATS=1
  GATED=1
fi

mkdir -p "$RUN_DIR"
note() { printf '[perf] %s\n' "$*"; }

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

## A co-tenant on the GPU invalidates every number this harness prints. Only
## Godot processes running THIS project count — the owner's other games are
## their business, but they are also recorded, because a number taken beside
## one deserves that footnote.
## MATCH THE EXECUTABLE, NEVER THE COMMAND TEXT.
## This used to be `pgrep -fl "Godot.*great-houses-chess"`, which matches the
## WHOLE command line of every process — including a sibling agent's shell
## running a heredoc that merely MENTIONS Godot and this project path. It
## reported 47 co-tenants when the true answer was 0, and refused to measure.
## A monitor that matches on text matches the people talking about it, so the
## test is on `comm` (the executable) and the project is looked for only in
## that process's own arguments.
godot_procs() {   # -> "<pid> <args>" per line, real Godot processes only
  ## argv[0], NOT `comm`: macOS truncates comm to the column width
  ## ("/Applications/Go"), so matching on it silently finds nothing.
  ps -Ao pid=,%cpu=,args= | awk '$3 ~ /\/Godot$/'
}

guard_cotenants() {
  local all mine others
  all=$(godot_procs)
  mine=$(printf '%s\n' "$all" | grep -c "great-houses-chess" || true)
  others=$(printf '%s\n' "$all" | grep -v "great-houses-chess" | grep -c . || true)
  mine=${mine:-0}; others=${others:-0}
  echo "cotenants_same_project=$mine cotenants_other=$others" > "$RUN_DIR/cotenants.txt"
  printf '%s\n' "$all" >> "$RUN_DIR/cotenants.txt" 2>/dev/null
  if [ "$mine" -gt 0 ]; then
    if [ "$FORCE" -eq 1 ]; then
      note "WARNING: $mine other Godot process(es) on this project — FORCED, numbers are contaminated"
    else
      note "REFUSING to measure: $mine other Godot process(es) are running this project."
      note "  (an e2e suite or a second agent's window is a GPU co-tenant)"
      note "  wait for them, or re-run with --force and treat the numbers as dirty"
      return 1
    fi
  fi
  [ "$others" -gt 0 ] && note "note: $others unrelated Godot process(es) running (recorded in cotenants.txt)"
  return 0
}

run_preflight() {
  local log="$RUN_DIR/preflight-import.log" rc n
  note "preflight: headless --import"
  run_with_timeout 300 "$log" "$GODOT" --headless --path "$PROJ" --import
  rc=$?
  if [ "$rc" -ne 0 ]; then
    note "FAIL preflight: --import exited $rc (log: $log)"
    return 1
  fi
  n=$(ls "$PROJ/.godot/imported" 2>/dev/null | grep -c '\.scn$')
  if [ "${n:-0}" -lt 9 ]; then
    note "FAIL preflight: only ${n:-0} imported .scn files"
    return 1
  fi
  note "preflight OK — --import exit 0, $n imported scenes"
}

# run_one <label> <mode> <win_w> <win_h> <expect_px> <shots 0|1> <timeout>
run_one() {
  local label="$1" mode="$2" w="$3" h="$4" expect="$5" shots="$6" tmo="$7"
  local log="$RUN_DIR/$label.log"
  local home="$RUN_DIR/home-$label"; mkdir -p "$home"
  local art="$RUN_DIR/shots-$label"
  local shot_args=()
  if [ "$shots" = "1" ]; then
    mkdir -p "$art"
    shot_args=("--perf-shots=1" "--perf-artifacts=$art")
  fi
  note "run '$label': mode=$mode window=${w}x${h} pts (target ${expect} px)"
  # The co-tenant's load is part of the evidence, not a footnote: a Godot game
  # already rendering on this GPU is the single largest uncontrolled variable
  # in every number below.
  ps -Ao pid=,%cpu=,args= | awk '$3 ~ /\/Godot$/' > "$RUN_DIR/$label.cotenant-before.txt"
  HOME="$home" run_with_timeout "$tmo" "$log" \
    "$GODOT" --path "$PROJ" --scene res://test_e2e/perf_boot.tscn \
    --resolution "${w}x${h}" --position 0,0 \
    --disable-vsync --max-fps 0 --delta-smoothing disable \
    -- "--perf=$mode" "--perf-label=$label" "--perf-timeout=$((tmo - 15))" \
       "--e2e-fen=${RUN_FEN:-$PERF_FEN}" ${PERF_ABL:+"--perf-abl=$PERF_ABL"} \
       "${shot_args[@]+"${shot_args[@]}"}"
  local rc=$?
  ps -Ao pid=,%cpu=,args= | awk '$3 ~ /\/Godot$/' > "$RUN_DIR/$label.cotenant-after.txt"
  if grep -Eq 'SCRIPT ERROR|Parse Error' "$log"; then
    note "FAIL $label: SCRIPT ERROR/Parse Error (log: $log)"
    return 1
  fi
  local px
  px=$(grep -m1 '^PERF ENV' "$log" | sed -n 's/.* px=\([0-9]*\) .*/\1/p')
  if [ -z "$px" ]; then
    note "FAIL $label: no PERF ENV line — the harness never started (log: $log)"
    return 1
  fi
  # ±3 % on the pixel count: window decorations and the menu bar can shave a
  # row, a 2x scale change cannot hide inside that.
  local lo=$(( expect * 97 / 100 )) hi=$(( expect * 103 / 100 ))
  if [ "$px" -lt "$lo" ] || [ "$px" -gt "$hi" ]; then
    note "FAIL $label: framebuffer is $px px, expected ~$expect px — the"
    note "  resolution flag did NOT produce the intended render target"
    return 1
  fi
  if ! grep -q '^PERF DONE .* exit=0' "$log"; then
    note "FAIL $label: run did not finish clean (rc=$rc) — $(grep -m1 '^PERF FAIL' "$log" || echo 'no PERF FAIL line')"
    return 1
  fi
  note "OK $label — $px px, $(grep -c '^PERF phase=' "$log") sampled seconds (log: $log)"
}

# ── main ───────────────────────────────────────────────────────────────────
if [ ! -x "$GODOT" ]; then note "Godot binary missing: $GODOT"; exit 2; fi
RC=0
note "run dir: $RUN_DIR"
for step in "${STEPS[@]}"; do
  case "$step" in
    preflight) run_preflight || RC=1 ;;
    noise)
      guard_cotenants || { RC=1; continue; }
      run_one "noise-1080p" noise "$W1080" "$H1080" "$PX_1080" 0 90 || RC=1 ;;
    load)
      guard_cotenants || { RC=1; continue; }
      run_one "load-1080p" load "$W1080" "$H1080" "$PX_1080" 0 240 || RC=1 ;;
    vfx)
      guard_cotenants || { RC=1; continue; }
      RUN_FEN="$VFX_FEN" run_one "vfx-1080p" vfx "$W1080" "$H1080" "$PX_1080" 0 240 || RC=1 ;;
    vfx-6k)
      guard_cotenants || { RC=1; continue; }
      RUN_FEN="$VFX_FEN" run_one "vfx-6k" vfx "$W6K" "$H6K" "$PX_6K" 0 300 || RC=1 ;;
    load-6k)
      guard_cotenants || { RC=1; continue; }
      run_one "load-6k" load "$W6K" "$H6K" "$PX_6K" 0 300 || RC=1 ;;
    1080p)
      guard_cotenants || { RC=1; continue; }
      for i in $(seq 1 $REPEATS); do
        run_one "1080p-run$i" perf "$W1080" "$H1080" "$PX_1080" 0 200 || RC=1
      done ;;
    6k)
      guard_cotenants || { RC=1; continue; }
      for i in $(seq 1 $REPEATS); do
        run_one "6k-run$i" perf "$W6K" "$H6K" "$PX_6K" 0 240 || RC=1
      done ;;
    contaminated)
      guard_cotenants || { RC=1; continue; }
      # DELIBERATELY DIRTY. Never quote a number from this log as a game
      # measurement — it exists so the trap is documented, not merely avoided.
      run_one "6k-CONTAMINATED-shots" perf "$W6K" "$H6K" "$PX_6K" 1 300 || RC=1
      run_one "1080p-CONTAMINATED-shots" perf "$W1080" "$H1080" "$PX_1080" 1 300 || RC=1 ;;
    ablate-1080p)
      guard_cotenants || { RC=1; continue; }
      run_one "ablate-1080p" ablate "$W1080" "$H1080" "$PX_1080" 0 420 || RC=1 ;;
    ablate-6k)
      guard_cotenants || { RC=1; continue; }
      run_one "ablate-6k" ablate "$W6K" "$H6K" "$PX_6K" 0 420 || RC=1 ;;
    *) note "unknown step '$step'"; RC=1 ;;
  esac
done

note "──── logs in $RUN_DIR ────"

## THE GATE. Until now this harness could only ever print; a regression could
## walk straight past it because nothing it produced was allowed to be red.
## perf_table.py --gate reads the same logs and exits 1 on a breached ceiling.
if [ "$GATED" -eq 1 ]; then
  echo
  for f in "$RUN_DIR"/*.log; do
    case "$f" in *preflight-import.log|*CONTAMINATED*) continue ;; esac
    python3 "$SCRIPT_DIR/perf_table.py" --gate "$f" || RC=1
  done
fi

echo "$RUN_DIR"
exit "$RC"
