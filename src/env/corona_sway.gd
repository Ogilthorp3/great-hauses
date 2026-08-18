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
##   THE STRIKE — a real damped pendulum with STATE: an angle and an angular
##     velocity, integrated every frame. A blow is an IMPULSE to the velocity.
##     Period comes from the pendulum's own length (the drop from the pivot to
##     the ring), because a long chain swings slowly and a short one does not,
##     and getting that wrong is instantly legible.
##
## WHY IT IS AN OSCILLATOR AND NOT A CLOSED-FORM SINE (Bert, 2026-08-18: "the
## chandeliers didn't move like it should"). The first version evaluated
## `amp * exp(-k t) * sin(w t)` and every call to `strike()` set `t = 0`. The
## cinematic strikes EVERY FRAME the wyrm is within reach — so t was reset to
## zero on every one of those frames, sin(0) = 0, and the fixture hung dead
## still for precisely as long as the dragon was passing through it, then
## began to swing a second later once the wing had gone and the camera was
## somewhere else. The one moment it had to sell was the one moment it was
## guaranteed motionless.
##
## A stateful oscillator cannot fail that way: repeated blows FEED it, the
## same as a hand pushing a swing, and it is already moving while it is being
## hit. It also rings on afterwards — damping is light, because a hundred
## kilos of iron on a chain does not stop in two seconds, and the coronas hang
## over the board for the whole match, not just the cinematic.
##
## Costs nothing but a rotation per fixture per frame; no physics server, no
## collision, no new lights.

## Damping ratio. 0.055 rings for roughly ten seconds on a 4 m drop — iron on
## a chain, not a screen door. The old 0.55 was applied TWICE (once inside the
## sine, once per frame to the amplitude) and killed the swing before it
## reached its first peak.
const ZETA := 0.055
const STRIKE_MAX := 0.30        ## radians (~17 deg) — a wingtip, not a wrecking ball
## Angular velocity a full-power one-off blow imparts, rad/s. Chosen so a
## clean hit peaks near STRIKE_MAX: peak angle ~= vel / w.
const STRIKE_IMPULSE := 0.46
## Continuous forcing, rad/s per second, for a wing SLIDING past over many
## frames. Scaled by the caller's delta so the energy a pass delivers does not
## depend on the frame rate.
const STRIKE_RATE := 2.2
const DRAUGHT_AMP := 0.013      ## radians (~0.75 deg) of idle breath
const G := 9.81


class Fixture:
	extends RefCounted
	var node: Node3D
	var rest: Basis
	var drop := 3.0              ## pivot to the ring: sets the swing period
	var phase := 0.0
	var ang := 0.0               ## current swing angle, radians
	var vel := 0.0               ## angular velocity, rad/s — what a blow adds
	var axis := Vector3.RIGHT    ## the horizontal axis it is swinging about

	func period() -> float:
		# T = 2*pi*sqrt(L/g), the only number that makes a swing look its size
		return TAU * sqrt(maxf(drop, 0.2) / G)

	func omega() -> float:
		return TAU / period()

	## At rest enough that a new blow may choose a new swing PLANE. While it
	## is already moving, a fresh hit feeds the plane it is in — a swing does
	## not change direction because you pushed it sideways once.
	func quiet() -> bool:
		return absf(ang) < 0.02 and absf(vel) < 0.05


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
## `power` 0..1 scales it. A blow is an IMPULSE to the angular velocity, so
## repeated blows accumulate like a hand pushing a swing instead of resetting
## it — which is the whole reason this is stateful.
func strike(i: int, dir: Vector3, power: float = 1.0) -> void:
	_impulse(i, dir, STRIKE_IMPULSE * clampf(power, 0.0, 1.0))


func _impulse(i: int, dir: Vector3, dv: float) -> void:
	if i < 0 or i >= _fixtures.size() or is_zero_approx(dv):
		return
	var f := _fixtures[i]
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.001:
		flat = Vector3.FORWARD
	flat = flat.normalized()
	# swing ALONG the blow: rotate about the horizontal axis perpendicular to it
	var axis := Vector3.UP.cross(flat).normalized()
	if f.quiet():
		f.axis = axis
		f.vel += dv
	else:
		# already swinging: feed it in its own plane, signed by whether the
		# new blow agrees with the plane it is already using
		f.vel += dv * signf(f.axis.dot(axis)) if not is_zero_approx(f.axis.dot(axis)) else dv
	# never let repeated feeding wind it past a wingtip's worth of swing
	var cap := STRIKE_MAX * 1.15 * f.omega()
	f.vel = clampf(f.vel, -cap, cap)


## `delta` > 0 means CONTINUOUS forcing — a wing sliding past across many
## frames — and the energy delivered is scaled by it, so a pass imparts the
## same swing at 30 fps as at 120. Leave it 0 for a single discrete blow.
func strike_all_within(world_pos: Vector3, dir: Vector3, radius: float,
		power: float = 1.0, delta: float = 0.0) -> int:
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
			var near := clampf(1.0 - d / radius, 0.15, 1.0)
			if delta > 0.0:
				_impulse(i, dir, STRIKE_RATE * power * near * delta)
			else:
				strike(i, dir, power * near)
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
		# …and the pendulum: angle and velocity integrated, semi-implicit so
		# it stays stable at any frame rate the tablet gives us.
		var w := f.omega()
		if absf(f.ang) > 0.0002 or absf(f.vel) > 0.0002:
			f.vel += (-w * w * f.ang - 2.0 * ZETA * w * f.vel) * delta
			f.ang += f.vel * delta
			if absf(f.ang) > STRIKE_MAX * 1.15:
				f.ang = clampf(f.ang, -STRIKE_MAX * 1.15, STRIKE_MAX * 1.15)
				f.vel *= -0.35        # it has reached the end of its arc
			basis = basis * Basis(f.axis, f.ang)
		f.node.transform.basis = basis
