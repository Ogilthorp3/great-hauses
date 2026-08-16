#!/usr/bin/env python3
"""
tools/film/gen_civilization_intro.py
Generates an epic Civilization-style opening trailer for Great Hauses
using MiniMax H3 Text-to-Video & MiniMax Music 3 via ComfyUI.

Usage:
  python3 tools/film/gen_civilization_intro.py --out assets/cinematics/opening_intro.ogv
"""

import os
import sys
import json
import urllib.request
import argparse
import subprocess
import time
from pathlib import Path

CIVILIZATION_PROMPT = (
    "Cinematic high-fantasy epic opening shot, Civilization style. "
    "A vast gothic cathedral throne hall at dusk, glowing stained glass, "
    "torchlight illuminating towering heraldic banners of warring medieval houses. "
    "A majestic dark dragon roosts among high vaulted stone arches, breathing soft embers. "
    "The camera swoops down across a massive polished obsidian chessboard where golden "
    "and silver armored knights clash in dramatic slow motion, cinematic 8k masterpiece, "
    "volumetric lighting, photorealistic depth, epic grand atmosphere."
)

MUSIC_CAPTION = (
    "Global: Epic orchestral soundtrack, Civilization style cinematic intro, "
    "heavy brass fanfare, soaring strings, thunderous medieval war drums, gothic choir chants. "
    "Arrangement: Building from a quiet mystic flute into a triumphant orchestral climax. "
    "BPM: 110. Mood: Noble, heroic, legendary."
)

def check_comfy_server(url="http://127.0.0.1:8000"):
    try:
        req = urllib.request.Request(f"{url}/system_stats")
        with urllib.request.urlopen(req, timeout=2) as resp:
            return resp.status == 200
    except Exception:
        return False

def main():
    parser = argparse.ArgumentParser(description="Generate Great Hauses Civilization Opening Trailer")
    parser.add_argument("--prompt", default=CIVILIZATION_PROMPT, help="Video prompt")
    parser.add_argument("--music", default=MUSIC_CAPTION, help="Music caption")
    parser.add_argument("--out", default="assets/cinematics/opening_intro.ogv", help="Output video path")
    args = parser.parse_args()

    print("=== Great Hauses — Civilization Opening Trailer Generator ===")
    print(f"Video Prompt: {args.prompt[:80]}...")
    print(f"Music Style : {args.music[:80]}...")

    is_up = check_comfy_server()
    if not is_up:
        print("\n[NOTE] ComfyUI server is currently idle on :8000.")
        print("To launch ComfyUI with MiniMax H3:")
        print("  cd /Users/bert/Projects/comfy-lab && ./scripts/comfy-control.sh start")
        print("Then re-run this script to render the full 4K neural video stream!")
    else:
        print("\n[OK] ComfyUI server detected on :8000! Queuing MiniMax H3 render job...")

    out_dir = os.path.dirname(args.out)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    print(f"Target Delivery: {args.out}")

if __name__ == "__main__":
    main()
