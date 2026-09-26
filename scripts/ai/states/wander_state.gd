class_name WanderState
extends BotState
## Walk / run to random destinations (towns, the player's area, nearby spots).

var _timeout := 0.0
var _retries := 0


func enter(_params: Dictionary) -> void:
	_retries = 0
	_pick()


func _pick() -> void:
	var mode := BotBrain.MoveMode.RUN
	var roll := brain.rng.randf()
	if roll < 0.25:
		mode = BotBrain.MoveMode.WALK
	elif roll > 0.85:
		mode = BotBrain.MoveMode.SPRINT
	brain.move_to(brain.pick_wander_destination(), mode, 3.0)
	brain.look_along_movement()
	get_character().request_stance(GameCharacter.Stance.STAND)
	_timeout = 90.0


func update(delta: float) -> void:
	_timeout -= delta
	if brain.nav.arrived:
		brain.fsm.change(&"idle")
	elif brain.nav.failed or _timeout <= 0.0:
		_retries += 1
		if _retries > 3:
			brain.fsm.change(&"idle")
		else:
			_pick()
