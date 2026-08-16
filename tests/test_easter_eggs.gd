extends SceneTree
## Headless Unit Test Suite for Zelda Easter Eggs.

const ZeldaEasterEggsScript := preload("res://src/cinematics/zelda_easter_eggs.gd")

var checks_run := 0
var failures := 0


func _init() -> void:
	_main()


func _main() -> void:
	print("=== Great Hauses — Zelda Easter Eggs Unit Suite ===")
	_test_audio_synthesis()
	_test_secret_key_matching()
	_test_king_triple_click()
	_test_rage_click_cucco()
	_test_procedural_props()

	print("---")
	if failures == 0:
		print("EASTER EGGS OK — all %d checks passed" % checks_run)
		quit(0)
	else:
		print("EASTER EGGS FAILED — %d of %d checks failed" % [failures, checks_run])
		quit(1)


func check(name: String, expected, actual) -> void:
	checks_run += 1
	var ok := str(expected) == str(actual)
	if not ok:
		failures += 1
	print("%s %s (expected %s, got %s)" % ["PASS" if ok else "FAIL", name, expected, actual])


func _test_audio_synthesis() -> void:
	var chime := ZeldaEasterEggsScript.get_secret_chime_stream()
	check("chime: stream synthesized", true, chime != null)
	check("chime: 16-bit format", AudioStreamWAV.FORMAT_16_BITS, chime.format)
	check("chime: has audio data", true, chime.data.size() > 1000)

	var fanfare := ZeldaEasterEggsScript.get_fanfare_stream()
	check("fanfare: stream synthesized", true, fanfare != null)
	check("fanfare: has audio data", true, fanfare.data.size() > 1000)

	var cucco := ZeldaEasterEggsScript.get_cucco_stream()
	check("cucco: stream synthesized", true, cucco != null)
	check("cucco: has audio data", true, cucco.data.size() > 500)


func _test_secret_key_matching() -> void:
	var egg := ZeldaEasterEggsScript.new()
	var dummy := Node.new()

	# Test typing "zelda"
	var triggered := false
	for ch in "zelda":
		var ev := InputEventKey.new()
		ev.pressed = true
		ev.unicode = ch.unicode_at(0)
		if egg.handle_key_input(ev, dummy):
			triggered = true

	check("keys: 'zelda' sequence triggers easter egg", true, triggered)
	dummy.free()
	egg.free()


func _test_king_triple_click() -> void:
	var egg := ZeldaEasterEggsScript.new()
	var dummy := Node.new()

	# Click king 3 times
	egg.handle_piece_clicked(5, true, dummy)
	egg.handle_piece_clicked(5, true, dummy)
	check("king: 2 clicks not triggered yet", 2, egg._king_click_times.size())
	egg.handle_piece_clicked(5, true, dummy)
	check("king: 3 clicks consumed and triggered", 0, egg._king_click_times.size())

	dummy.free()
	egg.free()


func _test_rage_click_cucco() -> void:
	var egg := ZeldaEasterEggsScript.new()
	var dummy := Node.new()

	for i in 6:
		egg.handle_piece_clicked(0, false, dummy)
	check("rage: 6 clicks accumulated", 6, egg._rage_click_times.size())

	# 7th click triggers Cucco
	egg.handle_piece_clicked(0, false, dummy)
	check("rage: 7th click consumed and triggered", 0, egg._rage_click_times.size())

	dummy.free()
	egg.free()


func _test_procedural_props() -> void:
	var sword := ZeldaEasterEggsScript._build_master_sword()
	check("sword: node created", true, sword != null)
	check("sword: has mesh children", true, sword.get_child_count() >= 4)
	sword.free()

	var flurry := ZeldaEasterEggsScript._build_feather_flurry()
	check("flurry: node created", true, flurry != null)
	check("flurry: contains 32 feathers", 32, flurry.get_child_count())
	flurry.free()

	# Verify Triforce sigil banner file and Haus Hyrule manifest
	check("sigil: hyrule Triforce PNG exists", true, FileAccess.file_exists("res://assets/sigils/hyrule.png"))
	var sigil_img := Image.load_from_file(ProjectSettings.globalize_path("res://assets/sigils/hyrule.png"))
	check("sigil: loaded 512x512 image", true, sigil_img != null and sigil_img.get_width() == 512)

	# Verify secret unlock of Haus Hyrule
	var hs_dummy := Node.new()
	var egg := ZeldaEasterEggsScript.new()
	egg.trigger_zelda_secret(hs_dummy, "TRIFORCE SECRET!")
	var hyrule: Dictionary = HouseRegistry.get_house("hyrule")
	check("house: Haus Hyrule registered on secret", true, not hyrule.is_empty())
	check("house: seat is Temple of Time", "Temple of Time", hyrule.get("seat", ""))
	check("house: sigil is hyrule.png", "res://assets/sigils/hyrule.png", hyrule.get("sigil", ""))
	check("house: coat is white_grey steed", "white_grey", hyrule.get("coat", ""))
	egg.free()
	hs_dummy.free()
