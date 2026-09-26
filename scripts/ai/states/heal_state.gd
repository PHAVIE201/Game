class_name HealState
extends BotState
## Patch up: use heals / boosts one after another, crouched, looking around.
## Optionally pops a smoke grenade toward a threat first.

var _look_timer := 0.0


func enter(params: Dictionary) -> void:
	var c := get_character()
	brain.stop_moving()
	c.input_fire = false
	c.input_aim = false
	if params.has("smoke_toward"):
		var threat: Vector3 = params.smoke_toward
		var dir := threat - c.global_position
		dir.y = 0.0
		var spot := c.global_position + dir.normalized() * minf(5.0, dir.length() * 0.5)
		brain.throw_grenade_at(&"grenade_smoke", spot, 4.0)
	if brain.rng.randf() < 0.7:
		c.request_stance(GameCharacter.Stance.CROUCH)
	_look_timer = 0.0


func exit() -> void:
	get_character().cancel_item_use()


func update(delta: float) -> void:
	var c := get_character()
	_look_timer -= delta
	if _look_timer <= 0.0:
		_look_timer = brain.rng.randf_range(0.8, 1.8)
		var ang := c.aim_yaw + brain.rng.randf_range(-1.8, 1.8)
		brain.look_at_point(c.get_eye_position() + Vector3(-sin(ang), 0.0, -cos(ang)) * 20.0)
	if c.throwing_item != &"" or c.is_using_item():
		return
	var item := brain.pick_heal_or_boost()
	if item == &"" or brain.fsm.time_in_state > 45.0:
		c.request_stance(GameCharacter.Stance.STAND)
		brain.fsm.change(&"idle")
		return
	c.use_item(item)
