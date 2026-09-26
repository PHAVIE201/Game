class_name ZoneManager
extends Node3D
## The shrinking safe zone ("bo").
##
## Each phase: the next (white) circle is announced, after `wait` seconds the
## current (blue) circle shrinks toward it over `shrink` seconds. Everyone
## outside the current circle loses health every second; armor does not help.
## The next circle always lies completely inside the current one.

signal phase_changed(phase: int, state: int)

enum State { IDLE, WAITING, SHRINKING, FINISHED }

## [wait (s), shrink (s), radius at the end (m), damage per second outside]
const PHASES := [
	[90.0, 60.0, 600.0, 0.6],
	[60.0, 45.0, 360.0, 1.0],
	[50.0, 40.0, 200.0, 2.0],
	[40.0, 30.0, 110.0, 3.5],
	[30.0, 25.0, 55.0, 5.0],
	[25.0, 20.0, 25.0, 7.0],
	[20.0, 20.0, 0.0, 10.0],
]
## The first circle covers the whole island.
const START_RADIUS := 1150.0
const WALL_HEIGHT := 520.0

var state: int = State.IDLE
var phase := 0
var center := Vector2.ZERO
var radius := START_RADIUS
var next_center := Vector2.ZERO
var next_radius := START_RADIUS
## Seconds left in the current WAITING / SHRINKING state.
var timer := 0.0
var damage_per_second := 0.4
## < 1 = faster zone (menu option).
var time_scale := 1.0

var _from_center := Vector2.ZERO
var _from_radius := START_RADIUS
var _tick := 0.0
var _rng := RandomNumberGenerator.new()
var _wall: MeshInstance3D


func _ready() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = 128
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/zone_wall.gdshader")
	cyl.material = mat
	_wall = MeshInstance3D.new()
	_wall.name = "ZoneWall"
	_wall.mesh = cyl
	_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wall.custom_aabb = AABB(Vector3(-1.2, -0.6, -1.2), Vector3(2.4, 1.2, 2.4))
	_wall.visible = false
	add_child(_wall)


func start(rng_seed: int, p_time_scale := 1.0) -> void:
	_rng.seed = rng_seed
	time_scale = p_time_scale
	phase = 0
	center = Vector2.ZERO
	radius = START_RADIUS
	damage_per_second = 0.4
	_begin_waiting()


func stop() -> void:
	state = State.IDLE
	_wall.visible = false


func is_active() -> bool:
	return state == State.WAITING or state == State.SHRINKING or state == State.FINISHED


func get_phase_count() -> int:
	return PHASES.size()


## Distance (m) from a point to the safe area (0 inside).
func distance_outside(p: Vector3) -> float:
	return maxf(Vector2(p.x, p.z).distance_to(center) - radius, 0.0)


func is_inside(p: Vector3, margin := 0.0) -> bool:
	return Vector2(p.x, p.z).distance_to(center) <= radius - margin


func is_inside_next(p: Vector3, margin := 0.0) -> bool:
	return Vector2(p.x, p.z).distance_to(next_center) <= next_radius - margin


## Seconds until the current circle reaches the next one.
func time_until_closed() -> float:
	if state == State.WAITING:
		return timer + float(PHASES[phase][1]) * time_scale
	if state == State.SHRINKING:
		return timer
	return 0.0


## Random walkable point inside the next circle (bots use it to move in).
func random_point_in_next(rng: RandomNumberGenerator, margin := 0.2) -> Vector3:
	var r := maxf(next_radius * (1.0 - margin), 0.0)
	for k in 30:
		var p := next_center + Vector2.from_angle(rng.randf() * TAU) * r * sqrt(rng.randf())
		if Game.world != null and Game.world.is_walkable(p.x, p.y):
			return Vector3(p.x, Game.world.get_height(p.x, p.y), p.y)
	var h := Game.world.get_height(next_center.x, next_center.y) if Game.world != null else 0.0
	return Vector3(next_center.x, h, next_center.y)


func _begin_waiting() -> void:
	var spec: Array = PHASES[phase]
	next_radius = float(spec[2])
	next_center = _pick_next_center(next_radius)
	state = State.WAITING
	timer = float(spec[0]) * time_scale
	phase_changed.emit(phase, state)
	var text := "Vùng an toàn mới đã xuất hiện - bo thu hẹp sau %s" % format_time(timer)
	if phase == 0:
		text = "Xem bản đồ (M): bo sẽ thu hẹp sau %s" % format_time(timer)
	Events.hud_message.emit(text, 4.0)


func _pick_next_center(new_radius: float) -> Vector2:
	var max_off := maxf(radius - new_radius, 0.0)
	var best := center
	for k in 40:
		var c := center + Vector2.from_angle(_rng.randf() * TAU) * max_off * sqrt(_rng.randf())
		best = c
		# Prefer circles centered on dry land.
		if Game.world == null or Game.world.is_walkable(c.x, c.y):
			break
	return best


func _physics_process(delta: float) -> void:
	if state == State.IDLE:
		return
	match state:
		State.WAITING:
			timer -= delta
			if timer <= 0.0:
				state = State.SHRINKING
				timer = float(PHASES[phase][1]) * time_scale
				_from_center = center
				_from_radius = radius
				damage_per_second = float(PHASES[phase][3])
				phase_changed.emit(phase, state)
				Events.hud_message.emit("Bo đang thu hẹp!", 3.0)
		State.SHRINKING:
			timer -= delta
			var total := float(PHASES[phase][1]) * time_scale
			var t := clampf(1.0 - timer / maxf(total, 0.001), 0.0, 1.0)
			center = _from_center.lerp(next_center, t)
			radius = lerpf(_from_radius, next_radius, t)
			if timer <= 0.0:
				center = next_center
				radius = next_radius
				phase += 1
				if phase < PHASES.size():
					_begin_waiting()
				else:
					state = State.FINISHED
					phase_changed.emit(phase, state)
	_tick += delta
	if _tick >= 1.0:
		_apply_damage(_tick)
		_tick = 0.0


func _apply_damage(seconds: float) -> void:
	if Game.match_manager == null:
		return
	for c in Game.match_manager.alive.duplicate():
		if c.is_dead or is_inside(c.global_position) or not c.is_zone_vulnerable():
			continue
		var info := DamageInfo.new()
		info.amount = damage_per_second * seconds
		info.part = DamageInfo.Part.OTHER
		info.ignore_armor = true
		info.weapon_name = "Vùng độc"
		info.hit_position = c.global_position
		info.direction = Vector3.DOWN
		c.apply_damage(info)


func _process(_delta: float) -> void:
	_wall.visible = state != State.IDLE and radius > 1.0
	if _wall.visible:
		_wall.scale = Vector3(radius, WALL_HEIGHT, radius)
		_wall.position = Vector3(center.x, WALL_HEIGHT * 0.5 - 60.0, center.y)


static func format_time(seconds: float) -> String:
	var s := maxi(ceili(seconds), 0)
	return "%d:%02d" % [floori(s / 60.0), s % 60]
