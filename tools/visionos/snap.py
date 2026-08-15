#!/usr/bin/python3
"""tools/visionos/snap.py — Pull, analyze, and visually inspect Vision Pro frames.

Usage:
    /usr/bin/python3 tools/visionos/snap.py [--device <DEVICE_ID>] [--out <DIR>]
"""

import argparse
import os
import shutil
import subprocess
import sys
from datetime import datetime
from PIL import Image

DEFAULT_DEVICE = "FF74469D-4113-57D5-AC5C-9E4D68B22A0D"
BUNDLE_ID = "vc.triptyq.greathauses"
ASCII_CHARS = " .:-=+*#%@"


def pull_device_file(device_id: str, source_path: str, dest_path: str) -> bool:
    cmd = [
        "xcrun", "devicectl", "device", "copy", "from",
        "--device", device_id,
        "--domain-type", "appDataContainer",
        "--domain-identifier", BUNDLE_ID,
        "--source", source_path,
        "--destination", dest_path
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    return res.returncode == 0 and os.path.isfile(dest_path)


def render_ascii(img: Image.Image, width: int = 70) -> str:
    aspect = img.height / max(img.width, 1)
    height = max(int(width * aspect * 0.45), 10)
    small = img.resize((width, height)).convert("L")
    pixels = list(small.getdata())
    lines = []
    for y in range(height):
        row = pixels[y * width:(y + 1) * width]
        line = "".join(ASCII_CHARS[int(val / 256 * len(ASCII_CHARS))] for val in row)
        lines.append(line)
    return "\n".join(lines)


def analyze_image(path: str, out_dir: str):
    img = Image.open(path)
    w, h = img.size
    mode = img.mode
    rgb_img = img.convert("RGB")
    pixels = list(rgb_img.getdata())
    total_px = len(pixels)

    lum_list = []
    active_px = 0
    r_sum, g_sum, b_sum = 0, 0, 0
    r_max, g_max, b_max = 0, 0, 0

    for r, g, b in pixels:
        r_sum += r
        g_sum += g
        b_sum += b
        r_max = max(r_max, r)
        g_max = max(g_max, g)
        b_max = max(b_max, b)
        lum = 0.2126 * (r / 255.0) + 0.7152 * (g / 255.0) + 0.0722 * (b / 255.0)
        lum_list.append(lum)
        if lum > 0.01:
            active_px += 1

    pct_active = (active_px / total_px) * 100.0 if total_px > 0 else 0.0
    lum_min = min(lum_list) if lum_list else 0.0
    lum_max = max(lum_list) if lum_list else 0.0
    lum_mean = (sum(lum_list) / total_px) if total_px > 0 else 0.0

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    saved_path = os.path.join(out_dir, f"visionos_snap_{timestamp}.png")
    latest_path = os.path.join(out_dir, "latest.png")
    shutil.copyfile(path, saved_path)
    shutil.copyfile(path, latest_path)

    print("=" * 65)
    print(f"👁️  VISIONOS FRAME INSPECTOR — {timestamp}")
    print("=" * 65)
    print(f"Image Resolution   : {w} x {h} ({mode})")
    print(f"Saved Artifact     : {saved_path}")
    print(f"Active Pixels (>1%): {active_px:,} / {total_px:,} ({pct_active:.2f}%)")
    print(f"Luminance Min/Max  : {lum_min:.4f} / {lum_max:.4f}")
    print(f"Luminance Mean     : {lum_mean:.4f}")
    print(f"Red Mean / Max     : {r_sum / total_px / 255.0:.4f} / {r_max / 255.0:.4f}")
    print(f"Green Mean / Max   : {g_sum / total_px / 255.0:.4f} / {g_max / 255.0:.4f}")
    print(f"Blue Mean / Max    : {b_sum / total_px / 255.0:.4f} / {b_max / 255.0:.4f}")
    print("-" * 65)
    print("TERMINAL PREVIEW:")
    print(render_ascii(img, width=70))
    print("=" * 65)


def main():
    parser = argparse.ArgumentParser(description="VisionOS visual frame puller & inspector")
    parser.add_argument("--device", default=DEFAULT_DEVICE, help="Device UUID")
    parser.add_argument("--out", default="artifacts/visionos", help="Output directory")
    args = parser.parse_args()

    os.makedirs(args.out, exist_ok=True)
    temp_dest = "/tmp/visionos_screenshot.png"
    if os.path.exists(temp_dest):
        os.remove(temp_dest)

    print(f"Pulling latest screenshot from Vision Pro ({args.device})...")
    ok = pull_device_file(args.device, "Documents/screenshot_latest.png", temp_dest)
    if not ok:
        print("ERROR: Could not retrieve Documents/screenshot_latest.png.")
        print("Make sure the Great Hauses app is running on the device.")
        sys.exit(1)

    analyze_image(temp_dest, args.out)


if __name__ == "__main__":
    main()
