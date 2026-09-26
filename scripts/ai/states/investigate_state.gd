class_name InvestigateState
extends BotState
## Go check a suspicious position (gunshot heard, last known enemy position),
## then look around before giving up.

var _pos := Vector3.ZERO
var _timeout := 0.0
var _search_time := 0.0
var _look_timer := 0.0


func enter(params: Dictionary) -> void:
	_pos = params.get("pos", get_character().global_position)
	var dist := get_character().global_position.distance_to(_pos)
	brain.move_to(_pos, BotBrain.MoveMode.RUN if dist > 45.0 else BotBrain.MoveMode.WALK, 6.0)
	brain.look_along_movement()
	_timeout = 30.0
	_search_time = 0.0
	get_character().input_fire = false


func update(delta: float) -> void:
	var c := get_character()
	_timeout -= delta
	if brain.nav.active:
		# Sneak when getting close.
		if brain.nav.distance_to_destination() < 25.0 and c.stance == GameCharacter.Stance.STAND and brain.rng.randf() < 0.01:
			c.request_stance(GameCharacter.Stance.CROUCH)
		if _timeout <= 0.0 or brain.nav.failed:
			brain.fsm.change(&"wander")
		return
	# Arrived: scan the area for a few seconds.
	_search_time += delta
	_look_timer -= delta
	if _look_timer <= 0.0:
		_look_timer = brain.rng.randf_range(0.6, 1.4)
		var ang := brain.rng.randf() * TAU
		brain.look_at_point(c.get_eye_position() + Vector3(cos(ang), 0.0, sin(ang)) * 15.0)
	if _search_time > 4.0 or _timeout <= 0.0:
		c.request_stance(GameCharacter.Stance.STAND)
		brain.fsm.change(&"wander")
