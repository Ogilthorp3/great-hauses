# DS4-ORACLE opponent (`src/ai/`)

`ds4_opponent.gd` (`Ds4Opponent`, extends **Node**) — a MAX-THINKING LLM
opponent that speaks to an OpenAI-compatible endpoint (DeepSeek-V4-Flash
through the SSH tunnel to the MBP, default `http://127.0.0.1:18000`).
Prompt / parse / retry design ported from the proven
`~/Projects/godot-lab/ds4-chess-bridge/ds4_chess_bot.py`.

`uci_engine.gd` (`UciEngine`, extends **Node**) — minimal async UCI client
for Stockfish (`OS.execute_with_pipe` + reader thread). Autodetects the
binary (`which stockfish`, Homebrew fallbacks), supports `depth`/`movetime`/
`MultiPV`/`searchmoves`, and shuts the process down on tree exit (quit →
grace → kill) so it never orphans an engine.

## Oracle modes (`mode`)

| Mode | Behavior |
|------|----------|
| `pure` | historic behavior — the LLM alone, MAX thinking |
| `counseled` | LLM proposes; Stockfish (depth 12) reviews vs its own best. A proposal losing > 150 cp draws a reconsideration prompt (≤ 2); exhausted counsel plays Stockfish's 3rd-ranked move via `oracle_stumbled` with the softer `HEEDS_TEXT` ("The Oracle heeds counsel") |
| `maester` | Stockfish MultiPV 4 (depth 14) builds candidates + evals + one-line summaries; the LLM picks one and narrates via `oracle_reason(text)` (≤ 100 chars). Unreachable LLM (90 s) → engine top move, reason "The Maester moves for the sleeping Oracle." Always strong |

Stockfish missing → `counseled` degrades to `pure` (logged); the UI greys the
maester entry out (`HouseSelect.set_oracle_mode_enabled`).

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
| MAX THINKING | `temperature 0.3`, system prompt demands step-by-step candidate analysis then a final `MOVE: <uci>` line |
| adaptive tokens | `max_tokens` scales with branching: ≤ 5 legal moves → 512, ≤ 15 → 1024, else 3072; corrective retries escalate one tier; maester pick 300; counseled reconsiderations 768 |
| forced moves | exactly 1 legal move → played instantly, no LLM call, HUD caption "The Oracle need not ponder." |
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
| `oracle_stumbled(reason)` | show `STUMBLE_TEXT` — a random move was played; when the reason contains `HEEDS_TEXT` show that softer line instead (counseled save — a strong engine move) |
| `oracle_reason(text)` | maester: caption the Oracle's in-character reason under the move list (~6 s) |

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
