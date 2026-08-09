#!/usr/bin/env python3
"""
GREAT HOUSES — title wordmark for the Hall of Banners.

    python3 tools/branding/gen_wordmark.py

Writes  assets/branding/wordmark-great-houses.png   (1600x760, transparent)
        assets/branding/wordmark-great-houses-flat.png  (type only, no crest —
        for places that already show the shield, e.g. a window title bar)

Lockup: CREST OVER TYPE.  A shield's native lockup is the crest above the
name — it is why the app icon and the title can be the same mark twice without
reading as a redundancy, and it is the one gate the runner-up concepts failed
(a GH monogram set above the words GREAT HOUSES makes the reader parse the same
two letters twice).  So: shield, rule, name.  No monogram anywhere.

Type: Luminari — a flared-serif medieval face that ships with macOS.  Set in
caps with wide tracking, filled with the SAME gold ramp as the icon's charge
(gen_app_icon.gold_fill) over the same dark keyline, so the title is visibly
the same metal as the shield it sits under.  Everything is imported from
gen_app_icon.py rather than re-declared, so the icon's palette is the only
place colour is defined.
"""

import os
import sys

from PIL import Image, ImageDraw, ImageChops, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import gen_app_icon as G  # noqa: E402

W, H = 1600, 760
TITLE = "GREAT HOUSES"

# Luminari first — it is the medieval serif on macOS.  The fallbacks are the
# other flared/inscriptional faces that ship on the same machine, so a missing
# Luminari degrades to something still Roman-carved rather than to Helvetica.
FONT_CANDIDATES = [
    "/System/Library/Fonts/Supplemental/Luminari.ttf",
    "/System/Library/Fonts/Supplemental/Herculanum.ttf",
    "/System/Library/Fonts/Supplemental/Trattatello.ttf",
    "/System/Library/Fonts/Supplemental/Copperplate.ttc",
    "/System/Library/Fonts/Supplemental/Baskerville.ttc",
]


def pick_font(px):
    for p in FONT_CANDIDATES:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, px), os.path.basename(p)
            except Exception:
                continue
    return ImageFont.load_default(), "PIL-default"


def tracked_mask(text, font, tracking, size, baseline_y, center_x):
    """Draw TEXT letter by letter into an L mask with manual tracking.

    Wide tracking is what turns a font into a wordmark; PIL will not do it, so
    the advance is walked by hand.
    """
    d0 = ImageDraw.Draw(Image.new("L", (1, 1)))
    widths = [d0.textlength(ch, font=font) for ch in text]
    total = sum(widths) + tracking * (len(text) - 1)
    m = Image.new("L", size, 0)
    d = ImageDraw.Draw(m)
    x = center_x - total / 2.0
    for ch, w in zip(text, widths):
        d.text((x, baseline_y), ch, font=font, fill=255, anchor="ls")
        x += w + tracking
    return m, total


def metal(mask, size, y0, y1, keyline=True, bevel=True):
    """Turn a mask into the icon's gold: keyline, cast shadow, ramp, bevel."""
    R = size[0]
    layer = Image.new("RGBA", size, (0, 0, 0, 0))

    if keyline:
        key = G.dilate(mask, R * 0.0042)
        layer.paste(Image.new("RGB", size, (0x0B, 0x07, 0x09)), (0, 0),
                    key.point(lambda v: int(v * 0.85)))
        outer = G.dilate(mask, R * 0.0100)
        layer.paste(Image.new("RGB", size, (0x0B, 0x07, 0x09)), (0, 0),
                    outer.filter(ImageFilter.GaussianBlur(R * 0.004)).point(
                        lambda v: int(v * 0.55)))

    shadow = mask.filter(ImageFilter.GaussianBlur(R * 0.004)).point(
        lambda v: int(v * 0.55))
    layer.paste(Image.new("RGB", size, (0, 0, 0)),
                (int(R * 0.0035), int(R * 0.0035)), shadow)

    # gold_fill() is square by construction (it is the icon's ramp); the
    # wordmark canvas is not, so take the strip we need.
    ramp = G.gold_fill(max(R, size[1]), y0, y1).crop((0, 0, size[0], size[1]))
    layer.paste(ramp, (0, 0), mask)

    if bevel:
        lip = ImageChops.subtract(mask, G.erode(mask, R * 0.0026))
        up = lip.copy()
        up.paste(0, (0, int(R * 0.0024)), lip)
        layer.paste(Image.new("RGB", size, (0xFF, 0xF0, 0xC0)), (0, 0),
                    up.filter(ImageFilter.GaussianBlur(R * 0.0012)).point(
                        lambda v: int(v * 0.62)))
        dn = lip.copy()
        dn.paste(0, (0, -int(R * 0.0024)), lip)
        layer.paste(Image.new("RGB", size, (0x5A, 0x38, 0x10)), (0, 0),
                    dn.filter(ImageFilter.GaussianBlur(R * 0.0012)).point(
                        lambda v: int(v * 0.55)))
    return layer


def rule_mask(size, cx, cy, half, thick):
    """A tapered rule with a lozenge at each end — heraldic, not a <hr>."""
    m = Image.new("L", size, 0)
    d = ImageDraw.Draw(m)
    d.polygon([(cx - half, cy), (cx - half * 0.55, cy - thick / 2),
               (cx + half * 0.55, cy - thick / 2), (cx + half, cy),
               (cx + half * 0.55, cy + thick / 2),
               (cx - half * 0.55, cy + thick / 2)], fill=255)
    for s in (-1, 1):
        lx = cx + s * (half + thick * 1.9)
        d.polygon([(lx, cy - thick * 1.5), (lx + thick * 1.5, cy),
                   (lx, cy + thick * 1.5), (lx - thick * 1.5, cy)], fill=255)
    return m


def build(with_crest=True):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    cx = W // 2

    crest_px = 300
    crest_top = 24
    type_baseline = crest_top + crest_px + 224 if with_crest else 300

    if with_crest:
        crest = G.render(crest_px)
        img.paste(crest, (cx - crest_px // 2, crest_top), crest)

        rule_y = crest_top + crest_px + 46
        rm = rule_mask((W, H), cx, rule_y, W * 0.235, max(3, H * 0.009))
        img.alpha_composite(metal(rm, (W, H), rule_y - 22, rule_y + 28,
                                  bevel=False))

    font_px = 168
    font, font_name = pick_font(font_px)
    mask, total = tracked_mask(TITLE, font, font_px * 0.16, (W, H),
                               type_baseline, cx)
    # keep the lockup inside the canvas whatever the fallback font's metrics are
    if total > W * 0.90:
        font_px = int(font_px * (W * 0.90) / total)
        font, font_name = pick_font(font_px)
        mask, total = tracked_mask(TITLE, font, font_px * 0.16, (W, H),
                                   type_baseline, cx)

    img.alpha_composite(metal(mask, (W, H), type_baseline - font_px * 0.78,
                              type_baseline + font_px * 0.10))
    return img, font_name, total


def main():
    out_dir = os.path.join(PROJ, "assets", "branding")
    os.makedirs(out_dir, exist_ok=True)

    full, font_name, total = build(with_crest=True)
    # trim the transparent surround so the PNG's own box IS the lockup — a
    # TextureRect can then be centred without hand-measuring dead pixels.
    bb = full.getbbox()
    pad = 18
    full = full.crop((max(0, bb[0] - pad), max(0, bb[1] - pad),
                      min(full.width, bb[2] + pad), min(full.height, bb[3] + pad)))
    p1 = os.path.join(out_dir, "wordmark-great-houses.png")
    full.save(p1)
    print(f"wrote {p1}  ({full.width}x{full.height}, type set in {font_name}, "
          f"tracked width {total:.0f}px)")

    flat, _, _ = build(with_crest=False)
    flat = flat.crop(flat.getbbox())
    p2 = os.path.join(out_dir, "wordmark-great-houses-flat.png")
    flat.save(p2)
    print(f"wrote {p2}  ({flat.width}x{flat.height}, type only)")


if __name__ == "__main__":
    main()
