class_name Minimap
extends Control
## North-up minimap around the player: terrain image, safe zone (blue),
## next zone (white), a line toward the next zone, and the player arrow.
## Also used, with `full_map = true`, for the big M map of the whole island.

const ZONE_COLOR := Color(0.25, 0.55, 1.0, 0.95)
const NEXT_COLOR := Color(1, 1, 1, 0.95)
const GRID_LETTERS := "ABCDEFGH"

## Meters shown across the minimap.
@export var view_meters := 520.0
@export var full_map := false

var _redraw_timer := 0.0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_redraw_timer -= delta
	if _redraw_timer <= 0.0:
		# The minimap follows the player every frame; the big map a bit slower.
		_redraw_timer = 0.0 if not full_map else 0.1
		queue_redraw()


## Map pixel (in this control) of a world position.
func world_to_map(p: Vector2) -> Vector2:
	return (p - _view_center()) / _meters_per_px() + size * 0.5


func _meters_per_px() -> float:
	if full_map:
		return HeightMap.SIZE / minf(size.x, size.y)
	return view_meters / minf(size.x, size.y)


func _view_center() -> Vector2:
	if full_map:
		return Vector2.ZERO
	var p := Game.player
	if p != null and is_instance_valid(p):
		return Vector2(p.global_position.x, p.global_position.z)
	return Vector2.ZERO


func _draw() -> void:
	var world := Game.world
	if world == null or world.map_texture == null:
		return
	var mpp := _meters_per_px()
	var tex_mpp := HeightMap.SIZE / float(GameWorld.MAP_RES)
	# Terrain: the part of the map texture under this control.
	var view_c := _view_center()
	var half_m := size * 0.5 * mpp
	var src := Rect2((view_c - half_m + Vector2(HeightMap.HALF, HeightMap.HALF)) / tex_mpp, half_m * 2.0 / tex_mpp)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.35, 0.6))
	draw_texture_rect_region(world.map_texture, Rect2(Vector2.ZERO, size), src)

	if full_map:
		_draw_grid()
		_draw_towns()

	_draw_plane_route()

	# Zones
	var zone := Game.zone
	if zone != null and zone.is_active():
		var cz := world_to_map(zone.center)
		draw_arc(cz, zone.radius / mpp, 0.0, TAU, 96, ZONE_COLOR, 2.5 if full_map else 2.0, true)
		if zone.state == ZoneManager.State.WAITING or zone.state == ZoneManager.State.SHRINKING:
			var nz := world_to_map(zone.next_center)
			draw_arc(nz, maxf(zone.next_radius / mpp, 1.0), 0.0, TAU, 96, NEXT_COLOR, 2.0, true)
			var p := Game.player
			if p != null and is_instance_valid(p) and not p.is_dead and not zone.is_inside_next(p.global_position):
				# Straight line to the nearest edge of the next zone.
				var pp := Vector2(p.global_position.x, p.global_position.z)
				var edge := zone.next_center + (pp - zone.next_center).normalized() * zone.next_radius
				draw_dashed_line(world_to_map(pp), world_to_map(edge), Color(1, 1, 1, 0.8), 1.5, 6.0)

	_draw_player()
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.45), false, 2.0)


func _draw_plane_route() -> void:
	var mm := Game.match_manager
	if mm == null or mm.plane == null or not is_instance_valid(mm.plane) or not mm.plane.is_active():
		return
	var plane := mm.plane
	var a := world_to_map(Vector2(plane.start.x, plane.start.z))
	var b := world_to_map(Vector2(plane.end.x, plane.end.z))
	draw_dashed_line(a, b, Color(1.0, 0.85, 0.3, 0.9), 2.0, 10.0)
	var pp := world_to_map(Vector2(plane.global_position.x, plane.global_position.z))
	var d := Vector2(plane.dir.x, plane.dir.z)
	var n := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([pp + d * 9.0, pp - d * 6.0 + n * 7.0, pp - d * 3.0, pp - d * 6.0 - n * 7.0]), Color(1.0, 0.85, 0.3))


func _draw_player() -> void:
	var p := Game.player
	if p == null or not is_instance_valid(p):
		return
	var pos := world_to_map(Vector2(p.global_position.x, p.global_position.z))
	var yaw := p.aim_yaw
	if Game.camera != null and is_instance_valid(Game.camera):
		var f := -Game.camera.global_transform.basis.z
		yaw = atan2(-f.x, -f.z)
	# Forward (-Z) is "up" on the map; yaw is counter-clockwise from above.
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(-fwd.y, fwd.x)
	var s := 9.0 if full_map else 8.0
	var tip := pos + fwd * s
	var pts := PackedVector2Array([tip, pos - fwd * s * 0.6 + right * s * 0.6, pos - fwd * s * 0.25, pos - fwd * s * 0.6 - right * s * 0.6])
	draw_colored_polygon(pts, Color(1.0, 0.8, 0.25) if not p.is_dead else Color(0.6, 0.6, 0.6))
	pts.append(tip)
	draw_polyline(pts, Color(0, 0, 0, 0.8), 1.5)


func _draw_grid() -> void:
	var font := get_theme_default_font()
	var n := GRID_LETTERS.length()
	var cell := HeightMap.SIZE / n
	for k in range(n + 1):
		var w := -HeightMap.HALF + k * cell
		var a := world_to_map(Vector2(w, -HeightMap.HALF))
		var b := world_to_map(Vector2(w, HeightMap.HALF))
		draw_line(a, b, Color(1, 1, 1, 0.18), 1.0)
		a = world_to_map(Vector2(-HeightMap.HALF, w))
		b = world_to_map(Vector2(HeightMap.HALF, w))
		draw_line(a, b, Color(1, 1, 1, 0.18), 1.0)
	for k in n:
		var c := -HeightMap.HALF + (k + 0.5) * cell
		var top := world_to_map(Vector2(c, -HeightMap.HALF))
		draw_string(font, top + Vector2(-10, 18), GRID_LETTERS[k], HORIZONTAL_ALIGNMENT_CENTER, 20, 15, Color(1, 1, 1, 0.7))
		var left := world_to_map(Vector2(-HeightMap.HALF, c))
		draw_string(font, left + Vector2(4, 6), str(k + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.7))


func _draw_towns() -> void:
	var font := get_theme_default_font()
	for t in Game.world.get_towns():
		var pos := world_to_map(t.center as Vector2)
		var text: String = t.name
		draw_string_outline(font, pos + Vector2(-80, -14), text, HORIZONTAL_ALIGNMENT_CENTER, 160, 16, 4, Color(0, 0, 0, 0.7))
		draw_string(font, pos + Vector2(-80, -14), text, HORIZONTAL_ALIGNMENT_CENTER, 160, 16, Color.WHITE)
