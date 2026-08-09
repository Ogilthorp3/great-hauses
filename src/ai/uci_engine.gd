class_name UciEngine
extends Node
## Minimal async UCI client for Stockfish (the Grand Maester's engine).
##
## Godot 4.7 pattern: OS.execute_with_pipe spawns the engine with blocking
## pipes; a reader Thread blocks on get_line() and feeds a mutex-guarded
## queue; the main thread awaits process frames while draining it. All public
## search entry points are awaitable and never throw.
##
##   var eng := UciEngine.new()
##   add_child(eng)                      # needs the tree for await
##   eng.start()                         # autodetects stockfish
##   await eng.init()                    # uci/isready handshake
##   var r := await eng.search(fen, {"depth": 12, "multipv": 3})
##   # r = {"bestmove": "e2e4", "lines": [{"multipv":1,"move":"e2e4",
##   #      "cp":34,"mate":null,"depth":12,"pv":"e2e4 e7e5 ..."}, ...]}
##
## Shutdown is automatic on tree exit (quit -> grace -> OS.kill) — a
## UciEngine never orphans a stockfish process.

## Unix install prefixes. These are NOT redundant with the PATH scan: a
## double-clicked macOS .app inherits a minimal PATH with no Homebrew in it,
## so a Mac player would otherwise lose the Maester the moment they stopped
## launching from a shell.
const DEFAULT_PATHS := [
	"/opt/homebrew/bin/stockfish",
	"/usr/local/bin/stockfish",
	"/usr/bin/stockfish",
]
## Explicit override, wins over every other lookup. Also how the degradation
## suite points the engine at a path that cannot exist.
const ENV_STOCKFISH := "GREAT_HOUSES_STOCKFISH"
const SEARCH_TIMEOUT_S := 30.0   # outer guard per search; depth limits finish long before

var _pipe: FileAccess = null
var _pid := -1
var _thread: Thread = null
var _mutex := Mutex.new()
var _rx: Array[String] = []      # reader thread -> main thread line queue
var _handshaken := false
var _cur_multipv := 1


## The platform's stockfish filename.
static func binary_name() -> String:
	return "stockfish.exe" if OS.has_feature("windows") else "stockfish"


## Directories searched before PATH, in order. On Windows this is what makes
## "drop stockfish.exe next to GreatHauses.exe" work — the friend never has
## to touch their PATH. On macOS the executable lives inside the bundle, so
## the folder CONTAINING the .app is searched too.
static func sidecar_dirs() -> Array[String]:
	var exe_dir := OS.get_executable_path().get_base_dir()
	var dirs: Array[String] = [exe_dir, exe_dir.path_join("stockfish")]
	if OS.has_feature("macos"):
		# <dir>/Great Hauses.app/Contents/MacOS/<bin> -> <dir>
		var outside := exe_dir.get_base_dir().get_base_dir().get_base_dir()
		if not outside.is_empty():
			dirs.append(outside)
			dirs.append(outside.path_join("stockfish"))
	return dirs


## Scan the PATH environment variable ourselves rather than shelling out to
## `which` — /usr/bin/which does not exist on Windows, and this spawns no
## process at all.
static func search_path_env() -> String:
	var raw := OS.get_environment("PATH")
	if raw.is_empty():
		return ""
	var sep := ";" if OS.has_feature("windows") else ":"
	var bin := binary_name()
	for d in raw.split(sep, false):
		var dir := String(d).strip_edges()
		if dir.is_empty():
			continue
		var p := dir.path_join(bin)
		if FileAccess.file_exists(p):
			return p
	return ""


## Autodetect the stockfish binary, platform-aware and in cost order:
##   1. $GREAT_HOUSES_STOCKFISH   explicit override (tests, power users)
##   2. beside the executable     stockfish[.exe], or a stockfish/ subfolder
##   3. PATH                      scanned directly, no subprocess
##   4. Homebrew/usr prefixes     Unix only, for PATH-less GUI launches
## "" when not installed — every caller treats that as "grey the mode out",
## so a Windows box with no engine degrades instead of crashing.
static func find_stockfish() -> String:
	var override := OS.get_environment(ENV_STOCKFISH).strip_edges()
	if not override.is_empty():
		# An override that does not exist resolves to "" — a deliberately bogus
		# path must degrade exactly like "no engine installed", not fall
		# through to whatever happens to be on this machine's PATH.
		return override if FileAccess.file_exists(override) else ""
	var bin := binary_name()
	for dir in sidecar_dirs():
		var p := dir.path_join(bin)
		if FileAccess.file_exists(p):
			return p
	var on_path := search_path_env()
	if not on_path.is_empty():
		return on_path
	if not OS.has_feature("windows"):
		for p in DEFAULT_PATHS:
			if FileAccess.file_exists(String(p)):
				return String(p)
	return ""


## One line of UI copy for the greyed-out Grand Maester, naming the place
## THIS platform's player should put the binary.
static func install_hint() -> String:
	if OS.has_feature("windows"):
		return "put stockfish.exe next to GreatHauses.exe"
	if OS.has_feature("macos"):
		return "brew install stockfish"
	return "install stockfish from your package manager"


func pid() -> int:
	return _pid


func is_running() -> bool:
	return _pid > 0 and OS.is_process_running(_pid)


func is_ready() -> bool:
	return _handshaken and is_running()


## Spawn the engine process. Returns false when no binary is found or the
## spawn fails. Follow with `await init()` before searching.
func start(path := "") -> bool:
	if _pipe != null:
		return true
	var exe := path if not path.is_empty() else find_stockfish()
	if exe.is_empty():
		push_warning("UciEngine: no stockfish binary found (%s)" % install_hint())
		return false
	# An explicitly-passed path is NOT vetted by find_stockfish(), and
	# OS.execute_with_pipe happily forks for a path that cannot be exec'd:
	# it hands back a live pid and a pipe, the child dies immediately, and
	# start() would report success for an engine that will never answer
	# (init() then burns its full 5 s timeout before anything degrades).
	# Check the file up front so a wrong path greys the Maester out at once.
	if not FileAccess.file_exists(exe):
		push_warning("UciEngine: no stockfish binary at %s (%s)" % [exe, install_hint()])
		return false
	var info := OS.execute_with_pipe(exe, [])
	if info.is_empty():
		push_warning("UciEngine: failed to spawn %s" % exe)
		return false
	_pipe = info["stdio"]
	_pid = int(info["pid"])
	_thread = Thread.new()
	_thread.start(_reader)
	return true


## UCI handshake: uci -> uciok, isready -> readyok. Awaitable; false on timeout.
func init(timeout_s := 5.0) -> bool:
	if _pipe == null:
		return false
	_send("uci")
	if not await _wait_line(func(l: String) -> bool: return l == "uciok", timeout_s):
		return false
	_send("isready")
	if not await _wait_line(func(l: String) -> bool: return l == "readyok", timeout_s):
		return false
	_handshaken = true
	return true


## One synchronous-feeling search. fen "" = startpos. opts:
##   depth: int          go depth N
##   movetime_ms: int    go movetime N (combinable with depth; first limit wins)
##   multipv: int        MultiPV k (default 1)
##   searchmoves: Array  restrict the search to these UCI moves
##   timeout_s: float    outer guard (default SEARCH_TIMEOUT_S)
## Returns {"bestmove": String, "lines": Array[Dictionary]} — lines sorted by
## multipv rank, each {"multipv","move","cp","mate","depth","pv"}. {} on failure.
func search(fen: String, opts: Dictionary = {}) -> Dictionary:
	if not is_ready():
		return {}
	var multipv := int(opts.get("multipv", 1))
	if multipv != _cur_multipv:
		_send("setoption name MultiPV value %d" % multipv)
		_cur_multipv = multipv
	_take_lines()   # drop any stale output from a previous search
	_send("isready")
	if not await _wait_line(func(l: String) -> bool: return l == "readyok", 5.0):
		return {}
	_send("position startpos" if fen.is_empty() else "position fen " + fen)
	var go := "go"
	if opts.has("depth"):
		go += " depth %d" % int(opts["depth"])
	if opts.has("movetime_ms"):
		go += " movetime %d" % int(opts["movetime_ms"])
	if not (opts.has("depth") or opts.has("movetime_ms")):
		go += " depth 10"
	if opts.has("searchmoves"):
		go += " searchmoves " + " ".join(PackedStringArray(opts["searchmoves"]))
	_send(go)
	var infos := {}      # multipv rank -> deepest info line seen
	var bestmove := ""
	var deadline := Time.get_ticks_msec() + int(float(opts.get("timeout_s", SEARCH_TIMEOUT_S)) * 1000.0)
	while bestmove.is_empty() and Time.get_ticks_msec() < deadline:
		if not is_running():
			return {}
		for l in _take_lines():
			if l.begins_with("bestmove"):
				bestmove = l.get_slice(" ", 1)
			elif l.begins_with("info ") and l.contains(" pv "):
				var parsed := _parse_info(l)
				if not parsed.is_empty():
					infos[int(parsed["multipv"])] = parsed
		await get_tree().process_frame
	if bestmove.is_empty():
		# Guard tripped: stop the search and give the engine a beat to answer.
		_send("stop")
		var d2 := Time.get_ticks_msec() + 2000
		while bestmove.is_empty() and Time.get_ticks_msec() < d2:
			for l in _take_lines():
				if l.begins_with("bestmove"):
					bestmove = l.get_slice(" ", 1)
			await get_tree().process_frame
	var lines: Array = []
	var ranks := infos.keys()
	ranks.sort()
	for r in ranks:
		lines.append(infos[r])
	return {"bestmove": bestmove, "lines": lines}


## quit -> 1 s grace -> OS.kill. Joins the reader thread, closes the pipe.
## Safe to call repeatedly; also fired by _exit_tree and predelete.
func shutdown() -> void:
	_handshaken = false
	if _pipe != null and is_running():
		_pipe.store_line("quit")
		_pipe.flush()
	var deadline := Time.get_ticks_msec() + 1000
	while is_running() and Time.get_ticks_msec() < deadline:
		OS.delay_msec(10)
	if is_running():
		OS.kill(_pid)
	if _thread != null:
		if _thread.is_started():
			_thread.wait_to_finish()   # EOF after process death releases the reader
		_thread = null
	if _pipe != null:
		_pipe.close()
		_pipe = null
	_pid = -1


func _exit_tree() -> void:
	shutdown()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		shutdown()


# -- internals ---------------------------------------------------------------


func _send(cmd: String) -> void:
	if _pipe != null:
		_pipe.store_line(cmd)
		_pipe.flush()


func _reader() -> void:
	var pipe := _pipe   # local ref: main thread may null the member during shutdown
	while pipe.is_open() and pipe.get_error() == OK:
		var line := pipe.get_line().strip_edges()
		if pipe.get_error() != OK and line.is_empty():
			break
		if line.is_empty():
			continue
		_mutex.lock()
		_rx.append(line)
		_mutex.unlock()


func _take_lines() -> Array[String]:
	_mutex.lock()
	var out := _rx.duplicate()
	_rx.clear()
	_mutex.unlock()
	return out


func _wait_line(pred: Callable, timeout_s: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		for l in _take_lines():
			if pred.call(l):
				return true
		if not is_inside_tree():
			return false
		await get_tree().process_frame
	return false


## Parse one "info ... multipv N score cp/mate X ... pv m1 m2 ..." line.
## {} when the line carries no pv move.
func _parse_info(l: String) -> Dictionary:
	var toks := l.split(" ", false)
	var out := {"multipv": 1, "cp": null, "mate": null, "depth": 0, "move": "", "pv": ""}
	var i := 0
	while i < toks.size():
		match toks[i]:
			"multipv":
				if i + 1 < toks.size():
					out["multipv"] = int(toks[i + 1])
				i += 2
			"depth":
				if i + 1 < toks.size():
					out["depth"] = int(toks[i + 1])
				i += 2
			"score":
				if i + 2 < toks.size():
					if toks[i + 1] == "cp":
						out["cp"] = int(toks[i + 2])
					elif toks[i + 1] == "mate":
						out["mate"] = int(toks[i + 2])
				i += 3
			"pv":
				var pv := PackedStringArray()
				for j in range(i + 1, toks.size()):
					pv.append(toks[j])
				out["move"] = pv[0] if pv.size() > 0 else ""
				out["pv"] = " ".join(pv)
				i = toks.size()
			_:
				i += 1
	return out if not String(out["move"]).is_empty() else {}
