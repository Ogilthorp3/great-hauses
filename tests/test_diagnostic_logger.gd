extends SceneTree

func _initialize() -> void:
	_run()

func _run() -> void:
	print("Testing DiagnosticLogger...")
	var script: GDScript = load("res://src/diag/diagnostic_logger.gd")
	var diag = script.new()
	root.add_child(diag)
	await process_frame
	
	diag.log_event("TEST", "Sample event log message")
	diag.log_warn("TEST", "Sample warning log message")
	diag.log_err("TEST", "Sample error log message")
	
	var text: String = diag.get_log_text()
	print("\n=== GENERATED DIAGNOSTIC REPORT ===\n")
	print(text)
	print("\n===================================\n")
	
	assert(text.contains("GREAT HAUSES CHESS — SYSTEM & DIAGNOSTIC REPORT"), "Header missing")
	assert(text.contains("OPERATING SYSTEM & HARDWARE"), "OS section missing")
	assert(text.contains("GRAPHICS & RENDERING PIPELINE"), "Graphics section missing")
	assert(text.contains("CHESS ENGINES & SUBSYSTEMS"), "Engines section missing")
	assert(FileAccess.file_exists("user://greathauses_diagnostic.log"), "Log file not created")
	
	print("ALL DIAGNOSTIC LOGGER ASSERTIONS PASSED GREEN!")
	quit(0)
