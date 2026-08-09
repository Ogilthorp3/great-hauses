# Build your own Great House — in 20 minutes

A house in this game is **a folder**, not code. Drop the folder in, start the
game, and your banner hangs in the Hall with the other nine. No rebuild, no
recompile, no patch to the game.

```
ravenmark/
  house.json      the manifest — who you are, what colour you wear
  sigil.png       your heraldry
  pawn_helm.glb   your footmen's half-helm   (optional)
  crest.glb       your knights' crest        (optional)
```

There is a worked example of exactly that in
[`houses/_examples/ravenmark/`](../houses/_examples/ravenmark/) — House
Ravenmark, which ships its own sigil, its own helm, its own crest, its own
taunts, and whose two models were built by a 200-line GDScript with no
modelling tool at all. Copy it, or copy the blank
[`houses/_template/`](../houses/_template/).

---

## The 20 minutes

**1 · Copy the template** (2 min)

```bash
cp -R houses/_template ~/mynewhouse
```

**2 · Edit `house.json`** (10 min). The only field with no default is `id`.

```json
{
  "format": 1,
  "id": "ravenmark",
  "name": "House Ravenmark",
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
Godot --headless --path <game> -s res://tools/gen_sigils.gd -- --pack ~/mynewhouse
```

**4 · Check it** (1 min). Run the validator *before* the game does:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path <game> \
    -s res://tools/validate_house_pack.gd -- ~/mynewhouse
```

```
── /Users/you/mynewhouse
   house 'ravenmark' — House Ravenmark of Corvenhold
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

**5 · Install it** (1 min). Move the folder into `user://houses/`:

| platform | `user://houses/` is |
|---|---|
| macOS | `~/Library/Application Support/Godot/app_userdata/Great Houses/houses/` |
| Linux | `~/.local/share/godot/app_userdata/Great Houses/houses/` |
| Windows | `%APPDATA%\Godot\app_userdata\Great Houses\houses\` |

Start the game. Your house is in the Hall of Banners, playable, with its
sigil on every shield, its colour on every tabard, its helm on every pawn.

---

## The two hard rules

Everything in this format is optional and forgiving except two things. Both
exist because the game's armies were broken once, in each direction, and the
fixes cost real work.

### 1 · Your horse is a horse

> *"Horse should be brown, black or white, something majestic."*

Nine houses once rode nine horses dyed in nine house colours — a steel-blue
charger, a gold one. A blue horse is a bug, not heraldry: a mount's house
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
house 'vaelor': coat_palette.Main = #2e5cff is not a coat a horse comes in
(saturation 0.82, hue 220°) — a coat colour is either near-colourless
(s <= 0.20: black, grey, white) or a warm brown (hue 5-58°: bay, chestnut,
dun). Blue horses are a bug, not heraldry.
```

One more: **your coat may not be your jersey.** They must sit at least 0.14
apart in RGB, because a horse wearing the house colour is precisely what the
rule above forbids. (This is why the shipped bronze house rides a grey.)

### 2 · The house colour goes on the KIT, and nowhere else

This is the important one.

The game once painted the house hue on **every** surface — and to survive that
on skin, steel and horsehide the saturation had to be driven to zero. The
result was nine monochrome armies that all looked like the same team in
different lighting. The owner, looking at them:

> *"The figurines are too much mono color, should be like a hockey team jersey
> — colors of the team/house, but NOT everywhere."*

So the pipeline stopped asking *what colour is this house* and started asking
**what is this surface made of**:

| role | what it is | what it does |
|---|---|---|
| **KIT** | tabard, cloak, hood, shield face, caparison, helm, crest, plume, sash | wears the house jersey, confidently saturated |
| **NATURAL** | steel, leather, wood, stone, skin, bone, the horse's coat | keeps its own colours; at most a whisper of house in the shadows |
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
steel — and steel is NATURAL. The house colour goes on the kit (tabard, cloak,
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
| `name` | no | `House <Id>` |
| `archetype` | no | `wolf`. Picks the taunting **voice** and the generated sigil's mark |
| `seat` | no | `an old keep` |
| `motto` | no | empty — the house rides to war in silence |
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
house* second. Two surfaces:

- `pawnhelm_iron` — the dome. Painted in your house colour, dyed dark.
- `pawnhelm_accent` — the rim and motif. Painted in your house **charge**: the
  one of your four declared colours that stands furthest off the dome. This is
  computed, not declared, so your motif can never come out green-on-green.

**The crest** TOWERS over the head, and is worn by knight, queen and king only.
Name the **mesh node** `Crest_<yourid>` and the whole thing is KIT.

Both are ordinary `.glb` files. A pack dropped into `user://houses/` never goes
through the editor's import pipeline, so the game parses your models and images
**at runtime** — which is exactly why a DLC house needs no rebuild. Material
names survive that trip; that is what makes the contract above work.

No modelling tool? [`houses/_examples/ravenmark/make_props.gd`](../houses/_examples/ravenmark/make_props.gd)
builds a helm and a crest out of domes, bands and wedges in GDScript:

```bash
Godot --headless --path <game> -s res://houses/_examples/ravenmark/make_props.gd -- ~/mynewhouse
```

---

## The optional extras

**Your own army.** `army` swaps the models for any of `pawn` `knight` `bishop`
`queen` `king` (there is no `rook`: the rook is a watchtower flying your
banner). The shipped example is the Drowned Legion —
[`houses/tidegrip/house.json`](../houses/tidegrip/house.json) fields five
skeleton models on the same rig.

If you override the army you must declare at least one `natural:` surface. An
army painted entirely in the house colour is the monochrome army this whole
system exists to end, and the validator refuses it.

**Your own taunts.** `banter` is `{ beat: [lines] }` over the six beats
`game_start` `player_captured` `rival_captured` `check_given` `check_received`
`game_end`. Eight lines each is the shipped standard, ≤ 90 characters after
`{piece}` is substituted. A pack that declares the id of a shipped house
replaces that house's pool, which is how a translation or a rewrite ships
without touching the game.

**Your own music.** `music` names an audio file for your house's theme.

---

## When something is wrong

Nothing here can crash the game and nothing here can take another house down
with it. A pack whose manifest has errors is **skipped**, its reasons printed
once, and the rest of the roster loads:

```
HOUSE PACK REFUSED  user://houses/vaelor
    error: house 'vaelor': coat 'electric_blue' is not a natural coat — allowed:
    bay, dark_bay, chestnut, liver_chestnut, black, white_grey, dapple_grey,
    drowned_grey, dun. A mount's house identity lives in its CAPARISON, not in
    the animal: declare one of those, or supply your own "coat_palette" of real
    horse colours (near-colourless, or in the warm-brown band 5-58°).
```

Everything else is a **warning**: it names the default you just accepted and
what it will look like. Run the validator and read them; they are the things
that would otherwise surprise you on the board.

---

## Where this lives in the code

| file | what it is |
|---|---|
| [`src/houses/house_pack.gd`](../src/houses/house_pack.gd) | the format, the validation rules, and the runtime loaders for dropped-in art |
| [`src/houses/houses.gd`](../src/houses/houses.gd) | discovery from `res://houses/` + `user://houses/`, and the roster |
| [`src/houses/coats.json`](../src/houses/coats.json) | the natural coats — the closed list |
| [`src/board/piece_assets.gd`](../src/board/piece_assets.gd) | `MATERIAL_ROLES`, and where a pack's declarations are folded in |
| [`tools/validate_house_pack.gd`](../tools/validate_house_pack.gd) | the checker you run before the game does |
| [`tests/test_house_packs.gd`](../tests/test_house_packs.gd) | the suite: the port is lossless, and every refusal above actually fires |
