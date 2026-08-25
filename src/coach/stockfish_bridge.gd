class_name StockfishBridge
extends RefCounted
## StockfishBridge — Connects Stockfish 18 with NNUE Neural Networks
## to Great Hauses for 3600+ Grandmaster-level analysis and move recommendations.

const UciEngineScript := preload("res://src/ai/uci_engine.gd")

static var _cached_bin_path := ""
static var _checked_bin := false


## Find Stockfish binary on the system (delegates to UciEngine's multi-tier platform search)
static func get_stockfish_path() -> String:
	if _checked_bin:
		return _cached_bin_path

	_checked_bin = true
	if not platform_can_spawn():
		_cached_bin_path = ""
		return _cached_bin_path

	_cached_bin_path = UciEngineScript.find_stockfish()
	return _cached_bin_path


## PLATFORMS THAT CANNOT FORK. iOS forbids spawning a child process outright
## (App Store review rejects it and the sandbox blocks it), and Web has no
## process model at all.
static func platform_can_spawn() -> bool:
	return not (OS.has_feature("ios") or OS.has_feature("web"))


## Check if Stockfish 18 is available
static func is_available() -> bool:
	return not get_stockfish_path().is_empty()


## Run deep Stockfish 18 NNUE analysis on a given FEN position using native Godot pipes
static func analyze_fen(fen: String, movetime_ms: int = 150) -> Dictionary:
	var result := {
		"available": false,
		"engine": "Internal Minimax",
		"bestmove_uci": "",
		"from_sq": -1,
		"to_sq": -1,
		"eval_cp": 0.0,
		"mate_in": 0,
		"pv": [],
		"raw_info": ""
	}

	var sf_path := get_stockfish_path()
	if sf_path.is_empty():
		return result

	# Execute Stockfish directly via native OS pipes — NO Python, NO shell wrapper
	var info := OS.execute_with_pipe(sf_path, [])
	if info.is_empty() or not info.has("stdio"):
		return result

	var pipe: FileAccess = info["stdio"]
	var pid: int = int(info.get("pid", -1))
	if pipe == null or not pipe.is_open():
		return result

	result["available"] = true
	result["engine"] = "Stockfish 18 NNUE (3600+ Elo)"

	pipe.store_string("uci\nisready\nposition fen %s\ngo movetime %d\n" % [fen, movetime_ms])
	pipe.flush()

	var deadline := Time.get_ticks_msec() + movetime_ms + 1200
	var text := ""

	while Time.get_ticks_msec() < deadline:
		if pipe.is_open() and pipe.get_error() == OK:
			var line := pipe.get_line().strip_edges()
			if line.is_empty():
				OS.delay_msec(2)
				continue
			text += line + "\n"
			if line.begins_with("info ") and "score " in line:
				var tokens := line.split(" ")
				for i in range(tokens.size()):
					if tokens[i] == "cp" and i + 1 < tokens.size():
						result["eval_cp"] = float(tokens[i + 1]) / 100.0
					elif tokens[i] == "mate" and i + 1 < tokens.size():
						result["mate_in"] = int(tokens[i + 1])
					elif tokens[i] == "pv":
						result["pv"] = tokens.slice(i + 1)
			elif line.begins_with("bestmove "):
				var parts := line.split(" ")
				if parts.size() >= 2:
					var uci_move := parts[1]
					result["bestmove_uci"] = uci_move
					if uci_move.length() >= 4:
						result["from_sq"] = _uci_to_sq(uci_move.substr(0, 2))
						result["to_sq"] = _uci_to_sq(uci_move.substr(2, 2))
				break
		else:
			break

	result["raw_info"] = text
	if pipe.is_open():
		pipe.store_string("quit\n")
		pipe.flush()
		pipe.close()
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)

	return result


static func _uci_to_sq(coord: String) -> int:
	if coord.length() < 2:
		return -1
	var col := ord(coord[0]) - ord("a")
	var row := int(coord[1]) - 1
	if col < 0 or col > 7 or row < 0 or row > 7:
		return -1
	return row * 8 + col
