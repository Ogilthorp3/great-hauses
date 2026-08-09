#!/usr/bin/env blender --python
"""
make_crests.py — Great Hauses: nine helmet-crest attachments (HAUS layer).

Run headless:
  /Applications/Blender.app/Contents/MacOS/Blender -b --python \
      tools/props/make_crests.py -- <out_dir> [<houses_json>]

Outputs: crest_<house_id>.glb for each of the nine hauses:
  antlers (hartcrown) · wolf-pelt hood (winterfang) · dragon fins (ashwyrm) ·
  tentacle sweep (tidegrip) · rose ring (thornvale) · sun rays (duskfire) ·
  falcon wings (swiftcrest) · fish-fin crest (silverbrook) ·
  lion mane collar (goldclaw)

Design constraints (art direction: gritty low-poly medieval):
  - each crest <= 600 tris (decimate fallback enforces the budget)
  - haus-colored Principled BSDF constants read from src/houses/houses.json
    (primary/secondary/accent, sRGB hex -> linear)
  - authored in KayKit Rig_Medium HEAD-BONE space: origin = skull-top contact
    point, +Z up (Blender) -> Y-up GLB, front faces Blender -Y -> Godot +Z.
    Runtime: rigid BoneAttachment3D on the `head` bone (crown-attach pattern
    in piece_assets/piece_view), attach position ~(0, 1.02, 0), scale 1.0.
  - flat shading; deterministic seeded RNG (SEED below)

Blender 4.0.2 bpy API.
"""
import bpy
import json
import math
import os
import random
import sys

from mathutils import Vector

SEED = 9917

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_DIR = argv[0] if argv else "."
# Hauses are HAUS PACKS now (docs/HAUS-PACK.md): one folder each under
# hauses/, holding a haus.json. This used to read a single src/houses/houses.json.
HOUSES_DIR = argv[1] if len(argv) > 1 else os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "..", "hauses")

TRI_BUDGET = 600


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_to_linear(h):
    h = h.lstrip("#")
    return tuple(srgb_to_linear(int(h[i:i + 2], 16) / 255.0) for i in (0, 2, 4))


def _load_house_packs(root):
    """Every hauses/<id>/haus.json, keyed by id. Folders starting with "_"
    are the template and the examples, and are skipped exactly as the game's
    discovery skips them."""
    out = {}
    for name in sorted(os.listdir(root)):
        if name.startswith("_") or name.startswith("."):
            continue
        manifest = os.path.join(root, name, "haus.json")
        if not os.path.isfile(manifest):
            continue
        with open(manifest) as fh:
            house = json.load(fh)
        out[house["id"]] = house
    return out


HOUSES = _load_house_packs(HOUSES_DIR)


def make_material(name, base, metallic=0.0, rough=0.8, emission=None, emission_strength=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*base, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = rough
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    return m


def assign(ob, mat):
    ob.data.materials.append(mat)
    return ob


def add_box(size, loc=(0, 0, 0), rot=(0, 0, 0), taper=1.0):
    """Cube scaled to size, base at local z=0, optional top-face taper."""
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
    return ob


def add_cone(verts, r1, r2, depth, loc=(0, 0, 0), rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2,
                                    depth=depth, location=loc, rotation=rot)
    return bpy.context.active_object


def add_sphere(segments, rings, r, loc=(0, 0, 0), scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings,
                                         radius=r, location=loc)
    ob = bpy.context.active_object
    ob.scale = scale
    return ob


def add_torus(major, minor, mseg, msub, loc=(0, 0, 0), rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor,
                                     major_segments=mseg, minor_segments=msub,
                                     location=loc, rotation=rot)
    ob = bpy.context.active_object
    ob.rotation_euler = rot
    return ob


def chain(n, r0, r1, seg_len, start, direction, bend, mat, verts=5, jitter=0.03):
    """Bent chain of tapered cone segments (antlers/tentacles).
    start: Vector; direction: unit Vector; bend: per-segment Euler-ish
    (axis-angle around X then Y in world) applied to the direction."""
    objs = []
    pos = Vector(start)
    d = Vector(direction).normalized()
    for i in range(n):
        t0, t1 = i / n, (i + 1) / n
        ra = r0 + (r1 - r0) * t0
        rb = r0 + (r1 - r0) * t1
        length = seg_len * random.uniform(1.0 - jitter, 1.0 + jitter)
        mid = pos + d * (length / 2.0)
        ob = add_cone(verts, ra, rb, length, loc=mid)
        ob.rotation_mode = 'QUATERNION'
        ob.rotation_quaternion = d.to_track_quat('Z', 'Y')
        objs.append(assign(ob, mat))
        pos = pos + d * length
        # bend the running direction
        d = d.copy()
        d.rotate(bend)
        d.normalize()
    return objs, pos, d


def finalize(objs, name, out_path):
    for ob in objs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    crest = bpy.context.active_object
    crest.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for p in crest.data.polygons:
        p.use_smooth = False

    def tris():
        deps = bpy.context.evaluated_depsgraph_get()
        me = crest.evaluated_get(deps).to_mesh()
        me.calc_loop_triangles()
        n = len(me.loop_triangles)
        crest.evaluated_get(deps).to_mesh_clear()
        return n

    n = tris()
    if n > TRI_BUDGET:
        dec = crest.modifiers.new("Budget", 'DECIMATE')
        dec.ratio = TRI_BUDGET / float(n)
        n = tris()
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=out_path, export_format='GLB',
                              export_apply=True, export_yup=True)
    return n


def euler_rot(x_deg=0.0, y_deg=0.0, z_deg=0.0):
    from mathutils import Euler
    return Euler((math.radians(x_deg), math.radians(y_deg), math.radians(z_deg)), 'XYZ')


# ---------------------------------------------------------------- crest builders
# All: origin = skull-top contact, +Z up, front -Y.

def crest_hartcrown(cols):
    """Antlers — two mirrored branching beams, bone-gold."""
    beam_mat = make_material("hartcrown_bone", cols["secondary"], 0.25, 0.62)
    tip_mat = make_material("hartcrown_tip", cols["accent"], 0.35, 0.5)
    objs = []
    for sx in (-1, 1):
        d0 = Vector((sx * 0.55, 0.12, 1.0)).normalized()
        bend = euler_rot(x_deg=-9.0, y_deg=sx * 13.0)
        segs, tip_pos, tip_dir = chain(
            4, 0.045, 0.014, 0.17, Vector((sx * 0.17, 0.02, -0.02)),
            d0, bend, beam_mat)
        objs += segs
        # three tines per antler, branching up-forward
        base = Vector((sx * 0.17, 0.02, -0.02))
        for k in range(3):
            t = 0.30 + 0.26 * k
            p = base.lerp(tip_pos, t)
            td = Vector((sx * 0.25, -0.55, 1.0)).normalized()
            length = random.uniform(0.10, 0.15) * (1.0 - 0.18 * k)
            ob = add_cone(4, 0.020, 0.004, length, loc=p + td * (length / 2))
            ob.rotation_mode = 'QUATERNION'
            ob.rotation_quaternion = td.to_track_quat('Z', 'Y')
            objs.append(assign(ob, tip_mat if k == 2 else beam_mat))
    return objs


def crest_winterfang(cols):
    """Wolf-pelt hood — ellipsoid pelt over the skull, snout wedge, ears."""
    pelt = make_material("winterfang_pelt", cols["primary"], 0.0, 0.92)
    snout_m = make_material("winterfang_snout", cols["accent"], 0.0, 0.85)
    objs = []
    hood = add_sphere(10, 6, 0.5, loc=(0, 0.05, 0.02), scale=(1.16, 1.36, 0.86))
    objs.append(assign(hood, pelt))
    # snout wedge over the brow, pointing forward (-Y)
    snout = add_box((0.30, 0.42, 0.16), loc=(0, -0.52, 0.14),
                    rot=euler_rot(x_deg=104.0), taper=0.45)
    objs.append(assign(snout, snout_m))
    for sx in (-1, 1):
        ear = add_cone(4, 0.075, 0.012, 0.20,
                       loc=(sx * 0.26, 0.12, 0.48),
                       rot=euler_rot(x_deg=-14.0, y_deg=sx * 16.0))
        objs.append(assign(ear, pelt))
    return objs


def crest_ashwyrm(cols):
    """Dragon fins — spiked midline fin row plus swept temple horns."""
    fin_mat = make_material("ashwyrm_fin", cols["secondary"], 0.1, 0.7)
    horn_mat = make_material("ashwyrm_horn", cols["accent"], 0.2, 0.55)
    objs = []
    ys = (-0.22, 0.0, 0.22, 0.42)
    hs = (0.34, 0.28, 0.22, 0.15)
    for y, h in zip(ys, hs):
        fin = add_cone(4, 0.085, 0.008, h,
                       loc=(0, y, h / 2 - 0.01),
                       rot=euler_rot(x_deg=random.uniform(10.0, 16.0)))
        fin.scale = (0.28, 1.35, 1.0)   # blade-thin, stretched along the spine
        objs.append(assign(fin, fin_mat))
    for sx in (-1, 1):
        horn = add_cone(5, 0.045, 0.006, 0.30,
                        loc=(sx * 0.33, 0.14, 0.10),
                        rot=euler_rot(x_deg=52.0, y_deg=sx * 26.0))
        objs.append(assign(horn, horn_mat))
    return objs


def crest_tidegrip(cols):
    """Tentacle sweep — four tapered tentacles curling back off the skull."""
    body = make_material("tidegrip_tentacle", cols["primary"], 0.05, 0.6)
    tip = make_material("tidegrip_tip", cols["accent"], 0.05, 0.5)
    objs = []
    lanes = ((-0.24, 0.10), (-0.08, 0.16), (0.08, 0.16), (0.24, 0.10))
    for x, lift in lanes:
        d0 = Vector((x * 0.4, 0.55, 1.0 + lift)).normalized()
        bend = euler_rot(x_deg=26.0, y_deg=-x * 24.0)
        segs, p, d = chain(4, 0.055, 0.020, 0.14,
                           Vector((x, -0.05, 0.0)), d0, bend, body, jitter=0.08)
        objs += segs
        curl = add_cone(5, 0.020, 0.003, 0.10, loc=p + d * 0.05)
        curl.rotation_mode = 'QUATERNION'
        curl.rotation_quaternion = d.to_track_quat('Z', 'Y')
        objs.append(assign(curl, tip))
    return objs


def crest_thornvale(cols):
    """Rose ring — thorned wreath with three gold roses."""
    wreath = make_material("thornvale_wreath", cols["primary"], 0.0, 0.85)
    rose = make_material("thornvale_rose", cols["secondary"], 0.1, 0.6)
    thorn = make_material("thornvale_thorn", cols["accent"], 0.0, 0.8)
    objs = []
    ring = add_torus(0.40, 0.055, 10, 5, loc=(0, 0, 0.10),
                     rot=euler_rot(x_deg=8.0))
    objs.append(assign(ring, wreath))
    for ang in (90.0, 210.0, 330.0):   # front, back-left, back-right
        a = math.radians(ang)
        loc = (math.sin(a) * 0.40 * 0.98, -math.cos(a) * 0.40, 0.13)
        bud = add_sphere(7, 5, 0.095, loc=loc, scale=(1.0, 1.0, 0.85))
        objs.append(assign(bud, rose))
    for k in range(6):
        a = math.radians(30.0 + 60.0 * k + random.uniform(-8.0, 8.0))
        loc = (math.sin(a) * 0.42, -math.cos(a) * 0.42, 0.12)
        th = add_cone(4, 0.020, 0.003, 0.10, loc=loc,
                      rot=euler_rot(x_deg=random.uniform(-30, 30),
                                    y_deg=random.uniform(-30, 30)))
        objs.append(assign(th, thorn))
    return objs


def crest_duskfire(cols):
    """Sun rays — a halo fan of flat rays out of a brow band, faint ember glow."""
    band = make_material("duskfire_band", cols["primary"], 0.5, 0.5)
    ray = make_material("duskfire_ray", cols["accent"], 0.4, 0.45,
                        emission=cols["accent"], emission_strength=0.35)
    objs = []
    ring = add_torus(0.38, 0.045, 10, 5, loc=(0, 0, 0.06))
    objs.append(assign(ring, band))
    n_rays = 9
    for k in range(n_rays):
        a = math.pi * k / (n_rays - 1)          # ear-to-ear halo arc
        long_ray = (k % 2 == 0)
        length = (0.34 if long_ray else 0.20) * random.uniform(0.94, 1.06)
        dx, dz = math.cos(a), math.sin(a)
        r0 = 0.36
        rayob = add_box((0.055, 0.016, length),
                        loc=(dx * r0, 0.02, 0.02 + dz * r0 * 0.55), taper=0.25)
        rayob.rotation_mode = 'QUATERNION'
        rayob.rotation_quaternion = Vector((dx, 0.0, dz)).to_track_quat('Z', 'Y')
        objs.append(assign(rayob, ray))
    return objs


def crest_swiftcrest(cols):
    """Falcon wings — three-layer swept feather stacks off the temples."""
    feather = make_material("swiftcrest_feather", cols["secondary"], 0.05, 0.7)
    edge = make_material("swiftcrest_edge", cols["accent"], 0.1, 0.6)
    objs = []
    for sx in (-1, 1):
        for layer in range(3):
            length = 0.44 - 0.10 * layer
            d = Vector((sx * 1.0, 0.55 + 0.18 * layer, 0.72 - 0.16 * layer)).normalized()
            wing = add_box((0.030, 0.10 + 0.02 * layer, length), taper=0.55)
            wing.location = (sx * 0.24, 0.05 + 0.03 * layer, 0.06 + 0.03 * layer)
            wing.rotation_mode = 'QUATERNION'
            wing.rotation_quaternion = d.to_track_quat('Z', 'Y')
            objs.append(assign(wing, edge if layer == 2 else feather))
    return objs


def crest_silverbrook(cols):
    """Fish-fin crest — rippled dorsal fin down the midline, small side fins."""
    fin = make_material("silverbrook_fin", cols["secondary"], 0.35, 0.45)
    side = make_material("silverbrook_side", cols["accent"], 0.3, 0.5)
    objs = []
    ys = (-0.30, -0.16, -0.02, 0.12, 0.26, 0.40)
    hs = (0.16, 0.28, 0.34, 0.30, 0.22, 0.14)
    for y, h in zip(ys, hs):
        seg = add_box((0.024, 0.13, h * random.uniform(0.95, 1.05)),
                      loc=(0, y, -0.01), rot=euler_rot(x_deg=8.0), taper=0.5)
        objs.append(assign(seg, fin))
    for sx in (-1, 1):
        sf = add_cone(4, 0.075, 0.010, 0.16,
                      loc=(sx * 0.30, 0.16, 0.05),
                      rot=euler_rot(x_deg=38.0, y_deg=sx * 52.0))
        sf.scale = (0.35, 1.2, 1.0)
        objs.append(assign(sf, side))
    return objs


def crest_goldclaw(cols):
    """Lion mane collar — a ruff of alternating gold petals around the skull."""
    mane_a = make_material("goldclaw_mane_a", cols["secondary"], 0.35, 0.55)
    mane_b = make_material("goldclaw_mane_b", cols["accent"], 0.35, 0.5)
    objs = []
    n = 12
    for k in range(n):
        a = 2.0 * math.pi * k / n
        tall = (k % 2 == 0)
        length = (0.26 if tall else 0.19) * random.uniform(0.94, 1.06)
        dx, dy = math.sin(a), -math.cos(a)
        d = Vector((dx * 0.9, dy * 0.9, 0.85)).normalized()
        petal = add_box((0.10, 0.022, length), taper=0.35)
        petal.location = (dx * 0.34, dy * 0.34, -0.04)
        petal.rotation_mode = 'QUATERNION'
        petal.rotation_quaternion = d.to_track_quat('Z', 'X')
        objs.append(assign(petal, mane_a if tall else mane_b))
    return objs


BUILDERS = {
    "hartcrown": crest_hartcrown,
    "winterfang": crest_winterfang,
    "ashwyrm": crest_ashwyrm,
    "tidegrip": crest_tidegrip,
    "thornvale": crest_thornvale,
    "duskfire": crest_duskfire,
    "swiftcrest": crest_swiftcrest,
    "silverbrook": crest_silverbrook,
    "goldclaw": crest_goldclaw,
}

for house_id, builder in BUILDERS.items():
    # NOT hash(): Python string hashing is salted per-process -> not reproducible
    random.seed(SEED + sum(ord(c) for c in house_id))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    cols = {k: hex_to_linear(v) for k, v in HOUSES[house_id]["colors"].items()}
    objs = builder(cols)
    out = os.path.join(OUT_DIR, "crest_%s.glb" % house_id)
    n = finalize(objs, "Crest_%s" % house_id, out)
    print("[crest] %-11s %4d tris -> %s" % (house_id, n, out))
