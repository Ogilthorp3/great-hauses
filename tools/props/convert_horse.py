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

WAR-TACK (original geometry, authored in the house art style):
  - "Saddle": chunky low-poly seat with pommel + cantle, leather brown.
  - "Caparison": two draped cloth panels down the flanks, UV-mapped 0..1
    per panel with v=0 at the TOP (Godot image convention) so the runtime
    can drop PieceAssets.banner_texture(house_id) straight in — the house
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

# ---------------------------------------------------------------- war tack
# World-space landmarks measured off the standing pose (Blender Z-up, horse
# faces -Y): back top z=3.515 over the saddle zone y in [-0.9..-0.2], torso
# half-width ~0.45, belly/leg action below z~2.2.
BACK_TOP = 3.515
SADDLE_Y = -0.55          # seat center along the spine (negative = forward)


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
saddle_parts = [
    add_box((0.72, 0.60, 0.20), (0.0, SADDLE_Y, BACK_TOP - 0.04), MAT_LEATHER,
            taper=0.88),
    add_box((0.62, 0.12, 0.38), (0.0, SADDLE_Y - 0.32, BACK_TOP - 0.02),
            MAT_LEATHER, taper=0.68),                     # pommel
    add_box((0.66, 0.14, 0.44), (0.0, SADDLE_Y + 0.33, BACK_TOP - 0.02),
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
CAP_HEM_Z = 1.92               # below the belly — the silhouette maker
CAP_HEM_X = 0.82
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
