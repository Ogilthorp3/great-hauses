#!/usr/bin/env python3
"""Assert the visionOS export preset is immersive.

Godot defaults application/app_role to 0 (Window) and immersion_style to 1
(Mixed). Shipping either default gives a flat panel floating in the room
instead of an immersive app, and nothing else in the build catches it.
"""
import configparser
import sys

REQUIRED = {
    "application/app_role": "1",         # 0=Window, 1=Immersive
    "application/immersion_style": "0",  # 0=Full, 1=Mixed, 2=Progressive
}


def main(path: str) -> int:
    cp = configparser.ConfigParser()
    cp.optionxform = str
    cp.read(path)

    section = None
    for name in cp.sections():
        if name.endswith(".options"):
            continue
        if cp[name].get("platform", "").strip('"') == "visionOS":
            section = name + ".options"
            break

    if section is None or section not in cp:
        print("FAIL: no visionOS export preset in " + path)
        return 1

    bad = []
    for key, want in REQUIRED.items():
        got = cp[section].get(key, "<missing>").strip('"')
        if got != want:
            bad.append(f"  {key}: got {got}, want {want}")

    if bad:
        print("FAIL: visionOS preset is not immersive:")
        print("\n".join(bad))
        return 1

    print("OK: visionOS preset is app_role=Immersive, immersion_style=Full")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "export_presets.cfg"))
