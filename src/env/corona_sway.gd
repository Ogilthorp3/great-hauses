class_name CoronaSway
extends Node
## The chandeliers hang, therefore they move.
##
## Bert, 2026-08-18: "when the dragon enter the cathedral, he hits the first
## chandelier, that's ok, but that chandelier should wobble to show it's
## realistic." He is right, and the better answer than dodging the fixture is
## to let the fixture answer back — a chandelier that takes a dragon's
## wingtip without so much as a tremor is the tell that none of this is real.
##
## The nave coronas are exported from build_sanctum_cathedral.py as their own
## nodes (`Corona_0..2`), each parented to an Empty AT ITS SUSPENSION POINT,
## so rotating that node swings the whole fixture about the place it hangs
## from — which is what a pendulum does, and what rotating a mesh about its
## own middle does not.
##
## Two motions, summed:
##   THE DRAUGHT — every corona always breathes a little. Amplitude under a
##     degree, periods deliberately incommensurate (and phase-offset per
##     fixture) so a row of them never ticks in unison, which is the thing
##     that reads as a machine.
##   THE STRIKE — `strike()` kicks one into a real swing: a damped pendulum
##     about the horizontal axis perpendicular to the blow, so it swings the
##     way it was hit. Period comes from the pendulum's own length (the drop
##     from the pivot to the ring), because a long chain swings slowly and a
##     short one does not, and getting that wrong is instantly legible.
##
## Costs nothing but a rotation per fixture per frame; no physics server, no
## collision, no new lights.

const SETTLE := 0.55            ## damping: how fast a struck corona calms
const STRIKE_MAX := 0.30        ## radians (~17 deg) — a wingtip, not a wrecking ball
const DRAUGHT_AMP := 0.013      ## radians (~0.75 deg) of idle breath
const G := 9.81


class Fixture:
	extends RefCounted
	var node: Node3D
	var rest: Basis
	var drop := 3.0              ## pivot to the ring: sets the swing period
	var phase := 0.0
	var amp := 0.0               ## current strike amplitude, radians
	var axis := Vector3.RIGHT    ## the horizontal axis it is swinging about
	var t := 0.0

	func period() -> float:
		# T = 2*pi*sqrt(L/g), the only number that makes a swing look its size
		return TAU * sqrt(maxf(drop, 0.2) / G)


var _fixtures: Array[Fixture] = []
var _elapsed := 0.0


## Adopt every `Corona_*` under `root`. Safe to call on a tree that has none.
func adopt(root: Node) -> int:
	if root == null:
		return 0
	for n: Node3D in root.find_children("Corona_*", "Node3D", true, false):
		# only the exported pivots, not their mesh children
		if not (n.get_parent() is Node3D) or n.name.begins_with("cathedral_"):
			continue
		var f := Fixture.new()
		f.node = n
		f.rest = n.transform.basis
		# the drop is the pivot down to the lowest mesh the fixture owns
		var lowest := 0.0
		for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh != null:
				lowest = minf(lowest, (mi.transform * mi.mesh.get_aabb()).position.y)
		f.drop = maxf(-lowest, 1.0)
		f.phase = float(_fixtures.size()) * 1.9
		_fixtures.append(f)
	set_process(not _fixtures.is_empty())
	return _fixtures.size()


func count() -> int:
	return _fixtures.size()


## World position of fixture `i`'s pivot — what a flier tests its distance
## against.
func pivot(i: int) -> Vector3:
	if i < 0 or i >= _fixtures.size():
		return Vector3.INF
	return _fixtures[i].node.global_position


## Strike fixture `i` with a blow travelling along `dir` (world space).
## `power` 0..1 scales the swing. Idempotent-ish: a second blow adds to the
## first rather than restarting it, so a slow pass that grazes twice builds.
func strike(i: int, dir: Vector3, power: float = 1.0) -> void:
	if i < 0 or i >= _fixtures.size():
		return
	var f := _fixtures[i]
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.001:
		flat = Vector3.FORWARD
	flat = flat.normalized()
	# swing ALONG the blow: rotate about the horizontal axis perpendicular to it
	f.axis = Vector3.UP.cross(flat).normalized()
	f.amp = minf(f.amp + STRIKE_MAX * clampf(power, 0.0, 1.0), STRIKE_MAX * 1.4)
	f.t = 0.0


func strike_all_within(world_pos: Vector3, dir: Vector3, radius: float,
		power: float = 1.0) -> int:
	## Strike EVERY fixture the flier is close enough to have touched, not
	## merely the nearest one (Bert: "first and second chandeliers should
	## wobble"). A wyrm 10.6 u across passing down a nave is inside two of
	## them at once, and picking a single winner meant the second sat dead
	## still while a wing went through it. Power falls off with distance, so
	## the one it nearly centres on swings hard and the one it only brushes
	## trembles. Returns how many were struck.
	var struck := 0
	for i in _fixtures.size():
		var d := _fixtures[i].node.global_position.distance_to(world_pos)
		if d < radius:
			strike(i, dir, power * clampf(1.0 - d / radius, 0.15, 1.0))
			struck += 1
	return struck


func _process(delta: float) -> void:
	_elapsed += delta
	for f in _fixtures:
		if not is_instance_valid(f.node):
			continue
		# the draught: two slow, incommensurate rocks so it never repeats
		var a := DRAUGHT_AMP * sin(_elapsed * 0.41 + f.phase)
		var b := DRAUGHT_AMP * 0.7 * sin(_elapsed * 0.29 + f.phase * 1.7)
		var basis := f.rest * Basis(Vector3.RIGHT, a) * Basis(Vector3.FORWARD, b)
		# …and the strike, decaying
		if f.amp > 0.0005:
			f.t += delta
			var w := TAU / f.period()
			var swing: float = f.amp * exp(-SETTLE * f.t) * sin(w * f.t)
			basis = basis * Basis(f.axis, swing)
			f.amp *= exp(-SETTLE * delta)
		f.node.transform.basis = basis
