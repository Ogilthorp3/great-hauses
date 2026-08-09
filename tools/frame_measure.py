#!/usr/bin/env python3
"""frame_measure.py — reproduce the art critic's numbers on a shipped frame.

Every claim in this repo's art defects must cite a measurement taken from the
frame that actually ships, not from a close-up preview.  This is that ruler.

Usage:
    python3 tools/frame_measure.py flare  <png> [x0 y0 x1 y1]
    python3 tools/frame_measure.py fire   <png>
    python3 tools/frame_measure.py rect   <png> x0 y0 x1 y1
    python3 tools/frame_measure.py sigil  <png> x0 y0 x1 y1
"""
import sys

import numpy as np
from PIL import Image


def load(path):
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float64) / 255.0


def rel_lum(rgb):
    c = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    return 0.2126 * c[..., 0] + 0.7152 * c[..., 1] + 0.0722 * c[..., 2]


def contrast(l1, l2):
    hi, lo = max(l1, l2), min(l1, l2)
    return (hi + 0.05) / (lo + 0.05)


def hsv(img):
    mx = img.max(axis=-1)
    mn = img.min(axis=-1)
    d = mx - mn
    s = np.where(mx > 0, d / np.maximum(mx, 1e-9), 0.0)
    return mx, s  # value, saturation


def cmd_flare(path, box=None):
    """Clipping census of a bright flare: how much of the frame is at v==1."""
    img = load(path)
    if box:
        x0, y0, x1, y1 = box
        img = img[y0:y1, x0:x1]
    v, _ = hsv(img)
    n = v.size
    print(f"file={path} region={img.shape[1]}x{img.shape[0]}")
    print(f"  v_max      = {v.max():.4f}")
    print(f"  v95        = {np.percentile(v, 95):.4f}")
    print(f"  v99        = {np.percentile(v, 99):.4f}")
    print(f"  v99.9      = {np.percentile(v, 99.9):.4f}")
    for t in (0.999, 0.98, 0.95, 0.90):
        k = int((v >= t).sum())
        print(f"  px v>={t:<5} = {k:7d}  ({100.0 * k / n:6.3f}% of region)")
    # Hard-edge probe: the largest single-pixel value jump on the boundary of
    # the v>=0.90 blob.  A soft falloff never steps more than a few percent.
    hot = v >= 0.90
    if hot.any():
        ys, xs = np.nonzero(hot)
        print(f"  hot bbox   = x {xs.min()}..{xs.max()}  y {ys.min()}..{ys.max()}"
              f"  ({xs.max() - xs.min() + 1}x{ys.max() - ys.min() + 1} px)")
        gy, gx = np.gradient(v)
        grad = np.hypot(gx, gy)
        edge = hot ^ _erode(hot)
        if edge.any():
            print(f"  edge |grad| p50={np.percentile(grad[edge], 50):.4f} "
                  f"p95={np.percentile(grad[edge], 95):.4f} "
                  f"max={grad[edge].max():.4f}")
    else:
        print("  hot bbox   = (nothing at v>=0.90)")


def _erode(mask):
    m = mask.copy()
    m[1:, :] &= mask[:-1, :]
    m[:-1, :] &= mask[1:, :]
    m[:, 1:] &= mask[:, :-1]
    m[:, :-1] &= mask[:, 1:]
    return m


def cmd_fire(path):
    """Is there actual FIRE in this frame?  Fire = hot hue (0..60 deg), high
    value, and a spread of values (a jet is a gradient, a grey square is flat).
    """
    img = load(path)
    v, s = hsv(img)
    r, g, b = img[..., 0], img[..., 1], img[..., 2]
    fire = (r > 0.45) & (r > b + 0.18) & (s > 0.30) & (v > 0.35)
    n = fire.sum()
    total = v.size
    print(f"file={path} size={img.shape[1]}x{img.shape[0]}")
    print(f"  fire px     = {n} ({100.0 * n / total:.3f}% of frame)")
    if n:
        ys, xs = np.nonzero(fire)
        print(f"  fire bbox   = x {xs.min()}..{xs.max()} y {ys.min()}..{ys.max()}")
        print(f"  fire v      = mean {v[fire].mean():.3f} max {v[fire].max():.3f} "
              f"sd {v[fire].std():.3f}")
        print(f"  fire sat    = mean {s[fire].mean():.3f} max {s[fire].max():.3f}")
        print(f"  fire hue R/G= {r[fire].mean():.3f}/{g[fire].mean():.3f} "
              f"B {b[fire].mean():.3f}")
    # Flat-grey-square probe: big axis-aligned runs of identical low-sat pixels.
    grey = (s < 0.12) & (v > 0.25) & (v < 0.75)
    print(f"  flat-grey px= {grey.sum()} ({100.0 * grey.sum() / total:.3f}%)")


def cmd_rect(path, box):
    x0, y0, x1, y1 = box
    img = load(path)[y0:y1, x0:x1]
    v, s = hsv(img)
    lum = rel_lum(img)
    print(f"file={path} rect=({x0},{y0})-({x1},{y1})")
    print(f"  mean rgb = {img.reshape(-1, 3).mean(axis=0).round(4).tolist()}")
    print(f"  v mean={v.mean():.4f} min={v.min():.4f} max={v.max():.4f} "
          f"p95={np.percentile(v, 95):.4f}")
    print(f"  s mean={s.mean():.4f}   lum mean={lum.mean():.5f} "
          f"p05={np.percentile(lum, 5):.5f} p95={np.percentile(lum, 95):.5f}")


def cmd_sigil(path, box):
    """Sigil-vs-cloth value contrast inside a banner rect.

    Splits the rect's luminance at Otsu, calls the brighter cluster the charge
    and the darker one the cloth (or vice-versa), and reports the WCAG contrast
    ratio between the two cluster means — the number a glance actually obeys.
    """
    x0, y0, x1, y1 = box
    img = load(path)[y0:y1, x0:x1]
    lum = rel_lum(img).ravel()
    hist, edges = np.histogram(lum, bins=64)
    tot = hist.sum()
    best, thr = -1.0, edges[1]
    for i in range(1, 64):
        w0 = hist[:i].sum() / tot
        w1 = 1.0 - w0
        if w0 <= 0 or w1 <= 0:
            continue
        mids = (edges[:-1] + edges[1:]) / 2
        m0 = (hist[:i] * mids[:i]).sum() / hist[:i].sum()
        m1 = (hist[i:] * mids[i:]).sum() / hist[i:].sum()
        var = w0 * w1 * (m0 - m1) ** 2
        if var > best:
            best, thr = var, edges[i]
    dark = lum[lum < thr]
    light = lum[lum >= thr]
    print(f"file={path} rect=({x0},{y0})-({x1},{y1})")
    print(f"  split lum   = {thr:.5f}")
    print(f"  cloth  mean = {dark.mean():.5f}  ({dark.size} px)")
    print(f"  charge mean = {light.mean():.5f}  ({light.size} px)")
    print(f"  CONTRAST    = {contrast(dark.mean(), light.mean()):.2f} : 1")


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    mode, path = sys.argv[1], sys.argv[2]
    box = [int(a) for a in sys.argv[3:7]] if len(sys.argv) >= 7 else None
    if mode == "flare":
        cmd_flare(path, box)
    elif mode == "fire":
        cmd_fire(path)
    elif mode == "rect":
        cmd_rect(path, box)
    elif mode == "sigil":
        cmd_sigil(path, box)
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
