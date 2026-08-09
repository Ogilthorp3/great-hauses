#!/usr/bin/env python3
"""pck_list.py — list the contents of a Godot 4 .pck, standalone OR embedded in an executable.

Why this exists: an export preset's include/exclude filters are a *claim* about what
ships. This tool turns that claim into evidence — it parses the real shipped artifact
and prints exactly which res:// paths are inside it.

Usage:
    python3 pck_list.py <artifact> [--grep SUBSTR] [--count-only] [--assert-present P]...
                                   [--assert-absent P]...

<artifact> may be:
  * a standalone GreatHauses.pck
  * a Windows GreatHauses.exe with binary_format/embed_pck=true
  * a macOS .app bundle (the .pck inside Contents/Resources is found automatically)

Exit codes: 0 all assertions held · 1 an assertion failed · 2 could not parse a pck.

Godot PCK layout, for the next person (verified by hexdump against a real 4.7.1 export):
  embedded:   [exe][GDPC magic][header][data...][index][u64 pck_size][GDPC magic]
              -- so the header starts at EOF-12-pck_size.
  header:     magic u32 | format u32 | engine maj/min/patch u32 x3 | pack_flags u32
              | file_base u64 | (format>=3: index_offset u64) | reserved u32 x16
  index:      file_count u32, then per file:
              path_len u32 | path bytes (NUL-padded) | offset u64 | size u64 | md5 16B | flags u32

  Format 2 (Godot 4.0-4.3) keeps the index inline right after the reserved block.
  Format 4 (Godot 4.7) moves the index to the tail and points at it from header+32.
  Paths in format 4 are stored WITHOUT the "res://" prefix; we re-add it for readability.
"""

import argparse
import os
import struct
import sys

PACK_MAGIC = 0x43504447  # "GDPC" little-endian


class PckError(Exception):
    pass


def _resolve_artifact(path):
    """A .app bundle is a directory — dig out the .pck Godot put in Contents/Resources."""
    if os.path.isdir(path) and path.endswith(".app"):
        res = os.path.join(path, "Contents", "Resources")
        if os.path.isdir(res):
            pcks = [f for f in os.listdir(res) if f.endswith(".pck")]
            if len(pcks) == 1:
                return os.path.join(res, pcks[0])
            if len(pcks) > 1:
                raise PckError("%d .pck files in %s — ambiguous" % (len(pcks), res))
        raise PckError("no .pck inside bundle %s" % path)
    return path


def _find_header_offset(f, size):
    """Return the byte offset of the GDPC header (0 for standalone, computed for embedded)."""
    f.seek(0)
    if len(f.read(4)) == 4:
        f.seek(0)
        if struct.unpack("<I", f.read(4))[0] == PACK_MAGIC:
            return 0
    # Embedded: trailer is [u64 pck_size][u32 magic] at EOF.
    if size < 12:
        raise PckError("file too small to contain a pck trailer")
    f.seek(size - 4)
    if struct.unpack("<I", f.read(4))[0] != PACK_MAGIC:
        raise PckError("no GDPC magic at start or end — not a pck / not an embedded-pck binary")
    f.seek(size - 12)
    pck_size = struct.unpack("<Q", f.read(8))[0]
    header = size - 12 - pck_size
    if header < 0 or header >= size:
        raise PckError("implausible embedded pck size %d in a %d-byte file" % (pck_size, size))
    f.seek(header)
    if struct.unpack("<I", f.read(4))[0] != PACK_MAGIC:
        raise PckError("computed embedded-pck header offset %d has no GDPC magic" % header)
    return header


def read_pck(path):
    """-> (list of (res_path, size), info dict). Raises PckError on anything unparseable."""
    path = _resolve_artifact(path)
    size = os.path.getsize(path)
    with open(path, "rb") as f:
        header = _find_header_offset(f, size)
        f.seek(header + 4)  # past magic
        fmt_version = struct.unpack("<I", f.read(4))[0]
        ver = struct.unpack("<III", f.read(12))  # engine major, minor, patch
        if fmt_version not in (2, 3, 4):
            raise PckError("unsupported pck format version %d (this tool handles 2, 3 and 4)"
                           % fmt_version)
        pack_flags = struct.unpack("<I", f.read(4))[0]
        _file_base = struct.unpack("<Q", f.read(8))[0]
        if fmt_version >= 3:
            # Index lives at the tail; the header only points at it.
            index_offset = struct.unpack("<Q", f.read(8))[0]
            f.seek(header + index_offset)
        else:
            f.read(16 * 4)  # reserved block, index follows inline
        file_count = struct.unpack("<I", f.read(4))[0]
        if file_count > 5_000_000:
            raise PckError("implausible file_count %d — header layout not understood"
                           % file_count)

        entries = []
        for i in range(file_count):
            head = f.read(4)
            if len(head) < 4:
                raise PckError("index truncated at entry %d of %d" % (i, file_count))
            path_len = struct.unpack("<I", head)[0]
            raw = f.read(path_len)
            _offset = struct.unpack("<Q", f.read(8))[0]
            fsize = struct.unpack("<Q", f.read(8))[0]
            f.read(16)  # md5
            struct.unpack("<I", f.read(4))[0]  # per-file flags
            rp = raw.rstrip(b"\0").decode("utf-8", "replace")
            if not rp.startswith("res://"):  # format 4 drops the scheme
                rp = "res://" + rp.lstrip("/")
            entries.append((rp, fsize))

    info = {
        "artifact": path,
        "artifact_size": size,
        "embedded": header != 0,
        "header_offset": header,
        "engine_version": "%d.%d.%d" % ver,
        "encrypted_index": bool(pack_flags & 1),
        "file_count": file_count,
    }
    return entries, info


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("artifact")
    ap.add_argument("--grep", default=None, help="only show paths containing SUBSTR")
    ap.add_argument("--count-only", action="store_true")
    ap.add_argument("--assert-present", action="append", default=[], metavar="SUBSTR",
                    help="fail unless at least one path contains SUBSTR (repeatable)")
    ap.add_argument("--assert-absent", action="append", default=[], metavar="SUBSTR",
                    help="fail if any path contains SUBSTR (repeatable)")
    args = ap.parse_args()

    try:
        entries, info = read_pck(args.artifact)
    except (PckError, OSError) as e:
        print("ERROR: %s" % e, file=sys.stderr)
        return 2

    total = sum(s for _, s in entries)
    print("artifact : %s" % info["artifact"])
    print("size     : %.1f MiB  (pck %s at offset %d)"
          % (info["artifact_size"] / 1048576.0,
             "EMBEDDED" if info["embedded"] else "standalone", info["header_offset"]))
    print("engine   : %s   files: %d   payload: %.1f MiB"
          % (info["engine_version"], info["file_count"], total / 1048576.0))
    print()

    if not args.count_only:
        for p, s in sorted(entries):
            if args.grep and args.grep not in p:
                continue
            print("  %10d  %s" % (s, p))
        print()

    rc = 0
    for needle in args.assert_present:
        hit = any(needle in p for p, _ in entries)
        print("ASSERT present %-46s %s" % (needle, "OK" if hit else "*** MISSING ***"))
        if not hit:
            rc = 1
    for needle in args.assert_absent:
        bad = [p for p, _ in entries if needle in p]
        print("ASSERT absent  %-46s %s" % (needle, "OK" if not bad else
                                           "*** %d LEAKED e.g. %s ***" % (len(bad), bad[0])))
        if bad:
            rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
