#!/usr/bin/env blender --python
"""
make_pawn_helms.py — Great Hauses: nine per-haus PAWN half-helms (HAUS layer).

Run headless:
  /Applications/Blender.app/Contents/MacOS/Blender -b --python \
      tools/props/make_pawn_helms.py -- <out_dir>

Outputs pawn_helm_<house_id>.glb for each of the nine hauses, plus
pawn_helm_tidegrip_charred.glb (an optional zero-code Drowned-Legion variant —
identical geometry, pre-charred materials; the preferred convention is the
runtime darken documented in the assets README).

WHY THESE ARE NOT CRESTS (ISSUES.md #3)
---------------------------------------
The royal crest (tools/props/make_crests.py, <=600 tris) sits ABOVE the skull
and exists to build a tall, proud silhouette for knight/queen/king. A PAWN helm
does the opposite job: it WRAPS the skull, adds almost nothing to the
silhouette, and carries only a small haus motif. A player must read "pawn"
first and "which haus" second. Hard rules enforced here:

  * <= 250 tris per helm (TRI_BUDGET; the decimate fallback is a guard, not a
    plan — every haus is authored under budget)
  * nothing rises more than MOTIF_CEILING above the skull crown — a sixth of a
    head, against the crests' half-a-head. Asserted at export.
  * no tall spikes, no ring that could read as a circlet, no fan silhouettes

AUTHORING SPACE (same convention as make_crests.py)
---------------------------------------------------
KayKit `Rig_Medium` HEAD-BONE space. Origin = the SKULL-TOP CONTACT POINT of
the ADVENTURER cast, +Z up (Blender) -> Y-up GLB, front faces Blender -Y ->
Godot +Z. Runtime: rigid BoneAttachment3D on the `head` bone (the crown-attach
pattern in piece_assets/piece_view), attach position (0, 0.945, 0), scale 1.0
— for ALL NINE, Tidegrip included.

Tidegrip's pawn is a Skeleton_Minion, whose skull is narrower and
proportionally deeper than the adventurer skull, and whose crown sits 0.020
lower. Its helm is therefore built against the SKELETON profile and shifted by
that 0.020 at export, so the wiring agent needs exactly ONE mount transform and
no per-cast branch.

THE SHELL IS BUILT FROM A MEASURED SLICE PROFILE, NOT AN AABB
--------------------------------------------------------------
SKULL_SLICES below is real measured data from
great-houses-assets/pawn-helms/tools/measure_head.py: for horizontal bands
below the crown, the max |x| and the y-extent of the head mesh in bone space.
The first cut of this script fitted one ellipsoid to the head's AABB and the
result was a helm that was baggy on the Barbarian (the AABB half-width 0.543 is
the BEARD, not the cranium — which is 0.45) and that sliced straight through
the skeleton's cranium (whose widest point is not where the ellipsoid's was).
A profile-driven shell cannot make either mistake: at every ring height it is
the measured skull radius plus CLEARANCE, made monotone from the crown down so
the cap never cuts inward.

The glTF rest chain root->hips->spine->chest->head carries identity rotations
(verified by dumping the GLB node transforms), so Blender armature space
translated by the bone rest position IS Godot bone space — which is why the
crest convention's 1.04 lands exactly on the measured Knight/Ranger skull tops.

Blender 4.0.2 bpy API.
"""
import bmesh
import bpy
import math
import os
import random
import sys

from mathutils import Matrix, Vector

SEED = 4471
TRI_BUDGET = 250

# Bone-space Y at which every helm mounts (Godot) — the measured adventurer
# skull crown (Barbarian_Head max z in bone space).
MOUNT_Y = 0.945

# Nothing may poke higher than this above the skull crown. Reference points
# from make_crests.py, same units: the Hartcrown royal antlers reach ~0.85,
# the Winterfang pelt hood ~0.68, the Goldclaw mane ruff ~0.26 AND rings the
# whole skull at radius 0.34. A pawn gets 0.21 and a single local motif — the
# side-by-side render (renders/crest_vs_helm.png) is the actual gate.
MOTIF_CEILING = 0.21

# Standoff between the helm shell and the skull surface.
CLEARANCE = 0.030

# ---------------------------------------------------------------------------
# MEASURED skull slice profiles (tools/measure_head.py), bone space.
# rows: (z relative to that skull's crown, half_width, y_front, y_back)
# Bands that sampled only the face (the mesh has no verts across the back at
# that height) are harmless: the envelope below takes a running max from the
# crown downward, which absorbs them.
SKULL_SLICES = {
    # Barbarian.glb / Barbarian_Head — the PAWN body for the eight
    # adventurer hauses. (Barbarian_BearHat is a separate mesh; see README —
    # it must be hidden when the helm is worn.)
    "adventurer": [
        (+0.000, 0.2248, -0.2248, +0.2248),
        (-0.050, 0.3253, -0.3253, +0.3253),
        (-0.100, 0.3984, -0.3984, +0.3984),
        (-0.150, 0.3984, -0.3984, +0.3984),
        (-0.200, 0.4443, -0.4443, +0.4443),
        (-0.250, 0.4443, -0.4443, +0.4443),
        (-0.350, 0.4500, -0.4500, +0.4500),
        (-0.400, 0.3498, -0.4727, -0.2533),
        (-0.450, 0.3609, -0.4727, -0.2530),
        (-0.500, 0.4548, -0.4724, +0.0293),
    ],
    # Skeleton_Minion.glb / Skeleton_Minion_Head — Tidegrip's Drowned Legion.
    "skeleton": [
        (+0.000, 0.1961, -0.1965, +0.1957),
        (-0.050, 0.2220, -0.2032, +0.1957),
        (-0.100, 0.3514, -0.3518, +0.3510),
        (-0.150, 0.3384, -0.3387, +0.3380),
        (-0.200, 0.3139, -0.4050, -0.2913),
        (-0.250, 0.4354, -0.4538, +0.4319),
        (-0.300, 0.4354, -0.4538, +0.4319),
        (-0.350, 0.4241, -0.4530, +0.4175),
        (-0.400, 0.4251, -0.4530, +0.4467),
        (-0.450, 0.3747, -0.4121, +0.3466),
    ],
}

SKULLS = {
    # crown  : bone-space z of the skull crown (== the measured max z)
    # brow   : z relative to the crown where the helm rim stops — just above
    #          the eyes, so the face stays readable
    "adventurer": dict(crown=0.9449, brow=-0.435),
    "skeleton": dict(crown=0.9247, brow=-0.430),
}

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_DIR = argv[0] if argv else "."


# ---------------------------------------------------------------- materials
# Two materials, THE SAME NAMES in all nine GLBs, so the wiring agent finds the
# tintable surface by name and never by index:
#   pawnhelm_iron   — plain dark iron; the helm proper. Left alone by the tint.
#   pawnhelm_accent — rim + haus motif. Deliberately NEAR-WHITE so that
#                     PieceAssets.tinted_material's `albedo_color * tint`
#                     multiply lands the haus colour TRUE instead of muddying
#                     it. (Assigning albedo_color outright works too.)
IRON_RGB = (0.168, 0.180, 0.200)      # cold near-black steel (~#2b3037)
ACCENT_RGB = (0.878, 0.878, 0.878)    # multiply-safe near-white
CHARRED_IRON_RGB = (0.055, 0.053, 0.058)
CHARRED_ACCENT_RGB = (0.290, 0.283, 0.276)


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def make_material(name, base, metallic=0.0, rough=0.8):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*[srgb_to_linear(c) for c in base], 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = rough
    return m


def helm_materials(charred=False):
    iron = make_material("pawnhelm_iron",
                         CHARRED_IRON_RGB if charred else IRON_RGB,
                         0.50 if charred else 0.74,
                         0.74 if charred else 0.52)
    accent = make_material("pawnhelm_accent",
                           CHARRED_ACCENT_RGB if charred else ACCENT_RGB,
                           0.28 if charred else 0.46,
                           0.68 if charred else 0.40)
    return iron, accent


def assign(ob, mat):
    ob.data.materials.append(mat)
    return ob


# ------------------------------------------------------------------- shell
class Shell:
    """The skull-hugging surface the helm is built on, in AUTHORING space
    (origin = this skull's crown, +Z up, front -Y).

    Every motif is placed by asking the shell for a surface point and its
    outward normal, so no motif floats off the cap or sinks into it — and a
    motif written once works on both the adventurer and skeleton skulls."""

    def __init__(self, key):
        prof = SKULLS[key]
        self.brow = prof["brow"]
        self.mount_dz = prof["crown"] - MOUNT_Y

        rows = sorted(SKULL_SLICES[key], key=lambda r: -r[0])   # crown first
        self.zs, self.hw, self.yf, self.yb = [], [], [], []
        run_hw, run_yf, run_yb = 0.0, 1e9, -1e9
        for z, hw, yf, yb in rows:
            # Running max from the crown downward: guarantees the cap is
            # monotone (never cuts inward as it descends) AND always clears
            # the widest skull section at or above this height.
            run_hw = max(run_hw, hw)
            run_yf = min(run_yf, yf)
            run_yb = max(run_yb, yb)
            self.zs.append(z)
            self.hw.append(run_hw + CLEARANCE)
            self.yf.append(run_yf - CLEARANCE)
            self.yb.append(run_yb + CLEARANCE)

    def _lerp(self, table, z):
        zs = self.zs
        if z >= zs[0]:
            return table[0]
        if z <= zs[-1]:
            return table[-1]
        for i in range(len(zs) - 1):
            if zs[i] >= z >= zs[i + 1]:
                t = (zs[i] - z) / (zs[i] - zs[i + 1])
                return table[i] + (table[i + 1] - table[i]) * t
        return table[-1]

    def rx(self, z):
        return self._lerp(self.hw, z)

    def cy(self, z):
        return 0.5 * (self._lerp(self.yf, z) + self._lerp(self.yb, z))

    def ry(self, z):
        return 0.5 * (self._lerp(self.yb, z) - self._lerp(self.yf, z))

    def point(self, az, z):
        """az in radians: 0 = front (-Y), +pi/2 = right (+X)."""
        return Vector((self.rx(z) * math.sin(az),
                       self.cy(z) - self.ry(z) * math.cos(az),
                       z))

    def normal(self, az, z):
        d = 1e-3
        du = self.point(az + d, z) - self.point(az - d, z)
        dv = self.point(az, min(0.0, z + d)) - self.point(az, z - d)
        n = du.cross(dv)
        if n.length < 1e-9:
            return Vector((math.sin(az), -math.cos(az), 0.3)).normalized()
        n.normalize()
        # outward = away from the shell axis
        if n.dot(Vector((math.sin(az), -math.cos(az), 0.25))) < 0:
            n = -n
        return n

    def ridge(self, y):
        """Highest midline (x = 0) surface point at the given y — the fore-aft
        crest line the combs and fins ride."""
        z = 0.0
        while z > self.brow - 0.20:
            if self.cy(z) - self.ry(z) <= y <= self.cy(z) + self.ry(z):
                return Vector((0.0, y, z))
            z -= 0.004
        return Vector((0.0, y, self.brow))

    def ridge_normal(self, y):
        p0, p1 = self.ridge(y - 0.02), self.ridge(y + 0.02)
        t = (p1 - p0).normalized()
        n = Vector((0.0, -t.z, t.y))
        return n if n.z > 0 else -n

    def top(self):
        return self.zs[0]


# --------------------------------------------------------------- primitives
def add_box(size, loc=(0, 0, 0), rot=(0, 0, 0), taper=1.0):
    """Cube scaled to size, base at local z=0, optional top-face taper.
    (Same helper vocabulary as make_crests.py — one pipeline, one dialect.)"""
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


def orient(ob, grow, face):
    """Set a primitive's rotation from an EXPLICIT basis: local +Z along
    `grow`, local +X along `face` (the thin axis of a plate / the direction a
    flat motif looks at). Mirrored motifs stay mirror-symmetric.

    This replaces Vector.to_track_quat(), whose roll is degenerate when the
    growth direction approaches world up — which silently flipped one ear /
    one antler flat against the cap while its twin stood proud."""
    z = Vector(grow).normalized()
    x = Vector(face) - z * Vector(face).dot(z)
    if x.length < 1e-6:
        x = z.orthogonal()
    x.normalize()
    y = z.cross(x)
    ob.rotation_mode = 'QUATERNION'
    ob.rotation_quaternion = Matrix(((x.x, y.x, z.x),
                                     (x.y, y.y, z.y),
                                     (x.z, y.z, z.z))).to_quaternion()
    return ob


def plate(shell, az, z, mat, size, grow, face, taper=0.5, sink=0.035):
    """A flat slab standing off the shell. `size` = (thickness, width, length);
    it grows along `grow` and its flat faces look along `face`."""
    p = shell.point(az, z)
    n = shell.normal(az, z)
    ob = add_box(size, loc=p - n * sink, taper=taper)
    return assign(orient(ob, grow, face), mat)


def spike(shell, az, z, mat, r1, r2, depth, grow, sink=0.35, verts=4):
    """A tapered stub growing out of the shell, sunk `sink` of its length so it
    never shows a floating base."""
    p = shell.point(az, z)
    d = Vector(grow).normalized()
    ob = add_cone(verts, r1, r2, depth, loc=p + d * (depth * (0.5 - sink)))
    return assign(orient(ob, d, Vector((0.0, 0.0, 1.0))), mat)


def tube_chain(points, radii, mat, name="tube"):
    """Round-ish tapered segments through a polyline — the shape language for
    tentacles. A ribbon reads as a fin; a tube reads as a limb."""
    objs = []
    for i in range(len(points) - 1):
        a, b = Vector(points[i]), Vector(points[i + 1])
        d = b - a
        length = d.length
        if length < 1e-6:
            continue
        ob = add_cone(4, radii[i], radii[i + 1], length, loc=a + d * 0.5)
        objs.append(assign(orient(ob, d, Vector((0.0, 0.0, 1.0))), mat))
    return objs


def add_ribbon(sections, mat, name="ribbon"):
    """A solid low ridge/fin swept through 3D `sections`, each
    (base: Vector, top: Vector, side: Vector). 8*(N-1)+4 tris — the cheapest
    CONTINUOUS crest (as opposed to a row of separate studs)."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    rows = []
    for base, top, side in sections:
        rows.append((bm.verts.new(base - side), bm.verts.new(base + side),
                     bm.verts.new(top + side), bm.verts.new(top - side)))
    bm.verts.ensure_lookup_table()
    for i in range(len(rows) - 1):
        a, b = rows[i], rows[i + 1]
        for k in range(4):
            k2 = (k + 1) % 4
            bm.faces.new((a[k], a[k2], b[k2], b[k]))
    bm.faces.new(rows[0])
    bm.faces.new(tuple(reversed(rows[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    # quad_method='FIXED': BEAUTY picks the shorter diagonal, and on the
    # near-square quads of the browband the two diagonals tie — which made
    # the exported INDEX buffer flip between runs. FIXED is reproducible.
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method='FIXED',
                          ngon_method='BEAUTY')
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    return assign(ob, mat)


def midline_fin(shell, ys, heights, half_thick, mat, lean_back=0.0,
                name="fin", thin_tips=True):
    """A fore-aft crest riding the shell's midline ridge."""
    secs = []
    n = len(ys)
    for i, (y, h) in enumerate(zip(ys, heights)):
        base = shell.ridge(y)
        nrm = shell.ridge_normal(y)
        d = (nrm + Vector((0.0, lean_back, 0.0))).normalized()
        t = half_thick * (0.55 if thin_tips and i in (0, n - 1) else 1.0)
        secs.append((base - nrm * 0.035, base + d * h, Vector((t, 0.0, 0.0))))
    return add_ribbon(secs, mat, name)


# ----------------------------------------------------------------- the nine
# Each builder returns the MOTIF objects; build() supplies the dome.
# Everything here is sized to read from the GAMEPLAY camera, which looks down
# on the board from the front at roughly 30-45 degrees: motifs live on the
# top-front of the cap or break the silhouette sideways. A pure fore-aft fin
# is nearly invisible from that angle unless it also breaks the skyline.

def helm_winterfang(shell, iron, accent):
    """WOLF — two broad PRICKED ears facing forward off the temples, plus a
    snout ridge over the brow continuing into a nose guard. Broad-and-forward
    is what separates an ear from Hartcrown's horn: seen head-on the wolf
    shows two triangles, the stag two forks."""
    objs = []
    for sx in (-1, 1):
        grow = Vector((sx * 0.40, 0.12, 1.0)).normalized()
        face = Vector((sx * 0.34, -0.94, 0.0)).normalized()
        objs.append(plate(shell, sx * math.radians(56.0), -0.165, accent,
                          (0.036, 0.235, 0.255), grow, face, taper=0.10))
        objs.append(plate(shell, sx * math.radians(53.0), -0.140, iron,
                          (0.026, 0.130, 0.150),
                          Vector((sx * 0.34, 0.10, 1.0)).normalized(), face,
                          taper=0.18))
    objs.append(midline_fin(shell, (-0.02, -0.13, -0.24, -0.33),
                            (0.062, 0.078, 0.072, 0.050),
                            0.064, accent, lean_back=-0.25, name="SnoutRidge"))
    # nasal: a nose guard hanging from the front rim, set just FORWARD of the
    # face (the shell front sits 0.02 behind the Barbarian's nose, so a nasal
    # placed on the shell buries itself in the beard)
    front_y = shell.cy(shell.brow) - shell.ry(shell.brow)
    nasal = add_box((0.115, 0.075, 0.215),
                    loc=(0.0, front_y - 0.048, shell.brow + 0.035), taper=0.44)
    orient(nasal, Vector((0.0, -0.16, -1.0)), Vector((1.0, 0.0, 0.0)))
    objs.append(assign(nasal, iron))
    return objs


def helm_goldclaw(shell, iron, accent):
    """LION — a short mane-comb: wide, blunt bristle blades splayed alternately
    left and right so the crest reads as FUR, not as a row of spikes."""
    objs = []
    ys = (-0.28, -0.19, -0.10, -0.01, 0.08, 0.17, 0.26)
    for i, y in enumerate(ys):
        base = shell.ridge(y)
        nrm = shell.ridge_normal(y)
        splay = 0.78 if i % 2 == 0 else -0.78
        grow = (nrm + Vector((splay, 0.0, 0.10))).normalized()
        h = (0.185 if i % 2 == 0 else 0.145) * random.uniform(0.96, 1.04)
        if i == 0:
            h = 0.200          # forelock: breaks the brow line head-on
        blade = add_box((0.042, 0.145, h), loc=base - nrm * 0.035, taper=0.46)
        orient(blade, grow, Vector((0.0, 1.0, 0.0)))
        objs.append(assign(blade, accent))
    # cheek tufts finish the ruff at the rim so the mane reads head-on
    for sx in (-1, 1):
        objs.append(plate(shell, sx * math.radians(64.0), -0.315, accent,
                          (0.030, 0.120, 0.170),
                          Vector((sx * 0.85, 0.15, -0.35)).normalized(),
                          Vector((0.0, 1.0, 0.15)).normalized(), taper=0.32))
    return objs


def helm_hartcrown(shell, iron, accent):
    """STAG — two small antler NUBS: a short beam a side carrying two stubby
    tines, one raked forward and one back. Never a rack.

    THICKENED 2026-08-09 (critic defect #10): "Hartcrown's pawn crest is a
    2-pixel gold wire." Correct — the beams were 0.060 radius on a piece
    ~50 px tall, which is under one pixel of shading. The nubs keep their
    height (a pawn stays under MOTIF_CEILING) and gain girth, which is the
    dimension that actually survives downsampling."""
    objs = []
    for sx in (-1, 1):
        az, z = sx * math.radians(43.0), -0.175
        p = shell.point(az, z)
        grow = Vector((sx * 0.50, 0.05, 1.0)).normalized()
        objs.append(assign(orient(add_cone(4, 0.088, 0.052, 0.170,
                                           loc=p + grow * 0.058),
                                  grow, Vector((0.0, 0.0, 1.0))), accent))
        head = p + grow * 0.140
        # the two tines fork OUTWARD and INWARD (not fore/aft): head-on the
        # stag shows a V per side, which is what tells it from Winterfang
        for k, tilt in enumerate(((sx * 1.05, -0.45, 0.90),
                                  (sx * 0.10, -0.30, 1.15))):
            td = Vector(tilt).normalized()
            tine = add_cone(4, 0.052, 0.0, 0.180 - 0.025 * k,
                            loc=head + td * 0.072)
            objs.append(assign(orient(tine, td, Vector((0.0, 0.0, 1.0))),
                               accent))
    return objs


def helm_ashwyrm(shell, iron, accent):
    """DRAGON — ONE continuous dorsal fin with a saw-tooth top, raked back,
    plus two swept brow horns so it reads as a wyrm head-on. Deliberately
    unlike Goldclaw's separate splayed bristles and Silverbrook's smooth-lobed
    fin: the three fore-aft crests must never be confusable at small size."""
    ys = (-0.30, -0.22, -0.14, -0.06, 0.02, 0.10, 0.18, 0.26, 0.32)
    hs = (0.045, 0.150, 0.090, 0.185, 0.098, 0.200, 0.100, 0.145, 0.040)
    objs = [midline_fin(shell, ys, hs, 0.038, accent, lean_back=0.55,
                        name="DorsalFin")]
    for sx in (-1, 1):
        objs.append(spike(shell, sx * math.radians(68.0), -0.255, accent,
                          0.055, 0.006, 0.300,
                          Vector((sx * 0.50, 0.80, 0.34)).normalized(),
                          sink=0.20))
    return objs


def helm_tidegrip(shell, iron, accent):
    """KRAKEN — three short tentacles that grip the brow, run back over the cap
    and hook UP at the tail. Built as TUBES, not ribbons: a ribbon on a helm
    reads as one more fin, a tube reads as a limb.

    HUMBLED 2026-08-09 (critic defect #8). The first cut hooked its tentacle
    tails 0.150 clear of the cap; on the board that read as "a five-spike
    black crown over a bare glowing-eyed face — grander than Thornvale's or
    Hartcrown's ROYAL crests. It reads as a king, not a foot soldier." A pawn
    outranking other hauses' kings is a rank-legibility bug, so the tails now
    barely lift off the shell and the limbs are thinner: the kraken still
    grips the helm, it no longer wears it as a diadem.

    HUMBLED AGAIN 2026-08-09 (third-pass critic, P10): "the board-distance
    half is fixed; close up it still reads royal/undead-king." Correct, and
    the remaining cause is not the tails' HEIGHT but their DESTINATION. They
    climbed to z -0.01 — the crown of the cap — and splayed to +/-65 degrees
    on the way, so at duel range three limbs terminated in upright tips evenly
    spaced around the skull's summit. That is the definition of a diadem, at
    any scale. Two changes end it for good:

      * the limbs now STOP on the upper front slope (z -0.11, a clear tenth
        below the crown) with only a third of the old splay, and their tips
        hook DOWN and back along the shell instead of lifting off it — a
        kraken gripping a helmet, seen from outside the grip;
      * a NASAL BAR (Winterfang's pattern, in plain iron) closes the face.
        Half the "undead king" read was never the tentacles at all: it was a
        BARE glowing-eyed skull framed by a band, which is a portrait of a
        lich. A footman's face bar makes it a portrait of a soldier.

    HUMBLED A THIRD TIME 2026-08-09 (critic defect #4, the close-up half of
    P10 that survived). The tails had stopped climbing, but the SPLAY had not:
    46 degrees grown by a further 35 % put the outer two limbs' tips at +/-62
    degrees — the TEMPLES — and a limb that ends at the temple ends ABOVE the
    browline, because the shell rises there. Three raised tabs spaced evenly
    around a band is a circlet whatever the tabs are shaped like, and the
    duel-range close-up read exactly that: undead ROYALTY, not a footman.
    The geometry now denies the shape rather than shrinking it:
      * the limbs are pulled to the FRONT QUARTER (+/-34 degrees) and the
        splay INVERTS (0.88) — they converge toward the nasal as they climb
        instead of fanning around the skull, so no tip ever reaches a temple;
      * the climb is halved (0.55 of the old rise), keeping every tip on the
        brow's own slope where it sits UNDER the band's top edge, not above;
      * the limbs are thinner again (0.038 base) — a grip, not a frame.
    The kraken still grips the brow; there is no longer a ring of anything."""
    objs = []
    for i, az_deg in enumerate((-34.0, 0.0, 34.0)):
        pts, radii = [], []
        n_pt = 4
        for k in range(n_pt):
            t = k / float(n_pt - 1)
            # up the front slope only — never onto the crown, never to a temple
            z = shell.brow + 0.04 + (abs(shell.brow) - 0.15) * 0.55 * t
            az = math.radians(az_deg) * (1.0 - 0.12 * t)
            p = shell.point(az, z)
            n = shell.normal(az, z)
            pts.append(p + n * (0.018 + 0.012 * t * t))
            radii.append(0.038 - 0.014 * t)
        # the tail hooks DOWN the cap behind it — a grip, never a point
        tail = pts[-1]
        pts.append(tail + Vector((0.0, 0.050, -0.040)))
        radii.append(0.0)
        objs += tube_chain(pts, radii, accent, "Tentacle_%d" % i)
    front_y = shell.cy(shell.brow) - shell.ry(shell.brow)
    nasal = add_box((0.105, 0.070, 0.205),
                    loc=(0.0, front_y - 0.042, shell.brow + 0.032), taper=0.46)
    orient(nasal, Vector((0.0, -0.14, -1.0)), Vector((1.0, 0.0, 0.0)))
    objs.append(assign(nasal, iron))
    return objs


def helm_thornvale(shell, iron, accent):
    """ROSE — a banded browline (a beaded second band above the rim) with a
    rose BOSS at the front centre. The lowest silhouette of the nine:
    Thornvale's pawns are the plainest soldiers on the board.

    MOVED TO THE BROW AND ENLARGED 2026-08-09 (critic defect #9): "the rose
    boss is invisible even at 5x zoom — band and boss are the same green as
    the armour; the pawn is an unmarked black dome." Half of that was colour
    and is fixed at runtime (the helm charge is now the heraldic colour
    FURTHEST from the body, which hands Thornvale its gold). The other half
    was placement and size: the boss sat high on the cap where the top-down
    camera foreshortens it into the shell. It now sits ON the browband,
    front and centre, half again as large."""
    objs = []
    band_z = shell.brow + 0.085
    secs = []
    n = 11
    for k in range(n):
        az = math.radians(-106.0 + 212.0 * k / (n - 1.0))
        p = shell.point(az, band_z)
        nrm = shell.normal(az, band_z)
        h = 0.058 if k % 2 == 0 else 0.036       # beaded: a thorn-set browband
        tangent = Vector((math.cos(az), math.sin(az), 0.0)).normalized()
        secs.append((p - nrm * 0.035, p + nrm * h, tangent * 0.060))
    objs.append(add_ribbon(secs, accent, "BrowBand"))
    boss_z = band_z + 0.028
    p = shell.point(0.0, boss_z)
    n = shell.normal(0.0, boss_z)
    objs.append(assign(add_sphere(6, 4, 0.150, loc=p + n * 0.044,
                                  scale=(1.0, 0.72, 1.0)), accent))
    for sx in (-1, 1):
        objs.append(spike(shell, sx * math.radians(32.0), band_z + 0.050, iron,
                          0.036, 0.0, 0.105,
                          Vector((sx * 0.55, -0.55, 0.62)).normalized(),
                          sink=0.28))
    return objs


def helm_duskfire(shell, iron, accent):
    """SUN — a low sunburst disc set over the brow: a boss ringed by short
    rays, flat on the front of the cap, adding nothing at all to the height."""
    objs = []
    z = shell.brow + 0.155
    p = shell.point(0.0, z)
    n = shell.normal(0.0, z)
    disc = add_cone(8, 0.150, 0.150, 0.048, loc=p + n * 0.014)
    objs.append(assign(orient(disc, n, Vector((1.0, 0.0, 0.0))), accent))
    v = n.cross(Vector((1.0, 0.0, 0.0)))
    if v.length < 1e-6:
        v = n.cross(Vector((0.0, 0.0, 1.0)))
    v.normalize()
    u = v.cross(n).normalized()
    for k in range(8):
        a = 2.0 * math.pi * k / 8.0
        d = (u * math.cos(a) + v * math.sin(a)).normalized()
        length = 0.135 if k % 2 == 0 else 0.085
        ray = add_cone(3, 0.038, 0.0, length,
                       loc=p + n * 0.012 + d * (0.140 + length * 0.45))
        objs.append(assign(orient(ray, d, n), accent if k % 2 == 0 else iron))
    return objs


def helm_swiftcrest(shell, iron, accent):
    """FALCON — swept wing-flares at the temples: a long primary with a shorter
    covert above it, both raked BACK (+Y) and up, their planes vertical like a
    winged helm. These break the silhouette SIDEWAYS, which is how a small
    motif survives a top-down camera."""
    objs = []
    for sx in (-1, 1):
        face = Vector((sx * 0.95, 0.30, 0.0)).normalized()
        objs.append(plate(shell, sx * math.radians(80.0), -0.235, accent,
                          (0.030, 0.140, 0.390),
                          Vector((sx * 0.80, 0.62, 0.30)).normalized(),
                          face, taper=0.12))
        objs.append(plate(shell, sx * math.radians(70.0), -0.120, accent,
                          (0.026, 0.105, 0.265),
                          Vector((sx * 0.66, 0.55, 0.62)).normalized(),
                          face, taper=0.18))
        # a leading nub at the brow finishes the wing root
        objs.append(spike(shell, sx * math.radians(86.0), -0.320, iron,
                          0.042, 0.008, 0.110,
                          Vector((sx * 0.80, -0.55, 0.20)).normalized(),
                          sink=0.30))
    return objs


def helm_silverbrook(shell, iron, accent):
    """TROUT — a smooth-LOBED fin crest fore-aft (rounded humps, no saw teeth)
    over big overlapping scale tiles lying flat on the cap flanks."""
    ys = (-0.38, -0.28, -0.17, -0.06, 0.05, 0.16, 0.27)
    hs = (0.048, 0.145, 0.185, 0.180, 0.145, 0.100, 0.045)
    objs = [midline_fin(shell, ys, hs, 0.032, accent, lean_back=0.12,
                        name="FinCrest")]
    for sx in (-1, 1):
        for k, (az_deg, z) in enumerate(((58.0, -0.150), (80.0, -0.300))):
            p = shell.point(sx * math.radians(az_deg), z)
            n = shell.normal(sx * math.radians(az_deg), z)
            # a scale lies ON the cap: it grows along the surface (down/back)
            # and its flat face IS the surface normal
            down = Vector((0.0, 0.30, -1.0))
            grow = (down - n * down.dot(n)).normalized()
            tile = add_box((0.030, 0.245, 0.180), loc=p - n * 0.012,
                           taper=0.60)
            orient(tile, grow, n)
            objs.append(assign(tile, accent))
    return objs


BUILDERS = {
    "winterfang": helm_winterfang,
    "goldclaw": helm_goldclaw,
    "hartcrown": helm_hartcrown,
    "ashwyrm": helm_ashwyrm,
    "tidegrip": helm_tidegrip,
    "thornvale": helm_thornvale,
    "duskfire": helm_duskfire,
    "swiftcrest": helm_swiftcrest,
    "silverbrook": helm_silverbrook,
}

# Tidegrip's pawn is a Skeleton_Minion; every other haus's is a Barbarian.
SKELETON_HOUSE = "tidegrip"


# ------------------------------------------------------------------- dome
def build_dome(shell, iron, accent, n_seg=12, n_rows=3,
               flare=0.038, flare_drop=0.052):
    """The helm proper: a faceted skullcap following the measured profile from
    the crown down to the brow, finished with a flared rim in the ACCENT
    material (so every haus reads its colour even when the motif is tiny).

    Tris = n_seg*2*n_rows (wall) + (n_seg-2) (crown cap) + n_seg*2 (rim)."""
    me = bpy.data.meshes.new("HelmDome")
    bm = bmesh.new()

    # ring heights: brow -> crown, eased so the facets stay even in silhouette
    zs = []
    for j in range(n_rows + 1):
        t = (j / float(n_rows)) ** 0.85
        zs.append(shell.brow + (shell.top() - shell.brow) * t)
    rings = [[bm.verts.new(shell.point(2.0 * math.pi * k / n_seg, z))
              for k in range(n_seg)] for z in zs]

    fx = 1.0 + flare / shell.rx(shell.brow)
    fy = 1.0 + flare / shell.ry(shell.brow)
    cy0 = shell.cy(shell.brow)
    rim = []
    for k in range(n_seg):
        p = shell.point(2.0 * math.pi * k / n_seg, shell.brow)
        rim.append(bm.verts.new(Vector((p.x * fx, cy0 + (p.y - cy0) * fy,
                                        p.z - flare_drop))))
    bm.verts.ensure_lookup_table()

    faces_rim = []
    for k in range(n_seg):
        k2 = (k + 1) % n_seg
        for j in range(n_rows):
            bm.faces.new((rings[j][k], rings[j][k2], rings[j + 1][k2],
                          rings[j + 1][k]))
        faces_rim.append(bm.faces.new((rim[k], rim[k2], rings[0][k2],
                                       rings[0][k])))
    bm.faces.new(list(reversed(rings[-1])))     # flat crown cap

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    for f in faces_rim:
        f.material_index = 1
    # quad_method='FIXED': BEAUTY picks the shorter diagonal, and on the
    # near-square quads of the browband the two diagonals tie — which made
    # the exported INDEX buffer flip between runs. FIXED is reproducible.
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method='FIXED',
                          ngon_method='BEAUTY')
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("HelmDome", me)
    bpy.context.collection.objects.link(ob)
    ob.data.materials.append(iron)
    ob.data.materials.append(accent)
    return ob


# ------------------------------------------------------------------ export
def tri_count(ob):
    deps = bpy.context.evaluated_depsgraph_get()
    me = ob.evaluated_get(deps).to_mesh()
    me.calc_loop_triangles()
    n = len(me.loop_triangles)
    ob.evaluated_get(deps).to_mesh_clear()
    return n


def finalize(objs, name, shell, out_path):
    for ob in objs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    helm = bpy.context.active_object
    helm.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for p in helm.data.polygons:
        p.use_smooth = False

    # Shift so adventurer-skull and skeleton-skull helms mount at the SAME
    # bone-space Y: one transform for the wiring agent, no per-cast branch.
    # The same pass snaps sub-micron values to exact zero: without it the
    # midline vertices land on denormals (~1e-38) that flip run to run, and
    # the GLBs stop being byte-reproducible for no geometric reason.
    #
    # KNOWN GAP (measured 2026-08-09, not yet closed): eight of the nine helms
    # are byte-identical across runs; pawn_helm_thornvale.glb is NOT — same
    # file size, same tri count, same silhouette, different last bits. Its
    # builder is the only one that mixes a swept ribbon with a non-uniformly
    # scaled UV sphere, so the snap above is not catching whatever survives the
    # join. Harmless visually, but it means a regeneration of the whole set
    # dirties one file for nothing; check `cmp` before committing a rebuild.
    for v in helm.data.vertices:
        v.co.z += shell.mount_dz
        for i in range(3):
            if abs(v.co[i]) < 1e-6:
                v.co[i] = 0.0

    n = tri_count(helm)
    over = n > TRI_BUDGET
    if over:
        print("[helm] WARNING %s over budget (%d) — decimating" % (name, n))
        dec = helm.modifiers.new("Budget", 'DECIMATE')
        dec.ratio = TRI_BUDGET / float(n)
        n = tri_count(helm)

    bb = [Vector(c) for c in helm.bound_box]
    hi = Vector((max(c.x for c in bb), max(c.y for c in bb), max(c.z for c in bb)))
    lo = Vector((min(c.x for c in bb), min(c.y for c in bb), min(c.z for c in bb)))
    peak = hi.z - shell.mount_dz          # height above THIS skull's crown
    if peak > MOTIF_CEILING + 1e-3:
        print("[helm] WARNING %s breaks the pawn ceiling: %.3f > %.3f"
              % (name, peak, MOTIF_CEILING))
        over = True

    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=out_path, export_format='GLB',
                              export_apply=True, export_yup=True)
    return n, lo, hi, peak, over


def build(house_id, charred=False):
    # NOT hash(): Python string hashing is salted per-process -> not reproducible
    random.seed(SEED + sum(ord(c) for c in house_id))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    shell = Shell("skeleton" if house_id == SKELETON_HOUSE else "adventurer")
    iron, accent = helm_materials(charred)
    objs = [build_dome(shell, iron, accent)] + BUILDERS[house_id](shell, iron, accent)
    suffix = "_charred" if charred else ""
    out = os.path.join(OUT_DIR, "pawn_helm_%s%s.glb" % (house_id, suffix))
    n, lo, hi, peak, over = finalize(objs, "Helm_%s%s" % (house_id, suffix),
                                     shell, out)
    print("[helm] %-11s %-7s %4d tris  size=(%.3f, %.3f, %.3f)  peak=%+.3f  -> %s"
          % (house_id, "CHARRED" if charred else "", n,
             hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, peak, os.path.basename(out)))
    return n, over


if __name__ == "__main__":
    total, bad = 0, 0
    for hid in BUILDERS:
        n, over = build(hid)
        total += n
        bad += int(over)
    build(SKELETON_HOUSE, charred=True)
    print("[helm] nine helms, %d tris total (avg %d), budget %d each, %d over"
          % (total, total // 9, TRI_BUDGET, bad))
    if bad:
        sys.exit(1)
