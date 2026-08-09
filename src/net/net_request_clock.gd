class_name NetRequestClock
extends RefCounted
## The move-request deadline — the answer to "what if the host never answers?"
##
## THE BUG THIS EXISTS FOR (verifier defect P1, 2026-08-09). A joiner's click is
## a REQUEST: `game.gd::_play_turn` sets `busy = true`, hands the move to
## `NetMatch.request_move`, and returns. `busy` was cleared by exactly two
## events — `move_applied` or `move_rejected` — both of which come FROM THE
## HOST. If the host never answered (packet lost, host wedged, host mid-crash)
## the joiner sat with `busy = true` forever: board frozen, no message, no way
## out. A dropped UDP datagram is not an exotic failure; it is Tuesday.
##
## So a request is now on a clock, and the clock has two hands:
##
##   SLOW    (`REQUEST_SLOW_SEC`)     say something. The board stays held —
##                                    the move may still land — but the player
##                                    is told the answer is late instead of
##                                    watching a dead screen.
##   STALLED (`REQUEST_TIMEOUT_SEC`)  give the board back and offer the way out
##                                    (keep waiting, or return to the Hall of
##                                    Banners). The request is NOT re-sent: the
##                                    host may yet apply it, and the seq guard
##                                    in net_match.gd drops it if it does not.
##
## Pure logic, zero networking, same shape as net_ply_gate.gd — `net_match.gd`
## supplies the clock and the transitions, `tests/test_net.gd` proves the rules:
## nothing fires early, each hand fires exactly once, an answer at any point
## disarms it, and a re-armed clock starts clean.

const PHASE_IDLE := 0      ## nothing outstanding
const PHASE_SENT := 1      ## a request is on the wire, inside its budget
const PHASE_SLOW := 2      ## late — the player has been told
const PHASE_STALLED := 3   ## given up on: board handed back, way out offered
const NO_CHANGE := -1      ## `tick` did not cross a threshold this frame

var seq := -1              ## the ply the outstanding request was written for
var phase := PHASE_IDLE
var armed_ms := 0


## A request for ply `s` just went on the wire.
func arm(s: int, now_ms: int) -> void:
	seq = s
	phase = PHASE_SENT
	armed_ms = now_ms


## The host answered (applied OR rejected), or the match ended. Returns true
## when this call actually disarmed something, so the caller can announce a
## recovery exactly once — and only if it had announced a problem first.
func clear() -> bool:
	var was_waiting := phase != PHASE_IDLE
	seq = -1
	phase = PHASE_IDLE
	armed_ms = 0
	return was_waiting


## True while the host owes us an answer.
func waiting() -> bool:
	return phase != PHASE_IDLE


## True once the request has been given up on (the board is handed back).
func stalled() -> bool:
	return phase == PHASE_STALLED


## Advance the clock. Returns the phase it TRANSITIONED INTO (PHASE_SLOW /
## PHASE_STALLED) so the caller emits exactly one signal per threshold, or
## NO_CHANGE. Both thresholds are measured from `arm`, never from each other,
## so a paused process loop cannot skip a hand: a single late tick that crosses
## both reports STALLED (the state that matters) and never fires SLOW after it.
func tick(now_ms: int, slow_sec: float, stall_sec: float) -> int:
	if phase == PHASE_IDLE or phase == PHASE_STALLED:
		return NO_CHANGE
	var waited := float(now_ms - armed_ms)
	if waited >= stall_sec * 1000.0:
		phase = PHASE_STALLED
		return PHASE_STALLED
	if phase == PHASE_SENT and waited >= slow_sec * 1000.0:
		phase = PHASE_SLOW
		return PHASE_SLOW
	return NO_CHANGE
