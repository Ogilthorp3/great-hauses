#!/usr/bin/env python3
"""atlas_probe.py — census the flat colour patches in a KayKit-style atlas.

The KayKit adventurer/skeleton packs paint an entire character from ONE 1024²
atlas of flat colour patches: skin, leather, steel, cloth, hair, metal trim.
The material-ROLE pipeline has to know which texels are which, so this is the
instrument that reads the palette off the atlas instead of guessing at it.

Usage:
    python3 tools/props/atlas_probe.py <png> [<png> ...]

Prints, per file, every distinct opaque colour holding >=0.05 % of the opaque
texels, with its HSV and its share — the raw material for ROLE_PALETTE.
"""
import sys
from collections import Counter

import numpy as np
from PIL import Image


def rgb_to_hsv(r, g, b):
    mx, mn = max(r, g, b), min(r, g, b)
    d = mx - mn
    if d == 0:
        h = 0.0
    elif mx == r:
        h = (60 * ((g - b) / d)) % 360
    elif mx == g:
        h = 60 * ((b - r) / d) + 120
    else:
        h = 60 * ((r - g) / d) + 240
    s = 0.0 if mx == 0 else d / mx
    return h, s, mx


def probe(path):
    img = np.asarray(Image.open(path).convert("RGBA"))
    a = img[..., 3]
    opaque = img[a > 127][:, :3]
    total = len(opaque)
    if total == 0:
        print(f"{path}: fully transparent")
        return
    # Quantise lightly (KayKit patches are flat, so this only merges AA edges).
    q = (opaque // 4) * 4
    counts = Counter(map(tuple, q))
    print(f"\n=== {path}  ({total} opaque texels) ===")
    print(f"{'hex':>9} {'share%':>7} {'H':>6} {'S':>5} {'V':>5}")
    for col, n in counts.most_common(40):
        share = 100.0 * n / total
        if share < 0.05:
            break
        r, g, b = [c / 255.0 for c in col]
        h, s, v = rgb_to_hsv(r, g, b)
        print(f"  #{col[0]:02x}{col[1]:02x}{col[2]:02x} {share:7.2f} "
              f"{h:6.1f} {s:5.2f} {v:5.2f}")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    for p in sys.argv[1:]:
        probe(p)
    return 0


if __name__ == "__main__":
    sys.exit(main())
