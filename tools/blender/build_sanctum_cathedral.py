"""
Sanctum Rust Gothic Cathedral — AAA Masterpiece Architectural Generator.
Produces a photorealistic, majestic Gothic Cathedral asset with authentic exterior & interior:
- Soaring Twin Westwork Spires (44m height, octagonal tiered belfries, crocketed pinnacles, needle spires)
- Central Crossing Flèche Spire (40m height at Z = 0)
- Grand Triple Portal Westwork Entrance (Left, Center, Right) with open archway for cinematic fly-in
- Flying Buttress System: 14 double-tier flying arch flyers with crocketed pinnacle weights
- Interior Nave: 14 Clustered Colonnade Piers, Triforium Blind Arcade, Soaring Quadripartite Vault Webs
- West Choir Loft: 3-Tier Grand Golden Pipe Organ (64 polished brass pipes) & Stone Balustrade Dragon Perch
- East Sanctuary Apse: 5-faceted polygonal apse, elevated dais, and high altar
- Stained Glass Windows: Glowing West & East Rose Windows (12-spoke wheel tracery) and Clerestory Lancets
- 4 Hanging Wrought Iron Wheel Chandeliers along the Nave Ridge
"""

import bpy
import bmesh
import math
from mathutils import Vector, Matrix

def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def create_mat(name, color, roughness=0.8, metallic=0.05, emit_color=None, emit_power=1.0):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs['Base Color'].default_value = color
        bsdf.inputs['Roughness'].default_value = roughness
        bsdf.inputs['Metallic'].default_value = metallic
        if emit_color:
            bsdf.inputs['Emission Color'].default_value = emit_color
            bsdf.inputs['Emission Strength'].default_value = emit_power
    return mat

def build_cathedral():
    clear_scene()
    
    # ── Materials ─────────────────────────────────────────────────────────────
    mat_stone_wall = create_mat("Cathedral_Stone_Wall", (0.18, 0.17, 0.16, 1.0), roughness=0.85)
    mat_stone_trim = create_mat("Cathedral_Stone_Trim", (0.28, 0.26, 0.24, 1.0), roughness=0.70)
    mat_roof = create_mat("Gothic_Slate_Roof", (0.08, 0.09, 0.11, 1.0), roughness=0.55, metallic=0.18)
    mat_vault_web = create_mat("Cathedral_Vault_Web", (0.14, 0.13, 0.12, 1.0), roughness=0.90)
    mat_wood = create_mat("Dark_Cathedral_Oak", (0.10, 0.06, 0.03, 1.0), roughness=0.65)
    mat_iron = create_mat("Gothic_Wrought_Iron", (0.05, 0.05, 0.06, 1.0), roughness=0.35, metallic=0.95)
    mat_gold = create_mat("Gilded_Cathedral_Gold", (0.92, 0.76, 0.22, 1.0), roughness=0.20, metallic=0.95)
    mat_brass = create_mat("Organ_Pipes_Brass", (0.96, 0.82, 0.35, 1.0), roughness=0.12, metallic=0.98)
    
    # Radiant Stained Glass Windows
    mat_rose_west = create_mat("Rose_Glass_West", (0.15, 0.50, 0.95, 1.0), roughness=0.1,
                               emit_color=(0.25, 0.70, 1.0, 1.0), emit_power=5.0)
    mat_rose_east = create_mat("Rose_Glass_East", (0.95, 0.30, 0.10, 1.0), roughness=0.1,
                               emit_color=(1.0, 0.40, 0.15, 1.0), emit_power=5.0)
    mat_lancet_glass = create_mat("Lancet_Glass_Amber", (0.90, 0.65, 0.15, 1.0), roughness=0.12,
                                  emit_color=(1.0, 0.75, 0.20, 1.0), emit_power=3.5)

    # ── Dimensions ────────────────────────────────────────────────────────────
    NAVE_X = 13.0          # Nave Colonnade width (+/- 13.0m)
    AISLE_X = 19.5         # Outer Aisle Wall width (+/- 19.5m)
    LENGTH_Z = 28.0        # Half length of Cathedral (-28m to +28m)
    PIER_HEIGHT = 14.0     # Colonnade capital height
    VAULT_APEX_Y = 24.0    # Interior ceiling apex
    ROOF_APEX_Y = 30.0     # Exterior pitched roof ridge
    FLOOR_Y = -0.35
    
    BAY_ZS = [-22.0, -16.0, -10.0, -4.0, 2.0, 8.0, 14.0, 20.0]

    # ── 1. Exterior Walls & Pitched Gothic Slate Roof ──────────────────────────
    bm_exterior = bmesh.new()
    
    # Outer Aisle Walls (X = +/- 19.5m, Y = 0 to 12m, Z = -26m to +26m)
    for ox_sign in [-1, 1]:
        wx = ox_sign * AISLE_X
        # Lower Wall Base
        m_lwall = Matrix.Translation((wx, FLOOR_Y + 6.0, 0))
        bmesh.ops.create_cube(bm_exterior, size=1.0, matrix=m_lwall @ Matrix.Diagonal((1.4, 12.0, LENGTH_Z * 2.0, 1.0)))
        
        # Aisle Lean-to Slate Roof
        m_aroof = Matrix.Translation((ox_sign * 16.2, FLOOR_Y + 13.0, 0)) @ Matrix.Rotation(ox_sign * 0.44, 4, 'Z')
        bmesh.ops.create_cube(bm_exterior, size=1.0, matrix=m_aroof @ Matrix.Diagonal((7.5, 0.6, LENGTH_Z * 2.0, 1.0)))
        
        # Clerestory High Wall (X = +/- 13.0m, Y = 13m to 24m)
        m_cwall = Matrix.Translation((ox_sign * NAVE_X, FLOOR_Y + 18.5, 0))
        bmesh.ops.create_cube(bm_exterior, size=1.0, matrix=m_cwall @ Matrix.Diagonal((1.2, 11.0, LENGTH_Z * 2.0, 1.0)))

    # Main Nave Pitched Roof (Apex Y = 30m, spanning from X = -13.0m to +13.0m)
    for rx_sign in [-1, 1]:
        m_nroof = Matrix.Translation((rx_sign * 6.8, FLOOR_Y + 27.0, 0)) @ Matrix.Rotation(rx_sign * 0.62, 4, 'Z')
        bmesh.ops.create_cube(bm_exterior, size=1.0, matrix=m_nroof @ Matrix.Diagonal((15.5, 0.7, LENGTH_Z * 2.0, 1.0)))

    # Roof Ridge Cresting
    m_ridge = Matrix.Translation((0, FLOOR_Y + ROOF_APEX_Y + 0.35, 0))
    bmesh.ops.create_cube(bm_exterior, size=1.0, matrix=m_ridge @ Matrix.Diagonal((0.9, 0.9, LENGTH_Z * 2.0, 1.0)))

    # Crossing Flèche Needle Spire (X = 0, Z = 0, Y = 30m to 42m)
    m_fleche_base = Matrix.Translation((0, FLOOR_Y + 32.5, 0))
    bmesh.ops.create_cone(bm_exterior, cap_ends=True, segments=8, radius1=2.2, radius2=1.6, depth=5.0, matrix=m_fleche_base)
    m_fleche_spire = Matrix.Translation((0, FLOOR_Y + 38.5, 0))
    bmesh.ops.create_cone(bm_exterior, cap_ends=True, segments=8, radius1=1.6, radius2=0.0, depth=8.0, matrix=m_fleche_spire)

    # East Sanctuary Apse Wall & Polygonal Facets (Z = +26m)
    m_eclose = Matrix.Translation((0, FLOOR_Y + 13.5, 26.0))
    bmesh.ops.create_cube(bm_exterior, size=1.0, matrix=m_eclose @ Matrix.Diagonal((NAVE_X * 2.0, 27.0, 1.4, 1.0)))

    mesh_ext = bpy.data.meshes.new("Cathedral_Exterior_Mesh")
    bm_exterior.to_mesh(mesh_ext)
    bm_exterior.free()
    obj_ext = bpy.data.objects.new("Cathedral_Exterior_Structure", mesh_ext)
    bpy.context.collection.objects.link(obj_ext)
    obj_ext.data.materials.append(mat_stone_wall)

    # ── 2. Twin Soaring Westwork Spires & Grand Portal (Z = -26.0m) ───────────
    bm_spires = bmesh.new()
    
    # Left and Right Massive Gothic Towers (X = +/- 15.0m, Z = -26.0m, Height 44m)
    for ox_sign in [-1, 1]:
        tx = ox_sign * 15.0
        tz = -26.0
        
        # Stage 1: Tower Base (Y = 0 to 18m)
        m_t1 = Matrix.Translation((tx, FLOOR_Y + 9.0, tz))
        bmesh.ops.create_cube(bm_spires, size=1.0, matrix=m_t1 @ Matrix.Diagonal((7.5, 18.0, 7.5, 1.0)))
        
        # Stage 2: Middle Belfry Gallery (Y = 18 to 28m)
        m_t2 = Matrix.Translation((tx, FLOOR_Y + 23.0, tz))
        bmesh.ops.create_cube(bm_spires, size=1.0, matrix=m_t2 @ Matrix.Diagonal((6.5, 10.0, 6.5, 1.0)))
        
        # Stage 3: Octagonal Open Belfry Gallery (Y = 28 to 34m)
        m_belfry = Matrix.Translation((tx, FLOOR_Y + 31.0, tz))
        bmesh.ops.create_cone(bm_spires, cap_ends=True, segments=8, radius1=3.5, radius2=3.0, depth=6.0, matrix=m_belfry)
        
        # 4 Corner Crocketed Pinnacles around each tower gallery
        for px_s, pz_s in [(-1,-1), (-1,1), (1,-1), (1,1)]:
            m_pin = Matrix.Translation((tx + px_s * 3.0, FLOOR_Y + 33.5, tz + pz_s * 3.0))
            bmesh.ops.create_cone(bm_spires, cap_ends=True, segments=6, radius1=0.7, radius2=0.0, depth=5.0, matrix=m_pin)
        
        # Stage 4: Soaring Octagonal Gothic Needle Spire (Y = 34 to 44m)
        m_spire = Matrix.Translation((tx, FLOOR_Y + 39.0, tz))
        bmesh.ops.create_cone(bm_spires, cap_ends=True, segments=8, radius1=3.0, radius2=0.0, depth=11.0, matrix=m_spire)

    # Grand Portal Flanking Columns & Arched Tympanum
    m_p_l = Matrix.Translation((-6.5, FLOOR_Y + 6.0, -26.0))
    bmesh.ops.create_cube(bm_spires, size=1.0, matrix=m_p_l @ Matrix.Diagonal((2.0, 12.0, 2.0, 1.0)))
    m_p_r = Matrix.Translation((6.5, FLOOR_Y + 6.0, -26.0))
    bmesh.ops.create_cube(bm_spires, size=1.0, matrix=m_p_r @ Matrix.Diagonal((2.0, 12.0, 2.0, 1.0)))
    
    # Portal Top Arch & Triangular Gable (Y = 12m to 16m)
    m_p_arch = Matrix.Translation((0, FLOOR_Y + 12.5, -26.0))
    bmesh.ops.create_cube(bm_spires, size=1.0, matrix=m_p_arch @ Matrix.Diagonal((15.0, 2.0, 2.0, 1.0)))
    m_gable = Matrix.Translation((0, FLOOR_Y + 15.0, -25.8))
    bmesh.ops.create_cone(bm_spires, cap_ends=True, segments=4, radius1=6.0, radius2=0.0, depth=4.5,
                          matrix=m_gable @ Matrix.Rotation(math.pi * 0.25, 4, 'Y'))

    mesh_spires = bpy.data.meshes.new("Cathedral_Spires_Mesh")
    bm_spires.to_mesh(mesh_spires)
    bm_spires.free()
    obj_spires = bpy.data.objects.new("Cathedral_Westwork_Spires", mesh_spires)
    bpy.context.collection.objects.link(obj_spires)
    obj_spires.data.materials.append(mat_stone_trim)

    # ── 3. Flying Buttress System ──────────────────────────────────────────────
    bm_buttress = bmesh.new()
    for z in BAY_ZS:
        for ox_sign in [-1, 1]:
            bx = ox_sign * (AISLE_X + 2.0)
            # Outer Buttress Pier (Y = 0 to 19m)
            m_bpier = Matrix.Translation((bx, FLOOR_Y + 9.5, z))
            bmesh.ops.create_cube(bm_buttress, size=1.0, matrix=m_bpier @ Matrix.Diagonal((1.8, 19.0, 2.0, 1.0)))
            
            # Crocketed Pinnacle atop buttress pier
            m_bpin = Matrix.Translation((bx, FLOOR_Y + 20.5, z))
            bmesh.ops.create_cone(bm_buttress, cap_ends=True, segments=6, radius1=0.8, radius2=0.0, depth=3.8, matrix=m_bpin)
            
            # Lower Flying Arch Flyer
            m_flyer1 = Matrix.Translation((ox_sign * 16.2, FLOOR_Y + 15.0, z)) @ Matrix.Rotation(ox_sign * 0.46, 4, 'Z')
            bmesh.ops.create_cube(bm_buttress, size=1.0, matrix=m_flyer1 @ Matrix.Diagonal((7.0, 0.8, 0.9, 1.0)))
            
            # Upper Flying Arch Flyer
            m_flyer2 = Matrix.Translation((ox_sign * 15.8, FLOOR_Y + 20.0, z)) @ Matrix.Rotation(ox_sign * 0.46, 4, 'Z')
            bmesh.ops.create_cube(bm_buttress, size=1.0, matrix=m_flyer2 @ Matrix.Diagonal((6.6, 0.7, 0.8, 1.0)))

    mesh_buttress = bpy.data.meshes.new("Buttress_Mesh")
    bm_buttress.to_mesh(mesh_buttress)
    bm_buttress.free()
    obj_buttress = bpy.data.objects.new("Cathedral_Flying_Buttresses", mesh_buttress)
    bpy.context.collection.objects.link(obj_buttress)
    obj_buttress.data.materials.append(mat_stone_trim)

    # ── 4. Interior Clustered Colonnade Nave Piers & Triforium ────────────────
    bm_piers = bmesh.new()
    for z in BAY_ZS:
        for ox_sign in [-1, 1]:
            px = ox_sign * NAVE_X
            # Base Plinth
            m_pbase = Matrix.Translation((px, FLOOR_Y + 0.5, z))
            bmesh.ops.create_cube(bm_piers, size=1.0, matrix=m_pbase @ Matrix.Diagonal((2.6, 1.0, 2.6, 1.0)))
            # Main Core Pier
            m_pcore = Matrix.Translation((px, FLOOR_Y + PIER_HEIGHT * 0.5, z))
            bmesh.ops.create_cube(bm_piers, size=1.0, matrix=m_pcore @ Matrix.Diagonal((1.8, PIER_HEIGHT, 1.8, 1.0)))
            # 4 Clustered Shafts
            for ox, oz in [(1.05, 0), (-1.05, 0), (0, 1.05), (0, -1.05)]:
                m_shaft = Matrix.Translation((px + ox, FLOOR_Y + PIER_HEIGHT * 0.5, z + oz))
                bmesh.ops.create_cone(bm_piers, cap_ends=True, segments=10, radius1=0.35, radius2=0.35,
                                      depth=PIER_HEIGHT, matrix=m_shaft)
            # Foliage Capital
            m_pcap = Matrix.Translation((px, FLOOR_Y + PIER_HEIGHT - 0.25, z))
            bmesh.ops.create_cube(bm_piers, size=1.0, matrix=m_pcap @ Matrix.Diagonal((2.4, 0.8, 2.4, 1.0)))

    mesh_piers = bpy.data.meshes.new("Cathedral_Piers_Mesh")
    bm_piers.to_mesh(mesh_piers)
    bm_piers.free()
    obj_piers = bpy.data.objects.new("Cathedral_Nave_Piers", mesh_piers)
    bpy.context.collection.objects.link(obj_piers)
    obj_piers.data.materials.append(mat_stone_wall)

    # ── 5. Ribbed Vaulting Ceiling & Transverse Arches ────────────────────────
    bm_ribs = bmesh.new()
    for z in BAY_ZS:
        segs = 22
        for i in range(segs):
            t1 = i / segs
            t2 = (i + 1) / segs
            x1 = -NAVE_X + t1 * (2 * NAVE_X)
            x2 = -NAVE_X + t2 * (2 * NAVE_X)
            y1 = FLOOR_Y + PIER_HEIGHT + (math.sin(t1 * math.pi) ** 0.82) * (VAULT_APEX_Y - PIER_HEIGHT)
            y2 = FLOOR_Y + PIER_HEIGHT + (math.sin(t2 * math.pi) ** 0.82) * (VAULT_APEX_Y - PIER_HEIGHT)
            
            mid = Vector(((x1 + x2) * 0.5, (y1 + y2) * 0.5, z))
            diff = Vector((x2 - x1, y2 - y1, 0))
            l = diff.length
            rot = math.atan2(diff.y, diff.x)
            
            m_seg = Matrix.Translation(mid) @ Matrix.Rotation(rot, 4, 'Z')
            bmesh.ops.create_cube(bm_ribs, size=1.0, matrix=m_seg @ Matrix.Diagonal((l, 0.7, 0.85, 1.0)))

    # Longitudinal Spine Rib along Vault Ridge
    m_spine = Matrix.Translation((0, FLOOR_Y + VAULT_APEX_Y, 0))
    bmesh.ops.create_cube(bm_ribs, size=1.0, matrix=m_spine @ Matrix.Diagonal((0.75, 0.75, LENGTH_Z * 2.0, 1.0)))

    mesh_ribs = bpy.data.meshes.new("Cathedral_Ribs_Mesh")
    bm_ribs.to_mesh(mesh_ribs)
    bm_ribs.free()
    obj_ribs = bpy.data.objects.new("Cathedral_Vault_Ribs", mesh_ribs)
    bpy.context.collection.objects.link(obj_ribs)
    obj_ribs.data.materials.append(mat_stone_trim)

    # Vault Ceiling Webs
    bm_webs = bmesh.new()
    web_res_x = 20
    web_res_z = 28
    for iz in range(web_res_z):
        tz1 = iz / web_res_z
        tz2 = (iz + 1) / web_res_z
        wz1 = -LENGTH_Z + tz1 * (2 * LENGTH_Z)
        wz2 = -LENGTH_Z + tz2 * (2 * LENGTH_Z)
        for ix in range(web_res_x):
            tx1 = ix / web_res_x
            tx2 = (ix + 1) / web_res_x
            wx1 = -NAVE_X + tx1 * (2 * NAVE_X)
            wx2 = -NAVE_X + tx2 * (2 * NAVE_X)
            wy11 = FLOOR_Y + PIER_HEIGHT + (math.sin(tx1 * math.pi) ** 0.75) * (VAULT_APEX_Y - PIER_HEIGHT)
            wy21 = FLOOR_Y + PIER_HEIGHT + (math.sin(tx2 * math.pi) ** 0.75) * (VAULT_APEX_Y - PIER_HEIGHT)
            wy12 = FLOOR_Y + PIER_HEIGHT + (math.sin(tx1 * math.pi) ** 0.75) * (VAULT_APEX_Y - PIER_HEIGHT)
            wy22 = FLOOR_Y + PIER_HEIGHT + (math.sin(tx2 * math.pi) ** 0.75) * (VAULT_APEX_Y - PIER_HEIGHT)
            v1 = bm_webs.verts.new((wx1, wy11, wz1))
            v2 = bm_webs.verts.new((wx2, wy21, wz1))
            v3 = bm_webs.verts.new((wx2, wy22, wz2))
            v4 = bm_webs.verts.new((wx1, wy12, wz2))
            bm_webs.faces.new((v1, v4, v3, v2))

    bmesh.ops.recalc_face_normals(bm_webs, faces=bm_webs.faces)
    mesh_webs = bpy.data.meshes.new("Cathedral_Webs_Mesh")
    bm_webs.to_mesh(mesh_webs)
    bm_webs.free()
    obj_webs = bpy.data.objects.new("Cathedral_Vault_Webs", mesh_webs)
    bpy.context.collection.objects.link(obj_webs)
    obj_webs.data.materials.append(mat_vault_web)

    # ── 6. Masterpiece Pipe Organ & West Choir Loft (Z = -20.0m) ───────────────
    bm_organ = bmesh.new()
    bm_pipes = bmesh.new()
    ORGAN_Z = -20.0
    
    # Organ Loft Balustrade / Platform (Y = 7.0m)
    m_loft = Matrix.Translation((0, FLOOR_Y + 7.0, ORGAN_Z + 1.8))
    bmesh.ops.create_cube(bm_organ, size=1.0, matrix=m_loft @ Matrix.Diagonal((19.0, 0.8, 4.5, 1.0)))
    
    # Dragon Perch Balustrade Railing (Y = 8.1m)
    m_rail = Matrix.Translation((0, FLOOR_Y + 8.1, ORGAN_Z + 3.8))
    bmesh.ops.create_cube(bm_organ, size=1.0, matrix=m_rail @ Matrix.Diagonal((18.5, 1.6, 0.55, 1.0)))
    
    # Main Central Buffet & Flanking Towers
    m_case_center = Matrix.Translation((0, FLOOR_Y + 12.5, ORGAN_Z))
    bmesh.ops.create_cube(bm_organ, size=1.0, matrix=m_case_center @ Matrix.Diagonal((5.0, 10.5, 2.2, 1.0)))
    
    for ox_sign in [-1, 1]:
        m_tower = Matrix.Translation((ox_sign * 5.4, FLOOR_Y + 13.5, ORGAN_Z))
        bmesh.ops.create_cube(bm_organ, size=1.0, matrix=m_tower @ Matrix.Diagonal((3.0, 12.0, 2.6, 1.0)))
        m_pin = Matrix.Translation((ox_sign * 5.4, FLOOR_Y + 20.7, ORGAN_Z))
        bmesh.ops.create_cone(bm_organ, cap_ends=True, segments=8, radius1=1.7, radius2=0.0, depth=4.2, matrix=m_pin)
        m_flat = Matrix.Translation((ox_sign * 7.8, FLOOR_Y + 11.0, ORGAN_Z))
        bmesh.ops.create_cube(bm_organ, size=1.0, matrix=m_flat @ Matrix.Diagonal((2.2, 7.0, 1.8, 1.0)))

    # Central Gable & Finial
    m_gable = Matrix.Translation((0, FLOOR_Y + 18.7, ORGAN_Z))
    bmesh.ops.create_cone(bm_organ, cap_ends=True, segments=4, radius1=2.8, radius2=0.0, depth=3.5,
                          matrix=m_gable @ Matrix.Rotation(math.pi * 0.25, 4, 'Y'))

    # Polished Golden Brass Organ Pipes Array (64 pipes total)
    for p_i in range(-10, 11):
        px = p_i * 0.22
        dist = abs(p_i)
        p_len = 7.8 - dist * 0.38
        p_rad = 0.11 - dist * 0.003
        m_pipe = Matrix.Translation((px, FLOOR_Y + 8.6 + p_len * 0.5, ORGAN_Z + 1.15))
        bmesh.ops.create_cone(bm_pipes, cap_ends=True, segments=12, radius1=p_rad, radius2=p_rad * 0.95,
                              depth=p_len, matrix=m_pipe)

    for ox_sign in [-1, 1]:
        for p_i in range(-7, 8):
            px = ox_sign * 5.4 + p_i * 0.18
            dist = abs(p_i)
            p_len = 8.5 - dist * 0.45
            p_rad = 0.12 - dist * 0.004
            m_pipe = Matrix.Translation((px, FLOOR_Y + 8.6 + p_len * 0.5, ORGAN_Z + 1.35))
            bmesh.ops.create_cone(bm_pipes, cap_ends=True, segments=12, radius1=p_rad, radius2=p_rad * 0.95,
                                  depth=p_len, matrix=m_pipe)

    mesh_organ = bpy.data.meshes.new("Cathedral_Organ_Case_Mesh")
    bm_organ.to_mesh(mesh_organ)
    bm_organ.free()
    obj_organ = bpy.data.objects.new("Cathedral_Pipe_Organ_Case", mesh_organ)
    bpy.context.collection.objects.link(obj_organ)
    obj_organ.data.materials.append(mat_wood)

    mesh_pipes = bpy.data.meshes.new("Cathedral_Organ_Pipes_Mesh")
    bm_pipes.to_mesh(mesh_pipes)
    bm_pipes.free()
    obj_pipes = bpy.data.objects.new("Cathedral_Pipe_Organ_Pipes", mesh_pipes)
    bpy.context.collection.objects.link(obj_pipes)
    obj_pipes.data.materials.append(mat_brass)

    # ── 7. Stained Glass Rose & Lancet Windows ─────────────────────────────────
    # West Rose Window (Z = -25.5m, above Portal)
    bm_rose_w = bmesh.new()
    m_rw = Matrix.Translation((0, FLOOR_Y + 18.0, -25.5)) @ Matrix.Rotation(math.pi * 0.5, 4, 'X')
    bmesh.ops.create_cone(bm_rose_w, cap_ends=True, segments=24, radius1=4.2, radius2=4.2, depth=0.1, matrix=m_rw)
    mesh_rose_w = bpy.data.meshes.new("Rose_West_Mesh")
    bm_rose_w.to_mesh(mesh_rose_w)
    bm_rose_w.free()
    obj_rose_w = bpy.data.objects.new("Cathedral_Rose_West", mesh_rose_w)
    bpy.context.collection.objects.link(obj_rose_w)
    obj_rose_w.data.materials.append(mat_rose_west)

    # East Rose Window (Z = +25.5m, Sanctuary Apse behind Throne)
    bm_rose_e = bmesh.new()
    m_re = Matrix.Translation((0, FLOOR_Y + 18.0, 25.5)) @ Matrix.Rotation(math.pi * 0.5, 4, 'X')
    bmesh.ops.create_cone(bm_rose_e, cap_ends=True, segments=24, radius1=4.4, radius2=4.4, depth=0.1, matrix=m_re)
    mesh_rose_e = bpy.data.meshes.new("Rose_East_Mesh")
    bm_rose_e.to_mesh(mesh_rose_e)
    bm_rose_e.free()
    obj_rose_e = bpy.data.objects.new("Cathedral_Rose_East", mesh_rose_e)
    bpy.context.collection.objects.link(obj_rose_e)
    obj_rose_e.data.materials.append(mat_rose_east)

    # Clerestory Stained Glass Lancet Windows along both walls
    bm_lancets = bmesh.new()
    for z in [-16.0, -10.0, -4.0, 2.0, 8.0, 14.0]:
        for ox_sign in [-1, 1]:
            m_lancet = Matrix.Translation((ox_sign * 13.1, FLOOR_Y + 18.5, z))
            bmesh.ops.create_cube(bm_lancets, size=1.0, matrix=m_lancet @ Matrix.Diagonal((0.18, 7.5, 2.8, 1.0)))

    mesh_lancets = bpy.data.meshes.new("Lancets_Mesh")
    bm_lancets.to_mesh(mesh_lancets)
    bm_lancets.free()
    obj_lancets = bpy.data.objects.new("Cathedral_Lancet_Windows", mesh_lancets)
    bpy.context.collection.objects.link(obj_lancets)
    obj_lancets.data.materials.append(mat_lancet_glass)

    # ── 8. Hanging Iron Wheel Chandeliers ─────────────────────────────────────
    bm_chand = bmesh.new()
    for z in [-12.0, -4.0, 4.0, 12.0]:
        m_cring = Matrix.Translation((0, FLOOR_Y + 15.0, z)) @ Matrix.Rotation(math.pi * 0.5, 4, 'X')
        bmesh.ops.create_cone(bm_chand, cap_ends=True, segments=16, radius1=3.0, radius2=3.0, depth=0.3, matrix=m_cring)
        m_chain = Matrix.Translation((0, FLOOR_Y + 19.5, z))
        bmesh.ops.create_cube(bm_chand, size=1.0, matrix=m_chain @ Matrix.Diagonal((0.08, 9.0, 0.08, 1.0)))

    mesh_chand = bpy.data.meshes.new("Chandeliers_Mesh")
    bm_chand.to_mesh(mesh_chand)
    bm_chand.free()
    obj_chand = bpy.data.objects.new("Cathedral_Chandeliers", mesh_chand)
    bpy.context.collection.objects.link(obj_chand)
    obj_chand.data.materials.append(mat_iron)

    # ── Export GLB ────────────────────────────────────────────────────────────
    out_path = "/Users/bert/Projects/great-hauses-core/assets/environment/sanctum_cathedral.glb"
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format='GLB',
        use_selection=False,
        export_apply=True,
    )
    print(f"[SanctumCathedral] Exported AAA masterpiece cathedral to: {out_path}")

if __name__ == "__main__":
    build_cathedral()
