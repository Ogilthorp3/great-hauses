extends SceneTree

# Headless suite for the HOUSE PACK format (src/houses/house_pack.gd) and the
# pack-discovering registry (src/houses/houses.gd).
# Run: /Applications/Godot.app/Contents/MacOS/Godot --headless --path <project> -s res://tests/test_house_packs.gd
# Exit code 0 = all green, 1 = failures.
#
# It answers three questions, in this order:
#
#   1. DID THE PORT CHANGE ANYTHING? The nine houses moved out of one
#      src/houses/houses.json and into nine houses/<id>/house.json packs. The
#      GOLDEN table below is the pre-port data, transcribed from that file's
#      last committed state, and every field of every house is compared against
#      it — plus the crest, half-helm and army-cast each house resolves to. A
#      refactor that changes a colour is not a refactor.
#
#   2. DOES THE FORMAT REFUSE WHAT IT MUST? A third-party pack must not be able
#      to undo the material-role discipline: no blue horses, no jersey painted
#      on steel, no monochrome army, no claiming a surface it does not own.
#      Each of those has a negative control here, because a validator that
#      fires on nothing is not a validator.
#
#   3. DOES IT DEGRADE INSTEAD OF CRASHING? A pack with no motto, no crest, no
#      colours, a broken JSON body or a file that is not there must produce a
#      warning a human can act on and a house that still plays.
#
# NOTE deliberately NO preload/const of PieceAssets: -s runs never instance
# autoloads, and any script naming that global fails to COMPILE until a node
# called "PieceAssets" hangs under /root (the scar recorded in test_costumes).

var failures := 0
var checks_run := 0

## A hard-erroring test aborts silently at the error and its caller resumes as
## if it finished — so "no FAIL lines" is not proof the suite ran.
const MIN_EXPECTED_CHECKS := 210

## PieceView.Type ints (mirrored — see test_costumes.gd).
const T_PAWN := 0
const T_KNIGHT := 2
const T_BISHOP := 3
const T_QUEEN := 4
const T_KING := 5

const CREST_DIR := "res://assets/custom-props/crests"
const HELM_DIR := "res://assets/custom-props/pawn-helms"
const ADVENTURERS := "res://assets/kaykit-adventurers"
const SKELETONS := "res://assets/kaykit-skeletons"

## THE PRE-PORT DATA — src/houses/houses.json as it stood at commit a27279b,
## field for field. This is the whole proof of "no behaviour change": the port
## moved bytes between files, and these are the bytes.
const GOLDEN := [
	{"id": "winterfang", "archetype": "wolf", "name": "Haus Winterfang",
		"seat": "Frosthollow", "motto": "The wolf remembers.",
		"primary": "#8d99a6", "secondary": "#eef2f5", "accent": "#7fb0d4",
		"piece": "#9fb4cc", "tower": "#8ca1b8", "kit": "#6f9fc9",
		"coat": "white_grey"},
	{"id": "goldclaw", "archetype": "lion", "name": "Haus Goldclaw",
		"seat": "Gildenspire", "motto": "A lion settles every account.",
		"primary": "#8e1f2c", "secondary": "#d9a441", "accent": "#f0c96a",
		"piece": "#d4a43c", "tower": "#b8862f", "kit": "#f0cc2a",
		"coat": "chestnut"},
	{"id": "hartcrown", "archetype": "stag", "name": "Haus Hartcrown",
		"seat": "Stormrest", "motto": "The storm answers to us.",
		"primary": "#1d1a17", "secondary": "#cfa63b", "accent": "#e8c866",
		"piece": "#8f5218", "tower": "#784514", "kit": "#7a3410",
		"coat": "dapple_grey"},
	{"id": "ashwyrm", "archetype": "dragon", "name": "Haus Ashwyrm",
		"seat": "Cinderhold", "motto": "From ash, dominion.",
		"primary": "#171214", "secondary": "#b3282d", "accent": "#e04b3a",
		"piece": "#b03a2e", "tower": "#93302a", "kit": "#c2261e",
		"coat": "black"},
	{"id": "tidegrip", "archetype": "kraken", "name": "Haus Tidegrip",
		"seat": "Brinehold", "motto": "The tide takes what it pleases.",
		"primary": "#4c6357", "secondary": "#14181a", "accent": "#7d9c8d",
		"piece": "#6f8a7d", "tower": "#5d7568", "kit": "#3f8a6d",
		"coat": "drowned_grey"},
	{"id": "thornvale", "archetype": "rose", "name": "Haus Thornvale",
		"seat": "Bloomhall", "motto": "Every rose keeps its thorns.",
		"primary": "#2f5d3a", "secondary": "#d3b04a", "accent": "#8fbf6a",
		"piece": "#79a04a", "tower": "#648540", "kit": "#4f9235",
		"coat": "dun"},
	{"id": "duskfire", "archetype": "sun", "name": "Haus Duskfire",
		"seat": "Sunspire", "motto": "The sun kneels for no one.",
		"primary": "#c96a1e", "secondary": "#a3282a", "accent": "#f0a03c",
		"piece": "#e07b2f", "tower": "#c2691f", "kit": "#e85f14",
		"coat": "liver_chestnut"},
	{"id": "swiftcrest", "archetype": "falcon", "name": "Haus Swiftcrest",
		"seat": "Skyloft", "motto": "Honor rides the high wind.",
		"primary": "#7fb3d9", "secondary": "#f2f6f9", "accent": "#4f86ad",
		"piece": "#6fc2c9", "tower": "#5aa3ab", "kit": "#37b0c8",
		"coat": "bay"},
	{"id": "silverbrook", "archetype": "trout", "name": "Haus Silverbrook",
		"seat": "Rivergate", "motto": "The river binds us all.",
		"primary": "#2c4d7c", "secondary": "#c9d3dc", "accent": "#8fb3d9",
		"piece": "#6e8fc4", "tower": "#5d7aa9", "kit": "#3560ad",
		"coat": "dark_bay"},
]

## A minimal manifest that passes, used as the base for the negative controls
## so each one differs from a KNOWN-GOOD pack by exactly one field.
const SANE := {
	"id": "probehouse",
	"name": "Haus Probe",
	"archetype": "wolf",
	"seat": "Probehold",
	"motto": "We test what we ship.",
	"colors": {"primary": "#3b2a6b", "secondary": "#d8cfe6", "accent": "#a06fd6"},
	"tints": {"piece": "#6f5aa8", "tower": "#5a4890", "kit": "#7b3fb5"},
	"coat": "black",
}

var assets: Node          # the PieceAssets shim
var tmp_dir := "user://test_house_packs"


func _initialize() -> void:
	_main()


func _main() -> void:
	print("=== Great Hauses — house-pack headless suite ===")
	assets = (load("res://src/board/piece_assets.gd") as GDScript).new()
	assets.name = "PieceAssets"
	root.add_child(assets)
	_test_port_is_lossless()
	_test_pack_assets_resolve()
	_test_role_vocabulary_matches_the_engine()
	_test_shipped_packs_are_clean()
	_test_refuses_unnatural_coats()
	_test_refuses_kit_on_natural_stuff()
	_test_refuses_surfaces_it_does_not_own()
	_test_refuses_a_monochrome_army()
	_test_degrades_without_crashing()
	_test_one_bad_pack_does_not_take_the_others()
	_test_runtime_assets_load_from_outside_res()
	print("---")
	check("final: no test silently aborted (checks >= %d)" % MIN_EXPECTED_CHECKS,
			true, checks_run >= MIN_EXPECTED_CHECKS)
	if failures == 0:
		print("HAUS PACKS OK — all %d checks passed" % checks_run)
	else:
		print("HAUS PACKS FAILED — %d of %d checks failed" % [failures, checks_run])
	quit(0 if failures == 0 else 1)


func check(test_name: String, expected, actual) -> void:
	checks_run += 1
	var ok := str(expected) == str(actual)
	if not ok:
		failures += 1
		print("FAIL  %-62s expected %s, got %s" % [test_name, expected, actual])


## An error list must not merely be non-empty — it must SAY the thing a modder
## needs to read. Every negative control asserts both.
func check_error(test_name: String, rep: Dictionary, needle: String) -> void:
	var joined := "\n".join(rep["errors"])
	check("%s: refused" % test_name, false, rep["ok"])
	check("%s: says '%s'" % [test_name, needle], true, joined.containsn(needle))
	if not joined.containsn(needle):
		print("      errors were: %s" % joined)


# ── 1. the port ────────────────────────────────────────────────────────────


## Every field of every house, against the pre-port file.
func _test_port_is_lossless() -> void:
	var ids := HouseRegistry.house_ids()
	var want_ids: Array = []
	for g: Dictionary in GOLDEN:
		want_ids.append(g["id"])
	# The SHIPPED nine lead the roster, in index.json order. Compare the leading
	# slice, not the whole array: a haus a player dropped into user://hauses/ is
	# appended after them and must not turn this suite red — that a tenth can be
	# installed without breaking the nine IS the format's promise.
	check("port: the nine load, in seed order", str(want_ids),
			str(ids.slice(0, want_ids.size())))
	check("port: all nine are builtin", str(want_ids),
			str(HouseRegistry.builtin_house_ids()))
	for g: Dictionary in GOLDEN:
		var hid: String = g["id"]
		var h := HouseRegistry.get_house(hid)
		check("port %s: found" % hid, false, h.is_empty())
		if h.is_empty():
			continue
		check("port %s: name" % hid, g["name"], str(h["name"]))
		check("port %s: seat" % hid, g["seat"], str(h["seat"]))
		check("port %s: motto" % hid, g["motto"], str(h["motto"]))
		check("port %s: archetype" % hid, g["archetype"], str(h["archetype"]))
		var cols := HouseRegistry.get_colors(hid)
		check("port %s: primary" % hid, g["primary"],
				"#" + (cols["primary"] as Color).to_html(false))
		check("port %s: secondary" % hid, g["secondary"],
				"#" + (cols["secondary"] as Color).to_html(false))
		check("port %s: accent" % hid, g["accent"],
				"#" + (cols["accent"] as Color).to_html(false))
		check("port %s: kit tint" % hid, g["kit"],
				"#" + HouseRegistry.get_house_tint(hid, "kit").to_html(false))
		check("port %s: piece tint" % hid, g["piece"],
				"#" + HouseRegistry.get_house_tint(hid, "piece").to_html(false))
		check("port %s: tower tint" % hid, g["tower"],
				"#" + HouseRegistry.get_house_tint(hid, "tower").to_html(false))
		check("port %s: legacy saturation" % hid, 0.25,
				HouseRegistry.get_tint_saturation(hid))
		check("port %s: coat" % hid, g["coat"], HouseRegistry.get_house_coat(hid))
		check("port %s: sigil path" % hid, "res://assets/sigils/%s.png" % hid,
				HouseRegistry.sigil_path(hid))
		# ...and the coat still resolves to the same six colours it always did.
		var coat: Dictionary = assets.coat_palette(hid)
		for part in ["Main", "Main_Light", "Main_Dark", "Muzzle", "Hair", "Hooves"]:
			check("port %s: coat names %s" % [hid, part], true, coat.has(part))


## The crest, half-helm and army cast a house resolves to — the three things
## that used to be const preloads keyed by house id in piece_assets.gd.
func _test_pack_assets_resolve() -> void:
	for g: Dictionary in GOLDEN:
		var hid: String = g["id"]
		check("assets %s: crest path" % hid,
				"%s/crest_%s.glb" % [CREST_DIR, hid], HouseRegistry.crest_path(hid))
		var want_helm := "%s/pawn_helm_%s.glb" % [HELM_DIR, hid]
		if hid == "tidegrip":
			# The Drowned Legion's pre-charred twin — a shipped ASSET SWAP that
			# used to be a branch in pawn_helm_scene(); it is a manifest line now.
			want_helm = "%s/pawn_helm_tidegrip_charred.glb" % HELM_DIR
		check("assets %s: pawn helm path" % hid, want_helm,
				HouseRegistry.pawn_helm_path(hid))
		check("assets %s: crest loads" % hid, true,
				assets.crest_scene(hid) != null)
		check("assets %s: helm loads" % hid, true,
				assets.pawn_helm_scene(hid) != null)
	# The cast: skeletons for Tidegrip, adventurers for everyone else.
	var cast_want := {
		T_PAWN: "Barbarian", T_KNIGHT: "Knight", T_BISHOP: "Mage",
		T_QUEEN: "Rogue_Hooded", T_KING: "Ranger"}
	var drowned_want := {
		T_PAWN: "Skeleton_Minion", T_KNIGHT: "Skeleton_Warrior",
		T_BISHOP: "Skeleton_Mage", T_QUEEN: "Skeleton_Rogue",
		T_KING: "Skeleton_Warrior"}
	for g: Dictionary in GOLDEN:
		var hid: String = g["id"]
		var want: Dictionary = drowned_want if hid == "tidegrip" else cast_want
		var dir := SKELETONS if hid == "tidegrip" else ADVENTURERS
		for t in want:
			var scene: PackedScene = assets.character_scene(t, hid)
			check("cast %s/%d: %s" % [hid, t, want[t]],
					"%s/%s.glb" % [dir, want[t]], scene.resource_path)
	check("cast: an unknown house still fields the shipped cast", true,
			assets.character_scene(T_PAWN, "no_such_house") != null)


## The manifest is written in WORDS ("natural:steel"); the engine dispatches on
## an ENUM. Two vocabularies, one meaning — and nothing tells you when they
## drift except this.
func _test_role_vocabulary_matches_the_engine() -> void:
	var words: Dictionary = assets.ROLE_WORDS
	check("vocabulary: roles match", str(HousePack.ROLES.size()), str(words.size()))
	for role in HousePack.ROLES:
		check("vocabulary: role '%s' is a real Role" % role, true, words.has(role))
	check("vocabulary: 'mixed' is NOT offered to packs", false,
			HousePack.ROLES.has("mixed"))
	var stuffs: Dictionary = assets.STUFF_WORDS
	check("vocabulary: stuffs match", str(HousePack.STUFFS.size()), str(stuffs.size()))
	for stuff in HousePack.STUFFS:
		check("vocabulary: stuff '%s' is a real Stuff" % stuff, true, stuffs.has(stuff))
	# The engine's own contract names must be classified by the ENGINE table —
	# a pack neither declares them nor needs to.
	for contract in ["pawnhelm_iron", "pawnhelm_accent"]:
		check("vocabulary: '%s' is KIT in the engine table" % contract,
				assets.Role.KIT, int(assets.classify(contract, contract)["role"]))
	# And the coat vocabulary the manifest quotes is the one the game paints.
	for coat_name in HousePack.coat_names():
		check("vocabulary: coat '%s' has six parts" % coat_name, 6,
				(HousePack.natural_coats()[coat_name] as Dictionary).size())


## A pack that SHIPS with the game must load without a single complaint. A
## warning in one of the nine means the format and the data disagree.
func _test_shipped_packs_are_clean() -> void:
	for rep: Dictionary in HouseRegistry.load_report():
		var id := str(rep["id"])
		check("shipped %s: no errors" % id, "[]", str(rep["errors"]))
		check("shipped %s: no warnings" % id, "[]", str(rep["warnings"]))


# ── 2. what the format refuses ─────────────────────────────────────────────


## THE HARD RULE. "Horse should be brown, black or white, something majestic."
## A pack cannot name a colour that is not a coat, and cannot mix its own.
func _test_refuses_unnatural_coats() -> void:
	var m := SANE.duplicate(true)
	m["coat"] = "electric_blue"
	var rep := HousePack.parse(m, "res://hauses/_probe")
	check_error("coat/unknown-name", rep, "is not a natural coat")
	check("coat/unknown-name: lists the allowed coats", true,
			"\n".join(rep["errors"]).contains("bay") \
			and "\n".join(rep["errors"]).contains("dapple_grey"))

	m = SANE.duplicate(true)
	m["coat_palette"] = {"Main": "#2e5cff", "Main_Light": "#5a80ff",
		"Main_Dark": "#1a3ba8", "Muzzle": "#16307f", "Hair": "#0f2255",
		"Hooves": "#2b2724"}
	check_error("coat/blue-horse", HousePack.parse(m, "res://hauses/_probe"),
			"not a coat a horse comes in")

	m = SANE.duplicate(true)
	m["coat_palette"] = {"Main": "#6b4526", "Main_Light": "#8a5c33"}
	check_error("coat/incomplete-palette", HousePack.parse(m, "res://hauses/_probe"),
			"missing \"Main_Dark\"")

	# A coat that IS the jersey — the role gate would refuse the render, so the
	# format refuses the manifest.
	m = SANE.duplicate(true)
	m["tints"] = {"kit": "#6b4526"}
	m["coat"] = "bay"
	check_error("coat/is-the-jersey", HousePack.parse(m, "res://hauses/_probe"),
			"is your own jersey colour")

	# ...and a legal one passes, so the check is not simply "always red".
	var ok := HousePack.parse(SANE.duplicate(true), "res://hauses/_probe")
	check("coat/black-under-a-violet-jersey: accepted", true, ok["ok"])
	check("coat/…: no errors", "[]", str(ok["errors"]))


## The single most important design point: a stranger's pack must not be able
## to paint the house colour onto steel, leather, bone or a horse.
func _test_refuses_kit_on_natural_stuff() -> void:
	for surface in ["probehouse_steel_pauldron", "probehouse_saddle_leather",
			"probehouse_skull_mask", "probehouse_horse_hide"]:
		var m := SANE.duplicate(true)
		m["materials"] = {surface: "kit"}
		check_error("kit-on-natural/%s" % surface,
				HousePack.parse(m, "res://hauses/_probe"), "is NATURAL")
	# The same surfaces are perfectly legal as naturals.
	var m2 := SANE.duplicate(true)
	m2["materials"] = {
		"probehouse_steel_pauldron": "natural:steel",
		"probehouse_saddle_leather": "natural:leather",
		"probehouse_plume": "kit",
		"probehouse_torch": "effect",
	}
	var rep := HousePack.parse(m2, "res://hauses/_probe")
	check("roles: an honest declaration is accepted", true, rep["ok"])
	check("roles: kept all four", 4, (rep["house"]["materials"] as Dictionary).size())
	check("roles: steel keeps its stuff", "steel",
			str(rep["house"]["materials"]["probehouse_steel_pauldron"]["stuff"]))
	# An unknown role names the ones that exist.
	var m3 := SANE.duplicate(true)
	m3["materials"] = {"probehouse_thing": "shiny"}
	check_error("roles/unknown", HousePack.parse(m3, "res://hauses/_probe"),
			"which is not a role")
	# natural WITHOUT a stuff is a half-answer.
	var m4 := SANE.duplicate(true)
	m4["materials"] = {"probehouse_thing": "natural:unobtainium"}
	check_error("roles/unknown-stuff", HousePack.parse(m4, "res://hauses/_probe"),
			"is not a material family")
	# MIXED belongs to the shipped atlas casts and is not on offer.
	var m5 := SANE.duplicate(true)
	m5["materials"] = {"probehouse_body": "mixed"}
	check_error("roles/mixed-is-reserved", HousePack.parse(m5, "res://hauses/_probe"),
			"reserved")


## The prefix rule is what makes a merged role table safe. Without it, a pack
## could declare "Main" (the horse's hide) or "*_Helmet" and re-role the whole
## game.
func _test_refuses_surfaces_it_does_not_own() -> void:
	for surface in ["Main", "Hair", "Knight_Body", "tower_stone", "someone_else_plume"]:
		var m := SANE.duplicate(true)
		m["materials"] = {surface: "kit"}
		check_error("ownership/%s" % surface,
				HousePack.parse(m, "res://hauses/_probe"), "must be named")
	# The engine's dressing contract is the pack's way IN, not something to
	# redeclare.
	var m2 := SANE.duplicate(true)
	m2["materials"] = {"pawnhelm_iron": "kit"}
	check_error("ownership/contract-name", HousePack.parse(m2, "res://hauses/_probe"),
			"engine")
	# An id whose prefix would swallow an engine name is refused outright.
	var m3 := SANE.duplicate(true)
	m3["id"] = "crest"
	check_error("ownership/reserved-id", HousePack.parse(m3, "res://hauses/_probe"),
			"reserved")
	var m4 := SANE.duplicate(true)
	m4["id"] = "Haus Probe!"
	check_error("ownership/illegal-id", HousePack.parse(m4, "res://hauses/_probe"),
			"not a legal id")


## An army supplied is an army described — and an army described as nothing but
## kit is the monochrome army the role system exists to end.
func _test_refuses_a_monochrome_army() -> void:
	var m := SANE.duplicate(true)
	m["army"] = {"pawn": "res://assets/kaykit-skeletons/Skeleton_Minion.glb"}
	m["materials"] = {"probehouse_tabard": "kit", "probehouse_plume": "kit"}
	check_error("army/all-kit", HousePack.parse(m, "res://hauses/_probe"),
			"painted\nentirely in the haus colour".replace("\n", " "))
	# One honest natural surface and the same pack is fine.
	m["materials"]["probehouse_mail"] = "natural:steel"
	var rep := HousePack.parse(m, "res://hauses/_probe")
	check("army/with-naturals: accepted", true, rep["ok"])
	check("army/with-naturals: pawn override kept", 1,
			(rep["house"]["army"] as Dictionary).size())
	# A piece type that does not exist says which ones do.
	var m2 := SANE.duplicate(true)
	m2["army"] = {"jester": "res://assets/kaykit-skeletons/Skeleton_Minion.glb"}
	check_error("army/unknown-type", HousePack.parse(m2, "res://hauses/_probe"),
			"is not a piece type")


# ── 3. degrading, not crashing ─────────────────────────────────────────────


## Everything optional has a documented default and says so. The only field
## with no default is the id.
func _test_degrades_without_crashing() -> void:
	var bare := {"id": "barehouse"}
	var rep := HousePack.parse(bare, "res://hauses/_probe")
	check("bare: still a house", true, rep["ok"])
	var h: Dictionary = rep["house"]
	check("bare: name defaulted", "Haus Barehouse", str(h["name"]))
	check("bare: coat defaulted to the documented one", HousePack.coat_default(),
			str(h["coat"]))
	check("bare: no crest", "", str(h["crest"]))
	check("bare: no sigil", "", str(h["sigil"]))
	check("bare: colours are real", true,
			Color.html_is_valid(str(h["colors"]["primary"])))
	check("bare: has a kit tint anyway", true,
			Color.html_is_valid(str(h["tints"]["kit"])))
	var warned := "\n".join(rep["warnings"])
	for want in ["name", "archetype", "seat", "motto", "colors", "coat"]:
		check("bare: warns about %s" % want, true, warned.containsn(want))
	check("bare: warnings are plural, not a crash", true, rep["warnings"].size() >= 6)

	# No id at all is the one refusal — nothing can refer to that house.
	check_error("no-id", HousePack.parse({}, "res://hauses/_probe"), "no \"id\"")

	# A pack from the future says so instead of half-loading.
	var future := SANE.duplicate(true)
	future["format"] = HousePack.FORMAT + 5
	check_error("future-format", HousePack.parse(future, "res://hauses/_probe"),
			"newer than this build")

	# A pointer at art that is not there loses the art, not the house.
	var missing := SANE.duplicate(true)
	missing["sigil"] = "not_here.png"
	missing["crest"] = "also_not_here.glb"
	var rep2 := HousePack.parse(missing, "res://hauses/_probe")
	check("missing-art: still a house", true, rep2["ok"])
	check("missing-art: sigil dropped", "", str(rep2["house"]["sigil"]))
	check("missing-art: says what will happen instead", true,
			"\n".join(rep2["warnings"]).containsn("flat"))

	# A typo is a warning with the key quoted, never a silent no-op.
	var typo := SANE.duplicate(true)
	typo["colours"] = {"primary": "#ffffff"}
	var rep3 := HousePack.parse(typo, "res://hauses/_probe")
	check("typo: loaded", true, rep3["ok"])
	check("typo: names the unknown key", true,
			"\n".join(rep3["warnings"]).contains("colours"))

	# A jersey nobody can see is a warning, not a refusal — it is a choice.
	var grey := SANE.duplicate(true)
	grey["tints"] = {"kit": "#8a8a8a"}
	var rep4 := HousePack.parse(grey, "res://hauses/_probe")
	check("pale-jersey: allowed", true, rep4["ok"])
	check("pale-jersey: warned", true,
			"\n".join(rep4["warnings"]).containsn("nearly colourless"))


## ONE BAD PACK MUST NOT TAKE DOWN THE OTHERS. Written to disk, because the
## failure mode being tested is a real folder a real player made.
func _test_one_bad_pack_does_not_take_the_others() -> void:
	var abs_root := ProjectSettings.globalize_path(tmp_dir)
	DirAccess.make_dir_recursive_absolute(abs_root)
	# (a) a manifest that is not JSON at all
	DirAccess.make_dir_recursive_absolute(abs_root.path_join("broken"))
	var f := FileAccess.open(tmp_dir.path_join("broken/haus.json"), FileAccess.WRITE)
	f.store_string("{ \"id\": \"broken\", oops")
	f.close()
	var rep := HousePack.load_from_dir(tmp_dir.path_join("broken"))
	check("bad-pack/json: refused", false, rep["ok"])
	check("bad-pack/json: says where", true,
			"\n".join(rep["errors"]).containsn("not valid JSON"))
	check("bad-pack/json: names the line", true,
			"\n".join(rep["errors"]).containsn("line"))
	# (b) a folder with no manifest at all
	DirAccess.make_dir_recursive_absolute(abs_root.path_join("empty"))
	var rep2 := HousePack.load_from_dir(tmp_dir.path_join("empty"))
	check("bad-pack/no-manifest: refused", false, rep2["ok"])
	check("bad-pack/no-manifest: says what a pack IS", true,
			"\n".join(rep2["errors"]).containsn("haus.json"))
	# (c) a manifest that is a JSON ARRAY
	DirAccess.make_dir_recursive_absolute(abs_root.path_join("array"))
	var f2 := FileAccess.open(tmp_dir.path_join("array/haus.json"), FileAccess.WRITE)
	f2.store_string("[\"winterfang\"]")
	f2.close()
	var rep3 := HousePack.load_from_dir(tmp_dir.path_join("array"))
	check("bad-pack/array: refused", false, rep3["ok"])
	check("bad-pack/array: says it wants an object", true,
			"\n".join(rep3["errors"]).containsn("JSON object"))
	# ...and the roster the game actually plays is untouched by all three.
	check("bad-pack: the nine still stand", 9, HouseRegistry.builtin_house_ids().size())
	_rm_rf(abs_root)


## The DLC path. A pack a player dropped in never went through the editor's
## import pipeline, so its art is parsed at RUNTIME — and the material names
## the engine's dressing contract depends on have to survive that trip.
func _test_runtime_assets_load_from_outside_res() -> void:
	var abs_root := ProjectSettings.globalize_path(tmp_dir)
	DirAccess.make_dir_recursive_absolute(abs_root)
	# a PNG, written and read back as a pack sigil would be
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.48, 0.25, 0.71))
	check("runtime/png: written", OK, img.save_png(abs_root.path_join("sigil.png")))
	var tex := HousePack.load_texture(abs_root.path_join("sigil.png"))
	check("runtime/png: loads outside res://", true, tex != null)
	check("runtime/png: right size", 32, int(tex.get_size().x))
	check("runtime/png: a missing file is null, not a crash", true,
			HousePack.load_texture(abs_root.path_join("nope.png")) == null)
	# a GLB carrying the engine's dressing contract material name
	var glb := abs_root.path_join("pawn_helm.glb")
	check("runtime/glb: written", OK, _write_probe_glb(glb))
	var packed := HousePack.load_scene(glb)
	check("runtime/glb: loads outside res://", true, packed != null)
	var inst := packed.instantiate() if packed != null else null
	check("runtime/glb: instantiates", true, inst != null)
	var found := ""
	if inst != null:
		for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
			var mat := mi.mesh.surface_get_material(0)
			if mat != null:
				found = str(mat.resource_name)
		inst.free()
	check("runtime/glb: the contract material name survives", "pawnhelm_iron", found)
	check("runtime/glb: and the engine classifies it as KIT", assets.Role.KIT,
			int(assets.classify("Helm", found)["role"]))
	check("runtime/glb: a .txt is refused, not crashed on", true,
			HousePack.load_scene(abs_root.path_join("sigil.png")) == null)
	_rm_rf(abs_root)


func _write_probe_glb(path: String) -> int:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [Vector3(-0.1, 0, -0.1), Vector3(0.1, 0, -0.1), Vector3(0, 0.2, 0.1)]:
		st.set_normal(Vector3.UP)
		st.add_vertex(v)
	var mat := StandardMaterial3D.new()
	mat.resource_name = "pawnhelm_iron"
	st.set_material(mat)
	var mi := MeshInstance3D.new()
	mi.name = "ProbeHelm"
	mi.mesh = st.commit()
	var node := Node3D.new()
	node.name = "Helm"
	node.add_child(mi)
	mi.owner = node
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(node, state)
	if err != OK:
		node.free()
		return err
	err = doc.write_to_filesystem(state, path)
	node.free()
	return err


func _rm_rf(abs_path: String) -> void:
	var dir := DirAccess.open(abs_path)
	if dir == null:
		return
	for name in dir.get_files():
		dir.remove(name)
	for name in dir.get_directories():
		_rm_rf(abs_path.path_join(name))
	DirAccess.remove_absolute(abs_path)
