extends SceneTree

# Headless test for the UciEngine Stockfish client (src/ai/uci_engine.gd).
# Run: /Applications/Godot.app/Contents/MacOS/Godot --headless --path <project> -s res://tests/test_uci_engine.gd
# Exit code 0 = all green, 1 = failures. Requires stockfish on the box
# (autodetected); when missing the suite fails loudly — the advisor modes
# depend on it on dev machines.

const CS := preload("res://src/chess/ChessState.gd")
const UE := preload("res://src/ai/uci_engine.gd")

const MATE_IN_1_FEN := "6k1/5ppp/8/8/8/8/8/4R1K1 w - - 0 1"   # e1e8#

var rows := []
var failures := 0
var _mark := 0


func _initialize() -> void:
	_main()


func _main() -> void:
	print("=== UciEngine (Stockfish) — headless test suite ===")
	_mark = Time.get_ticks_msec()

	var path: String = UE.find_stockfish()
	check("uci: stockfish binary found", true, not path.is_empty())
	if path.is_empty():
		_print_summary()
		return
	print("stockfish at %s" % path)

	var eng: UE = UE.new()
	eng.name = "Engine"
	root.add_child(eng)
	while not eng.is_inside_tree():
		await process_frame
	check("uci: start", true, eng.start(path))
	check("uci: init handshake", true, await eng.init(8.0))

	# 1. startpos bestmove sane at depth 8, under 2 s
	var state = CS.new()
	var t0 := Time.get_ticks_msec()
	var res: Dictionary = await eng.search("", {"depth": 8})
	var elapsed := Time.get_ticks_msec() - t0
	_mark = Time.get_ticks_msec()
	var bm := String(res.get("bestmove", ""))
	check("uci: startpos bestmove legal (%s)" % bm, true, state.move_from_uci(bm) != null)
	check("uci: depth-8 under 2s (%d ms)" % elapsed, true, elapsed < 2000)

	# 2. MultiPV 3 — three distinct legal moves, each with an eval
	res = await eng.search(CS.INITIAL_FEN, {"depth": 8, "multipv": 3})
	var lines: Array = res.get("lines", [])
	check("uci: multipv-3 returns 3 lines", 3, lines.size())
	var seen := {}
	var all_legal := true
	var all_scored := true
	for l in lines:
		var mv := String(l.get("move", ""))
		seen[mv] = true
		if state.move_from_uci(mv) == null:
			all_legal = false
		if l.get("cp") == null and l.get("mate") == null:
			all_scored = false
	check("uci: multipv moves distinct", 3, seen.size())
	check("uci: multipv moves legal", true, all_legal)
	check("uci: multipv lines carry evals", true, all_scored)

	# 3. mate-in-1 FEN returns the mate
	res = await eng.search(MATE_IN_1_FEN, {"depth": 8})
	check("uci: mate-in-1 bestmove", "e1e8", String(res.get("bestmove", "")))
	var m1: Array = res.get("lines", [])
	var mate_val := 0
	if not m1.is_empty() and m1[0].get("mate") != null:
		mate_val = int(m1[0]["mate"])
	check("uci: mate score reported", 1, mate_val)

	# 4. clean shutdown — never orphan a stockfish process
	var pid: int = eng.pid()
	check("uci: engine running before shutdown", true, OS.is_process_running(pid))
	eng.shutdown()
	OS.delay_msec(200)
	check("uci: process gone after shutdown", false, OS.is_process_running(pid))
	eng.queue_free()

	_print_summary()


func check(test_name: String, expected, actual) -> void:
	var now := Time.get_ticks_msec()
	var ms := now - _mark
	_mark = now
	var ok := str(expected) == str(actual)
	if not ok:
		failures += 1
	rows.push_back([test_name, str(expected), str(actual), ok, ms])


func _print_summary() -> void:
	print("")
	print("%-46s %-14s %-14s %-6s %s" % ["test", "expected", "actual", "ok", "ms"])
	for row in rows:
		print("%-46s %-14s %-14s %-6s %d" % [row[0], row[1].left(14), row[2].left(14),
			"PASS" if row[3] else "FAIL", row[4]])
	print("")
	print("%d checks, %d failures" % [rows.size(), failures])
	quit(0 if failures == 0 else 1)
