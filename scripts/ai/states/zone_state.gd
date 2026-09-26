class_name ZoneState
extends BotState
## Run into the safe zone (the next circle), sprinting when it is urgent.

var _retries := 0
var _timeout := 0.0


func enter(_params: Dictionary) -> void:
	_retries = 0
	_pick()


func _pick() -> void:
	var zone := Game.zone
	if zone == null:
		brain.fsm.change(&"idle")
		return
	var dest := zone.random_point_in_next(brain.rng, 0.35)
	brain.move_to(dest, _mode(), 6.0)
	brain.look_along_movement()
	get_character().request_stance(GameCharacter.Stance.STAND)
	_timeout = 150.0


func _mode() -> int:
	var zone := Game.zone
	var c := get_character()
	if not zone.is_inside(c.global_position) or zone.time_until_closed() < 60.0:
		return BotBrain.MoveMode.SPRINT
	return BotBrain.MoveMode.RUN


func update(delta: float) -> void:
	_timeout -= delta
	brain.move_mode = _mode()
	if brain.nav.arrived:
		brain.fsm.change(&"idle")
	elif brain.nav.failed or _timeout <= 0.0:
		_retries += 1
		if _retries > 4:
			brain.fsm.change(&"wander")
		else:
			_pick()
