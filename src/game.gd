extends Node3D
## Great Houses — game root (scaffold).
## Spawns the classic starting lineup with placeholder pieces and wires
## click-to-select / click-to-move. NO chess rules yet: any square goes and
## the "legal move" markers just show the adjacent ring to exercise the
## board API. Real rules + combat choreography come later.
##
## E2E hooks (after "--" on the command line):
##   --smoke      windowed: wait 3 s, save a screenshot (GH_SMOKE_OUT or
##                user://smoke.png), quit with 0/1.
##   --dump-tree  headless-safe: print the scene tree and quit.

const PieceScene: PackedScene = preload("res://scenes/piece_view.tscn")

const BACK_RANK: Array[PieceView.Type] = [
	PieceView.Type.ROOK, PieceView.Type.KNIGHT, PieceView.Type.BISHOP,
	PieceView.Type.QUEEN, PieceView.Type.KING,
	PieceView.Type.BISHOP, PieceView.Type.KNIGHT, PieceView.Type.ROOK,
]

@onready var board: BoardView = $Board

var _pieces: Dictionary = {}   # Vector2i -> PieceView
var _selected: Variant = null  # Vector2i, or null when nothing selected
var _busy := false             # a move/capture animation is running


func _ready() -> void:
	_spawn_lineup()
	board.square_clicked.connect(_on_square_clicked)
	var args := OS.get_cmdline_user_args()
	if args.has("--smoke"):
		_smoke()
	elif args.has("--dump-tree"):
		_dump_tree()


# -- setup -----------------------------------------------------------------


func _spawn_lineup() -> void:
	for file in 8:
		_spawn(BACK_RANK[file], PieceView.House.FROST, Vector2i(file, 0))
		_spawn(PieceView.Type.PAWN, PieceView.House.FROST, Vector2i(file, 1))
		_spawn(PieceView.Type.PAWN, PieceView.House.EMBER, Vector2i(file, 6))
		_spawn(BACK_RANK[file], PieceView.House.EMBER, Vector2i(file, 7))


func _spawn(piece_type: PieceView.Type, piece_side: PieceView.House, sq: Vector2i) -> void:
	var p: PieceView = PieceScene.instantiate()
	add_child(p)
	p.setup(piece_type, piece_side)
	p.position = board.square_to_world(sq)
	if piece_side == PieceView.House.EMBER:
		p.rotation.y = PI  # face the enemy
	_pieces[sq] = p


# -- interaction (scaffold rules: everything is legal) ---------------------


func _on_square_clicked(sq: Vector2i) -> void:
	if _busy:
		return
	if _selected == null:
		if _pieces.has(sq):
			_select(sq)
		return
	var from_sq: Vector2i = _selected
	if sq == from_sq:
		_clear_selection()
		return
	var mover: PieceView = _pieces[from_sq]
	if _pieces.has(sq) and (_pieces[sq] as PieceView).side == mover.side:
		_select(sq)
		return
	_move(from_sq, sq)


func _select(sq: Vector2i) -> void:
	_selected = sq
	board.set_selected(sq)
	board.show_legal_moves(_placeholder_moves(sq))


func _clear_selection() -> void:
	_selected = null
	board.clear_highlights()


func _placeholder_moves(sq: Vector2i) -> Array[Vector2i]:
	## Scaffold only: the adjacent ring, minus friendly-occupied squares.
	## Replaced by the real move generator later.
	var piece_side: PieceView.House = (_pieces[sq] as PieceView).side
	var out: Array[Vector2i] = []
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var n: Vector2i = sq + Vector2i(dx, dy)
			if not board.is_on_board(n):
				continue
			if _pieces.has(n) and (_pieces[n] as PieceView).side == piece_side:
				continue
			out.append(n)
	return out


func _move(from_sq: Vector2i, to_sq: Vector2i) -> void:
	_busy = true
	var mover: PieceView = _pieces[from_sq]
	var victim: PieceView = _pieces.get(to_sq)
	_pieces.erase(from_sq)
	_clear_selection()
	var target := board.square_to_world(to_sq)
	if victim != null:
		_pieces.erase(to_sq)
		var dir := (target - mover.position).normalized()
		await mover.move_to(target - dir * 0.55, 0.35)
		await mover.play_capture(victim)
	await mover.move_to(target, 0.3)
	_pieces[to_sq] = mover
	_busy = false


# -- e2e hooks -------------------------------------------------------------


func _smoke() -> void:
	await get_tree().create_timer(3.0).timeout
	var img := get_viewport().get_texture().get_image()
	var out := OS.get_environment("GH_SMOKE_OUT")
	if out.is_empty():
		out = "user://smoke.png"
	var err := img.save_png(out)
	print("SMOKE_SAVED path=%s err=%d size=%dx%d" % [out, err, img.get_width(), img.get_height()])
	get_tree().quit(0 if err == OK else 1)


func _dump_tree() -> void:
	await get_tree().process_frame
	print_tree_pretty()
	print("TREE_PIECES=%d" % _pieces.size())
	get_tree().quit()
