extends SceneTree
## Headless unit test suite for DevConsole.

const DevConsoleScript := preload("res://src/ui/dev_console.gd")

var passed := 0
var failed := 0


func _init() -> void:
	print("\n=== Great Hauses Chess — Quake Dev Console Unit Suite ===")
	_test_console_lifecycle()
	_test_command_execution()
	_test_history_and_autocomplete()
	print("---")
	if failed == 0:
		print("DEV CONSOLE OK — all %d checks passed" % passed)
		quit(0)
	else:
		print("DEV CONSOLE FAILED — %d of %d checks failed" % [failed, passed + failed])
		quit(1)


func check(desc: String, expected, got) -> void:
	if expected == got:
		passed += 1
		print("PASS %s (expected %s, got %s)" % [desc, str(expected), str(got)])
	else:
		failed += 1
		print("FAIL %s (expected %s, got %s)" % [desc, str(expected), str(got)])


func _test_console_lifecycle() -> void:
	var console = DevConsoleScript.new()
	root.add_child(console)

	check("console: starts closed", false, console.is_open())
	check("console: panel exists", true, console._panel != null)
	check("console: output box exists", true, console._output_box != null)
	check("console: input line exists", true, console._input_line != null)
	check("console: quick bar exists", true, console._quick_bar != null)

	# Toggle open
	console.toggle_console()
	check("console: toggled open", true, console.is_open())

	# Toggle closed
	console.toggle_console()
	check("console: toggled closed", false, console.is_open())

	console.queue_free()


func _test_command_execution() -> void:
	var console = DevConsoleScript.new()
	root.add_child(console)

	# Test help command
	console._execute_command("help")
	check("cmd: help executed", true, console.log_history.any(func(l): return l.contains("Available Great Hauses Chess Commands")))

	# Test houses list command
	console._execute_command("houses")
	check("cmd: houses roster listed", true, console.log_history.any(func(l): return l.contains("Registered Great Hauses")))

	# Test pieces command
	console._execute_command("pieces")
	check("cmd: pieces listed", true, console.log_history.any(func(l): return l.contains("Piece Models")))

	# Test kills command
	console._execute_command("kills")
	check("cmd: signature kills listed", true, console.log_history.any(func(l): return l.contains("Signature Kill Choreographies")))

	# Test dragon commands
	console._execute_command("dragon wake")
	check("cmd: dragon wake logged", true, console.log_history.any(func(l): return l.contains("Dragon awakens")))

	# Test timescale command
	console._execute_command("timescale 1.5")
	check("cmd: timescale modified", 1.5, Engine.time_scale)
	console._execute_command("timescale 1.0")
	check("cmd: timescale restored", 1.0, Engine.time_scale)

	# Test clear command
	console._execute_command("clear")
	check("cmd: clear emptied box", true, console._output_box.text.is_empty())

	console.queue_free()


func _test_history_and_autocomplete() -> void:
	var console = DevConsoleScript.new()
	root.add_child(console)

	console._on_input_submitted("houses")
	console._on_input_submitted("dragon wake")
	check("history: 2 commands recorded", 2, console._history.size())

	# Test Up arrow recall
	console._history_prev()
	check("history: previous is 'dragon wake'", "dragon wake", console._input_line.text)

	console._history_prev()
	check("history: second previous is 'houses'", "houses", console._input_line.text)

	# Test Tab auto-complete
	console._input_line.text = "holoch"
	console._auto_complete()
	check("autocomplete: holoch -> holochess", "holochess", console._input_line.text)

	console.queue_free()
