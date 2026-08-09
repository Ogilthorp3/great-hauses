#!/usr/bin/env blender --python
"""
convert_horse.py — Quaternius CC0 Horse: poly.pizza GLB -> game-ready STATIC
horse.glb (standing pose) + authored war-tack (Saddle, Caparison).

Run headless:
  /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/props/convert_horse.py -- \
      <path/to/source Horse.glb> <out/horse.glb>

Source: "Horse" by Quaternius (CC0 1.0 Universal), poly.pizza model qvTrSG9pZF
(the animated horse from the Ultimate Animated Animal Pack — quaternius.com
confirms CC0 for the pack). A copy of the source GLB + provenance lives in
great-houses-assets/quaternius-animals/ so this conversion is reproducible
offline.

WHY STATIC (scar of 2026-08-08): the source rig is FBX lineage — armature
node scale 100, tiny bone-space data. Godot (Metal, Mobile AND Forward+)
renders its skinned mesh fine at scale ~1 but CORRUPTS it at chess-piece
instance scales (~0.126): vertices bound to half the bones fly off to
infinity and the horse's front half vanishes, camera-angle-dependently.
Rig surgery (scale apply, fcurve rescale, re-bind, full rig rebuild with
visual-key baking) moved the failure around but never killed it — while
STATIC meshes at the same scale render flawlessly. So the mount ships as a
frozen standing pose (Idle frame 0) and PieceView drives idle-sway, walk-bob
and the death collapse procedurally on the node — the exact pattern the
banner-rook already uses (glide+bob, tilt-crumble), proven at this scale.

WAR-TACK (original geometry, authored in the haus art style):
  - "Saddle": chunky low-poly seat with pommel + cantle, leather brown.
  - "Caparison": two draped cloth panels down the flanks, UV-mapped 0..1
    per panel with v=0 at the TOP (Godot image convention) so the runtime
    can drop PieceAssets.banner_texture(house_id) straight in — the haus
    sigil reads on the horse's flank at distance.

Node/mesh names are runtime API (piece_view.gd): Horse · Saddle · Caparison.

Conventions: source faces -Y in Blender -> +Z in Godot after export (same as
the KayKit fighters). Deterministic: seeded RNG. Blender 4.0.2 bpy API.
"""
import bpy
import math
import os
import random
import sys

SEED = 1066   # the year cavalry settled an island argument
random.seed(SEED)

argv = sys.argv[sys.argv.index("--") + 1:]
GLB_IN, GLB_OUT = argv[0], argv[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.render.fps = 24
bpy.ops.import_scene.gltf(filepath=GLB_IN)

# ------------------------------------------------------------- prune the junk
for ob in [o for o in bpy.data.objects if o.name.startswith("Icosphere")]:
    bpy.data.objects.remove(ob, do_unlink=True)

meshes = [o for o in bpy.data.objects if o.type == 'MESH']
old_arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
horse_mesh = meshes[0]
horse_mesh.name = "Horse"

# --------------------------- freeze the standing pose (Idle frame 0) in
for a in [a for a in bpy.data.actions if "|" in a.name]:
    bpy.data.actions.remove(a)
for a in bpy.data.actions:
    a.name = a.name.removesuffix("_AnimalArmature")
if old_arm.animation_data is None:
    old_arm.animation_data_create()
old_arm.animation_data.action = next(
    a for a in bpy.data.actions if a.name == "Idle")
bpy.context.scene.frame_set(0)
bpy.context.view_layer.update()

# Reference world AABB of the posed mesh — used to recalibrate the frozen
# data (modifier_apply on FBX-lineage parent/scale chains lands in whichever
# space it pleases).
deps = bpy.context.evaluated_depsgraph_get()
me_eval = horse_mesh.evaluated_get(deps).to_mesh()
ref_lo = [min((horse_mesh.matrix_world @ v.co)[i] for v in me_eval.vertices)
          for i in range(3)]
ref_hi = [max((horse_mesh.matrix_world @ v.co)[i] for v in me_eval.vertices)
          for i in range(3)]
horse_mesh.evaluated_get(deps).to_mesh_clear()

bpy.ops.object.select_all(action='DESELECT')
horse_mesh.select_set(True)
bpy.context.view_layer.objects.active = horse_mesh
for mod in [m for m in horse_mesh.modifiers if m.type == 'ARMATURE']:
    bpy.ops.object.modifier_apply(modifier=mod.name)
bpy.context.view_layer.update()
w = horse_mesh.matrix_world.copy()
horse_mesh.parent = None
horse_mesh.matrix_world = w
bpy.context.view_layer.update()
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
now_lo = [min(v.co[i] for v in horse_mesh.data.vertices) for i in range(3)]
now_hi = [max(v.co[i] for v in horse_mesh.data.vertices) for i in range(3)]
f = (ref_hi[2] - ref_lo[2]) / max(now_hi[2] - now_lo[2], 1e-9)
for v in horse_mesh.data.vertices:
    for i in range(3):
        v.co[i] = ref_lo[i] + (v.co[i] - now_lo[i]) * f
# strip vertex groups — this mesh is deliberately unskinned now
for vg in list(horse_mesh.vertex_groups):
    horse_mesh.vertex_groups.remove(vg)
print(f"[horse] standing pose frozen (recalibration factor {f:.4f})")

# Drop the rig, its helper empties, and every action — static export.
for ob in [o for o in bpy.data.objects if o.type == 'EMPTY']:
    bpy.data.objects.remove(ob, do_unlink=True)
bpy.data.objects.remove(old_arm, do_unlink=True)
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)
print("[horse] rig + actions dropped — static standing horse")

# ======================================================================
# THE DESTRIER PASS (critic defect #1, 2026-08-08)
# ======================================================================
# Quaternius ships a slim RIDING horse: long thin legs, a giraffe-straight
# neck carrying the skull to the very top of the model, a torso half-width of
# 0.45 against a 5.6-long body, and a mane/tail two vertices thick. It renders
# beautifully in a 1280x720 beauty shot. On the board — where the whole piece
# is ~50 px tall and lit from above — it read as "a dog-sized, spindly,
# mane-less, tail-less quadruped", and worse: with the skull at the model's
# apex the RIDER'S HEAD AND THE HORSE'S HEAD LANDED AT THE SAME HEIGHT, so the
# silhouette was a two-headed animal, and from the near-side camera the rider
# simply occluded the horse's head entirely. A knight riding a greyhound.
#
# We own this conversion, so the mount is reshaped into a WAR HORSE — the fix
# is proportional, not a scale-up:
#   LEGS shorter        stocky, and it drops the saddle (and the whole rider)
#                       closer to the ground, buying ensemble height back
#   BARREL/NECK thicker mass is what survives at 50 px; a wide barrel under a
#                       caparison is the cavalry read
#   NECK ARCHED DOWN    the single most important change: the head comes off
#                       the top of the silhouette and reaches FORWARD, so the
#                       rider's helm owns the skyline alone and the horse's
#                       head extends the shape into an unmistakable quadruped
#   MANE + TAIL bulked  two vertices of hair are invisible; a chunky crest and
#                       a fat brush are two more silhouette landmarks
# Every landmark the tack needs is MEASURED off the result below, never
# hard-coded, so these knobs can move without unseating the saddle.

me = horse_mesh.data
# glTF ships custom split normals; they do not survive a deformation. Drop
# them and let Blender recompute from the new geometry.
bpy.ops.object.select_all(action='DESELECT')
horse_mesh.select_set(True)
bpy.context.view_layer.objects.active = horse_mesh
if me.has_custom_normals:
    bpy.ops.mesh.customdata_custom_splitnormals_clear()

LEG_TOP_Z = 1.90       # knee/elbow line — below it is leg, above it is body
LEG_SHORTEN = 0.78     # destrier stance: 22% off the leg length
BARREL_GAIN = 0.46     # torso half-width x1.46
NECK_GAIN = 0.34       # neck half-width x1.34
NECK_DROP_DEG = 21.0   # how far the neck arches down and forward
# Mane and tail are FLAT strips: widen them too far and they stop being hair
# and become dark planks bolted to the horse (caught in the beauty shot at
# 2.10/2.30). Enough to survive downsampling, not enough to read as slabs.
MANE_WIDEN = 1.45
TAIL_WIDEN = 1.55
TAIL_THICKEN = 1.12
LEG_GIRTH = 1.34      # sticks read as spindles; a destrier stands on columns

# material name -> vertex indices (glTF primitives never share vertices)
mat_verts = {m.name: set() for m in me.materials}
for poly in me.polygons:
    name = me.materials[poly.material_index].name
    for vi in poly.vertices:
        mat_verts[name].add(vi)
hair_verts = mat_verts.get("Hair", set())


def window(v, lo_out, lo_in, hi_in, hi_out):
    """Smooth 0..1 trapezoid: 0 outside [lo_out,hi_out], 1 inside [lo_in,hi_in]."""
    if v <= lo_out or v >= hi_out:
        return 0.0
    if lo_in <= v <= hi_in:
        return 1.0
    t = (v - lo_out) / (lo_in - lo_out) if v < lo_in else (hi_out - v) / (hi_out - hi_in)
    return t * t * (3.0 - 2.0 * t)          # smoothstep


# 1. shorter legs — body rides down with them, hooves stay on the ground
drop = LEG_TOP_Z * (1.0 - LEG_SHORTEN)
for v in me.vertices:
    v.co.z = v.co.z * LEG_SHORTEN if v.co.z < LEG_TOP_Z else v.co.z - drop

# 2. girth: barrel and neck widen about the spine (legs keep their stance)
for v in me.vertices:
    barrel = window(v.co.y, -2.5, -1.40, 1.05, 1.70) \
        * window(v.co.z, 1.05, 1.55, 9.0, 9.1)
    neck = window(v.co.y, -2.85, -2.40, -1.15, -0.70) \
        * window(v.co.z, 2.00, 2.45, 9.0, 9.1)
    v.co.x *= 1.0 + max(BARREL_GAIN * barrel, NECK_GAIN * neck)

# 2b. leg girth: thicken each leg about its OWN axis (a global x-scale would
# just splay the stance). Quadrants: fore/hind x left/right.
leg_top = LEG_TOP_Z * LEG_SHORTEN
quads = {}
for v in me.vertices:
    if v.co.z >= leg_top:
        continue
    q = (v.co.y > 0.0, v.co.x > 0.0)
    acc = quads.setdefault(q, [0.0, 0.0, 0])
    acc[0] += v.co.x
    acc[1] += v.co.y
    acc[2] += 1
for v in me.vertices:
    if v.co.z >= leg_top:
        continue
    acc = quads[(v.co.y > 0.0, v.co.x > 0.0)]
    cx, cy = acc[0] / acc[2], acc[1] / acc[2]
    taper = 1.0 + (LEG_GIRTH - 1.0) * min(1.0, v.co.z / leg_top + 0.25)
    v.co.x = cx + (v.co.x - cx) * taper
    v.co.y = cy + (v.co.y - cy) * taper

# 3. arch the neck down and forward about the withers
pivot_y, pivot_z = -1.00, 3.515 - drop
ang = math.radians(NECK_DROP_DEG)
for v in me.vertices:
    w = window(-v.co.y, 0.80, 2.20, 9.0, 9.1)
    if w <= 0.0:
        continue
    c, s = math.cos(ang * w), math.sin(ang * w)
    dy, dz = v.co.y - pivot_y, v.co.z - pivot_z
    v.co.y = pivot_y + dy * c - dz * s
    v.co.z = pivot_z + dy * s + dz * c

# 4. mane and tail: two vertices of hair are nothing at board scale
tail_zs = [me.vertices[i].co.z for i in hair_verts if me.vertices[i].co.y > 0.4]
tail_mid = sum(tail_zs) / len(tail_zs) if tail_zs else 0.0
for i in hair_verts:
    v = me.vertices[i]
    if v.co.y < 0.4:                       # mane: crest along the neck
        v.co.x *= MANE_WIDEN
    else:                                  # tail: a fat brush, not a wire
        v.co.x *= TAIL_WIDEN
        v.co.z = tail_mid + (v.co.z - tail_mid) * TAIL_THICKEN

me.update()

# ---------------------------------------------------------------- war tack
# Landmarks MEASURED off the reshaped standing pose (Blender Z-up, horse
# faces -Y) rather than hard-coded, so the destrier knobs above stay free.
SADDLE_Y = -0.55          # seat center along the spine (negative = forward)
BACK_TOP = max(v.co.z for v in me.vertices
               if -0.95 <= v.co.y <= -0.15 and abs(v.co.x) < 0.40)
# Belly on the MID-LINE BETWEEN the leg pairs — anywhere else and the tape
# measure lands on a foreleg and reports the knee.
BELLY_Z = min(v.co.z for v in me.vertices
              if -0.55 <= v.co.y <= 0.55 and abs(v.co.x) < 0.22)
FLANK_X = max(abs(v.co.x) for v in me.vertices if -1.30 <= v.co.y <= 1.00)
HEAD_TOP = max(v.co.z for v in me.vertices)
SEAT_TOP = BACK_TOP - 0.04 + 0.20     # top of the saddle slab built below
print(f"[horse] destrier: back {BACK_TOP:.3f} belly {BELLY_Z:.3f} "
      f"flank {FLANK_X:.3f} head_top {HEAD_TOP:.3f} seat_top {SEAT_TOP:.3f} "
      f"(head clears the back by {HEAD_TOP - BACK_TOP:.3f})")


def make_material(name, base, rough=0.9):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*base, 1.0)
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = rough
    return m


MAT_LEATHER = make_material("saddle_leather", (0.16, 0.10, 0.06), 0.8)
MAT_CLOTH = make_material("caparison_cloth", (0.85, 0.82, 0.78), 0.92)
# CRINET + CHANFRON (critic P6, 2026-08-09) — see the block that builds them.
# Both are dyed at runtime by material NAME (PieceAssets.MOUNT_DYE_WEIGHTS),
# deliberately at weights ABOVE the hide's, because their whole job is to
# carry the horse's neck and head at values the near-side camera can find.
MAT_CRINET = make_material("crinet_cloth", (0.82, 0.80, 0.76), 0.92)
MAT_CHANFRON = make_material("chanfron_steel", (0.72, 0.70, 0.66), 0.55)


def add_box(size, loc, mat, taper=1.0):
    """Cube with base at loc.z (make_watchtower convention)."""
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
    ob.location = loc
    ob.data.materials.append(mat)
    return ob


# Saddle: seat slab over the back (wider than the torso so it reads from the
# side), pommel lip fore, cantle lip aft.
# Sized off the MEASURED flank so a fatter barrel never swallows its own
# saddle: the seat has to overhang the torso to read from the side.
SEAT_W = FLANK_X * 1.32
saddle_parts = [
    add_box((SEAT_W, 0.60, 0.20), (0.0, SADDLE_Y, BACK_TOP - 0.04), MAT_LEATHER,
            taper=0.88),
    add_box((SEAT_W * 0.86, 0.12, 0.38), (0.0, SADDLE_Y - 0.32, BACK_TOP - 0.02),
            MAT_LEATHER, taper=0.68),                     # pommel
    add_box((SEAT_W * 0.92, 0.14, 0.44), (0.0, SADDLE_Y + 0.33, BACK_TOP - 0.02),
            MAT_LEATHER, taper=0.68),                     # cantle
]
bpy.ops.object.select_all(action='DESELECT')
for ob in saddle_parts:
    ob.select_set(True)
bpy.context.view_layer.objects.active = saddle_parts[0]
bpy.ops.object.join()
saddle = bpy.context.active_object
saddle.name = "Saddle"
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for p in saddle.data.polygons:
    p.use_smooth = False

# Caparison: two draped panels, one per flank, meeting at the spine. The
# cross-section is a quarter-ellipse from the spine ridge out and down the
# flank — it hugs the torso but always clears it.
#
# SIZED FOR THE SILHOUETTE (2026-08-08): a chess knight is read head-on from
# the player camera, where a horse is a narrow shape hiding behind its rider.
# The caparison is what makes the mount read as CAVALRY from the front — so
# it runs shoulder-to-rump and hangs BELOW the belly line (~2.2), widening
# the piece into an unmistakable skirted silhouette. Short flank patches (the
# first cut: y -1.15..0.85, hem 2.52) vanished at gameplay distance.
CAP_Y0, CAP_Y1 = -1.50, 1.20   # fore/aft extent along the spine
CAP_TOP_Z = BACK_TOP + 0.06
CAP_HEM_Z = BELLY_Z - 0.30     # below the belly — the silhouette maker
CAP_HEM_X = FLANK_X + 0.20
COLS, ROWS = 12, 6             # along the body, down the drape

cap_objs = []
for side in (1, -1):
    verts, faces = [], []
    for r in range(ROWS + 1):
        t = r / ROWS                       # 0 at spine, 1 at hem
        for c in range(COLS + 1):
            u = c / COLS                   # 0 fore, 1 aft
            y = CAP_Y0 + (CAP_Y1 - CAP_Y0) * u
            # quarter-ellipse drape: spine ridge -> out over the torso -> hang
            theta = t * math.pi * 0.5
            x = side * CAP_HEM_X * math.sin(theta)
            z = CAP_TOP_Z - (CAP_TOP_Z - CAP_HEM_Z) * (1.0 - math.cos(theta))
            # heraldic scalloped hem (deepest at the hem, fades to the ridge)
            z += 0.11 * abs(math.sin(u * math.pi * 5.0)) * t
            # fore/aft corners sweep up so the cloth reads draped, not boxed
            z += 0.30 * max(0.0, abs(u - 0.5) * 2.0 - 0.62) * t
            # gentle cloth ripple along the hem
            x += side * math.sin(u * math.pi * 3.0) * 0.02 * t
            verts.append((x, y, z))
    for r in range(ROWS):
        for c in range(COLS):
            a = r * (COLS + 1) + c
            faces.append((a, a + 1, a + COLS + 2, a + COLS + 1))
    me = bpy.data.meshes.new("caparison_panel")
    me.from_pydata(verts, [], faces)
    me.update()
    ob = bpy.data.objects.new("CaparisonPanel", me)
    bpy.context.collection.objects.link(ob)
    uv = me.uv_layers.new()
    for poly in me.polygons:
        for li in poly.loop_indices:
            vx, vy, vz = me.vertices[me.loops[li].vertex_index].co
            uu = (vy - CAP_Y0) / (CAP_Y1 - CAP_Y0)
            vv = (CAP_TOP_Z - vz) / (CAP_TOP_Z - CAP_HEM_Z)   # v=0 at TOP
            uv.data[li].uv = (uu if side > 0 else 1.0 - uu, max(0.0, vv))
    me.materials.append(MAT_CLOTH)
    for p in me.polygons:
        p.use_smooth = False
    cap_objs.append(ob)

bpy.ops.object.select_all(action='DESELECT')
for ob in cap_objs:
    ob.select_set(True)
bpy.context.view_layer.objects.active = cap_objs[0]
bpy.ops.object.join()
caparison = bpy.context.active_object
caparison.name = "Caparison"
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# ======================================================================
# CRINET + CHANFRON — the NEAR-SIDE cavalry read (critic P6, 2026-08-09)
# ======================================================================
# "On the far army it is a triumph... from directly behind, the rider occludes
# the mount." Both armies stand the same 74-degree broadside, so the stance was
# never the difference — the CAMERA ANGLE is. The near rank sits close under a
# high camera, so it is read from ABOVE, where a horse is its own plan view:
# the rider's chibi head owns the middle of the frame and the only mount left
# is a low, dark, foreshortened neck reaching out from under him. The far rank
# sits far away under a shallow angle, i.e. in profile, which is exactly the
# view a horse is designed to be recognised from.
#
# You cannot yaw your way out of that (both sides are already broadside), and
# reshaping the mount again would put the far side's triumph at risk. So the
# answer is added ARMOUR that has plan-view area, on the two parts that a
# top-down view otherwise loses:
#
#   CRINET   haus cloth over the whole NECK, withers to poll. From above it
#            paints the neck as a long haus-coloured band reaching forward
#            out of the rider — the shape that says "there is an animal under
#            this man" before any detail is legible.
#   CHANFRON a face plate with a brow spike at the end of that band. Small,
#            but it is the brightest thing on the mount and it sits exactly
#            where the horse's head is, so the band terminates in a HEAD
#            instead of trailing off into the board.
#
# Both are measured off the reshaped standing pose, like every other landmark
# here, and both are additive: the far-side silhouette gains barding and loses
# nothing.
hme = horse_mesh.data
NOSE_Y = min(v.co.y for v in hme.vertices)
HEAD_BACK_Y = NOSE_Y + 0.95          # the skull, forward of the poll
head_co = [v.co for v in hme.vertices if v.co.y <= HEAD_BACK_Y]
POLL_Z = max(c.z for c in head_co)
NECK_BACK_Y = CAP_Y0 + 0.05          # meets the caparison's fore edge


def spine_at(y, half=0.16, x_lim=0.75):
    """Top-of-body z and half-width at a station along the spine."""
    near = [v.co for v in hme.vertices
            if abs(v.co.y - y) <= half and abs(v.co.x) <= x_lim]
    if not near:
        return None
    return max(c.z for c in near), max(abs(c.x) for c in near)


def ribbon(name, rows, mat):
    """Quad strip through rows of same-length vertex lists."""
    verts, faces = [], []
    n = len(rows[0])
    for row in rows:
        verts.extend(row)
    for r in range(len(rows) - 1):
        for c in range(n - 1):
            a = r * n + c
            faces.append((a, a + 1, a + n + 1, a + n))
    me_r = bpy.data.meshes.new(name)
    me_r.from_pydata(verts, [], faces)
    me_r.update()
    ob = bpy.data.objects.new(name, me_r)
    bpy.context.collection.objects.link(ob)
    me_r.materials.append(mat)
    for p in me_r.polygons:
        p.use_smooth = False
    return ob


# --- crinet: 5 columns (hem, side, ridge, side, hem) x 9 stations
CRINET_STATIONS = 9
CRINET_LIFT = 0.045      # standoff so the cloth never z-fights the hide
CRINET_FLARE = 1.16      # the hem sits proud of the neck
CRINET_DROP = 0.30       # ...and hangs this far below the top line
crinet_rows = []
for i in range(CRINET_STATIONS):
    t = i / (CRINET_STATIONS - 1)
    y = NECK_BACK_Y + (HEAD_BACK_Y - NECK_BACK_Y) * t
    probe = spine_at(y)
    if probe is None:
        continue
    top, hw = probe
    hw = max(hw, 0.22)
    # taper the cloth toward the poll so it reads as barding, not a sack
    w = hw * CRINET_FLARE * (1.0 - 0.28 * t)
    drop = CRINET_DROP * (1.0 - 0.45 * t)
    z = top + CRINET_LIFT
    crinet_rows.append([
        (-w, y, z - drop), (-w * 0.72, y, z - drop * 0.30), (0.0, y, z),
        (w * 0.72, y, z - drop * 0.30), (w, y, z - drop),
    ])
crinet = ribbon("Crinet", crinet_rows, MAT_CRINET)

# --- chanfron: a face plate down the skull + a brow spike
CHANFRON_STATIONS = 5
CHANFRON_LIFT = 0.035
chanfron_rows = []
for i in range(CHANFRON_STATIONS):
    t = i / (CHANFRON_STATIONS - 1)
    y = HEAD_BACK_Y + (NOSE_Y + 0.06 - HEAD_BACK_Y) * t
    near = [c for c in head_co if abs(c.y - y) <= 0.16]
    if not near:
        continue
    top = max(c.z for c in near)
    hw = max(max(abs(c.x) for c in near), 0.10) * (1.0 - 0.30 * t)
    z = top + CHANFRON_LIFT
    chanfron_rows.append([
        (-hw, y, z - 0.14), (0.0, y, z), (hw, y, z - 0.14),
    ])
chanfron = ribbon("Chanfron", chanfron_rows, MAT_CHANFRON)
# PLUME: a swept crest off the poll — the head's skyline mark, and the one
# part of the mount that survives being looked at from directly above. Sized
# in WORLD terms, not by eye: the ensemble normalizes to 1.22 world units on a
# ~0.29 scale factor, so a 0.30-tall spike here renders 0.06 world (about
# three pixels on a board-distance knight) and might as well not exist.
#
# It also LEANS FORWARD, and that is the near-side half of the fix. A vertical
# spike is the worst possible shape for a camera looking down at it: at the
# near rank's ~50-degree elevation it foreshortens to cos(50) of its length
# and lands as a stub on the end of the neck band. Raked 42 degrees over the
# brow it projects nearly its FULL length in screen space, forward of the
# muzzle — so from above the band no longer just stops, it comes to a point,
# and the eye reads a head where the point is. In profile (the far army) the
# same rake is simply a swept war crest.
PLUME_LEN = 0.95
PLUME_RAKE_DEG = 42.0
spike = add_box((0.115, 0.115, PLUME_LEN),
                (0.0, HEAD_BACK_Y - 0.04, POLL_Z + 0.02), MAT_CHANFRON,
                taper=0.16)
spike.rotation_euler = (math.radians(PLUME_RAKE_DEG), 0.0, 0.0)
bpy.ops.object.select_all(action='DESELECT')
for ob in (chanfron, spike):
    ob.select_set(True)
bpy.context.view_layer.objects.active = chanfron
bpy.ops.object.join()
chanfron = bpy.context.active_object
chanfron.name = "Chanfron"
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
print(f"[horse] barding: crinet {NECK_BACK_Y:.2f}..{HEAD_BACK_Y:.2f} "
      f"({len(crinet_rows)} stations) · chanfron {HEAD_BACK_Y:.2f}..{NOSE_Y:.2f} "
      f"poll {POLL_Z:.2f}")

# ---------------------------------------------------------------- stats
deps = bpy.context.evaluated_depsgraph_get()
tris = 0
lo = [1e9] * 3
hi = [-1e9] * 3
for ob in [o for o in bpy.data.objects if o.type == 'MESH']:
    me = ob.evaluated_get(deps).to_mesh()
    me.calc_loop_triangles()
    tris += len(me.loop_triangles)
    for v in me.vertices:
        wv = ob.matrix_world @ v.co
        for i in range(3):
            lo[i] = min(lo[i], wv[i])
            hi[i] = max(hi[i], wv[i])
    ob.evaluated_get(deps).to_mesh_clear()
print(f"[horse] tris: {tris} (budget 3000 incl. tack)")
print(f"[horse] world size: x {hi[0]-lo[0]:.2f}  y {hi[1]-lo[1]:.2f}  z {hi[2]-lo[2]:.2f}")
print(f"[horse] saddle seat (Godot local): (0.0, {BACK_TOP + 0.10:.2f}, {-SADDLE_Y:.2f})")

# ---------------------------------------------------------------- export
os.makedirs(os.path.dirname(GLB_OUT) or ".", exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=GLB_OUT, export_format='GLB',
                          export_yup=True)
print(f"[horse] wrote {GLB_OUT}")
