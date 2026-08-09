# Great Hauses Chess Engine (`src/chess/`)

Standalone, headless-testable chess rules engine + AI in pure GDScript (Godot 4.x).
No scene, node, or UI dependencies — `RefCounted` all the way down, safe to use from
any presentation layer (2D, 3D, server-side) or from worker threads.

## Attribution

The rules engine and negamax AI are ported from
[**Stop Waiting For Godot** by Terry Hearst (thearst3rd)](https://github.com/thearst3rd/stopwaitingforgodot),
MIT License — see [`LICENSE-stopwaitingforgodot`](./LICENSE-stopwaitingforgodot).
The port keeps the proven engine logic verbatim; Great Hauses additions are limited to
API aliases, presentation metadata on moves, UCI helpers, difficulty tiers, and the
`WorkerThreadPool`-based async search.

## Files

| File | Class | Role |
|------|-------|------|
| `ChessState.gd` | `ChessState` | Board state, FEN in/out, legal move generation, game-end + draw rules, SAN |
| `ChessMove.gd` | `ChessMove` | Move object: everything needed to play/undo + animate a move |
| `ChessAI.gd` | `ChessAI` | Negamax + alpha-beta + quiescence AI with 3 difficulty tiers, async via `WorkerThreadPool` |

## ChessState

A new `ChessState.new()` starts at the standard initial position.

```gdscript
var state := ChessState.new()

# FEN in/out
state.set_fen("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1") # -> bool (false = rejected, state unchanged)
state.get_fen()          # -> String

# Moves
var moves := state.legal_moves()        # -> Array[ChessMove], fast (no SAN)
var moves2 := state.legal_moves(true)   # same, with .notation_san populated (slower)
var m = state.move_from_uci("e2e4")     # -> ChessMove or null if illegal
state.apply_move(m)                     # play it (alias of play_move)
state.undo()                            # take back the last applied move

# Status
state.turn               # false = white to move, true = black
state.in_check()         # -> bool
state.is_game_over()     # -> bool
state.get_result()       # -> ChessState.RESULT
```

`RESULT` enum: `ONGOING`, `CHECKMATE`, `STALEMATE`, `INSUFFICIENT` (material),
`FIFTY_MOVE`, `THREEFOLD` (+ reserved `SEVENTY_FIVE_MOVE` / `FIVEFOLD`, unused).
`CHECKMATE`/`STALEMATE` mean the side **to move** has no legal moves.

Board layout: `pieces` is a 64-slot array of piece chars (`"K"`, `"q"`, ...) or `null`;
index 0 = a8, 63 = h1 (see the `SQUARES` enum). Uppercase = white, lowercase = black.
Static helpers: `square_index(file, rank)`, `square_get_file/rank/name(idx)`,
`square_index_from_name("e4")`, `piece_color(char)` (false = white).

Note: the en-passant target is pruned — it is only kept (in state and in FEN output)
when a *legal* en-passant capture actually exists. This makes threefold repetition
detection exact.

`duplicate()` returns a deep copy (search/AI works on copies; two states never share
mutable data).

## ChessMove

Returned by `legal_moves()` / `move_from_uci()`. Never construct one by hand — only
moves minted by a `ChessState` are guaranteed applicable/undoable on it.

Engine fields: `from_square`, `to_square`, `promotion` (piece char or `null`),
`captured_piece` (char on `to_square`, `null` for en passant — check `en_passant`),
`en_passant`, `notation_san` (when notated).

Presentation metadata — enough for a 3D layer to animate without knowing the rules:

| Field | Meaning |
|-------|---------|
| `piece` | moving piece char (`"P"`, `"n"`, ...) |
| `is_capture()` | true for any capture, including en passant |
| `captured_square` | where the captured piece actually sits (differs from `to_square` for en passant), `-1` if none |
| `is_castling`, `castle_kingside` | castling and which side |
| `rook_from`, `rook_to` | the rook's path when castling |
| `to_uci()` | long-algebraic string, e.g. `"e2e4"`, `"e7e8q"` |

Typical animation recipe: lift `piece` at `from_square`; if `is_capture()` remove the
piece at `captured_square`; land at `to_square` (swap mesh if `promotion`); if
`is_castling` also slide the rook `rook_from` → `rook_to`.

## ChessAI

```gdscript
var ai := ChessAI.new()

# Async — search runs on WorkerThreadPool against a duplicate of `state`;
# the caller's state is never touched by the worker thread.
var move = await ai.choose_move(state, ChessAI.Difficulty.HARD)   # -> ChessMove (SAN-notated) or null if game over
state.apply_move(move)

# Synchronous variant (blocks the calling thread):
var move2 = ai.choose_move_sync(state, ChessAI.Difficulty.EASY)
```

Difficulty tiers (search depth / quiescence depth): `EASY` 1/2, `MEDIUM` 2/4, `HARD` 3/5.
The engine is negamax with alpha-beta pruning, quiescence search, MVV-LVA-style move
ordering, and the Simplified Evaluation Function piece-square tables.

After a search: `ai.last_score` (positive = good for the side that moved),
`ai.num_positions_searched`, `ai.num_positions_searched_q`, `ai.num_positions_evaluated`,
`ai.search_time` (usec).

`await ai.choose_move(...)` needs a running main loop (it awaits `process_frame` while
polling task completion); in a loop-less context it falls back to short sleeps. Use
`choose_move_sync` if you are already on a background thread.

## Tests

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path <this project> -s res://tests/run_tests.gd
```

79 checks: perft (startpos depths 1-4: 20/400/8902/197281; Kiwipete depths 1-3:
48/2039/97862), castling legality (through/into/while-in-check forbidden, b1-attacked
queenside allowed), en passant incl. the discovered-check pin, promotion +
underpromotion, checkmate vs stalemate, threefold, fifty-move, insufficient material,
FEN round-trips, and an AI mate-in-1 smoke test at every difficulty (< 5 s budget).
Prints a summary table; exit code 0 = all green, 1 = failures.
