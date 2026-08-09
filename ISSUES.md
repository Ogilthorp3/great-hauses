# Issues

Lightweight tracker (repo has no remote yet — this file is the issue queue).

## #1 — Knights should be mounted on horses
**Status:** fixed, 2026-08-08 (mounted-knights pass) · **Requested:** Bert, 2026-08-08

The knight piece is currently an armored KayKit foot soldier. A knight belongs on a horse.
- KayKit Adventurers FREE has no horse model.
- Options: Quaternius CC0 animated animals (horse with idle/walk clips — verify at quaternius.com / poly.pizza), or a Blender-built stylized horse via the `tools/props/` pipeline (seeded, matches art style), rider merged or bone-attached.
- Must keep: piece-type readability (silhouette becomes MORE distinct — good), height grading slot between bishop and rook, house crest/palette on the rider, walk animation for moves (horse walk replaces rider walk), duel choreography (mounted strike / rider falls on death).

Shipped: every knight now rides. The mount is the Quaternius CC0 horse (poly.pizza `qvTrSG9pZF`, provenance in `assets/quaternius-animals/LICENSE-horse.txt`) run through `tools/props/convert_horse.py`, which freezes it into a STATIC standing pose and adds authored war-tack — a leather `Saddle` and a `Caparison` whose flank panels are UV-mapped for the house banner cloth, so the mount wears the same dyed cloth + sigil the house's rook flies. The hide is dyed too: the pack's untextured browns survive the normal multiply-tint unchanged (Winterfang fielded a brown horse in a steel-blue army until the preview caught it), so each mount re-takes the house hue modulated by its own material luminance — hide, mane and hooves keep their contrast, the eyes keep their paint. The rig is deliberately dropped: Godot corrupts that FBX-lineage skinned mesh at chess-piece scale (front half vanishes, camera-angle-dependently, on Mobile *and* Forward+), while static meshes render clean — so `PieceView` drives the mount procedurally, the banner-rook's proven pattern: idle weight-shift sway, a canter bob with a rocking pitch on moves, a horse step-in under the rider's Throw, and on death the rider tumbles from the saddle through `Death_A` while the horse keels over. The rider is the same KayKit knight (Tidegrip's skeleton on a charred charger), seat-posed on paused bones and lifted a height slot to `0.98` — mounted, he out-tops the foot bishop. Ensemble proportions were picked off rendered A/Bs, and the ensemble stands reined a quarter-turn (`KNIGHT_MODEL_YAW`) so the head-on gameplay camera sees horse, barrel and caparison instead of a narrow shape hiding behind its rider. Covered by the costume suite (165 checks — assembly, house-dressed mount, seat, mounted death/capture, face-to-face turn on the real ensemble), a mounted-ensemble ASHFALL burn test in the dragon suite (no orphan horse left in the ashes), and the regenerated per-house previews plus a dedicated `mounted_knight.png` beauty shot.

## #2 — Piece-type glyph rings: visible on mouse-over only
**Status:** fixed, 2026-08-08 (undo/polish pass) · **Requested:** Bert, 2026-08-08

The engraved type-glyph rings under pieces are always visible. Change: hidden by default, shown on hover (board raycast → hovered piece), stay bright on selection. Keep the e2e costume assertions in sync (glyph presence checked via hover state, not rest state).

Shipped: rings hidden at rest (transparency-faded, ~0.15 s in/out), revealed by a throttled mouse-motion raycast (`BoardView.square_hovered` → `PieceView.set_hovered`), held lit while selected. Both armies hover-reveal. Covered by the costume suite's hover/selection/layering checks and the boot e2e's real-input glyph assertions.

## #3 — Per-house pawn helmets
**Status:** queued (launches after mounted knights land) · **Requested:** Bert, 2026-08-08

Each house's pawns get a distinct half-helm with a small house motif (wolf ears, lion crest, antler nubs, dragon fin, tentacle ridge, rose band, sun disc, falcon wings, scale crest) via the tools/props/ Blender pipeline (seeded, ≤250 tris each). Deliberately subtler than royal crests — pawns must still read as pawns first. Skeleton (Tidegrip) pawns get the charred/dark variant. Costume suite + previews updated per house.
