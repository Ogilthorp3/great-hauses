extends SceneTree
## Headless suite for TOUCH ON THE BOARD (2026-08-18).
##
## Albert, after the first TestFlight build: the camera could not be rotated on
## the iPad. The fix gives two fingers the camera — and immediately creates a
## worse hazard than the one it cures, because `emulate_mouse_from_touch` turns
## the FIRST finger into a left click and the board used to act on PRESS. So
## the act of putting two fingers down to look around could select a piece, or
## on a legal destination square, COMMIT A MOVE. Losing a game to a camera
## gesture is not an acceptable price for a camera gesture.
##
## Contract under test:
##  * one finger, pressed and lifted in the same place, plays a square;
##  * a second finger cancels the tap outright — that is a camera gesture;
##  * a finger that travels does not play (it was aiming, not tapping);
##  * the mouse still plays on press, so the desktop game is untouched;
##  * the emulated mouse echo that FOLLOWS a real touch is ignored, or every
##    tap would count twice.
## Run: godot --headless --path <project> -s res://tests/test_touch_input.gd

var passed := 0
var failed := 0
var _clicks := 0

const MIN_EXPECTED_CHECKS := 7


func _initialize() -> void:
	_main()


func _main() -> void:
	print("\n=== Great Hauses Chess — Board Touch Suite ===")
	var board := BoardView.new()
	get_root().add_child(board)
	# A lens straight over the middle of the board, so a tap at the centre of
	# the screen lands on a real square and `pick_square` has something to hit.
	var cam := Camera3D.new()
	get_root().add_child(cam)
	# A gameplay-like angle, NOT straight down: a top-down lens with a
	# degenerate up vector produces a skewed basis and every pick misses.
	cam.position = Vector3(0.0, 8.0, 8.0)
	cam.look_at(Vector3(0.0, BoardView.TILE_HEIGHT, 0.0), Vector3.UP)
	cam.current = true
	await process_frame
	await process_frame
	board.square_clicked.connect(func(_sq): _clicks += 1)
	# Aim at a KNOWN square by projecting it back to the screen, rather than
	# assuming where the middle of the screen is: headless reports one
	# viewport size and projects against another, and a guessed centre lands
	# off the board.
	var mid: Vector2 = cam.unproject_position(board.square_to_world(Vector2i(4, 4)))
	check("probe: the lens is actually on the board", true, board.pick_square(mid) != null)

	# 1. THE TAP: down and up in the same place.
	_clicks = 0
	board._unhandled_input(_touch(0, mid, true))
	board._unhandled_input(_touch(0, mid, false))
	check("one finger tapped: plays exactly one square", 1, _clicks)

	# 2. THE CAMERA GESTURE: a second finger joins before either lifts.
	_clicks = 0
	board._unhandled_input(_touch(0, mid, true))
	board._unhandled_input(_touch(1, mid + Vector2(90, 0), true))
	board._unhandled_input(_touch(0, mid, false))
	board._unhandled_input(_touch(1, mid + Vector2(90, 0), false))
	check("two fingers: the board does NOT play", 0, _clicks)

	# 3. A FINGER THAT TRAVELS is aiming something, not tapping.
	_clicks = 0
	board._unhandled_input(_touch(0, mid, true))
	board._unhandled_input(_drag(0, mid + Vector2(60, 40)))
	board._unhandled_input(_touch(0, mid + Vector2(60, 40), false))
	check("a dragged finger does NOT play", 0, _clicks)

	# 4. …but a finger that wanders a pixel or two still counts.
	_clicks = 0
	board._unhandled_input(_touch(0, mid, true))
	board._unhandled_input(_drag(0, mid + Vector2(4, 3)))
	board._unhandled_input(_touch(0, mid + Vector2(4, 3), false))
	check("a steady-enough finger still plays", 1, _clicks)

	# 5. THE EMULATED ECHO: iOS sends this right after the real touch.
	_clicks = 0
	board._unhandled_input(_touch(0, mid, true))
	board._unhandled_input(_touch(0, mid, false))
	board._unhandled_input(_click(mid))
	check("the emulated mouse echo is ignored (one tap, one play)", 1, _clicks)

	# 6. THE DESKTOP IS UNTOUCHED: a mouse with no touch behind it still plays.
	await _wait_ms(BoardView.TOUCH_ECHO_MS + 60)
	_clicks = 0
	board._unhandled_input(_click(mid))
	check("mouse alone still plays on press", 1, _clicks)

	print("---")
	if failed == 0:
		print("TOUCH OK — all %d checks passed" % passed)
	else:
		print("TOUCH FAILED — %d check(s) failed" % failed)
	quit(0 if failed == 0 else 1)


func _touch(index: int, pos: Vector2, pressed: bool) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	return e


func _drag(index: int, pos: Vector2) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	return e


func _click(pos: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = pos
	return e


func _wait_ms(ms: int) -> void:
	var until := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < until:
		await process_frame


func check(desc: String, expected, got) -> void:
	if str(expected) == str(got):
		passed += 1
		print("PASS %s (got %s)" % [desc, got])
	else:
		failed += 1
		print("FAIL %s (expected %s, got %s)" % [desc, expected, got])
