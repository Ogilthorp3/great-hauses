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
**Status:** fixed, 2026-08-08 (pawn-helm pass) · **Requested:** Bert, 2026-08-08

Each house's pawns get a distinct half-helm with a small house motif (wolf ears, lion crest, antler nubs, dragon fin, tentacle ridge, rose band, sun disc, falcon wings, scale crest) via the tools/props/ Blender pipeline (seeded, ≤250 tris each). Deliberately subtler than royal crests — pawns must still read as pawns first. Skeleton (Tidegrip) pawns get the charred/dark variant. Costume suite + previews updated per house.

Shipped: every pawn now wears its own house's half-helm — nine originals from `tools/props/make_pawn_helms.py` (194–238 tris, avg 197, none decimated), mounted on the rig's `head` bone by the same `BoneAttachment3D` pattern that carries the royal crest, so a helm tracks idle, walk and death for free. The two ranks are deliberately different *kinds* of headgear rather than different sizes of the same one: a crest **towers over** the skull (mount y 1.04, reaching ~0.85 higher still), a helm **wraps** it (mount y 0.945, motif capped 0.21 above the crown line) — the player reads "pawn" first and "which house" second. Only the flared rim and the motif take the house accent; the shell is left plain dark iron, and that restraint is what keeps a footman humble next to his queen. The rim carries the accent on *every* helm, so a house still reads by color when its motif is a few pixels. The Drowned Legion fields the pre-charred twin (identical kraken geometry, iron and rim baked black — the `crown.glb`/`crown_frost.glb` precedent), matching the charred charger its knight already rides.

The shell is fitted to a **measured slice profile** of each cast's head-bone-weighted vertices, not to the head's AABB — the Barbarian's AABB half-width is its *beard* and the skeleton's widest point is somewhere else entirely, so an AABB-fitted ellipsoid was baggy on one skull and cut clean through the other. One mount transform serves both casts: the skeleton's crown sits 0.020 lower and its helm is pre-shifted by exactly that in the generator, so the runtime needs no per-cast branch.

One trap, paid for in advance: the Barbarian ships wearing a full bear-skull hood that swallows any helm, and that hood is the model's **tallest mesh** (2.398 vs the bald skull's 2.186) — the very mesh the height grading measures. So it is **hidden, never freed**: `visible = false` leaves `_raw_model_height` untouched and every piece's scale factor bit-identical to before, where `queue_free()` would have silently scaled every living-house pawn up ~10% and broken the grading. The costume suite asserts the hood is both *doffed* and *still in the tree*.

Covered by the costume suite (273 checks, up from 165 — per-house helm assets are asserted distinct, mounted on the head bone at the measured crown, accent-dyed and iron-untouched, absent from every other rank and from legacy sides, with the height law re-measured per house) and by the shared `validate_piece` gate that the headless costume run and the suite both call. Previews regenerated: nine per-house sets, the all-houses overview, the mounted-knight beauty shot, and a new pawn-helm parade (`pawn_helms.png`, orthographic and staggered so all nine are judged on equal terms) plus two close heroes (`pawn_helm_hero.png`, `pawn_helm_drowned.png`).

## #4 — Cinematic captions must never cover the fight
**Status:** fixed (caption layer), 2026-08-09 (scene/HUD/lighting pass) · **Requested:** frame critique, 2026-08-09

The mid-duel frame showed the caption layer reading as an unfinished debug panel: no backing, hard cut on hide, and the rival's taunt free to land in the same frame as the kill line.

Shipped: every cinematic caption (DuelDirector's own and the shared `CineCaption` layer) now wears one styled backing plate — `DuelDirector.caption_backing()`, a rounded 62%-opacity scrim with gold hairlines that HUGS the text (the label sizes to its content, so it can never become a slab across the frame) — and is anchored in the bottom sixth (96–160 px off the bottom edge), clear of the middle third where the fight happens. Captions fade in AND out on the wall clock (0.25 s / 0.30 s, immune to `Engine.time_scale` so they behave inside slow-mo); `restore()` still hard-cuts for teardown. The two voices are now separated twice over: spatially (the rival's taunt sits in the bottom 10–64 px band, below the caption band) and temporally — `DuelDirector.caption_visible()` is public, and `game.gd` holds a banter line back until the kill line clears (6 s ceiling, so a taunt is delayed, never lost). Generation tokens mean a newer taunt abandons the older one's fade instead of racing it.

**Not fixed by this pass:** the mustard rectangle the critique names in `05_mid_duel.png` is *not* a caption. It is `PieceView._strike_flash()` — the weapon-trail billboard (0.85 × 0.22 quad, `albedo (1.0, 0.85, 0.5, 0.9)`, emission ×3, scaled up over 0.24 s), caught by the screenshot at t≈0 where it is still an unstretched opaque rectangle. Fix belongs in `src/board/piece_view.gd`: additive blend instead of 90 %-alpha, a soft-edged streak texture instead of a bare quad, and spawn it already elongated (start scale ≈ (1.6, 0.25)) so it never presents as a filled rectangle.

## #5 — Legal-move markers read as missing-texture nameplates
**Status:** fixed, 2026-08-09 (scene/HUD/lighting pass) · **Requested:** frame critique, 2026-08-09

The selection/legal-move highlights were untextured flat quads: a pale-blue square floating over the square in front of the selected pawn read as a blank nameplate, and the capture marker was a smaller blue tab beside its victim. This is the most-used interaction in the game, so it must look deliberate.

Shipped: `BoardView` draws its highlight art into small procedural alpha textures at boot (96², `_move_dot_texture` / `_capture_ring_texture` / `_select_frame_texture`) and the three highlights now read as three different, recognisable things: a steel **rune dot** (ring + core) for a quiet move, a red **target reticle with crosshair ticks** inscribed in the tile for a capture — it frames the victim standing there instead of hiding under his feet — and an amber **squircle frame with a soft inner wash** for the selected square. `show_legal_moves()` takes the capture subset (`game.gd` derives it from `ChessMove.is_capture()`), which also fixed a latent duplicate-marker bug on promotion moves. All three materials are `SHADING_MODE_UNSHADED`: the highlight layer is UI drawn in world space and must not take a cast shadow (see #17).

## #15 — The hall was underlit and the far army read as mud
**Status:** fixed, 2026-08-09 (scene/HUD/lighting pass) · **Requested:** frame critique, 2026-08-09

The far half of every board frame sat 2–3 stops under the near half and the checker pattern nearly vanished through the empty middle.

Shipped, without adding a single light (the Mobile renderer's 8-omni budget is full with the hall torches):
- **Fog was the main culprit** — density 0.013 against a near-black fog color blends distant stone toward black and crushes the light/dark ratio with it. Density 0.013 → 0.006, fog color lifted off black (0.055 → 0.10).
- **Tile value split widened** where lighting cannot help: lighting multiplies both stones equally, so only the ALBEDO RATIO survives the gloom. `LIGHT_STONE` 0.36 → 0.50, `DARK_STONE` 0.13 → 0.105 (light tile ≈ 126/255 rendered vs dark ≈ 39/255, from 67 vs 31 before).
- **Ambient** 0.52 → 0.66 and warmed off blue (torchlight, not moonlight); **exposure** 1.08 → 1.12.
- **`CoolFill`** 0.24 → 0.50: it is the only light that reaches a far fighter's FACE (the Sun rakes from the near side, the torches are wall fixtures), so the far army's mud was mostly its weakness. `Rim` 0.45 → 0.55.

Verified on regenerated `boot/02_boot_lineup.png` and `showcase/02_great_hall_wide.png`: both back ranks and the full checker read, while the walls, aisles and ceiling stay dark — legibility, not a bright room.

## #16 — Shipped placeholder artifacts (orientation labels, facing fixture)
**Status:** fixed, 2026-08-09 (scene/HUD/lighting pass) · **Requested:** frame critique, 2026-08-09

Two artifacts in the reviewed set read as unfinished: `orientation/labeled.png` drew its royal plates on top of each other ("Qd&e8", "QdKe1"), and `module-previews/facing.png` captioned two grey capsules "So falls the queen of House Ember" — a legacy fallback house that is not one of the Nine.

Shipped:
- **Orientation overlay** (our permanent human-audit instrument, so legibility is a hard requirement): d and e are adjacent files, so two same-height three-glyph plates one world unit apart could only collide. The queen's plate now rides at y 3.25 and the king's at y 2.15, both at font 104 instead of 150, and each drops a thin leader stem from y 1.65 to its plate so the square it names is unambiguous. No two plates can share a screen row again.
- **Facing fixture**: `duel_test.gd` now passes real house keys (`winterfang` / `goldclaw`) into `play_duel`/`play_checkmate` instead of falling through to the legacy FROST/EMBER table, and every frame the stage renders carries a `MODULE TEST FIXTURE — DuelDirector stage / capsule stand-ins, not gameplay art` stamp. The fixture's own victory-hook check moved to `House Winterfang` with it — deliberately, and it still proves the same thing.

## #17 — Hard black ellipses under pieces read as holes in the floor
**Status:** fixed, 2026-08-09 (scene/HUD/lighting pass) · **Requested:** frame critique, 2026-08-09

Two different black discs were being read as one defect.

1. **The Sun's cast shadow** was painted to full black and hard-edged. The rake is unchanged (43°; lowering it only smears longer streaks across the tiles) — what changed is that a shadow is now a shadow and not a hole: `shadow_opacity` 0.55, `light_angular_distance` 2.2 for an angular penumbra, `shadow_blur` 1.6, energy 0.55 → 0.72, plus the ambient lift from #15 filling what the shadow leaves.
2. **The glyph medallion** (#2's hover ring) was the disc the critique called "worst on the orange selection tile" — a dark ring with an emissive glyph, revealed by hover and left burning through an entire cinematic because no new hover event arrives while the pointer sits still on the duel square. From the duel camera, inches off the floor, it read as a black hole under the fighters. Hover reveals are now suppressed while `DuelDirector.is_active()`, and any lit ring is dropped when a cinematic starts. A mouse-hover affordance has no business on screen while the camera is taken over.

The selection tile no longer catches a shadow at all: its highlight quad is unshaded (see #5).
