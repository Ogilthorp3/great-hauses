#!/usr/bin/env blender --python
"""
make_glyph_rings.py — Great Houses: TYPE-GLYPH RINGS (piece readability layer).

Run headless:
  /Applications/Blender.app/Contents/MacOS/Blender -b --python \
      tools/props/make_glyph_rings.py -- <out_dir>

Outputs (one per piece type):
  glyph_ring_pawn.glb    ... glyph_ring_king.glb

Each ring is a flat two-step stone disc that sits UNDER a piece, plus a
small MEDALLION at the ring's front lip tilted toward the gameplay camera,
carrying the chess glyph for the piece TYPE (the filled/"black" codepoints
U+265A-U+265F) as real extruded geometry — engraved look, muted-gold
emissive material so it reads at rest and can be brightened on selection
(PieceView.set_selected duplicates the material and bumps emission energy).
The glyph sits on the front lip, NOT the disc center: a centered glyph is
hidden by the piece standing on it (found the hard way in preview shots).

Conventions (matches make_crown.py / make_throne.py):
  - origin center-bottom, +Z up in Blender -> exported Y-up for Godot
  - glyph top edge points Blender -Y -> Godot +Z, so from the default
    gameplay camera (behind the player at -Z, looking +Z) the glyph reads
    upright; PieceView counter-rotates the ring against the piece's home yaw
  - flat shading, low-poly; text curve resolution clamped + limited
    dissolve to keep each ring around/under ~1k tris
  - deterministic: no RNG at all here; text geometry is deterministic

Materials (names are runtime API — PieceView looks them up):
  glyphring_stone  — dark ring stone
  glyphring_inlay  — slightly darker recessed inlay disc
  glyphring_glyph  — muted gold, low emissive (brightened on selection)

Font: the glyphs need a font that covers the chess block. Candidates are
tried in order; a candidate is accepted only if the converted mesh has
vertices (a missing glyph converts to an empty mesh).

Blender 4.0.2 bpy API.
"""
import bpy
import math
import os
import sys

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_DIR = argv[0] if argv else "."

# ---------------------------------------------------------------- parameters
RING_R = 0.300        # outer disc radius (fits a 1.0 board tile with margin)
RING_H = 0.012        # outer disc height
RING_SEG = 28
INLAY_R = 0.255       # recessed inlay disc
INLAY_H = 0.0085      # lower than the ring rim -> engraved step
INLAY_SEG = 24
MEDAL_R = 0.130        # front medallion (the glyph plate)
MEDAL_H = 0.012
MEDAL_Y = 0.215        # medallion center: the ring's front lip (Blender +Y
                       # = Godot -Z = toward the default gameplay camera)
MEDAL_TILT = -24.0     # degrees about X: face leans toward the camera
GLYPH_MAX_DIM = 0.185  # glyph scaled to fit the medallion
GLYPH_EXTRUDE = 0.0050

GLYPHS = {
    "pawn":   "♟",  # black pawn
    "knight": "♞",
    "bishop": "♝",
    "rook":   "♜",
    "queen":  "♛",
    "king":   "♚",
}

FONT_CANDIDATES = [
    "/System/Library/Fonts/Apple Symbols.ttf",
    "/Library/Fonts/Arial Unicode.ttf",
]
# Blender's bundled Noto Symbols 2 covers the chess block too (any version dir).
for _res in sorted(__import__("glob").glob(
        "/Applications/Blender.app/Contents/Resources/*/datafiles/fonts/NotoSansSymbols2-Regular.woff2")):
    FONT_CANDIDATES.append(_res)


def make_material(name, base, metallic, rough, emission=None, emission_strength=0.0):
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


def tri_count(objs):
    deps = bpy.context.evaluated_depsgraph_get()
    total = 0
    for ob in objs:
        me = ob.evaluated_get(deps).to_mesh()
        me.calc_loop_triangles()
        total += len(me.loop_triangles)
        ob.evaluated_get(deps).to_mesh_clear()
    return total


def flat_shade(ob):
    for p in ob.data.polygons:
        p.use_smooth = False


def build_glyph_mesh(char, font):
    """Text -> mesh, centered at origin, scaled to GLYPH_MAX_DIM, base z=0.
    Returns the object, or None if the font has no outline for the char."""
    bpy.ops.object.text_add(location=(0, 0, 0))
    txt = bpy.context.active_object
    txt.data.body = char
    txt.data.font = font
    txt.data.extrude = GLYPH_EXTRUDE
    txt.data.resolution_u = 4          # keep the curve low-poly
    txt.data.size = 1.0
    bpy.ops.object.convert(target='MESH')
    ob = bpy.context.active_object
    if len(ob.data.vertices) == 0:
        bpy.data.objects.remove(ob, do_unlink=True)
        return None
    # tidy: merge + limited dissolve to cut the fill fan triangle count
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.remove_doubles(threshold=0.0005)
    bpy.ops.mesh.dissolve_limited(angle_limit=math.radians(3.0))
    bpy.ops.object.mode_set(mode='OBJECT')
    # glyph top toward Blender -Y (-> Godot +Z: upright from the game camera)
    ob.rotation_euler = (0.0, 0.0, math.pi)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    # center + fit
    xs = [v.co.x for v in ob.data.vertices]
    ys = [v.co.y for v in ob.data.vertices]
    zs = [v.co.z for v in ob.data.vertices]
    w, d = max(xs) - min(xs), max(ys) - min(ys)
    s = GLYPH_MAX_DIM / max(w, d)
    cx, cy = (max(xs) + min(xs)) / 2.0, (max(ys) + min(ys)) / 2.0
    for v in ob.data.vertices:
        v.co.x = (v.co.x - cx) * s
        v.co.y = (v.co.y - cy) * s
        v.co.z = (v.co.z - min(zs)) * s
    return ob


def pick_font(char):
    for path in FONT_CANDIDATES:
        if not os.path.exists(path):
            continue
        font = bpy.data.fonts.load(path)
        probe = build_glyph_mesh(char, font)
        if probe is not None:
            bpy.data.objects.remove(probe, do_unlink=True)
            return font
    raise RuntimeError("no candidate font renders chess glyph %r" % char)


for type_name, char in GLYPHS.items():
    bpy.ops.wm.read_factory_settings(use_empty=True)

    mat_stone = make_material("glyphring_stone", (0.042, 0.037, 0.031), 0.15, 0.84)
    mat_inlay = make_material("glyphring_inlay", (0.022, 0.020, 0.017), 0.10, 0.9)
    mat_glyph = make_material("glyphring_glyph", (0.34, 0.25, 0.10), 0.65, 0.42,
                              emission=(0.78, 0.60, 0.28), emission_strength=0.85)
    mat_medal = make_material("glyphring_medal", (0.10, 0.088, 0.072), 0.3, 0.7)

    bpy.ops.mesh.primitive_cylinder_add(
        vertices=RING_SEG, radius=RING_R, depth=RING_H,
        location=(0, 0, RING_H / 2))
    ring = bpy.context.active_object
    ring.name = "RingBase"
    ring.data.materials.append(mat_stone)
    flat_shade(ring)

    bpy.ops.mesh.primitive_cylinder_add(
        vertices=INLAY_SEG, radius=INLAY_R, depth=INLAY_H,
        location=(0, 0, RING_H + INLAY_H / 2 - 0.006))
    inlay = bpy.context.active_object
    inlay.name = "RingInlay"
    inlay.data.materials.append(mat_inlay)
    flat_shade(inlay)

    # front medallion: a tilted plate at the ring's lip carrying the glyph
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=20, radius=MEDAL_R, depth=MEDAL_H, location=(0, 0, MEDAL_H / 2))
    medal = bpy.context.active_object
    medal.name = "Medallion"
    medal.data.materials.append(mat_medal)
    flat_shade(medal)

    font = pick_font(char)
    glyph = build_glyph_mesh(char, font)
    if glyph is None:
        raise RuntimeError("glyph %r lost its outline after font probe" % char)
    glyph.name = "Glyph"
    glyph.location = (0, 0, MEDAL_H - 0.0015)   # proud of the medallion face
    glyph.data.materials.append(mat_glyph)
    flat_shade(glyph)

    # join glyph onto its plate, then tilt the plate toward the camera and
    # park it on the ring's front lip
    for ob in (glyph, medal):
        ob.select_set(True)
    bpy.context.view_layer.objects.active = medal
    bpy.ops.object.join()
    medal = bpy.context.active_object
    medal.rotation_euler = (math.radians(MEDAL_TILT), 0.0, 0.0)
    medal.location = (0.0, MEDAL_Y, RING_H + 0.004)

    for ob in (ring, inlay, medal):
        ob.select_set(True)
    bpy.context.view_layer.objects.active = ring
    bpy.ops.object.join()
    disc = bpy.context.active_object
    disc.name = "GlyphRing_%s" % type_name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    n = tri_count([disc])
    path = os.path.join(OUT_DIR, "glyph_ring_%s.glb" % type_name)
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(
        filepath=path, export_format='GLB', export_apply=True, export_yup=True)
    print("[glyph_ring] %-6s %4d tris -> %s" % (type_name, n, path))
