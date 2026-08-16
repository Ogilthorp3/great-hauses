import bpy
import bmesh
import math
import os

def create_triforce_crest(output_path):
    # Clear default scene
    bpy.ops.wm.read_factory_settings(use_empty=True)

    # Create root collection/object
    mesh = bpy.data.meshes.new("Crest_Hyrule_Mesh")
    obj = bpy.data.objects.new("Crest_Hyrule", mesh)
    bpy.context.scene.collection.objects.link(obj)

    bm = bmesh.new()

    # Dimensions for Triforce triangles
    h_tri = 0.45
    w_tri = h_tri * (2.0 / math.sqrt(3.0))
    depth = 0.08
    bevel = 0.02

    # Helper to make a 3D prism triangle
    def add_triangle_prism(center_x, center_y, size_w, size_h, z_depth):
        # 3 vertices for top, bottom-left, bottom-right
        v_top = (center_x, center_y + size_h * (2.0 / 3.0), 0)
        v_bl = (center_x - size_w * 0.5, center_y - size_h * (1.0 / 3.0), 0)
        v_br = (center_x + size_w * 0.5, center_y - size_h * (1.0 / 3.0), 0)

        # Front and back face vertices
        v_f_top = bm.verts.new((v_top[0], v_top[1], z_depth * 0.5))
        v_f_bl = bm.verts.new((v_bl[0], v_bl[1], z_depth * 0.5))
        v_f_br = bm.verts.new((v_br[0], v_br[1], z_depth * 0.5))

        v_b_top = bm.verts.new((v_top[0], v_top[1], -z_depth * 0.5))
        v_b_bl = bm.verts.new((v_bl[0], v_bl[1], -z_depth * 0.5))
        v_b_br = bm.verts.new((v_br[0], v_br[1], -z_depth * 0.5))

        # Faces
        bm.faces.new((v_f_top, v_f_bl, v_f_br))
        bm.faces.new((v_b_top, v_b_br, v_b_bl))
        bm.faces.new((v_f_top, v_f_br, v_b_br, v_b_top))
        bm.faces.new((v_f_br, v_f_bl, v_b_bl, v_b_br))
        bm.faces.new((v_f_bl, v_f_top, v_b_top, v_b_bl))

    sub_h = h_tri * 0.5
    sub_w = w_tri * 0.5

    # 1. Top triangle
    add_triangle_prism(0.0, sub_h * 0.5, sub_w, sub_h, depth)
    # 2. Bottom-left triangle
    add_triangle_prism(-sub_w * 0.5, -sub_h * 0.5, sub_w, sub_h, depth)
    # 3. Bottom-right triangle
    add_triangle_prism(sub_w * 0.5, -sub_h * 0.5, sub_w, sub_h, depth)

    bm.to_mesh(mesh)
    bm.free()

    # Material: Gold Metallic
    mat = bpy.data.materials.new(name="Gold_Triforce")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (0.95, 0.78, 0.15, 1.0)
        bsdf.inputs["Metallic"].default_value = 0.95
        bsdf.inputs["Roughness"].default_value = 0.22
    obj.data.materials.append(mat)

    # Export to GLB
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=output_path,
        export_format='GLB',
        use_selection=False,
        export_apply=True
    )
    print("Exported 3D Triforce Crest ->", output_path)

if __name__ == "__main__":
    out = "/Users/bert/Projects/great-hauses-core/assets/custom-props/crests/crest_hyrule.glb"
    create_triforce_crest(out)
