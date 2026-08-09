#!/usr/bin/env python3
"""frame_rank.py — the RANK-VALUE ruler for the shipped board frame.

Three hard-won wins on this board are VALUE relationships between pieces, and
a value relationship can only be defended by measuring the same pixels before
and after a change:

  * the king must stay the brightest MAN on the near army (the cavalry once
    peaked at 0.839 against a king at 0.776 — the horse was the loudest thing
    on the board);
  * the far queen must stay out of her black hole (0.212 against a rank
    running 0.310-0.376) and inside her rank's band;
  * the nine pawn ranks must stay distinguishable from one another.

The rects below were calibrated ONCE against test_e2e/artifacts/boot/
02_boot_lineup.png (1280x720, the boot scenario's fixed gameplay camera) and
are re-usable because that camera is deterministic. `annotate` draws them so a
human can confirm each rect is still on its piece before trusting a number.

Metric: over the rect, the piece's own pixels are the ones that are NOT board
stone — stone is neutral and flat, so a pixel is kept when it is either
chromatic (saturation above the floor's) or brighter than the light tile. We
report the MEDIAN and the 90th percentile of HSV value over the kept pixels;
median is "how bright is this figure", p90 is "how loud is its brightest
face". Both are printed because the king/knight claim was made on the peak.

Usage:
    python3 tools/frame_rank.py near   <boot.png>
    python3 tools/frame_rank.py far    <boot.png>
    python3 tools/frame_rank.py parade <pawn_helms.png>
    python3 tools/frame_rank.py annotate <boot.png> <out.png>
    python3 tools/frame_rank.py rect   <png> x0 y0 x1 y1
"""
import sys

import numpy as np
from PIL import Image, ImageDraw

# Near army (the player's own side, Winterfang in the boot scenario).
# Back rank y 505-610, pawn rank y 455-525 — measured off 02_boot_lineup.png.
NEAR = {
    "rook_a1":   (296, 524, 376, 612),
    "knight_b1": (384, 520, 466, 606),
    "bishop_c1": (486, 534, 544, 602),
    "queen_d1":  (560, 508, 634, 602),
    "king_e1":   (644, 502, 728, 602),
    "bishop_f1": (740, 534, 798, 602),
    "knight_g1": (806, 520, 890, 606),
    "rook_h1":   (910, 524, 992, 612),
    "pawn_a2":   (330, 470, 380, 522),
    "pawn_b2":   (412, 470, 462, 522),
    "pawn_c2":   (494, 470, 544, 522),
    "pawn_d2":   (576, 470, 626, 522),
    "pawn_e2":   (658, 470, 708, 522),
    "pawn_f2":   (740, 470, 790, 522),
    "pawn_g2":   (822, 470, 872, 522),
    "pawn_h2":   (904, 470, 954, 522),
}

# Far army (the rival, Goldclaw in the boot scenario) — smaller on screen.
FAR = {
    "rook_a8":   (418, 165, 462, 222),
    "knight_b8": (476, 168, 528, 216),
    "bishop_c8": (536, 170, 570, 214),
    "queen_d8":  (588, 160, 632, 214),
    "king_e8":   (646, 158, 692, 214),
    "bishop_f8": (704, 170, 738, 214),
    "knight_g8": (748, 168, 800, 216),
    "rook_h8":   (812, 165, 856, 222),
    "pawn_a7":   (420, 222, 456, 262),
    "pawn_b7":   (478, 222, 514, 262),
    "pawn_c7":   (536, 222, 572, 262),
    "pawn_d7":   (592, 222, 628, 262),
    "pawn_e7":   (650, 222, 686, 262),
    "pawn_f7":   (706, 222, 742, 262),
    "pawn_g7":   (762, 222, 798, 262),
    "pawn_h7":   (818, 222, 854, 262),
}

# The nine-haus pawn parade (module-previews/costumes/pawn_helms.png, 1280x720,
# orthographic and staggered — 5 in front, 4 behind, registry order left to
# right). Rects cover helm + torso, the two things a pawn is read by. This is
# the "nine distinguishable pawn ranks" gate's ruler.
PARADE = {
    "thornvale":   (75, 125, 180, 300),
    "duskfire":    (320, 125, 425, 300),
    "swiftcrest":  (525, 125, 650, 300),
    "silverbrook": (750, 130, 860, 300),
    "winterfang":  (185, 335, 300, 520),
    "goldclaw":    (420, 335, 530, 520),
    "hartcrown":   (645, 340, 760, 520),
    "ashwyrm":     (870, 330, 985, 520),
    "tidegrip":    (1075, 310, 1200, 520),
}

# The board's own stone, from BoardView: light tile albedo 0.50, dark 0.105.
# A pixel brighter than the light tile renders, or carrying real chroma, is a
# piece; flat mid/dark neutrals are the floor it stands on.
STONE_SAT = 0.14
STONE_V_HI = 0.56


def load(path):
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float64) / 255.0


def hsv(img):
    mx = img.max(axis=-1)
    mn = img.min(axis=-1)
    d = mx - mn
    s = np.where(mx > 1e-9, d / np.maximum(mx, 1e-9), 0.0)
    return mx, s


def measure(img, box):
    x0, y0, x1, y1 = box
    crop = img[y0:y1, x0:x1]
    v, s = hsv(crop)
    keep = (s > STONE_SAT) | (v > STONE_V_HI)
    if keep.sum() < 24:          # nothing but stone — report the whole rect
        keep = np.ones_like(v, dtype=bool)
    vv = v[keep]
    ss = s[keep]
    return {
        "px": int(keep.sum()),
        "median": float(np.median(vv)),
        "p90": float(np.percentile(vv, 90)),
        "sat": float(np.median(ss)),
    }


def report(path, table, title):
    img = load(path)
    print(f"=== {title}  {path} ===")
    print(f"{'piece':<11}{'px':>7}{'median':>9}{'p90':>8}{'sat':>7}")
    rows = {}
    for name, box in table.items():
        m = measure(img, box)
        rows[name] = m
        print(f"{name:<11}{m['px']:>7}{m['median']:>9.3f}{m['p90']:>8.3f}"
              f"{m['sat']:>7.3f}")
    backs = [k for k in table if not k.startswith("pawn")]
    pawns = [k for k in table if k.startswith("pawn")]
    king = next(k for k in backs if k.startswith("king"))
    knights = [k for k in backs if k.startswith("knight")]
    queen = next(k for k in backs if k.startswith("queen"))
    print("---")
    print(f"  king      median {rows[king]['median']:.3f}  p90 {rows[king]['p90']:.3f}")
    for k in knights:
        print(f"  {k:<9} median {rows[k]['median']:.3f}  p90 {rows[k]['p90']:.3f}"
              f"   {'OK  king brighter' if rows[k]['p90'] < rows[king]['p90'] else 'FAIL  out-shines the king'}")
    band_lo = min(rows[k]["median"] for k in backs)
    band_hi = max(rows[k]["median"] for k in backs)
    print(f"  back-rank median band {band_lo:.3f}..{band_hi:.3f}"
          f"   queen {rows[queen]['median']:.3f}"
          f"   {'OK  inside' if rows[queen]['median'] > band_lo - 1e-9 else 'FAIL  below the band'}")
    if pawns:
        pv = [rows[k]["median"] for k in pawns]
        print(f"  pawn medians {min(pv):.3f}..{max(pv):.3f}")
    return rows


def parade(path):
    """Nine pawn ranks, and how far apart the closest two of them are.

    A pawn is read at board distance by ONE colour — the colour of the figure,
    whatever surface is carrying it. So the metric is the mean RGB of the
    rect's non-background pixels, and the gate is the smallest distance
    between any two hauses' means.
    """
    img = load(path)
    print(f"=== PAWN PARADE  {path} ===")
    means = {}
    print(f"{'haus':<12}{'px':>7}   {'mean rgb':<22}{'v':>6}{'sat':>7}")
    for name, box in PARADE.items():
        x0, y0, x1, y1 = box
        crop = img[y0:y1, x0:x1]
        v, s = hsv(crop)
        keep = (s > 0.10) | (v > 0.35)
        if keep.sum() < 24:
            keep = np.ones_like(v, dtype=bool)
        m = crop[keep].mean(axis=0)
        means[name] = m
        vv, ss = hsv(m.reshape(1, 1, 3))
        print(f"{name:<12}{int(keep.sum()):>7}   "
              f"({m[0]:.3f},{m[1]:.3f},{m[2]:.3f})     {vv[0][0]:>6.3f}{ss[0][0]:>7.3f}")
    worst = (9.9, "", "")
    names = list(means)
    for i in range(len(names)):
        for j in range(i + 1, len(names)):
            d = float(np.linalg.norm(means[names[i]] - means[names[j]]))
            if d < worst[0]:
                worst = (d, names[i], names[j])
    print("---")
    print(f"  closest pair: {worst[1]} vs {worst[2]}  distance {worst[0]:.3f}")
    return means


def annotate(path, out):
    img = Image.open(path).convert("RGB")
    d = ImageDraw.Draw(img)
    tables = ((NEAR, (0, 255, 128)), (FAR, (255, 160, 0))) \
        if img.height == 720 and img.width == 1280 and "pawn_helms" not in path \
        else ((PARADE, (0, 255, 128)),)
    for table, color in tables:
        for name, box in table.items():
            d.rectangle(box, outline=color)
            d.text((box[0] + 1, box[1] - 9), name.split("_")[0][:2], fill=color)
    img.save(out)
    print(f"{out} written")


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    mode, path = sys.argv[1], sys.argv[2]
    if mode == "near":
        report(path, NEAR, "NEAR ARMY")
    elif mode == "far":
        report(path, FAR, "FAR ARMY")
    elif mode == "parade":
        parade(path)
    elif mode == "annotate":
        annotate(path, sys.argv[3])
    elif mode == "rect":
        box = [int(a) for a in sys.argv[3:7]]
        print(measure(load(path), box))
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
