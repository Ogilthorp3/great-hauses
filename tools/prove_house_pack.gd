extends Node
## tools/prove_house_pack.gd — play a house nobody built into the game.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path <game> \
##       --resolution 1280x720 res://tools/prove_house_pack.tscn -- \
##       --house=ravenmark --artifacts=<abs dir>
##
## Exit code 0 = that house is in the Hall of Banners and plays.
##
## WHY THIS EXISTS. "The loader parses the manifest" is not the claim worth
## making; "a house someone else wrote actually plays" is. So this drives the
## SHIPPED main scene — the real Hall, real synthesized clicks on the new
## house's crest, the real match — and then measures the army that shows up:
##
##   * the roster: the pack is there, and it came from user://
##   * the Hall:   its crest hangs with the others (screenshot)
##   * the match:  32 pieces on a real board (screenshot)
##   * the army:   assembled (costume_preview.validate_piece) and obeying the
##                 material roles (costume_preview.role_offenders) — the same
##                 two gates the shipped nine are held to
##   * the roles:  its pawns wear ITS half-helm, its royals ITS crest, and the
##                 surface it declared "natural:bone" did NOT take the jersey
##
## It installs itself under /root so it survives the scene swap, the way
## main.gd installs the e2e harness. It never touches test_e2e/.

const MAIN_SCENE := "res://scenes/main.tscn"
const TIMEOUT := 90.0

var house_id := "ravenmark"
var artifacts := ""
var failures: Array[String] = []
var passes := 0
var _t0 := 0.0
var _tree: SceneTree


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--house="):
			house_id = a.split("=", true, 1)[1]
		elif a.begins_with("--artifacts="):
			artifacts = a.split("=", true, 1)[1]
	_t0 = Time.get_ticks_msec() / 1000.0
	_install.call_deferred()


## Reparent to /root: this node has to outlive the change_scene into the game,
## and then a SECOND one when the Hall swaps into the match.
##
## Three things have to happen in this order or the proof kills itself:
## clear `current_scene` FIRST (change_scene_to_file frees whatever it points
## at, and it points at this node), take a reference to the SceneTree BEFORE
## leaving the tree (get_tree() is null for an orphan), and only then re-add.
func _install() -> void:
	_tree = get_tree()
	if _tree.current_scene == self:
		_tree.current_scene = null
	if get_parent() != null:
		get_parent().remove_child(self)
	_tree.root.add_child(self)
	_tree.change_scene_to_file(MAIN_SCENE)
	_run()


func _run() -> void:
	print("=== PROVE HOUSE PACK: %s ===" % house_id)
	if not await _prove_roster():
		return _finish()
	if not await _prove_hall():
		return _finish()
	if not await _prove_match():
		return _finish()
	_finish()


# ── 1. the roster ──────────────────────────────────────────────────────────


func _prove_roster() -> bool:
	var ids := HouseRegistry.house_ids()
	print("roster (%d): %s" % [ids.size(), ", ".join(ids)])
	print("installed from user://: %s" % ", ".join(HouseRegistry.installed_house_ids()))
	if not HouseRegistry.has_house(house_id):
		_fail("roster", "'%s' is not in the roster — is the pack in user://houses/?" % house_id)
		return false
	_pass("roster: %s is one of %d houses" % [house_id, ids.size()])
	if not HouseRegistry.installed_house_ids().has(house_id):
		_fail("roster", "'%s' loaded, but not from user:// — this proves nothing about DLC"
				% house_id)
		return false
	var h := HouseRegistry.get_house(house_id)
	_pass("roster: %s, seat %s, jersey %s, coat %s (from %s)" % [str(h["name"]),
			str(h["seat"]), str(h["tints"]["kit"]), str(h["coat"]), str(h["pack_dir"])])
	return true


# ── 2. the Hall of Banners ─────────────────────────────────────────────────


func _prove_hall() -> bool:
	# NOTE the predicate only ANSWERS; it does not assign. A GDScript lambda
	# captures locals BY VALUE, so `hall = ...` inside one writes to the
	# lambda's own copy and leaves the outer `hall` null — which then aborted
	# this function at the next line, silently, and let the proof print PASS
	# with nothing proved. (Hence MIN_PASSES below: the same trap the costume
	# suite guards with MIN_EXPECTED_CHECKS.)
	if not await _wait_until(func() -> bool:
			return _find_first(_tree.root, "HouseSelect") != null, 20.0):
		_fail("hall", "the Hall of Banners never appeared")
		return false
	var hall := _find_first(_tree.root, "HouseSelect") as Control
	await _sleep(0.9)   # deferred ring layout + first draw
	var names: Array[String] = []
	for c in _find_first(hall, "CrestRing").get_children():
		names.append(str(c.name).trim_prefix("Crest_"))
	print("hall ring (%d): %s" % [names.size(), ", ".join(names)])
	await _shot("hall_of_banners")
	var crest := hall.find_child("Crest_%s" % house_id, true, false) as Control
	if crest == null:
		_fail("hall", "no crest named Crest_%s hangs in the ring" % house_id)
		return false
	_pass("hall: %s hangs with the other %d" % [house_id, names.size() - 1])
	# Hover it, so the preview panel shows the pack's own words, and shoot that.
	crest.get_node("Sigil").mouse_entered.emit()
	await _sleep(0.5)
	var motto := _find_first(hall, "Preview").get_child(2) as Label
	print("hall preview: %s" % motto.text)
	await _shot("hall_ravenmark_hovered")

	# ...and now a real click on a real button, exactly as a player would.
	if not await _click_until(crest.get_node("Sigil"),
			func() -> bool: return int(hall.get("phase")) == 1, "crest"):
		_fail("hall", "clicking %s's crest never advanced the Hall" % house_id)
		return false
	_pass("hall: its crest is clickable and pledges the house")
	var opp := _find_button(hall, "Casual")
	if opp == null or not await _click_until(opp,
			func() -> bool: return int(hall.get("phase")) == 2, "opponent"):
		_fail("hall", "could not choose an opponent")
		return false
	var mode := _find_button(hall, "Single Match")
	if mode == null:
		_fail("hall", "no Single Match button")
		return false
	await _click_control(mode)
	_pass("hall: opponent + war chosen")
	return true


# ── 3. the match ───────────────────────────────────────────────────────────


func _prove_match() -> bool:
	if not await _wait_until(func() -> bool:
			var g := _find_first(_tree.root, "Game")
			return g != null and not bool(g.get("busy")), 40.0):
		_fail("match", "the board never finished assembling")
		return false
	var game := _find_first(_tree.root, "Game")
	await _sleep(1.2)
	if str(Session.player_house) != house_id:
		_fail("match", "the match seated '%s', not '%s'" % [Session.player_house, house_id])
		return false
	_pass("match: seated for %s vs %s" % [Session.player_house, Session.rival_house()])

	var pieces: Array[Node] = []
	for n in game.find_children("*", "PieceView", true, false):
		pieces.append(n)
	if pieces.size() != 32:
		_fail("match", "%d pieces on the board, expected 32" % pieces.size())
		return false
	_pass("match: 32 pieces stand")
	await _shot("board_playing")

	# -- the army the pack actually fielded ---------------------------------
	var preview: GDScript = load("res://src/board/costume_preview.gd")
	var mine: Array[Node] = []
	for pv in pieces:
		if str(pv.get("house_id")) == house_id:
			mine.append(pv)
	if mine.size() != 16:
		_fail("army", "%d %s pieces, expected 16" % [mine.size(), house_id])
		return false
	_pass("army: 16 %s pieces on the board" % house_id)

	var assembly: Array = []
	var roles: Array = []
	for pv in mine:
		assembly.append_array(preview.validate_piece(pv, int(pv.get("piece_type")), house_id))
		roles.append_array(preview.role_offenders(pv, house_id))
	if not assembly.is_empty():
		_fail("army", "assembly gate: %s" % str(assembly))
	else:
		_pass("army: every piece assembles (the shipped assembly gate)")
	if not roles.is_empty():
		_fail("army", "ROLE GATE: %s" % str(roles))
	else:
		_pass("army: the whole army obeys its material roles (the shipped role gate)")

	# -- the pack's OWN art, on the board ------------------------------------
	var helmed := 0
	var crested := 0
	for pv in mine:
		if pv.find_child("Helm_%s" % house_id, true, false) != null:
			helmed += 1
		if pv.find_child("Crest_%s" % house_id, true, false) != null:
			crested += 1
	if helmed != 8:
		_fail("art", "%d pawns wear the pack's own helm, expected 8" % helmed)
	else:
		_pass("art: 8 pawns wear the pack's own half-helm (Helm_%s)" % house_id)
	if crested != 4:
		_fail("art", "%d pieces wear the pack's own crest, expected 4 (2 knights, queen, king)"
				% crested)
	else:
		_pass("art: knights, queen and king wear the pack's own crest")

	# -- and the one line that matters: a declared NATURAL stayed natural ----
	_prove_declared_natural(mine)
	await _shot("board_close")
	return true


## THE POINT OF THE WHOLE FORMAT, measured on a rendered piece.
##
## House Ravenmark's crest is one mesh with two surfaces: a plume (KIT, takes
## the jersey) and a beak declared "natural:bone" in its manifest. If the
## declaration works, those two surfaces render in DIFFERENT colours and the
## beak is nowhere near the house purple. If a pack could not do this, the
## whole exercise would be "a stranger may pick a colour", not "a stranger may
## build a house".
func _prove_declared_natural(mine: Array[Node]) -> void:
	var declared: Dictionary = HouseRegistry.material_roles(house_id)
	if declared.is_empty():
		print("      (this pack declares no material roles — nothing to prove here)")
		return
	var kit: Color = HouseRegistry.get_house_tint(house_id, "kit")
	for surface in declared:
		if str(declared[surface]["role"]) != "natural":
			continue
		var found := false
		for pv in mine:
			for mi: MeshInstance3D in pv.find_children("*", "MeshInstance3D", true, false):
				if mi.mesh == null:
					continue
				for s in mi.mesh.get_surface_count():
					var base := mi.mesh.surface_get_material(s) as StandardMaterial3D
					if base == null or str(base.resource_name) != str(surface):
						continue
					found = true
					var live := mi.get_active_material(s) as StandardMaterial3D
					var c: Color = live.albedo_color
					var gap := Vector3(c.r - kit.r, c.g - kit.g, c.b - kit.b).length()
					if gap > 0.14:
						_pass("roles: '%s' declared natural:%s renders %s — %.2f off the jersey %s"
								% [surface, str(declared[surface]["stuff"]),
								c.to_html(false), gap, kit.to_html(false)])
					else:
						_fail("roles", "'%s' is declared natural but rendered %s, only %.2f from the jersey"
								% [surface, c.to_html(false), gap])
					break
				if found:
					break
			if found:
				break
		if not found:
			print("      (no rendered surface named '%s' — nothing to measure)" % surface)


# ── plumbing ───────────────────────────────────────────────────────────────


## A hard error inside an awaited step aborts it silently and resumes the
## caller as if it had returned — so "no failures" is not proof anything ran.
## This floor turns a silently-aborted proof into a loud one.
const MIN_PASSES := 11


func _finish() -> void:
	print("---")
	if failures.is_empty() and passes < MIN_PASSES:
		_fail("proof", "only %d of at least %d checks ran — a step aborted silently"
				% [passes, MIN_PASSES])
	if failures.is_empty():
		print("PROOF PASS — %s was written by nobody who built this game, and it plays"
				% house_id)
	else:
		print("PROOF FAIL — %d problem(s):" % failures.size())
		for f in failures:
			print("   %s" % f)
	_tree.quit(0 if failures.is_empty() else 1)


func _pass(msg: String) -> void:
	passes += 1
	print("PROOF PASS  %s" % msg)


func _fail(where: String, msg: String) -> void:
	failures.append("%s: %s" % [where, msg])
	print("PROOF FAIL  %s: %s" % [where, msg])


func _shot(name: String) -> void:
	await _tree.process_frame
	await RenderingServer.frame_post_draw
	if artifacts.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(artifacts)
	var img := get_viewport().get_texture().get_image()
	var path := artifacts.path_join("%s.png" % name)
	if img.save_png(path) == OK:
		print("PROOF SHOT  %s" % path)


func _sleep(seconds: float) -> void:
	await _tree.create_timer(seconds).timeout


func _wait_until(pred: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() / 1000.0 + seconds
	while Time.get_ticks_msec() / 1000.0 < deadline:
		if bool(pred.call()):
			return true
		if Time.get_ticks_msec() / 1000.0 - _t0 > TIMEOUT:
			_fail("watchdog", "the whole proof ran past %.0f s" % TIMEOUT)
			return false
		await _tree.process_frame
	return false


## A click, in the coordinates the OS would have used.
##
## Input.parse_input_event feeds events as if they came from the window, but a
## Control's rect is in CANVAS coordinates — and this project stretches a
## 1920x1080 UI into whatever the window is (1280x720 here). Without the
## viewport's final transform every click lands two thirds of the way toward
## the top-left corner and hits nothing, which is exactly what happened the
## first time this ran. The motion event first: a button wants to be hovered
## before it is pressed.
func _click_control(c: Control) -> void:
	var to_window := get_viewport().get_final_transform()
	var at: Vector2 = to_window * c.get_global_rect().get_center()
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	Input.parse_input_event(mm)
	await _tree.process_frame
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		ev.position = at
		ev.global_position = at
		Input.parse_input_event(ev)
		await _tree.process_frame
	await _sleep(0.35)


func _click_until(c: Control, pred: Callable, what: String, attempts := 3) -> bool:
	for i in attempts:
		await _click_control(c)
		if await _wait_until(pred, 2.5):
			return true
		print("      (retrying the %s click)" % what)
	return false


func _find_button(root: Node, needle: String) -> Button:
	for b: Button in root.find_children("*", "Button", true, false):
		if str(b.text).containsn(needle) or str(b.get_meta("label", "")).containsn(needle):
			return b
	return null


func _find_first(root: Node, node_name: String) -> Node:
	if str(root.name) == node_name:
		return root
	return root.find_child(node_name, true, false)
