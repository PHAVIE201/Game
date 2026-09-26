class_name BotNavigator
extends RefCounted
## Steering-based navigation for bots on the open island.
##
## Goes straight toward the destination and avoids obstacles (trees, rocks,
## walls) and deep water with short "whisker" raycasts. Stuck detection makes
## the bot jump / sidestep, and finally reports failure so the state picks a
## new goal. Phase 4 can swap this for NavigationAgent3D on baked navmeshes
## around towns without touching the states.

const PROBE_INTERVAL := 0.15
const PROBE_LENGTH := 2.2

var brain: BotBrain
var destination := Vector3.ZERO
var active := false
var arrived := false
var failed := false
var arrive_radius := 2.5

var _probe_timer := 0.0
var _avoid_timer := 0.0
var _avoid_side := 1.0
var _stuck_timer := 0.0
var _stuck_count := 0
var _last_pos := Vector3.ZERO
var _ray := PhysicsRayQueryParameters3D.new()


func _init(p_brain: BotBrain) -> void:
	brain = p_brain
	_ray.collision_mask = Layers.WORLD


func set_destination(p: Vector3, radius := 2.5) -> void:
	destination = p
	arrive_radius = radius
	active = true
	arrived = false
	failed = false
	_stuck_count = 0
	_stuck_timer = 0.0
	_last_pos = brain.character.global_position


func stop() -> void:
	active = false


func distance_to_destination() -> float:
	var d := destination - brain.character.global_position
	d.y = 0.0
	return d.length()


## Returns the world-space direction to move this tick (zero when done).
func update(delta: float) -> Vector3:
	if not active:
		return Vector3.ZERO
	var pos := brain.character.global_position
	var to := destination - pos
	to.y = 0.0
	if to.length() < arrive_radius:
		arrived = true
		active = false
		return Vector3.ZERO
	var dir := steer(to.normalized(), delta)

	# Stuck detection.
	_stuck_timer += delta
	if _stuck_timer > 1.5:
		var moved := Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length()
		if moved < 0.8:
			_stuck_count += 1
			brain.character.request_jump()
			_avoid_side = 1.0 if randf() < 0.5 else -1.0
			_avoid_timer = 1.2
			if _stuck_count >= 4:
				failed = true
				active = false
		else:
			_stuck_count = maxi(_stuck_count - 1, 0)
		_stuck_timer = 0.0
		_last_pos = pos
	return dir


## Adjusts a desired direction to avoid obstacles and water.
func steer(dir: Vector3, delta: float) -> Vector3:
	if dir.length_squared() < 0.0001:
		return Vector3.ZERO
	_probe_timer -= delta
	if _avoid_timer > 0.0:
		_avoid_timer -= delta
		return dir.rotated(Vector3.UP, _avoid_side * 0.95)
	if _probe_timer <= 0.0:
		_probe_timer = PROBE_INTERVAL
		if _blocked(dir):
			var left_free := not _blocked(dir.rotated(Vector3.UP, 0.8))
			var right_free := not _blocked(dir.rotated(Vector3.UP, -0.8))
			if left_free and (not right_free or randf() < 0.5):
				_avoid_side = 1.0
			elif right_free:
				_avoid_side = -1.0
			else:
				_avoid_side = 1.0 if randf() < 0.5 else -1.0
				_avoid_timer = 0.9
				return dir.rotated(Vector3.UP, _avoid_side * 1.8)
			_avoid_timer = 0.5
			return dir.rotated(Vector3.UP, _avoid_side * 0.95)
	return dir


func _blocked(dir: Vector3) -> bool:
	var pos := brain.character.global_position
	if Game.world != null:
		var ahead := pos + dir * 3.5
		if Game.world.is_water(ahead.x, ahead.z, 0.9) and not Game.world.is_water(pos.x, pos.z, 0.9):
			return true
	var space := brain.character.get_world_3d().direct_space_state
	for h in [0.55, 1.3]:
		_ray.from = pos + Vector3(0, h, 0)
		_ray.to = _ray.from + dir * PROBE_LENGTH
		var hit := space.intersect_ray(_ray)
		if not hit.is_empty() and (hit.normal as Vector3).y < 0.65:
			return true
	return false
