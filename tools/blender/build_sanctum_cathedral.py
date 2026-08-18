"""Sanctum Cathedral — procedural gothic architecture generator (headless Blender).

Run:  blender -b -P tools/blender/build_sanctum_cathedral.py -- [--no-ao] [--out <path.glb>]

Rebuilt 2026-08-17. The previous generator authored its geometry Y-up inside
Z-up Blender and then exported with the exporter's own +Y-up conversion, so
the shipped GLB was rotated 90 deg: `glb_stats.py` measured y in [-31.6, 29.9]
and z in [-41.7, 0.4] — half the cathedral below the floor and none of it east
of the board. Every coordinate in THIS file is written in GODOT space (x
lateral, y up, z nave axis, board at origin) and crosses into Blender exactly
once, through `G()`. After every export, `tools/blender/glb_stats.py` must
show y >= -22 (the crag cliffs) and towers topping out near +52 — that check
is the reproducible observation this asset cites.

Site constraints the architecture is designed around (src/env/great_hall.gd):
  * the 24x24 great hall occupies |x|,|z| <= 12 up to y 11.7 (open-topped) —
    the nave arcade stands OUTSIDE it at x = +-13.4;
  * the hall floor top is y -0.30 — the cathedral slab sits at -0.42;
  * the 8-omni torch budget is FULL: this asset ships ZERO lights; stained
    glass and candle crowns are emissive materials only;
  * the gameplay camera (pivot y 0.4, pitch -0.85, fov 50) frames the far
    wall's bottom metre — everything scenic lives above that band.

The two set-pieces the fly-in cinematic depends on (coordinates are load-
bearing — cathedral_cinematic_intro.gd and great_hall.gd cite them):
  * THE DRAGON DOOR — the west rose (0, 20.5, -26) is an OPEN stone wheel,
    oculus clear radius ~3.2: the wyrm threads it on the way in;
  * THE WYRM'S GALLERY — a corbelled ledge over the apse arch, top at
    y 12.2, front face z 12.85, centred on x 0: the perch with a clear
    sightline over the hall's 11.7 wall crest to the board, silhouetted
    against the ember rose in the chevet behind it.

Vertex colors carry baked AO x grime (Cycles, deterministic) — on the Mobile
renderer with no SSAO/GI that bake is where all the depth comes from. Godot's
glTF importer enables vertex-color-as-albedo automatically when COLOR_0 is
present; glb_stats.py asserts the attribute survived export.
"""

import math
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

RNG = random.Random(1988)

# ── the measure ledger (godot units) ─────────────────────────────────────────
FLOOR_TOP = -0.42          # cathedral slab, under the hall's -0.30 floor
NAVE_X = 13.4              # arcade centreline (hall walls end at 12.0)
AISLE_X = 20.0             # aisle outer wall centreline
WEST_Z = -26.0             # west facade / dragon door wall
EAST_ARCH_Z = 14.0         # apse arch wall (the gallery wall)
CHEVET_Z = 27.0            # flat east chevet (ember rose wall)
BAY_ZS = [-19.5, -13.0, -6.5, 0.0, 6.5, 13.0]   # free-standing pier pairs
BAY_EDGES = [-26.0, -19.5, -13.0, -6.5, 0.0, 6.5, 13.0, 14.0]

PIER_CAP = 9.0             # capital seat
ARCADE_SPRING = 9.8
TRIF_LO, TRIF_HI = 14.4, 17.2
CLER_SILL, CLER_TOP = 17.8, 25.2
VAULT_SPRING = 17.0
VAULT_APEX = 31.0
# The eaves sit ABOVE the vault haunches: the transverse crowns run level at
# y 31 across the nave, so a lower eave line puts webs through the roof
# (measured on the first build's aerial still — pale triangles along the
# ridge were the vault poking out of the slate).
EAVE_Y = 31.8
RIDGE_Y = 38.5
AISLE_WALL_TOP = 13.0

ROSE_WEST = Vector((0.0, 20.8, WEST_Z))     # OPEN — the dragon door
ROSE_WEST_R = 6.0
ROSE_EAST = Vector((0.0, 20.0, CHEVET_Z))   # ember glass behind the perch
ROSE_EAST_R = 4.8

GALLERY_TOP = 12.2         # the Wyrm's Gallery ledge top
GALLERY_FRONT_Z = 12.85
GALLERY_BACK_Z = 14.55
GALLERY_HALF_W = 4.8       # spectator HitReact wings reach +-4.6 at 1.65

TOWER_X = 15.8             # twin west towers, centres
TOWER_Z = -27.6
TOWER_S1 = 22.0            # stage tops: base / gallery / belfry / spire tip
TOWER_S2 = 33.0
TOWER_S3 = 41.0
SPIRE_TIP = 56.0

COURT_Y = -2.25            # west courtyard below the portal steps
CRAG_R = 46.0
CLIFF_BOTTOM = -21.0


def G(x, y, z):
    """Godot (x lateral, y up, z axis) -> Blender (Z-up). The ONLY crossing."""
    return Vector((x, -z, y))


def R_for(span, rise):
    """Two-centre pointed-arch radius for a given span and rise (rise > span/2
    keeps it pointed; at rise == span/2 it degenerates to a semicircle)."""
    return (rise * rise + span * span / 4.0) / span


def arch_pts(span, rise, n=14):
    """(u, v) polyline of a pointed arch from (-span/2, 0) to (span/2, 0),
    apex at (0, rise). n points per half."""
    radius = R_for(span, rise)
    c = radius - span / 2.0        # centre of the LEFT arc sits at +c
    a0 = math.pi                   # at the left springing
    a1 = math.atan2(rise, -c)      # at the apex
    left = []
    for i in range(n + 1):
        a = a0 + (a1 - a0) * i / n
        left.append((c + radius * math.cos(a), radius * math.sin(a)))
    right = [(-u, v) for (u, v) in reversed(left[:-1])]
    return left + right            # 2n+1 points, left springing -> right


# ── material buckets ─────────────────────────────────────────────────────────
# name -> (base RGBA, roughness, metallic, emission RGB or None, strength, ao)
MAT_SPECS = {
    "cathedral_stone_light": ((0.60, 0.565, 0.505, 1.0), 0.86, 0.02, None, 0, True),
    "cathedral_stone_mid":   ((0.47, 0.44, 0.415, 1.0), 0.88, 0.02, None, 0, True),
    "cathedral_stone_dark":  ((0.335, 0.315, 0.30, 1.0), 0.90, 0.02, None, 0, True),
    "cathedral_slate":       ((0.135, 0.15, 0.185, 1.0), 0.52, 0.12, None, 0, True),
    "cathedral_copper_rust": ((0.52, 0.26, 0.11, 1.0), 0.46, 0.55, None, 0, True),
    "cathedral_oak":         ((0.165, 0.105, 0.062, 1.0), 0.62, 0.02, None, 0, True),
    "cathedral_brass":       ((0.86, 0.66, 0.28, 1.0), 0.26, 0.90, None, 0, False),
    "cathedral_iron":        ((0.085, 0.085, 0.095, 1.0), 0.42, 0.85, None, 0, False),
    "cathedral_glass_sapphire": ((0.08, 0.17, 0.55, 1.0), 0.15, 0.0, (0.16, 0.36, 1.0), 1.7, False),
    "cathedral_glass_amber":    ((0.55, 0.30, 0.08, 1.0), 0.15, 0.0, (1.0, 0.55, 0.12), 1.9, False),
    "cathedral_glass_ember":    ((0.52, 0.12, 0.04, 1.0), 0.15, 0.0, (1.0, 0.26, 0.06), 2.2, False),
    "cathedral_candle":         ((1.0, 0.78, 0.40, 1.0), 0.4, 0.0, (1.0, 0.68, 0.28), 2.4, False),
    "cathedral_rock":        ((0.225, 0.21, 0.20, 1.0), 0.95, 0.0, None, 0, True),
    "cathedral_void":        ((0.015, 0.013, 0.018, 1.0), 1.0, 0.0, None, 0, False),
}

BUCKETS = {}


def bucket(name):
    if name not in BUCKETS:
        BUCKETS[name] = bmesh.new()
    return BUCKETS[name]


# ── low-level builders (all take godot coordinates) ──────────────────────────


def add_box(bm, center, size, yaw=0.0):
    """Axis box at godot `center`, godot `size` (sx lateral, sy up, sz axis),
    yawed about godot up."""
    m = (Matrix.Translation(G(*center))
         @ Matrix.Rotation(yaw, 4, 'Z')
         @ Matrix.Diagonal((size[0], size[2], size[1], 1.0)))
    bmesh.ops.create_cube(bm, size=1.0, matrix=m)


def add_cone(bm, base_center, r1, r2, height, segments=8, yaw=0.0):
    """Vertical (godot up) cone/cylinder from base_center rising `height`."""
    c = (base_center[0], base_center[1] + height / 2.0, base_center[2])
    m = (Matrix.Translation(G(*c)) @ Matrix.Rotation(yaw, 4, 'Z')
         @ Matrix.Rotation(0.0, 4, 'X'))
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segments,
                          radius1=r1, radius2=r2, depth=height, matrix=m)


def add_disk(bm, center, radius, segments=32, facing_up=True):
    m = Matrix.Translation(G(*center))
    ret = bmesh.ops.create_circle(bm, cap_ends=True, segments=segments,
                                  radius=radius, matrix=m)
    for v in ret["verts"]:
        for f in v.link_faces:
            want = 1.0 if facing_up else -1.0
            if f.normal.z * want < 0:
                f.normal_flip()


def quad(bm, a, b, c, d):
    """One quad through four godot points (winding = caller's problem)."""
    vs = [bm.verts.new(G(*p)) for p in (a, b, c, d)]
    try:
        return bm.faces.new(vs)
    except ValueError:
        return None


def sweep_box(bm, pts, half_w, half_h, up_hint=None):
    """Loft a rectangular profile along a godot polyline (ribs, flyers,
    archivolt mouldings). `half_w` spans the side axis, `half_h` the up axis."""
    up_hint = Vector(up_hint) if up_hint is not None else Vector((0, 0, 1))
    bpts = [G(*p) for p in pts]
    rings = []
    for i, p in enumerate(bpts):
        a = bpts[max(i - 1, 0)]
        b = bpts[min(i + 1, len(bpts) - 1)]
        t = (b - a).normalized()
        side = t.cross(up_hint)
        if side.length < 1e-4:
            side = t.cross(Vector((0, 1, 0)))
        side.normalize()
        up = side.cross(t).normalized()
        ring = [bm.verts.new(p + side * half_w + up * half_h),
                bm.verts.new(p - side * half_w + up * half_h),
                bm.verts.new(p - side * half_w - up * half_h),
                bm.verts.new(p + side * half_w - up * half_h)]
        rings.append(ring)
    for i in range(len(rings) - 1):
        r0, r1 = rings[i], rings[i + 1]
        for k in range(4):
            bm.faces.new((r0[k], r0[(k + 1) % 4], r1[(k + 1) % 4], r1[k]))
    bm.faces.new(tuple(reversed(rings[0])))
    bm.faces.new(tuple(rings[-1]))


class Panel:
    """A vertical wall plane in godot space with its own 2D (u=lateral,
    v=up) frame. `origin` is the u=0,v=0 point ON the panel's centre plane,
    `lateral` the godot direction of +u, `normal` the outward face direction.
    Depth w runs along -normal into the wall (half-thickness each way)."""

    def __init__(self, bm, origin, lateral, normal, thickness):
        self.bm = bm
        self.o = Vector(origin)
        self.lat = Vector(lateral).normalized()
        self.n = Vector(normal).normalized()
        self.t = thickness

    def p(self, u, v, w):
        """godot point: on-plane (u,v) pushed w along the normal."""
        gp = self.o + self.lat * u + Vector((0, 1, 0)) * v + self.n * w
        return (gp.x, gp.y, gp.z)

    def face(self, quad_uv, front=True):
        """A quad face on the front (+t/2) or back (-t/2) skin.
        quad_uv = [(u, v), ...] CCW as seen from OUTSIDE (front)."""
        w = self.t / 2.0 if front else -self.t / 2.0
        pts = quad_uv if front else list(reversed(quad_uv))
        vs = [self.bm.verts.new(G(*self.p(u, v, w))) for (u, v) in pts]
        try:
            self.bm.faces.new(vs)
        except ValueError:
            pass

    def slab(self, u0, v0, u1, v1):
        """Solid rectangle through the whole thickness (front+back+4 rims)."""
        self.face([(u0, v0), (u1, v0), (u1, v1), (u0, v1)], front=True)
        self.face([(u0, v0), (u1, v0), (u1, v1), (u0, v1)], front=False)
        h = self.t / 2.0
        for (a, b) in [((u0, v0), (u1, v0)), ((u1, v0), (u1, v1)),
                       ((u1, v1), (u0, v1)), ((u0, v1), (u0, v0))]:
            vs = [self.bm.verts.new(G(*self.p(a[0], a[1], h))),
                  self.bm.verts.new(G(*self.p(b[0], b[1], h))),
                  self.bm.verts.new(G(*self.p(b[0], b[1], -h))),
                  self.bm.verts.new(G(*self.p(a[0], a[1], -h)))]
            try:
                self.bm.faces.new(vs)
            except ValueError:
                pass

    def curtain(self, curve_uv, v_top):
        """Wall from a polyline UP to v_top (the spandrel above an arch):
        smooth curved bottom edge, straight top, both skins + reveal strips."""
        h = self.t / 2.0
        for i in range(len(curve_uv) - 1):
            (u0, v0), (u1, v1) = curve_uv[i], curve_uv[i + 1]
            self.face([(u0, v0), (u1, v1), (u1, v_top), (u0, v_top)], True)
            self.face([(u0, v0), (u1, v1), (u1, v_top), (u0, v_top)], False)
            vs = [self.bm.verts.new(G(*self.p(u0, v0, h))),
                  self.bm.verts.new(G(*self.p(u1, v1, h))),
                  self.bm.verts.new(G(*self.p(u1, v1, -h))),
                  self.bm.verts.new(G(*self.p(u0, v0, -h)))]
            try:
                self.bm.faces.new(list(reversed(vs)))
            except ValueError:
                pass

    def arch_wall(self, u_center, span, sill, spring, rise, u0, u1, v0, v1):
        """Rectangular panel (u0..u1, v0..v1) pierced by one pointed-arch
        opening: side slabs, sill slab, arch spandrel, jamb reveals."""
        ul, ur = u_center - span / 2.0, u_center + span / 2.0
        if u0 < ul:
            self.slab(u0, v0, ul, v1)
        if ur < u1:
            self.slab(ur, v0, u1, v1)
        if v0 < sill:
            self.slab(ul, v0, ur, sill)
        curve = [(u_center + u, spring + v) for (u, v) in arch_pts(span, rise)]
        jambed = [(ul, sill)] + curve + [(ur, sill)]
        self.curtain(jambed, v1)


def annulus(bm, center, r_in, r_out, depth, seg=40):
    """Flat ring at godot `center` in an x/y plane (normal along z):
    front + back annulus faces and inner + outer rim walls."""
    cx, cy, cz = center
    for i in range(seg):
        a0 = 2 * math.pi * i / seg
        a1 = 2 * math.pi * (i + 1) / seg
        p = [(cx + r_out * math.cos(a0), cy + r_out * math.sin(a0)),
             (cx + r_out * math.cos(a1), cy + r_out * math.sin(a1)),
             (cx + r_in * math.cos(a1), cy + r_in * math.sin(a1)),
             (cx + r_in * math.cos(a0), cy + r_in * math.sin(a0))]
        for zface, flip in [(cz - depth / 2, False), (cz + depth / 2, True)]:
            pts = [(u, v, zface) for (u, v) in (reversed(p) if flip else p)]
            quad(bm, *pts)
        for k in [(0, 1), (3, 2)]:
            (u0, v0), (u1, v1) = p[k[0]], p[k[1]]
            quad(bm, (u0, v0, cz - depth / 2), (u1, v1, cz - depth / 2),
                 (u1, v1, cz + depth / 2), (u0, v0, cz + depth / 2))


def glass_fan(bm, pts3, both_sides=True):
    """Triangle-fan a closed godot polyline (a window pane). Two windings so
    the emissive pane reads from inside AND outside."""
    n = len(pts3)
    cx = sum(p[0] for p in pts3) / n
    cy = sum(p[1] for p in pts3) / n
    cz = sum(p[2] for p in pts3) / n
    for flip in ([False, True] if both_sides else [False]):
        cv = bm.verts.new(G(cx, cy, cz))
        ring = [bm.verts.new(G(*p)) for p in pts3]
        for i in range(n - 1):
            tri = (cv, ring[i + 1], ring[i]) if flip else (cv, ring[i], ring[i + 1])
            try:
                bm.faces.new(tri)
            except ValueError:
                pass


def arch_pane(bm, origin, lateral, u_center, span, sill, spring, rise):
    """Glass pane filling a pointed-arch opening on a wall panel: jambs up
    from the sill, arch over the top. `origin`/`lateral` as in Panel."""
    o = Vector(origin)
    lat = Vector(lateral).normalized()
    up = Vector((0, 1, 0))

    def P3(u, v):
        p = o + lat * u + up * v
        return (p.x, p.y, p.z)

    curve = [(u_center + u, spring + v) for (u, v) in arch_pts(span, rise, 9)]
    outline = ([(u_center - span / 2, sill)] + curve
               + [(u_center + span / 2, sill)])
    glass_fan(bm, [P3(u, v) for (u, v) in outline])


def rose_window(stone, glass, center, radius, depth, open_center, spokes=12):
    """Wheel-tracery rose on a z-normal wall: slender outer ring, slim
    radial spokes, hub ring, cusp roundels between the spoke heads — and
    either stained glass behind the wheel or (the dragon door) open sky."""
    cx, cy, cz = center
    seg = 44
    # outer ring
    annulus(stone, center, radius * 0.90, radius, depth, seg)
    # hub ring: wide-open oculus for the dragon door, tight hub when glazed
    hub_in = radius * (0.50 if open_center else 0.22)
    hub_out = radius * (0.58 if open_center else 0.30)
    annulus(stone, center, hub_in, hub_out, depth * 0.8, seg // 2)
    # spokes: slim swept boxes from the hub to the ring
    for i in range(spokes):
        a = 2 * math.pi * (i + 0.5) / spokes
        r0, r1 = hub_out - radius * 0.01, radius * 0.915
        pts = [(cx + r * math.cos(a), cy + r * math.sin(a), cz)
               for r in (r0, (r0 + r1) / 2, r1)]
        sweep_box(stone, pts, radius * 0.030, depth * 0.36, up_hint=(0, 0, -1))
    # cusp roundels between spoke heads
    ro = (hub_out + radius * 0.90) / 2
    rc = radius * 0.085
    for i in range(spokes):
        a = 2 * math.pi * i / spokes
        annulus(stone, (cx + ro * math.cos(a), cy + ro * math.sin(a), cz),
                rc * 0.55, rc, depth * 0.55, 10)
    if not open_center and glass is not None:
        seg_g = 36
        ring = [(cx + radius * 0.92 * math.cos(2 * math.pi * i / seg_g),
                 cy + radius * 0.92 * math.sin(2 * math.pi * i / seg_g), cz)
                for i in range(seg_g)]
        glass_fan(glass, ring + [ring[0]])


def pinnacle(bm, base, base_w, shaft_h, spire_h):
    """Square shaft + tapering crocketed spirelet + finial knob."""
    x, y, z = base
    add_box(bm, (x, y + shaft_h / 2, z), (base_w, shaft_h, base_w))
    add_cone(bm, (x, y + shaft_h, z), base_w * 0.62, 0.02, spire_h, segments=6)
    for i in range(3):
        fy = y + shaft_h + spire_h * (0.22 + 0.26 * i)
        fr = base_w * 0.62 * (1.0 - (0.22 + 0.26 * i)) + 0.05
        for a in range(4):
            aa = a * math.pi / 2 + math.pi / 4
            add_box(bm, (x + (fr + 0.07) * math.cos(aa), fy,
                         z + (fr + 0.07) * math.sin(aa)), (0.13, 0.16, 0.13), yaw=aa)
    add_cone(bm, (x, y + shaft_h + spire_h, z), 0.09, 0.0, 0.34, segments=6)


def balustrade(bm, p0, p1, height=0.85, gap_center=0.0):
    """Pierced parapet between two godot points: rails + colonnettes.
    gap_center > 0 leaves an opening of that width mid-run (the wyrm's step)."""
    p0, p1 = Vector(p0), Vector(p1)
    run = p1 - p0
    length = run.length
    d = run.normalized()
    n = int(length / 0.55)
    yaw = math.atan2(d.x, d.z)
    for (t0, t1) in [(0.0, 1.0)]:
        pass
    for frac_h, th in [(height, 0.14), (0.08, 0.12)]:
        if gap_center > 0:
            for (a, b) in [(0.0, 0.5 - gap_center / (2 * length)),
                           (0.5 + gap_center / (2 * length), 1.0)]:
                c = p0 + run * ((a + b) / 2)
                add_box(bm, (c.x, c.y + frac_h, c.z),
                        (0.2, th, (b - a) * length), yaw=yaw)
        else:
            c = p0 + run * 0.5
            add_box(bm, (c.x, c.y + frac_h, c.z), (0.2, th, length), yaw=yaw)
    for i in range(n + 1):
        f = i / n
        if gap_center > 0 and abs(f - 0.5) < gap_center / (2 * length):
            continue
        c = p0 + run * f
        add_cone(bm, (c.x, c.y + 0.12, c.z), 0.075, 0.06, height - 0.14, segments=6)


def gargoyle(bm, pos, out_dir):
    """A projecting stone beast: haunched body, long snout, folded wings."""
    x, y, z = pos
    dx = 1.0 if out_dir > 0 else -1.0
    add_box(bm, (x + dx * 0.35, y, z), (1.1, 0.5, 0.5))
    add_box(bm, (x + dx * 1.0, y + 0.1, z), (0.75, 0.34, 0.34))
    add_box(bm, (x + dx * 1.42, y + 0.04, z), (0.4, 0.22, 0.26))
    for sz in (-1, 1):
        add_box(bm, (x + dx * 0.25, y + 0.42, z + sz * 0.28),
                (0.65, 0.5, 0.1), yaw=sz * 0.5)
    add_box(bm, (x - dx * 0.28, y + 0.18, z), (0.5, 0.24, 0.24), yaw=0.35)


# ── the architecture ─────────────────────────────────────────────────────────


def build_floor_and_crag():
    rock = bucket("cathedral_rock")
    stone = bucket("cathedral_stone_dark")
    # nave + aisle slab (under the hall too — 0.12 below its floor, no fight)
    add_box(stone, (0.0, FLOOR_TOP - 0.25, (WEST_Z + CHEVET_Z) / 2),
            (AISLE_X * 2 + 1.6, 0.5, CHEVET_Z - WEST_Z + 1.6))
    # west courtyard
    add_box(rock, (0.0, COURT_Y - 0.25, -37.5), (26.0, 0.5, 15.0))
    # portal steps: courtyard up to the slab
    steps = 6
    for i in range(steps):
        t = i / (steps - 1)
        yy = COURT_Y + (FLOOR_TOP - COURT_Y) * (i + 1) / steps
        add_box(rock, (0.0, yy - 0.14, -30.2 + t * 3.4), (16.0 - 2.0 * t, 0.28, 0.9))
    # the crag: irregular plateau rim dropping to cliffs
    seg = 40
    rim = []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        r = CRAG_R * (1.0 + 0.16 * math.sin(a * 3 + 1.7) + 0.09 * math.sin(a * 7 + 0.4))
        rim.append((math.cos(a) * r, math.sin(a) * r))
    for i in range(seg):
        (x0, z0), (x1, z1) = rim[i], rim[(i + 1) % seg]
        top = COURT_Y if (z0 < -28 and z1 < -28) else FLOOR_TOP
        in0 = (x0 * 0.42, z0 * 0.42)
        in1 = (x1 * 0.42, z1 * 0.42)
        quad(rock, (in0[0], top, in0[1]), (in1[0], top, in1[1]),
             (x1, top - 0.7, z1), (x0, top - 0.7, z0))
        mid0 = (x0 * 1.06, z0 * 1.06)
        mid1 = (x1 * 1.06, z1 * 1.06)
        quad(rock, (x0, top - 0.7, z0), (x1, top - 0.7, z1),
             (mid1[0], top - 9.0, mid1[1]), (mid0[0], top - 9.0, mid0[1]))
        bot0 = (x0 * 0.9, z0 * 0.9)
        bot1 = (x1 * 0.9, z1 * 0.9)
        quad(rock, (mid0[0], top - 9.0, mid0[1]), (mid1[0], top - 9.0, mid1[1]),
             (bot1[0], CLIFF_BOTTOM, bot1[1]), (bot0[0], CLIFF_BOTTOM, bot0[1]))
    # inner apron ring: plateau surface between building and rim
    for i in range(seg):
        (x0, z0), (x1, z1) = rim[i], rim[(i + 1) % seg]
        top = COURT_Y if (z0 < -28 and z1 < -28) else FLOOR_TOP
        in0 = (x0 * 0.42, z0 * 0.42)
        in1 = (x1 * 0.42, z1 * 0.42)
        f = quad(rock, (0.0, top - 0.02, 0.0), (in0[0], top, in0[1]),
                 (in1[0], top, in1[1]), None) if False else None
        vs = [rock.verts.new(G(0.0, top - 0.05, 0.0)),
              rock.verts.new(G(in0[0], top, in0[1])),
              rock.verts.new(G(in1[0], top, in1[1]))]
        try:
            f = rock.faces.new(vs)
            if f.normal.z < 0:
                f.normal_flip()
        except ValueError:
            pass
    # distant peaks — silhouette ring for the establishing shot
    for i in range(11):
        a = 2 * math.pi * i / 11 + 0.35
        r = 110 + 42 * math.sin(i * 2.7)
        h = 26 + 30 * abs(math.sin(i * 1.9 + 0.6))
        add_cone(rock, (math.cos(a) * r, CLIFF_BOTTOM, math.sin(a) * r),
                 22 + 8 * math.sin(i), 0.0, h, segments=7)


def build_arcades_and_elevation():
    light = bucket("cathedral_stone_light")
    mid = bucket("cathedral_stone_mid")
    void = bucket("cathedral_void")
    sap = bucket("cathedral_glass_sapphire")
    amb = bucket("cathedral_glass_amber")

    # free-standing clustered piers
    for z in BAY_ZS:
        for sx in (-1, 1):
            x = sx * NAVE_X
            add_box(mid, (x, FLOOR_TOP + 0.55, z), (2.5, 1.1, 2.5))
            add_box(light, (x, FLOOR_TOP + 1.1 + (PIER_CAP - 1.1) / 2, z),
                    (1.45, PIER_CAP - 1.1, 1.45))
            for (ox, oz) in [(0.95, 0), (-0.95, 0), (0, 0.95), (0, -0.95)]:
                add_cone(light, (x + ox, FLOOR_TOP + 1.1, z + oz), 0.30, 0.30,
                         PIER_CAP - 1.1, segments=9)
            add_box(mid, (x, FLOOR_TOP + PIER_CAP + 0.35, z), (2.3, 0.7, 2.3))
            # wall shaft riding up to the vault springing
            add_box(light, (x, FLOOR_TOP + PIER_CAP + 0.7 + (VAULT_SPRING - PIER_CAP - 0.7) / 2, z),
                    (0.9, VAULT_SPRING - PIER_CAP - 0.7, 0.9))

    # per-side elevation: arcade arches, triforium, clerestory
    for sx in (-1, 1):
        panel_n = (-1.0 if sx > 0 else 1.0, 0.0, 0.0)   # face the nave axis
        for b in range(len(BAY_EDGES) - 1):
            z0, z1 = BAY_EDGES[b], BAY_EDGES[b + 1]
            zc = (z0 + z1) / 2
            w = z1 - z0
            if w < 2.0:
                continue
            # arcade: the spandrel wall above the open arch between piers
            pan = Panel(bucket("cathedral_stone_light"),
                        (sx * NAVE_X, FLOOR_TOP, zc), (0, 0, 1), panel_n, 1.1)
            span = w - 1.45
            pan.arch_wall(0.0, span, 0.0, ARCADE_SPRING - FLOOR_TOP,
                          span * 0.866, -w / 2, w / 2, 0.0,
                          TRIF_LO - FLOOR_TOP)
            # triforium: three blind pointed arcades, dark voids behind
            band = Panel(bucket("cathedral_stone_mid"),
                         (sx * NAVE_X, TRIF_LO, zc), (0, 0, 1), panel_n, 0.9)
            n_open = 3
            pitch = w / n_open
            for k in range(n_open):
                uc = -w / 2 + pitch * (k + 0.5)
                band.arch_wall(uc, pitch * 0.58, 0.35, 1.7, pitch * 0.72,
                               uc - pitch / 2, uc + pitch / 2, 0.0,
                               TRIF_HI - TRIF_LO)
            add_box(void, (sx * (NAVE_X + 0.75), (TRIF_LO + TRIF_HI) / 2, zc),
                    (0.1, TRIF_HI - TRIF_LO, w))
            # clerestory: twin glazed lancets per bay
            cler = Panel(bucket("cathedral_stone_light"),
                         (sx * NAVE_X, CLER_SILL, zc), (0, 0, 1), panel_n, 0.85)
            for k in range(2):
                uc = -w / 4 + (w / 2) * k
                lspan = w * 0.26
                cler.arch_wall(uc, lspan, 0.4, CLER_TOP - CLER_SILL - 2.6,
                               lspan * 1.9, uc - w / 4, uc + w / 4, 0.0,
                               CLER_TOP - CLER_SILL)
                glass = sap if (b % 2 == 0) else amb
                arch_pane(glass, (sx * (NAVE_X - 0.1), CLER_SILL, zc),
                          (0, 0, 1), uc, lspan, 0.4,
                          0.4 + (CLER_TOP - CLER_SILL - 2.6), lspan * 1.9)
            # band between triforium top and clerestory sill
            add_box(light, (sx * NAVE_X, (TRIF_HI + CLER_SILL) / 2, zc),
                    (1.0, CLER_SILL - TRIF_HI, w))
            # wall head above the clerestory up to the eaves
            add_box(light, (sx * NAVE_X, (CLER_TOP + EAVE_Y) / 2, zc),
                    (0.95, EAVE_Y - CLER_TOP, w))
        # interior stringcourses
        for (yy, tt) in [(TRIF_LO - 0.15, 0.3), (CLER_SILL - 0.2, 0.28)]:
            add_box(mid, (sx * (NAVE_X - 0.62), yy, (WEST_Z + EAST_ARCH_Z) / 2),
                    (0.34, tt, EAST_ARCH_Z - WEST_Z))


def build_vault():
    """Quadripartite groin vault: two crossed pointed barrels per bay, ribs
    swept along the creases. Underside faces point DOWN into the nave."""
    web = bucket("cathedral_stone_mid")
    rib = bucket("cathedral_stone_dark")
    span_x = NAVE_X * 2
    rise = VAULT_APEX - VAULT_SPRING

    def barrel_x(x):
        pts = arch_pts(span_x, rise, 24)
        ax = max(-span_x / 2, min(span_x / 2, x))
        best = min(pts, key=lambda p: abs(p[0] - ax))
        return VAULT_SPRING + best[1]

    for b in range(len(BAY_EDGES) - 1):
        z0, z1 = BAY_EDGES[b], BAY_EDGES[b + 1]
        w = z1 - z0
        if w < 2.0:
            continue
        zc = (z0 + z1) / 2

        def barrel_z(z):
            pts = arch_pts(w, rise, 16)
            az = max(-w / 2, min(w / 2, z - zc))
            best = min(pts, key=lambda p: abs(p[0] - az))
            return VAULT_SPRING + best[1]

        def vy(x, z):
            return max(barrel_x(x), barrel_z(z))

        nx, nz = 16, 8
        for i in range(nx):
            for j in range(nz):
                x0 = -span_x / 2 + span_x * i / nx
                x1 = -span_x / 2 + span_x * (i + 1) / nx
                zz0 = z0 + w * j / nz
                zz1 = z0 + w * (j + 1) / nz
                f = quad(web, (x0, vy(x0, zz0), zz0), (x1, vy(x1, zz0), zz0),
                         (x1, vy(x1, zz1), zz1), (x0, vy(x0, zz1), zz1))
                if f is not None and f.normal.z > 0:
                    f.normal_flip()
        # ribs: transverse arch at each bay edge + the two diagonal creases
        tpts = [(u, VAULT_SPRING + v, z0)
                for (u, v) in arch_pts(span_x, rise, 12)]
        sweep_box(rib, tpts, 0.30, 0.38)
        for sgn in (-1, 1):
            dpts = []
            n = 14
            for i in range(n + 1):
                t = i / n
                x = -span_x / 2 + span_x * t
                z = z0 + w * (t if sgn > 0 else 1 - t)
                dpts.append((x, vy(x, z) - 0.05, z))
            sweep_box(rib, dpts, 0.22, 0.30)
    # final transverse at the last edge + longitudinal ridge
    tpts = [(u, VAULT_SPRING + v, BAY_EDGES[-1])
            for (u, v) in arch_pts(span_x, rise, 12)]
    sweep_box(rib, tpts, 0.30, 0.38)
    sweep_box(rib, [(0.0, VAULT_APEX - 0.05, WEST_Z),
                    (0.0, VAULT_APEX - 0.05, EAST_ARCH_Z)], 0.26, 0.30)


def build_aisles():
    light = bucket("cathedral_stone_light")
    mid = bucket("cathedral_stone_mid")
    amb = bucket("cathedral_glass_amber")
    slate = bucket("cathedral_slate")
    for sx in (-1, 1):
        n_out = (1.0 if sx > 0 else -1.0, 0.0, 0.0)
        for b in range(len(BAY_EDGES) - 1):
            z0, z1 = BAY_EDGES[b], BAY_EDGES[b + 1]
            w = z1 - z0
            if w < 2.0:
                continue
            zc = (z0 + z1) / 2
            pan = Panel(light, (sx * AISLE_X, FLOOR_TOP, zc), (0, 0, 1),
                        n_out, 0.9)
            span = w * 0.40
            pan.arch_wall(0.0, span, 4.2 - FLOOR_TOP, 9.6 - FLOOR_TOP,
                          span * 1.25, -w / 2, w / 2, 0.0,
                          AISLE_WALL_TOP - FLOOR_TOP)
            arch_pane(amb, (sx * (AISLE_X - 0.05), FLOOR_TOP, zc), (0, 0, 1),
                      0.0, span, 4.2 - FLOOR_TOP, 9.6 - FLOOR_TOP,
                      span * 1.25)
        # lean-to roof from the aisle wall up to the clerestory sill
        for (xa, ya, xb, yb) in [(sx * (AISLE_X + 0.7), AISLE_WALL_TOP + 0.4,
                                  sx * (NAVE_X + 0.2), CLER_SILL - 0.3)]:
            f = quad(slate, (xa, ya, WEST_Z), (xb, yb, WEST_Z),
                     (xb, yb, EAST_ARCH_Z), (xa, ya, EAST_ARCH_Z))
            if f is not None and f.normal.z < 0:
                f.normal_flip()
        # aisle parapet band
        add_box(mid, (sx * AISLE_X, AISLE_WALL_TOP + 0.25,
                      (WEST_Z + EAST_ARCH_Z) / 2),
                (1.1, 0.5, EAST_ARCH_Z - WEST_Z))


def build_nave_roof():
    slate = bucket("cathedral_slate")
    rust = bucket("cathedral_copper_rust")
    light = bucket("cathedral_stone_light")
    mid = bucket("cathedral_stone_mid")
    for sx in (-1, 1):
        f = quad(slate, (sx * (NAVE_X + 1.2), EAVE_Y, WEST_Z),
                 (0.0, RIDGE_Y, WEST_Z), (0.0, RIDGE_Y, EAST_ARCH_Z),
                 (sx * (NAVE_X + 1.2), EAVE_Y, EAST_ARCH_Z))
        if f is not None and f.normal.z < 0:
            f.normal_flip()
    # gable end walls closing the roof at both ends (the first build showed
    # night sky through the open triangles above the facade)
    for gz, nz in [(WEST_Z + 0.3, -1.0), (EAST_ARCH_Z - 0.3, 1.0)]:
        gp = Panel(light, (0.0, 0.0, gz), (1, 0, 0), (0, 0, nz), 0.9)
        gp.face([(-(NAVE_X + 1.2), EAVE_Y - 0.1), ((NAVE_X + 1.2), EAVE_Y - 0.1),
                 (0.0, RIDGE_Y)], front=True)
        gp.face([(-(NAVE_X + 1.2), EAVE_Y - 0.1), ((NAVE_X + 1.2), EAVE_Y - 0.1),
                 (0.0, RIDGE_Y)], front=False)
    # ridge cresting: rust-iron spine with finial spikes
    add_box(rust, (0.0, RIDGE_Y + 0.18, (WEST_Z + EAST_ARCH_Z) / 2),
            (0.28, 0.36, EAST_ARCH_Z - WEST_Z))
    z = WEST_Z + 1.5
    while z < EAST_ARCH_Z - 1.0:
        add_cone(rust, (0.0, RIDGE_Y + 0.3, z), 0.14, 0.0, 0.85, segments=4)
        z += 2.6
    # eaves cornice + corbel table band under it (breaks the tall wall head)
    for sx in (-1, 1):
        add_box(light, (sx * (NAVE_X + 1.15), EAVE_Y - 0.2,
                        (WEST_Z + EAST_ARCH_Z) / 2),
                (0.9, 0.5, EAST_ARCH_Z - WEST_Z))
        add_box(mid, (sx * (NAVE_X + 0.62), EAVE_Y - 0.75,
                      (WEST_Z + EAST_ARCH_Z) / 2),
                (0.5, 0.35, EAST_ARCH_Z - WEST_Z))
        z = WEST_Z + 1.0
        while z < EAST_ARCH_Z - 0.5:
            add_box(mid, (sx * (NAVE_X + 0.55), EAVE_Y - 1.1, z),
                    (0.4, 0.45, 0.5))
            z += 1.3
    # crossing fleche riding the ridge above the gallery / apse arch
    base_y = RIDGE_Y - 1.4
    add_cone(mid, (0.0, base_y, EAST_ARCH_Z - 1.4), 2.6, 1.9, 3.2, segments=8)
    add_cone(rust, (0.0, base_y + 3.2, EAST_ARCH_Z - 1.4), 1.9, 0.02, 11.5,
             segments=8)
    for row in range(4):
        fy = base_y + 3.2 + 11.5 * (0.18 + 0.2 * row)
        fr = 1.9 * (1.0 - (0.18 + 0.2 * row)) + 0.1
        for a8 in range(8):
            aa = a8 * math.pi / 4
            add_box(rust, (fr * math.cos(aa), fy,
                           EAST_ARCH_Z - 1.4 + fr * math.sin(aa)),
                    (0.14, 0.2, 0.14), yaw=aa)
    add_cone(rust, (0.0, base_y + 14.7, EAST_ARCH_Z - 1.4), 0.16, 0.0, 1.0,
             segments=6)


def build_west_front():
    light = bucket("cathedral_stone_light")
    mid = bucket("cathedral_stone_mid")
    dark = bucket("cathedral_stone_dark")
    rust = bucket("cathedral_copper_rust")
    oak = bucket("cathedral_oak")
    slate = bucket("cathedral_slate")

    # facade wall between the towers, pierced by three portals + open rose
    pan = Panel(light, (0.0, FLOOR_TOP, WEST_Z), (1, 0, 0), (0, 0, -1), 1.3)
    band_top = 15.0 - FLOOR_TOP
    # centre portal (grand) + flanking portals — exact u-partition, no
    # coplanar overlaps: centre owns (-4.6, 4.6), sides own out to +-11.8
    pan.arch_wall(0.0, 5.4, 0.0, 6.2 - FLOOR_TOP, 6.1, -4.6, 4.6, 0.0,
                  band_top)
    pan.arch_wall(-7.4, 3.2, 0.0, 4.6 - FLOOR_TOP, 3.9, -11.8, -4.6, 0.0,
                  band_top)
    pan.arch_wall(7.4, 3.2, 0.0, 4.6 - FLOOR_TOP, 3.9, 4.6, 11.8, 0.0,
                  band_top)
    # wall above the portal band, around the open rose: four slabs
    rose_v = ROSE_WEST.y - FLOOR_TOP
    r_hole = ROSE_WEST_R + 0.15
    upper_top = 31.4 - FLOOR_TOP
    pan.slab(-11.8, band_top, -r_hole, upper_top)
    pan.slab(r_hole, band_top, 11.8, upper_top)
    if rose_v - r_hole > band_top + 0.02:
        pan.slab(-r_hole, band_top, r_hole, rose_v - r_hole)
    pan.slab(-r_hole, rose_v + r_hole, r_hole, upper_top)
    # square-to-round infill: 4 corner gussets closing the rose square
    seg = 24
    for corner in range(4):
        for i in range(seg // 4):
            a0 = corner * math.pi / 2 + math.pi / 4 + (math.pi / 2) * i / (seg // 4)
            a1 = corner * math.pi / 2 + math.pi / 4 + (math.pi / 2) * (i + 1) / (seg // 4)
            sq = lambda a: (r_hole * (1 if abs(math.cos(a)) < math.cos(math.pi / 4)
                                      else 1) * math.copysign(1, math.cos(a))
                            if False else 0)
            def sq_pt(a):
                ca, sa = math.cos(a), math.sin(a)
                m = max(abs(ca), abs(sa))
                return (r_hole * ca / m, r_hole * sa / m)
            (qx0, qy0), (qx1, qy1) = sq_pt(a0), sq_pt(a1)
            for front in (True, False):
                pan.face([(0 + qx0, rose_v + qy0), (qx1, rose_v + qy1),
                          (r_hole * math.cos(a1), rose_v + r_hole * math.sin(a1)),
                          (r_hole * math.cos(a0), rose_v + r_hole * math.sin(a0))],
                         front=front)
    # THE DRAGON DOOR — open wheel tracery, no glass
    rose_window(bucket("cathedral_stone_mid"), None,
                (ROSE_WEST.x, ROSE_WEST.y, ROSE_WEST.z), ROSE_WEST_R, 1.0,
                open_center=True, spokes=12)
    # portal archivolts + gables + doors
    for (uc, span, spring) in [(0.0, 5.4, 6.2), (-7.4, 3.2, 4.6), (7.4, 3.2, 4.6)]:
        rise = span * (6.1 / 5.4) if span > 4 else 3.9
        for k in range(3):
            grow = 0.32 * (k + 1)
            pts = [(uc + u, spring + v, WEST_Z - 0.65 - 0.30 * k)
                   for (u, v) in arch_pts(span + grow * 2, rise + grow, 12)]
            sweep_box(mid, pts, 0.17, 0.26)
        # gable
        gb = spring + rise + 1.1
        gt = gb + (2.6 if span > 3 else 1.7)
        gw = span / 2 + 1.5
        gp = Panel(mid, (uc, 0.0, WEST_Z - 0.75), (1, 0, 0), (0, 0, -1), 0.5)
        gp.face([(-gw, gb), (gw, gb), (0.0, gt)], front=True)
        gp.face([(-gw, gb), (gw, gb), (0.0, gt)], front=False)
        add_cone(rust, (uc, gt - 0.1, WEST_Z - 0.8), 0.12, 0.0, 1.0, segments=4)
        # oak doors with rust strap-hinges, recessed
        add_box(oak, (uc, FLOOR_TOP + spring * 0.45, WEST_Z + 0.28),
                (span * 0.86, spring * 0.9, 0.24))
        for hy in (0.3, 0.55, 0.8):
            add_box(rust, (uc, FLOOR_TOP + spring * 0.9 * hy, WEST_Z + 0.12),
                    (span * 0.78, 0.12, 0.06))
    # jamb colonnettes flanking the centre portal
    for su in (-1, 1):
        for k in range(3):
            add_cone(dark, (su * (2.9 + 0.42 * k), FLOOR_TOP,
                            WEST_Z - 0.5 - 0.3 * k), 0.17, 0.17, 6.0, segments=8)
    # string course over the portal band + facade parapet + centre gable
    add_box(mid, (0.0, 15.1, WEST_Z), (23.6, 0.55, 1.6))
    add_box(mid, (0.0, 31.7, WEST_Z), (23.6, 0.8, 1.5))
    gpan = Panel(light, (0.0, 0.0, WEST_Z), (1, 0, 0), (0, 0, -1), 1.1)
    gpan.face([(-8.6, 32.0), (8.6, 32.0), (0.0, 38.6)], front=True)
    gpan.face([(-8.6, 32.0), (8.6, 32.0), (0.0, 38.6)], front=False)
    add_cone(rust, (0.0, 38.5, WEST_Z), 0.15, 0.0, 1.3, segments=4)
    # blind lancet niches flanking the rose (break the big upper wall)
    for su in (-1, 1):
        np_ = Panel(mid, (su * 9.2, 16.0, WEST_Z - 0.68), (1, 0, 0),
                    (0, 0, -1), 0.25)
        np_.arch_wall(0.0, 1.3, 0.4, 6.4, 2.1, -1.1, 1.1, 0.0, 9.6)

    # ── twin towers ──
    for sx in (-1, 1):
        x = sx * TOWER_X
        add_box(light, (x, (FLOOR_TOP + TOWER_S1) / 2, TOWER_Z),
                (8.4, TOWER_S1 - FLOOR_TOP, 8.4))
        add_box(mid, (x, (TOWER_S1 + TOWER_S2) / 2, TOWER_Z),
                (7.4, TOWER_S2 - TOWER_S1, 7.4))
        add_box(light, (x, (TOWER_S2 + TOWER_S3) / 2, TOWER_Z),
                (6.6, TOWER_S3 - TOWER_S2, 6.6))
        # stepped corner buttresses hugging the base stage
        for (cx, cz) in [(-4.2, -4.2), (-4.2, 4.2), (4.2, -4.2), (4.2, 4.2)]:
            for (step_h, step_w) in [(9.0, 1.7), (16.0, 1.35), (TOWER_S1, 1.0)]:
                add_box(mid, (x + cx, (FLOOR_TOP + step_h) / 2, TOWER_Z + cz),
                        (step_w, step_h - FLOOR_TOP, step_w))
        # cornice bands at each stage
        for yy in (TOWER_S1, TOWER_S2, TOWER_S3):
            shrink = 0.0 if yy <= TOWER_S1 else 1.2
            add_box(dark, (x, yy, TOWER_Z), (8.9 - shrink, 0.6, 8.9 - shrink))
        # belfry openings: paired open lancets on all four faces (dark voids)
        for face in range(4):
            a = face * math.pi / 2
            nx_, nz_ = math.cos(a), math.sin(a)
            lat = (-math.sin(a), 0.0, math.cos(a))
            bp = Panel(bucket("cathedral_stone_mid"),
                       (x + nx_ * 3.3, TOWER_S2 + 0.6, TOWER_Z + nz_ * 3.3),
                       lat, (nx_, 0.0, nz_), 0.7)
            for su in (-1, 1):
                bp.arch_wall(su * 1.5, 1.6, 0.4, 4.6, 2.6, su * 1.5 - 1.55,
                             su * 1.5 + 1.55, 0.0, 7.0)
            add_box(bucket("cathedral_void"),
                    (x + nx_ * 2.6, TOWER_S2 + 4.0, TOWER_Z + nz_ * 2.6),
                    (abs(lat[0]) * 5.2 + 0.15, 6.4, abs(lat[2]) * 5.2 + 0.15))
        # gallery-stage lancets (glazed sapphire, tall and paired) + lower
        # stage windows on the west face
        for su in (-1, 1):
            gp2 = Panel(bucket("cathedral_stone_light"),
                        (x, TOWER_S1 + 1.5, TOWER_Z - 3.75), (1, 0, 0),
                        (0, 0, -1), 0.6)
            gp2.arch_wall(su * 1.7, 1.7, 0.4, 6.4, 2.8, su * 1.7 - 1.75,
                          su * 1.7 + 1.75, 0.0, 9.5)
            arch_pane(bucket("cathedral_glass_sapphire"),
                      (x, TOWER_S1 + 1.5, TOWER_Z - 3.7), (1, 0, 0),
                      su * 1.7, 1.7, 0.4, 6.4, 2.8)
        for (fy, fh) in [(5.0, 7.0), (13.5, 6.0)]:
            wp = Panel(bucket("cathedral_stone_mid"),
                       (x, fy, TOWER_Z - 4.25), (1, 0, 0), (0, 0, -1), 0.5)
            wp.arch_wall(0.0, 1.9, 0.3, fh - 2.2, 2.4, -1.6, 1.6, 0.0, fh)
        # corner pinnacles + octagonal needle spire with crockets
        for (cx, cz) in [(-2.9, -2.9), (-2.9, 2.9), (2.9, -2.9), (2.9, 2.9)]:
            pinnacle(bucket("cathedral_stone_light"),
                     (x + cx, TOWER_S3, TOWER_Z + cz), 1.1, 2.2, 4.4)
        add_cone(slate, (x, TOWER_S3, TOWER_Z), 3.3, 0.03,
                 SPIRE_TIP - TOWER_S3, segments=8)
        for row in range(5):
            fy = TOWER_S3 + (SPIRE_TIP - TOWER_S3) * (0.14 + 0.17 * row)
            fr = 3.3 * (1.0 - (0.14 + 0.17 * row)) + 0.12
            for a8 in range(8):
                aa = a8 * math.pi / 4 + math.pi / 8
                add_box(bucket("cathedral_stone_light"),
                        (x + fr * math.cos(aa), fy, TOWER_Z + fr * math.sin(aa)),
                        (0.18, 0.26, 0.18), yaw=aa)
        add_cone(rust, (x, SPIRE_TIP, TOWER_Z), 0.14, 0.0, 1.2, segments=6)


def build_east_end():
    """Apse arch wall with the Wyrm's Gallery, chevet with the ember rose."""
    light = bucket("cathedral_stone_light")
    mid = bucket("cathedral_stone_mid")
    dark = bucket("cathedral_stone_dark")
    ember = bucket("cathedral_glass_ember")
    amb = bucket("cathedral_glass_amber")
    slate = bucket("cathedral_slate")

    # the great apse arch wall (nave side face at z = EAST_ARCH_Z)
    pan = Panel(light, (0.0, FLOOR_TOP, EAST_ARCH_Z), (1, 0, 0), (0, 0, -1), 1.3)
    pan.arch_wall(0.0, 15.0, 0.0, 12.0 - FLOOR_TOP, 12.0, -NAVE_X, NAVE_X,
                  0.0, EAVE_Y - FLOOR_TOP)

    # THE WYRM'S GALLERY — corbelled ledge over the arch impost
    slab_y = GALLERY_TOP - 0.5
    add_box(mid, (0.0, slab_y + 0.25, (GALLERY_FRONT_Z + GALLERY_BACK_Z) / 2),
            (GALLERY_HALF_W * 2, 0.5, GALLERY_BACK_Z - GALLERY_FRONT_Z))
    for cx in (-3.7, -1.25, 1.25, 3.7):
        add_box(dark, (cx, slab_y - 0.5, GALLERY_FRONT_Z + 0.45),
                (0.6, 1.0, 0.9))
        add_box(dark, (cx, slab_y - 1.15, GALLERY_FRONT_Z + 0.7),
                (0.45, 0.45, 0.5))
    balustrade(bucket("cathedral_stone_mid"),
               (-GALLERY_HALF_W + 0.2, GALLERY_TOP, GALLERY_FRONT_Z + 0.25),
               (GALLERY_HALF_W - 0.2, GALLERY_TOP, GALLERY_FRONT_Z + 0.25),
               height=0.8, gap_center=2.6)
    for sx in (-1, 1):
        balustrade(bucket("cathedral_stone_mid"),
                   (sx * (GALLERY_HALF_W - 0.1), GALLERY_TOP, GALLERY_FRONT_Z + 0.35),
                   (sx * (GALLERY_HALF_W - 0.1), GALLERY_TOP, GALLERY_BACK_Z - 0.2),
                   height=0.8)
    # candle crowns flanking the wyrm's step — the emissive markers that draw
    # the eye to the perch from the board (no lights, authored glow only)
    iron = bucket("cathedral_iron")
    candle = bucket("cathedral_candle")
    for sx in (-1, 1):
        cx = sx * 3.1
        add_cone(iron, (cx, GALLERY_TOP, GALLERY_FRONT_Z + 0.6), 0.09, 0.07,
                 1.15, segments=6)
        add_cone(iron, (cx, GALLERY_TOP + 1.15, GALLERY_FRONT_Z + 0.6), 0.22,
                 0.22, 0.08, segments=8)
        for k in range(5):
            a = 2 * math.pi * k / 5
            add_cone(candle, (cx + 0.16 * math.cos(a), GALLERY_TOP + 1.23,
                              GALLERY_FRONT_Z + 0.6 + 0.16 * math.sin(a)),
                     0.035, 0.015, 0.16, segments=5)

    # apse walls: two angled flanks + flat chevet with the ember rose
    for sx in (-1, 1):
        a0 = Vector((sx * 10.5, 0.0, EAST_ARCH_Z))
        a1 = Vector((sx * 5.4, 0.0, CHEVET_Z))
        run = (a1 - a0)
        lat = run.normalized()
        n_out = Vector((lat.z * sx, 0.0, -lat.x * sx))
        n_out = Vector((sx * 1.0, 0.0, 0.35)).normalized()
        c = (a0 + a1) / 2
        p = Panel(light, (c.x, FLOOR_TOP, c.z), (lat.x, 0, lat.z),
                  (n_out.x, 0, n_out.z), 1.0)
        L = run.length
        p.arch_wall(0.0, 2.4, 6.0 - FLOOR_TOP, 15.0 - FLOOR_TOP, 4.6,
                    -L / 2, L / 2, 0.0, 26.0 - FLOOR_TOP)
        arch_pane(amb, (c.x, FLOOR_TOP, c.z), (lat.x, 0, lat.z), 0.0, 2.4,
                  6.0 - FLOOR_TOP, 15.0 - FLOOR_TOP, 4.6)
    chev = Panel(light, (0.0, FLOOR_TOP, CHEVET_Z), (1, 0, 0), (0, 0, 1), 1.2)
    rose_v = ROSE_EAST.y - FLOOR_TOP
    r_hole = ROSE_EAST_R + 0.15
    chev.slab(-5.6, 0.0, 5.6, rose_v - r_hole)
    chev.slab(-5.6, rose_v + r_hole, 5.6, 28.4 - FLOOR_TOP)
    chev.slab(-5.6, rose_v - r_hole, -r_hole + 1.4, rose_v + r_hole)
    chev.slab(r_hole - 1.4, rose_v - r_hole, 5.6, rose_v + r_hole)
    rose_window(bucket("cathedral_stone_mid"), ember,
                (ROSE_EAST.x, ROSE_EAST.y, ROSE_EAST.z - 0.1), ROSE_EAST_R,
                0.9, open_center=False, spokes=12)
    # apse roof: sloped cap from the flank walls up toward the nave ridge
    f = quad(slate, (-10.5, 26.0, EAST_ARCH_Z), (10.5, 26.0, EAST_ARCH_Z),
             (5.4, 26.0, CHEVET_Z), (-5.4, 26.0, CHEVET_Z))
    if f is not None and f.normal.z < 0:
        f.normal_flip()
    for sx in (-1, 1):
        f = quad(slate, (sx * 10.5, 26.0, EAST_ARCH_Z),
                 (sx * 5.4, 26.0, CHEVET_Z), (0.0, 32.5, CHEVET_Z - 4.0),
                 (0.0, 33.5, EAST_ARCH_Z))
        if f is not None and f.normal.z < 0:
            f.normal_flip()
    # radiating buttresses
    for (bx, bz, yaw) in [(-9.5, 20.0, 0.5), (9.5, 20.0, -0.5),
                          (-6.0, 25.5, 0.9), (6.0, 25.5, -0.9),
                          (0.0, 29.0, 0.0)]:
        add_box(mid, (bx * 1.25, (FLOOR_TOP + 16.0) / 2, bz + 1.5),
                (1.3, 16.0 - FLOOR_TOP, 1.9), yaw=yaw)
        pinnacle(bucket("cathedral_stone_light"), (bx * 1.25, 16.0, bz + 1.5),
                 1.0, 1.4, 3.2)


def build_buttresses():
    light = bucket("cathedral_stone_light")
    mid = bucket("cathedral_stone_mid")
    for z in BAY_ZS:
        for sx in (-1, 1):
            x = sx * (AISLE_X + 0.9)
            add_box(light, (x, (FLOOR_TOP + 16.0) / 2, z),
                    (1.7, 16.0 - FLOOR_TOP, 2.1))
            add_box(light, (x - sx * 0.25, 16.0 + 5.5, z), (1.3, 11.0, 1.7))
            add_box(mid, (x, 15.9, z), (2.2, 0.55, 2.6))
            pinnacle(light, (x - sx * 0.25, 27.0, z), 1.15, 1.8, 4.0)
            gargoyle(bucket("cathedral_stone_dark"), (x, 15.4, z), sx)
            # two flyer tiers arcing down from the clerestory wall
            for (y_hi, y_lo) in [(29.4, 24.6), (24.9, 20.5)]:
                pts = []
                n = 9
                for i in range(n + 1):
                    t = i / n
                    xx = sx * (NAVE_X + 0.4) + sx * (AISLE_X + 0.65 - NAVE_X - 0.4) * t
                    yy = y_hi + (y_lo - y_hi) * (t ** 1.6)
                    pts.append((xx, yy, z))
                sweep_box(mid, pts, 0.30, 0.5)
                # arched underside: a thin deeper sweep suggesting the flyer arch
                pts2 = [(px, py - 0.9 - 0.9 * math.sin(math.pi * i / n), pz)
                        for i, (px, py, pz) in enumerate(pts)]
                sweep_box(mid, pts2, 0.22, 0.22)


def build_organ_loft():
    """The west choir loft: balustraded tribune with the grand organ."""
    mid = bucket("cathedral_stone_mid")
    oak = bucket("cathedral_oak")
    brass = bucket("cathedral_brass")
    rust = bucket("cathedral_copper_rust")
    add_box(mid, (0.0, 6.8, -23.9), (16.4, 0.7, 4.4))
    for cx in (-6.5, -3.25, 0.0, 3.25, 6.5):
        add_box(mid, (cx, (FLOOR_TOP + 6.45) / 2, -23.0),
                (0.8, 6.45 - FLOOR_TOP, 0.8))
    balustrade(mid, (-8.0, 7.15, -21.9), (8.0, 7.15, -21.9), height=0.8)
    # organ case: centre tower + two flank towers + flats, all oak
    for (cx, w, top) in [(0.0, 4.2, 18.4), (-4.6, 3.2, 16.8), (4.6, 3.2, 16.8),
                         (-7.4, 1.9, 13.6), (7.4, 1.9, 13.6)]:
        add_box(oak, (cx, (7.2 + top) / 2, -24.8), (w, top - 7.2, 2.0))
        add_box(oak, (cx, top + 0.25, -24.8), (w + 0.5, 0.5, 2.4))
        if w > 2.5:
            add_cone(rust, (cx, top + 0.5, -24.8), w * 0.15, 0.0, 1.6,
                     segments=6)
    # pipe ranks: brass cylinders, tallest at each tower's centre
    for (cx, w, base, tallest) in [(0.0, 3.6, 8.6, 8.6), (-4.6, 2.7, 8.6, 7.0),
                                   (4.6, 2.7, 8.6, 7.0), (-7.4, 1.6, 8.6, 4.2),
                                   (7.4, 1.6, 8.6, 4.2)]:
        n = int(w / 0.30)
        for i in range(n):
            fx = cx - w / 2 + w * (i + 0.5) / n
            d = abs(fx - cx) / (w / 2)
            h = tallest * (1.0 - 0.42 * d)
            add_cone(brass, (fx, base, -23.75), 0.115, 0.105, h, segments=8)


def build_chandeliers():
    # Three wheels on the nave axis at y 14.2 — ABOVE the orbit camera's
    # sweep (the gameplay camera rides a ring at y ~9, climbing to ~13 at
    # full pitch: the first build hung one wheel straight through the lens)
    # and spaced as slalom gates for the dragon's nave run.
    iron = bucket("cathedral_iron")
    candle = bucket("cathedral_candle")
    for z in (-8.0, 0.0, 8.0):
        y = 14.2
        seg = 14
        ring = [(2.1 * math.cos(2 * math.pi * i / seg), y,
                 z + 2.1 * math.sin(2 * math.pi * i / seg))
                for i in range(seg + 1)]
        sweep_box(iron, ring, 0.09, 0.06)
        for k in range(3):
            a = 2 * math.pi * k / 3 + 0.5
            sweep_box(iron, [(0.0, y + 2.0, z),
                             (1.9 * math.cos(a), y + 0.15, z + 1.9 * math.sin(a))],
                      0.04, 0.04)
        sweep_box(iron, [(0.0, y + 1.6, z), (0.0, VAULT_APEX - 0.6, z)],
                  0.05, 0.05)
        for i in range(10):
            a = 2 * math.pi * i / 10
            cx, cz = 2.1 * math.cos(a), z + 2.1 * math.sin(a)
            add_cone(iron, (cx, y + 0.05, cz), 0.05, 0.05, 0.16, segments=6)
            add_cone(candle, (cx, y + 0.21, cz), 0.045, 0.02, 0.16, segments=6)


# ── vertex-colour AO + grime ─────────────────────────────────────────────────


def vnoise(x, y, z):
    """Cheap deterministic value noise in [0, 1]."""
    return 0.5 + 0.5 * math.sin(x * 12.9898 + y * 78.233 + z * 37.719)


def bake_ao(objects, samples=24):
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = samples
    scene.render.bake.target = 'VERTEX_COLORS'
    for obj in objects:
        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.bake(type='AO')


def apply_grime(obj):
    """Multiply the baked AO with height grime, streaking and jitter."""
    mesh = obj.data
    attr = mesh.color_attributes.get("Col")
    if attr is None:
        return
    for li, loop in enumerate(mesh.loops):
        v = mesh.vertices[loop.vertex_index].co  # blender space
        gx, gy, gz = v.x, v.z, -v.y              # back to godot axes
        f = 1.0
        if gy < 2.2:
            f *= 0.72 + 0.127 * max(gy, 0.0)
        f *= 0.88 + 0.12 * vnoise(gx * 0.7, gy * 0.23, gz * 0.7)
        f *= 0.97 + 0.06 * vnoise(gx * 3.1, gy * 3.7, gz * 3.1)
        c = attr.data[li].color
        ao = c[0] ** 1.35
        val = max(0.06, min(1.0, ao * f))
        attr.data[li].color = (val, val, val, 1.0)


# ── materials / export ───────────────────────────────────────────────────────


def make_material(name):
    base, rough, metal, emit, strength, _ao = MAT_SPECS[name]
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs['Base Color'].default_value = base
    bsdf.inputs['Roughness'].default_value = rough
    bsdf.inputs['Metallic'].default_value = metal
    if emit is not None:
        bsdf.inputs['Emission Color'].default_value = (*emit, 1.0)
        bsdf.inputs['Emission Strength'].default_value = strength
    return mat


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    do_ao = "--no-ao" not in argv
    out_path = None
    if "--out" in argv:
        out_path = argv[argv.index("--out") + 1]
    if out_path is None:
        import os
        here = os.path.dirname(os.path.abspath(__file__))
        out_path = os.path.normpath(os.path.join(
            here, "..", "..", "assets", "environment", "sanctum_cathedral.glb"))

    bpy.ops.wm.read_factory_settings(use_empty=True)

    build_floor_and_crag()
    build_arcades_and_elevation()
    build_vault()
    build_aisles()
    build_nave_roof()
    build_west_front()
    build_east_end()
    build_buttresses()
    build_organ_loft()
    build_chandeliers()

    ao_objects = []
    total_tris = 0
    for name, bm in BUCKETS.items():
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
        mesh = bpy.data.meshes.new(name + "_mesh")
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        obj.data.materials.append(make_material(name))
        tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
        total_tris += tris
        print(f"[cathedral] {name:28s} tris={tris}")
        if MAT_SPECS[name][5]:
            attr = mesh.color_attributes.new(name="Col", type='BYTE_COLOR',
                                             domain='CORNER')
            mesh.color_attributes.active_color = attr
            for d in attr.data:
                d.color = (1.0, 1.0, 1.0, 1.0)
            ao_objects.append(obj)
    print(f"[cathedral] TOTAL tris={total_tris}")

    if do_ao and ao_objects:
        print(f"[cathedral] baking AO on {len(ao_objects)} objects…")
        bake_ao(ao_objects)
        for obj in ao_objects:
            apply_grime(obj)
        print("[cathedral] AO + grime baked into COLOR_0")
    else:
        for obj in ao_objects:
            apply_grime(obj)
        print("[cathedral] AO SKIPPED (--no-ao) — grime only")

    export_kwargs = dict(filepath=out_path, export_format='GLB',
                         use_selection=False, export_apply=True)
    try:
        bpy.ops.export_scene.gltf(**export_kwargs, export_vertex_color='ACTIVE')
    except TypeError:
        bpy.ops.export_scene.gltf(**export_kwargs)
    print(f"[cathedral] exported {out_path}")
    print("[cathedral] verify with: python3 tools/blender/glb_stats.py "
          + out_path)


if __name__ == "__main__":
    main()
