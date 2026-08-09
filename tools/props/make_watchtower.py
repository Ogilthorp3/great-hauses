#!/usr/bin/env blender --python
"""
make_watchtower.py — Great Hauses: the BANNER-ROOK battle-worn watchtower.

Run headless:
  /Applications/Blender.app/Contents/MacOS/Blender -b --python \
      tools/props/make_watchtower.py -- <out_dir>

Output: watchtower.glb — an original low-poly stone watchtower that replaces
the Kenney tower as the rook:
  - great-hall-matched stone tones (board LIGHT_STONE is (0.36,0.33,0.30);
    the tower stone sits just under it so the haus tower-tint multiply in
    PieceAssets.tinted_material lands in the same family)
  - crenellated parapet with seeded merlon jitter; two merlons chipped and
    tilted — battle-worn, not pristine
  - "BannerCloth": a rippled cloth sheet hanging down the tower's front
    face, UV-mapped 0..1 (u across, v=0 at the TOP — Godot image convention)
    so the runtime can drop the haus sigil PNG straight in as albedo.
    Kept a SEPARATE object so PieceView can find it by name, re-skin it,
    and detach it to fall when the tower crumbles.
  - "Pennant" on "PennantPole": a small triangular flag at the top. The
    runtime swaps its material for the pennant_flutter.gdshader
    ShaderMaterial (time-based sine vertex flutter, no physics). The pennant
    root sits at local x=0 and stretches +X, so VERTEX.x is the flutter mask.

Node/mesh names are runtime API (piece_view.gd): TowerBody · BannerCloth ·
BannerRod · PennantPole · Pennant.

Conventions: origin center-bottom, Blender +Z up / front -Y -> exported Y-up,
front +Z for Godot. Tower BODY height (TowerBody mesh) is the height-grading
reference — the pennant pole is an accent allowed to poke above it.
< 4k tris. Deterministic: seeded RNG. Blender 4.0.2 bpy API.
"""
import bpy
import math
import os
import random
import sys

SEED = 1453   # the year walls stopped being enough
random.seed(SEED)

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_DIR = argv[0] if argv else "."

bpy.ops.wm.read_factory_settings(use_empty=True)


def make_material(name, base, metallic, rough):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*base, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = rough
    return m


MAT_STONE = make_material("tower_stone", (0.30, 0.28, 0.255), 0.0, 0.92)
MAT_TRIM = make_material("tower_stone_dark", (0.165, 0.155, 0.145), 0.0, 0.95)
MAT_SLIT = make_material("tower_slit", (0.025, 0.024, 0.022), 0.0, 1.0)
MAT_BANNER = make_material("banner_cloth", (0.92, 0.90, 0.86), 0.0, 0.9)
MAT_WOOD = make_material("tower_wood", (0.21, 0.14, 0.09), 0.0, 0.85)
MAT_PENNANT = make_material("pennant_cloth", (0.85, 0.82, 0.78), 0.0, 0.9)


def add_box(size, loc, mat, taper=1.0, rot=(0, 0, 0)):
    """Cube with base at loc.z, sized size, top-face taper."""
    bpy.ops.mesh.primitive_cube_add(size=1)
    ob = bpy.context.active_object
    for v in ob.data.vertices:
        top = v.co.z > 0
        v.co.x *= size[0]
        v.co.y *= size[1]
        v.co.z = (v.co.z + 0.5) * size[2]
        if top and taper != 1.0:
            v.co.x *= taper
            v.co.y *= taper
    ob.rotation_euler = rot
    ob.location = loc
    ob.data.materials.append(mat)
    return ob


stone_parts = []

# ---------------------------------------------------------------- masonry
PLINTH_H = 0.10
SHAFT_H = 1.00
PARAPET_Z = PLINTH_H + SHAFT_H            # 1.10
stone_parts.append(add_box((0.92, 0.92, PLINTH_H), (0, 0, 0), MAT_TRIM))
stone_parts.append(add_box((0.70, 0.70, SHAFT_H), (0, 0, PLINTH_H),
                           MAT_STONE, taper=0.86))
# mid string-course band
stone_parts.append(add_box((0.72, 0.72, 0.055), (0, 0, 0.56), MAT_TRIM))
# corner quoins (slightly proud posts, seeded wear on height)
for sx in (-1, 1):
    for sy in (-1, 1):
        h = SHAFT_H * random.uniform(0.86, 0.99)
        stone_parts.append(add_box(
            (0.085, 0.085, h),
            (sx * 0.335, sy * 0.335, PLINTH_H), MAT_TRIM, taper=0.9))
# parapet slab
stone_parts.append(add_box((0.80, 0.80, 0.09), (0, 0, PARAPET_Z), MAT_STONE))

# merlons around the parapet rim — the crenellations
MERLON_Z = PARAPET_Z + 0.09
rim = 0.36
merlon_spots = []
for sx in (-1, 1):
    for sy in (-1, 1):
        merlon_spots.append((sx * rim, sy * rim))         # corners
for t in (-0.17, 0.0, 0.17):
    merlon_spots += [(t, -rim), (t, rim), (-rim, t), (rim, t)]
chipped = random.sample(range(len(merlon_spots)), 2)      # battle-worn pair
for i, (mx, my) in enumerate(merlon_spots):
    h = 0.15 * random.uniform(0.92, 1.08)
    rot = (0, 0, 0)
    if i in chipped:
        h *= 0.45
        rot = (math.radians(random.uniform(-9, 9)),
               math.radians(random.uniform(-9, 9)), 0)
    stone_parts.append(add_box((0.105, 0.105, h), (mx, my, MERLON_Z),
                               MAT_STONE, taper=0.92, rot=rot))

# arrow slits: front (-Y) and right side, dark and thin, just proud of stone
stone_parts.append(add_box((0.04, 0.02, 0.24), (0, -0.345, 0.72), MAT_SLIT))
stone_parts.append(add_box((0.02, 0.04, 0.20), (0.335, 0.0, 0.36), MAT_SLIT))

for ob in stone_parts:
    ob.select_set(True)
bpy.context.view_layer.objects.active = stone_parts[0]
bpy.ops.object.join()
tower = bpy.context.active_object
tower.name = "TowerBody"
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for p in tower.data.polygons:
    p.use_smooth = False

# ---------------------------------------------------------------- banner
# Rippled cloth down the front face, hung from a wooden rod under the parapet.
B_W, B_H = 0.42, 0.64
B_TOP = 1.055
B_COLS, B_ROWS = 6, 8
verts, faces = [], []
for r in range(B_ROWS + 1):
    t = r / B_ROWS
    z = B_TOP - B_H * t
    for c in range(B_COLS + 1):
        u = c / B_COLS
        x = (u - 0.5) * B_W
        # front face of the tapered shaft ~0.345 at the top; drape outward
        y = -(0.345 - 0.02 * t)
        y -= math.sin(u * math.pi * 2.2 + t * 2.6) * 0.018 * (0.25 + t)
        y -= random.uniform(-0.004, 0.004) * t
        verts.append((x, y, z))
for r in range(B_ROWS):
    for c in range(B_COLS):
        a = r * (B_COLS + 1) + c
        faces.append((a, a + 1, a + B_COLS + 2, a + B_COLS + 1))
bmesh_data = bpy.data.meshes.new("banner_cloth")
bmesh_data.from_pydata(verts, [], faces)
bmesh_data.update()
banner = bpy.data.objects.new("BannerCloth", bmesh_data)
bpy.context.collection.objects.link(banner)
uv = bmesh_data.uv_layers.new()
for poly in bmesh_data.polygons:
    for li in poly.loop_indices:
        vx, _, vz = bmesh_data.vertices[bmesh_data.loops[li].vertex_index].co
        uv.data[li].uv = (vx / B_W + 0.5, (B_TOP - vz) / B_H)  # v=0 at TOP
bmesh_data.materials.append(MAT_BANNER)
for p in bmesh_data.polygons:
    p.use_smooth = False

bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.016, depth=B_W + 0.10,
                                    location=(0, -0.345, B_TOP + 0.01),
                                    rotation=(0, math.pi / 2, 0))
rod = bpy.context.active_object
rod.name = "BannerRod"
rod.data.materials.append(MAT_WOOD)
for p in rod.data.polygons:
    p.use_smooth = False

# ---------------------------------------------------------------- pennant
POLE_H = 0.40
bpy.ops.mesh.primitive_cylinder_add(vertices=7, radius=0.014, depth=POLE_H,
                                    location=(0, 0, MERLON_Z + POLE_H / 2 - 0.02))
pole = bpy.context.active_object
pole.name = "PennantPole"
pole.data.materials.append(MAT_WOOD)
for p in pole.data.polygons:
    p.use_smooth = False

# triangular pennant: root at the pole (local x=0), streaming +X, tapering to
# a point — authored FLAT; all life comes from the runtime vertex shader.
P_LEN, P_H = 0.34, 0.115
P_SEGS = 6
pv, pf = [], []
ptop = MERLON_Z + POLE_H - 0.035
for s in range(P_SEGS + 1):
    t = s / P_SEGS
    x = P_LEN * t
    h = P_H * (1.0 - t)
    pv.append((x, 0.0, ptop))
    pv.append((x, 0.0, ptop - h))
for s in range(P_SEGS):
    a = s * 2
    pf.append((a, a + 2, a + 3, a + 1))
pmesh = bpy.data.meshes.new("pennant")
pmesh.from_pydata(pv, [], pf)
pmesh.update()
pennant = bpy.data.objects.new("Pennant", pmesh)
bpy.context.collection.objects.link(pennant)
puv = pmesh.uv_layers.new()
for poly in pmesh.polygons:
    for li in poly.loop_indices:
        vx, _, vz = pmesh.vertices[pmesh.loops[li].vertex_index].co
        puv.data[li].uv = (vx / P_LEN, (ptop - vz) / P_H)
pmesh.materials.append(MAT_PENNANT)
for p in pmesh.polygons:
    p.use_smooth = False
# pennant root must sit at local x=0 for the shader mask -> keep the object
# origin at the pole and the mesh already authored that way (no transform).

# ---------------------------------------------------------------- report + export


def tri_count(objs):
    deps = bpy.context.evaluated_depsgraph_get()
    total = 0
    for ob in objs:
        me = ob.evaluated_get(deps).to_mesh()
        me.calc_loop_triangles()
        total += len(me.loop_triangles)
        ob.evaluated_get(deps).to_mesh_clear()
    return total


all_objs = [tower, banner, rod, pole, pennant]
n = tri_count(all_objs)
body_top = max(v.co.z for v in tower.data.vertices)
print("[watchtower] %d tris total (budget 4000) · TowerBody height %.3f"
      % (n, body_top))
path = os.path.join(OUT_DIR, "watchtower.glb")
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=path, export_format='GLB',
                          export_apply=True, export_yup=True)
print("[watchtower] wrote %s" % path)
