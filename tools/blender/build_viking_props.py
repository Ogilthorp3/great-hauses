import bpy
import bmesh
import math
import os

def create_pawn_helm(output_path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mesh = bpy.data.meshes.new("PawnHelm_Mesh")
    obj = bpy.data.objects.new("pawn_helm", mesh)
    bpy.context.scene.collection.objects.link(obj)

    bm = bmesh.new()

    # 1. Dome (pawnhelm_iron)
    # Conical spangenhelm skull cap, mounts on head bone at y=0, hangs below
    segments = 16
    rings = 6
    radius = 0.16
    depth_y = 0.12

    dome_verts = []
    # Apex at top (y = 0.04)
    v_apex = bm.verts.new((0.0, 0.04, 0.0))

    for r in range(1, rings + 1):
        frac = r / float(rings)
        y = 0.04 - frac * (depth_y + 0.04)
        rad = radius * math.sin(frac * math.pi * 0.5)
        ring_v = []
        for s in range(segments):
            angle = s * (2.0 * math.pi / segments)
            x = rad * math.cos(angle)
            z = rad * math.sin(angle)
            ring_v.append(bm.verts.new((x, y, z)))
        dome_verts.append(ring_v)

    # Faces for dome apex
    for s in range(segments):
        s_next = (s + 1) % segments
        bm.faces.new((v_apex, dome_verts[0][s], dome_verts[0][s_next]))

    # Faces for dome body
    for r in range(rings - 1):
        for s in range(segments):
            s_next = (s + 1) % segments
            v1 = dome_verts[r][s]
            v2 = dome_verts[r + 1][s]
            v3 = dome_verts[r + 1][s_next]
            v4 = dome_verts[r][s_next]
            bm.faces.new((v1, v2, v3, v4))

    # 2. Brow band & Spectacle Ocular Guard (pawnhelm_accent)
    # Circular spectacle frame around the eyes and nasal guard
    spectacle_verts = []
    brow_y = -depth_y
    brow_rad = radius * 1.02

    # Brow band ring
    b_ring1 = []
    b_ring2 = []
    for s in range(segments):
        angle = s * (2.0 * math.pi / segments)
        x1 = brow_rad * math.cos(angle)
        z1 = brow_rad * math.sin(angle)
        x2 = (brow_rad + 0.015) * math.cos(angle)
        z2 = (brow_rad + 0.015) * math.sin(angle)
        b_ring1.append(bm.verts.new((x1, brow_y, z1)))
        b_ring2.append(bm.verts.new((x2, brow_y - 0.02, z2)))

    for s in range(segments):
        s_next = (s + 1) % segments
        bm.faces.new((b_ring1[s], b_ring2[s], b_ring2[s_next], b_ring1[s_next]))

    # Nasal bar protruding down between eyes in +Z
    v_n1 = bm.verts.new((-0.015, brow_y - 0.02, brow_rad + 0.012))
    v_n2 = bm.verts.new((0.015, brow_y - 0.02, brow_rad + 0.012))
    v_n3 = bm.verts.new((0.012, brow_y - 0.07, brow_rad + 0.015))
    v_n4 = bm.verts.new((-0.012, brow_y - 0.07, brow_rad + 0.015))
    bm.faces.new((v_n1, v_n2, v_n3, v_n4))

    # Left and Right spectacle eye arches
    # Left eye arch
    v_el1 = bm.verts.new((-0.055, brow_y - 0.05, brow_rad * 0.95))
    v_el2 = bm.verts.new((-0.02, brow_y - 0.02, brow_rad + 0.01))
    v_el3 = bm.verts.new((-0.015, brow_y - 0.06, brow_rad + 0.01))
    v_el4 = bm.verts.new((-0.05, brow_y - 0.065, brow_rad * 0.95))
    bm.faces.new((v_el2, v_n1, v_n4, v_el3))
    bm.faces.new((v_el1, v_el2, v_el3, v_el4))

    # Right eye arch
    v_er1 = bm.verts.new((0.055, brow_y - 0.05, brow_rad * 0.95))
    v_er2 = bm.verts.new((0.02, brow_y - 0.02, brow_rad + 0.01))
    v_er3 = bm.verts.new((0.015, brow_y - 0.06, brow_rad + 0.01))
    v_er4 = bm.verts.new((0.05, brow_y - 0.065, brow_rad * 0.95))
    bm.faces.new((v_n2, v_er2, v_er3, v_n3))
    bm.faces.new((v_er2, v_er1, v_er4, v_er3))

    bm.to_mesh(mesh)
    bm.free()

    # Materials for contract
    mat_iron = bpy.data.materials.new(name="pawnhelm_iron")
    mat_iron.diffuse_color = (0.08, 0.15, 0.22, 1.0)
    mat_accent = bpy.data.materials.new(name="pawnhelm_accent")
    mat_accent.diffuse_color = (0.28, 0.79, 0.89, 1.0)

    obj.data.materials.append(mat_iron)
    obj.data.materials.append(mat_accent)

    # Assign material slots (slot 0: dome, slot 1: brow & spectacles)
    for i, poly in enumerate(mesh.polygons):
        if i < segments + (rings - 1) * segments:
            poly.material_index = 0
        else:
            poly.material_index = 1

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=output_path,
        export_format='GLB',
        use_selection=False,
        export_apply=True
    )
    print("Exported Viking Pawn Helm ->", output_path)


def create_wendigo_crest(output_path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mesh = bpy.data.meshes.new("Crest_vinterdread_Mesh")
    obj = bpy.data.objects.new("Crest_vinterdread", mesh)
    bpy.context.scene.collection.objects.link(obj)

    bm = bmesh.new()

    # Helper: add cylinder/cone branch
    def add_branch(p_start, p_end, r_start, r_end, sides=8):
        v_diff = (p_end[0] - p_start[0], p_end[1] - p_start[1], p_end[2] - p_start[2])
        length = math.sqrt(v_diff[0]**2 + v_diff[1]**2 + v_diff[2]**2)
        if length < 1e-5:
            return []
        
        # Basis vector for cylinder
        dir_v = (v_diff[0] / length, v_diff[1] / length, v_diff[2] / length)
        up = (0.0, 1.0, 0.0)
        if abs(dir_v[1]) > 0.9:
            up = (1.0, 0.0, 0.0)
        
        # Orthogonal axes
        side_x = (up[1]*dir_v[2] - up[2]*dir_v[1], up[2]*dir_v[0] - up[0]*dir_v[2], up[0]*dir_v[1] - up[1]*dir_v[0])
        s_len = math.sqrt(side_x[0]**2 + side_x[1]**2 + side_x[2]**2)
        side_x = (side_x[0]/s_len, side_x[1]/s_len, side_x[2]/s_len)
        side_y = (dir_v[1]*side_x[2] - dir_v[2]*side_x[1], dir_v[2]*side_x[0] - dir_v[0]*side_x[2], dir_v[0]*side_x[1] - dir_v[1]*side_x[0])

        ring_s = []
        ring_e = []
        for i in range(sides):
            a = i * (2.0 * math.pi / sides)
            dx = math.cos(a)
            dy = math.sin(a)
            
            ps = (p_start[0] + (side_x[0]*dx + side_y[0]*dy)*r_start,
                  p_start[1] + (side_x[1]*dx + side_y[1]*dy)*r_start,
                  p_start[2] + (side_x[2]*dx + side_y[2]*dy)*r_start)
            pe = (p_end[0] + (side_x[0]*dx + side_y[0]*dy)*r_end,
                  p_end[1] + (side_x[1]*dx + side_y[1]*dy)*r_end,
                  p_end[2] + (side_x[2]*dx + side_y[2]*dy)*r_end)
            
            ring_s.append(bm.verts.new(ps))
            ring_e.append(bm.verts.new(pe))

        faces = []
        for i in range(sides):
            i_next = (i + 1) % sides
            faces.append(bm.faces.new((ring_s[i], ring_e[i], ring_e[i_next], ring_s[i_next])))
        
        # End cap
        v_tip = bm.verts.new(p_end)
        for i in range(sides):
            i_next = (i + 1) % sides
            faces.append(bm.faces.new((ring_e[i], v_tip, ring_e[i_next])))

        return faces

    # 1. Antlers (Left & Right branched deer horns)
    antler_faces = []
    for sign in [-1.0, 1.0]:
        # Main antler beam: base at head side curving up and back
        p0 = (sign * 0.08, 0.04, 0.02)
        p1 = (sign * 0.16, 0.18, -0.02)
        p2 = (sign * 0.24, 0.32, -0.06)
        p3 = (sign * 0.28, 0.44, -0.04)
        
        antler_faces.extend(add_branch(p0, p1, 0.022, 0.018))
        antler_faces.extend(add_branch(p1, p2, 0.018, 0.014))
        antler_faces.extend(add_branch(p2, p3, 0.014, 0.006))

        # Brow tine (pointing forward)
        p_brow_end = (sign * 0.20, 0.24, 0.10)
        antler_faces.extend(add_branch(p1, p_brow_end, 0.014, 0.005))

        # Crown tine (pointing inward/up)
        p_crown_end = (sign * 0.18, 0.42, 0.02)
        antler_faces.extend(add_branch(p2, p_crown_end, 0.012, 0.005))

        # Rear tine (pointing back)
        p_rear_end = (sign * 0.28, 0.36, -0.14)
        antler_faces.extend(add_branch(p2, p_rear_end, 0.011, 0.004))

    # 2. Dreadlock braids flowing down the back and sides
    dread_faces = []
    dread_strands = [
        # Left side dreads
        [(-0.10, 0.02, 0.02), (-0.12, -0.08, 0.01), (-0.11, -0.18, -0.01)],
        [(-0.08, 0.03, -0.04), (-0.10, -0.09, -0.06), (-0.09, -0.20, -0.08)],
        # Right side dreads
        [(0.10, 0.02, 0.02), (0.12, -0.08, 0.01), (0.11, -0.18, -0.01)],
        [(0.08, 0.03, -0.04), (0.10, -0.09, -0.06), (0.09, -0.20, -0.08)],
        # Back dreads (central waterfall)
        [(0.0, 0.04, -0.08), (0.0, -0.08, -0.11), (0.0, -0.22, -0.12)],
        [(-0.04, 0.04, -0.07), (-0.05, -0.08, -0.10), (-0.04, -0.21, -0.11)],
        [(0.04, 0.04, -0.07), (0.05, -0.08, -0.10), (0.04, -0.21, -0.11)]
    ]

    for strand in dread_strands:
        dread_faces.extend(add_branch(strand[0], strand[1], 0.014, 0.012, sides=6))
        dread_faces.extend(add_branch(strand[1], strand[2], 0.012, 0.008, sides=6))

    # 3. Fur-trimmed cap band & Valknut talisman
    cap_faces = []
    cap_ring_top = []
    cap_ring_bot = []
    for s in range(16):
        a = s * (2.0 * math.pi / 16)
        x = 0.12 * math.cos(a)
        z = 0.12 * math.sin(a)
        cap_ring_top.append(bm.verts.new((x, 0.05, z)))
        cap_ring_bot.append(bm.verts.new((x * 1.05, 0.01, z * 1.05)))

    for s in range(16):
        s_next = (s + 1) % 16
        cap_faces.append(bm.faces.new((cap_ring_top[s], cap_ring_bot[s], cap_ring_bot[s_next], cap_ring_top[s_next])))

    bm.to_mesh(mesh)
    bm.free()

    # Materials for contract:
    # 0: vinterdread_antlers (natural:bone)
    # 1: vinterdread_dreads  (natural:leather)
    # 2: vinterdread_cap     (kit)
    mat_antler = bpy.data.materials.new(name="vinterdread_antlers")
    mat_antler.diffuse_color = (0.78, 0.74, 0.65, 1.0) # Aged bone

    mat_dread = bpy.data.materials.new(name="vinterdread_dreads")
    mat_dread.diffuse_color = (0.22, 0.16, 0.12, 1.0) # Dark leather/hair

    mat_cap = bpy.data.materials.new(name="vinterdread_cap")
    mat_cap.diffuse_color = (0.05, 0.46, 0.71, 1.0) # Fjord Blue kit

    obj.data.materials.append(mat_antler)
    obj.data.materials.append(mat_dread)
    obj.data.materials.append(mat_cap)

    # Material assignment across faces
    n_antler = len(antler_faces)
    n_dread = len(dread_faces)
    for i, poly in enumerate(mesh.polygons):
        if i < n_antler:
            poly.material_index = 0
        elif i < n_antler + n_dread:
            poly.material_index = 1
        else:
            poly.material_index = 2

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=output_path,
        export_format='GLB',
        use_selection=False,
        export_apply=True
    )
    print("Exported Wendigo Wizard Crest ->", output_path)


if __name__ == "__main__":
    pawn_out = "/Users/bert/Projects/great-hauses-core/assets/custom-props/pawn-helms/pawn_helm_vinterdread.glb"
    crest_out = "/Users/bert/Projects/great-hauses-core/assets/custom-props/crests/crest_vinterdread.glb"
    create_pawn_helm(pawn_out)
    create_wendigo_crest(crest_out)
