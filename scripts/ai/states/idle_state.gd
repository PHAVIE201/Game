class_name IdleState
extends BotState
## Stand still for a moment and look around, then go wander.

var _timer := 0.0
var _look_timer := 0.0


func enter(_params: Dictionary) -> void:
	brain.stop_moving()
	_timer = brain.rng.randf_range(1.0, 3.5)
	_look_timer = 0.0
	var c := get_character()
	c.input_fire = false
	c.input_aim = false
	if c.stance == GameCharacter.Stance.PRONE:
		c.request_stance(GameCharacter.Stance.STAND)


func update(delta: float) -> void:
	_timer -= delta
	_look_timer -= delta
	if _look_timer <= 0.0:
		_look_timer = brain.rng.randf_range(0.8, 2.0)
		var c := get_character()
		var ang := c.aim_yaw + brain.rng.randf_range(-1.6, 1.6)
		brain.look_at_point(c.get_eye_position() + Vector3(-sin(ang), 0.0, -cos(ang)) * 20.0)
	if _timer <= 0.0:
		brain.fsm.change(&"wander")
