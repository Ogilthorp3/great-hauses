# Issues

Lightweight tracker (repo has no remote yet — this file is the issue queue).

## #1 — Knights should be mounted on horses
**Status:** fixed, 2026-08-08 (mounted-knights pass) · **Requested:** Bert, 2026-08-08

The knight piece is currently an armored KayKit foot soldier. A knight belongs on a horse.
- KayKit Adventurers FREE has no horse model.
- Options: Quaternius CC0 animated animals (horse with idle/walk clips — verify at quaternius.com / poly.pizza), or a Blender-built stylized horse via the `tools/props/` pipeline (seeded, matches art style), rider merged or bone-attached.
- Must keep: piece-type readability (silhouette becomes MORE distinct — good), height grading slot between bishop and rook, haus crest/palette on the rider, walk animation for moves (horse walk replaces rider walk), duel choreography (mounted strike / rider falls on death).

Shipped: every knight now rides. The mount is the Quaternius CC0 horse (poly.pizza `qvTrSG9pZF`, provenance in `assets/quaternius-animals/LICENSE-horse.txt`) run through `tools/props/convert_horse.py`, which freezes it into a STATIC standing pose and adds authored war-tack — a leather `Saddle` and a `Caparison` whose flank panels are UV-mapped for the haus banner cloth, so the mount wears the same dyed cloth + sigil the haus's rook flies. The hide is dyed too: the pack's untextured browns survive the normal multiply-tint unchanged (Winterfang fielded a brown horse in a steel-blue army until the preview caught it), so each mount re-takes the haus hue modulated by its own material luminance — hide, mane and hooves keep their contrast, the eyes keep their paint. The rig is deliberately dropped: Godot corrupts that FBX-lineage skinned mesh at chess-piece scale (front half vanishes, camera-angle-dependently, on Mobile *and* Forward+), while static meshes render clean — so `PieceView` drives the mount procedurally, the banner-rook's proven pattern: idle weight-shift sway, a canter bob with a rocking pitch on moves, a horse step-in under the rider's Throw, and on death the rider tumbles from the saddle through `Death_A` while the horse keels over. The rider is the same KayKit knight (Tidegrip's skeleton on a charred charger), seat-posed on paused bones and lifted a height slot to `0.98` — mounted, he out-tops the foot bishop. Ensemble proportions were picked off rendered A/Bs, and the ensemble stands reined a quarter-turn (`KNIGHT_MODEL_YAW`) so the head-on gameplay camera sees horse, barrel and caparison instead of a narrow shape hiding behind its rider. Covered by the costume suite (165 checks — assembly, haus-dressed mount, seat, mounted death/capture, face-to-face turn on the real ensemble), a mounted-ensemble ASHFALL burn test in the dragon suite (no orphan horse left in the ashes), and the regenerated per-haus previews plus a dedicated `mounted_knight.png` beauty shot.

## #2 — Piece-type glyph rings: visible on mouse-over only
**Status:** fixed, 2026-08-08 (undo/polish pass) · **Requested:** Bert, 2026-08-08

The engraved type-glyph rings under pieces are always visible. Change: hidden by default, shown on hover (board raycast → hovered piece), stay bright on selection. Keep the e2e costume assertions in sync (glyph presence checked via hover state, not rest state).

Shipped: rings hidden at rest (transparency-faded, ~0.15 s in/out), revealed by a throttled mouse-motion raycast (`BoardView.square_hovered` → `PieceView.set_hovered`), held lit while selected. Both armies hover-reveal. Covered by the costume suite's hover/selection/layering checks and the boot e2e's real-input glyph assertions.

## #3 — Per-haus pawn helmets
**Status:** fixed, 2026-08-08 (pawn-helm pass) · **Requested:** Bert, 2026-08-08

Each haus's pawns get a distinct half-helm with a small haus motif (wolf ears, lion crest, antler nubs, dragon fin, tentacle ridge, rose band, sun disc, falcon wings, scale crest) via the tools/props/ Blender pipeline (seeded, ≤250 tris each). Deliberately subtler than royal crests — pawns must still read as pawns first. Skeleton (Tidegrip) pawns get the charred/dark variant. Costume suite + previews updated per haus.

Shipped: every pawn now wears its own haus's half-helm — nine originals from `tools/props/make_pawn_helms.py` (194–238 tris, avg 197, none decimated), mounted on the rig's `head` bone by the same `BoneAttachment3D` pattern that carries the royal crest, so a helm tracks idle, walk and death for free. The two ranks are deliberately different *kinds* of headgear rather than different sizes of the same one: a crest **towers over** the skull (mount y 1.04, reaching ~0.85 higher still), a helm **wraps** it (mount y 0.945, motif capped 0.21 above the crown line) — the player reads "pawn" first and "which haus" second. Only the flared rim and the motif take the haus accent; the shell is left plain dark iron, and that restraint is what keeps a footman humble next to his queen. The rim carries the accent on *every* helm, so a haus still reads by color when its motif is a few pixels. The Drowned Legion fields the pre-charred twin (identical kraken geometry, iron and rim baked black — the `crown.glb`/`crown_frost.glb` precedent), matching the charred charger its knight already rides.

The shell is fitted to a **measured slice profile** of each cast's head-bone-weighted vertices, not to the head's AABB — the Barbarian's AABB half-width is its *beard* and the skeleton's widest point is somewhere else entirely, so an AABB-fitted ellipsoid was baggy on one skull and cut clean through the other. One mount transform serves both casts: the skeleton's crown sits 0.020 lower and its helm is pre-shifted by exactly that in the generator, so the runtime needs no per-cast branch.

One trap, paid for in advance: the Barbarian ships wearing a full bear-skull hood that swallows any helm, and that hood is the model's **tallest mesh** (2.398 vs the bald skull's 2.186) — the very mesh the height grading measures. So it is **hidden, never freed**: `visible = false` leaves `_raw_model_height` untouched and every piece's scale factor bit-identical to before, where `queue_free()` would have silently scaled every living-haus pawn up ~10% and broken the grading. The costume suite asserts the hood is both *doffed* and *still in the tree*.

Covered by the costume suite (273 checks, up from 165 — per-haus helm assets are asserted distinct, mounted on the head bone at the measured crown, accent-dyed and iron-untouched, absent from every other rank and from legacy sides, with the height law re-measured per haus) and by the shared `validate_piece` gate that the headless costume run and the suite both call. Previews regenerated: nine per-haus sets, the all-hauses overview, the mounted-knight beauty shot, and a new pawn-helm parade (`pawn_helms.png`, orthographic and staggered so all nine are judged on equal terms) plus two close heroes (`pawn_helm_hero.png`, `pawn_helm_drowned.png`).

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

Two artifacts in the reviewed set read as unfinished: `orientation/labeled.png` drew its royal plates on top of each other ("Qd&e8", "QdKe1"), and `module-previews/facing.png` captioned two grey capsules "So falls the queen of Haus Ember" — a legacy fallback haus that is not one of the Nine.

Shipped:
- **Orientation overlay** (our permanent human-audit instrument, so legibility is a hard requirement): d and e are adjacent files, so two same-height three-glyph plates one world unit apart could only collide. The queen's plate now rides at y 3.25 and the king's at y 2.15, both at font 104 instead of 150, and each drops a thin leader stem from y 1.65 to its plate so the square it names is unambiguous. No two plates can share a screen row again.
- **Facing fixture**: `duel_test.gd` now passes real haus keys (`winterfang` / `goldclaw`) into `play_duel`/`play_checkmate` instead of falling through to the legacy FROST/EMBER table, and every frame the stage renders carries a `MODULE TEST FIXTURE — DuelDirector stage / capsule stand-ins, not gameplay art` stamp. The fixture's own victory-hook check moved to `Haus Winterfang` with it — deliberately, and it still proves the same thing.

## #17 — Hard black ellipses under pieces read as holes in the floor
**Status:** fixed, 2026-08-09 (scene/HUD/lighting pass) · **Requested:** frame critique, 2026-08-09

Two different black discs were being read as one defect.

1. **The Sun's cast shadow** was painted to full black and hard-edged. The rake is unchanged (43°; lowering it only smears longer streaks across the tiles) — what changed is that a shadow is now a shadow and not a hole: `shadow_opacity` 0.55, `light_angular_distance` 2.2 for an angular penumbra, `shadow_blur` 1.6, energy 0.55 → 0.72, plus the ambient lift from #15 filling what the shadow leaves.
2. **The glyph medallion** (#2's hover ring) was the disc the critique called "worst on the orange selection tile" — a dark ring with an emissive glyph, revealed by hover and left burning through an entire cinematic because no new hover event arrives while the pointer sits still on the duel square. From the duel camera, inches off the floor, it read as a black hole under the fighters. Hover reveals are now suppressed while `DuelDirector.is_active()`, and any lit ring is dropped when a cinematic starts. A mouse-hover affordance has no business on screen while the camera is taken over.

The selection tile no longer catches a shadow at all: its highlight quad is unshaded (see #5).

## #18 — The armies are monochrome; the haus colour must be a JERSEY, not a coat of paint
**Status:** fixed, 2026-08-09 (material-role pass) · **Requested:** Bert (game owner), 2026-08-09

> "The figurines [are] too much mono color, should be like a hockey team jersey — colors of the team/haus, but NOT everywhere. Horse should be brown, black or white, something majestic."

He is right, and the cause was ours. A critic found un-tinted marketplace props — a fluorescent magenta grimoire on every bishop, a lime staff orb, a salmon shield rim — and the fix was made ABSOLUTE: a palette-envelope gate requiring EVERY rendered surface to sit on the haus hue, with the saturation ceiling driven to 0.10 and then to 0.00 precisely because the dye had to survive on skin, steel, bone and horsehide too. Nine monochrome armies, and a steel-blue Winterfang charger. **The gate had become the defect.**

Shipped: the pipeline no longer asks "what colour is this haus?" first. It asks **what is this surface made of**, and dispatches on the answer.

- **`PieceAssets.MATERIAL_ROLES`** — one ordered, readable table classifying every prop and mesh in the game as `KIT`, `NATURAL` (with a material family), `REGALIA`, `HERALDRY`, `MIXED` or `EFFECT`. Matched against the mesh node name first and the material's `resource_name` second, first match wins. **`UNCLASSIFIED` is a failure, never a default** — `classify()` `push_error()`s and the role gate fails on it, because the old pipeline's silent fallback was "dye it", which is how a magenta grimoire hid AND how nine armies later went grey.
- **`MIXED` meshes are split per TRIANGLE.** A KayKit figure is painted from ONE 1024² atlas, so `Mage_Body` is a navy robe *and* leather boots *and* skin; a mesh-level role cannot serve it and a per-texel dye per haus is 9M pixel ops nobody should pay for. Each triangle is classified by the colour the atlas paints it (`tools/dump_uv_palette.gd` is the instrument that read those palettes off disk), the surface is split into a KIT half and a NATURAL half, and each takes one material. The split never moves a vertex, so the mesh AABB the height law measures is bit-identical.
- **The jersey is finally LOUD.** `tints.kit` per haus, saturation 0.45–0.90, applied as the flat albedo over a pure-luminance copy of the atlas so a tabard keeps every fold the artist painted. The 0.00 ceiling existed only because the dye was universal.
- **Naturals keep their own colours.** Steel and stone take at most a whisper of the haus tint (capped saturation, so it can only shift the hue a hair); leather, wood, skin and bone take none.
- **The horse is a horse.** Nine natural coats (`PieceAssets.COAT_PALETTES`) assigned per haus — Winterfang white-grey, Goldclaw chestnut, Ashwyrm black, Hartcrown dapple-grey, Tidegrip drowned-grey, Thornvale dun, Duskfire liver chestnut, Swiftcrest bay, Silverbrook dark bay. The mount's haus identity is the **caparison** over it, never the animal. Every mane is pushed off its hide's own value, because a real chestnut's same-colour mane renders at chess-piece scale as a horse with no mane.
- **The charge law is value-only now.** The old law bought contrast with chroma and walked Thornvale's gold #d3b04a off to #302300, a colour the haus does not own. A charge is a declared haus colour moved only along VALUE — and searched by intent (each colour at its OWN value first), because "maximise the distance" reliably elects black: Winterfang's mitre band came out #2a2e32 and the near bishop read as a black ring with a blue nub in it.
- **The rook faces its banner at the player.** A watchtower's masonry is stone, so the tower is the same grey in all nine hauses and the banner is the only thing that says whose rook it is. Facing it at the enemy left the player two neutral grey blocks in his own corners.

**The gate was rewritten to match** (`costume_preview.role_offenders`): KIT must be dressed and wearing one of its haus's four colours (value-normalised, so a jersey's white or black charge is legal and a stock grey is not); NATURAL must be inside its material's range and must NOT be the haus kit; REGALIA must stay metal. **Three negative controls**, all in `tests/test_costumes.gd`: strip a dye and the gate goes red (the original discipline), **paint a horse blue and the gate goes red** (its mirror), and rename a surface out of the table and the gate goes red.

**Preserved wins, re-measured on the same instrument** (`tools/frame_rank.py`, boot frame `02_boot_lineup.png`): the king still leads his own army's peak (p90 0.867 against knights at 0.769/0.749 — the margin widened from 0.098/0.091); the far queen is further out of her black hole than the lift that rescued her (median 0.400 at the top of a 0.373–0.400 band, from 0.353 in 0.286–0.373); the nine pawn ranks are at least as separable as before (closest pair 0.055 against a 0.054 baseline, whole-figure mean RGB); the height law is unchanged and still monotonic; the Drowned Legion is coherent — bone is NATURAL and Tidegrip's colour lives entirely in its cloaks, hoods and helms.

## #4 — Small art follow-ups from the jersey critic (non-blocking)
**Status:** open · **Raised:** critic pass, 2026-08-09

Critic verdict was SHIP; these are the leftovers it explicitly said should not hold the ship.
1. **Rook banner sigils too dim on light cloth** — Winterfang and Tidegrip sigil PNGs in `assets/sigils/` need brightness/contrast so the rook's banner reads its haus from the board camera. Highest value per minute of the four.
2. **The crown is navy on five hauses, gold on four** — decide: gold on all nine (a crown is metal, consistent, and kills the navy-crown-on-a-gold-king collision), or keep a warm/cool contrast rule and write it down.
3. **Tidegrip's caparison does not lift off its drowned-grey coat** — one value step / higher chroma on the teal.
4. No pre-change costume sheet survives for an A/B (artifacts are gitignored) — render one if a record is ever wanted.
