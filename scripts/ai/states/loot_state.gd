class_name LootState
extends BotState
## Go to the most valuable item nearby (BotLoot), pick it up, repeat until
## nothing worth the walk is left or the time budget is used up.

const RADIUS := 32.0
const TAKE_DIST := 1.8

## Counters for the match simulation report.
static var stats := {"taken": 0, "refused": 0, "nav_failed": 0, "timeout": 0, "no_target": 0}

var _target: LootManager.Pickup = null
var _ignore := {}
var _timeout := 0.0
var _budget := 0.0


func enter(params: Dictionary) -> void:
	_budget = float(params.get("budget", brain.rng.randf_range(45.0, 90.0)))
	_ignore.clear()
	get_character().input_fire = false
	get_character().input_aim = false
	_pick()


func exit() -> void:
	_target = null


func _pick() -> void:
	var c := get_character()
	_target = BotLoot.best_pickup(c, RADIUS, _ignore)
	if _target == null:
		stats.no_target += 1
		# The house here is done.
		var here := Game.world.settlements.building_at(c.global_position, 10.0)
		if not here.is_empty():
			brain.mark_searched(here)
		brain.fsm.change(&"idle")
		return
	var d := c.global_position.distance_to(_target.pos)
	brain.move_to(_target.pos, BotBrain.MoveMode.RUN if d > 10.0 else BotBrain.MoveMode.WALK, 1.0)
	brain.look_along_movement()
	c.request_stance(GameCharacter.Stance.STAND)
	_timeout = 15.0 + d / 2.5


func update(delta: float) -> void:
	var c := get_character()
	_budget -= delta
	_timeout -= delta
	brain.maintain_weapon()
	if _target == null or not _target.alive:
		_pick()
		return
	var off := _target.pos - c.global_position
	var flat := Vector2(off.x, off.z).length()
	if flat < TAKE_DIST and absf(off.y) < 1.7:
		var code := Game.loot.take(c, _target)
		if code != LootManager.Take.OK and _target != null:
			_ignore[_target.get_instance_id()] = true
			stats.refused += 1
		else:
			stats.taken += 1
		brain.stop_moving()
		if _budget <= 0.0:
			brain.fsm.change(&"idle")
		else:
			_pick()
		return
	if brain.nav.failed or _timeout <= 0.0:
		if brain.nav.failed:
			stats.nav_failed += 1
		else:
			stats.timeout += 1
		_ignore[_target.get_instance_id()] = true
		_pick()
	elif brain.nav.arrived:
		# Close but not close enough (item on a table, a crate...).
		brain.move_to(_target.pos, BotBrain.MoveMode.WALK, 0.5)
