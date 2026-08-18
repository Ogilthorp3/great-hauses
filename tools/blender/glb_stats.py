#!/usr/bin/env python3
"""glb_stats.py — validate a GLB from disk: per-mesh tris, world AABB, materials.

Pure Python (no Blender). Coordinates reported are glTF space, which Godot
imports unchanged (both are right-handed Y-up) — so the AABB printed here IS
the Godot-space AABB. This is the reproducible observation every cathedral
export must cite before it ships: a Y-up/Z-up axis scramble shows up here as
an impossible bounding box, not as a vague "looks wrong in engine".

Usage: python3 glb_stats.py <file.glb>
"""
import json
import struct
import sys


def read_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, _version, _length = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67:
        raise SystemExit(f"{path}: not a GLB (magic {magic:#x})")
    offset = 12
    doc, blob = None, b""
    while offset < len(data):
        chunk_len, chunk_type = struct.unpack_from("<II", data, offset)
        chunk = data[offset + 8:offset + 8 + chunk_len]
        if chunk_type == 0x4E4F534A:  # JSON
            doc = json.loads(chunk)
        elif chunk_type == 0x004E4942:  # BIN
            blob = chunk
        offset += 8 + chunk_len
    return doc, blob


def accessor_minmax(doc, idx):
    acc = doc["accessors"][idx]
    return acc.get("min"), acc.get("max"), acc.get("count", 0)


def node_world_transforms(doc):
    """node index -> 4x4 column-major world matrix (TRS or matrix)."""
    import math

    def local_matrix(node):
        if "matrix" in node:
            return node["matrix"]
        t = node.get("translation", [0, 0, 0])
        r = node.get("rotation", [0, 0, 0, 1])
        s = node.get("scale", [1, 1, 1])
        x, y, z, w = r
        rot = [
            1 - 2 * (y * y + z * z), 2 * (x * y + z * w), 2 * (x * z - y * w),
            2 * (x * y - z * w), 1 - 2 * (x * x + z * z), 2 * (y * z + x * w),
            2 * (x * z + y * w), 2 * (y * z - x * w), 1 - 2 * (x * x + y * y),
        ]
        m = [
            rot[0] * s[0], rot[1] * s[0], rot[2] * s[0], 0,
            rot[3] * s[1], rot[4] * s[1], rot[5] * s[1], 0,
            rot[6] * s[2], rot[7] * s[2], rot[8] * s[2], 0,
            t[0], t[1], t[2], 1,
        ]
        return m

    def mul(a, b):
        out = [0.0] * 16
        for c in range(4):
            for r in range(4):
                out[c * 4 + r] = sum(a[k * 4 + r] * b[c * 4 + k] for k in range(4))
        return out

    world = {}

    def walk(idx, parent):
        node = doc["nodes"][idx]
        m = mul(parent, local_matrix(node)) if parent else local_matrix(node)
        world[idx] = m
        for child in node.get("children", []):
            walk(child, m)

    scene = doc["scenes"][doc.get("scene", 0)]
    ident = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    for root in scene["nodes"]:
        walk(root, ident)
    return world


def xform_point(m, p):
    return [
        m[0] * p[0] + m[4] * p[1] + m[8] * p[2] + m[12],
        m[1] * p[0] + m[5] * p[1] + m[9] * p[2] + m[13],
        m[2] * p[0] + m[6] * p[1] + m[10] * p[2] + m[14],
    ]


def main(path):
    doc, _blob = read_glb(path)
    world = node_world_transforms(doc)
    mats = doc.get("materials", [])
    print(f"== {path}")
    print(f"materials ({len(mats)}):")
    for m in mats:
        pbr = m.get("pbrMetallicRoughness", {})
        emiss = m.get("emissiveFactor", [0, 0, 0])
        strength = m.get("extensions", {}).get(
            "KHR_materials_emissive_strength", {}).get("emissiveStrength", 1.0)
        tag = " EMISSIVE(%.1f)" % strength if max(emiss) > 0 else ""
        base = pbr.get("baseColorFactor", [1, 1, 1, 1])
        print(f"  {m.get('name', '?'):34s} base=({base[0]:.2f},{base[1]:.2f},{base[2]:.2f})"
              f" rough={pbr.get('roughnessFactor', 1):.2f} metal={pbr.get('metallicFactor', 1):.2f}{tag}")

    total_tris = 0
    total_verts = 0
    aabb_min = [1e30] * 3
    aabb_max = [-1e30] * 3
    print("meshes:")
    for idx, m in world.items():
        node = doc["nodes"][idx]
        if "mesh" not in node:
            continue
        mesh = doc["meshes"][node["mesh"]]
        tris = 0
        verts = 0
        has_color = False
        for prim in mesh["primitives"]:
            if "indices" in prim:
                _, _, count = accessor_minmax(doc, prim["indices"])
                tris += count // 3
            pos = prim["attributes"].get("POSITION")
            if pos is not None:
                pmin, pmax, pcount = accessor_minmax(doc, pos)
                verts += pcount
                if pmin and pmax:
                    for corner in range(8):
                        p = [pmin[0] if corner & 1 else pmax[0],
                             pmin[1] if corner & 2 else pmax[1],
                             pmin[2] if corner & 4 else pmax[2]]
                        wp = xform_point(m, p)
                        for a in range(3):
                            aabb_min[a] = min(aabb_min[a], wp[a])
                            aabb_max[a] = max(aabb_max[a], wp[a])
            if "COLOR_0" in prim["attributes"]:
                has_color = True
        total_tris += tris
        total_verts += verts
        name = mesh.get("name", node.get("name", "?"))
        print(f"  {name:34s} tris={tris:8d} verts={verts:7d}"
              f"{'  COLOR_0' if has_color else ''}")
    print(f"TOTAL tris={total_tris} verts={total_verts}")
    print("world AABB (glTF == Godot space):")
    print(f"  x [{aabb_min[0]:8.2f} .. {aabb_max[0]:8.2f}]")
    print(f"  y [{aabb_min[1]:8.2f} .. {aabb_max[1]:8.2f}]   (up)")
    print(f"  z [{aabb_min[2]:8.2f} .. {aabb_max[2]:8.2f}]")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    main(sys.argv[1])
