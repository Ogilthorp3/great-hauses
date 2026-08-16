class_name StockfishBridge
extends RefCounted
## StockfishBridge — Connects Stockfish 18 with NNUE Neural Networks
## to Great Hauses for 3600+ Grandmaster-level analysis and move recommendations.

const STOCKFISH_PATHS := [
	"/opt/homebrew/bin/stockfish",
	"/usr/local/bin/stockfish",
	"/usr/bin/stockfish",
	"stockfish"
]

static var _cached_bin_path := ""
static var _checked_bin := false


## Find Stockfish 18 binary on the system
static func get_stockfish_path() -> String:
	if _checked_bin:
		return _cached_bin_path

	_checked_bin = true
	for p in STOCKFISH_PATHS:
		if FileAccess.file_exists(p):
			_cached_bin_path = p
			return _cached_bin_path

	# Try 'which stockfish'
	var out: Array = []
	var rc := OS.execute("which", ["stockfish"], out)
	if rc == 0 and not out.is_empty():
		var found_path := str(out[0]).strip_edges()
		if not found_path.is_empty() and FileAccess.file_exists(found_path):
			_cached_bin_path = found_path
			return _cached_bin_path

	_cached_bin_path = ""
	return ""


## Check if Stockfish 18 is available
static func is_available() -> bool:
	return not get_stockfish_path().is_empty()


## Run deep Stockfish 18 NNUE analysis on a given FEN position
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

	result["available"] = true
	result["engine"] = "Stockfish 18 NNUE (3600+ Elo)"

	# Construct python / shell one-shot wrapper to interact cleanly with UCI
	var py_script := """import subprocess, time, sys
sf = '%s'
fen = '%s'
p = subprocess.Popen([sf], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
p.stdin.write('uci\\nisready\\nposition fen ' + fen + '\\ngo movetime %d\\n')
p.stdin.flush()
time.sleep(%.3f)
p.stdin.write('quit\\n')
p.stdin.flush()
out, _ = p.communicate()
print(out)
""" % [sf_path, fen, movetime_ms, float(movetime_ms) / 1000.0 + 0.1]

	var output: Array = []
	var rc := OS.execute("python3", ["-c", py_script], output)
	if rc != 0 or output.is_empty():
		return result

	var text := str(output[0])
	result["raw_info"] = text

	for line in text.split("\n"):
		line = line.strip_edges()
		if line.begins_with("info ") and "score " in line:
			# Parse centipawns or mate
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

	return result


static func _uci_to_sq(coord: String) -> int:
	if coord.length() < 2:
		return -1
	var col := ord(coord[0]) - ord("a")
	var row := int(coord[1]) - 1
	if col < 0 or col > 7 or row < 0 or row > 7:
		return -1
	return row * 8 + col
