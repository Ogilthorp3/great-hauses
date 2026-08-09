extends SceneTree
## tools/validate_house_pack.gd — check a haus pack before the game does.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       -s res://tools/validate_house_pack.gd -- <dir> [<dir> ...]
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       -s res://tools/validate_house_pack.gd -- --all
##
## <dir> is a haus-pack folder — the one holding haus.json. It may be
## anywhere: res://hauses/ravenmark, user://hauses/ravenmark, or a plain
## ~/my-hauses/ravenmark you have not installed yet. `--all` checks every pack
## the game would actually load, shipped and installed.
##
## Exit code 0 = every pack checked is loadable, 1 = at least one is refused.
## Warnings never fail the run: they are the things that will silently become a
## default, and you should read them.
##
## WHAT IT CHECKS, in the order a problem costs you time:
##
##   1. THE MANIFEST (HousePack.parse) — id, colours, the natural-coat rule,
##      the material-role declarations, army overrides, paths that lead
##      nowhere. Everything the game checks at load, checked here with the same
##      code, so this tool cannot drift from the loader.
##   2. THE MODELS. Every surface of every .glb the pack ships is classified
##      with the engine's own table (PieceAssets.classify). A surface the table
##      cannot name is UNCLASSIFIED: the game refuses to paint it, the role
##      gate goes red, and it renders in whatever colour your modelling tool
##      left it. Better to hear it here.
##   3. THE JERSEY. What your kit colour will look like next to every other
##      haus already installed — because two hauses that wear the same colour
##      are one haus, twice.
##
## It runs with NO autoloads (that is what `-s` means), so it shims the
## PieceAssets node the same way tests/test_costumes.gd does.

const OK_MARK := "  ok "
const WARN_MARK := "  !! "
const FAIL_MARK := "  XX "

var assets: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var dirs: Array[String] = []
	var want_all := false
	for a in args:
		if str(a) == "--all":
			want_all = true
		elif str(a).begins_with("--"):
			print("unknown option %s" % str(a))
		else:
			dirs.append(str(a))
	assets = (load("res://src/board/piece_assets.gd") as GDScript).new()
	assets.name = "PieceAssets"
	root.add_child(assets)

	if want_all:
		for rep: Dictionary in HouseRegistry.load_report():
			dirs.append(str(rep["dir"]))
	if dirs.is_empty():
		print("usage: Godot --headless -s res://tools/validate_house_pack.gd -- <pack dir> [...]")
		print("       ...or --all to check every pack this game would load")
		print("a pack dir is the folder holding haus.json — see docs/HAUS-PACK.md")
		quit(1)
		return

	var bad := 0
	for d in dirs:
		if not _validate(d):
			bad += 1
	print("")
	if bad == 0:
		print("VALIDATE PASS — %d pack(s) would load" % dirs.size())
	else:
		print("VALIDATE FAIL — %d of %d pack(s) would be REFUSED" % [bad, dirs.size()])
	quit(0 if bad == 0 else 1)


func _validate(dir_path: String) -> bool:
	var normalized := dir_path.rstrip("/")
	print("")
	print("── %s" % normalized)
	var rep: Dictionary = HousePack.load_from_dir(normalized, "installed")
	var house: Dictionary = rep["house"]
	if not str(rep["id"]).is_empty():
		print("   haus '%s' — %s of %s" % [str(rep["id"]),
				str(house.get("name", "?")), str(house.get("seat", "?"))])

	for e in rep["errors"]:
		print("%s%s" % [FAIL_MARK, _wrap(str(e))])
	for w in rep["warnings"]:
		print("%s%s" % [WARN_MARK, _wrap(str(w))])

	if not rep["ok"]:
		print("   REFUSED — the game would skip this pack and load the others")
		return false

	# -- what the manifest actually declares, in one readable block ---------
	print("%scoat '%s' — %s" % [OK_MARK, str(house["coat"]),
			"the pack's own palette" if not (house["coat_palette"] as Dictionary).is_empty()
			else "a natural coat"])
	print("%sjersey %s%s" % [OK_MARK, str(house["tints"]["kit"]),
			"" if not str(house["sigil"]).is_empty() else "  (no sigil — a flat shield will stand in)"])
	var mats: Dictionary = house["materials"]
	if mats.is_empty():
		print("%sno material declarations — everything this pack ships must be" % OK_MARK)
		print("       named by the engine's dressing contract (%s)"
				% ", ".join(HousePack.CONTRACT_MATERIALS))
	else:
		for surface in mats:
			print("%s%-34s %s" % [OK_MARK, surface,
					_role_line(mats[surface])])

	# -- the models ---------------------------------------------------------
	# Judge the pack by ITS OWN declarations even though it is not installed —
	# otherwise a surface it correctly declares reads as one the engine had to
	# guess at, which is the opposite of the answer.
	assets.declare_pack_rules(mats)
	var model_errors := 0
	for key in ["crest", "pawn_helm"]:
		model_errors += _scan_model(str(house[key]), key, false)
	for piece_type in (house["army"] as Dictionary):
		model_errors += _scan_model(str((house["army"] as Dictionary)[piece_type]),
				"army[%d]" % int(piece_type), true)

	# -- the neighbours -----------------------------------------------------
	_compare_jerseys(rep)

	if model_errors > 0:
		print("   REFUSED — %d surface(s) the engine cannot name" % model_errors)
		return false
	print("   PASS — this pack would load%s" % ("" if rep["warnings"].is_empty()
			else " (with %d manifest warning(s) above)" % rep["warnings"].size()))
	return true


## Classify every surface of one model exactly as the game will.
## `expect_natural` is true for army models: a soldier made entirely of haus
## colour is the monochrome army the role system exists to end.
func _scan_model(path: String, label: String, expect_natural: bool) -> int:
	if path.is_empty():
		return 0
	var packed: PackedScene = HousePack.load_scene(path)
	if packed == null:
		print("%s%s: %s could not be read as a model (.glb/.gltf, or an imported"
				% [WARN_MARK, label, path] + " res:// scene)")
		return 0
	var inst := packed.instantiate()
	var counts := {}
	var unnamed: Array[String] = []
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as StandardMaterial3D
			var mat_name := "" if mat == null else str(mat.resource_name)
			var cls: Dictionary = assets.classify(str(mi.name), mat_name, true)
			var role := int(cls["role"])
			counts[role] = int(counts.get(role, 0)) + 1
			if role == assets.Role.UNCLASSIFIED:
				unnamed.append("%s / material '%s'" % [str(mi.name), mat_name])
	inst.free()
	print("%s%s: %s" % [OK_MARK if unnamed.is_empty() else FAIL_MARK, label,
			_role_census(counts)])
	for u in unnamed:
		print("%s   surface %s is UNCLASSIFIED — the engine will leave it" % [FAIL_MARK, u])
		print("         undressed and the role gate will fail on it. Either name it")
		print("         with the engine's contract (%s), or declare it in"
				% ", ".join(HousePack.CONTRACT_MATERIALS))
		print("         \"materials\" as \"<your id>_<name>\": \"kit\" / \"natural:steel\" / …")
	if expect_natural and int(counts.get(assets.Role.NATURAL, 0)) == 0 \
			and int(counts.get(assets.Role.KIT, 0)) > 0:
		print("%s%s: every surface is KIT — nothing on this model is steel," % [WARN_MARK, label])
		print("         leather, skin or bone, so the whole figure will be painted")
		print("         in your haus colour. That is the monochrome army the role")
		print("         system exists to end; give the soldier some materials.")
	return unnamed.size()


func _role_census(counts: Dictionary) -> String:
	if counts.is_empty():
		return "no rendered surfaces"
	var names := {assets.Role.KIT: "kit", assets.Role.NATURAL: "natural",
		assets.Role.REGALIA: "regalia", assets.Role.HERALDRY: "heraldry",
		assets.Role.MIXED: "mixed", assets.Role.EFFECT: "effect",
		assets.Role.UNCLASSIFIED: "UNCLASSIFIED"}
	var bits: Array[String] = []
	for role in counts:
		bits.append("%d %s" % [int(counts[role]), str(names.get(role, "?"))])
	return ", ".join(bits)


func _role_line(spec: Dictionary) -> String:
	var role := str(spec["role"])
	if role == "natural":
		return "natural:%s — keeps its own colours" % str(spec["stuff"])
	if role == "kit":
		return "kit — wears the haus jersey"
	if role == "regalia":
		return "regalia — stays metal"
	if role == "heraldry":
		return "heraldry — carries its own artwork"
	return role


## Two hauses that wear the same colour are one haus, twice.
func _compare_jerseys(rep: Dictionary) -> void:
	var kit := Color.html(str((rep["house"] as Dictionary)["tints"]["kit"]))
	var id := str(rep["id"])
	for other in HouseRegistry.house_ids():
		if other == id:
			continue
		var theirs := HouseRegistry.get_house_tint(other, "kit")
		var gap := Vector3(kit.r - theirs.r, kit.g - theirs.g, kit.b - theirs.b).length()
		if gap < HousePack.KIT_DISTINCT:
			print("%sjersey %s is %.2f from Haus %s's %s (under %.2f) — on the board"
					% [WARN_MARK, kit.to_html(false), gap, other.capitalize(),
					theirs.to_html(false), HousePack.KIT_DISTINCT])
			print("         those two armies will look like the same haus")


## Long sentences, wrapped so a terminal can read them.
func _wrap(text: String, width := 74) -> String:
	var out := ""
	var line := ""
	for word in text.split(" "):
		if line.length() + str(word).length() + 1 > width:
			out += line + "\n       "
			line = str(word)
		else:
			line += (" " if not line.is_empty() else "") + str(word)
	return out + line
