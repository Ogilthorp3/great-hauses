#!/usr/bin/env python3
"""
Build the two OS bundle icons from the icon generator: GreatHouses.icns
(macOS) and GreatHouses.ico (Windows).

    python3 tools/branding/make_icns.py

Why this is not `sips -z` off the 1024 master: the generator draws every size at
its own DETAIL TIER (gen_app_icon.py: tier_of()).  A 16px member downsampled
from 1024 is mud; a 16px member DRAWN at 16 keeps the shield point, the gold
rim and the charge's cross as whole pixels.  So every .iconset member is
rendered natively at its own pixel size, exactly as the dock will show it.

Members written (the ten Apple asks for):
    16 / 16@2x=32 / 32 / 32@2x=64 / 128 / 128@2x=256 / 256 / 256@2x=512
    512 / 512@2x=1024

Output:  assets/branding/GreatHouses.icns   (macOS, via iconutil)
         assets/branding/GreatHouses.ico    (Windows, 16..256 members)

Where they go — these are EXPORT PRESET icons, not the Godot project icon.
In export_presets.cfg, under [preset.<n>.options]:

    macOS preset:    application/icon="res://assets/branding/GreatHouses.icns"
    Windows preset:  application/icon="res://assets/branding/GreatHouses.ico"
                     application/console_wrapper_icon="res://assets/branding/GreatHouses.ico"

(project.godot's config/icon is a separate thing — it is the editor/project-
manager icon and wants a res:// PNG.  It is already set to
res://assets/branding/app-icon-1024.png.)
"""

import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(os.path.dirname(HERE))      # the Godot project root
sys.path.insert(0, HERE)

import gen_app_icon as G  # noqa: E402

# (iconset member name, pixel size actually rendered)
MEMBERS = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]


def main():
    out_dir = os.path.join(PROJ, "assets", "branding")
    os.makedirs(out_dir, exist_ok=True)
    iconset = os.path.join(out_dir, "GreatHouses.iconset")
    shutil.rmtree(iconset, ignore_errors=True)
    os.makedirs(iconset)

    cache = {}
    for name, px in MEMBERS:
        if px not in cache:
            cache[px] = G.render(px)
            print(f"  rendered {px}px at tier '{G.tier_of(px)}'")
        cache[px].save(os.path.join(iconset, name))

    icns = os.path.join(out_dir, "GreatHouses.icns")
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", icns], check=True)
    shutil.rmtree(iconset)          # the .icns is the artifact; the dir is scratch
    print("wrote", icns, os.path.getsize(icns), "bytes")

    # Windows .ico — same natively-drawn tiers, capped at 256 (the format's max
    # uncompressed member and all the Windows shell asks for).
    ico = os.path.join(out_dir, "GreatHouses.ico")
    ico_sizes = [16, 32, 48, 64, 128, 256]
    for px in ico_sizes:
        if px not in cache:
            cache[px] = G.render(px)
            print(f"  rendered {px}px at tier '{G.tier_of(px)}'")
    cache[256].save(ico, format="ICO",
                    sizes=[(p, p) for p in ico_sizes],
                    append_images=[cache[p] for p in ico_sizes if p != 256])
    print("wrote", ico, os.path.getsize(ico), "bytes")

    print()
    print("export_presets.cfg — under [preset.<n>.options]:")
    print('  macOS   application/icon="res://assets/branding/GreatHouses.icns"')
    print('  Windows application/icon="res://assets/branding/GreatHouses.ico"')


if __name__ == "__main__":
    main()
