# Issues

Lightweight tracker (repo has no remote yet — this file is the issue queue).

## #1 — Knights should be mounted on horses
**Status:** open · **Requested:** Bert, 2026-08-08

The knight piece is currently an armored KayKit foot soldier. A knight belongs on a horse.
- KayKit Adventurers FREE has no horse model.
- Options: Quaternius CC0 animated animals (horse with idle/walk clips — verify at quaternius.com / poly.pizza), or a Blender-built stylized horse via the `tools/props/` pipeline (seeded, matches art style), rider merged or bone-attached.
- Must keep: piece-type readability (silhouette becomes MORE distinct — good), height grading slot between bishop and rook, house crest/palette on the rider, walk animation for moves (horse walk replaces rider walk), duel choreography (mounted strike / rider falls on death).

## #2 — Piece-type glyph rings: visible on mouse-over only
**Status:** planned (bundled into the undo/polish agent, task #14) · **Requested:** Bert, 2026-08-08

The engraved type-glyph rings under pieces are always visible. Change: hidden by default, shown on hover (board raycast → hovered piece), stay bright on selection. Keep the e2e costume assertions in sync (glyph presence checked via hover state, not rest state).
