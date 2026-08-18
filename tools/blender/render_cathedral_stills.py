"""Render verification stills of the shipped cathedral GLB (headless EEVEE).

Imports the exported GLB fresh — so what renders here is what Godot loads,
not whatever was in the builder's session. Night rig: deep-blue moonlight,
warm interior bounce stand-ins, emissive glass carries itself.

Run: blender -b -P tools/blender/render_cathedral_stills.py -- \
        --glb <path.glb> --out <dir> [--shot NAME]
"""

import math
import sys

import bpy
from mathutils import Vector

# godot (x, y, z) -> blender (x, -z, y); camera positions are authored in
# godot coords to match the cinematic's numbers.


def G(x, y, z):
    return Vector((x, -z, y))


SHOTS = {
    # name: (cam godot pos, look-at godot pos, fov degrees)
    "01_establishing_sw": ((-74.0, 6.0, -88.0), (0.0, 24.0, -14.0), 42),
    "02_west_facade": ((0.0, 16.0, -55.0), (0.0, 22.0, -26.0), 50),
    "03_spires_close": ((-24.0, 38.0, -42.0), (8.0, 34.0, -24.0), 55),
    "04_rose_dragon_door": ((0.0, 20.5, -37.0), (0.0, 20.5, -26.0), 42),
    "05_nave_from_rose": ((0.0, 19.0, -24.0), (0.0, 8.0, 10.0), 60),
    "06_nave_run_low": ((0.0, 5.0, -6.0), (0.0, 11.0, 14.0), 62),
    "07_gallery_perch": ((-6.5, 10.5, 4.5), (0.0, 12.4, 13.6), 45),
    "08_gallery_closeup": ((3.0, 13.5, 9.0), (0.0, 12.3, 13.6), 40),
    "09_gameplay_frame": ((0.0, 9.04, -7.59), (0.0, 0.7, 2.5), 50),
    "10_orbit_high": ((9.0, 13.0, -9.0), (0.0, 2.0, 2.0), 55),
    "11_exterior_east": ((30.0, 12.0, 48.0), (0.0, 20.0, 10.0), 48),
    "12_aerial": ((-38.0, 55.0, -48.0), (0.0, 12.0, 0.0), 50),
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []

    def arg(flag, default=None):
        return argv[argv.index(flag) + 1] if flag in argv else default

    glb = arg("--glb")
    out = arg("--out", "/tmp/cathedral_stills")
    only = arg("--shot")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb)

    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.eevee.taa_render_samples = 24
    scene.eevee.use_shadows = True

    world = bpy.data.worlds.new("night")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.010, 0.014, 0.030, 1.0)
    bg.inputs[1].default_value = 1.0
    scene.world = world

    # moon: cool key from the SW-high
    moon = bpy.data.objects.new("Moon", bpy.data.lights.new("Moon", 'SUN'))
    moon.data.energy = 2.6
    moon.data.color = (0.62, 0.72, 1.0)
    moon.data.angle = 0.03
    moon.rotation_euler = (math.radians(55), 0, math.radians(-140))
    scene.collection.objects.link(moon)

    # interior torch stand-ins (the hall owns the real ones): warm points
    for gp in [(0, 4.0, 0), (0, 6.0, -16), (0, 7.0, 8), (8, 3.0, 0),
               (-8, 3.0, 0), (0, 12.0, -2), (0, 10.0, 12)]:
        li = bpy.data.lights.new("torch", 'POINT')
        li.energy = 14000.0
        li.color = (1.0, 0.62, 0.28)
        li.shadow_soft_size = 0.6
        ob = bpy.data.objects.new("torch", li)
        ob.location = G(*gp)
        scene.collection.objects.link(ob)

    cam_data = bpy.data.cameras.new("Cam")
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam

    for name, (pos, look, fov) in SHOTS.items():
        if only and only != name:
            continue
        cam.location = G(*pos)
        direction = G(*look) - cam.location
        cam.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
        cam_data.angle = math.radians(fov)
        scene.render.filepath = f"{out}/{name}.png"
        bpy.ops.render.render(write_still=True)
        print(f"[stills] rendered {name}")


if __name__ == "__main__":
    main()
