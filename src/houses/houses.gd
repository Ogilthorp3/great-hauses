class_name HouseRegistry
extends RefCounted
## Loader for the Nine Great Houses (src/houses/houses.json).
##
## Static registry — no autoload needed; any script can call
## `HouseRegistry.get_house("winterfang")`. Data is loaded once from JSON and
## cached in a static Dictionary (plain data only, no Resources, so the
## static-var-holding-Resources shutdown crash documented in piece_assets.gd
## does not apply here).
##
## Piece tinting: `get_house_tint(house, side_role)` returns a Color meant to
## be fed straight into `PieceAssets.tinted_material(src, tint, saturation)`
## (same multiply-tint pipeline PieceView uses for its FROST/EMBER tints);
## `get_tint_saturation(house)` supplies the matching saturation argument.

const DATA_PATH := "res://src/houses/houses.json"

static var _by_id: Dictionary = {}     # id -> house Dictionary
static var _order: Array[String] = []  # ids in file order (= seed order)


static func _ensure_loaded() -> void:
	if not _by_id.is_empty():
		return
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("HouseRegistry: cannot open %s" % DATA_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed == null or not parsed is Dictionary or not parsed.has("houses"):
		push_error("HouseRegistry: %s is not a valid houses file" % DATA_PATH)
		return
	for h: Dictionary in parsed["houses"]:
		var id := str(h.get("id", ""))
		if id.is_empty():
			push_error("HouseRegistry: house entry without id skipped")
			continue
		_by_id[id] = h
		_order.append(id)


## Force a re-read of houses.json (tests / hot-reload).
static func reload() -> void:
	_by_id.clear()
	_order.clear()
	_ensure_loaded()


## All house ids in file order — this order is the tournament seed order.
static func house_ids() -> Array[String]:
	_ensure_loaded()
	return _order.duplicate()


## Full data Dictionary for a house id ({} if unknown).
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


## The multiply-tint Color for a house's pieces, per side role.
## `side_role` accepts "piece"/"character" (default) or anything containing
## "tower"/"rook" for the static tower rook. Compatible with
## PieceAssets.tinted_material(src, tint, saturation).
static func get_house_tint(house, side_role: String = "piece") -> Color:
	var h := _resolve(house)
	if h.is_empty():
		return Color.WHITE
	var role := side_role.to_lower()
	var key := "tower" if (role.contains("tower") or role.contains("rook")) else "piece"
	return Color.html(h["tints"][key])


## Saturation argument matching get_house_tint for PieceAssets.tinted_material.
static func get_tint_saturation(house) -> float:
	var h := _resolve(house)
	if h.is_empty():
		return 0.25
	return float(h["tints"].get("saturation", 0.25))


## res:// path of the house's generated sigil PNG.
static func sigil_path(house) -> String:
	var h := _resolve(house)
	return str(h.get("sigil", ""))


## The sigil as a Texture2D; falls back to a flat primary-color texture if the
## generated PNG is missing (e.g. before tools/gen_sigils.gd has run).
static func load_sigil(house) -> Texture2D:
	var path := sigil_path(house)
	if not path.is_empty() and ResourceLoader.exists(path):
		return load(path)
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(get_colors(house)["primary"])
	return ImageTexture.create_from_image(img)


## Accept either a house id String or an already-fetched house Dictionary.
static func _resolve(house) -> Dictionary:
	if house is Dictionary:
		return house
	return get_house(str(house))
