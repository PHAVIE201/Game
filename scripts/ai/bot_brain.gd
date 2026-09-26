class_name BotBrain
extends Node
## AI controller for a bot. Child of a GameCharacter; drives its intent fields.
##
## Layers:
##   BotPerception  -> what the bot sees (throttled scans)
##   StateMachine   -> what it wants to do (idle / wander / investigate / combat)
##   BotNavigator   -> how it moves there (steering + obstacle avoidance)
##   aiming helpers -> turn rate, aim error, recoil compensation
## The "blackboard" (target, last known position...) lives here so states stay
## small and stateless between bots.

enum MoveMode { WALK, RUN, SPRINT }
enum Look { MOVEMENT, POINT }

var character: GameCharacter
var profile: BotProfile
var fsm: StateMachine
var perception: BotPerception
var nav: BotNavigator
var rng := RandomNumberGenerator.new()

# ---- Blackboard ---------------------------------------------------------------
var target: GameCharacter = null
var target_last_seen_pos := Vector3.ZERO
var target_last_seen_time := -100.0
var target_first_seen_time := -100.0
var time := 0.0
var last_damaged_time := -100.0

# ---- Movement / look requests (set by states every tick) ------------------
var move_mode: int = MoveMode.RUN
var look_mode: int = Look.MOVEMENT
var look_point := Vector3.ZERO
## Direct movement (e.g. combat strafing) used when the navigator is idle.
var direct_move := Vector3.ZERO

var _aim_offset := Vector3.ZERO
var _aim_offset_timer := 0.0
var _weapon_switch_cooldown := 0.0
var _zone_check_timer := 0.0

## Level of detail: bots far from the camera think less often (every 2nd / 4th
## physics tick, with the accumulated delta). Their last inputs stay applied in
## between, so movement and shooting continue smoothly.
var lod_every := 1
var _lod_counter := 0
var _lod_delta := 0.0


func _ready() -> void:
	character = get_parent() as GameCharacter
	rng.randomize()
	var difficulty: int = MatchConfig.Difficulty.NORMAL
	if Game.match_manager != null and Game.match_manager.config != null:
		difficulty = Game.match_manager.config.difficulty
	profile = BotProfile.create(difficulty, rng)
	perception = BotPerception.new(self)
	nav = BotNavigator.new(self)
	fsm = StateMachine.new(self)
	_build_states()
	fsm.change(&"idle")
	character.damaged.connect(_on_damaged)
	_lod_counter = rng.randi() % 4   # stagger bots across ticks


## Register behaviours here. Later phases add: loot, heal, zone, parachute...
func _build_states() -> void:
	fsm.add(&"idle", IdleState.new())
	fsm.add(&"wander", WanderState.new())
	fsm.add(&"investigate", InvestigateState.new())
	fsm.add(&"combat", CombatState.new())
	fsm.add(&"zone", ZoneState.new())
	fsm.add(&"parachute", ParachuteState.new())


func _physics_process(delta: float) -> void:
	if character.is_dead:
		set_physics_process(false)
		return
	if Game.match_manager == null or Game.match_manager.state != MatchManager.State.IN_PROGRESS:
		_idle_inputs()
		return
	if character.is_in_air():
		# Plane / freefall / parachute: only the parachute behaviour runs.
		if not fsm.is_in(&"parachute"):
			fsm.change(&"parachute")
		time += delta
		fsm.update(delta)
		return
	if fsm.is_in(&"parachute"):
		# Just landed.
		(fsm.current as ParachuteState).on_landed()
		fsm.change(&"idle")
	_lod_delta += delta
	_lod_counter += 1
	if _lod_counter < lod_every:
		return
	_lod_counter = 0
	delta = _lod_delta
	_lod_delta = 0.0
	lod_every = _compute_lod()

	time += delta
	perception.update(delta)
	_check_zone(delta)
	fsm.update(delta)

	var dir := Vector3.ZERO
	if nav.active:
		dir = nav.update(delta)
	elif direct_move.length_squared() > 0.01:
		dir = nav.steer(direct_move.normalized(), delta)

	if look_mode == Look.POINT:
		_turn_towards_point(look_point, delta)
	elif dir.length_squared() > 0.01:
		_turn_towards_dir(dir, 0.0, delta)
	_apply_move(dir)


## Heads into the safe zone when outside it, or when the next circle closes
## soon compared with the time needed to walk there.
func _check_zone(delta: float) -> void:
	_zone_check_timer -= delta
	if _zone_check_timer > 0.0:
		return
	_zone_check_timer = 1.0 + rng.randf() * 0.5
	var zone := Game.zone
	if zone == null or not zone.is_active() or fsm.is_in(&"combat") or fsm.is_in(&"zone"):
		return
	var pos := character.global_position
	var go := not zone.is_inside(pos, 3.0)
	if not go and not zone.is_inside_next(pos, 8.0):
		# Be inside the next circle before it starts shrinking.
		var dist := Vector2(pos.x, pos.z).distance_to(zone.next_center) - zone.next_radius
		var travel := dist / GameCharacter.RUN_SPEED
		var deadline := zone.timer if zone.state == ZoneManager.State.WAITING else 0.0
		go = deadline < travel * 1.3 + profile.zone_margin
	if go:
		fsm.change(&"zone")


func _compute_lod() -> int:
	var d2 := Game.get_view_position().distance_squared_to(character.global_position)
	if d2 < 120.0 * 120.0:
		return 1
	if d2 < 300.0 * 300.0:
		return 2
	return 4


func _idle_inputs() -> void:
	character.input_move = Vector2.ZERO
	character.input_fire = false
	character.input_aim = false


# --------------------------------------------------------------------------
# Helpers used by states
# --------------------------------------------------------------------------

## Distance band (m) in which the current weapon works best.
func preferred_range() -> Vector2:
	return range_for(character.weapon_data)


static func range_for(data: WeaponData) -> Vector2:
	match data.category:
		WeaponData.Category.SHOTGUN:
			return Vector2(0.0, 12.0)
		WeaponData.Category.SMG:
			return Vector2(0.0, 40.0)
		WeaponData.Category.PISTOL:
			return Vector2(0.0, 28.0)
		WeaponData.Category.DMR:
			return Vector2(18.0, 350.0)
		WeaponData.Category.SNIPER:
			return Vector2(25.0, 500.0)
		WeaponData.Category.MELEE:
			return Vector2(0.0, 1.4)
		_:
			return Vector2(9.0, 130.0)


## How well a weapon suits a fight at `dist` meters (higher = better).
func weapon_score(w: Weapon, dist: float) -> float:
	if w == null:
		return -1.0
	var data := w.data
	if w.uses_ammo() and w.ammo == 0 and character.inventory.get_ammo(data.ammo_type) == 0:
		return -1.0
	var r := range_for(data)
	var score := 1.0
	if dist < r.x:
		score -= (r.x - dist) / maxf(r.x, 1.0)
	elif dist > r.y:
		score -= minf((dist - r.y) / r.y, 0.9)
	if data.is_pistol():
		score -= 0.25
	return score


## Switches to the most suitable carried weapon for a fight at `dist`.
func select_weapon_for(dist: float, delta: float) -> void:
	_weapon_switch_cooldown -= delta
	if _weapon_switch_cooldown > 0.0 or character.weapon.is_reloading() or character.is_switching_weapon():
		return
	var best := character.active_slot
	var best_score := weapon_score(character.weapon, dist) + 0.15   # prefer keeping
	if character.active_slot < 0:
		best_score = 0.05
	for k in GameCharacter.SLOT_COUNT:
		var sc := weapon_score(character.slots[k], dist)
		if sc > best_score:
			best_score = sc
			best = k
	if best != character.active_slot and best >= 0:
		character.equip_slot(best)
		_weapon_switch_cooldown = 2.5


## Takes out a gun when walking around with bare fists.
func ensure_armed() -> void:
	if character.active_slot < 0 and character.has_any_gun():
		select_weapon_for(60.0, 1.0)


func can_target(c: GameCharacter) -> bool:
	if c.is_player:
		return true
	if Game.match_manager != null and Game.match_manager.config != null:
		return Game.match_manager.config.bots_fight_each_other
	return true


func move_to(p: Vector3, mode: int, radius := 2.5) -> void:
	move_mode = mode
	direct_move = Vector3.ZERO
	nav.set_destination(p, radius)


func stop_moving() -> void:
	nav.stop()
	direct_move = Vector3.ZERO


func look_at_point(p: Vector3) -> void:
	look_mode = Look.POINT
	look_point = p


func look_along_movement() -> void:
	look_mode = Look.MOVEMENT


func is_target_visible() -> bool:
	return target != null and time - target_last_seen_time < 0.45


func clear_target() -> void:
	target = null


## Landing spot for the parachute: next to a building (loot!) not too far
## from the flight line, towns more likely than lone farms.
func choose_drop_target(plane: AirPlane) -> Vector3:
	var world := Game.world
	var candidates: Array[Vector3] = []
	var weights: Array[float] = []
	for b in world.settlements.buildings:
		var c := Vector3(b.center.x, b.floor_y, b.center.y)
		if plane.lateral_distance(c) > 520.0:
			continue
		candidates.append(c)
		weights.append(1.5 if b.town != "" else 1.0)
	if candidates.is_empty() or rng.randf() < 0.08:
		# A quiet spot in the countryside.
		for k in 30:
			var along := rng.randf_range(0.2, 0.8) * plane.length
			var side := Vector3(-plane.dir.z, 0.0, plane.dir.x) * rng.randf_range(-450.0, 450.0)
			var p := plane.point_at(along) + side
			if world.is_walkable(p.x, p.z):
				return Vector3(p.x, world.get_height(p.x, p.z), p.z)
		return plane.point_at(plane.length * 0.5)
	var total := 0.0
	for w in weights:
		total += w
	var r := rng.randf() * total
	var pick := candidates[0]
	for k in candidates.size():
		r -= weights[k]
		if r <= 0.0:
			pick = candidates[k]
			break
	# Land next to the building, not on its roof.
	var ang := rng.randf() * TAU
	return pick + Vector3(cos(ang), 0.0, sin(ang)) * rng.randf_range(9.0, 14.0)


## Random walkable destination inside the safe zone, biased toward towns
## and toward the next circle (where everybody ends up meeting).
func pick_wander_destination() -> Vector3:
	var pos := character.global_position
	if Game.world == null:
		return pos
	var zone := Game.zone
	var zone_on := zone != null and zone.is_active()
	for attempt in 15:
		var roll := rng.randf()
		var p: Vector3
		if roll < 0.25 and not Game.world.get_towns().is_empty():
			var towns := Game.world.get_towns()
			var c: Vector2 = towns[rng.randi() % towns.size()].center
			if Vector2(pos.x, pos.z).distance_to(c) > 700.0:
				continue
			p = Vector3(c.x + rng.randf_range(-35.0, 35.0), 0.0, c.y + rng.randf_range(-35.0, 35.0))
		elif roll < 0.55 and zone_on:
			p = zone.random_point_in_next(rng, 0.1)
		else:
			var ang := rng.randf() * TAU
			var r := rng.randf_range(50.0, 180.0)
			p = pos + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		if zone_on and not zone.is_inside(p, 10.0) and attempt < 12:
			continue
		if Game.world.is_walkable(p.x, p.z):
			p.y = Game.world.get_height(p.x, p.z)
			return p
	return pos


# --------------------------------------------------------------------------
# Perception / events
# --------------------------------------------------------------------------

func on_enemy_seen(c: GameCharacter) -> void:
	var switch := target == null or target.is_dead or target == c or not is_target_visible()
	if not switch and target != null:
		# Switch if the new enemy is much closer.
		var d_new := character.global_position.distance_to(c.global_position)
		var d_old := character.global_position.distance_to(target.global_position)
		switch = d_new < d_old * 0.5
	if not switch:
		return
	if target != c:
		target_first_seen_time = time
	target = c
	target_last_seen_pos = c.global_position
	target_last_seen_time = time
	if not fsm.is_in(&"combat"):
		fsm.change(&"combat")


func on_heard_shot(pos: Vector3, shooter: GameCharacter, radius: float) -> void:
	if shooter == character or character.is_dead or fsm.is_in(&"combat") or character.is_in_air():
		return
	if not can_target(shooter):
		return
	var d := character.global_position.distance_to(pos)
	if d > radius or rng.randf() > profile.hearing_chance:
		return
	# Sound position is imprecise, more so from far away.
	var err := d * 0.12
	var guess := pos + Vector3(rng.randf_range(-err, err), 0.0, rng.randf_range(-err, err))
	fsm.change(&"investigate", {"pos": guess})


func _on_damaged(info: DamageInfo) -> void:
	last_damaged_time = time
	var attacker := info.attacker as GameCharacter
	if attacker == null or attacker.is_dead or attacker == character or not can_target(attacker):
		return
	if target == null or target.is_dead or not is_target_visible():
		if target != attacker:
			target_first_seen_time = time
		target = attacker
		# The bot knows roughly where the shot came from.
		target_last_seen_pos = attacker.global_position
		target_last_seen_time = time - 1.0
		if not fsm.is_in(&"combat") and not character.is_in_air():
			fsm.change(&"combat")


# --------------------------------------------------------------------------
# Aiming
# --------------------------------------------------------------------------

## Point to aim at on the target, including a human-like error that shrinks
## the longer the bot keeps the target in sight.
func get_aim_point(delta: float) -> Vector3:
	var base := target.get_hitbox_center() if is_target_visible() else target_last_seen_pos + Vector3(0, 1.1, 0)
	_aim_offset_timer -= delta
	if _aim_offset_timer <= 0.0:
		_aim_offset_timer = rng.randf_range(0.3, 0.6)
		var dist := character.get_eye_position().distance_to(base)
		# Error shrinks while the bot keeps the target in sight ("zeroing in").
		var engage := clampf((time - target_first_seen_time) / 2.5, 0.0, 1.0)
		var err := profile.aim_error * lerpf(1.6, 0.6, engage)
		err *= 1.0 + Vector2(target.velocity.x, target.velocity.z).length() * 0.1
		if time - last_damaged_time < 0.6:
			err *= 1.8   # flinch when hit
		# Normal distribution around the target, sigma = angular error * distance.
		var sigma := dist * tan(err)
		_aim_offset = Vector3(rng.randfn(0.0, sigma), rng.randfn(0.0, sigma * 0.8), rng.randfn(0.0, sigma))
	return base + _aim_offset


## Angle (radians) between where the bot looks and where it wants to look.
func aim_error_to(p: Vector3) -> float:
	var want := (p - character.get_eye_position()).normalized()
	var have := character.get_aim_direction()
	return have.angle_to(want)


func _turn_towards_point(p: Vector3, delta: float) -> void:
	var to := p - character.get_eye_position()
	var flat := Vector2(to.x, to.z).length()
	var pitch := atan2(to.y, maxf(flat, 0.001))
	# Compensate part of the weapon recoil (skilled bots pull down more).
	pitch -= deg_to_rad(character.weapon.recoil_pitch) * profile.recoil_control
	_turn_towards_dir(to, pitch, delta)


func _turn_towards_dir(dir: Vector3, pitch: float, delta: float) -> void:
	var target_yaw := atan2(-dir.x, -dir.z)
	var diff := wrapf(target_yaw - character.aim_yaw, -PI, PI)
	var max_step := profile.turn_speed * delta
	# Ease in: fast for big turns, precise for small corrections.
	var step := clampf(diff * minf(1.0, 10.0 * delta) + signf(diff) * minf(absf(diff), max_step * 0.35), -max_step, max_step)
	character.aim_yaw = wrapf(character.aim_yaw + step, -PI, PI)
	var pdiff := pitch - character.aim_pitch
	character.aim_pitch += clampf(pdiff * minf(1.0, 10.0 * delta), -max_step, max_step)


func _apply_move(dir: Vector3) -> void:
	var yaw := character.aim_yaw
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	character.input_move = Vector2(dir.dot(right), dir.dot(fwd))
	character.input_sprint = move_mode == MoveMode.SPRINT and dir.length_squared() > 0.01
	character.input_walk = move_mode == MoveMode.WALK
	# Bots aim where they look (their shots follow their current aim + spread).
	character.aim_point = character.get_eye_position() + character.get_aim_direction() * 200.0
	character.has_aim_point = look_mode == Look.POINT
	if look_mode == Look.POINT:
		character.aim_point = character.get_eye_position() + character.get_aim_direction() * character.get_eye_position().distance_to(look_point)
