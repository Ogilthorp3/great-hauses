class_name LeelaBridge
extends RefCounted
## LeelaBridge — Connects Leela Chess Zero (Lc0 / AlphaZero Deep Neural Networks)
## to Great Hauses for intuitive positional strategy, holistic board harmony, and human-playable plans.

const LEELA_PATHS := [
	"/opt/homebrew/bin/lc0",
	"/usr/local/bin/lc0",
	"/usr/bin/lc0",
	"lc0"
]

static var _cached_bin_path := ""
static var _checked_bin := false


## Find Lc0 binary on the system
static func get_leela_path() -> String:
	if _checked_bin:
		return _cached_bin_path

	_checked_bin = true
	if not platform_can_spawn():
		_cached_bin_path = ""
		return _cached_bin_path
	for p in LEELA_PATHS:
		if FileAccess.file_exists(p):
			_cached_bin_path = p
			return _cached_bin_path

	# Try 'which lc0'
	var out: Array = []
	var rc := OS.execute("which", ["lc0"], out)
	if rc == 0 and not out.is_empty():
		var found_path := str(out[0]).strip_edges()
		if not found_path.is_empty() and FileAccess.file_exists(found_path):
			_cached_bin_path = found_path
			return _cached_bin_path

	_cached_bin_path = ""
	return ""


## PLATFORMS THAT CANNOT FORK. iOS forbids spawning a child process outright
## (App Store review rejects it and the sandbox blocks it), and Web has no
## process model at all. Asking is the FIRST question, before any filesystem
## probe or `which`, so the existing degradation path — a greyed-out Grand
## Maester rather than a crash — is what the player meets on an iPad.
static func platform_can_spawn() -> bool:
	return not (OS.has_feature("ios") or OS.has_feature("web"))


## Check if Leela Lc0 is available
static func is_available() -> bool:
	return not get_leela_path().is_empty()


## Run deep Leela Lc0 Neural Net MCTS analysis on a given FEN position
static func analyze_fen(fen: String, max_nodes: int = 80) -> Dictionary:
	var result := {
		"available": false,
		"engine": "Leela Chess Zero (Lc0)",
		"bestmove_uci": "",
		"from_sq": -1,
		"to_sq": -1,
		"eval_cp": 0.0,
		"pv": [],
		"raw_info": ""
	}

	var lc0_path := get_leela_path()
	if lc0_path.is_empty():
		return result

	result["available"] = true
	result["engine"] = "Leela Chess Zero (Lc0 AlphaZero)"

	var py_script := """import subprocess, sys
lc0 = '%s'
fen = '%s'
p = subprocess.Popen([lc0], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
p.stdin.write('uci\\nisready\\nposition fen ' + fen + '\\ngo nodes %d\\n')
p.stdin.flush()
output = []
while True:
    line = p.stdout.readline()
    if not line:
        break
    line = line.strip()
    output.append(line)
    if line.startswith('bestmove'):
        break
p.stdin.write('quit\\n')
p.stdin.flush()
print('\\n'.join(output))
""" % [lc0_path, fen, max_nodes]

	var output: Array = []
	var rc := OS.execute("python3", ["-c", py_script], output)
	if rc != 0 or output.is_empty():
		return result

	var text := str(output[0])
	result["raw_info"] = text

	for line in text.split("\n"):
		line = line.strip_edges()
		if line.begins_with("info ") and "score cp " in line:
			var tokens := line.split(" ")
			for i in range(tokens.size()):
				if tokens[i] == "cp" and i + 1 < tokens.size():
					result["eval_cp"] = float(tokens[i + 1]) / 100.0
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
