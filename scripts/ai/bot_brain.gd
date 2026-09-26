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
## Buildings already searched for loot (key: center Vector2).
var searched := {}
var _throw_timer := 0.0
var _throw_yaw := 0.0
var _throw_pitch := 0.0
var _heal_check_timer := 0.0
## Last time a grenade / smoke was thrown (cooldowns).
var last_throw_time := -100.0

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
	fsm.add(&"loot", LootState.new())
	fsm.add(&"search", SearchState.new())
	fsm.add(&"heal", HealState.new())


func _physics_process(delta: float) -> void:
	if not Prof.enabled:
		_think(delta)
		return
	var t0 := Time.get_ticks_usec()
	_think(delta)
	Prof.add(&"bot_brain", t0)


func _think(delta: float) -> void:
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
		# Just landed: the building next to us has loot.
		(fsm.current as ParachuteState).on_landed()
		fsm.change(&"loot", {"budget": rng.randf_range(60.0, 110.0)})
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
	_check_heal(delta)
	fsm.update(delta)
	_update_throw(delta)

	var dir := Vector3.ZERO
	if character.throwing_item != &"":
		pass   # stand still while throwing (the throw inherits our velocity)
	elif nav.active:
		dir = nav.update(delta)
	elif direct_move.length_squared() > 0.01:
		dir = nav.steer(direct_move.normalized(), delta)

	if look_mode == Look.POINT:
		_turn_towards_point(look_point, delta)
	elif dir.length_squared() > 0.01:
		_turn_towards_dir(dir, 0.0, delta)
	_apply_move(dir)


## > 0 when it is time to walk into the next circle: the walk (with a margin
## that grows in the later, deadlier phases) takes longer than the time left
## before the circle has finished closing on us.
func zone_urgency() -> float:
	var zone := Game.zone
	if zone == null or not zone.is_active():
		return -1.0
	var pos := character.global_position
	var dist := Vector2(pos.x, pos.z).distance_to(zone.next_center) - zone.next_radius
	if dist <= 0.0:
		return -1.0
	var travel := dist / GameCharacter.SPRINT_SPEED
	var phase_k := clampf(zone.phase / 3.0, 0.3, 1.0)
	return travel * 1.25 + profile.zone_margin * phase_k - zone.time_until_closed()


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
		go = zone_urgency() > 0.0
	if go:
		# Early zones hurt little: badly equipped bots loot a house on the way.
		if zone.phase <= 1 and needs_gear() and zone_urgency() < 45.0 and not fsm.is_in(&"search") \
				and not pick_building_to_search(true).is_empty():
			fsm.change(&"search", {"toward_zone": true})
		else:
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


## A gun with rounds in it or in the backpack.
func has_usable_gun() -> bool:
	for w in character.slots:
		if w != null and (w.ammo > 0 or character.inventory.get_ammo(w.data.ammo_type) > 0):
			return true
	return false


## Out of combat: hold the best gun and keep it loaded.
func maintain_weapon() -> void:
	if character.is_switching_weapon() or character.is_using_item() or character.throwing_item != &"":
		return
	if character.active_slot < 0 or weapon_score(character.weapon, 60.0) < 0.0:
		if has_usable_gun():
			select_weapon_for(60.0, 1.0)
		return
	var w := character.weapon
	if w.uses_ammo() and not w.is_reloading() and w.ammo < w.data.magazine_size * 0.6 \
			and character.inventory.get_ammo(w.data.ammo_type) > 0:
		character.request_reload()


## Heal / boost item to use now (&"" = nothing sensible).
func pick_heal_or_boost() -> StringName:
	var c := character
	if c.health < 75.0:
		var h := c.pick_heal()
		if h != &"":
			return h
	if c.boost < 45.0 and c.health < 98.0:
		for id in [&"energy_drink", &"painkiller"]:
			if c.can_use_item(id):
				return id
	return &""


## Out of combat and hurt: heal (unless the zone needs us to move now).
func _check_heal(delta: float) -> void:
	_heal_check_timer -= delta
	if _heal_check_timer > 0.0:
		return
	_heal_check_timer = 1.0 + rng.randf() * 0.5
	if fsm.is_in(&"combat") or fsm.is_in(&"heal") or character.is_using_item():
		return
	if character.health > 80.0 and character.boost > 30.0:
		return
	if zone_urgency() > -10.0 and Game.zone != null and not Game.zone.is_inside(character.global_position):
		return
	if pick_heal_or_boost() != &"":
		fsm.change(&"heal")


## Throws a grenade so that it lands near `target` (tries a few arcs with the
## trajectory prediction). Returns false when no arc lands close enough.
func throw_grenade_at(id: StringName, spot: Vector3, max_error := 5.0) -> bool:
	var c := character
	if Game.throwables == null or c.inventory.get_count(id) <= 0 or c.throwing_item != &"" or c.is_in_air():
		return false
	var to := spot - c.global_position
	var yaw := atan2(-to.x, -to.z)
	var old_yaw := c.aim_yaw
	var old_pitch := c.aim_pitch
	c.aim_yaw = yaw
	# Where it is when it goes off: smoke pops after its fuse, a frag is cooked
	# for the wind-up only.
	var fuse := ThrowableSystem.SMOKE_FUSE if id == &"grenade_smoke" else ThrowableSystem.FRAG_FUSE - 0.45
	var best_pitch := 0.3
	var best_err := INF
	var candidates: Array[float] = []
	for k in 12:
		candidates.append(-0.25 + k * 0.08)
	for pass_k in 2:
		for pitch in candidates:
			c.aim_pitch = pitch
			# Same time step as the real flight so bounces match.
			var pts := Game.throwables.predict(c.get_throw_origin(), c.get_throw_velocity(), fuse, 8,
				1.0 / Engine.physics_ticks_per_second)
			var err := (pts[pts.size() - 1] as Vector3).distance_to(spot)
			if err < best_err:
				best_err = err
				best_pitch = pitch
		# Refine around the best coarse angle.
		candidates = [best_pitch - 0.05, best_pitch - 0.025, best_pitch + 0.025, best_pitch + 0.05]
	c.aim_yaw = old_yaw
	c.aim_pitch = old_pitch
	if best_err > max_error or not c.begin_throw(id):
		return false
	# Turn toward the throw during the wind-up, release along the planned arc.
	var dir := Vector3(-sin(yaw) * cos(best_pitch), sin(best_pitch), -cos(yaw) * cos(best_pitch))
	look_at_point(c.get_eye_position() + dir * 40.0)
	stop_moving()
	_throw_yaw = yaw
	_throw_pitch = best_pitch
	_throw_timer = 0.45
	last_throw_time = time
	return true


func _update_throw(delta: float) -> void:
	if character.throwing_item == &"":
		return
	_throw_timer -= delta
	if _throw_timer <= 0.0:
		character.aim_yaw = _throw_yaw
		character.aim_pitch = _throw_pitch
		character.release_throw()


## A nearby spot hidden (at crouch height) from `threat_eye`, or Vector3.INF.
## Samples a ring around the bot; prefers close spots that do not move away
## from the enemy much.
func find_cover(threat_eye: Vector3) -> Vector3:
	var world := Game.world
	var pos := character.global_position
	var best := Vector3.INF
	var best_score := INF
	var d_now := pos.distance_to(threat_eye)
	var offset := rng.randf() * TAU
	for k in 12:
		var ang := offset + k * TAU / 12.0
		var r := rng.randf_range(2.5, 10.0)
		var p := pos + Vector3(cos(ang), 0.0, sin(ang)) * r
		if not world.is_walkable(p.x, p.z) or world.settlements.is_inside_building(p, 0.5):
			continue
		p.y = world.get_height(p.x, p.z)
		if Game.projectiles.has_line_of_sight(threat_eye, p + Vector3(0, 0.95, 0)):
			continue
		var score := r + maxf(p.distance_to(threat_eye) - d_now, 0.0) * 0.6
		if score < best_score:
			best_score = score
			best = p
	return best


## Still missing important gear (a usable gun, ammo, armor, heals)?
func needs_gear() -> bool:
	if not has_usable_gun():
		return true
	var inv := character.inventory
	var ammo := 0
	for w in character.slots:
		if w != null:
			ammo += w.ammo + inv.get_ammo(w.data.ammo_type)
	if ammo < 60:
		return true
	if inv.vest == &"" or inv.helmet == &"":
		return true
	return inv.get_count(&"bandage") + inv.get_count(&"first_aid") * 3 + inv.get_count(&"medkit") * 5 < 5


func mark_searched(b: Dictionary) -> void:
	searched[b.center] = true


## Nearest building (inside the zone) not searched yet, or {}. With
## `toward_zone`, only buildings that bring us clearly closer to the next circle.
func pick_building_to_search(toward_zone := false) -> Dictionary:
	var pos := character.global_position
	var zone := Game.zone
	var best: Dictionary = {}
	var best_d := 420.0
	var my_zone_d := INF
	if zone != null and zone.is_active():
		my_zone_d = Vector2(pos.x, pos.z).distance_to(zone.next_center)
	for b in Game.world.settlements.buildings:
		if searched.has(b.center):
			continue
		var c := Vector3(b.center.x, b.floor_y, b.center.y)
		if zone != null and zone.is_active() and not zone.is_inside(c, 15.0):
			continue
		if toward_zone and (b.center as Vector2).distance_to(zone.next_center) > my_zone_d - 60.0:
			continue
		var d := pos.distance_to(c) * rng.randf_range(0.85, 1.15)
		if d < best_d:
			best_d = d
			best = b
	return best


## Something valuable within `radius` (opportunistic looting).
func sees_loot(radius: float, min_value: float) -> bool:
	var p := BotLoot.best_pickup(character, radius, {})
	return p != null and BotLoot.value(character, p) >= min_value


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
## from the flight line. Bigger buildings and towns are more attractive,
## spots other bots already picked much less (except for hot-droppers).
func choose_drop_target(plane: AirPlane) -> Vector3:
	var world := Game.world
	var claims: Dictionary = Game.match_manager.drop_claims if Game.match_manager != null else {}
	var candidates: Array[Vector3] = []
	var weights: Array[float] = []
	var keys: Array[Vector2] = []
	for b in world.settlements.buildings:
		var c := Vector3(b.center.x, b.floor_y, b.center.y)
		var lateral := plane.lateral_distance(c)
		if lateral > 650.0:
			continue
		var w := 1.4 if b.town != "" else 1.0
		match int(b.type):
			Settlements.BType.WAREHOUSE:
				w *= 1.6
			Settlements.BType.LONGHOUSE:
				w *= 1.3
			Settlements.BType.SHED:
				w *= 0.4
		# Closer to the flight line = faster landing.
		w *= 1.2 - lateral / 1000.0
		var n := _claims_near(claims, b.center)
		w = w * (1.0 + n * 0.8) if profile.hot_dropper else w / (1.0 + n * n * 1.5)
		candidates.append(c)
		weights.append(w)
		keys.append(b.center)
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
	var key := keys[0]
	for k in candidates.size():
		r -= weights[k]
		if r <= 0.0:
			pick = candidates[k]
			key = keys[k]
			break
	claims[key] = int(claims.get(key, 0)) + 1
	# Land next to the building, not on its roof.
	var ang := rng.randf() * TAU
	return pick + Vector3(cos(ang), 0.0, sin(ang)) * rng.randf_range(9.0, 14.0)


## Bots that already chose a building within 40 m of `center`.
static func _claims_near(claims: Dictionary, center: Vector2) -> int:
	var n := 0
	for k: Vector2 in claims:
		if k.distance_squared_to(center) < 40.0 * 40.0:
			n += int(claims[k])
	return n


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
	# Running from the zone: ignore far enemies instead of turning around.
	if fsm.is_in(&"zone") and zone_urgency() > 0.0 and time - last_damaged_time > 2.0:
		if character.global_position.distance_to(c.global_position) > 25.0:
			return
	# Bare hands: only fight when the enemy is right here (or hurt us).
	if not has_usable_gun() and not fsm.is_in(&"combat"):
		var d := character.global_position.distance_to(c.global_position)
		if d > 7.0 and time - last_damaged_time > 3.0:
			return
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
	if not has_usable_gun():
		# Unarmed: stay away from the shooting.
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
		if dist > 60.0 and character.get_scope_zoom() >= 2.0:
			err *= 0.75   # a scope helps at range
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
