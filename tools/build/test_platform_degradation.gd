extends SceneTree

# Platform-degradation suite — the two macOS-specific opponents must DEGRADE,
# not crash and not hang, on a machine that has neither of them.
#
#   Grand Maester -> shells out to a Stockfish binary
#   DS4-Oracle    -> talks to a local HTTP endpoint
#
# The friend's Windows PC has no Homebrew Stockfish and no SSH tunnel to the
# MBP, so both of those are simply absent there. We cannot boot Windows here,
# so we reproduce the *condition* on macOS: point each one at a path/URL that
# cannot resolve and assert it fails fast, reports a reason, and leaves the
# rest of the game alone.
#
# Run: /Applications/Godot.app/Contents/MacOS/Godot --headless --path <project> \
#          -s res://tools/build/test_platform_degradation.gd
# Exit 0 = all green, 1 = failures.

const UE := preload("res://src/ai/uci_engine.gd")
const DS4 := preload("res://src/ai/ds4_opponent.gd")
const CS := preload("res://src/chess/ChessState.gd")

# A path that cannot exist on any machine.
const BOGUS_ENGINE := "/nonexistent/great-houses/stockfish-does-not-exist"
# Loopback discard port: nothing listens, so the OS refuses instantly.
const REFUSED_URL := "http://127.0.0.1:9"
# TEST-NET-1 (RFC 5737) — routable nowhere, so this BLACK-HOLES instead of
# refusing. This is the case that actually hangs a naive client.
const BLACKHOLE_URL := "http://192.0.2.1:18000"
const BLACKHOLE_TIMEOUT_S := 3.0

var rows := []
var failures := 0
var _mark := 0


func _initialize() -> void:
	_main()


func _main() -> void:
	print("=== Platform degradation — Maester (stockfish) + Oracle (HTTP) ===")
	print("host: %s" % OS.get_name())
	_mark = Time.get_ticks_msec()
	await _test_stockfish()
	await _test_oracle()
	_print_summary()


# ── The Grand Maester: a missing engine must grey out, never crash ─────────
func _test_stockfish() -> void:
	# Platform naming — the thing that was hardcoded to Unix before.
	var expect_bin := "stockfish.exe" if OS.has_feature("windows") else "stockfish"
	check("maester: binary_name matches platform", expect_bin, UE.binary_name())
	check("maester: install hint is non-empty", true, not UE.install_hint().is_empty())
	check("maester: sidecar dirs are searched", true, UE.sidecar_dirs().size() >= 2)

	# Baseline: this Mac HAS stockfish, so the real lookup must still work.
	# (If this regresses, the maester silently vanishes on dev machines.)
	OS.unset_environment(UE.ENV_STOCKFISH)
	var real := UE.find_stockfish()
	check("maester: real lookup finds an engine on this Mac", true,
		not real.is_empty() and FileAccess.file_exists(real))
	if not real.is_empty():
		print("  stockfish resolved to %s" % real)

	# THE DEGRADATION: a bogus override must resolve to "" — NOT fall through
	# to the Homebrew copy that happens to exist on this box, or the test
	# would be proving nothing.
	OS.set_environment(UE.ENV_STOCKFISH, BOGUS_ENGINE)
	var t0 := Time.get_ticks_msec()
	var missing := UE.find_stockfish()
	var lookup_ms := Time.get_ticks_msec() - t0
	check("maester: bogus override resolves to \"\" (greys out)", "", missing)
	check("maester: lookup fails fast (%d ms)" % lookup_ms, true, lookup_ms < 1000)

	# start() must return false rather than throw or block.
	var eng: UE = UE.new()
	eng.name = "DegradedEngine"
	root.add_child(eng)
	while not eng.is_inside_tree():
		await process_frame
	t0 = Time.get_ticks_msec()
	var started_auto: bool = eng.start()             # no path -> autodetect -> ""
	var started_explicit: bool = eng.start(BOGUS_ENGINE)  # explicit bogus path
	var start_ms := Time.get_ticks_msec() - t0
	check("maester: start() with no engine returns false", false, started_auto)
	check("maester: start(bogus path) returns false", false, started_explicit)
	check("maester: start() never blocks (%d ms)" % start_ms, true, start_ms < 2000)
	check("maester: no engine process was spawned", -1, eng.pid())
	check("maester: is_ready() false when degraded", false, eng.is_ready())
	# shutdown() on a never-started engine must be a no-op, not a crash.
	eng.shutdown()
	check("maester: shutdown() safe when never started", -1, eng.pid())
	eng.queue_free()

	OS.unset_environment(UE.ENV_STOCKFISH)
	check("maester: lookup restored after override cleared", true,
		not UE.find_stockfish().is_empty())


# ── The DS4-Oracle: an unreachable endpoint must fail fast, not hang ───────
func _test_oracle() -> void:
	# chat_url() reads DS4_CHESS_URL before endpoint_override, so an ambient
	# value in the shell would silently steer this whole test at a live box.
	OS.unset_environment(DS4.ENV_URL)

	var orc: DS4 = DS4.new()
	orc.name = "DegradedOracle"
	orc.mode = DS4.MODE_PURE          # no stockfish involvement in this test
	orc.endpoint_override = REFUSED_URL
	root.add_child(orc)
	while not orc.is_inside_tree():
		await process_frame

	check("oracle: endpoint_override drives chat_url",
		"http://127.0.0.1:9/v1/chat/completions", orc.chat_url())

	# 1. Connection REFUSED — ping must come back false, fast, with copy for
	#    the greyed-out entry.
	var t0 := Time.get_ticks_msec()
	var up: bool = await orc.ping(5.0)
	var refused_ms := Time.get_ticks_msec() - t0
	check("oracle: ping(refused) returns false", false, up)
	check("oracle: offline_reason set for the UI", true, not orc.offline_reason.is_empty())
	check("oracle: refused ping is fast (%d ms)" % refused_ms, true, refused_ms < 5000)
	print("  offline_reason: %s" % orc.offline_reason)

	# 2. BLACK HOLE — the genuinely dangerous case: no RST comes back, so a
	#    client without a timeout waits forever. Must honour the budget.
	orc.endpoint_override = BLACKHOLE_URL
	t0 = Time.get_ticks_msec()
	var up2: bool = await orc.ping(BLACKHOLE_TIMEOUT_S)
	var blackhole_ms := Time.get_ticks_msec() - t0
	check("oracle: ping(black hole) returns false", false, up2)
	check("oracle: black hole respects timeout (%d ms, budget %d ms)"
		% [blackhole_ms, int(BLACKHOLE_TIMEOUT_S * 1000)],
		true, blackhole_ms < int(BLACKHOLE_TIMEOUT_S * 1000) + 2500)

	# 3. The real gameplay path: asked for a move with nothing listening, the
	#    Oracle must still hand back a LEGAL move (random fallback) and flag
	#    that it stumbled — a hang here would freeze the friend's game.
	orc.endpoint_override = REFUSED_URL
	var stumbled := {"hit": false}
	orc.oracle_stumbled.connect(func(_reason: String) -> void: stumbled["hit"] = true)
	var state = CS.new()
	state.set_fen(CS.INITIAL_FEN)
	t0 = Time.get_ticks_msec()
	var mv = await orc.choose_move(state, 2)
	var move_ms := Time.get_ticks_msec() - t0
	check("oracle: unreachable endpoint still returns a move", true, mv != null)
	if mv != null:
		check("oracle: the fallback move is legal", true,
			state.move_from_uci(String(mv.to_uci())) != null)
	check("oracle: fallback flagged via oracle_stumbled", true, stumbled["hit"])
	check("oracle: last_source is the random fallback", "fallback", orc.last_source)
	check("oracle: move request never hangs (%d ms)" % move_ms, true, move_ms < 30000)

	orc.queue_free()


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
	print("%-58s %-12s %-12s %-6s %s" % ["test", "expected", "actual", "ok", "ms"])
	for row in rows:
		print("%-58s %-12s %-12s %-6s %d" % [row[0], row[1].left(12), row[2].left(12),
			"PASS" if row[3] else "FAIL", row[4]])
	print("")
	print("%d checks, %d failures" % [rows.size(), failures])
	quit(0 if failures == 0 else 1)
