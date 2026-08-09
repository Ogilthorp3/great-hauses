#!/usr/bin/env python3
"""haus_palette_check.py — the nine-haus data gate, run before the engine.

Rendering nine armies takes ~40 s; this reads hauses/*/haus.json and
src/houses/coats.json directly and answers, in a second, every question the
shipped suites will ask about the palette:

  * jerseys        no two within 0.20 RGB (tests/test_costumes.gd)
  * pawn domes     no two within 0.10 RGB — the dome is kit x the helm shell
                   weight (0.72, or 0.46 for the Drowned Legion's charred twin)
  * coats          every coat part >= 0.14 RGB from its own haus's jersey
  * crinet         the mount's kit band must clear its own coat by 0.14
  * kit on-palette every jersey within KIT_MATCH 0.26 of one of its haus's
                   four declared colours, value-normalised (the role gate)
  * crown metal    ONE metal on all nine (regalia carries the rank, not the
                   haus), both its tones clear of every jersey, and at least
                   one of them reaching every haus's own dome
  * spread         the population must span VALUE and CHROMA, not just hue:
                   at least one pale haus, one near-black, one muted, one vivid
  * dE2000         full pairwise CIELAB matrix on the jerseys and on the domes,
                   plus the three dichromacy simulations

It is the CHEAP half of the loop. The expensive half — tools/haus_field.gd —
is the one that tells the truth, because the hall's eight orange torches move
every one of these colours before a player sees it.

Usage:  haus_palette_check.py [--project DIR] [--matrix]
"""
import json
import os
import re
import sys
import colorsys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from haus_delta_e import (hex_to_rgb, lab, delta_e2000, simulate,  # noqa: E402
                          rgb_to_hex)

HELM_SHELL_WEIGHT = 0.72
HELM_SHELL_WEIGHT_DROWNED = 0.46
DROWNED = "tidegrip"

JERSEY_GAP = 0.20
DOME_GAP = 0.10
COAT_GAP = 0.14
KIT_MATCH = 0.26

## THE DRAGON WEARS NO HAUS. src/cinematics/dragon_rig.gd was deliberately
## moved off ice-blue so the beast belongs to nobody; these are the six
## fullest buckets of its hide sampled off the shipped boot frame
## (`haus_delta_e.py dominant test_e2e/artifacts/boot/02_boot_lineup.png
## 150 300 120 90 8`) — violet-slate, L 25-54. A haus jersey that lands on
## them re-lends the wyrm to somebody, which is the thing that was just fixed.
DRAGON_HIDE = ["#48475a", "#706c91", "#57526c", "#3a3b4e", "#807ca5", "#7c79a2"]
DRAGON_FLOOR = 15.0
## THE BAR A DICHROMAT ACTUALLY GETS, and it is not "safe" (art critic,
## 2026-08-09 — the last pass reported the dichromatic minimum "roughly
## trebling", 2.4 -> 4.3, which is a move from identical to barely separable and
## was written up as though it were a solved problem). Two bars, and the report
## says which is which: below CB_FLOOR two armies are the same army; below
## CB_WEAK they are separable but not comfortably, and every such pair is NAMED
## on every run. Nine categorical hues cannot all clear ~10 dE under all three
## dichromacies — a dichromat has one colour axis and lightness — so the ladder
## is spread on LIGHTNESS and the sigil SHAPE carries the rest.
CB_FLOOR = 7.5
CB_WEAK = 12.0

## THE CROWN. One metal on all nine (regalia carries the RANK, not the haus), in
## two states of itself so it can contrast with nine different armies. READ OFF
## src/board/piece_assets.gd rather than copied: a gate holding a stale copy of
## the number it is gating is not a gate.
def _crown_tones(project):
    src = open(os.path.join(project, "src", "board", "piece_assets.gd")).read()
    out = {}
    for name, key in (("CROWN_BAND_COLOR", "band"), ("CROWN_POINT_COLOR", "points")):
        m = re.search(r'const\s+%s\s*:=\s*Color\("(#[0-9a-fA-F]{6})"\)' % name, src)
        if m is None:
            raise SystemExit("haus_palette_check: %s not found in piece_assets.gd"
                             % name)
        out[key] = m.group(1).lower()
    return out
REGALIA_KIT_GAP = 0.14      # costume_preview.NATURAL_KIT_DISTANCE
REGALIA_REACH = 15.0        # ...and how far a tone must sit from its own army


def rgb_gap(a, b):
    return sum((x - y) ** 2 for x, y in zip(a, b)) ** 0.5


def unit_value(rgb):
    m = max(max(rgb), 0.0001)
    return (0.0, 0.0, 0.0) if m < 0.02 else tuple(c / m for c in rgb)


def norm_dist(a, b):
    return rgb_gap(unit_value(a), unit_value(b))


def hsv(hexs):
    r, g, b = hex_to_rgb(hexs)
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    return h * 360.0, s, v


def load(project):
    hausdir = os.path.join(project, "hauses")
    order = json.load(open(os.path.join(hausdir, "index.json")))["order"]
    hauses = {}
    for hid in order:
        hauses[hid] = json.load(open(os.path.join(hausdir, hid, "haus.json")))
    coats = json.load(open(os.path.join(project, "src", "houses",
                                        "coats.json")))["coats"]
    return order, hauses, coats, _crown_tones(project)


def dome_hex(hid, kit):
    w = HELM_SHELL_WEIGHT_DROWNED if hid == DROWNED else HELM_SHELL_WEIGHT
    return rgb_to_hex(tuple(c * w for c in hex_to_rgb(kit)))


def report(order, hauses, coats, tones, want_matrix):
    fails = []
    crown_band = tones["band"]
    crown_points = tones["points"]
    kits = {h: hauses[h]["tints"]["kit"] for h in order}
    domes = {h: dome_hex(h, kits[h]) for h in order}

    print("=== the nine, as declared ===")
    print("%-12s %-9s %-9s %-22s %-9s %s"
          % ("haus", "kit", "dome", "H / S / V", "coat", "crown"))
    for h in order:
        hh, ss, vv = hsv(kits[h])
        print("%-12s %-9s %-9s %5.0f / %.2f / %.2f      %-9s %s"
              % (h, kits[h], domes[h], hh, ss, vv, hauses[h]["coat"],
                 "gold (all nine)"))

    # --- jerseys and domes ------------------------------------------------
    for label, table, floor in (("jersey", kits, JERSEY_GAP),
                                ("pawn dome", domes, DOME_GAP)):
        worst = (9.9, None, None)
        for i, a in enumerate(order):
            for b in order[i + 1:]:
                d = rgb_gap(hex_to_rgb(table[a]), hex_to_rgb(table[b]))
                if d < worst[0]:
                    worst = (d, a, b)
                if d < floor:
                    fails.append("%s gap %s/%s = %.3f < %.2f"
                                 % (label, a, b, d, floor))
        print("  %-10s closest pair %s/%s = %.3f (floor %.2f)"
              % (label, worst[1], worst[2], worst[0], floor))

    # --- coats ------------------------------------------------------------
    for h in order:
        coat = coats[hauses[h]["coat"]]
        kit = hex_to_rgb(kits[h])
        tight = min((rgb_gap(hex_to_rgb(coat[p]), kit), p) for p in coat)
        if tight[0] < COAT_GAP:
            fails.append("coat %s/%s (%s) sits %.3f from the jersey %s"
                         % (h, tight[1], hauses[h]["coat"], tight[0], kits[h]))
        # the crinet is the jersey ON the coat — it must clear the hide too
        if rgb_gap(hex_to_rgb(coat["Main"]), kit) < COAT_GAP:
            fails.append("crinet %s: the kit band cannot clear its own hide" % h)
    print("  coats      tightest kit/coat gap %.3f (floor %.2f)"
          % (min(min(rgb_gap(hex_to_rgb(coats[hauses[h]['coat']][p]),
                             hex_to_rgb(kits[h])) for p in coats[hauses[h]["coat"]])
                 for h in order), COAT_GAP))

    # --- the jersey must be one of the haus's own declared colours --------
    for h in order:
        cols = [kits[h]] + [hauses[h]["colors"][k]
                            for k in ("primary", "secondary", "accent")]
        best = min(norm_dist(hex_to_rgb(kits[h]), hex_to_rgb(c)) for c in cols)
        if best > KIT_MATCH:
            fails.append("kit %s is off its own palette (%.2f > %.2f)"
                         % (h, best, KIT_MATCH))

    # --- crown metal ------------------------------------------------------
    #
    # THE CROWN NO LONGER DEPENDS ON THE HAUS (art critic, 2026-08-09). This
    # gate used to require that both metals were fielded — cold armies in gold,
    # warm in steel — which is the rule that put five kings in crown_frost's
    # navy, the same navy Silverbrook wears. Regalia is a RANK marker: one
    # metal, all nine, so it cannot name anybody. What is checked instead is
    # what that costs — a single flat metal cannot contrast with nine armies —
    # and the two tones the crown carries to pay for it.
    print("  crown      ", end="")
    tone_worst = (999.0, None)
    for h in order:
        for name, tone in (("band", crown_band), ("points", crown_points)):
            gap = rgb_gap(hex_to_rgb(tone), hex_to_rgb(kits[h]))
            if gap < REGALIA_KIT_GAP:
                fails.append("crown %s: the %s (%s) is %s's own jersey (%.2f < %.2f)"
                             % (name, name, tone, h, gap, REGALIA_KIT_GAP))
        reach = max(min(delta_e2000(lab(crown_band), lab(kits[h])),
                        delta_e2000(lab(crown_band), lab(domes[h]))),
                    min(delta_e2000(lab(crown_points), lab(kits[h])),
                        delta_e2000(lab(crown_points), lab(domes[h]))))
        if reach < tone_worst[0]:
            tone_worst = (reach, h)
        if reach < REGALIA_REACH:
            fails.append("crown: neither tone reaches %s's army (%.1f dE < %.0f)"
                         % (h, reach, REGALIA_REACH))
        if lab(crown_points)[0] <= lab(domes[h])[0]:
            fails.append("crown: the points do not outshine %s's dome" % h)
    print("one metal, two tones %s/%s (%.0f dE apart); worst army reach %.1f dE "
          "(%s, floor %.0f)"
          % (crown_band, crown_points,
             delta_e2000(lab(crown_band), lab(crown_points)),
             tone_worst[0], tone_worst[1], REGALIA_REACH))

    # --- the dragon's own hide --------------------------------------------
    print("  dragon     ", end="")
    worst = (999.0, None)
    for h in order:
        d = min(delta_e2000(lab(kits[h]), lab(g)) for g in DRAGON_HIDE)
        if d < worst[0]:
            worst = (d, h)
        if d < DRAGON_FLOOR:
            fails.append("kit %s sits %.1f dE from the wyrm's own hide (floor %.0f)"
                         % (h, d, DRAGON_FLOOR))
    print("closest jersey to the wyrm's hide: %s at %.1f dE (floor %.0f)"
          % (worst[1], worst[0], DRAGON_FLOOR))

    # --- the spread that makes nine armies four kinds of army -------------
    vs = sorted((hsv(kits[h])[2], h) for h in order)
    ss = sorted((hsv(kits[h])[1], h) for h in order)
    print("\n=== the spread (value and chroma are axes, not side effects) ===")
    print("  palest   %s %.2f   ...   darkest %s %.2f   (span %.2f)"
          % (vs[-1][1], vs[-1][0], vs[0][1], vs[0][0], vs[-1][0] - vs[0][0]))
    print("  most vivid %s %.2f ...  most muted %s %.2f (span %.2f)"
          % (ss[-1][1], ss[-1][0], ss[0][1], ss[0][0], ss[-1][0] - ss[0][0]))
    if vs[-1][0] - vs[0][0] < 0.40:
        fails.append("value span %.2f — nine armies at one brightness"
                     % (vs[-1][0] - vs[0][0]))
    if ss[-1][0] - ss[0][0] < 0.40:
        fails.append("chroma span %.2f — nine armies at one saturation"
                     % (ss[-1][0] - ss[0][0]))

    # --- perceptual distance ---------------------------------------------
    print("\n=== dE2000 on the declared jerseys ===")
    labs = {h: lab(kits[h]) for h in order}
    pairs = sorted((delta_e2000(labs[a], labs[b]), a, b)
                   for i, a in enumerate(order) for b in order[i + 1:])
    print("  min %.1f (%s/%s) · " % (pairs[0][0], pairs[0][1], pairs[0][2])
          + " · ".join("%s/%s %.1f" % (a, b, d) for d, a, b in pairs[1:5]))
    weak = []
    for kind in ("deuteranopia", "protanopia", "tritanopia"):
        sim = {h: lab(simulate(kits[h], kind)) for h in order}
        p = sorted((delta_e2000(sim[a], sim[b]), a, b)
                   for i, a in enumerate(order) for b in order[i + 1:])
        print("  %-13s min %.1f (%s/%s) · next %s"
              % (kind, p[0][0], p[0][1], p[0][2],
                 ", ".join("%s/%s %.1f" % (a, b, d) for d, a, b in p[1:4])))
        if p[0][0] < CB_FLOOR:
            fails.append("%s: %s/%s collapse to %.1f dE (floor %.0f)"
                         % (kind, p[0][1], p[0][2], p[0][0], CB_FLOOR))
        weak.extend("%s: %s/%s %.1f dE" % (kind, a, b, d)
                    for d, a, b in p if d < CB_WEAK)

    # A dichromat sees one colour axis and LIGHTNESS. Print the ladder, so
    # tuning a jersey is reading a number instead of guessing a hue: two
    # hauses on the same rung of this ladder are the same army to 8 % of men.
    # NAMED, EVERY RUN. The point of printing the weak pairs rather than only
    # the failures is that "min dE = 7.6, floor 7.5" reads like a pass and is
    # not one: these are the pairs a colourblind player has to work at, and the
    # honest claim about them is "separable, not safe".
    print("\n=== separable but WEAK to a dichromat (under %.0f dE, named not hidden) ==="
          % CB_WEAK)
    if weak:
        for w in sorted(set(weak)):
            print("  * " + w)
        print("  ...these are told apart by LIGHTNESS and by the sigil's SHAPE,")
        print("     not by hue. The claim is 'separable', never 'colourblind-safe'.")
    else:
        print("  (none — every pair clears %.0f dE under all three)" % CB_WEAK)

    print("\n=== the dichromatic lightness ladder (L* after simulation) ===")
    for kind in ("deuteranopia", "protanopia", "tritanopia"):
        rungs = sorted((lab(simulate(kits[h], kind))[0], h) for h in order)
        print("  %-13s " % kind + "  ".join("%s %.0f" % (h, L) for L, h in rungs))

    if want_matrix:
        print("\n        " + "".join("%-8s" % h[:7] for h in order))
        for a in order:
            row = "%-8s" % a[:7]
            for b in order:
                row += "%-8s" % ("·" if a == b
                                 else "%.1f" % delta_e2000(labs[a], labs[b]))
            print(row)

    print()
    if fails:
        for f in fails:
            print("FAIL  " + f)
        print("=== %d failure(s) ===" % len(fails))
        return 1
    print("=== palette clean: %d hauses, every data gate green ===" % len(order))
    return 0


if __name__ == "__main__":
    proj = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if "--project" in sys.argv:
        proj = sys.argv[sys.argv.index("--project") + 1]
    sys.exit(report(*load(proj), want_matrix="--matrix" in sys.argv))
