# Haus Ravenmark — a worked example

A third-party haus pack, complete. It ships **nothing of the game's**: its own
sigil, its own half-helm, its own crest, its own taunts, and a natural coat.

```bash
# 1. check it
Godot --headless --path <game> -s res://tools/validate_house_pack.gd -- \
    res://hauses/_examples/ravenmark

# 2. install it — macOS
cp -R hauses/_examples/ravenmark \
    ~/Library/Application\ Support/Godot/app_userdata/Great\ Hauses/hauses/

# 3. play. It is in the Hall of Banners.
```

Its two models were built with no modelling tool at all:

```bash
Godot --headless --path <game> -s res://hauses/_examples/ravenmark/make_props.gd
```

Read `make_props.gd` for the engine's dressing contract in 200 lines, and
`haus.json` for the one line that matters most:

```json
"materials": { "ravenmark_beak": "natural:bone" }
```

That is what keeps Haus Ravenmark's purple off its raven's beak. The rest of
the crest is KIT and takes the jersey; the beak is BONE and does not. Same
mesh, two roles.

Full guide: [`docs/HAUS-PACK.md`](../../../docs/HAUS-PACK.md)
