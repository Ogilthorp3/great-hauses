#!/usr/bin/env python3
"""
tools/blender/build_star_wars_props.py
Procedural Blender 3D asset generator for the Star Wars Jedi Council pieces in Great Hauses:
1. Princess Leia's Hair Buns (leia_buns.glb) - Queen
2. Han Solo's Holster & Vest (han_holster_vest.glb) - King
3. R2-D2 Astromech Droid (r2d2_droid.glb) - Dark Bishop
4. C-3PO Protocol Droid (c3po_head.glb) - Light Bishop
5. Millennium Falcon Rook (falcon_rook.glb) - Queenside Rook
6. Chewbacca Bandolier & Bowcaster (chewie_bandolier.glb) - Kingside Rook / Knight
7. Ewok Tribal Hood & Spear (ewok_hood_spear.glb) - Pawns
"""

import bpy
import bmesh
import math
import os

OUTPUT_DIR = "/Users/bert/Projects/great-hauses/assets/custom-props/star-wars"
os.makedirs(OUTPUT_DIR, exist_ok=True)

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def create_pbr_material(name, color=(0.8, 0.8, 0.8, 1.0), metallic=0.0, roughness=0.5, emission=(0, 0, 0, 1), emission_strength=0.0):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
        if "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = emission
        elif "Emission" in bsdf.inputs:
            bsdf.inputs["Emission"].default_value = emission
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat

def export_glb(obj, filename):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    path = os.path.join(OUTPUT_DIR, filename)
    bpy.ops.export_scene.gltf(
        filepath=path,
        use_selection=True,
        export_format="GLB",
        export_apply=True
    )
    print(f"✅ Exported: {path}")

# ── 1. Princess Leia's Twin Spiral Hair Buns (Queen) ──────────────────────
def build_leia_buns():
    reset_scene()
    mesh = bpy.data.meshes.new("LeiaBuns_Mesh")
    obj = bpy.data.objects.new("leia_buns", mesh)
    bpy.context.scene.collection.objects.link(obj)
    bm = bmesh.new()

    mat_hair = create_pbr_material("Leia_Hair", color=(0.14, 0.08, 0.05, 1.0), roughness=0.6)
    mat_comb = create_pbr_material("Leia_CombSilver", color=(0.85, 0.85, 0.9, 1.0), metallic=0.9, roughness=0.2)
    obj.data.materials.append(mat_hair)
    obj.data.materials.append(mat_comb)

    for side in [-1.0, 1.0]:
        x_center = side * 0.18
        for ring_idx, (r_out, r_in, x_offset) in enumerate([(0.09, 0.03, 0.0), (0.075, 0.025, side * 0.025), (0.05, 0.015, side * 0.045)]):
            segments_u = 16
            segments_v = 12
            for i in range(segments_u):
                theta1 = i * 2.0 * math.pi / segments_u
                theta2 = (i + 1) * 2.0 * math.pi / segments_u
                for j in range(segments_v):
                    phi1 = j * 2.0 * math.pi / segments_v
                    phi2 = (j + 1) * 2.0 * math.pi / segments_v

                    def torus_pt(th, ph, rad_maj, rad_min, off_x):
                        x = x_center + off_x + (rad_maj + rad_min * math.cos(ph)) * math.cos(th) * 0.3
                        y = (rad_maj + rad_min * math.cos(ph)) * math.sin(th)
                        z = rad_min * math.sin(ph)
                        return (x, y, z)

                    v1 = bm.verts.new(torus_pt(theta1, phi1, r_out, r_in, x_offset))
                    v2 = bm.verts.new(torus_pt(theta2, phi1, r_out, r_in, x_offset))
                    v3 = bm.verts.new(torus_pt(theta2, phi2, r_out, r_in, x_offset))
                    v4 = bm.verts.new(torus_pt(theta1, phi2, r_out, r_in, x_offset))
                    f = bm.faces.new((v1, v2, v3, v4))
                    f.material_index = 0

    bm.to_mesh(mesh)
    bm.free()
    export_glb(obj, "leia_buns.glb")

# ── 2. Han Solo's Holster & Smuggler Vest (King) ──────────────────────────
def build_han_holster_vest():
    reset_scene()
    mesh = bpy.data.meshes.new("HanGear_Mesh")
    obj = bpy.data.objects.new("han_holster_vest", mesh)
    bpy.context.scene.collection.objects.link(obj)
    bm = bmesh.new()

    mat_leather = create_pbr_material("Han_Leather", color=(0.22, 0.12, 0.08, 1.0), roughness=0.7)
    mat_metal = create_pbr_material("Han_BlasterSilver", color=(0.3, 0.32, 0.35, 1.0), metallic=0.9, roughness=0.3)
    obj.data.materials.append(mat_leather)
    obj.data.materials.append(mat_metal)

    belt_segs = 20
    b_radius = 0.19
    b_width = 0.035
    for i in range(belt_segs):
        th1 = i * 2.0 * math.pi / belt_segs
        th2 = (i + 1) * 2.0 * math.pi / belt_segs
        y_slant1 = -0.05 + 0.04 * math.sin(th1)
        y_slant2 = -0.05 + 0.04 * math.sin(th2)

        v1 = bm.verts.new((b_radius * math.cos(th1), b_radius * math.sin(th1), y_slant1))
        v2 = bm.verts.new((b_radius * math.cos(th2), b_radius * math.sin(th2), y_slant2))
        v3 = bm.verts.new((b_radius * math.cos(th2), b_radius * math.sin(th2), y_slant2 - b_width))
        v4 = bm.verts.new((b_radius * math.cos(th1), b_radius * math.sin(th1), y_slant1 - b_width))
        f = bm.faces.new((v1, v2, v3, v4))
        f.material_index = 0

    hx, hy, hz = 0.20, -0.04, -0.16
    h_w, h_d, h_h = 0.05, 0.08, 0.12
    hv = [
        bm.verts.new((hx - h_w, hy - h_d, hz)),
        bm.verts.new((hx + h_w, hy - h_d, hz)),
        bm.verts.new((hx + h_w, hy + h_d, hz)),
        bm.verts.new((hx - h_w, hy + h_d, hz)),
        bm.verts.new((hx - h_w * 0.5, hy - h_d * 0.5, hz - h_h)),
        bm.verts.new((hx + h_w * 0.5, hy - h_d * 0.5, hz - h_h)),
        bm.verts.new((hx + h_w * 0.5, hy + h_d * 0.5, hz - h_h)),
        bm.verts.new((hx - h_w * 0.5, hy + h_d * 0.5, hz - h_h)),
    ]
    bm.faces.new((hv[0], hv[1], hv[5], hv[4])).material_index = 0
    bm.faces.new((hv[1], hv[2], hv[6], hv[5])).material_index = 0
    bm.faces.new((hv[2], hv[3], hv[7], hv[6])).material_index = 0
    bm.faces.new((hv[3], hv[0], hv[4], hv[7])).material_index = 0
    bm.faces.new((hv[4], hv[5], hv[6], hv[7])).material_index = 0

    gh_v = [
        bm.verts.new((hx - 0.02, hy - 0.02, hz + 0.01)),
        bm.verts.new((hx + 0.02, hy - 0.02, hz + 0.01)),
        bm.verts.new((hx + 0.02, hy + 0.04, hz + 0.06)),
        bm.verts.new((hx - 0.02, hy + 0.04, hz + 0.06)),
    ]
    bm.faces.new(gh_v).material_index = 1

    bm.to_mesh(mesh)
    bm.free()
    export_glb(obj, "han_holster_vest.glb")

# ── 3. R2-D2 Astromech Droid (Dark Bishop) ────────────────────────────────
def build_r2d2_droid():
    reset_scene()
    mesh = bpy.data.meshes.new("R2D2_Mesh")
    obj = bpy.data.objects.new("r2d2_droid", mesh)
    bpy.context.scene.collection.objects.link(obj)
    bm = bmesh.new()

    mat_white = create_pbr_material("R2_White", color=(0.92, 0.93, 0.95, 1.0), roughness=0.35)
    mat_blue = create_pbr_material("R2_Blue", color=(0.04, 0.22, 0.65, 1.0), metallic=0.4, roughness=0.3)
    mat_silver = create_pbr_material("R2_DomeSilver", color=(0.82, 0.84, 0.88, 1.0), metallic=0.9, roughness=0.2)
    mat_eye_red = create_pbr_material("R2_EyeRed", color=(0.9, 0.1, 0.1, 1.0), emission=(1, 0.1, 0.1, 1), emission_strength=4.0)
    obj.data.materials.append(mat_white)
    obj.data.materials.append(mat_blue)
    obj.data.materials.append(mat_silver)
    obj.data.materials.append(mat_eye_red)

    segs = 20
    radius = 0.14
    h_body = 0.22
    for i in range(segs):
        th1 = i * 2.0 * math.pi / segs
        th2 = (i + 1) * 2.0 * math.pi / segs
        v1 = bm.verts.new((radius * math.cos(th1), radius * math.sin(th1), -0.05))
        v2 = bm.verts.new((radius * math.cos(th2), radius * math.sin(th2), -0.05))
        v3 = bm.verts.new((radius * math.cos(th2), radius * math.sin(th2), -0.05 + h_body))
        v4 = bm.verts.new((radius * math.cos(th1), radius * math.sin(th1), -0.05 + h_body))
        f = bm.faces.new((v1, v2, v3, v4))
        f.material_index = 1 if (i % 5 == 0) else 0

    rings = 6
    z_base = -0.05 + h_body
    v_top = bm.verts.new((0, 0, z_base + radius))
    ring_verts = []
    for r in range(1, rings):
        phi = r * (0.5 * math.pi / rings)
        z_r = z_base + radius * math.cos(phi)
        rad_r = radius * math.sin(phi)
        r_list = []
        for s in range(segs):
            th = s * 2.0 * math.pi / segs
            r_list.append(bm.verts.new((rad_r * math.cos(th), rad_r * math.sin(th), z_r)))
        ring_verts.append(r_list)

    for s in range(segs):
        s_n = (s + 1) % segs
        f = bm.faces.new((v_top, ring_verts[0][s], ring_verts[0][s_n]))
        f.material_index = 2

    for r in range(rings - 2):
        for s in range(segs):
            s_n = (s + 1) % segs
            f = bm.faces.new((ring_verts[r][s], ring_verts[r+1][s], ring_verts[r+1][s_n], ring_verts[r][s_n]))
            f.material_index = 1 if (s in [2, 3, 8, 9, 14, 15] and r == 1) else 2

    eye_v = [
        bm.verts.new((0.02, 0.12, z_base + 0.08)),
        bm.verts.new((-0.02, 0.12, z_base + 0.08)),
        bm.verts.new((-0.02, 0.15, z_base + 0.06)),
        bm.verts.new((0.02, 0.15, z_base + 0.06))
    ]
    bm.faces.new(eye_v).material_index = 3

    for side in [-1.0, 1.0]:
        lx = side * 0.17
        leg_v = [
            bm.verts.new((lx - 0.02, -0.03, -0.15)),
            bm.verts.new((lx + 0.02, -0.03, -0.15)),
            bm.verts.new((lx + 0.02, 0.03, z_base + 0.02)),
            bm.verts.new((lx - 0.02, 0.03, z_base + 0.02)),
        ]
        bm.faces.new(leg_v).material_index = 0

    bm.to_mesh(mesh)
    bm.free()
    export_glb(obj, "r2d2_droid.glb")

# ── 4. C-3PO Golden Protocol Chassis (Light Bishop) ───────────────────────
def build_c3po_head():
    reset_scene()
    mesh = bpy.data.meshes.new("C3PO_Mesh")
    obj = bpy.data.objects.new("c3po_head", mesh)
    bpy.context.scene.collection.objects.link(obj)
    bm = bmesh.new()

    mat_gold = create_pbr_material("C3PO_Gold", color=(0.95, 0.76, 0.18, 1.0), metallic=0.92, roughness=0.22)
    mat_eyes_glow = create_pbr_material("C3PO_Eyes", color=(1.0, 0.95, 0.6, 1.0), emission=(1.0, 0.95, 0.6, 1), emission_strength=5.0)
    obj.data.materials.append(mat_gold)
    obj.data.materials.append(mat_eyes_glow)

    hw, hd, hh = 0.10, 0.11, 0.14
    v = [
        bm.verts.new((-hw, -hd, 0)),
        bm.verts.new((hw, -hd, 0)),
        bm.verts.new((hw * 0.8, hd, 0)),
        bm.verts.new((-hw * 0.8, hd, 0)),
        bm.verts.new((-hw * 0.9, -hd * 0.8, hh)),
        bm.verts.new((hw * 0.9, -hd * 0.8, hh)),
        bm.verts.new((hw * 0.7, hd * 0.7, hh)),
        bm.verts.new((-hw * 0.7, hd * 0.7, hh)),
    ]
    bm.faces.new((v[0], v[1], v[5], v[4])).material_index = 0
    bm.faces.new((v[1], v[2], v[6], v[5])).material_index = 0
    bm.faces.new((v[2], v[3], v[7], v[6])).material_index = 0
    bm.faces.new((v[3], v[0], v[4], v[7])).material_index = 0
    bm.faces.new((v[4], v[5], v[6], v[7])).material_index = 0

    for eye_side in [-1.0, 1.0]:
        ex = eye_side * 0.045
        ey = -hd * 0.95
        ez = hh * 0.65
        eye_verts = [
            bm.verts.new((ex - 0.02, ey, ez - 0.02)),
            bm.verts.new((ex + 0.02, ey, ez - 0.02)),
            bm.verts.new((ex + 0.02, ey, ez + 0.02)),
            bm.verts.new((ex - 0.02, ey, ez + 0.02))
        ]
        bm.faces.new(eye_verts).material_index = 1

    bm.to_mesh(mesh)
    bm.free()
    export_glb(obj, "c3po_head.glb")

# ── 5. Millennium Falcon Rook (Queenside Rook) ─────────────────────────────
def build_falcon_rook():
    reset_scene()
    mesh = bpy.data.meshes.new("FalconRook_Mesh")
    obj = bpy.data.objects.new("falcon_rook", mesh)
    bpy.context.scene.collection.objects.link(obj)
    bm = bmesh.new()

    mat_hull = create_pbr_material("Falcon_Hull", color=(0.82, 0.83, 0.86, 1.0), metallic=0.3, roughness=0.55)
    mat_engines = create_pbr_material("Falcon_Engines", color=(0.2, 0.7, 1.0, 1.0), emission=(0.2, 0.7, 1.0, 1), emission_strength=8.0)
    mat_pedestal = create_pbr_material("Rook_Stone", color=(0.25, 0.25, 0.28, 1.0), roughness=0.85)
    obj.data.materials.append(mat_hull)
    obj.data.materials.append(mat_engines)
    obj.data.materials.append(mat_pedestal)

    p_segs = 16
    p_rad = 0.12
    p_h = 0.35
    for i in range(p_segs):
        th1 = i * 2.0 * math.pi / p_segs
        th2 = (i + 1) * 2.0 * math.pi / p_segs
        v1 = bm.verts.new((p_rad * math.cos(th1), p_rad * math.sin(th1), 0))
        v2 = bm.verts.new((p_rad * math.cos(th2), p_rad * math.sin(th2), 0))
        v3 = bm.verts.new((p_rad * math.cos(th2), p_rad * math.sin(th2), p_h))
        v4 = bm.verts.new((p_rad * math.cos(th1), p_rad * math.sin(th1), p_h))
        f = bm.faces.new((v1, v2, v3, v4))
        f.material_index = 2

    f_z = p_h + 0.08
    f_rad = 0.22
    f_segs = 24
    saucer_top = bm.verts.new((0, 0, f_z + 0.04))
    saucer_bot = bm.verts.new((0, 0, f_z - 0.04))
    rim_verts = []
    for i in range(f_segs):
        th = i * 2.0 * math.pi / f_segs
        r = f_rad
        if math.cos(th) > 0.5:
            r = f_rad * 1.25
        rim_verts.append(bm.verts.new((r * math.cos(th), r * math.sin(th), f_z)))

    for i in range(f_segs):
        i_n = (i + 1) % f_segs
        bm.faces.new((saucer_top, rim_verts[i], rim_verts[i_n])).material_index = 0
        bm.faces.new((saucer_bot, rim_verts[i_n], rim_verts[i])).material_index = 0

    eng_v = [
        bm.verts.new((-f_rad * 0.7, -f_rad * 0.6, f_z - 0.01)),
        bm.verts.new((-f_rad * 0.7, -f_rad * 0.6, f_z + 0.01)),
        bm.verts.new((-f_rad * 0.7, f_rad * 0.6, f_z + 0.01)),
        bm.verts.new((-f_rad * 0.7, f_rad * 0.6, f_z - 0.01))
    ]
    bm.faces.new(eng_v).material_index = 1

    bm.to_mesh(mesh)
    bm.free()
    export_glb(obj, "falcon_rook.glb")

# ── 6. Chewbacca Bandolier & Bowcaster (Kingside Rook / Knight) ────────────
def build_chewie_bandolier():
    reset_scene()
    mesh = bpy.data.meshes.new("ChewieGear_Mesh")
    obj = bpy.data.objects.new("chewie_bandolier", mesh)
    bpy.context.scene.collection.objects.link(obj)
    bm = bmesh.new()

    mat_sash = create_pbr_material("Chewie_Sash", color=(0.18, 0.11, 0.08, 1.0), roughness=0.8)
    mat_silver_cartridges = create_pbr_material("Chewie_Cartridges", color=(0.85, 0.85, 0.88, 1.0), metallic=0.95, roughness=0.18)
    obj.data.materials.append(mat_sash)
    obj.data.materials.append(mat_silver_cartridges)

    steps = 14
    for i in range(steps):
        t1 = i / float(steps)
        t2 = (i + 1) / float(steps)
        p1 = (-0.14 + 0.30 * t1, 0.09, 0.22 - 0.37 * t1)
        p2 = (-0.14 + 0.30 * t2, 0.09, 0.22 - 0.37 * t2)

        w = 0.035
        v1 = bm.verts.new((p1[0] - w * 0.5, p1[1], p1[2] + w * 0.5))
        v2 = bm.verts.new((p1[0] + w * 0.5, p1[1], p1[2] - w * 0.5))
        v3 = bm.verts.new((p2[0] + w * 0.5, p2[1], p2[2] - w * 0.5))
        v4 = bm.verts.new((p2[0] - w * 0.5, p2[1], p2[2] + w * 0.5))
        f = bm.faces.new((v1, v2, v3, v4))
        f.material_index = 0

        if i % 2 == 0:
            c_cen = (p1[0] + p2[0]) * 0.5, 0.11, (p1[2] + p2[2]) * 0.5
            cw, ch = 0.015, 0.03
            cv = [
                bm.verts.new((c_cen[0] - cw, c_cen[1], c_cen[2] - ch)),
                bm.verts.new((c_cen[0] + cw, c_cen[1], c_cen[2] - ch)),
                bm.verts.new((c_cen[0] + cw, c_cen[1], c_cen[2] + ch)),
                bm.verts.new((c_cen[0] - cw, c_cen[1], c_cen[2] + ch))
            ]
            bm.faces.new(cv).material_index = 1

    bm.to_mesh(mesh)
    bm.free()
    export_glb(obj, "chewie_bandolier.glb")

# ── 7. Ewok Tribal Hood & Spear (Pawns) ───────────────────────────────────
def build_ewok_hood_spear():
    reset_scene()
    mesh = bpy.data.meshes.new("EwokGear_Mesh")
    obj = bpy.data.objects.new("ewok_hood_spear", mesh)
    bpy.context.scene.collection.objects.link(obj)
    bm = bmesh.new()

    mat_hood = create_pbr_material("Ewok_LeatherHood", color=(0.42, 0.24, 0.12, 1.0), roughness=0.85)
    mat_wood = create_pbr_material("Ewok_SpearWood", color=(0.35, 0.22, 0.14, 1.0), roughness=0.8)
    mat_flint = create_pbr_material("Ewok_SpearFlint", color=(0.6, 0.62, 0.65, 1.0), roughness=0.45)
    obj.data.materials.append(mat_hood)
    obj.data.materials.append(mat_wood)
    obj.data.materials.append(mat_flint)

    h_segs = 16
    h_rad = 0.15
    for i in range(h_segs):
        th1 = i * 2.0 * math.pi / h_segs
        th2 = (i + 1) * 2.0 * math.pi / h_segs
        if math.sin(th1) > 0.4 and math.sin(th2) > 0.4 and (math.cos(th1) > -0.6 and math.cos(th1) < 0.6):
            continue
        v1 = bm.verts.new((h_rad * math.cos(th1), h_rad * math.sin(th1), -0.05))
        v2 = bm.verts.new((h_rad * math.cos(th2), h_rad * math.sin(th2), -0.05))
        v3 = bm.verts.new((h_rad * 0.8 * math.cos(th2), h_rad * 0.8 * math.sin(th2), 0.14))
        v4 = bm.verts.new((h_rad * 0.8 * math.cos(th1), h_rad * 0.8 * math.sin(th1), 0.14))
        f = bm.faces.new((v1, v2, v3, v4))
        f.material_index = 0

    sx, sy = 0.18, 0.08
    s_len = 0.55
    shaft_v = [
        bm.verts.new((sx - 0.01, sy - 0.01, -0.20)),
        bm.verts.new((sx + 0.01, sy - 0.01, -0.20)),
        bm.verts.new((sx + 0.01, sy + 0.01, s_len - 0.20)),
        bm.verts.new((sx - 0.01, sy + 0.01, s_len - 0.20))
    ]
    bm.faces.new(shaft_v).material_index = 1

    sz_top = s_len - 0.20
    flint_v = [
        bm.verts.new((sx, sy, sz_top + 0.09)),
        bm.verts.new((sx - 0.03, sy, sz_top)),
        bm.verts.new((sx + 0.03, sy, sz_top)),
        bm.verts.new((sx, sy + 0.02, sz_top))
    ]
    bm.faces.new((flint_v[0], flint_v[1], flint_v[2])).material_index = 2
    bm.faces.new((flint_v[0], flint_v[2], flint_v[3])).material_index = 2
    bm.faces.new((flint_v[0], flint_v[3], flint_v[1])).material_index = 2

    bm.to_mesh(mesh)
    bm.free()
    export_glb(obj, "ewok_hood_spear.glb")

def main():
    print("🚀 Building Star Wars 3D Piece Props in Blender...")
    build_leia_buns()
    build_han_holster_vest()
    build_r2d2_droid()
    build_c3po_head()
    build_falcon_rook()
    build_chewie_bandolier()
    build_ewok_hood_spear()
    print("✨ ALL 7 STAR WARS 3D PROPS GENERATED AND EXPORTED!")

if __name__ == "__main__":
    main()
