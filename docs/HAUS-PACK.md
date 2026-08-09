# Build your own Great Haus — in 20 minutes

A haus in this game is **a folder**, not code. Drop the folder in, start the
game, and your banner hangs in the Hall with the other nine. No rebuild, no
recompile, no patch to the game.

```
ravenmark/
  haus.json       the manifest — who you are, what colour you wear
  sigil.png       your heraldry
  pawn_helm.glb   your footmen's half-helm   (optional)
  crest.glb       your knights' crest        (optional)
```

There is a worked example of exactly that in
[`hauses/_examples/ravenmark/`](../hauses/_examples/ravenmark/) — Haus
Ravenmark, which ships its own sigil, its own helm, its own crest, its own
taunts, and whose two models were built by a 200-line GDScript with no
modelling tool at all. Copy it, or copy the blank
[`hauses/_template/`](../hauses/_template/).

---

## The 20 minutes

**1 · Copy the template** (2 min)

```bash
cp -R hauses/_template ~/mynewhaus
```

**2 · Edit `haus.json`** (10 min). The only field with no default is `id`.

```json
{
  "format": 1,
  "id": "ravenmark",
  "name": "Haus Ravenmark",
  "archetype": "raven",
  "seat": "Corvenhold",
  "motto": "We are counted at dusk.",

  "colors": { "primary": "#2a2140", "secondary": "#d8cfe6", "accent": "#a06fd6" },
  "tints":  { "kit": "#7b3fb5", "piece": "#6f5aa8", "tower": "#5a4890" },

  "coat": "black",

  "sigil": "sigil.png",
  "pawn_helm": "pawn_helm.glb",
  "crest": "crest.glb",

  "materials": { "ravenmark_beak": "natural:bone" }
}
```

**3 · Draw a sigil** (1 min) — or skip it and get a flat shield:

```bash
Godot --headless --path <game> -s res://tools/gen_sigils.gd -- --pack ~/mynewhaus
```

**4 · Check it** (1 min). Run the validator *before* the game does:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path <game> \
    -s res://tools/validate_house_pack.gd -- ~/mynewhaus
```

```
── /Users/you/mynewhaus
   haus 'ravenmark' — Haus Ravenmark of Corvenhold
  ok coat 'black' — a natural coat
  ok jersey #7b3fb5
  ok ravenmark_beak                     natural:bone — keeps its own colours
  ok crest: 1 kit, 1 natural
  ok pawn_helm: 2 kit
   PASS — this pack would load
```

Exit code 0 = it will load. `--all` checks every pack the game would load,
shipped and installed, which is the fastest way to see if your jersey clashes
with someone else's.

**5 · Install it** (1 min). Move the folder into `user://hauses/`:

| platform | `user://hauses/` is |
|---|---|
| macOS | `~/Library/Application Support/Godot/app_userdata/Great Hauses/hauses/` |
| Linux | `~/.local/share/godot/app_userdata/Great Hauses/hauses/` |
| Windows | `%APPDATA%\Godot\app_userdata\Great Hauses\hauses\` |

Start the game. Your haus is in the Hall of Banners, playable, with its
sigil on every shield, its colour on every tabard, its helm on every pawn.

---

## The two hard rules

Everything in this format is optional and forgiving except two things. Both
exist because the game's armies were broken once, in each direction, and the
fixes cost real work.

### 1 · Your horse is a horse

> *"Horse should be brown, black or white, something majestic."*

Nine hauses once rode nine horses dyed in nine haus colours — a steel-blue
charger, a gold one. A blue horse is a bug, not heraldry: a mount's haus
identity is worn on its **caparison**, the cloth over its flank, and the animal
underneath is an animal.

So `coat` must name one of these:

`bay` · `dark_bay` · `chestnut` · `liver_chestnut` · `black` · `white_grey` ·
`dapple_grey` · `drowned_grey` · `dun`

(the table is [`src/houses/coats.json`](../src/houses/coats.json) — six colours
each: hide, blaze, shading, muzzle, mane, hooves).

You may declare your own instead:

```json
"coat_palette": {
  "Main": "#6b4526", "Main_Light": "#8a5c33", "Main_Dark": "#4a2f19",
  "Muzzle": "#3a2515", "Hair": "#211a14", "Hooves": "#2b2724"
}
```

…but every colour in it must still be a colour a horse comes in: **saturation
≤ 0.20** (black, grey, white) **or hue between 5° and 58°** (bay, chestnut,
dun). Anything else is refused, by name, with the number:

```
haus 'vaelor': coat_palette.Main = #2e5cff is not a coat a horse comes in
(saturation 0.82, hue 220°) — a coat colour is either near-colourless
(s <= 0.20: black, grey, white) or a warm brown (hue 5-58°: bay, chestnut,
dun). Blue horses are a bug, not heraldry.
```

One more: **your coat may not be your jersey.** They must sit at least 0.14
apart in RGB, because a horse wearing the haus colour is precisely what the
rule above forbids. (This is why the shipped bronze haus rides a grey.)

### 2 · The haus colour goes on the KIT, and nowhere else

This is the important one.

The game once painted the haus hue on **every** surface — and to survive that
on skin, steel and horsehide the saturation had to be driven to zero. The
result was nine monochrome armies that all looked like the same team in
different lighting. The owner, looking at them:

> *"The figurines are too much mono color, should be like a hockey team jersey
> — colors of the team/haus, but NOT everywhere."*

So the pipeline stopped asking *what colour is this haus* and started asking
**what is this surface made of**:

| role | what it is | what it does |
|---|---|---|
| **KIT** | tabard, cloak, hood, shield face, caparison, helm, crest, plume, sash | wears the haus jersey, confidently saturated |
| **NATURAL** | steel, leather, wood, stone, skin, bone, the horse's coat | keeps its own colours; at most a whisper of haus in the shadows |
| **REGALIA** | the crown, the tiara | stays metal — the contrast against the body *is* the royal read |
| **HERALDRY** | the sigil plate, banner cloth, the type-glyph ring | carries its own artwork; dyeing it would dye the sigil |
| **EFFECT** | transient VFX | owns its own light |

**A pack inherits that discipline by construction.** Three layers, and you
cannot get around any of them:

1. **You may only declare surfaces you own.** Every name in `materials` must
   begin with `<your id>_`. You cannot declare `Main` (the horse's hide) or
   `Knight_Body`, because you cannot name them. This is also what keeps two
   installed packs from fighting over the same material name.
2. **The engine's contract names are your way in.** Name a surface
   `pawnhelm_iron` / `pawnhelm_accent`, or a mesh node `Crest_*`, and the game
   dresses it for you. They belong to the engine; you neither declare them nor
   shadow them.
3. **What you can name, you are still held to.** A surface whose own name says
   `steel`, `leather`, `bone`, `hide`, `coat`, `skin`, `wood` or `stone` cannot
   be declared `kit`:

```
materials: 'vaelor_steel_pauldron' is declared KIT, but its own name says
steel — and steel is NATURAL. The haus colour goes on the kit (tabard, cloak,
shield face, caparison, helm, crest) and nowhere else: steel stays steel,
leather stays leather, and the horse keeps its coat. Declare it
"natural:steel", or rename the surface if it really is cloth.
```

**Anything your models add beyond the contract names must be declared**, or the
engine refuses to paint it and the role gate fails on it:

```json
"materials": {
  "ravenmark_plume":    "kit",
  "ravenmark_beak":     "natural:bone",
  "ravenmark_pauldron": "natural:steel",
  "ravenmark_strap":    "natural:leather"
}
```

Roles: `kit` · `natural:<stuff>` · `regalia` · `heraldry` · `effect`
Stuffs: `steel` `leather` `wood` `stone` `skin` `bone` `coat` `glow` `atlas` `none`

`mixed` is not on offer: it is the per-triangle atlas split the shipped
marketplace casts need, because one 1024² texture paints their cloth, steel and
skin onto a single mesh. Your own model can simply have one material per
material.

---

## Every field

| field | required | default if missing |
|---|---|---|
| `id` | **yes** | — the one field with no default; lowercase `a-z 0-9 _`, unique |
| `format` | no | `1`. A number higher than the game understands is refused |
| `name` | no | `Haus <Id>` |
| `archetype` | no | `wolf`. Picks the taunting **voice** and the generated sigil's mark |
| `seat` | no | `an old keep` |
| `motto` | no | empty — the haus rides to war in silence |
| `colors.primary/secondary/accent` | no | a neutral steel palette. These are the **only** colours your kit may wear |
| `tints.kit` | no | `colors.primary`. **The jersey** — the one saturated colour your kit is painted in |
| `tints.piece` / `tints.tower` | no | a desaturated cut of your jersey — the whisper natural surfaces take |
| `coat` | no | `bay` |
| `coat_palette` | no | none — use a named coat |
| `sigil` | no | a flat `primary`-coloured shield |
| `pawn_helm` | no | pawns keep the cast's own headgear |
| `crest` | no | knights, queens and kings ride bare-headed |
| `materials` | no | `{}` — you ship nothing the engine's table does not already name |
| `army` | no | the shipped cast |
| `banter` | no | the shipped taunt pool for your id, if any |
| `music` | no | the shipped playlist |

Paths are relative to your folder, or absolute `res://` / `user://`.

Any key beginning with `_` is a comment — JSON has none, and the template uses
this to carry its own instructions. An unrecognised key that does *not* start
with `_` is a warning with the key quoted, so a typo is never a silent no-op.

---

## Making the art

**The sigil** is a 256×256 PNG with transparency. `tools/gen_sigils.gd --pack`
draws one from your colours and archetype; ten archetypes have marks (`wolf`
`lion` `stag` `dragon` `kraken` `rose` `sun` `falcon` `trout` `raven`) and
anything else gets a placeholder plus a note.

**The pawn half-helm** WRAPS the skull. It mounts on the rig's `head` bone at
the skull-top contact point, so in its own model space it hangs *below* y=0 and
almost nothing rises above it (the shipped nine keep their motif under ~0.08;
the hard ceiling is about 0.21). A pawn must read as *pawn* first and *which
haus* second. Two surfaces:

- `pawnhelm_iron` — the dome. Painted in your haus colour, dyed dark.
- `pawnhelm_accent` — the rim and motif. Painted in your haus **charge**: the
  one of your four declared colours that stands furthest off the dome. This is
  computed, not declared, so your motif can never come out green-on-green.

**The crest** TOWERS over the head, and is worn by knight, queen and king only.
Name the **mesh node** `Crest_<yourid>` and the whole thing is KIT.

Both are ordinary `.glb` files. A pack dropped into `user://hauses/` never goes
through the editor's import pipeline, so the game parses your models and images
**at runtime** — which is exactly why a DLC haus needs no rebuild. Material
names survive that trip; that is what makes the contract above work.

No modelling tool? [`hauses/_examples/ravenmark/make_props.gd`](../hauses/_examples/ravenmark/make_props.gd)
builds a helm and a crest out of domes, bands and wedges in GDScript:

```bash
Godot --headless --path <game> -s res://hauses/_examples/ravenmark/make_props.gd -- ~/mynewhaus
```

---

## The optional extras

**Your own army.** `army` swaps the models for any of `pawn` `knight` `bishop`
`queen` `king` (there is no `rook`: the rook is a watchtower flying your
banner). The shipped example is the Drowned Legion —
[`hauses/tidegrip/haus.json`](../hauses/tidegrip/haus.json) fields five
skeleton models on the same rig.

If you override the army you must declare at least one `natural:` surface. An
army painted entirely in the haus colour is the monochrome army this whole
system exists to end, and the validator refuses it.

**Your own taunts.** `banter` is `{ beat: [lines] }` over the six beats
`game_start` `player_captured` `rival_captured` `check_given` `check_received`
`game_end`. Eight lines each is the shipped standard, ≤ 90 characters after
`{piece}` is substituted. A pack that declares the id of a shipped haus
replaces that haus's pool, which is how a translation or a rewrite ships
without touching the game.

**Your own music.** `music` names an audio file for your haus's theme.

---

## When something is wrong

Nothing here can crash the game and nothing here can take another haus down
with it. A pack whose manifest has errors is **skipped**, its reasons printed
once, and the rest of the roster loads:

```
HAUS PACK REFUSED  user://hauses/vaelor
    error: haus 'vaelor': coat 'electric_blue' is not a natural coat — allowed:
    bay, dark_bay, chestnut, liver_chestnut, black, white_grey, dapple_grey,
    drowned_grey, dun. A mount's haus identity lives in its CAPARISON, not in
    the animal: declare one of those, or supply your own "coat_palette" of real
    horse colours (near-colourless, or in the warm-brown band 5-58°).
```

Everything else is a **warning**: it names the default you just accepted and
what it will look like. Run the validator and read them; they are the things
that would otherwise surprise you on the board.

---

## Two spellings, on purpose

The game is **Great Hauses**; the house style is Bert's Sanctum dialect, where
the household is *the haus*. Everything you touch as a modder is spelled that
way: the folder is `hauses/`, the manifest is `haus.json`, the docs and every
message the loader and the validator print say **haus**.

The **code** underneath still spells it `house`, and deliberately so — renaming
identifiers would churn a suite that asserts on them for no reader's benefit.
So you will see, and should not be surprised by:

| you write / read | the code calls it |
|---|---|
| `hauses/<id>/haus.json` | `HousePack`, `HouseRegistry`, `MANIFEST_NAME` |
| your pack's `id` | `house_id`, `player_house_id` |
| the loader / validator source | `src/houses/houses.gd`, `src/houses/house_pack.gd`, `tools/validate_house_pack.gd` |
| the proof tool's flag | `--house=<id>` |

None of that leaks into a pack you author. Your manifest has no key that says
either word.

**No legacy fallback.** `houses/` and `house.json` are **not** read — not as a
fallback, not with a warning. The rename landed before any third-party pack
shipped, so there is nothing to be compatible with; a pack in a folder named
`houses/` is simply not discovered. If you built one in the hour before this
change: rename the directory to `hauses/` and the manifest to `haus.json`, and
nothing else moves.

---

## Where this lives in the code

| file | what it is |
|---|---|
| [`src/houses/house_pack.gd`](../src/houses/house_pack.gd) | the format, the validation rules, and the runtime loaders for dropped-in art |
| [`src/houses/houses.gd`](../src/houses/houses.gd) | discovery from `res://hauses/` + `user://hauses/`, and the roster |
| [`src/houses/coats.json`](../src/houses/coats.json) | the natural coats — the closed list |
| [`src/board/piece_assets.gd`](../src/board/piece_assets.gd) | `MATERIAL_ROLES`, and where a pack's declarations are folded in |
| [`tools/validate_house_pack.gd`](../tools/validate_house_pack.gd) | the checker you run before the game does |
| [`tests/test_house_packs.gd`](../tests/test_house_packs.gd) | the suite: the port is lossless, and every refusal above actually fires |
