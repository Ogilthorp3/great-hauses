#!/usr/bin/env bash
# build.sh — one command to produce (and PROVE) a Great Houses release build.
#
#   ./tools/build/build.sh                 # windows + macos + verify
#   ./tools/build/build.sh windows         # just the .exe
#   ./tools/build/build.sh macos
#   ./tools/build/build.sh degrade         # platform-degradation suite only
#   ./tools/build/build.sh --out /tmp/dist windows
#
# Every step checks its exit code and every artifact is verified after the
# fact — an export that "succeeded" but shipped an empty pck or a broken
# autoload has burned us before, so the build refuses to call itself done
# until `file` and the pck index agree with what we intended to ship.
#
# Env overrides:  GODOT=/path/to/Godot   OUT=/path/to/dist

set -uo pipefail

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT="${OUT:-$(cd "$PROJ/.." && pwd)/great-houses-dist}"
TEMPLATE_ROOT="$HOME/Library/Application Support/Godot/export_templates"

WIN_PRESET="Windows Desktop"
MAC_PRESET="macOS"
WIN_OUT_NAME="GreatHouses.exe"
MAC_OUT_NAME="GreatHouses.app"

RC=0
note() { printf '[build] %s\n' "$*"; }
fail() { printf '[build] FAIL: %s\n' "$*"; RC=1; }

# Files that MUST be in the shipped pck. The three .json data files are read
# with FileAccess (not load()), so they only ship because export_presets.cfg
# lists them in include_filter — assert them every single build.
ASSERT_PRESENT=(
  "src/houses/houses.json"
  "src/banter/banter_lines.json"
  "src/cinematics/kill_lines.json"
  "scenes/main.tscn"
  "src/board/piece_assets.gd"
  "src/audio/music_manager.gd"
)
# Things that must NEVER reach a player. test_e2e/ is the whole E2E harness:
# it was autoloaded from project.godot until 2026-08-09, so a 90 KB .gdc of
# test code shipped inside the Windows pck. It is registered at runtime now
# (src/main.gd::_install_e2e_harness) and excluded from every export.
ASSERT_ABSENT=( "test_e2e/" "res://tests/" "res://tools/" ".md" )

# macOS ships bash 3.2, which has no `mapfile` — build the argv in a global.
PCK_ARGS=()
build_pck_args() {
  PCK_ARGS=()
  for p in "${ASSERT_PRESENT[@]}"; do PCK_ARGS+=(--assert-present "$p"); done
  for p in "${ASSERT_ABSENT[@]}"; do PCK_ARGS+=(--assert-absent "$p"); done
}

# ── Preconditions ──────────────────────────────────────────────────────────
check_toolchain() {
  if [ ! -x "$GODOT" ]; then fail "Godot not executable at $GODOT"; return 1; fi
  local ver tpl_ver tpl_dir
  ver="$("$GODOT" --version 2>/dev/null | tail -1)"
  # Godot looks templates up by "<major>.<minor>.<patch>.<status>", which is
  # the first four dot-fields of the version string. A mismatch here is the
  # single most confusing export failure there is, so name it precisely.
  tpl_ver="$(printf '%s' "$ver" | cut -d. -f1-4)"
  tpl_dir="$TEMPLATE_ROOT/$tpl_ver"
  note "godot     : $ver"
  note "templates : $tpl_dir"
  if [ ! -d "$tpl_dir" ]; then
    fail "export templates for '$tpl_ver' are NOT installed.
       Fix: download Godot_v${tpl_ver%.*}-${tpl_ver##*.}_export_templates.tpz from
            https://github.com/godotengine/godot/releases and unzip its
            templates/ contents into:  $tpl_dir/"
    return 1
  fi
  local stamped
  stamped="$(cat "$tpl_dir/version.txt" 2>/dev/null || echo MISSING)"
  if [ "$stamped" != "$tpl_ver" ]; then
    fail "template version.txt says '$stamped' but the editor wants '$tpl_ver'"
    return 1
  fi
  note "template version.txt matches the editor ($stamped)"
  # Icons are another agent's deliverable; report status, never block.
  # macOS embeds its .icns directly. Windows needs BOTH a .ico AND rcedit,
  # so a .ico appearing on its own is still not enough.
  if [ -f "$PROJ/assets/branding/GreatHouses.icns" ]; then
    note "icon(mac) : GreatHouses.icns present — embedded in the .app"
  else
    note "icon(mac) : no .icns — bundle keeps the default Godot icon"
  fi
  # Godot 4.7 stamps the PE icon + version info natively — no rcedit needed.
  if [ -f "$PROJ/assets/branding/GreatHouses.ico" ]; then
    if grep -q '^application/icon=""' "$PROJ/export_presets.cfg"; then
      note "NOTE: assets/branding/GreatHouses.ico EXISTS but a preset still has"
      note "      application/icon=\"\" — point it at res://assets/branding/GreatHouses.ico"
    else
      note "icon(win) : GreatHouses.ico present — stamped into the .exe"
    fi
  else
    note "icon(win) : no .ico — .exe keeps the default Godot icon (see BUILDING.md)"
  fi
  return 0
}

# The e2e suite writes screenshots into test_e2e/artifacts/ — INSIDE res:// — and
# run_scenario `rm -rf`s each scenario's directory before refilling it. Godot's
# exclude_filter is applied by walking the live filesystem, so a directory that is
# being deleted out from under that walk can escape the filter entirely: a build run
# during a suite shipped 3 banter screenshots, one of them 0 bytes (caught mid-write).
# The pck assertions catch it after the fact; this refuses before wasting the export.
e2e_running() {
  # Recent writes under the artifacts tree. The window only has to cover the
  # ~1 s gap BETWEEN scenarios (when no --e2e process exists yet the suite is
  # still going); the process check below is the authoritative signal. Keep it
  # short or every build in the minute after a suite gets refused for nothing.
  if find "$PROJ/test_e2e/artifacts" -newermt '-20 seconds' -type f -print -quit \
       2>/dev/null | grep -q .; then
    return 0
  fi
  # A windowed scenario launch (run_scenario passes "--e2e=<name>" after --).
  # Built by concatenation so this grep's own argv can't self-match, and grep -v grep
  # drops the pipeline's own processes.
  # NOTE: -e is REQUIRED. The marker starts with "--", so a bare `grep -F "$marker"`
  # is parsed as an option and the check silently dies (exit 2 -> "not running").
  # This box's `grep` is ugrep, which rejects it loudly; GNU grep would too.
  local marker="--e2e"; marker="${marker}="
  if ps -axo command 2>/dev/null | grep -F -e "$marker" | grep -F -e "$PROJ" \
       | grep -v -e grep >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

guard_concurrent_e2e() {
  if [ "${ALLOW_CONCURRENT_E2E:-0}" = "1" ]; then
    note "WARNING: concurrent-e2e guard disabled by ALLOW_CONCURRENT_E2E=1"
    return 0
  fi
  if e2e_running; then
    fail "the e2e suite appears to be RUNNING (recent writes under test_e2e/artifacts,
       or a live --e2e scenario). Exporting now can leak test screenshots into the
       shipped pck, because Godot applies exclude_filter by walking a directory the
       suite is deleting and recreating. Wait for it to finish and re-run.
       Override with ALLOW_CONCURRENT_E2E=1 (the pck assertions still backstop you)."
    return 1
  fi
  return 0
}

do_import() {
  note "importing assets headless"
  "$GODOT" --headless --path "$PROJ" --import >"$OUT/import.log" 2>&1
  local rc=$?
  if [ $rc -ne 0 ]; then fail "--import exited $rc (see $OUT/import.log)"; return 1; fi
  note "import OK"
  return 0
}

# ── Exports ────────────────────────────────────────────────────────────────
build_windows() {
  local target="$OUT/windows/$WIN_OUT_NAME"
  mkdir -p "$OUT/windows"
  rm -f "$target"
  note "exporting '$WIN_PRESET' -> $target"
  "$GODOT" --headless --path "$PROJ" --export-release "$WIN_PRESET" "$target" \
      >"$OUT/windows/export.log" 2>&1
  local rc=$?
  if [ $rc -ne 0 ]; then fail "windows export exited $rc (see $OUT/windows/export.log)"; return 1; fi
  if [ ! -f "$target" ]; then fail "windows export produced no file"; return 1; fi

  local ftype size
  ftype="$(file -b "$target")"
  case "$ftype" in
    PE32+*x86-64*) note "file(1): $ftype" ;;
    *) fail "artifact is not a PE32+ x86-64 binary: $ftype"; return 1 ;;
  esac
  size=$(stat -f%z "$target" 2>/dev/null || stat -c%s "$target")
  if [ "$size" -lt 40000000 ]; then
    fail "artifact is only $size bytes — the pck is probably missing"; return 1
  fi
  note "size    : $((size / 1048576)) MiB (single self-contained .exe)"

  note "verifying pck contents"
  build_pck_args
  python3 "$SCRIPT_DIR/pck_list.py" "$target" --count-only "${PCK_ARGS[@]}" || {
    fail "pck content assertions failed for $target"; return 1; }
  note "windows build verified"
  return 0
}

build_macos() {
  local target="$OUT/macos/$MAC_OUT_NAME"
  mkdir -p "$OUT/macos"
  rm -rf "$target"
  note "exporting '$MAC_PRESET' -> $target"
  "$GODOT" --headless --path "$PROJ" --export-release "$MAC_PRESET" "$target" \
      >"$OUT/macos/export.log" 2>&1
  local rc=$?
  if [ $rc -ne 0 ]; then fail "macos export exited $rc (see $OUT/macos/export.log)"; return 1; fi
  if [ ! -d "$target" ]; then fail "macos export produced no .app bundle"; return 1; fi

  local bin
  bin="$(ls "$target/Contents/MacOS/" | head -1)"
  note "file(1): $(file -b "$target/Contents/MacOS/$bin")"

  note "verifying pck contents"
  build_pck_args
  python3 "$SCRIPT_DIR/pck_list.py" "$target" --count-only "${PCK_ARGS[@]}" || {
    fail "pck content assertions failed for $target"; return 1; }

  # The macOS bundle is the ONLY artifact we can actually execute here, so it
  # doubles as the smoke test for filters that are shared with Windows: a
  # dropped autoload script shows up as a boot error in this step.
  note "boot smoke test (headless, isolated HOME)"
  local h="$OUT/macos/.boothome"; rm -rf "$h"; mkdir -p "$h"
  HOME="$h" "$target/Contents/MacOS/$bin" --headless --quit \
      >"$OUT/macos/boot.log" 2>&1
  rc=$?
  if [ $rc -ne 0 ]; then fail "exported app exited $rc on boot (see $OUT/macos/boot.log)"; return 1; fi
  if grep -q "Failed to instantiate an autoload" "$OUT/macos/boot.log"; then
    fail "exported app has a BROKEN AUTOLOAD — an exclude_filter dropped a script
       named in project.godot's [autoload] block (see $OUT/macos/boot.log)"
    return 1
  fi
  note "macos build verified (booted clean)"
  return 0
}

run_degrade() {
  note "platform-degradation suite (missing stockfish + unreachable oracle)"
  local h="$OUT/.degradehome"; rm -rf "$h"; mkdir -p "$h"
  HOME="$h" "$GODOT" --headless --path "$PROJ" \
      -s res://tools/build/test_platform_degradation.gd >"$OUT/degrade.log" 2>&1
  local rc=$?
  tail -n 3 "$OUT/degrade.log"
  if [ $rc -ne 0 ]; then fail "degradation suite exited $rc (see $OUT/degrade.log)"; return 1; fi
  note "degradation suite green"
  return 0
}

# ── Main ───────────────────────────────────────────────────────────────────
TARGETS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    windows|macos|degrade|all) TARGETS+=("$1"); shift ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "unknown argument '$1'"; exit 2 ;;
  esac
done
[ ${#TARGETS[@]} -eq 0 ] && TARGETS=(all)

mkdir -p "$OUT"
note "project   : $PROJ"
note "output    : $OUT"
check_toolchain || { note "toolchain unusable — stopping"; exit 1; }

for t in "${TARGETS[@]}"; do
  case "$t" in
    windows) guard_concurrent_e2e && do_import && build_windows ;;
    macos)   guard_concurrent_e2e && do_import && build_macos ;;
    degrade) run_degrade ;;
    all)     guard_concurrent_e2e && do_import && { build_windows; build_macos; run_degrade; } ;;
  esac
done

echo
if [ $RC -eq 0 ]; then
  note "ALL GREEN — artifacts under $OUT"
else
  note "BUILD FAILED"
fi
exit $RC
