# houses/ — one folder per Great House

The nine that ship with the game live here, one directory each, discovered at
startup in the order named by `index.json` (that order is the tournament seed
order). A house is DATA: `house.json` plus whatever art it points at.

- `_template/` — copy this to start your own. Skipped by discovery (leading `_`).
- `_examples/ravenmark/` — a complete third-party pack, art and all.

A house a player installs goes in `user://houses/` instead and needs no
rebuild. Both directories are scanned; a pack with errors is skipped with its
reasons printed, and never takes the others down.

The format, the two hard rules, and the 20-minute walkthrough:
[`docs/HOUSE-PACK.md`](../docs/HOUSE-PACK.md).
