# DS4-ORACLE opponent (`src/ai/`)

`ds4_opponent.gd` (`Ds4Opponent`, extends **Node**) — a MAX-THINKING LLM
opponent that speaks to an OpenAI-compatible endpoint (DeepSeek-V4-Flash
through the SSH tunnel to the MBP, default `http://127.0.0.1:18000`).
Prompt / parse / retry design ported from the proven
`~/Projects/godot-lab/ds4-chess-bridge/ds4_chess_bot.py`.

## Swap surface (ChessAI parity)

```gdscript
var oracle := Ds4Opponent.new()
add_child(oracle)                       # Node, not RefCounted: HTTPRequest needs the tree

var move = await oracle.choose_move(state, difficulty)   # ChessMove (SAN-notated) or null
# difficulty is accepted for drop-in swap with ChessAI and ignored.

oracle.choose_move_async(state, func(move): ...)         # callback style, non-blocking
```

The returned `ChessMove` is minted by `state` (via `legal_moves(true)`), so
`state.apply_move(move)` and the SAN HUD work exactly as with `ChessAI`.

## Config

| Knob | Value |
|------|-------|
| endpoint | `http://127.0.0.1:18000/v1/chat/completions`; env `DS4_CHESS_URL` overrides (base, `/v1`, or full chat URL all accepted); `endpoint_override` property sits between the two |
| model | env `DS4_CHESS_MODEL`, else `deepseek-v4-flash`; `ping()` adopts the endpoint's first served model when ours is unknown |
| MAX THINKING | `temperature 0.3`, `max_tokens 3072`, system prompt demands step-by-step candidate analysis then a final `MOVE: <uci>` line |
| retries | up to 3 corrective retries on illegal/unparseable replies |
| budget | 120 s hard wall-clock per move, then fallback |

Fallback = **random legal move**, flagged via `oracle_stumbled(reason)` —
the HUD must show `Ds4Opponent.STUMBLE_TEXT` ("The Oracle stumbles").

## Signals

| Signal | HUD duty |
|--------|----------|
| `thinking_started` | show `THINKING_TEXT` ("The Oracle ponders…") shimmer + start elapsed counter |
| `thinking_finished(elapsed_s)` | stop shimmer/counter |
| `retry_attempted(attempt)` | optional: "the Oracle reconsiders…" |
| `oracle_stumbled(reason)` | show `STUMBLE_TEXT` — a random move was played |

## Preflight

```gdscript
if await oracle.ping(5.0):   # GET /v1/models
    # enable the DS4-Oracle entry
else:
    # grey it out with oracle.offline_reason  ("the Oracle sleeps (tunnel down?) — …")
```

## Test

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path <project> -s res://tests/test_ds4_opponent.gd
```

Green offline: when the real endpoint doesn't answer `ping()` within 5 s the
suite runs against a built-in canned HTTP server (TCPServer) covering ping,
clean move, corrective retry, fallback + `oracle_stumbled`, and the
"Oracle sleeps" path. When the tunnel is up it *additionally* plays one live
move from the starting position and asserts it legal.
