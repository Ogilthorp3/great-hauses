#!/usr/bin/env blender --python
"""
make_throne.py — Great Houses battle-chess prop: Throne of Blades.

Run headless:
  /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/make_throne.py -- <out_dir>

Output:
  throne.glb — original menacing high-backed throne built from ~60 elongated
  tapered blade shapes: a fan of blades for the tall back (seeded-random
  lengths/rotations), blade-bundle armrests, a skirt of blades at the base,
  all on a dark stone plinth. An original-geometry wink at a certain famous
  chair — evocative silhouette, nothing copied.

Art direction: gritty low-poly medieval — dark iron (metallic 0.85,
roughness 0.6, near-black steel) with a few rust-tinted blades for wear.
Origin at center-bottom (floor). < 6k tris. Front faces -Y.

Blender 4.0.2 bpy API. Deterministic: seeded RNG (SEED below).
"""
import bpy
import math
import random
import sys

SEED = 41
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


MAT_IRON = make_material("throne_iron", (0.045, 0.045, 0.055), 0.85, 0.60)
MAT_RUST = make_material("throne_iron_rust", (0.21, 0.09, 0.05), 0.55, 0.80)
MAT_STONE = make_material("throne_stone", (0.08, 0.08, 0.09), 0.00, 0.95)

parts = []


def blade(length, w, d, loc, rot, mat):
    """Elongated tapered blade: a cube with base cross-section w x d whose
    top face pinches to a point-ish tip. Base at local z=0."""
    bpy.ops.mesh.primitive_cube_add(size=1)
    ob = bpy.context.active_object
    for v in ob.data.vertices:
        top = v.co.z > 0
        v.co.x *= w
        v.co.y *= d
        v.co.z = (v.co.z + 0.5) * length
        if top:
            v.co.x *= 0.10
            v.co.y *= 0.35
    ob.location = loc
    ob.rotation_euler = rot
    ob.data.materials.append(mat)
    parts.append(ob)
    return ob


def box(size, loc, mat, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    ob = bpy.context.active_object
    ob.scale = size
    if bevel > 0:
        bv = ob.modifiers.new("Bevel", 'BEVEL')
        bv.width = bevel
        bv.segments = 1
    ob.data.materials.append(mat)
    parts.append(ob)
    return ob


R = math.radians
n_blades = 0


def iron_or_rust(p_rust=0.13):
    global n_blades
    n_blades += 1
    return MAT_RUST if random.random() < p_rust else MAT_IRON


# ---------------------------------------------------------------- stone plinth
box((1.50, 1.50, 0.16), (0, 0, 0.08), MAT_STONE, bevel=0.02)
box((1.15, 1.15, 0.16), (0, 0, 0.24), MAT_STONE, bevel=0.02)
PLINTH_TOP = 0.32

# ---------------------------------------------------------------- iron seat
box((0.78, 0.70, 0.30), (0, 0.06, PLINTH_TOP + 0.15), MAT_IRON)
SEAT_TOP = PLINTH_TOP + 0.30   # 0.62 m

# ------------------------------------------------- back fan, rear row (tall)
for i in range(20):
    x = -0.36 + i * (0.72 / 19)
    t = x / 0.36
    length = 1.25 + 0.85 * math.cos(t * math.pi / 2) + random.uniform(-0.14, 0.14)
    blade(length,
          random.uniform(0.055, 0.075), random.uniform(0.020, 0.030),
          (x + random.uniform(-0.008, 0.008), 0.385, PLINTH_TOP),
          (R(4 + random.uniform(0, 5)),                 # lean back
           -t * R(16) + R(random.uniform(-4, 4)),       # fan outward
           R(random.uniform(-14, 14))),                 # roll
          iron_or_rust())

# ------------------------------------------------ back fan, front row (short)
for i in range(16):
    x = -0.33 + i * (0.66 / 15)
    t = x / 0.33
    length = 0.72 + 0.55 * math.cos(t * math.pi / 2) + random.uniform(-0.10, 0.10)
    blade(length,
          random.uniform(0.050, 0.068), random.uniform(0.018, 0.026),
          (x + random.uniform(-0.008, 0.008), 0.30, PLINTH_TOP),
          (R(2 + random.uniform(0, 4)),
           -t * R(10) + R(random.uniform(-5, 5)),
           R(random.uniform(-16, 16))),
          iron_or_rust())

# ---------------------------------------------------- armrest blade bundles
for side in (-1, 1):
    for i in range(8):
        y = -0.16 + i * (0.40 / 7)
        length = random.uniform(0.55, 0.85) * (0.85 if y < 0 else 1.0)
        blade(length,
              random.uniform(0.040, 0.058), random.uniform(0.016, 0.024),
              (side * (0.42 + random.uniform(-0.015, 0.015)), y, PLINTH_TOP),
              (R(random.uniform(-6, 6)),
               side * R(8 + random.uniform(-4, 6)),   # lean outward
               R(random.uniform(-18, 18))),
              iron_or_rust())

# ----------------------------------------------------- base skirt (menace)
for i in range(8):
    ang = math.pi * (0.15 + 0.7 * i / 7)           # sweep across the front
    x = math.cos(ang + math.pi) * 0.52             # front = -Y side
    y = -abs(math.sin(ang)) * 0.48 - 0.10
    length = random.uniform(0.38, 0.62)
    out = math.atan2(x, -y - 0.2)
    blade(length,
          random.uniform(0.045, 0.06), random.uniform(0.016, 0.022),
          (x, y * 0.55, 0.16),
          (R(28 + random.uniform(-6, 8)) * (1 if y < 0 else 1),  # lean forward
           out * 0.35 + R(random.uniform(-6, 6)),
           R(random.uniform(-20, 20))),
          iron_or_rust(p_rust=0.25))

# ---------------------------------------------------------------- join + finish
for ob in parts:
    ob.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.join()
throne = bpy.context.active_object
throne.name = "ThroneOfBlades"
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
# origin = world (0,0,0) = center-bottom on the floor

for p in throne.data.polygons:
    p.use_smooth = False


def tri_count(ob):
    deps = bpy.context.evaluated_depsgraph_get()
    me = ob.evaluated_get(deps).to_mesh()
    me.calc_loop_triangles()
    n = len(me.loop_triangles)
    ob.evaluated_get(deps).to_mesh_clear()
    return n


# overall dimensions from evaluated bounds
xs = [v.co for v in throne.data.vertices]
print(f"[throne] blades: {n_blades}")
print(f"[throne] tris (post-modifier): {tri_count(throne)}")
print(f"[throne] bounds x [{min(v.x for v in xs):.2f},{max(v.x for v in xs):.2f}] "
      f"y [{min(v.y for v in xs):.2f},{max(v.y for v in xs):.2f}] "
      f"z [{min(v.z for v in xs):.2f},{max(v.z for v in xs):.2f}]")

bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(
    filepath=f"{OUT_DIR}/throne.glb", export_format='GLB',
    export_apply=True, export_yup=True)
print(f"[throne] wrote {OUT_DIR}/throne.glb")
