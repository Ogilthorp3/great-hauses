class_name AdaptiveScale
extends RefCounted
## AdaptiveScale — Steve Jobs Grade Apple Retina & Dynamic Resolution Typography Engine.
## Computes adaptive scaling multipliers based on screen DPI, resolution, and viewport dimensions
## so fonts are exquisitely readable, beautifully proportioned, and razor-sharp across all displays
## (MacBook Pro Liquid Retina XDR, Studio Display 5K, 4K monitors, and standard 1080p).

static var _cached_scale := -1.0


static func get_scale(node: Node = null) -> float:
	var vp_size := Vector2(1920, 1080)
	if node != null and node.is_inside_tree():
		var vp := node.get_viewport()
		if vp != null and vp.get_visible_rect().size.x > 200:
			vp_size = vp.get_visible_rect().size
	elif DisplayServer.window_get_size().x > 200:
		vp_size = DisplayServer.window_get_size()

	var dpi := DisplayServer.screen_get_dpi()
	var is_retina := (dpi > 150) or (OS.get_name() == "macOS" and DisplayServer.screen_get_scale() > 1.2)

	# Calculate responsive scale based on resolution & DPI
	var res_factor: float = clampf(maxf(vp_size.x / 1440.0, vp_size.y / 900.0), 1.0, 2.4)
	var dpi_mult: float = 1.35 if is_retina else 1.15

	return clampf(res_factor * dpi_mult, 1.15, 2.5)


static func font(base_pt: int, node: Node = null) -> int:
	var s := get_scale(node)
	return int(roundf(float(base_pt) * s))


static func size_v2(base_vec: Vector2, node: Node = null) -> Vector2:
	var s := get_scale(node)
	return base_vec * s
