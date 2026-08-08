#!/usr/bin/env blender --python
"""
make_crown.py — Great Houses battle-chess prop: battle-worn king's circlet.

Run headless:
  /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/make_crown.py -- <out_dir>

Outputs:
  crown.glb        — dark worn gold
  crown_frost.glb  — cold silver variant (same geometry)

Design constraints (art direction: gritty low-poly medieval):
  - low-poly ring, 14 segments
  - 7 uneven points, alternating tall/short, one slightly bent
  - subtle bevel, flat shading
  - origin at center-bottom (sits on a head), ~18 cm outer diameter
  - < 1k tris

Blender 4.0.2 bpy API. Deterministic: seeded RNG.
"""
import bpy
import math
import random
import sys

# ---------------------------------------------------------------- parameters
SEED = 77
SEGMENTS = 14          # ring segments
RADIUS = 0.090         # 18 cm diameter
BAND_H = 0.045         # band height
BAND_T = 0.006         # band thickness (solidify)
N_POINTS = 7           # spikes (odd -> alternation wraps unevenly, on purpose)
TALL = (0.062, 0.078)  # tall spike length range
SHORT = (0.036, 0.048) # short spike length range
BENT_INDEX = 2         # which spike is battle-bent
BEVEL_W = 0.0012

random.seed(SEED)

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_DIR = argv[0] if argv else "."

# ---------------------------------------------------------------- fresh scene
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


def make_material(name, base, metallic, rough):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*base, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = rough
    return m


# ---------------------------------------------------------------- band (ring)
bpy.ops.mesh.primitive_cylinder_add(
    vertices=SEGMENTS, radius=RADIUS, depth=BAND_H,
    end_fill_type='NOTHING', location=(0, 0, BAND_H / 2))
band = bpy.context.active_object
band.name = "CrownBand"
solid = band.modifiers.new("Solid", 'SOLIDIFY')
solid.thickness = BAND_T
solid.offset = -1.0          # thicken inward, outer wall stays at RADIUS

# ---------------------------------------------------------------- spikes
spikes = []
for i in range(N_POINTS):
    ang = i * 2.0 * math.pi / N_POINTS
    tall = (i % 2 == 0)
    length = random.uniform(*(TALL if tall else SHORT))
    w = random.uniform(0.026, 0.032)   # tangential base width
    d = BAND_T + 0.002                 # radial depth, proud of the band

    bpy.ops.mesh.primitive_cube_add(size=1)
    sp = bpy.context.active_object
    sp.name = f"Point{i}"
    me = sp.data
    for v in me.vertices:
        # cube -0.5..0.5 -> base cross-section w x d, height 'length', base z=0
        top = v.co.z > 0
        v.co.x *= w
        v.co.y *= d
        v.co.z = (v.co.z + 0.5) * length
        if top:
            v.co.x *= 0.14   # taper to a worn point
            v.co.y *= 0.40
    if i == BENT_INDEX:
        # battle-bent: lean the upper half sideways
        for v in me.vertices:
            if v.co.z > length * 0.5:
                v.co.x += (v.co.z - length * 0.5) * 0.55
    # small irregular jitters — worn, not pristine
    sp.rotation_euler = (
        math.radians(random.uniform(-3.0, 3.0)),   # radial lean
        math.radians(random.uniform(-2.5, 2.5)),   # tangential lean
        ang + math.pi / 2 + math.radians(random.uniform(-2.0, 2.0)))
    # sit on the band, slightly embedded; wall center is RADIUS - BAND_T/2
    r = RADIUS - BAND_T / 2
    sp.location = (math.cos(ang) * r, math.sin(ang) * r, BAND_H - 0.008)
    spikes.append(sp)

# ---------------------------------------------------------------- join + finish
for ob in spikes + [band]:
    ob.select_set(True)
bpy.context.view_layer.objects.active = band
bpy.ops.object.join()
crown = bpy.context.active_object
crown.name = "Crown"
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
# origin now at world (0,0,0) = center-bottom; band bottom rests on z=0

bev = crown.modifiers.new("Bevel", 'BEVEL')
bev.width = BEVEL_W
bev.segments = 1
bev.limit_method = 'ANGLE'
bev.angle_limit = math.radians(40.0)

gold = make_material("crown_gold_worn", (0.42, 0.28, 0.09), 0.90, 0.45)
crown.data.materials.append(gold)

# flat shading = low-poly gritty
for p in crown.data.polygons:
    p.use_smooth = False


def tri_count(ob):
    deps = bpy.context.evaluated_depsgraph_get()
    me = ob.evaluated_get(deps).to_mesh()
    me.calc_loop_triangles()
    n = len(me.loop_triangles)
    ob.evaluated_get(deps).to_mesh_clear()
    return n


def export(path):
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(
        filepath=path, export_format='GLB', export_apply=True,
        export_yup=True)


print(f"[crown] tris (post-modifier): {tri_count(crown)}")
export(f"{OUT_DIR}/crown.glb")
print(f"[crown] wrote {OUT_DIR}/crown.glb")

# ---------------------------------------------------------------- frost variant
bsdf = gold.node_tree.nodes["Principled BSDF"]
gold.name = "crown_frost"
bsdf.inputs["Base Color"].default_value = (0.62, 0.70, 0.78, 1.0)  # cold silver
bsdf.inputs["Metallic"].default_value = 0.90
bsdf.inputs["Roughness"].default_value = 0.38
export(f"{OUT_DIR}/crown_frost.glb")
print(f"[crown] wrote {OUT_DIR}/crown_frost.glb")
