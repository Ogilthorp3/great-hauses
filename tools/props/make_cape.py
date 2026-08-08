#!/usr/bin/env blender --python
"""
make_cape.py — Great Houses: the king's cape (TYPE signature gear).

Run headless:
  /Applications/Blender.app/Contents/MacOS/Blender -b --python \
      tools/props/make_cape.py -- <out_dir>

Output: cape.glb — a low-poly draped cape sheet, neutral mid-grey cloth
(runtime multiplies it with the house secondary color via the standard
tint pipeline; legacy sides get the FROST/EMBER tint).

Authored in KayKit Rig_Medium CHEST-BONE space, mirroring the rigid
Skeleton_Rogue cape convention observed in the pack (chest BoneAttachment,
mesh hanging bone -Y, draped behind at bone -Z):
  - Blender: origin at the shoulder line, sheet hangs -Z, drapes toward +Y
    (export_yup maps Blender (x,y,z)->(x,z,-y): hang -Z -> Godot -Y, drape
    +Y -> Godot -Z = behind the character). Runtime attach: BoneAttachment3D
    on `chest`, position ~(0, 0.02, -0.06), scale 1.0.
  - grid sheet with seeded ripple + flare so it reads as cloth, not card
  - solidified slightly so both sides render without runtime cull tricks
  - < 600 tris, flat shading. Deterministic: seeded RNG.

Blender 4.0.2 bpy API.
"""
import bpy
import math
import os
import random
import sys

SEED = 4114
random.seed(SEED)

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_DIR = argv[0] if argv else "."

COLS = 7        # across (X)
ROWS = 9        # down (-Z)
TOP_W = 0.86    # shoulder width
BOT_W = 1.22    # hem flare
LENGTH = 1.18   # shoulder -> hem
DRAPE = 0.34    # how far the hem swings back (+Y)
THICK = 0.015

bpy.ops.wm.read_factory_settings(use_empty=True)

mesh = bpy.data.meshes.new("cape")
verts = []
faces = []
for r in range(ROWS + 1):
    t = r / ROWS
    w = TOP_W + (BOT_W - TOP_W) * (t ** 1.3)
    z = -LENGTH * t
    y = DRAPE * (t ** 1.7)
    for c in range(COLS + 1):
        u = c / COLS - 0.5
        x = u * w
        # cloth ripple: gentle vertical waves that grow toward the hem
        ripple = math.sin(u * math.pi * 2.6 + t * 2.0) * 0.045 * t
        ripple += random.uniform(-0.008, 0.008) * t
        verts.append((x, y + ripple, z))
for r in range(ROWS):
    for c in range(COLS):
        a = r * (COLS + 1) + c
        b = a + 1
        d = a + (COLS + 1)
        e = d + 1
        faces.append((a, b, e, d))
mesh.from_pydata(verts, [], faces)
mesh.update()
ob = bpy.data.objects.new("Cape", mesh)
bpy.context.collection.objects.link(ob)
bpy.context.view_layer.objects.active = ob
ob.select_set(True)

solid = ob.modifiers.new("Solid", 'SOLIDIFY')
solid.thickness = THICK
solid.offset = 0.0

m = bpy.data.materials.new("cape_cloth")
m.use_nodes = True
bsdf = m.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.44, 0.42, 0.40, 1.0)  # neutral: tinted at runtime
bsdf.inputs["Metallic"].default_value = 0.0
bsdf.inputs["Roughness"].default_value = 0.95
ob.data.materials.append(m)
for p in ob.data.polygons:
    p.use_smooth = False

deps = bpy.context.evaluated_depsgraph_get()
me = ob.evaluated_get(deps).to_mesh()
me.calc_loop_triangles()
n = len(me.loop_triangles)
ob.evaluated_get(deps).to_mesh_clear()

path = os.path.join(OUT_DIR, "cape.glb")
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=path, export_format='GLB',
                          export_apply=True, export_yup=True)
print("[cape] %d tris -> %s" % (n, path))
