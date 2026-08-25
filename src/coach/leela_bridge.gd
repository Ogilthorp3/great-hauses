class_name LeelaBridge
extends RefCounted
## LeelaBridge — Connects Leela Chess Zero (Lc0 / AlphaZero Deep Neural Networks)
## to Great Hauses for intuitive positional strategy, holistic board harmony, and human-playable plans.

const ENV_LC0 := "GREAT_HOUSES_LC0"
const LEELA_PATHS := [
	"/opt/homebrew/bin/lc0",
	"/usr/local/bin/lc0",
	"/usr/bin/lc0"
]

static var _cached_bin_path := ""
static var _checked_bin := false


## The platform's lc0 filename.
static func binary_name() -> String:
	return "lc0.exe" if OS.has_feature("windows") else "lc0"


## Directories searched before PATH, in order.
static func sidecar_dirs() -> Array[String]:
	var exe_dir := OS.get_executable_path().get_base_dir()
	var dirs: Array[String] = [
		exe_dir,
		exe_dir.path_join("lc0")
	]
	if OS.has_feature("macos"):
		var contents_dir := exe_dir.get_base_dir()
		dirs.append(contents_dir.path_join("Resources"))
		dirs.append(contents_dir.path_join("Resources").path_join("lc0"))
		dirs.append(exe_dir.path_join("lc0"))
		var outside := contents_dir.get_base_dir()
		if not outside.is_empty():
			dirs.append(outside)
			dirs.append(outside.path_join("lc0"))
	return dirs


static func _find_weights(lc0_path: String) -> String:
	var base := lc0_path.get_base_dir()
	for fname in ["791556.pb.gz", "42850.pb.gz", "weights.pb.gz", "weights.bin", "weights.onnx"]:
		var w := base.path_join(fname)
		if FileAccess.file_exists(w):
			return w
	if OS.has_feature("macos"):
		var res_dir := lc0_path.get_base_dir().get_base_dir().path_join("Resources")
		for fname in ["791556.pb.gz", "42850.pb.gz", "weights.pb.gz", "weights.bin", "weights.onnx"]:
			var w := res_dir.path_join(fname)
			if FileAccess.file_exists(w):
				return w
	return ""


## Scan the PATH environment variable directly without spawning subprocesses
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


## Find Lc0 binary on the system
static func get_leela_path() -> String:
	if _checked_bin:
		return _cached_bin_path

	_checked_bin = true
	if not platform_can_spawn():
		_cached_bin_path = ""
		return _cached_bin_path

	var override := OS.get_environment(ENV_LC0).strip_edges()
	if not override.is_empty() and FileAccess.file_exists(override):
		_cached_bin_path = override
		return _cached_bin_path

	var bin := binary_name()
	for dir in sidecar_dirs():
		var p := dir.path_join(bin)
		if FileAccess.file_exists(p):
			_cached_bin_path = p
			return _cached_bin_path

	var on_path := search_path_env()
	if not on_path.is_empty():
		_cached_bin_path = on_path
		return _cached_bin_path

	if not OS.has_feature("windows"):
		for p in LEELA_PATHS:
			if FileAccess.file_exists(p):
				_cached_bin_path = p
				return _cached_bin_path

	_cached_bin_path = ""
	return ""


## PLATFORMS THAT CANNOT FORK.
static func platform_can_spawn() -> bool:
	return not (OS.has_feature("ios") or OS.has_feature("web"))


## Check if Leela Lc0 is available
static func is_available() -> bool:
	return not get_leela_path().is_empty()


## Run deep Leela Lc0 Neural Net MCTS analysis on a given FEN position using native Godot pipes
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

	# Execute Leela directly via native OS pipes with weights if found
	var args: Array[String] = []
	var weights := _find_weights(lc0_path)
	if not weights.is_empty():
		args.append("--weights=" + weights)

	var info := OS.execute_with_pipe(lc0_path, args)
	if info.is_empty() or not info.has("stdio"):
		return result

	var pipe: FileAccess = info["stdio"]
	var pid: int = int(info.get("pid", -1))
	if pipe == null or not pipe.is_open():
		return result

	result["available"] = true
	result["engine"] = "Leela Chess Zero (Lc0 AlphaZero)"

	pipe.store_string("uci\nisready\nposition fen %s\ngo nodes %d\n" % [fen, max_nodes])
	pipe.flush()

	var deadline := Time.get_ticks_msec() + 2000
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
