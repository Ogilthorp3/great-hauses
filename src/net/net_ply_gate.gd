class_name NetPlyGate
extends RefCounted
## The cinematic barrier: turn flow may not advance while one player is still
## watching a duel.
##
## A capture in Great Hauses is not an instant — it is a several-second
## slow-motion duel with a camera swoop and a kill line. Both players must see
## it. Without a barrier the fast machine finishes its animation, its player
## clicks the next move, the host validates it (the ENGINE is already ahead of
## the ANIMATION) and broadcasts — and the slow machine's screen jumps out of
## the duel mid-swing. So after every ply BOTH sides ack "I have finished
## watching", and only then does the host open the gate for the next request.
##
## Pure logic, zero networking — `net_match.gd` supplies the acks and the
## clock, `tests/test_net.gd` proves the rules:
##   * one ack alone never opens the gate,
##   * both acks open it exactly once,
##   * an ack for a stale ply is ignored (the late-packet guard),
##   * a peer that never acks can DELAY the gate, never wedge it forever.

const ROLE_HOST := "host"
const ROLE_JOIN := "join"

var seq := -1                  ## the ply this gate is holding
var opened := false            ## the gate for `seq` has opened
var forced := false            ## it opened on the timeout, not on both acks
var opened_at_ms := 0

var _acks := {}                ## role -> true
var _armed_ms := 0


## Start holding the gate for ply `s`. Any earlier ply's acks are discarded —
## they belong to a position that no longer exists.
func begin(s: int, now_ms: int = 0) -> void:
	seq = s
	opened = false
	forced = false
	opened_at_ms = 0
	_acks = {}
	_armed_ms = now_ms


## Record one side finishing its local animation. Returns true only on the
## transition that OPENS the gate, so the caller can broadcast exactly once.
func ack(s: int, role: String, now_ms: int = 0) -> bool:
	if s != seq or opened:
		return false            # stale packet for a dead position — dropped
	if role != ROLE_HOST and role != ROLE_JOIN:
		return false
	_acks[role] = true
	if _acks.has(ROLE_HOST) and _acks.has(ROLE_JOIN):
		opened = true
		opened_at_ms = now_ms
		return true
	return false


## Has `role` acked the ply currently being held?
func has_ack(role: String) -> bool:
	return bool(_acks.get(role, false))


func acks_in() -> int:
	return _acks.size()


func is_open_for(s: int) -> bool:
	return opened and s == seq


## The failsafe. A peer that hung mid-cinematic must not freeze the match
## forever, so after `timeout_sec` the gate opens anyway and records that it
## was FORCED (the caller warns; the players see a note, not a hang).
## Returns true only on the transition.
func tick(now_ms: int, timeout_sec: float) -> bool:
	if opened or seq < 0 or _armed_ms <= 0:
		return false
	if float(now_ms - _armed_ms) < timeout_sec * 1000.0:
		return false
	opened = true
	forced = true
	opened_at_ms = now_ms
	return true


## Gate open (or nothing being held) => the host may accept the next request.
func accepting() -> bool:
	return seq < 0 or opened
