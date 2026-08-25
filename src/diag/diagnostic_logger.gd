class_name DiagnosticLogger
extends Node
## Comprehensive System, Graphics, Engine & Runtime Diagnostic Logger for Great Hauses Chess.
##
## Writes a detailed report to:
##   1. user://greathauses_diagnostic.log (%APPDATA%\Godot\app_userdata\Great Hauses Chess\...)
##   2. [exe_directory]/greathauses_diagnostic.log (if directory is writable)
##
## Features:
##   * Hardware & OS specs (OS version, CPU cores, architecture)
##   * GPU & Vulkan / Direct3D / Metal adapter info & API version
##   * Active rendering method (Forward+ Clustered vs Mobile)
##   * Multiview stereo / XR shader status
##   * Display metrics (Window mode, resolution, DPI, monitor count)
##   * Stockfish & Leela Chess Zero (Lc0) binary verification
##   * F2 / Ctrl+L global shortcut to copy log & open log directory
##   * Runtime event, warning, and error logging

const LOG_USER_PATH := "user://greathauses_diagnostic.log"
const APP_VERSION := "0.3.5"

static var instance: DiagnosticLogger = null

var _log_buffer: Array[String] = []
var _log_file_user: FileAccess = null
var _log_file_local: FileAccess = null
var _local_path := ""


func _init() -> void:
	instance = self


func _ready() -> void:
	_init_log_files()
	_generate_system_report()
	print("[DIAGNOSTIC] Logger initialized. Press F2 or Ctrl+L anytime to open log folder or copy to clipboard.")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F2 or ((event.ctrl_pressed or event.meta_pressed) and event.keycode == KEY_L):
			open_log_folder()
			copy_log_to_clipboard()
			get_viewport().set_input_as_handled()


func _init_log_files() -> void:
	# 1. user:// path (always writable)
	_log_file_user = FileAccess.open(LOG_USER_PATH, FileAccess.WRITE)
	
	# 2. Local directory next to the executable (Windows convenient)
	var exe_dir := OS.get_executable_path().get_base_dir()
	if not exe_dir.is_empty():
		_local_path = exe_dir.path_join("greathauses_diagnostic.log")
		_log_file_local = FileAccess.open(_local_path, FileAccess.WRITE)


func _write_line(line: String) -> void:
	_log_buffer.append(line)
	if _log_file_user != null:
		_log_file_user.store_line(line)
		_log_file_user.flush()
	if _log_file_local != null:
		_log_file_local.store_line(line)
		_log_file_local.flush()


func log_event(category: String, message: String) -> void:
	var timestamp := Time.get_time_string_from_system()
	var line := "[%s] [%s] %s" % [timestamp, category, message]
	_write_line(line)
	print(line)


func log_warn(category: String, message: String) -> void:
	var timestamp := Time.get_time_string_from_system()
	var line := "[%s] [WARN:%s] %s" % [timestamp, category, message]
	_write_line(line)
	push_warning(line)


func log_err(category: String, message: String) -> void:
	var timestamp := Time.get_time_string_from_system()
	var line := "[%s] [ERROR:%s] %s" % [timestamp, category, message]
	_write_line(line)
	push_error(line)


func _generate_system_report() -> void:
	_write_line("================================================================================")
	_write_line("               GREAT HAUSES CHESS — SYSTEM & DIAGNOSTIC REPORT                  ")
	_write_line("================================================================================")
	_write_line("App Name               : %s" % ProjectSettings.get_setting("application/config/name", "Great Hauses Chess"))
	_write_line("App Version            : %s" % APP_VERSION)
	_write_line("Timestamp              : %s" % Time.get_datetime_string_from_system(false, true))
	_write_line("Engine Version         : %s" % Engine.get_version_info().get("string", "Unknown"))
	_write_line("Godot Architecture     : %s" % Engine.get_architecture_name())
	_write_line("--------------------------------------------------------------------------------")
	_write_line("OPERATING SYSTEM & HARDWARE:")
	_write_line("OS Name                : %s" % OS.get_name())
	_write_line("OS Version / Build     : %s" % OS.get_version())
	_write_line("OS Distribution        : %s" % OS.get_distribution_name())
	_write_line("OS Locale              : %s" % OS.get_locale())
	_write_line("CPU Processor Count    : %d logical cores" % OS.get_processor_count())
	_write_line("Executable Path        : %s" % OS.get_executable_path())
	_write_line("User Data Directory    : %s" % OS.get_user_data_dir())
	_write_line("Command Line Args      : %s" % str(OS.get_cmdline_args()))
	_write_line("User Cmdline Args      : %s" % str(OS.get_cmdline_user_args()))
	_write_line("--------------------------------------------------------------------------------")
	_write_line("GRAPHICS & RENDERING PIPELINE:")
	_write_line("Video Adapter Name     : %s" % RenderingServer.get_video_adapter_name())
	_write_line("Video Adapter API      : %s" % RenderingServer.get_video_adapter_api_version())
	_write_line("Video Adapter Type     : %s" % _get_adapter_type_string(RenderingServer.get_video_adapter_type()))
	_write_line("Configured Renderer    : %s" % str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "default")))
	_write_line("Windows Override       : %s" % str(ProjectSettings.get_setting("rendering/renderer/rendering_method.windows", "none")))
	_write_line("macOS Override         : %s" % str(ProjectSettings.get_setting("rendering/renderer/rendering_method.macos", "none")))
	_write_line("XR Multiview Shaders   : %s" % str(ProjectSettings.get_setting("xr/shaders/enabled", false)))
	_write_line("XR Shaders (Windows)   : %s" % str(ProjectSettings.get_setting("xr/shaders/enabled.windows", "default")))
	_write_line("XR Shaders (macOS)     : %s" % str(ProjectSettings.get_setting("xr/shaders/enabled.macos", "default")))
	_write_line("3D MSAA Setting        : %s" % str(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d", "0")))
	_write_line("Screen Space AA        : %s" % str(ProjectSettings.get_setting("rendering/anti_aliasing/quality/screen_space_aa", "0")))
	_write_line("VRAM Compression S3TC  : %s" % str(ProjectSettings.get_setting("rendering/textures/vram_compression/import_s3tc_bptc", false)))
	_write_line("VRAM Compression ETC2  : %s" % str(ProjectSettings.get_setting("rendering/textures/vram_compression/import_etc2_astc", false)))
	_write_line("--------------------------------------------------------------------------------")
	_write_line("DISPLAY & WINDOW METRICS:")
	_write_line("Display Driver Name    : %s" % DisplayServer.get_name())
	_write_line("Screen Count           : %d" % DisplayServer.get_screen_count())
	var primary_screen := DisplayServer.get_primary_screen()
	_write_line("Primary Screen ID      : %d" % primary_screen)
	_write_line("Screen Resolution      : %s" % str(DisplayServer.screen_get_size(primary_screen)))
	_write_line("Screen Refresh Rate    : %.1f Hz" % DisplayServer.screen_get_refresh_rate(primary_screen))
	_write_line("Screen Scale Factor    : %.2f" % DisplayServer.screen_get_scale(primary_screen))
	_write_line("Window Mode            : %s" % _get_window_mode_string(DisplayServer.window_get_mode()))
	_write_line("Window Size            : %s" % str(DisplayServer.window_get_size()))
	_write_line("--------------------------------------------------------------------------------")
	_write_line("CHESS ENGINES & SUBSYSTEMS:")
	_check_chess_engines()
	_write_line("================================================================================")
	_write_line("RUNTIME LOG EVENTS:")
	_write_line("--------------------------------------------------------------------------------")


func _check_chess_engines() -> void:
	var base_dir := OS.get_executable_path().get_base_dir()
	
	# Stockfish Check
	var sf_candidates := [
		base_dir.path_join("stockfish.exe"),
		base_dir.path_join("stockfish"),
		base_dir.path_join("Contents/MacOS/stockfish"),
		ProjectSettings.globalize_path("res://tools/engines/windows/stockfish.exe"),
		ProjectSettings.globalize_path("res://tools/engines/macos/stockfish"),
	]
	var sf_found := ""
	for path in sf_candidates:
		if FileAccess.file_exists(path):
			sf_found = path
			break
	if not sf_found.is_empty():
		var fa := FileAccess.open(sf_found, FileAccess.READ)
		var sz := fa.get_length() if fa != null else 0
		_write_line("Stockfish 18 Binary    : FOUND -> %s (%d bytes)" % [sf_found, sz])
	else:
		_write_line("Stockfish 18 Binary    : NOT FOUND (Checked: %s)" % str(sf_candidates))
	
	# Leela Lc0 Check
	var lc0_candidates := [
		base_dir.path_join("lc0/lc0.exe"),
		base_dir.path_join("lc0.exe"),
		base_dir.path_join("lc0/lc0"),
		base_dir.path_join("Contents/MacOS/lc0/lc0"),
		ProjectSettings.globalize_path("res://tools/engines/windows/lc0/lc0.exe"),
		ProjectSettings.globalize_path("res://tools/engines/macos/lc0/lc0"),
	]
	var lc0_found := ""
	for path in lc0_candidates:
		if FileAccess.file_exists(path):
			lc0_found = path
			break
	if not lc0_found.is_empty():
		var fa := FileAccess.open(lc0_found, FileAccess.READ)
		var sz := fa.get_length() if fa != null else 0
		_write_line("Leela Lc0 Binary       : FOUND -> %s (%d bytes)" % [lc0_found, sz])
		
		# Check weights
		var weights_dir := lc0_found.get_base_dir()
		var weights_candidates := [
			weights_dir.path_join("791556.pb.gz"),
			weights_dir.path_join("42850.pb.gz"),
		]
		var w_found := ""
		for wp in weights_candidates:
			if FileAccess.file_exists(wp):
				w_found = wp
				break
		if not w_found.is_empty():
			_write_line("  Lc0 Neural Network   : FOUND -> %s" % w_found)
		else:
			_write_line("  Lc0 Neural Network   : NOT FOUND in %s" % weights_dir)
	else:
		_write_line("Leela Lc0 Binary       : NOT FOUND (Checked: %s)" % str(lc0_candidates))


func _get_adapter_type_string(t: int) -> String:
	match t:
		1: return "Discrete GPU"
		0: return "Integrated GPU"
		2: return "Virtual GPU"
		3: return "Software / CPU"
		4: return "Other"
		_: return "Type %d" % t


func _get_window_mode_string(m: int) -> String:
	match m:
		DisplayServer.WINDOW_MODE_WINDOWED: return "Windowed"
		DisplayServer.WINDOW_MODE_MINIMIZED: return "Minimized"
		DisplayServer.WINDOW_MODE_MAXIMIZED: return "Maximized"
		DisplayServer.WINDOW_MODE_FULLSCREEN: return "Fullscreen"
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN: return "Exclusive Fullscreen"
		_: return "Mode %d" % m


func get_log_text() -> String:
	return "\n".join(_log_buffer)


func copy_log_to_clipboard() -> void:
	var txt := get_log_text()
	DisplayServer.clipboard_set(txt)
	log_event("DIAGNOSTIC", "Diagnostic report copied to system clipboard (%d characters)." % txt.length())


func open_log_folder() -> void:
	var user_dir := OS.get_user_data_dir()
	log_event("DIAGNOSTIC", "Opening log directory: %s" % user_dir)
	OS.shell_open(ProjectSettings.globalize_path(user_dir))
