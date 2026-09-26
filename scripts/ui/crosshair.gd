class_name Crosshair
extends Control
## Dynamic crosshair (gap follows the real weapon spread), hit marker,
## reload ring and damage direction indicators. Everything is drawn in _draw().

const COLOR := Color(1, 1, 1, 0.92)
const OUTLINE := Color(0, 0, 0, 0.55)

var _gap := 12.0
var _hit_time := 0.0
var _hit_color := Color.WHITE
var _hit_size := 1.0
## Array of { "pos": Vector3 (attacker position), "time": float }
var _damage_marks: Array = []


func show_hit(headshot: bool, kill: bool) -> void:
	_hit_time = 0.35 if not kill else 0.6
	_hit_color = Color(1.0, 0.25, 0.2) if kill else (Color(1.0, 0.75, 0.2) if headshot else Color.WHITE)
	_hit_size = 1.5 if kill else (1.2 if headshot else 1.0)


func add_damage_mark(attacker_pos: Vector3) -> void:
	_damage_marks.append({"pos": attacker_pos, "time": 1.6})
	if _damage_marks.size() > 6:
		_damage_marks.pop_front()


func _process(delta: float) -> void:
	var p := Game.player
	if p != null and is_instance_valid(p) and Game.camera != null:
		var hspeed := Vector2(p.velocity.x, p.velocity.z).length()
		var stance_factor := 1.0
		if p.stance == GameCharacter.Stance.CROUCH:
			stance_factor = p.weapon_data.crouch_spread_factor
		elif p.stance == GameCharacter.Stance.PRONE:
			stance_factor = p.weapon_data.prone_spread_factor
		var spread_deg := p.weapon.get_spread(p.input_aim, hspeed, not p.is_on_floor(), stance_factor)
		# Shotgun: show the pellet cone.
		spread_deg += p.weapon_data.pellet_spread
		var half_h := get_viewport_rect().size.y * 0.5
		var px := tan(deg_to_rad(spread_deg)) / tan(deg_to_rad(Game.camera.fov) * 0.5) * half_h
		_gap = lerpf(_gap, clampf(px, 3.0, 120.0), 1.0 - exp(-18.0 * delta))
	_hit_time = maxf(_hit_time - delta, 0.0)
	for m in _damage_marks:
		m.time -= delta
	_damage_marks = _damage_marks.filter(func(m): return m.time > 0.0)
	queue_redraw()


func _draw() -> void:
	var p := Game.player
	if p == null or not is_instance_valid(p) or p.is_dead:
		return
	var c := Vector2.ZERO
	if p.weapon_data.is_melee():
		draw_circle(c, 3.0, OUTLINE)
		draw_circle(c, 2.0, COLOR)
	elif p.weapon_data.pellets > 1 and not p.is_sprinting and not p.is_swimming:
		# Shotgun: circle showing where the pellets land.
		draw_arc(c, _gap, 0.0, TAU, 32, OUTLINE, 4.0)
		draw_arc(c, _gap, 0.0, TAU, 32, COLOR, 2.0)
		draw_circle(c, 2.2, OUTLINE)
		draw_circle(c, 1.4, COLOR)
	elif not p.is_sprinting and not p.is_swimming:
		var length := 9.0 if not p.input_aim else 6.0
		for dir in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
			var a: Vector2 = c + dir * _gap
			var b: Vector2 = c + dir * (_gap + length)
			draw_line(a, b, OUTLINE, 4.0)
			draw_line(a, b, COLOR, 2.0)
		draw_circle(c, 2.2, OUTLINE)
		draw_circle(c, 1.4, COLOR)

	# Hit marker
	if _hit_time > 0.0:
		var alpha := clampf(_hit_time / 0.2, 0.0, 1.0)
		var col := _hit_color
		col.a = alpha
		var r0 := 7.0 * _hit_size
		var r1 := 15.0 * _hit_size
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var n: Vector2 = d.normalized()
			draw_line(c + n * r0, c + n * r1, Color(0, 0, 0, alpha * 0.5), 4.5)
			draw_line(c + n * r0, c + n * r1, col, 2.5)

	# Reload ring
	if p.weapon.is_reloading():
		var prog := p.weapon.get_reload_progress()
		draw_arc(c, 26.0, 0.0, TAU, 40, Color(0, 0, 0, 0.35), 4.0)
		draw_arc(c, 26.0, -PI * 0.5, -PI * 0.5 + TAU * prog, 40, Color(1.0, 0.8, 0.3, 0.95), 4.0)

	# Damage direction indicators (relative to where the camera looks).
	if Game.camera != null:
		var cam_fwd := -Game.camera.global_transform.basis.z
		var cam_yaw := atan2(-cam_fwd.x, -cam_fwd.z)
		for m in _damage_marks:
			var to: Vector3 = (m.pos as Vector3) - p.global_position
			var ang := atan2(-to.x, -to.z) - cam_yaw
			# Screen angle: 0 = up, clockwise positive.
			var screen_ang := -ang - PI * 0.5
			var a := clampf(float(m.time) / 1.6, 0.0, 1.0)
			draw_arc(c, 130.0, screen_ang - 0.28, screen_ang + 0.28, 16, Color(1.0, 0.15, 0.1, 0.75 * a), 7.0)
