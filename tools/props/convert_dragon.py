#!/usr/bin/env blender --python
"""
convert_dragon.py — Quaternius CC0 Dragon: FBX -> GLB with armature + animations.

Run headless:
  /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/convert_dragon.py -- \
      <path/to/Dragon.fbx> <out/dragon.glb>

Source: Quaternius "Ultimate Monsters" pack (CC0 1.0 Universal), Flying/FBX/Dragon.fbx.
A copy of the FBX + Atlas_Monsters.png + the pack License.txt is kept in
../source-dragon/ so this conversion is reproducible offline.

The FBX ships with the Atlas_Monsters.png palette texture. If the FBX's
material references don't resolve (absolute paths from the author's machine),
we wire the atlas found next to the FBX into every Principled BSDF base color
so the GLB is textured. Animations are imported as actions and exported as
named glTF animations (Blender 4.0 exporter, animation mode ACTIONS).
"""
import bpy
import os
import sys

argv = sys.argv[sys.argv.index("--") + 1:]
FBX_IN, GLB_OUT = argv[0], argv[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=FBX_IN, use_anim=True)

# ---------------------------------------------------------------- report scene
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
arms = [o for o in bpy.data.objects if o.type == 'ARMATURE']
print(f"[dragon] meshes: {[o.name for o in meshes]}")
print(f"[dragon] armatures: {[o.name for o in arms]}")

# FBX take names come in as 'CharacterArmature|CharacterArmature|Fast_Flying';
# strip to the last segment so Godot's AnimationPlayer shows clean clip names.
for a in bpy.data.actions:
    a.name = a.name.split("|")[-1]
print(f"[dragon] actions: {sorted(a.name for a in bpy.data.actions)}")

# The FBX importer leaves all takes except the active one as orphan actions
# (no NLA strip, no user) — the glTF exporter silently skips those, and the
# GLB ends up with a single animation. Stash every action into its own muted
# NLA track on the armature so the exporter picks them all up as named clips.
for arm in arms:
    if arm.animation_data is None:
        arm.animation_data_create()
    stashed = {s.action for t in arm.animation_data.nla_tracks
               for s in t.strips if s.action}
    for a in bpy.data.actions:
        if a in stashed:
            continue
        try:
            a.id_root = 'OBJECT'   # FBX import can leave this invalid
        except Exception:
            pass
        track = arm.animation_data.nla_tracks.new()
        track.name = a.name
        track.mute = True
        track.strips.new(a.name, int(a.frame_range[0]), a)
print(f"[dragon] NLA-stashed {len(bpy.data.actions)} actions for export")

# ------------------------------------------------- texture fallback (atlas)
atlas = os.path.join(os.path.dirname(FBX_IN), "Atlas_Monsters.png")
have_valid_image = False
for img in bpy.data.images:
    try:
        if img.source == 'FILE' and os.path.exists(bpy.path.abspath(img.filepath)):
            have_valid_image = True
    except Exception:
        pass
if not have_valid_image and os.path.exists(atlas):
    img = bpy.data.images.load(atlas)
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            continue
        nt = mat.node_tree
        bsdf = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
        if bsdf is None:
            continue
        tex = nt.nodes.new('ShaderNodeTexImage')
        tex.image = img
        nt.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    print(f"[dragon] wired atlas texture fallback: {atlas}")
else:
    print(f"[dragon] material images resolved from FBX: {have_valid_image}")

# ---------------------------------------------------------------- stats
deps = bpy.context.evaluated_depsgraph_get()
tris = 0
lo = [1e9] * 3
hi = [-1e9] * 3
for ob in meshes:
    me = ob.evaluated_get(deps).to_mesh()
    me.calc_loop_triangles()
    tris += len(me.loop_triangles)
    for v in me.vertices:
        w = ob.matrix_world @ v.co
        for i in range(3):
            lo[i] = min(lo[i], w[i])
            hi[i] = max(hi[i], w[i])
    ob.evaluated_get(deps).to_mesh_clear()
print(f"[dragon] tris: {tris}")
print(f"[dragon] world size (m): "
      f"x {hi[0]-lo[0]:.2f}  y {hi[1]-lo[1]:.2f}  z {hi[2]-lo[2]:.2f}")

# ---------------------------------------------------------------- export
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(
    filepath=GLB_OUT, export_format='GLB',
    export_animations=True, export_yup=True)
print(f"[dragon] wrote {GLB_OUT}")
