#!/bin/bash
set -e

ARTIFACTS_DIR="/Users/bert/.gemini/antigravity-cli/brain/dc426532-efa9-4364-92c2-5a53db738eb2"
mkdir -p "$ARTIFACTS_DIR/inspection"

pkill -f "Great Hauses" 2>/dev/null || true
pkill -f "Godot" 2>/dev/null || true
sleep 0.5

echo "[inspect] Launching /Applications/Great Hauses Chess.app..."
open -a "/Applications/Great Hauses Chess.app"

for i in {1..8}; do
    sleep 0.6
    screencapture -x "$ARTIFACTS_DIR/inspection/frame_${i}.png"
    echo "[inspect] Captured frame_${i}.png"
done

echo "[inspect] Done capturing."
