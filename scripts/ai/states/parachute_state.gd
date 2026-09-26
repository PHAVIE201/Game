class_name ParachuteState
extends BotState
## Drop from the plane: pick a landing spot near the flight line, jump at the
## right moment, then steer the freefall and the parachute onto the spot.

var target := Vector3.ZERO
## Horizontal distance between the landing point and the chosen spot (m).
var landing_miss := -1.0
var _jump_at := 0.0


func enter(_params: Dictionary) -> void:
	var c := get_character()
	var plane := c.plane
	if plane == null:
		target = c.global_position
		return
	target = brain.choose_drop_target(plane)
	var door := plane.door_range()
	var along := plane.project(target)
	var lateral := plane.lateral_distance(target)
	# Jump a little before passing abeam of the spot, glide the rest.
	_jump_at = along - lateral * 0.35 - 40.0 + brain.rng.randf_range(-40.0, 40.0)
	_jump_at = clampf(_jump_at, door.x + 10.0, maxf(door.y - 10.0, door.x + 10.0))


func update(delta: float) -> void:
	var c := get_character()
	match c.air_state:
		GameCharacter.AirState.PLANE:
			if c.plane != null and c.plane.doors_open and c.plane.progress >= _jump_at:
				c.request_jump()
		GameCharacter.AirState.FREEFALL, GameCharacter.AirState.PARACHUTE:
			steer_to(c, target, delta)
		_:
			pass


func on_landed() -> void:
	var c := get_character()
	c.input_move = Vector2.ZERO
	c.aim_pitch = 0.0
	landing_miss = Vector2(c.global_position.x - target.x, c.global_position.z - target.z).length()


## Steers a falling character onto `target` (freefall, then parachute).
static func steer_to(c: GameCharacter, spot: Vector3, delta: float) -> void:
	var chute := c.air_state == GameCharacter.AirState.PARACHUTE
	var to := spot - c.global_position
	to.y = 0.0
	var d := to.length()
	if d > 0.5:
		var yaw := atan2(-to.x, -to.z)
		c.aim_yaw = lerp_angle(c.aim_yaw, yaw, clampf(delta * 2.5, 0.0, 1.0))
	var h := c.height_above_ground()
	var glide_ratio := GameCharacter.CHUTE_SPEED / GameCharacter.CHUTE_FALL
	if not chute:
		# How far a normal freefall + parachute from the automatic height reaches.
		var fall_time := maxf(h - GameCharacter.CHUTE_AUTO_HEIGHT, 0.0) / GameCharacter.FREEFALL_FALL
		var reach := fall_time * GameCharacter.FREEFALL_SPEED + GameCharacter.CHUTE_AUTO_HEIGHT * glide_ratio * 0.85
		if d > reach:
			c.request_jump()   # open now and glide further
		c.input_move = Vector2(0.0, 1.0) if d > 12.0 else Vector2.ZERO
		# Dive (look down) when the spot is well within reach.
		c.aim_pitch = -1.0 if d < reach * 0.6 else -0.15
	else:
		c.aim_pitch = -0.3
		var glide := h * glide_ratio
		if d < 8.0:
			c.input_move = Vector2(0.0, -1.0)
		elif d > glide * 0.8:
			c.input_move = Vector2.ZERO          # best glide ratio
		else:
			c.input_move = Vector2(0.0, 1.0)     # lose height faster, circle in
