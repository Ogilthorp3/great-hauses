#!/usr/bin/env python3
"""haus_delta_e.py — the nine-haus separation instrument.

Two previous critics each flagged ONE confusable pair and each got a LOCAL
patch. This is the systematic pass: it takes the colours the hall ACTUALLY
renders (tools/haus_field.gd samples them off the frame, under the eight
orange torches), converts them to CIELAB, and prints the full pairwise
Delta-E 2000 matrix with the minimum named.

It also runs the three dichromacy simulations (Brettel/Vienot LMS), because a
pair that separates for a trichromat and collapses for a deuteranope is not
separated — 8 % of men see the second matrix, not the first.

Usage:
  haus_delta_e.py matrix <samples.txt> [--label LABEL]
  haus_delta_e.py compare <before.txt> <after.txt>
  haus_delta_e.py crop <img.png> <out.png> <x> <y> <w> <h> [scale]
  haus_delta_e.py sheet <samples.txt> <out.png>   # nine swatches + 3 CB sims

`samples.txt` is the HAUSFIELD lines from tools/haus_field.gd, verbatim.
"""
import sys
import math
import re

# ── colour maths ───────────────────────────────────────────────────────────


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def linear_to_srgb(c):
    c = max(0.0, min(1.0, c))
    return c * 12.92 if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055


def hex_to_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def rgb_to_hex(rgb):
    return "#" + "".join("%02x" % max(0, min(255, round(c * 255))) for c in rgb)


def rgb_to_xyz(rgb):
    r, g, b = (srgb_to_linear(c) for c in rgb)
    return (
        0.4124564 * r + 0.3575761 * g + 0.1804375 * b,
        0.2126729 * r + 0.7151522 * g + 0.0721750 * b,
        0.0193339 * r + 0.1191920 * g + 0.9503041 * b,
    )


def xyz_to_lab(xyz):
    wx, wy, wz = 0.95047, 1.0, 1.08883
    x, y, z = xyz[0] / wx, xyz[1] / wy, xyz[2] / wz

    def f(t):
        return t ** (1 / 3) if t > 216 / 24389 else (24389 / 27 * t + 16) / 116

    fx, fy, fz = f(x), f(y), f(z)
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))


def lab(hexstr):
    return xyz_to_lab(rgb_to_xyz(hex_to_rgb(hexstr)))


def delta_e2000(l1, l2):
    """CIEDE2000. The perceptual metric, not the 1976 Euclidean one — Lab
    distance badly over-rates saturated blues and under-rates near-neutrals,
    which is exactly the axis this pass moves colours along."""
    L1, a1, b1 = l1
    L2, a2, b2 = l2
    kL = kC = kH = 1.0
    C1 = math.hypot(a1, b1)
    C2 = math.hypot(a2, b2)
    Cbar = (C1 + C2) / 2
    G = 0.5 * (1 - math.sqrt(Cbar ** 7 / (Cbar ** 7 + 25 ** 7))) if Cbar > 0 else 0.5
    a1p, a2p = (1 + G) * a1, (1 + G) * a2
    C1p, C2p = math.hypot(a1p, b1), math.hypot(a2p, b2)
    h1p = math.degrees(math.atan2(b1, a1p)) % 360 if (a1p or b1) else 0.0
    h2p = math.degrees(math.atan2(b2, a2p)) % 360 if (a2p or b2) else 0.0
    dLp = L2 - L1
    dCp = C2p - C1p
    if C1p * C2p == 0:
        dhp = 0.0
    elif abs(h2p - h1p) <= 180:
        dhp = h2p - h1p
    elif h2p - h1p > 180:
        dhp = h2p - h1p - 360
    else:
        dhp = h2p - h1p + 360
    dHp = 2 * math.sqrt(C1p * C2p) * math.sin(math.radians(dhp / 2))
    Lbp = (L1 + L2) / 2
    Cbp = (C1p + C2p) / 2
    if C1p * C2p == 0:
        hbp = h1p + h2p
    elif abs(h1p - h2p) <= 180:
        hbp = (h1p + h2p) / 2
    elif h1p + h2p < 360:
        hbp = (h1p + h2p + 360) / 2
    else:
        hbp = (h1p + h2p - 360) / 2
    T = (1 - 0.17 * math.cos(math.radians(hbp - 30))
         + 0.24 * math.cos(math.radians(2 * hbp))
         + 0.32 * math.cos(math.radians(3 * hbp + 6))
         - 0.20 * math.cos(math.radians(4 * hbp - 63)))
    dTh = 30 * math.exp(-(((hbp - 275) / 25) ** 2))
    Rc = 2 * math.sqrt(Cbp ** 7 / (Cbp ** 7 + 25 ** 7)) if Cbp > 0 else 0.0
    Sl = 1 + (0.015 * (Lbp - 50) ** 2) / math.sqrt(20 + (Lbp - 50) ** 2)
    Sc = 1 + 0.045 * Cbp
    Sh = 1 + 0.015 * Cbp * T
    Rt = -math.sin(math.radians(2 * dTh)) * Rc
    return math.sqrt((dLp / (kL * Sl)) ** 2 + (dCp / (kC * Sc)) ** 2
                     + (dHp / (kH * Sh)) ** 2
                     + Rt * (dCp / (kC * Sc)) * (dHp / (kH * Sh)))


# ── dichromacy simulation (Brettel-Vienot-Mollon, LMS) ─────────────────────

_RGB2LMS = ((0.31399022, 0.63951294, 0.04649755),
            (0.15537241, 0.75789446, 0.08670142),
            (0.01775239, 0.10944209, 0.87256922))
_LMS2RGB = ((5.47221206, -4.6419601, 0.16963708),
            (-1.1252419, 2.29317094, -0.1678952),
            (0.02980165, -0.19318073, 1.16364789))
_SIM = {
    "protanopia": ((0.0, 1.05118294, -0.05116099), (0, 1, 0), (0, 0, 1)),
    "deuteranopia": ((1, 0, 0), (0.9513092, 0.0, 0.04866992), (0, 0, 1)),
    "tritanopia": ((1, 0, 0), (0, 1, 0), (-0.86744736, 1.86727089, 0.0)),
}


def _mul(m, v):
    return tuple(sum(m[i][j] * v[j] for j in range(3)) for i in range(3))


def simulate(hexstr, kind):
    lin = tuple(srgb_to_linear(c) for c in hex_to_rgb(hexstr))
    lms = _mul(_RGB2LMS, lin)
    lms = _mul(_SIM[kind], lms)
    rgb = _mul(_LMS2RGB, lms)
    return rgb_to_hex(tuple(linear_to_srgb(c) for c in rgb))


# ── sample parsing ─────────────────────────────────────────────────────────

LINE = re.compile(r"^HAUSFIELD\s+(\S+)\s+(\S+)\s+([0-9a-fA-F]{6})\b")


def read_samples(path):
    """-> {channel: {haus: hex}} in file order."""
    out = {}
    with open(path) as fh:
        for line in fh:
            m = LINE.match(line.strip())
            if not m:
                continue
            haus, chan, hexs = m.group(1), m.group(2), m.group(3)
            out.setdefault(chan, {})[haus] = "#" + hexs.lower()
    return out


# ── reports ────────────────────────────────────────────────────────────────

FLOOR = 12.0   # the bar this pass holds every pair to, in Delta-E 2000


def matrix(chan, table, label=""):
    names = list(table)
    labs = {n: lab(table[n]) for n in names}
    print("\n=== %s%s ===" % (chan, (" — " + label) if label else ""))
    print("        " + "".join("%-8s" % n[:7] for n in names))
    worst = (999.0, None, None)
    pairs = []
    for i, a in enumerate(names):
        row = "%-8s" % a[:7]
        for j, b in enumerate(names):
            if i == j:
                row += "%-8s" % "·"
                continue
            d = delta_e2000(labs[a], labs[b])
            row += "%-8.1f" % d
            if j > i:
                pairs.append((d, a, b))
                if d < worst[0]:
                    worst = (d, a, b)
        print(row)
    pairs.sort()
    print("  MIN dE2000 = %.1f  (%s vs %s)" % worst)
    print("  five closest: " + " · ".join(
        "%s/%s %.1f" % (a, b, d) for d, a, b in pairs[:5]))
    below = [(d, a, b) for d, a, b in pairs if d < FLOOR]
    if below:
        print("  BELOW %.0f (confusable): " % FLOOR + " · ".join(
            "%s/%s %.1f" % (a, b, d) for d, a, b in below))
    else:
        print("  every pair clears the %.0f floor" % FLOOR)
    return worst[0], pairs


def cb_report(chan, table):
    names = list(table)
    print("\n--- %s under dichromacy ---" % chan)
    overall = 999.0
    for kind in ("deuteranopia", "protanopia", "tritanopia"):
        sim = {n: simulate(table[n], kind) for n in names}
        labs = {n: lab(sim[n]) for n in names}
        pairs = sorted((delta_e2000(labs[a], labs[b]), a, b)
                       for i, a in enumerate(names) for b in names[i + 1:])
        overall = min(overall, pairs[0][0])
        print("  %-13s min %.1f (%s/%s) · next %s"
              % (kind, pairs[0][0], pairs[0][1], pairs[0][2],
                 ", ".join("%s/%s %.1f" % (a, b, d) for d, a, b in pairs[1:4])))
    return overall


def cmd_matrix(argv):
    path = argv[0]
    label = ""
    if "--label" in argv:
        label = argv[argv.index("--label") + 1]
    data = read_samples(path)
    mins = {}
    for chan, table in data.items():
        m, _ = matrix(chan, table, label)
        cb = cb_report(chan, table)
        mins[chan] = (m, cb)
    print("\nSUMMARY%s" % ((" (" + label + ")") if label else ""))
    for chan, (m, cb) in mins.items():
        print("  %-8s min dE=%.1f  min dE under dichromacy=%.1f" % (chan, m, cb))


def cmd_compare(argv):
    before, after = read_samples(argv[0]), read_samples(argv[1])
    for chan in before:
        if chan not in after:
            continue
        b, a = before[chan], after[chan]
        print("\n### %s — before vs after ###" % chan)
        print("%-12s %-10s %-10s" % ("haus", "before", "after"))
        for n in a:
            print("%-12s %-10s %-10s" % (n, b.get(n, "—"), a[n]))
        mb, pb = matrix(chan, b, "BEFORE")
        ma, pa = matrix(chan, a, "AFTER")
        print("\n  >>> %s minimum: %.1f -> %.1f  (%+.1f)" % (chan, mb, ma, ma - mb))
        cbb = cb_report(chan + " BEFORE", b)
        cba = cb_report(chan + " AFTER", a)
        print("  >>> %s dichromatic minimum: %.1f -> %.1f  (%+.1f)"
              % (chan, cbb, cba, cba - cbb))


def cmd_crop(argv):
    from PIL import Image
    src, dst = argv[0], argv[1]
    x, y, w, h = (int(v) for v in argv[2:6])
    scale = float(argv[6]) if len(argv) > 6 else 1.0
    im = Image.open(src).crop((x, y, x + w, y + h))
    if scale != 1.0:
        im = im.resize((int(w * scale), int(h * scale)), Image.NEAREST)
    im.save(dst)
    print("wrote %s (%dx%d)" % (dst, im.size[0], im.size[1]))


def cmd_dominant(argv):
    """dominant <img.png> <x> <y> <w> <h> [n] — the n fullest colour buckets
    in a region, as hexes with their share. Used to read the dragon's hide off
    a real frame: the palette must stay clear of the colours the beast wears,
    and the beast's are painted by a shader chain, not declared anywhere."""
    from PIL import Image
    im = Image.open(argv[0]).convert("RGB")
    x, y, w, h = (int(v) for v in argv[1:5])
    n = int(argv[5]) if len(argv) > 5 else 5
    px = im.load()
    bins = {}
    for j in range(y, min(y + h, im.size[1])):
        for i in range(x, min(x + w, im.size[0])):
            r, g, b = px[i, j]
            key = (r >> 5, g >> 5, b >> 5)
            e = bins.setdefault(key, [0, 0, 0, 0])
            e[0] += 1
            e[1] += r
            e[2] += g
            e[3] += b
    total = sum(e[0] for e in bins.values())
    top = sorted(bins.values(), key=lambda e: -e[0])[:n]
    for e in top:
        hexs = "#%02x%02x%02x" % (e[1] // e[0], e[2] // e[0], e[3] // e[0])
        L, A, B = lab(hexs)
        print("  %s  %5.1f%%  L=%.0f a=%+.0f b=%+.0f" %
              (hexs, 100.0 * e[0] / total, L, A, B))


def cmd_montage(argv):
    """montage <out.png> <img...> — the sigils side by side at TWO sizes: big
    enough to judge the drawing, and 26 px, which is what a shield decal
    actually occupies on the board. The second row is the one that decides
    whether two marks are the same mark."""
    from PIL import Image
    out, paths = argv[0], argv[1:]
    big, small, pad = 168, 26, 10
    w = pad + len(paths) * (big + pad)
    h = pad + big + pad + small * 3 + pad
    im = Image.new("RGB", (w, h), (26, 24, 22))
    for i, p in enumerate(paths):
        src = Image.open(p).convert("RGBA")
        x = pad + i * (big + pad)
        b = src.resize((big, big), Image.LANCZOS)
        im.paste(b, (x, pad), b)
        s = src.resize((small, small), Image.LANCZOS).resize(
            (small * 3, small * 3), Image.NEAREST)
        im.paste(s, (x + (big - small * 3) // 2, pad + big + pad), s)
    im.save(out)
    print("wrote %s (%dx%d)" % (out, w, h))


def cmd_sheet(argv):
    """Nine swatches x four rows (normal + three dichromacies), one PNG."""
    from PIL import Image, ImageDraw
    data = read_samples(argv[0])
    chans = list(data)
    cell, pad, labelw = 150, 8, 130
    rows = ["normal", "deuteranopia", "protanopia", "tritanopia"]
    names = list(data[chans[0]])
    w = labelw + len(names) * (cell + pad) + pad
    h = pad + len(chans) * (len(rows) * (cell + pad) + 34)
    im = Image.new("RGB", (w, h), (18, 17, 20))
    d = ImageDraw.Draw(im)
    y = pad
    for chan in chans:
        d.text((pad, y + 6), "%s — as rendered under the hall's torches" % chan,
               fill=(235, 230, 220))
        y += 26
        for r in rows:
            d.text((pad, y + cell // 2 - 6), r, fill=(190, 185, 178))
            for i, n in enumerate(names):
                hexs = data[chan][n]
                if r != "normal":
                    hexs = simulate(hexs, r)
                x = labelw + i * (cell + pad)
                d.rectangle([x, y, x + cell, y + cell],
                            fill=hex_to_rgb_255(hexs))
                if r == "normal":
                    d.text((x + 6, y + cell - 16), n[:11], fill=(255, 255, 255))
                    d.text((x + 6, y + 6), hexs, fill=(255, 255, 255))
            y += cell + pad
        y += 8
    im.save(argv[1])
    print("wrote %s (%dx%d)" % (argv[1], w, h))


def hex_to_rgb_255(h):
    return tuple(round(c * 255) for c in hex_to_rgb(h))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    cmds = {"matrix": cmd_matrix, "compare": cmd_compare,
            "crop": cmd_crop, "sheet": cmd_sheet, "dominant": cmd_dominant, "montage": cmd_montage}
    cmd = sys.argv[1]
    if cmd not in cmds:
        print(__doc__)
        sys.exit(2)
    cmds[cmd](sys.argv[2:])
