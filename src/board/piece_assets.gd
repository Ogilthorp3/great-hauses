extends Node
## Autoload "PieceAssets" — shared runtime caches for PieceView: the merged
## Rig_Medium animation library and per-house tinted materials.
##
## Deliberately an autoload NODE rather than `static var`s on PieceView:
## script statics holding Resources crash Godot during engine shutdown
## (teardown-order bug — bit us as a SIGSEGV after quit(0) in e2e runs).
## An autoload releases its references in normal tree teardown.

const ANIM_GENERAL := preload("res://assets/kaykit-adventurers/Rig_Medium_General.glb")
const ANIM_MOVEMENT := preload("res://assets/kaykit-adventurers/Rig_Medium_MovementBasic.glb")

const LOOPED_ANIMS := ["Idle_A", "Idle_B", "Walking_A", "Walking_B", "Walking_C",
		"Running_A", "Running_B"]

var _shared_anims: AnimationLibrary
var _tint_cache: Dictionary = {}   # "<material rid>|<tint html>" -> StandardMaterial3D
var _desat_cache: Dictionary = {}  # texture rid id -> Texture2D


## Both Rig_Medium libraries merged once; the same rig drives every character.
func shared_anims() -> AnimationLibrary:
	if _shared_anims != null:
		return _shared_anims
	_shared_anims = AnimationLibrary.new()
	for packed: PackedScene in [ANIM_GENERAL, ANIM_MOVEMENT]:
		var inst := packed.instantiate()
		var player: AnimationPlayer = inst.get_node("AnimationPlayer")
		for anim_name in player.get_animation_list():
			if not _shared_anims.has_animation(anim_name):
				_shared_anims.add_animation(anim_name, player.get_animation(anim_name))
		inst.free()
	for anim_name in LOOPED_ANIMS:
		_shared_anims.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	return _shared_anims


func anim_length(anim_name: String) -> float:
	return shared_anims().get_animation(anim_name).length


## House-tinted variant of a pack material: desaturated albedo texture
## multiplied by the house tint, roughness pushed up. Cached and shared.
func tinted_material(src: StandardMaterial3D, tint: Color, saturation: float) -> StandardMaterial3D:
	var key := "%d|%s" % [src.get_rid().get_id(), tint.to_html()]
	if _tint_cache.has(key):
		return _tint_cache[key]
	var tinted: StandardMaterial3D = src.duplicate()
	if tinted.albedo_texture != null:
		tinted.albedo_texture = _desaturated(tinted.albedo_texture, saturation)
	tinted.albedo_color = src.albedo_color * tint
	tinted.roughness = maxf(tinted.roughness, 0.88)
	tinted.metallic = minf(tinted.metallic, 0.05)
	_tint_cache[key] = tinted
	return tinted


func _desaturated(tex: Texture2D, saturation: float) -> Texture2D:
	var key := tex.get_rid().get_id()
	if _desat_cache.has(key):
		return _desat_cache[key]
	var img := tex.get_image()
	if img == null:
		_desat_cache[key] = tex
		return tex
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	img.adjust_bcs(1.0, 1.0, saturation)
	img.generate_mipmaps()
	var out := ImageTexture.create_from_image(img)
	_desat_cache[key] = out
	return out
