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


## Check if Stockfish 18 is available (native binary or embedded loopback)
static func is_available() -> bool:
	if not get_stockfish_path().is_empty():
		return true
	# Check embedded in-process loopback (iOS/iPadOS/macOS) or Sanctum bridge
	return _check_loopback_health("127.0.0.1", 8765)


## Run deep Stockfish 18 NNUE analysis on a given FEN position
static func analyze_fen(fen: String, movetime_ms: int = 150) -> Dictionary:
	var sf_path := get_stockfish_path()
	if not sf_path.is_empty():
		return _analyze_native_pipe(sf_path, fen, movetime_ms)

	# Try embedded in-process server (iOS/iPadOS/macOS) on loopback
	var loopback_res := _analyze_http("127.0.0.1", 8765, fen, movetime_ms)
	if loopback_res.get("available", false):
		return loopback_res

	# Return unavailable fallback
	return {
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


static func _analyze_native_pipe(sf_path: String, fen: String, movetime_ms: int) -> Dictionary:
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


static func _check_loopback_health(host: String, port: int) -> bool:
	var tcp := StreamPeerTCP.new()
	var err := tcp.connect_to_host(host, port)
	if err != OK:
		return false
	var deadline := Time.get_ticks_msec() + 100
	while tcp.get_status() == StreamPeerTCP.STATUS_CONNECTING and Time.get_ticks_msec() < deadline:
		tcp.poll()
		OS.delay_msec(1)
	var ok := (tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED)
	tcp.disconnect_from_host()
	return ok


static func _analyze_http(host: String, port: int, fen: String, movetime_ms: int) -> Dictionary:
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

	var tcp := StreamPeerTCP.new()
	var err := tcp.connect_to_host(host, port)
	if err != OK:
		return result

	var connect_deadline := Time.get_ticks_msec() + 250
	while tcp.get_status() == StreamPeerTCP.STATUS_CONNECTING and Time.get_ticks_msec() < connect_deadline:
		tcp.poll()
		OS.delay_msec(1)

	if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		tcp.disconnect_from_host()
		return result

	var encoded_fen := fen.uri_encode()
	var req := "GET /analyze?fen=%s&movetime=%d HTTP/1.1\r\nHost: %s\r\nConnection: close\r\n\r\n" % [encoded_fen, movetime_ms, host]
	tcp.put_data(req.to_utf8_buffer())

	var timeout := Time.get_ticks_msec() + movetime_ms + 1500
	var response := ""

	while Time.get_ticks_msec() < timeout:
		tcp.poll()
		var avail := tcp.get_available_bytes()
		if avail > 0:
			var data := tcp.get_data(avail)
			if data[0] == OK:
				response += (data[1] as PackedByteArray).get_string_from_utf8()
				if "\r\n\r\n" in response and "}" in response:
					break
		elif tcp.get_status() == StreamPeerTCP.STATUS_ERROR or tcp.get_status() == StreamPeerTCP.STATUS_NONE:
			break
		OS.delay_msec(2)

	tcp.disconnect_from_host()

	var body_start := response.find("\r\n\r\n")
	if body_start != -1:
		var json_str := response.substr(body_start + 4)
		var parsed = JSON.parse_string(json_str)
		if parsed is Dictionary and parsed.has("bestmove_uci"):
			result["available"] = true
			result["engine"] = parsed.get("engine", "Stockfish 18 (Embedded Apple Silicon)")
			result["bestmove_uci"] = parsed.get("bestmove_uci", "")
			result["eval_cp"] = float(parsed.get("eval_cp", 0.0))
			result["pv"] = parsed.get("pv", [])
			if result["bestmove_uci"].length() >= 4:
				result["from_sq"] = _uci_to_sq(result["bestmove_uci"].substr(0, 2))
				result["to_sq"] = _uci_to_sq(result["bestmove_uci"].substr(2, 2))

	return result
