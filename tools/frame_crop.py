#!/usr/bin/env python3
"""frame_crop.py — crop (and optionally upscale) a region of a shipped frame
so a human can LOOK at the exact pixels a measurement just described.

    python3 tools/frame_crop.py <in.png> <out.png> x0 y0 x1 y1 [scale]
"""
import sys

from PIL import Image


def main():
    if len(sys.argv) < 7:
        print(__doc__)
        return 2
    src, dst = sys.argv[1], sys.argv[2]
    x0, y0, x1, y1 = (int(a) for a in sys.argv[3:7])
    scale = int(sys.argv[7]) if len(sys.argv) > 7 else 1
    img = Image.open(src).convert("RGB").crop((x0, y0, x1, y1))
    if scale > 1:
        img = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
    img.save(dst)
    print(f"{dst} {img.width}x{img.height}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
