class_name WanderState
extends BotState
## Walk / run to random destinations (towns, the player's area, nearby spots).

var _timeout := 0.0
var _retries := 0
var _loot_check := 0.0


func enter(params: Dictionary) -> void:
	_retries = 0
	_loot_check = 2.5
	if brain.needs_gear() and not params.get("no_search", false):
		brain.fsm.change(&"search")
		return
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
	_loot_check -= delta
	if _loot_check <= 0.0:
		_loot_check = 2.5
		brain.maintain_weapon()
		# Grab things on the way (bodies, houses we walk past).
		if brain.sees_loot(18.0, 0.3):
			brain.fsm.change(&"loot", {"budget": 25.0})
			return
	if brain.nav.arrived:
		brain.fsm.change(&"idle")
	elif brain.nav.failed or _timeout <= 0.0:
		_retries += 1
		if _retries > 3:
			brain.fsm.change(&"idle")
		else:
			_pick()
