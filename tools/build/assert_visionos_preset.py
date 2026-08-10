#!/usr/bin/env python3
"""Assert the visionOS build is actually immersive AND actually stereo.

Two independent silent-green traps, both checked here:

1. Godot defaults application/app_role to 0 (Window) and immersion_style to
   1 (Mixed). Shipping either default gives a flat panel floating in the
   room instead of an immersive app, and nothing else in the build catches
   it. (export_presets.cfg, [preset.N.options] for the visionOS platform.)

2. project.godot's xr/shaders/enabled defaults to false
   (rendering_server.cpp:3816) and gates whether the Mobile renderer's
   multiview shader variants are ever compiled
   (scene_shader_forward_mobile.cpp:625-627). The Mobile renderer — the only
   one visionOS immersive supports, and the one this project is pinned to
   (project.godot: rendering/rendering_method="mobile") — has NO lazy
   fallback for a missing multiview variant
   (render_forward_mobile.cpp:1033-1035); Clustered has one
   (render_forward_clustered.cpp:1888-1892), but that renderer is not an
   option here. Every other gate — including check #1 above — stays green
   while the frame is broken, so this reads project.godot too, not just
   export_presets.cfg.

Exit code 0 = both checks pass. Exit code 1 = at least one failed; the
offending key(s) are named on stdout.
"""
import configparser
import os
import sys

PRESET_REQUIRED = {
    "application/app_role": "1",         # 0=Window, 1=Immersive
    "application/immersion_style": "0",  # 0=Full, 1=Mixed, 2=Progressive
}

# (section, key) -> required value, read from project.godot.
PROJECT_REQUIRED = {
    ("xr", "shaders/enabled"): "true",
}


def _unquote(value: str) -> str:
    return value.strip().strip('"')


def _read_ini(path: str) -> configparser.ConfigParser:
    cp = configparser.ConfigParser()
    cp.optionxform = str  # preserve key case — Godot keys are case-sensitive
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    # project.godot opens with bare `config_version=5` before any [section] —
    # valid Godot ConfigFile syntax, but configparser requires every key to
    # sit under a header. Prepend a throwaway section so that preamble parses
    # instead of raising MissingSectionHeaderError; nothing here reads it.
    cp.read_string("[__preamble__]\n" + text)
    return cp


def check_preset(path: str) -> list[str]:
    if not os.path.isfile(path):
        return [f"{path}: file not found"]
    cp = _read_ini(path)

    section = None
    for name in cp.sections():
        if name.endswith(".options"):
            continue
        if _unquote(cp[name].get("platform", "")) == "visionOS":
            section = name + ".options"
            break

    if section is None or section not in cp:
        return [f"{path}: no visionOS export preset found"]

    bad = []
    for key, want in PRESET_REQUIRED.items():
        got = _unquote(cp[section].get(key, "<missing>"))
        if got != want:
            bad.append(f"{path} [{section}] {key}: got '{got}', want '{want}'")
    return bad


def check_project(path: str) -> list[str]:
    if not os.path.isfile(path):
        return [f"{path}: file not found"]
    cp = _read_ini(path)

    bad = []
    for (section, key), want in PROJECT_REQUIRED.items():
        got = _unquote(cp[section].get(key, "<missing>")) if section in cp else "<missing>"
        if got != want:
            bad.append(
                f"{path} [{section}] {key}: got '{got}', want '{want}' — "
                "defaults to false, which compiles no multiview shader "
                "variants; the Mobile renderer has no fallback, so this "
                "ships a build that cannot render a stereo frame"
            )
    return bad


def main(preset_path: str) -> int:
    # project.godot lives beside export_presets.cfg at the project root —
    # keep this callable with the SAME single argument build.sh already
    # passes it, rather than widening the CLI contract.
    project_path = os.path.join(
        os.path.dirname(os.path.abspath(preset_path)), "project.godot"
    )

    bad = check_preset(preset_path) + check_project(project_path)

    if bad:
        print("FAIL: visionOS build is not immersive/stereo:")
        for line in bad:
            print("  " + line)
        return 1

    print(
        "OK: visionOS preset is app_role=Immersive, immersion_style=Full, "
        "xr/shaders/enabled=true"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "export_presets.cfg"))
