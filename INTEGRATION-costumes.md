# INTEGRATION — House Costumes + Piece Readability + Banner-Rook

Module landed 2026-08-08. Owner files: `src/board/piece_view.gd`,
`src/board/piece_assets.gd`, `src/board/costume_preview.gd`,
`src/board/pennant_flutter.gdshader`, `scenes/piece_view.tscn`,
`scenes/costume_preview.tscn`, `tests/test_costumes.gd`, `tools/props/*`,
`assets/custom-props/*`, `assets/kaykit-skeletons/*`,
`assets/kaykit-adventurers/props/*`.

## Design principle (hold this line in future work)

Two layers, never confused:

- **piece TYPE** = silhouette + signature gear + height grading — identical
  logic across all houses, instantly readable.
- **HOUSE** = crest / shield sigil / palette flourish — never changes the
  type silhouette.

## What the integrator gets for free (no call-site changes)

`PieceView.setup(type, side, house_id)` is unchanged and backward
compatible (`house_id == ""` = legacy FROST/EMBER). Every existing flow
(spawn, move, capture, die, promote, crown checks) passed e2e untouched:
`boot`, `board-truth`, `duel`, `castle`, `promote` all PASS.

- Strict height grading pawn<knight<bishop<rook<queen<king
  (`PieceAssets.TYPE_HEIGHT`, world units; models are AABB-normalized at
  build so the law holds for every cast).
- Signature gear per type: pawn sword+round shield · knight sword+kite
  shield · bishop staff+tome · queen tiara+bow+quiver · king
  crown+cape+sword. (Royal swap 2026-08-08: the goateed Ranger is the KING,
  the clean-faced Rogue_Hooded is the QUEEN with a slim tiara — the crown
  prop scaled slimmer/flatter, node named `Tiara` so queens stay
  "uncrowned" for the e2e Crown-node check.)
- Type-glyph ring under every piece (front medallion, engraved emissive
  chess glyph).
- House crests on knight/queen/king; sigil decals on shields; the rook is
  now the banner watchtower (house-sigil banner + fluttering pennant);
  Tidegrip fields the KayKit skeleton cast.

## ONE opt-in hook — selection feedback

```gdscript
piece_view.set_selected(true)   # glyph medallion warms up (tweened)
piece_view.set_selected(false)  # back to rest
```

Suggested wiring in `game.gd`: wherever `board.set_selected(sq)` is called
with the selected square, also call `views[sq].set_selected(true)`, and
`set_selected(false)` on the previously selected piece (and on
clear-selection). Purely cosmetic — safe to skip.

## PieceAssets API changes (autoload)

Unchanged: `shared_anims()`, `anim_length()`, `crown_scene(tint)`,
`tinted_material(src, tint, saturation)`, `LOOPED_ANIMS`, crown preloads.

New (all keyed by `int(PieceView.Type)` where relevant — the dictionaries
use ints to avoid a parse-time cycle with `class_name PieceView`):

| API | Purpose |
|---|---|
| `TYPE_HEIGHT` / `piece_height(t)` | height-grading law (world units) |
| `character_scene(t, house_id)` | adventurer cast, or skeleton cast for `tidegrip` |
| `gear_specs(t)` | signature-gear mount specs (scene/bone/pos/rot/scale/decal) |
| `glyph_ring_scene(t)`, `GLYPH_ENERGY_REST/SELECTED` | glyph rings |
| `wants_crest(t)`, `crest_scene(house_id)` | crests (knight/queen/king) |
| `sigil_material(house_id)` | cached alpha-scissor shield decal material |
| `banner_texture(house_id)` | cached rook-banner texture (cloth + sigil composite) |
| `CAPE`, `WATCHTOWER`, `PENNANT_SHADER`, `SKELETON_HOUSE`, `SKELETON_SCENES` | assets |

**Removed from PieceView** (moved/replaced; verified unreferenced
elsewhere): `CHARACTER_SCALE`, `KING_SCALE`, `TOWER_SCALE`,
`CHARACTER_SCENES`, `TOWER_BASE`, `TOWER_TOP`.

## Node-name contracts (e2e + tests rely on these)

- `Crown` under `CrownMount` — kings only (existing e2e board-truth check;
  crests are named `Crest` precisely so queens stay "uncrowned").
- New names: `GlyphRing`, `Crest`/`CrestMount`, `Cape`/`CapeMount`,
  `Tiara`/`TiaraMount` (queens only — deliberately NOT `Crown`),
  `GearMount_<key>`/`Gear_<key>` (keys: sword, shield, staff, tome, bow,
  quiver), `SigilDecal`; watchtower meshes `TowerBody`, `BannerCloth`,
  `BannerRod`, `PennantPole`, `Pennant`.
- Rook death: `die()` sets `death_anim = "Tower_Crumble"` (unchanged) and
  now detaches `BannerCloth` to the piece's parent while the tower falls —
  the banner frees itself ~0.7 s later.

## Test wiring the integrator must add (test_e2e/ is not module-owned)

`run_e2e.sh` enumerates suites explicitly; add to the `tests)` branch:

```bash
run_suite costumes-suite res://tests/test_costumes.gd || SUITE_RC=1
```

Optional second gate (66 house×type assembly combos, exit code 0/1):

```bash
"$GODOT" --headless --path "$PROJ" res://scenes/costume_preview.tscn
```

## Verification commands

```bash
# assembly gate, headless (66 combos, exit code)
Godot --headless --path . res://scenes/costume_preview.tscn
# full costume suite (77 checks)
Godot --headless --path . -s res://tests/test_costumes.gd
# visual grid: per-house + overview screenshots ->
#   test_e2e/artifacts/module-previews/costumes/
Godot --path . res://scenes/costume_preview.tscn
```

## Asset regeneration (Blender 4.0.2 headless, deterministic)

```bash
B=/Applications/Blender.app/Contents/MacOS/Blender
$B -b --python tools/props/make_glyph_rings.py -- assets/custom-props/glyph-rings
$B -b --python tools/props/make_crests.py      -- assets/custom-props/crests
$B -b --python tools/props/make_cape.py        -- assets/custom-props
$B -b --python tools/props/make_watchtower.py  -- assets/custom-props
```

Tri counts: watchtower 472 · cape 316 · crests 72–340 each ·
glyph rings 484–1232 each. Provenance: `assets/custom-props/LICENSE-props.txt`;
KayKit licenses copied beside the new asset copies.

## Gotchas discovered (worth knowing before touching this area)

1. **`-s` scripts never instance autoloads**, and any script naming the
   `PieceAssets` global fails to *compile* until a node called
   `PieceAssets` hangs under `/root`. `tests/test_costumes.gd` therefore
   shims the autoload first and `load()`s everything after — no
   `preload`/`const` references to PieceView/PieceAssets from `-s` scripts.
2. **A glyph centered under a piece is invisible** — the piece stands on
   it. The rings carry the glyph on a tilted medallion at the front lip
   (and the rook's ring slides forward past the tower plinth).
3. The Skeletons pack is genuinely the same `Rig_Medium` rig as the
   Adventurers pack (same skeleton path, same bones incl. `handslot.l/r`)
   — the merged shared-anim library drives both casts directly;
   `test_costumes` locks this with bone/track assertions.
4. Pennant flutter is a vertex shader (`pennant_flutter.gdshader`,
   time-based sine, `cull_disabled`); the pennant mesh root sits at local
   x=0 so `VERTEX.x` is the flutter mask. No physics.

## Deviations from the brief

- King gear is **crown + cape** (cape was cheap in Blender) — the
  "else crown+scale" fallback was not needed; height grading applies to
  all types regardless.
- Glyph rings: engraved-in-disc look became **front-lip medallion** for
  the readability reason above (the "engraved + emissive, subtle at rest,
  brightens on selection" behavior is intact).
- Watchtower damage states (optional in the brief): skipped; the crumble
  death + banner detach are in.
- Tidegrip king wears `Skeleton_Warrior` (the free Skeletons pack has four
  characters for five roles; the warrior doubles as king under
  crown+cape+crest).
