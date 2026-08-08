class_name MusicCredits
extends RefCounted
## Static music attribution for the in-game credits display.
##
## CC BY 4.0 REQUIRES this attribution to be shown in-game — the integrator
## surfaces get_credits_text() (or the one-line get_credits_short()) in the
## house-select footer. Text mirrors the ready-to-paste block in
## assets/music/CREDITS.md (kept as a const so exported builds never depend
## on a non-resource .md file surviving the export filter).
##
## Full provenance: assets/music/CREDITS.md and the per-track .license.txt
## files beside each mp3; license texts in assets/music/licenses/.

const CREDITS_TEXT := """Music — licensed under CC BY 4.0 / CC0 1.0:

"Teller of the Tales", "Minstrel Guild", "Achaidh Cheide", "Lord of the Land",
"Skye Cuillin", "Fanfare for Space", "Agnus Dei X"
Kevin MacLeod (incompetech.com)
Licensed under Creative Commons: By Attribution 4.0 License
http://creativecommons.org/licenses/by/4.0/

"Orchestral Stinger - Dramatic Entrance" by Thor Arisland (tcarisland), opengameart.org
Licensed under Creative Commons: By Attribution 4.0 License
http://creativecommons.org/licenses/by/4.0/

Additional music (CC0, public domain):
"Medieval: Victory Theme" by RandomMind (opengameart.org)
"Dark Stinger 1" by Kresiek The Furry (opengameart.org)"""

const CREDITS_SHORT := "Music: Kevin MacLeod (incompetech.com), CC BY 4.0 · " \
		+ "Thor Arisland (opengameart.org), CC BY 4.0 · RandomMind & Kresiek The Furry, CC0"


## The full attribution block (multi-line) for a credits screen or footer popup.
static func get_credits_text() -> String:
	return CREDITS_TEXT


## Compact one-liner for tight UI (house-select footer strip).
static func get_credits_short() -> String:
	return CREDITS_SHORT
