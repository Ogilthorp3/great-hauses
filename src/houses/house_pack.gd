class_name HousePack
extends RefCounted
## ONE HAUS, ONE FOLDER — the haus-pack format and its validator.
##
## A haus is DATA, not code. Everything the game knows about a Great Haus
## lives in one directory holding a `haus.json` manifest and (optionally) the
## haus's own art:
##
##     hauses/ravenmark/
##       haus.json           the manifest — this file's subject
##       sigil.png           its heraldry
##       pawn_helm.glb       its footmen's half-helm      (optional)
##       crest.glb           its knights'/royals' crest   (optional)
##
## The game discovers packs in TWO places (HouseRegistry):
##   res://hauses/    the nine that ship with the game
##   user://hauses/   anything a player drops in — a DLC haus needs NO rebuild
##
## This script is deliberately dependency-free: it never names the PieceAssets
## autoload, so `godot --headless -s res://tools/validate_house_pack.gd` (which
## runs with no autoloads at all) can use it. Roles and stuffs are carried as
## STRINGS here and mapped to PieceAssets.Role / PieceAssets.Stuff there;
## tests/test_house_packs.gd asserts the two vocabularies have not drifted.
##
## ── THE ONE RULE A PACK CANNOT BREAK ──────────────────────────────────────
##
## The game paints the haus colour on KIT and on nothing else. Steel, leather,
## wood, stone, skin, bone and the horse's COAT are NATURAL and keep their own
## colours; the crown is REGALIA and stays metal; the sigil, banner and glyph
## ring are HERALDRY and carry their own artwork (PieceAssets.MATERIAL_ROLES).
## That discipline is four rounds of art work, and a stranger's haus must not
## be able to undo it. So it is enforced BY CONSTRUCTION, in three layers:
##
##   1. A pack may only declare roles for surfaces it OWNS. Every declared
##      surface name must begin with "<haus id>_", which makes a collision
##      with an engine surface — or with another pack's — impossible. A pack
##      cannot say "the horse's Main mesh is kit", because it cannot name it.
##   2. The engine's dressing CONTRACT names (pawnhelm_iron, pawnhelm_accent,
##      Crest_*) are the pack's way IN: name a helm's two surfaces that and the
##      engine dresses them for you. They may not be redeclared.
##   3. What a pack CAN name, it is still held to: a surface whose own name
##      says steel/skin/bone/hide/coat/leather/wood/stone may not be declared
##      KIT, an army override may not consist only of kit, and the `coat` field
##      must name one of the natural coats (src/houses/coats.json) — because a
##      blue horse is a bug, not heraldry.
##
## Everything else degrades: a missing sigil, crest, helm, motto or palette
## produces a documented default and a WARNING a modder can read, never a
## crash and never a silent guess. One bad pack is skipped with its reasons
## printed; the others load.

## Manifest format this build understands. A pack declaring a HIGHER number is
## refused (it wants engine features this build does not have); a pack
## declaring a lower one, or none, is read as format 1.
const FORMAT := 1

const COATS_PATH := "res://src/houses/coats.json"
const MANIFEST_NAME := "haus.json"

## Roles a pack may declare for its own surfaces. Mirrors PieceAssets.Role,
## minus MIXED — the per-triangle atlas split is for the shipped marketplace
## casts, whose one 1024² texture paints cloth, steel and skin on a single
## mesh. A pack authors its own models and can simply give them one material
## per material.
const ROLES := ["kit", "natural", "regalia", "heraldry", "effect"]
## What a NATURAL surface is made of — mirrors PieceAssets.Stuff (lowercased).
const STUFFS := ["steel", "leather", "wood", "stone", "skin", "bone", "coat",
	"glow", "atlas", "none"]

## The engine's dressing contract: name a surface one of these in your own
## model and the game paints it for you (the helm's dome and rim in the haus
## colour and its charge, the crest as kit). They belong to the engine, so a
## pack neither declares them nor may shadow them.
const CONTRACT_MATERIALS := ["pawnhelm_iron", "pawnhelm_accent", "Crest_*"]

## Ids whose "<id>_" prefix would collide with a name the ENGINE already
## classifies (crest_*, tower_*, pawnhelm_*, glyphring_*, banner_cloth …). The
## prefix rule is what makes a merged role table safe, so an id that breaks it
## is refused rather than quietly given power over the engine's own surfaces.
const RESERVED_IDS := ["crest", "tower", "pawnhelm", "glyphring", "banner",
	"pennant", "caparison", "crinet", "chanfron", "saddle", "shield", "sword",
	"staff", "spellbook", "bow", "quiver", "crown", "cape", "main", "muzzle",
	"hair", "hooves", "eye", "glow", "skeleton", "sigildecal", "striketrail"]

## Words that make a surface NATURAL no matter what a manifest says. A pack
## that declares `<id>_saddle_leather` as KIT is refused by name alone — it is
## the cheapest half of the "never dye the horse" rule, and it catches the
## honest mistake (a modder who thinks "kit" means "mine") before the role gate
## has to catch it in a render.
const NATURAL_WORDS := ["steel", "skin", "flesh", "bone", "skull", "hide",
	"coat", "horse", "mane", "hoof", "leather", "wood", "timber", "stone"]

## Piece-type names a pack may override army models for, in PieceView.Type
## order. ROOK is absent on purpose: the rook is a watchtower, not a figure.
const ARMY_TYPES := {"pawn": 0, "knight": 2, "bishop": 3, "queen": 4, "king": 5}

## Keys a manifest may carry. Anything else is a typo worth a warning.
const KNOWN_KEYS := ["format", "id", "name", "archetype", "seat", "motto",
	"colors", "tints", "coat", "coat_palette", "sigil", "crest", "pawn_helm",
	"materials", "army", "banter", "music", "_comment", "_readme", "_doc"]

## The six materials a horse's coat palette must name (convert_horse.py).
const COAT_PARTS := ["Main", "Main_Light", "Main_Dark", "Muzzle", "Hair", "Hooves"]

# ── the laws, in numbers ──────────────────────────────────────────────────
# These are not new thresholds: each is the number the shipped role gate
# (costume_preview.role_offenders) and the costume suite already judge a
# rendered army by. Checking them HERE means a modder reads a sentence instead
# of a failed screenshot.

## A coat colour is a real coat colour if it is near-colourless, or sits in the
## pack's warm-brown band. costume_preview.NATURAL_WARM_LO/HI.
const COAT_MAX_SAT := 0.20
const COAT_WARM_LO := 5.0
const COAT_WARM_HI := 58.0
## How far a natural surface must stay from the haus's kit colour.
## costume_preview.NATURAL_KIT_DISTANCE.
const COAT_KIT_DISTANCE := 0.14
## A jersey below this saturation reads as grey at board distance
## (tests/test_costumes.gd asserts it for the shipped nine). WARNING, not an
## error — a haus may want a pale jersey, it just wants to know.
const KIT_MIN_SAT := 0.40
## Two hauses whose jerseys sit closer than this are hard to tell apart on the
## board. WARNING: what else is installed is not the pack author's fault.
const KIT_DISTINCT := 0.20

## Defaults, all documented in docs/HAUS-PACK.md.
const DEFAULT_COLORS := {"primary": "#8d99a6", "secondary": "#eef2f5", "accent": "#b9c4cf"}
const DEFAULT_TINT_SATURATION := 0.25
const DEFAULT_ARCHETYPE := "wolf"


## Read + validate one pack directory.
##
## `dir_path` is a res:// or user:// directory holding haus.json; `source` is
## "builtin" or "installed" (bookkeeping only — the rules are identical).
## Never throws, never push_error()s: the report IS the output.
##
## Returns {ok, id, dir, source, house, errors: Array[String], warnings: Array[String]}
static func load_from_dir(dir_path: String, source: String = "installed") -> Dictionary:
	var manifest_path := dir_path.path_join(MANIFEST_NAME)
	var rep := _empty_report(dir_path, source)
	if not FileAccess.file_exists(manifest_path):
		rep["errors"].append("no %s in %s — a haus pack is a FOLDER containing that file"
				% [MANIFEST_NAME, dir_path])
		return rep
	var f := FileAccess.open(manifest_path, FileAccess.READ)
	if f == null:
		rep["errors"].append("cannot read %s (error %d)"
				% [manifest_path, FileAccess.get_open_error()])
		return rep
	var text := f.get_as_text()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		rep["errors"].append("%s is not valid JSON: line %d: %s"
				% [MANIFEST_NAME, json.get_error_line(), json.get_error_message()])
		return rep
	if not json.data is Dictionary:
		rep["errors"].append("%s must be a JSON object { ... }, got %s"
				% [MANIFEST_NAME, type_string(typeof(json.data))])
		return rep
	return parse(json.data, dir_path, source)


## Validate an already-parsed manifest. Split out from load_from_dir so tests
## can feed it hand-built dictionaries without touching the filesystem.
static func parse(m: Dictionary, dir_path: String,
		source: String = "installed") -> Dictionary:
	var rep := _empty_report(dir_path, source)
	var errors: Array[String] = rep["errors"]
	var warnings: Array[String] = rep["warnings"]

	# -- format ------------------------------------------------------------
	var fmt := int(m.get("format", FORMAT))
	if fmt > FORMAT:
		errors.append(("manifest format %d is newer than this build understands "
				+ "(%d) — update the game, or lower \"format\"") % [fmt, FORMAT])
		return rep

	# -- id: the one field with no default ---------------------------------
	var id := str(m.get("id", "")).strip_edges()
	if id.is_empty():
		errors.append("no \"id\" — every haus needs one, lowercase and unique "
				+ "(e.g. \"ravenmark\"); it is how saves, the tournament bracket "
				+ "and your asset names refer to this haus")
		return rep
	if not _is_valid_id(id):
		errors.append(("id '%s' is not a legal id — use lowercase letters, digits "
				+ "and underscores only (a-z, 0-9, _)") % id)
		return rep
	if RESERVED_IDS.has(id):
		errors.append(("id '%s' is reserved — the engine already classifies "
				+ "surfaces beginning with \"%s_\", and your pack's surfaces must "
				+ "be able to claim that prefix for themselves. Pick another id "
				+ "(reserved: %s)") % [id, id, ", ".join(RESERVED_IDS)])
		return rep
	rep["id"] = id

	for key in m.keys():
		# JSON has no comments, so ANY key starting with "_" is one. It is how
		# the template manifest carries its own instructions.
		if not str(key).begins_with("_") and not KNOWN_KEYS.has(str(key)):
			warnings.append("unknown key \"%s\" ignored — check the spelling against "
					% str(key) + "docs/HAUS-PACK.md")

	# -- the words on the banner -------------------------------------------
	var house := {"id": id}
	house["name"] = str(m.get("name", "")).strip_edges()
	if house["name"].is_empty():
		house["name"] = "Haus %s" % id.capitalize()
		warnings.append("no \"name\" — the Hall of Banners will read \"%s\"" % house["name"])
	house["archetype"] = str(m.get("archetype", "")).strip_edges()
	if house["archetype"].is_empty():
		house["archetype"] = DEFAULT_ARCHETYPE
		warnings.append(("no \"archetype\" — defaulting to \"%s\". The archetype "
				+ "picks the rival's taunting VOICE (BanterEngine.ARCHETYPE_VOICE) "
				+ "and, if you generate one, the sigil's mark")
				% DEFAULT_ARCHETYPE)
	house["seat"] = str(m.get("seat", ""))
	if str(house["seat"]).is_empty():
		house["seat"] = "an old keep"
		warnings.append("no \"seat\" — the Hall of Banners will read \"an old keep\"")
	house["motto"] = str(m.get("motto", ""))
	if str(house["motto"]).is_empty():
		warnings.append("no \"motto\" — the haus rides to war in silence "
				+ "(the pledge banner and the rival's persona prompt both use it)")

	# -- colours ------------------------------------------------------------
	house["colors"] = _read_colors(m, warnings)
	house["tints"] = _read_tints(m, house["colors"], warnings)
	var kit := Color.html(str(house["tints"]["kit"]))
	if kit.s < KIT_MIN_SAT:
		warnings.append(("jersey %s is nearly colourless (saturation %.2f < %.2f) "
				+ "— it will read as grey at board distance. tints.kit is the ONE "
				+ "saturated colour your kit is painted in; it can afford to be loud, "
				+ "because it is no longer painted on steel, skin or the horse")
				% [str(house["tints"]["kit"]), kit.s, KIT_MIN_SAT])

	# -- the coat: the hard rule --------------------------------------------
	_read_coat(m, house, kit, errors, warnings)

	# -- art ----------------------------------------------------------------
	house["sigil"] = _read_asset(m, "sigil", dir_path, warnings,
			"the Hall of Banners will hang a flat %s shield instead"
					% str(house["colors"]["primary"]))
	house["crest"] = _read_asset(m, "crest", dir_path, warnings,
			"knights, queens and kings ride bare-headed (no crest is not an error)")
	house["pawn_helm"] = _read_asset(m, "pawn_helm", dir_path, warnings,
			"pawns keep the cast's own headgear instead of a haus half-helm")

	# -- material roles: the pack's half of the discipline -------------------
	house["materials"] = _read_materials(m, id, errors, warnings)

	# -- optional extras -----------------------------------------------------
	house["army"] = _read_army(m, dir_path, house["materials"], errors, warnings)
	house["banter"] = _read_banter(m, warnings)
	house["music"] = _read_asset(m, "music", dir_path, warnings,
			"the haus rides to the shipped playlist")

	house["pack_dir"] = dir_path
	house["source"] = source
	rep["house"] = house
	rep["ok"] = errors.is_empty()
	return rep


# ── colours ────────────────────────────────────────────────────────────────


static func _read_colors(m: Dictionary, warnings: Array[String]) -> Dictionary:
	var raw: Dictionary = m.get("colors", {}) if m.get("colors") is Dictionary else {}
	if not m.has("colors"):
		warnings.append(("no \"colors\" — falling back to the neutral steel "
				+ "palette %s. These three are your heraldry: primary is the "
				+ "banner field, secondary and accent its charges")
				% str(DEFAULT_COLORS))
	var out := {}
	for key in ["primary", "secondary", "accent"]:
		var v := str(raw.get(key, ""))
		if v.is_empty():
			out[key] = DEFAULT_COLORS[key]
			if m.has("colors"):
				warnings.append("colors.%s missing — using %s" % [key, out[key]])
		elif not Color.html_is_valid(v):
			out[key] = DEFAULT_COLORS[key]
			warnings.append("colors.%s = \"%s\" is not a hex colour (want \"#rrggbb\") — using %s"
					% [key, v, out[key]])
		else:
			out[key] = v
	return out


## tints.kit is THE JERSEY; tints.piece / tints.tower are the faint whisper
## natural surfaces take so an army still hangs together. A pack that declares
## none of them inherits its heraldic colours, which is what a haus with no
## opinion should look like.
static func _read_tints(m: Dictionary, colors: Dictionary,
		warnings: Array[String]) -> Dictionary:
	var raw: Dictionary = m.get("tints", {}) if m.get("tints") is Dictionary else {}
	var out := {}
	var kit := str(raw.get("kit", ""))
	if kit.is_empty() or not Color.html_is_valid(kit):
		if not kit.is_empty():
			warnings.append("tints.kit = \"%s\" is not a hex colour — using colors.primary" % kit)
		else:
			warnings.append(("no \"tints.kit\" — your kit takes colors.primary (%s). "
					+ "tints.kit is worth declaring: it is the one colour your "
					+ "tabards, cloaks, shields and caparison are painted in")
					% str(colors["primary"]))
		kit = str(colors["primary"])
	out["kit"] = kit
	for key in ["piece", "tower"]:
		var v := str(raw.get(key, ""))
		if v.is_empty() or not Color.html_is_valid(v):
			# The whisper defaults to a DESATURATED cut of the jersey — loud on
			# the kit, a hint on the steel, which is the whole point of the
			# split. Nothing to warn about; this is a sane haus.
			var base := Color.html(kit)
			var soft := Color.from_hsv(base.h, minf(base.s, 0.45),
					clampf(base.v * (1.0 if key == "piece" else 0.86), 0.05, 1.0))
			v = soft.to_html(false)
			if not str(raw.get(key, "")).is_empty():
				warnings.append("tints.%s is not a hex colour — using %s" % [key, v])
		out[key] = v
	out["saturation"] = float(raw.get("saturation", DEFAULT_TINT_SATURATION))
	return out


# ── the coat ───────────────────────────────────────────────────────────────


## THE HARD RULE. `coat` names one of the natural coats in coats.json, or the
## pack supplies its own palette inline — and either way every colour in it is
## held to the law a rendered coat is held to. A haus's identity is worn on
## the caparison; the animal under it is an animal.
static func _read_coat(m: Dictionary, house: Dictionary, kit: Color,
		errors: Array[String], warnings: Array[String]) -> void:
	var table := natural_coats()
	var name := str(m.get("coat", "")).strip_edges()
	var custom: Dictionary = m.get("coat_palette", {}) \
			if m.get("coat_palette") is Dictionary else {}
	house["coat"] = name
	house["coat_palette"] = {}

	if name.is_empty() and custom.is_empty():
		house["coat"] = coat_default()
		warnings.append(("no \"coat\" — the haus rides a %s. Pick one of: %s")
				% [coat_default(), ", ".join(coat_names())])
	elif not custom.is_empty():
		# An inline palette: the pack is authoring a new coat. Every part must
		# be present, and every colour must be a colour a horse can be.
		if name.is_empty():
			house["coat"] = "%s_custom" % str(house["id"])
		for part in COAT_PARTS:
			if not custom.has(part):
				errors.append(("coat_palette is missing \"%s\" — a coat names all "
						+ "six: %s (Main is the hide, Main_Light the blaze and socks, "
						+ "Main_Dark the ears, Muzzle the nose, Hair the mane and "
						+ "tail, Hooves the feet)") % [part, ", ".join(COAT_PARTS)])
		for part in custom.keys():
			var v := str(custom[part])
			if not Color.html_is_valid(v):
				errors.append("coat_palette.%s = \"%s\" is not a hex colour" % [part, v])
				continue
			var c := Color.html(v)
			if not is_natural_color(c):
				errors.append(_unnatural_coat_message(str(house["id"]),
						"coat_palette.%s" % part, v, c))
			house["coat_palette"][part] = v
	elif not table.has(name):
		errors.append(_unknown_coat_message(str(house["id"]), name))
		house["coat"] = coat_default()

	# ...and whichever coat won, it may not be the jersey. This is the exact
	# check the role gate makes on the rendered horse (a NATURAL surface may
	# not wear the haus kit) — caught here, it costs a sentence instead of a
	# red gate and a screenshot.
	var palette: Dictionary = house["coat_palette"]
	if palette.is_empty():
		palette = table.get(house["coat"], {})
	for part in palette.keys():
		var v := str(palette[part])
		if not Color.html_is_valid(v):
			continue
		var c := Color.html(v)
		var gap := _rgb_gap(c, kit)
		if gap <= COAT_KIT_DISTANCE:
			errors.append(("coat '%s' part %s (%s) is your own jersey colour (%s) "
					+ "— they sit %.2f apart and the role gate refuses anything "
					+ "under %.2f. A horse wearing the haus colour IS the defect "
					+ "this rule exists for: pick a coat that stands off your kit "
					+ "(Hartcrown's bronze haus rides a grey for exactly this "
					+ "reason)") % [str(house["coat"]), part, v, kit.to_html(false),
					gap, COAT_KIT_DISTANCE])
			break


static func _unknown_coat_message(id: String, name: String) -> String:
	return ("haus '%s': coat '%s' is not a natural coat — allowed: %s. "
			+ "A mount's haus identity lives in its CAPARISON, not in the animal: "
			+ "declare one of those, or supply your own \"coat_palette\" of real "
			+ "horse colours (near-colourless, or in the warm-brown band %d-%d°)."
			) % [id, name, ", ".join(coat_names()), int(COAT_WARM_LO), int(COAT_WARM_HI)]


static func _unnatural_coat_message(id: String, field: String, hex: String,
		c: Color) -> String:
	return ("haus '%s': %s = %s is not a coat a horse comes in (saturation %.2f, "
			+ "hue %d°) — a coat colour is either near-colourless (s <= %.2f: black, "
			+ "grey, white) or a warm brown (hue %d-%d°: bay, chestnut, dun). "
			+ "Blue horses are a bug, not heraldry."
			) % [id, field, hex, c.s, int(c.h * 360.0), COAT_MAX_SAT,
			int(COAT_WARM_LO), int(COAT_WARM_HI)]


## Is this a colour a horse comes in? Near-colourless, or the warm-brown band.
static func is_natural_color(c: Color) -> bool:
	var hue := c.h * 360.0
	return c.s <= COAT_MAX_SAT or (hue >= COAT_WARM_LO and hue <= COAT_WARM_HI)


# ── material roles ─────────────────────────────────────────────────────────


## The pack's own surfaces and what they are MADE OF. Returns
## {"<id>_surface": {"role": String, "stuff": String}}.
static func _read_materials(m: Dictionary, id: String, errors: Array[String],
		warnings: Array[String]) -> Dictionary:
	var out := {}
	if not m.has("materials"):
		return out
	if not m["materials"] is Dictionary:
		errors.append("\"materials\" must be an object mapping surface name -> role, "
				+ "e.g. { \"%s_helm_plume\": \"kit\", \"%s_horn\": \"natural:bone\" }"
				% [id, id])
		return out
	for key in (m["materials"] as Dictionary).keys():
		var surface := str(key)
		var spec := str((m["materials"] as Dictionary)[key]).strip_edges().to_lower()
		var prefix := "%s_" % id
		if _is_contract_material(surface):
			errors.append(("materials: '%s' is one of the engine's own dressing "
					+ "contract names (%s) — do not declare it. Name a surface that "
					+ "in your model and the game paints it for you; the contract "
					+ "belongs to the engine") % [surface, ", ".join(CONTRACT_MATERIALS)])
			continue
		if not surface.begins_with(prefix):
			errors.append(("materials: surface '%s' must be named \"%s...\" — a pack "
					+ "may only declare roles for surfaces it OWNS, and the prefix "
					+ "is what makes that true. Rename the material in your model "
					+ "(this is also what keeps two installed packs from fighting "
					+ "over the same name)") % [surface, prefix])
			continue
		var role := spec
		var stuff := "none"
		if spec.contains(":"):
			var bits := spec.split(":", true, 1)
			role = bits[0]
			stuff = bits[1]
		if role == "mixed":
			errors.append(("materials: '%s' is declared \"mixed\" — that role is "
					+ "reserved for the shipped marketplace casts, whose ONE atlas "
					+ "paints cloth, steel and skin onto a single mesh. Give your "
					+ "own model one material per material and declare each") % surface)
			continue
		if not ROLES.has(role):
			errors.append(("materials: '%s' has role \"%s\", which is not a role — "
					+ "use one of: %s. KIT carries the haus colour; NATURAL keeps "
					+ "its own (say what of: natural:steel, natural:leather, "
					+ "natural:bone…); REGALIA stays metal; HERALDRY carries its own "
					+ "artwork; EFFECT owns its own light")
					% [surface, spec, ", ".join(ROLES)])
			continue
		if role == "natural":
			if not STUFFS.has(stuff):
				errors.append(("materials: '%s' is natural, but \"%s\" is not a "
						+ "material family — write natural:<stuff> with one of: %s")
						% [surface, stuff, ", ".join(STUFFS)])
				continue
		elif stuff != "none":
			warnings.append("materials: '%s' is %s — the \":%s\" is ignored (only "
					% [surface, role, stuff] + "natural surfaces have a stuff)")
			stuff = "none"
		if role == "kit":
			var offender := _natural_word_in(surface)
			if not offender.is_empty():
				errors.append(("materials: '%s' is declared KIT, but its own name "
						+ "says %s — and %s is NATURAL. The haus colour goes on the "
						+ "kit (tabard, cloak, shield face, caparison, helm, crest) "
						+ "and nowhere else: steel stays steel, leather stays "
						+ "leather, and the horse keeps its coat. Declare it "
						+ "\"natural:%s\", or rename the surface if it really is "
						+ "cloth") % [surface, offender, offender,
						_stuff_for_word(offender)])
				continue
		out[surface] = {"role": role, "stuff": stuff}
	return out


static func _is_contract_material(surface: String) -> bool:
	for c: String in CONTRACT_MATERIALS:
		if surface.begins_with(c) or surface.matchn("%s*" % c):
			return true
	return false


static func _natural_word_in(surface: String) -> String:
	for w: String in NATURAL_WORDS:
		if surface.to_lower().contains(w):
			return w
	return ""


static func _stuff_for_word(word: String) -> String:
	match word:
		"steel": return "steel"
		"skin", "flesh": return "skin"
		"bone", "skull": return "bone"
		"hide", "coat", "horse", "mane", "hoof": return "coat"
		"leather": return "leather"
		"wood", "timber": return "wood"
		"stone": return "stone"
	return "steel"


# ── optional extras ────────────────────────────────────────────────────────


## Army model overrides — {piece type int -> resource path}. The Drowned Legion
## (Tidegrip) is the shipped example: same rig, skeleton cast swapped in whole.
static func _read_army(m: Dictionary, dir_path: String, materials: Dictionary,
		errors: Array[String], warnings: Array[String]) -> Dictionary:
	var out := {}
	if not m.has("army"):
		return out
	if not m["army"] is Dictionary:
		errors.append("\"army\" must be an object mapping piece type -> model path, "
				+ "e.g. { \"pawn\": \"minion.glb\" }. Types: %s"
				% ", ".join(ARMY_TYPES.keys()))
		return out
	for key in (m["army"] as Dictionary).keys():
		var type_name := str(key).to_lower()
		if not ARMY_TYPES.has(type_name):
			errors.append(("army: \"%s\" is not a piece type — use %s. (There is no "
					+ "\"rook\": the rook is a watchtower flying your banner, not a "
					+ "figure)") % [str(key), ", ".join(ARMY_TYPES.keys())])
			continue
		var path := resolve_path(dir_path, str((m["army"] as Dictionary)[key]))
		if not _asset_exists(path):
			warnings.append(("army.%s points at \"%s\", which is not there — that "
					+ "rank keeps the shipped cast") % [type_name, path])
			continue
		out[int(ARMY_TYPES[type_name])] = path
	# THE MONOCHROME GUARD. An army you supply is an army you must describe, and
	# an army described as nothing but kit is nine monochrome armies again.
	if not out.is_empty() and not materials.is_empty():
		var has_natural := false
		for surface in materials.keys():
			if str(materials[surface]["role"]) == "natural":
				has_natural = true
				break
		if not has_natural:
			errors.append(("army: you override %d model(s) and every one of the %d "
					+ "surfaces you declare is KIT — that is an army painted "
					+ "entirely in the haus colour, which is the exact failure the "
					+ "role system exists to end. Real soldiers are mostly steel, "
					+ "leather, skin and bone; declare at least one natural:<stuff>")
					% [out.size(), materials.size()])
	return out


static func _read_banter(m: Dictionary, warnings: Array[String]) -> Dictionary:
	if not m.has("banter"):
		return {}
	if not m["banter"] is Dictionary:
		warnings.append("\"banter\" must be an object of beat -> [lines]; ignored")
		return {}
	var out := {}
	for beat in (m["banter"] as Dictionary).keys():
		var lines: Variant = (m["banter"] as Dictionary)[beat]
		if not lines is Array:
			warnings.append("banter.%s is not a list of lines; ignored" % str(beat))
			continue
		var kept: Array = []
		for l in (lines as Array):
			kept.append(str(l))
		out[str(beat)] = kept
	return out


# ── paths ──────────────────────────────────────────────────────────────────


static func _read_asset(m: Dictionary, key: String, dir_path: String,
		warnings: Array[String], consequence: String) -> String:
	var raw := str(m.get(key, "")).strip_edges()
	if raw.is_empty():
		return ""
	var path := resolve_path(dir_path, raw)
	if not _asset_exists(path):
		warnings.append("\"%s\": \"%s\" is not there (looked in %s) — %s"
				% [key, raw, path, consequence])
		return ""
	return path


## A manifest path is either PACK-RELATIVE ("sigil.png" — the normal case, and
## what makes a pack a self-contained folder you can zip) or an absolute
## res:// / user:// path (how the shipped nine point at the game's own art).
static func resolve_path(dir_path: String, raw: String) -> String:
	if raw.is_empty():
		return ""
	if raw.begins_with("res://") or raw.begins_with("user://") or raw.begins_with("/"):
		return raw
	return dir_path.path_join(raw)


static func _asset_exists(path: String) -> bool:
	if path.is_empty():
		return false
	if path.begins_with("res://"):
		# In an exported game the source .png/.glb is gone and only the imported
		# resource remains, so ask the loader, not the filesystem.
		return ResourceLoader.exists(path) or FileAccess.file_exists(path)
	return FileAccess.file_exists(path)


# ── loading a pack's own art, at RUNTIME ───────────────────────────────────
#
# This is what makes a DLC pack a DLC pack. Anything under res:// went through
# the editor's import pipeline and is loaded with ResourceLoader. Anything a
# player DROPPED IN did not — there is no .import file, no .godot/imported
# artifact, and ResourceLoader will not touch it. So those are parsed at
# runtime: images with Image.load_from_file, models with GLTFDocument. A pack
# is a folder of ordinary PNGs and GLBs, exactly as a modder expects.


## A pack texture: imported if it lives in the game, parsed at runtime if a
## player dropped it in. null (never a crash) if it cannot be read.
static func load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if path.begins_with("res://"):
		if not ResourceLoader.exists(path):
			return null
		var res := ResourceLoader.load(path)
		return res as Texture2D
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img == null:
		push_warning("HousePack: cannot read image %s" % path)
		return null
	return ImageTexture.create_from_image(img)


## A pack model, as a PackedScene ready to instantiate: imported .glb/.tscn
## from res://, or a runtime GLTF parse of a file a player dropped in. Material
## resource_names survive the runtime path, which is what lets the engine's
## dressing contract (pawnhelm_iron / pawnhelm_accent / Crest_*) work on a
## model the game has never seen.
static func load_scene(path: String) -> PackedScene:
	if path.is_empty():
		return null
	if path.begins_with("res://") and ResourceLoader.exists(path):
		return ResourceLoader.load(path) as PackedScene
	# A res:// model the editor has not imported yet falls through to the
	# runtime parser below — that is a pack being DEVELOPED inside the game's
	# own folder, and it should work without a reimport.
	var ext := path.get_extension().to_lower()
	if ext != "glb" and ext != "gltf":
		push_warning("HousePack: %s is not a .glb/.gltf — a dropped-in model must be one" % path)
		return null
	if not FileAccess.file_exists(path):
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_warning("HousePack: %s is not a readable glTF file" % path)
		return null
	var scene := doc.generate_scene(state)
	if scene == null:
		return null
	# pack() only keeps nodes it OWNS, and generate_scene hands back a tree
	# whose children have no owner set — without this the PackedScene is an
	# empty root and the haus silently rides bare-headed.
	_own_all(scene, scene)
	var packed := PackedScene.new()
	if packed.pack(scene) != OK:
		scene.queue_free()
		return null
	scene.queue_free()
	return packed


static func _own_all(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_own_all(child, owner)


# ── the coat table ─────────────────────────────────────────────────────────


static var _coats: Dictionary = {}
static var _coat_default := "bay"


static func _ensure_coats() -> void:
	if not _coats.is_empty():
		return
	var f := FileAccess.open(COATS_PATH, FileAccess.READ)
	if f == null:
		push_error("HousePack: cannot open %s" % COATS_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed == null or not parsed is Dictionary or not (parsed as Dictionary).has("coats"):
		push_error("HousePack: %s is not a valid coats file" % COATS_PATH)
		return
	_coats = (parsed as Dictionary)["coats"]
	_coat_default = str((parsed as Dictionary).get("default", "bay"))


## The natural coats, {name -> {material -> "#rrggbb"}}. THE allowed list.
static func natural_coats() -> Dictionary:
	_ensure_coats()
	return _coats


static func coat_names() -> Array:
	_ensure_coats()
	return _coats.keys()


static func coat_default() -> String:
	_ensure_coats()
	return _coat_default


# ── helpers ────────────────────────────────────────────────────────────────


static func _empty_report(dir_path: String, source: String) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	return {"ok": false, "id": "", "dir": dir_path, "source": source,
		"house": {}, "errors": errors, "warnings": warnings}


static func _is_valid_id(id: String) -> bool:
	for i in id.length():
		var ch := id[i]
		if not ((ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_"):
			return false
	return true


static func _rgb_gap(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()
