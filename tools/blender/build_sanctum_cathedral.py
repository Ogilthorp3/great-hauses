"""
Procedural Gothic Cathedral Generator for Great Hauses Chess.
Builds the Sanctum Rust Gothic Cathedral:
- Soaring 36m ribbed vault ceiling (clearing all upstairs & top-down camera views)
- Clustered gothic stone pillars with molded capitals
- Pointed arches and criss-crossing stone rib groins
- Upper triforium galleries with gothic arcaded railings
- 12-petal Rose Stained Glass Window with glowing emissive glass & stone tracery
- High Gothic lancet clerestory windows along the nave
- Flagstone cathedral floor with elevated sanctuary dais
- Wrought iron hanging wheel chandeliers and torch sconces
"""

import bpy
import bmesh
import math
from mathutils import Vector, Matrix

def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def create_material(name, diffuse_color, roughness=0.7, metallic=0.0, emission_color=None, emission_strength=1.0):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()
    
    output = nodes.new(type='ShaderNodeOutputMaterial')
    principled = nodes.new(type='ShaderNodeBsdfPrincipled')
    
    principled.inputs['Base Color'].default_value = diffuse_color
    principled.inputs['Roughness'].default_value = roughness
    principled.inputs['Metallic'].default_value = metallic
    
    if emission_color:
        principled.inputs['Emission Color'].default_value = emission_color
        principled.inputs['Emission Strength'].default_value = emission_strength
        
    links.new(principled.outputs['BSDF'], output.inputs['Surface'])
    return mat

def build_cathedral():
    clear_scene()
    
    # ── Materials ─────────────────────────────────────────────────────────────
    mat_stone = create_material("Stone_Cathedral", (0.38, 0.35, 0.32, 1.0), roughness=0.82, metallic=0.05)
    mat_stone_dark = create_material("Stone_Dark_Trim", (0.24, 0.22, 0.20, 1.0), roughness=0.75, metallic=0.1)
    mat_floor = create_material("Stone_Floor", (0.28, 0.26, 0.25, 1.0), roughness=0.55, metallic=0.1)
    mat_iron = create_material("Wrought_Iron", (0.12, 0.12, 0.13, 1.0), roughness=0.45, metallic=0.85)
    mat_gold = create_material("Cathedral_Gold", (0.85, 0.68, 0.25, 1.0), roughness=0.3, metallic=0.9)
    mat_wood = create_material("Dark_Oak", (0.18, 0.12, 0.08, 1.0), roughness=0.65, metallic=0.0)
    
    # Stained Glass Emissives
    mat_rose_glass = create_material("Rose_Stained_Glass", (0.8, 0.2, 0.15, 1.0), roughness=0.1, metallic=0.0,
                                     emission_color=(0.95, 0.45, 0.2, 1.0), emission_strength=4.5)
    mat_lancet_glass = create_material("Lancet_Stained_Glass", (0.2, 0.45, 0.85, 1.0), roughness=0.1, metallic=0.0,
                                       emission_color=(0.3, 0.6, 0.95, 1.0), emission_strength=3.5)
    mat_candle = create_material("Candle_Flame", (1.0, 0.8, 0.3, 1.0), roughness=0.1, metallic=0.0,
                                 emission_color=(1.0, 0.75, 0.25, 1.0), emission_strength=8.0)

    # ── Cathedral Dimensions ──────────────────────────────────────────────────
    NAVE_HALF_W = 12.0      # Nave width = 24m (-12 to +12)
    AISLE_HALF_W = 20.0     # Side aisle outer wall = 40m wide
    LENGTH_HALF = 30.0      # Cathedral length = 60m (-30 to +30)
    PILLAR_H = 18.0         # Pillar height to springline
    VAULT_APEX_Y = 36.0     # Main nave vault apex height (36m!)
    TRIFORIUM_Y = 14.0      # Upper balcony gallery height
    AISLE_VAULT_Y = 16.0    # Side aisle vault height
    FLOOR_Y = -0.3          # Plinth level

    # ── 1. Floor & Sanctuary Dais ─────────────────────────────────────────────
    # Main floor
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, FLOOR_Y - 0.25, 0))
    floor_obj = bpy.context.active_object
    floor_obj.name = "Cathedral_Floor"
    floor_obj.scale = (AISLE_HALF_W * 2 + 4.0, 0.5, LENGTH_HALF * 2 + 4.0)
    bpy.ops.object.transform_apply(scale=True)
    floor_obj.data.materials.append(mat_floor)

    # Elevated Sanctuary Dais at liturgical East (far end, z > 16)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, FLOOR_Y + 0.2, 22.0))
    dais_obj = bpy.context.active_object
    dais_obj.name = "Sanctuary_Dais"
    dais_obj.scale = (NAVE_HALF_W * 1.5, 0.4, 14.0)
    bpy.ops.object.transform_apply(scale=True)
    dais_obj.data.materials.append(mat_stone_dark)

    # Dais steps
    for step in range(3):
        step_y = FLOOR_Y + step * 0.15
        step_z = 14.5 - step * 0.6
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, step_y, step_z))
        st = bpy.context.active_object
        st.name = f"Dais_Step_{step}"
        st.scale = (NAVE_HALF_W * 1.6, 0.15, 0.8)
        bpy.ops.object.transform_apply(scale=True)
        st.data.materials.append(mat_stone)

    # ── 2. Clustered Gothic Nave Piers (Pillars) ──────────────────────────────
    # 7 bays along Z from z = -24 to z = +24 (stride = 8m)
    bay_zs = [-24.0, -16.0, -8.0, 0.0, 8.0, 16.0, 24.0]
    
    pillars_mesh = bpy.data.meshes.new("Nave_Pillars_Mesh")
    bm_pillars = bmesh.new()

    for z in bay_zs:
        for x_sign in [-1, 1]:
            px = x_sign * NAVE_HALF_W
            pz = z
            
            # Central pier column
            mat_col = Matrix.Translation((px, FLOOR_Y + PILLAR_H * 0.5, pz))
            bmesh.ops.create_cube(bm_pillars, size=1.0, matrix=mat_col @ Matrix.Diagonal((2.2, PILLAR_H, 2.2, 1.0)))
            
            # 4 Clustered shafts attached to pier
            shaft_offsets = [(1.3, 0), (-1.3, 0), (0, 1.3), (0, -1.3)]
            for so_x, so_z in shaft_offsets:
                mat_shaft = Matrix.Translation((px + so_x, FLOOR_Y + PILLAR_H * 0.5, pz + so_z))
                bmesh.ops.create_cone(bm_pillars, cap_ends=True, cap_tris=False, segments=12,
                                      radius1=0.45, radius2=0.45, depth=PILLAR_H, matrix=mat_shaft)
            
            # Molded Base
            mat_base = Matrix.Translation((px, FLOOR_Y + 0.6, pz))
            bmesh.ops.create_cube(bm_pillars, size=1.0, matrix=mat_base @ Matrix.Diagonal((3.4, 1.2, 3.4, 1.0)))
            
            # Ornate Capital at springline (y = PILLAR_H)
            mat_cap = Matrix.Translation((px, FLOOR_Y + PILLAR_H, pz))
            bmesh.ops.create_cone(bm_pillars, cap_ends=True, segments=16,
                                  radius1=1.8, radius2=2.4, depth=1.5, matrix=mat_cap)

    bm_pillars.to_mesh(pillars_mesh)
    bm_pillars.free()
    pillars_obj = bpy.data.objects.new("Cathedral_Nave_Pillars", pillars_mesh)
    bpy.context.collection.objects.link(pillars_obj)
    pillars_obj.data.materials.append(mat_stone)

    # ── 3. Soaring Ribbed Vault Ceiling & Pointed Transverse Arches ───────────
    vault_mesh = bpy.data.meshes.new("Cathedral_Vaults_Mesh")
    bm_vault = bmesh.new()

    # Transverse Pointed Arches across Nave
    for z in bay_zs:
        # Create pointed arch spline
        segments = 24
        for i in range(segments):
            t1 = i / segments
            t2 = (i + 1) / segments
            
            angle1 = t1 * math.pi
            angle2 = t2 * math.pi
            
            h1 = math.sin(angle1) ** 0.85
            h2 = math.sin(angle2) ** 0.85
            
            x1 = -NAVE_HALF_W + t1 * (2 * NAVE_HALF_W)
            y1 = FLOOR_Y + PILLAR_H + h1 * (VAULT_APEX_Y - PILLAR_H)
            x2 = -NAVE_HALF_W + t2 * (2 * NAVE_HALF_W)
            y2 = FLOOR_Y + PILLAR_H + h2 * (VAULT_APEX_Y - PILLAR_H)
            
            mid_x = (x1 + x2) * 0.5
            mid_y = (y1 + y2) * 0.5
            dx = x2 - x1
            dy = y2 - y1
            length = math.hypot(dx, dy)
            rot = math.atan2(dy, dx)
            
            mat_arch = Matrix.Translation((mid_x, mid_y, z)) @ Matrix.Rotation(rot, 4, 'Z')
            bmesh.ops.create_cube(bm_vault, size=1.0, matrix=mat_arch @ Matrix.Diagonal((length, 0.9, 1.2, 1.0)))

    # Longitudinal Spine Ribs & Diagonal Cross Ribs between bays
    for b_idx in range(len(bay_zs) - 1):
        z_start = bay_zs[b_idx]
        z_end = bay_zs[b_idx + 1]
        z_mid = (z_start + z_end) * 0.5
        
        # Longitudinal Apex Spine Rib
        mat_spine = Matrix.Translation((0, FLOOR_Y + VAULT_APEX_Y, z_mid))
        bmesh.ops.create_cube(bm_vault, size=1.0, matrix=mat_spine @ Matrix.Diagonal((1.2, 0.8, (z_end - z_start), 1.0)))
        
        # Central Carved Boss at vault intersection
        mat_boss = Matrix.Translation((0, FLOOR_Y + VAULT_APEX_Y - 0.3, z_mid))
        bmesh.ops.create_cone(bm_vault, cap_ends=True, segments=16, radius1=1.4, radius2=0.2, depth=1.0, matrix=mat_boss)
        
        # Diagonal Groin Ribs (X-shape)
        for diag in [1, -1]:
            seg_count = 20
            for s in range(seg_count):
                st1 = s / seg_count
                st2 = (s + 1) / seg_count
                
                ang1 = st1 * math.pi
                ang2 = st2 * math.pi
                
                h1 = math.sin(ang1) ** 0.8
                h2 = math.sin(ang2) ** 0.8
                
                px1 = -NAVE_HALF_W + st1 * (2 * NAVE_HALF_W)
                pz1 = z_start if diag == 1 else z_end
                pz1_target = z_end if diag == 1 else z_start
                pz1 = pz1 + st1 * (pz1_target - pz1)
                py1 = FLOOR_Y + PILLAR_H + h1 * (VAULT_APEX_Y - PILLAR_H)
                
                px2 = -NAVE_HALF_W + st2 * (2 * NAVE_HALF_W)
                pz2 = z_start if diag == 1 else z_end
                pz2_target = z_end if diag == 1 else z_start
                pz2 = pz2 + st2 * (pz2_target - pz2)
                py2 = FLOOR_Y + PILLAR_H + h2 * (VAULT_APEX_Y - PILLAR_H)
                
                mid_x = (px1 + px2) * 0.5
                mid_y = (py1 + py2) * 0.5
                mid_z = (pz1 + pz2) * 0.5
                
                d_vec = Vector((px2 - px1, py2 - py1, pz2 - pz1))
                l = d_vec.length
                if l > 0.001:
                    d_norm = d_vec.normalized()
                    q = Vector((1, 0, 0)).rotation_difference(d_norm)
                    mat_diag = Matrix.Translation((mid_x, mid_y, mid_z)) @ q.to_matrix().to_4x4()
                    bmesh.ops.create_cube(bm_vault, size=1.0, matrix=mat_diag @ Matrix.Diagonal((l, 0.6, 0.6, 1.0)))

        # Vault Web Infill Shell (Roof enclosure)
        mat_roof_l = Matrix.Translation((-NAVE_HALF_W * 0.5, FLOOR_Y + (PILLAR_H + VAULT_APEX_Y) * 0.5 + 0.8, z_mid)) @ Matrix.Rotation(math.radians(-32), 4, 'Z')
        bmesh.ops.create_cube(bm_vault, size=1.0, matrix=mat_roof_l @ Matrix.Diagonal((NAVE_HALF_W * 1.25, 0.4, (z_end - z_start), 1.0)))
        
        mat_roof_r = Matrix.Translation((NAVE_HALF_W * 0.5, FLOOR_Y + (PILLAR_H + VAULT_APEX_Y) * 0.5 + 0.8, z_mid)) @ Matrix.Rotation(math.radians(32), 4, 'Z')
        bmesh.ops.create_cube(bm_vault, size=1.0, matrix=mat_roof_r @ Matrix.Diagonal((NAVE_HALF_W * 1.25, 0.4, (z_end - z_start), 1.0)))

    bm_vault.to_mesh(vault_mesh)
    bm_vault.free()
    vault_obj = bpy.data.objects.new("Cathedral_Vaults", vault_mesh)
    bpy.context.collection.objects.link(vault_obj)
    vault_obj.data.materials.append(mat_stone_dark)

    # ── 4. Upper Triforium Galleries & Upstairs Walkways ──────────────────────
    gallery_mesh = bpy.data.meshes.new("Cathedral_Gallery_Mesh")
    bm_gallery = bmesh.new()

    for x_sign in [-1, 1]:
        gx = x_sign * (NAVE_HALF_W + 3.5)
        
        # Gallery Walkway Floor Slab (14m up, 7m wide, runs full 60m length)
        mat_gfloor = Matrix.Translation((gx, FLOOR_Y + TRIFORIUM_Y, 0))
        bmesh.ops.create_cube(bm_gallery, size=1.0, matrix=mat_gfloor @ Matrix.Diagonal((7.0, 0.6, LENGTH_HALF * 2, 1.0)))
        
        # Gothic Arcaded Balustrade / Railing facing the nave
        rail_x = x_sign * (NAVE_HALF_W + 0.2)
        mat_rail = Matrix.Translation((rail_x, FLOOR_Y + TRIFORIUM_Y + 0.8, 0))
        bmesh.ops.create_cube(bm_gallery, size=1.0, matrix=mat_rail @ Matrix.Diagonal((0.4, 1.4, LENGTH_HALF * 2, 1.0)))
        
        # Balustrade Top Handrail
        mat_top = Matrix.Translation((rail_x, FLOOR_Y + TRIFORIUM_Y + 1.6, 0))
        bmesh.ops.create_cube(bm_gallery, size=1.0, matrix=mat_top @ Matrix.Diagonal((0.7, 0.3, LENGTH_HALF * 2, 1.0)))
        
        # Cantilevered Stone Corbels supporting the gallery
        for z in bay_zs:
            mat_corbel = Matrix.Translation((rail_x + x_sign * 1.2, FLOOR_Y + TRIFORIUM_Y - 1.2, z))
            bmesh.ops.create_cone(bm_gallery, cap_ends=True, segments=8, radius1=1.2, radius2=0.2, depth=2.4, matrix=mat_corbel)

    bm_gallery.to_mesh(gallery_mesh)
    bm_gallery.free()
    gallery_obj = bpy.data.objects.new("Cathedral_Galleries", gallery_mesh)
    bpy.context.collection.objects.link(gallery_obj)
    gallery_obj.data.materials.append(mat_stone)

    # ── 5. Cathedral Outer Walls & Clerestory Lancets ─────────────────────────
    walls_mesh = bpy.data.meshes.new("Cathedral_Walls_Mesh")
    bm_walls = bmesh.new()

    # Outer Side Walls (at X = +/- AISLE_HALF_W, height = 24m)
    for x_sign in [-1, 1]:
        wx = x_sign * AISLE_HALF_W
        mat_wall = Matrix.Translation((wx, FLOOR_Y + 12.0, 0))
        bmesh.ops.create_cube(bm_walls, size=1.0, matrix=mat_wall @ Matrix.Diagonal((1.8, 24.0, LENGTH_HALF * 2 + 2.0, 1.0)))
        
        # Buttresses outside the wall
        for z in bay_zs:
            bx = wx + x_sign * 2.0
            mat_butt = Matrix.Translation((bx, FLOOR_Y + 10.0, z))
            bmesh.ops.create_cube(bm_walls, size=1.0, matrix=mat_butt @ Matrix.Diagonal((2.5, 20.0, 2.0, 1.0)))

    # Far End Apse Wall (Z = +LENGTH_HALF)
    mat_far_wall = Matrix.Translation((0, FLOOR_Y + 18.0, LENGTH_HALF))
    bmesh.ops.create_cube(bm_walls, size=1.0, matrix=mat_far_wall @ Matrix.Diagonal((AISLE_HALF_W * 2 + 2.0, 36.0, 2.0, 1.0)))

    # Near End Entrance Wall (Z = -LENGTH_HALF)
    mat_near_wall = Matrix.Translation((0, FLOOR_Y + 18.0, -LENGTH_HALF))
    bmesh.ops.create_cube(bm_walls, size=1.0, matrix=mat_near_wall @ Matrix.Diagonal((AISLE_HALF_W * 2 + 2.0, 36.0, 2.0, 1.0)))

    bm_walls.to_mesh(walls_mesh)
    bm_walls.free()
    walls_obj = bpy.data.objects.new("Cathedral_Walls", walls_mesh)
    bpy.context.collection.objects.link(walls_obj)
    walls_obj.data.materials.append(mat_stone)

    # ── 6. Great Gothic Rose Window (Far End Z = +29.0m) ──────────────────────
    ROSE_Z = LENGTH_HALF - 0.8
    ROSE_Y = FLOOR_Y + 22.0
    
    bpy.ops.mesh.primitive_cylinder_add(radius=5.5, depth=0.3, vertices=32, location=(0, ROSE_Y, ROSE_Z), rotation=(math.radians(90), 0, 0))
    rose_glass_obj = bpy.context.active_object
    rose_glass_obj.name = "Rose_Window_Stained_Glass"
    rose_glass_obj.data.materials.append(mat_rose_glass)

    # Rose Window Stone Tracery & Petals
    rose_tracery_mesh = bpy.data.meshes.new("Rose_Tracery_Mesh")
    bm_rose = bmesh.new()

    # Outer Stone Ring Frame
    mat_ring = Matrix.Translation((0, ROSE_Y, ROSE_Z + 0.1)) @ Matrix.Rotation(math.radians(90), 4, 'X')
    bmesh.ops.create_cone(bm_rose, cap_ends=False, segments=32, radius1=6.0, radius2=6.0, depth=0.6, matrix=mat_ring)
    
    # 12 Gothic Petal Spokes
    for p in range(12):
        ang = p * (math.pi * 2 / 12)
        mat_spoke = Matrix.Translation((0, ROSE_Y, ROSE_Z + 0.15)) @ Matrix.Rotation(ang, 4, 'Z') @ Matrix.Translation((2.7, 0, 0))
        bmesh.ops.create_cube(bm_rose, size=1.0, matrix=mat_spoke @ Matrix.Diagonal((5.2, 0.4, 0.4, 1.0)))
        
        # Outer petal cusps
        cx = math.cos(ang) * 4.2
        cy = math.sin(ang) * 4.2
        mat_cusp = Matrix.Translation((cx, ROSE_Y + cy, ROSE_Z + 0.2)) @ Matrix.Rotation(math.radians(90), 4, 'X')
        bmesh.ops.create_cone(bm_rose, cap_ends=True, segments=12, radius1=0.9, radius2=0.9, depth=0.35, matrix=mat_cusp)

    # Central Rose Boss
    mat_cboss = Matrix.Translation((0, ROSE_Y, ROSE_Z + 0.25)) @ Matrix.Rotation(math.radians(90), 4, 'X')
    bmesh.ops.create_cone(bm_rose, cap_ends=True, segments=16, radius1=1.2, radius2=1.2, depth=0.5, matrix=mat_cboss)

    bm_rose.to_mesh(rose_tracery_mesh)
    bm_rose.free()
    rose_tracery_obj = bpy.data.objects.new("Rose_Window_Tracery", rose_tracery_mesh)
    bpy.context.collection.objects.link(rose_tracery_obj)
    rose_tracery_obj.data.materials.append(mat_gold)

    # ── 7. Clerestory Lancet Stained Glass Windows ────────────────────────────
    lancets_mesh = bpy.data.meshes.new("Lancets_Glass_Mesh")
    bm_lancets = bmesh.new()

    for b_idx in range(len(bay_zs) - 1):
        z_mid = (bay_zs[b_idx] + bay_zs[b_idx + 1]) * 0.5
        
        for x_sign in [-1, 1]:
            lx = x_sign * (NAVE_HALF_W - 0.1)
            ly = FLOOR_Y + 22.0
            
            # Paired lancets in each clerestory bay
            for z_off in [-1.8, 1.8]:
                mat_lancet = Matrix.Translation((lx, ly, z_mid + z_off))
                bmesh.ops.create_cube(bm_lancets, size=1.0, matrix=mat_lancet @ Matrix.Diagonal((0.2, 8.0, 1.8, 1.0)))

    bm_lancets.to_mesh(lancets_mesh)
    bm_lancets.free()
    lancets_obj = bpy.data.objects.new("Clerestory_Lancets", lancets_mesh)
    bpy.context.collection.objects.link(lancets_obj)
    lancets_obj.data.materials.append(mat_lancet_glass)

    # ── 8. Hanging Wrought Iron Wheel Chandeliers ─────────────────────────────
    chand_mesh = bpy.data.meshes.new("Chandeliers_Mesh")
    bm_chand = bmesh.new()

    for z in [-16.0, 0.0, 16.0]:
        cy = FLOOR_Y + 16.0
        
        # Heavy Iron Wheel Rim (3.6m diameter)
        mat_wheel = Matrix.Translation((0, cy, z))
        bmesh.ops.create_cone(bm_chand, cap_ends=False, segments=24, radius1=2.8, radius2=2.8, depth=0.3, matrix=mat_wheel)
        
        # 6 Iron Spokes
        for s in range(6):
            ang = s * (math.pi * 2 / 6)
            mat_spoke = Matrix.Translation((0, cy, z)) @ Matrix.Rotation(ang, 4, 'Y') @ Matrix.Translation((1.4, 0, 0))
            bmesh.ops.create_cube(bm_chand, size=1.0, matrix=mat_spoke @ Matrix.Diagonal((2.8, 0.15, 0.15, 1.0)))
            
            # Candle holder cup & flame
            cx = math.cos(ang) * 2.8
            cz = z + math.sin(ang) * 2.8
            mat_cup = Matrix.Translation((cx, cy + 0.3, cz))
            bmesh.ops.create_cone(bm_chand, cap_ends=True, segments=8, radius1=0.2, radius2=0.25, depth=0.4, matrix=mat_cup)

        # Suspension Chains up to vault apex
        chain_h = (FLOOR_Y + VAULT_APEX_Y) - cy
        for hang_ang in [0, math.pi * 2 / 3, math.pi * 4 / 3]:
            hx = math.cos(hang_ang) * 2.6
            hz = z + math.sin(hang_ang) * 2.6
            mat_chain = Matrix.Translation((hx * 0.5, cy + chain_h * 0.5, hz - (hz - z) * 0.5))
            bmesh.ops.create_cube(bm_chand, size=1.0, matrix=mat_chain @ Matrix.Diagonal((0.1, chain_h, 0.1, 1.0)))

    bm_chand.to_mesh(chand_mesh)
    bm_chand.free()
    chand_obj = bpy.data.objects.new("Cathedral_Chandeliers", chand_mesh)
    bpy.context.collection.objects.link(chand_obj)
    chand_obj.data.materials.append(mat_iron)

    print("Sanctum Rust Gothic Cathedral geometry generated successfully!")

def export_glb(filepath):
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format='GLB',
        use_selection=False,
        export_apply=True,
        export_materials='EXPORT',
        export_yup=True
    )
    print(f"Exported Cathedral GLB to: {filepath}")

if __name__ == "__main__":
    import sys
    out_path = "/Users/bert/Projects/great-hauses-core/assets/environment/sanctum_cathedral.glb"
    for arg in sys.argv:
        if arg.endswith(".glb"):
            out_path = arg
            break
    
    build_cathedral()
    export_glb(out_path)
