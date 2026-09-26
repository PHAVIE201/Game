class_name HealthBar
extends Control
## Player health bar with a delayed "ghost" bar showing recent damage.

var _value := 100.0
var _ghost := 100.0
var _max := 100.0


func _process(delta: float) -> void:
	var p := Game.player
	if p == null or not is_instance_valid(p):
		return
	_max = p.max_health
	_value = p.health
	if _ghost < _value:
		_ghost = _value
	else:
		_ghost = move_toward(_ghost, _value, delta * 30.0)
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0, 0, 0, 0.45))
	var inner := r.grow(-3.0)
	var ratio := clampf(_value / _max, 0.0, 1.0)
	var ghost_ratio := clampf(_ghost / _max, 0.0, 1.0)
	draw_rect(Rect2(inner.position, Vector2(inner.size.x * ghost_ratio, inner.size.y)), Color(0.95, 0.35, 0.3, 0.8))
	var col := Color(0.97, 0.97, 0.95)
	if ratio < 0.3:
		# Pulse red when critical.
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
		col = Color(1.0, 0.3, 0.25).lerp(Color(1.0, 0.55, 0.5), pulse)
	elif ratio < 0.6:
		col = Color(1.0, 0.85, 0.55)
	draw_rect(Rect2(inner.position, Vector2(inner.size.x * ratio, inner.size.y)), col)
	draw_rect(r, Color(1, 1, 1, 0.35), false, 1.5)
