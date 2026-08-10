#!/bin/bash
# Build the Godot editor + visionOS export template from Apple's stacked
# visionOS-XR branch. No Godot release ships a visionOS template (godot#115415),
# so this is mandatory, not optional.
set -uo pipefail

# Resolved before the cd below, so it is correct regardless of cwd or whether
# this script was invoked with a relative or absolute path.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${GODOT_VISIONOS_REPO:-/Users/bert/Projects/godot-visionos}"
PIN="c1df64224a30bd8d7c51489b6c87ee03a86bfa26"
JOBS="${JOBS:-10}"

export PATH="/opt/homebrew/bin:$PATH"
cd "$REPO" || { echo "no engine repo at $REPO"; exit 1; }

HAVE="$(git rev-parse HEAD)"
if [ "$HAVE" != "$PIN" ]; then
  echo "ENGINE PIN MISMATCH: have $HAVE, want $PIN"
  exit 1
fi

# Local patches on top of the pin. Idempotent: --check first, skip if already applied.
PATCH_DIR="$SCRIPT_DIR/patches"
for p in "$PATCH_DIR"/*.patch; do
  [ -e "$p" ] || continue
  if git apply --check "$p" 2>/dev/null; then
    git apply "$p" && echo "applied $(basename "$p")"
  elif git apply --reverse --check "$p" 2>/dev/null; then
    echo "already applied $(basename "$p")"
  else
    echo "PATCH DOES NOT APPLY: $(basename "$p") — the pin moved or the patch is stale"
    exit 1
  fi
done

echo "branch : $(git rev-parse --abbrev-ref HEAD) @ $(git rev-parse --short HEAD)"
echo "xcode  : $(xcodebuild -version | head -1)"
echo "sdk    : $(xcrun --sdk xros --show-sdk-version)"

# macOS editor: the visionOS export plugin (and app_role) compiles INTO the editor.
# vulkan=no metal=yes — macOS defaults to Vulkan via MoltenVK, which we do not have.
scons platform=macos target=editor arch=arm64 \
  vulkan=no metal=yes opengl3=no accesskit=no angle=no -j"$JOBS" || exit 1

# Device templates, arm64 only. The simulator force-disables Metal (detect.py:154-156).
scons platform=visionos target=template_debug   arch=arm64 accesskit=no angle=no -j"$JOBS" || exit 1
scons platform=visionos target=template_release arch=arm64 accesskit=no angle=no -j"$JOBS" || exit 1

# Pack the .a slices into the export template zip.
scons platform=visionos generate_bundle=yes || exit 1

test -f bin/godot_visionos.zip || { echo "no export template produced"; exit 1; }
echo "OK: $(ls -la bin/godot_visionos.zip)"
