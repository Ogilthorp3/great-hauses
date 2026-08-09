class_name HouseRegistry
extends RefCounted
## The roster of Great Hauses — discovered from HAUS PACKS, not hardcoded.
##
## A haus is a FOLDER holding a haus.json manifest (see HousePack and
## docs/HAUS-PACK.md). This registry finds them in two places:
##
##   res://hauses/    the nine that ship with the game, in index.json order
##                    (that order IS the tournament seed order)
##   user://hauses/   anything a player dropped in, alphabetically — a DLC
##                    haus needs no rebuild, no recompile and no patch
##
## Static registry — no autoload needed; any script can call
## `HouseRegistry.get_house("winterfang")`. Data is loaded once and cached in a
## static Dictionary (PLAIN DATA ONLY, no Resources: script statics holding
## Resources crash Godot during engine shutdown — the scar documented in
## piece_assets.gd. Sigils and models are therefore returned as PATHS, and the
## PieceAssets autoload owns the loaded-resource caches).
##
## EVERY MANIFEST IS VALIDATED ON LOAD and one bad pack never takes down the
## others: a pack with errors is skipped, its reasons printed once, and the
## rest of the roster loads. `load_report()` hands the whole record back for
## tests, the validator tool and anything that wants to show a modder what
## happened.
##
## Piece colouring: `get_house_tint(house, "kit")` is the haus's JERSEY — the
## one saturated colour its kit is painted in (PieceAssets.kit_material);
## `get_house_tint(house, "piece"/"tower")` is the faint whisper natural
## surfaces take (PieceAssets.natural_material); `get_house_coat(house)` names
## the horse's natural coat. Which surface gets which is decided by
## PieceAssets.MATERIAL_ROLES, never here.

## Where the shipped hauses live, and where a dropped-in one goes.
const BUILTIN_DIR := "res://hauses"
const USER_DIR := "user://hauses"
## Names the shipped packs load in — the tournament seed order. Directories not
## listed here are still discovered (a haus you are working on), appended in
## alphabetical order after the ones that are.
const INDEX_PATH := "res://hauses/index.json"

static var _by_id: Dictionary = {}     # id -> house Dictionary
static var _order: Array[String] = []  # ids in load order (= seed order)
static var _builtin: Array[String] = []
static var _installed: Array[String] = []
static var _reports: Array = []        # every pack's load report, good or bad
static var _loaded := false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for dir_path in _pack_dirs(BUILTIN_DIR, _index_order()):
		_ingest(HousePack.load_from_dir(dir_path, "builtin"))
	for dir_path in _pack_dirs(USER_DIR, []):
		_ingest(HousePack.load_from_dir(dir_path, "installed"))
	if _by_id.is_empty():
		push_error(("HouseRegistry: no haus packs found. The nine ship in %s; "
				+ "a haus you add goes in %s/<id>/haus.json")
				% [BUILTIN_DIR, USER_DIR])


## Fold one pack report into the roster, or refuse it out loud.
static func _ingest(rep: Dictionary) -> void:
	_reports.append(rep)
	var id := str(rep["id"])
	var where := str(rep["dir"])
	if not rep["ok"]:
		# A refused pack is a paragraph a modder can act on, printed ONCE, and
		# it costs the rest of the roster nothing.
		push_warning("haus pack refused: %s" % where)
		print("HAUS PACK REFUSED  %s" % where)
		for e in rep["errors"]:
			print("    error: %s" % str(e))
		return
	if _by_id.has(id):
		var clash := str(_by_id[id].get("pack_dir", "?"))
		rep["ok"] = false
		(rep["errors"] as Array).append(("haus id '%s' is already provided by %s "
				+ "— two packs cannot claim the same id; rename one") % [id, clash])
		print("HAUS PACK REFUSED  %s\n    error: %s" % [where, rep["errors"][-1]])
		return
	for w in rep["warnings"]:
		print("haus pack %-14s warning: %s" % [id, str(w)])
	_by_id[id] = rep["house"]
	_order.append(id)
	if str(rep["source"]) == "builtin":
		_builtin.append(id)
	else:
		_installed.append(id)
		print("HAUS PACK LOADED   %s (%s) from %s"
				% [str(rep["house"]["name"]), id, where])


## Pack directories under `root`, `first` (index order) leading, then whatever
## else is there alphabetically. Directories whose name starts with "_" are
## ignored on purpose: that is where the TEMPLATE and the examples live.
static func _pack_dirs(root: String, first: Array) -> Array[String]:
	var out: Array[String] = []
	var seen := {}
	for name in first:
		var p := root.path_join(str(name))
		if FileAccess.file_exists(p.path_join(HousePack.MANIFEST_NAME)):
			out.append(p)
			seen[str(name)] = true
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	var extra: Array[String] = []
	for name in dir.get_directories():
		if name.begins_with("_") or name.begins_with(".") or seen.has(name):
			continue
		if FileAccess.file_exists(root.path_join(name).path_join(HousePack.MANIFEST_NAME)):
			extra.append(root.path_join(name))
	extra.sort()
	out.append_array(extra)
	return out


static func _index_order() -> Array:
	var f := FileAccess.open(INDEX_PATH, FileAccess.READ)
	if f == null:
		return []
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary and (parsed as Dictionary).get("order") is Array:
		return (parsed as Dictionary)["order"]
	return []


## Force a re-scan of both pack directories (tests / a pack installed while the
## game is running).
static func reload() -> void:
	_by_id.clear()
	_order.clear()
	_builtin.clear()
	_installed.clear()
	_reports.clear()
	_loaded = false
	_ensure_loaded()


## All haus ids in load order — this order is the tournament seed order.
static func house_ids() -> Array[String]:
	_ensure_loaded()
	return _order.duplicate()


## Just the hauses that ship with the game.
static func builtin_house_ids() -> Array[String]:
	_ensure_loaded()
	return _builtin.duplicate()


## Just the hauses a player dropped into user://hauses/.
static func installed_house_ids() -> Array[String]:
	_ensure_loaded()
	return _installed.duplicate()


## Every pack's load report — {ok, id, dir, source, house, errors, warnings}.
## Refused packs are in here too; that is the point.
static func load_report() -> Array:
	_ensure_loaded()
	return _reports.duplicate()


## Full data Dictionary for a haus id ({} if unknown).
static func get_house(id: String) -> Dictionary:
	_ensure_loaded()
	return _by_id.get(id, {})


static func has_house(id: String) -> bool:
	_ensure_loaded()
	return _by_id.has(id)


## Heraldic colors as Colors: {"primary": Color, "secondary": Color, "accent": Color}.
static func get_colors(house) -> Dictionary:
	var h := _resolve(house)
	if h.is_empty():
		return {"primary": Color.WHITE, "secondary": Color.WHITE, "accent": Color.WHITE}
	var c: Dictionary = h["colors"]
	return {
		"primary": Color.html(c["primary"]),
		"secondary": Color.html(c["secondary"]),
		"accent": Color.html(c["accent"]),
	}


## A haus tint by role.
##   "kit"          THE JERSEY — the one saturated colour the haus paints its
##                  KIT in (tabard, cloak, hood, shield face, caparison, helm,
##                  crest). Loud on purpose: since the material-ROLE pass it is
##                  no longer painted on steel, skin, leather, bone or horse.
##   "tower"/"rook" the whisper the rook's masonry takes.
##   "piece"        (default) the whisper every other natural surface takes.
## A pack that declares no kit tint falls back to its piece tint, so an
## incomplete manifest degrades to the old look rather than to white.
static func get_house_tint(house, side_role: String = "piece") -> Color:
	var h := _resolve(house)
	if h.is_empty():
		return Color.WHITE
	var role := side_role.to_lower()
	var key := "piece"
	if role.contains("tower") or role.contains("rook"):
		key = "tower"
	elif role.contains("kit"):
		key = "kit"
	var tints: Dictionary = h["tints"]
	if not tints.has(key):
		key = "piece"
	return Color.html(tints[key])


## The haus's horse COAT name — bay, chestnut, black, white_grey, dun and
## their variants (src/houses/coats.json). Never a haus hue: a mount's haus
## identity is worn on the caparison, not grown on the animal.
static func get_house_coat(house) -> String:
	var h := _resolve(house)
	return str(h.get("coat", HousePack.coat_default()))


## The coat palette a haus's mount wears, as {material name -> Color}. A pack
## may name one of the natural coats or supply its own (validated against the
## same law either way — see HousePack.is_natural_color).
static func get_coat_palette(house) -> Dictionary:
	var h := _resolve(house)
	var custom: Dictionary = h.get("coat_palette", {})
	var raw: Dictionary = custom if not custom.is_empty() \
			else HousePack.natural_coats().get(get_house_coat(h), {})
	if raw.is_empty():
		return {}
	var out := {}
	for key in raw:
		out[key] = Color.html(str(raw[key]))
	return out


## Legacy saturation argument (the pre-role multiply pipeline). Kept because
## manifests still carry the field; nothing in the costume path reads it.
static func get_tint_saturation(house) -> float:
	var h := _resolve(house)
	if h.is_empty():
		return HousePack.DEFAULT_TINT_SATURATION
	return float(h["tints"].get("saturation", HousePack.DEFAULT_TINT_SATURATION))


## Path of the haus's sigil image ("" when the pack ships none).
static func sigil_path(house) -> String:
	var h := _resolve(house)
	return str(h.get("sigil", ""))


## Path of the haus's helm-crest model, worn by knight/queen/king ("" = none).
static func crest_path(house) -> String:
	var h := _resolve(house)
	return str(h.get("crest", ""))


## Path of the haus's PAWN half-helm model ("" = none).
static func pawn_helm_path(house) -> String:
	var h := _resolve(house)
	return str(h.get("pawn_helm", ""))


## Army model overrides, {piece type int -> path}. {} = the shipped cast.
static func army_overrides(house) -> Dictionary:
	var h := _resolve(house)
	return h.get("army", {})


## The pack's own MATERIAL ROLE declarations, {surface name -> {role, stuff}}
## as validated strings. PieceAssets folds these into its classification table.
static func material_roles(house) -> Dictionary:
	var h := _resolve(house)
	return h.get("materials", {})


## Every installed pack's role declarations, merged. Surface names are prefixed
## with the haus id by construction, so this merge cannot collide.
static func all_material_roles() -> Dictionary:
	_ensure_loaded()
	var out := {}
	for id in _order:
		for surface in (_by_id[id].get("materials", {}) as Dictionary):
			out[surface] = (_by_id[id]["materials"] as Dictionary)[surface]
	return out


## The taunt pool a pack ships with, {beat -> [lines]} ({} = none; the haus
## then uses whatever src/banter/banter_lines.json holds for it).
static func banter_pool(house) -> Dictionary:
	var h := _resolve(house)
	return h.get("banter", {})


## Every pack-supplied taunt pool, {haus id -> {beat -> [lines]}}.
static func all_banter_pools() -> Dictionary:
	_ensure_loaded()
	var out := {}
	for id in _order:
		var pool: Dictionary = _by_id[id].get("banter", {})
		if not pool.is_empty():
			out[id] = pool
	return out


## Path of the haus's own music ("" = the shipped playlist).
static func music_path(house) -> String:
	var h := _resolve(house)
	return str(h.get("music", ""))


## The sigil as a Texture2D; falls back to a flat primary-color texture if the
## pack ships none (or its file cannot be read). Dropped-in PNGs are decoded at
## runtime — they never went through the editor's import pipeline.
static func load_sigil(house) -> Texture2D:
	var tex := HousePack.load_texture(sigil_path(house))
	if tex != null:
		return tex
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(get_colors(house)["primary"])
	return ImageTexture.create_from_image(img)


## Accept either a haus id String or an already-fetched haus Dictionary.
static func _resolve(house) -> Dictionary:
	if house is Dictionary:
		return house
	return get_house(str(house))
