class_name GameCharacter
extends CharacterBody3D
## One participant of the match (human player OR bot).
##
## The character only knows HOW to move / shoot. WHAT to do comes from a
## controller that writes the "intent" fields below every frame:
##   - PlayerController (keyboard + mouse)
##   - BotBrain (AI state machine)
## This keeps player and bots on exactly the same rules and lets later phases
## (parachuting, vehicles, inventory, healing...) be added once for everyone.

enum Stance { STAND, CROUCH, PRONE }

signal died(info: DamageInfo)
signal damaged(info: DamageInfo)
signal stance_changed(stance: int)

const RADIUS := 0.3
const HEIGHTS := [1.75, 1.15, 0.62]
const EYE_HEIGHTS := [1.62, 1.12, 0.38]

const RUN_SPEED := 4.8
const SPRINT_SPEED := 6.4
const WALK_SPEED := 1.9
const CROUCH_SPEED := 2.4
const PRONE_SPEED := 1.05
const SWIM_SPEED := 2.3
const GROUND_ACCEL := 11.0
const AIR_ACCEL := 1.5
const GRAVITY := 20.0
const JUMP_VELOCITY := 6.3
## Swim when the water is this deep above the feet (m).
const SWIM_ENTER := 1.25
const SWIM_EXIT := 1.05

@export var weapon_data: WeaponData
@export var is_player := false
@export var display_name := "Người chơi"

## Set before the node enters the tree to choose clothes (random otherwise).
var outfit: Dictionary = {}

# ---- Intent (written by the controller) ------------------------------------
var input_move := Vector2.ZERO     ## x = right, y = forward, length <= 1
var input_sprint := false
var input_walk := false
var input_aim := false
var input_fire := false
var aim_yaw := 0.0                 ## radians, 0 = looking toward -Z (north)
var aim_pitch := 0.0               ## radians, + = up
## World point the crosshair / bot is aiming at (bullets fly from the muzzle toward it).
var aim_point := Vector3.ZERO
var has_aim_point := false

# ---- State -----------------------------------------------------------------
var max_health := 100.0
var health := 100.0
var is_dead := false
var stance: int = Stance.STAND
var is_swimming := false
var is_sprinting := false
var kills := 0
var damage_dealt := 0.0
var spawn_time_msec := 0
var death_time_msec := 0
var inventory := Inventory.new()
var weapon: Weapon
var model: CharacterModel
var hitboxes: CharacterHitboxes
var last_attacker: GameCharacter = null
## Time of the last shot (bots spot shooting enemies from further away).
var last_fire_msec := -100000
## Simulation LOD: bots far from the camera skip move_and_slide() and simply
## follow the terrain (see _move_simple). Switched automatically.
var sim_simple := false
const SIMPLE_ENTER_DIST := 230.0
const SIMPLE_EXIT_DIST := 200.0

var _jump_requested := false
var _reload_requested := false
var _stance_request := -1
var _collision: CollisionShape3D
var _capsule: CapsuleShape3D
var _anim_accum := 0.0
## Seconds without floor contact (small bumps should not trigger the jump pose).
var _air_time := 0.0
var _prev_pos := Vector3.ZERO
var _curr_pos := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _ray := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	_rng.randomize()
	if weapon_data == null:
		weapon_data = load("res://resources/weapons/k7_rifle.tres")
	collision_layer = Layers.CHARACTERS
	collision_mask = Layers.CHARACTER_MASK
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.6
	floor_constant_speed = true
	floor_block_on_wall = false

	_collision = $CollisionShape3D
	_capsule = CapsuleShape3D.new()
	_capsule.radius = RADIUS
	_collision.shape = _capsule
	_apply_stance_shape()

	model = $Model
	if outfit.is_empty():
		outfit = CharacterModel.player_outfit() if is_player else CharacterModel.random_outfit(_rng)
	model.build(outfit, weapon_data.model, is_player)
	model.set_step_callback(_on_footstep)
	hitboxes = CharacterHitboxes.new(model)

	weapon = Weapon.new(weapon_data)
	weapon.reload_started.connect(_on_reload_started)
	weapon.reload_finished.connect(_on_reload_finished)
	weapon.dry_fired.connect(_on_dry_fired)
	# Phase 1: start with a rifle and spare ammo (phase 2: loot from buildings).
	inventory.add_ammo(weapon_data.ammo_type, 210 if is_player else 9999)

	spawn_time_msec = Time.get_ticks_msec()
	_prev_pos = global_position
	_curr_pos = global_position
	model.rotation.y = aim_yaw
	_ray.collision_mask = Layers.WORLD


# --------------------------------------------------------------------------
# Controller API
# --------------------------------------------------------------------------

func request_jump() -> void:
	_jump_requested = true


func request_reload() -> void:
	_reload_requested = true


func request_stance(s: int) -> void:
	_stance_request = s


func toggle_crouch() -> void:
	request_stance(Stance.STAND if stance == Stance.CROUCH else Stance.CROUCH)


func toggle_prone() -> void:
	request_stance(Stance.STAND if stance == Stance.PRONE else Stance.PRONE)


func cycle_fire_mode() -> void:
	weapon.cycle_fire_mode()


## Aim direction including recoil.
func get_aim_direction() -> Vector3:
	var yaw := aim_yaw + deg_to_rad(weapon.recoil_yaw)
	var pitch := aim_pitch + deg_to_rad(weapon.recoil_pitch)
	return Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))


func get_eye_position() -> Vector3:
	var h: float = EYE_HEIGHTS[stance]
	if is_swimming:
		h = 1.45
	var p := global_position + Vector3(0, h, 0)
	if stance == Stance.PRONE:
		p += Vector3(-sin(aim_yaw), 0, -cos(aim_yaw)) * 0.55
	return p


func get_hitbox_center() -> Vector3:
	return hitboxes.get_center()


func get_head_position() -> Vector3:
	return hitboxes.get_head()


func get_time_alive() -> float:
	var end := death_time_msec if is_dead else Time.get_ticks_msec()
	return (end - spawn_time_msec) / 1000.0


# --------------------------------------------------------------------------
# Simulation
# --------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_prev_pos = _curr_pos
	if is_dead:
		# Corpse: just settle on the ground.
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		move_and_slide()
		_curr_pos = global_position
		return
	_update_stance()
	_update_swimming()
	_update_movement(delta)
	_update_weapon(delta)
	# The body never rotates; only the visual model turns toward the aim.
	model.rotation.y = lerp_angle(model.rotation.y, aim_yaw, clampf(delta * 20.0, 0.0, 1.0))
	_curr_pos = global_position


func _update_movement(delta: float) -> void:
	var yaw_basis := Basis(Vector3.UP, aim_yaw)
	var wish := yaw_basis * Vector3(input_move.x, 0.0, -input_move.y)
	if wish.length_squared() > 1.0:
		wish = wish.normalized()

	is_sprinting = input_sprint and input_move.y > 0.3 and not input_aim and not input_fire \
		and not is_swimming and stance != Stance.PRONE
	if is_sprinting and stance == Stance.CROUCH:
		request_stance(Stance.STAND)

	var speed := RUN_SPEED
	if is_swimming:
		speed = SWIM_SPEED
	elif stance == Stance.PRONE:
		speed = PRONE_SPEED
	elif stance == Stance.CROUCH:
		speed = CROUCH_SPEED
	elif is_sprinting:
		speed = SPRINT_SPEED
	elif input_walk:
		speed = WALK_SPEED
	if input_aim and not is_sprinting:
		speed *= weapon_data.ads_move_factor
	if input_move.y < -0.1:
		speed *= 0.8
	# Wading through shallow water is slower.
	if not is_swimming and Game.world != null:
		var depth := HeightMap.WATER_LEVEL - global_position.y
		if depth > 0.35:
			speed *= 0.7

	var on_floor := is_on_floor() or sim_simple
	var accel := GROUND_ACCEL if (on_floor or is_swimming) else AIR_ACCEL
	var target := wish * speed
	var w := 1.0 - exp(-accel * delta)
	velocity.x = lerpf(velocity.x, target.x, w)
	velocity.z = lerpf(velocity.z, target.z, w)

	_update_sim_lod()
	if sim_simple:
		_move_simple(delta)
		return

	if is_swimming:
		# Float with the chest at the surface.
		var target_y := HeightMap.WATER_LEVEL - 1.3
		var want_vy := clampf((target_y - global_position.y) * 3.0, -3.0, 3.0)
		velocity.y = lerpf(velocity.y, want_vy, 1.0 - exp(-5.0 * delta))
	elif on_floor:
		if _jump_requested:
			if stance == Stance.STAND:
				velocity.y = JUMP_VELOCITY
			else:
				request_stance(Stance.STAND)
	else:
		velocity.y -= GRAVITY * delta
	_jump_requested = false
	move_and_slide()


func _update_sim_lod() -> void:
	if is_player or Game.world == null or is_swimming:
		sim_simple = false
		return
	var d2 := Game.get_view_position().distance_squared_to(global_position)
	var limit := SIMPLE_EXIT_DIST if sim_simple else SIMPLE_ENTER_DIST
	sim_simple = d2 > limit * limit and is_on_floor_or_simple()


## Cheap movement for far bots: slide along the terrain surface, blocked only
## by buildings and deep water (trees / other characters are ignored far away).
func _move_simple(delta: float) -> void:
	var next := global_position + Vector3(velocity.x, 0.0, velocity.z) * delta
	var world := Game.world
	if world.settlements.is_inside_building(next, 0.35) or world.get_water_depth(next.x, next.z) > 0.9:
		velocity.x = 0.0
		velocity.z = 0.0
		next = global_position
	next.y = world.get_height(next.x, next.z)
	velocity.y = 0.0
	_jump_requested = false
	global_position = next


func is_on_floor_or_simple() -> bool:
	return sim_simple or is_on_floor()


func _update_swimming() -> void:
	var under := HeightMap.WATER_LEVEL - global_position.y
	if is_swimming:
		is_swimming = under > SWIM_EXIT
	else:
		is_swimming = under > SWIM_ENTER
		if is_swimming and stance != Stance.STAND:
			stance = Stance.STAND
			_apply_stance_shape()
			stance_changed.emit(stance)


func _update_stance() -> void:
	if _stance_request < 0:
		return
	var s := _stance_request
	_stance_request = -1
	if s == stance or is_swimming:
		return
	var new_h: float = HEIGHTS[s]
	var cur_h: float = HEIGHTS[stance]
	if new_h > cur_h:
		# Need headroom to stand / crouch up.
		_ray.from = global_position + Vector3(0, cur_h - 0.1, 0)
		_ray.to = global_position + Vector3(0, new_h + 0.05, 0)
		if not get_world_3d().direct_space_state.intersect_ray(_ray).is_empty():
			return
	stance = s
	_apply_stance_shape()
	stance_changed.emit(stance)


func _apply_stance_shape() -> void:
	var h: float = HEIGHTS[stance]
	_capsule.height = h
	_collision.position = Vector3(0, h * 0.5, 0)


func _update_weapon(delta: float) -> void:
	if _reload_requested:
		_reload_requested = false
		if not is_swimming:
			weapon.start_reload(inventory)
	var can_fire := not is_sprinting and not is_swimming
	var shots := weapon.update(delta, input_fire, can_fire, inventory)
	# Auto reload when trying to shoot an empty magazine.
	if input_fire and can_fire and weapon.ammo == 0 and not weapon.is_reloading():
		weapon.start_reload(inventory)
	for i in shots:
		_fire_one()


func _fire_one() -> void:
	var muzzle := model.get_muzzle_global()
	var aim_dir := get_aim_direction()
	var target := aim_point if has_aim_point else get_eye_position() + aim_dir * 300.0
	var dir := target - muzzle
	# Aim point too close / behind the muzzle: fall back to the view direction.
	if dir.length() < 1.5 or dir.normalized().dot(aim_dir) < 0.6:
		dir = aim_dir
	dir = dir.normalized()
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var stance_factor := 1.0
	if stance == Stance.CROUCH:
		stance_factor = weapon_data.crouch_spread_factor
	elif stance == Stance.PRONE:
		stance_factor = weapon_data.prone_spread_factor
	var spread := weapon.get_spread(input_aim, hspeed, not is_on_floor_or_simple(), stance_factor)
	dir = _apply_spread(dir, deg_to_rad(spread))

	last_fire_msec = Time.get_ticks_msec()
	if Game.projectiles != null:
		Game.projectiles.fire(self, muzzle, dir, weapon_data)
	weapon.apply_recoil(stance_factor * (0.8 if input_aim else 1.0))
	model.on_fired()
	Events.shot_fired.emit(self, muzzle, weapon_data.loudness_radius)
	if is_player:
		Sfx.play_2d(&"rifle_shot", -5.0, 0.05)
	else:
		Sfx.play_3d(&"rifle_shot", muzzle, 2.0, 0.06, 800.0)


func _apply_spread(dir: Vector3, angle: float) -> Vector3:
	if angle <= 0.0:
		return dir
	var r := angle * sqrt(_rng.randf())
	var theta := _rng.randf() * TAU
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	var right := dir.cross(up).normalized()
	var up2 := right.cross(dir).normalized()
	return (dir + (right * cos(theta) + up2 * sin(theta)) * tan(r)).normalized()


# --------------------------------------------------------------------------
# Damage
# --------------------------------------------------------------------------

func apply_damage(info: DamageInfo) -> void:
	if is_dead:
		return
	var amount := _modify_incoming_damage(info)
	info.amount = amount
	health = maxf(health - amount, 0.0)
	var attacker := info.attacker as GameCharacter
	if attacker != null and attacker != self:
		last_attacker = attacker
		attacker.damage_dealt += amount
	damaged.emit(info)
	Events.character_damaged.emit(self, info)
	if health <= 0.0:
		_die(info)


## Hook for armor (phase 2: helmet reduces HEAD damage, vest reduces TORSO).
func _modify_incoming_damage(info: DamageInfo) -> float:
	return info.amount


func _die(info: DamageInfo) -> void:
	is_dead = true
	death_time_msec = Time.get_ticks_msec()
	collision_layer = 0
	collision_mask = Layers.WORLD
	input_fire = false
	input_aim = false
	input_move = Vector2.ZERO
	weapon.cancel_reload()
	var fall_dir := info.direction if info != null else Vector3(sin(aim_yaw), 0, cos(aim_yaw))
	model.play_death(fall_dir)
	var attacker: GameCharacter = (info.attacker as GameCharacter) if info != null else null
	if attacker != null and attacker != self:
		attacker.kills += 1
	died.emit(info)
	Events.character_died.emit(self, info)


# --------------------------------------------------------------------------
# Visuals
# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	model.velocity_world = velocity
	model.crouch_target = 1.0 if stance == Stance.CROUCH else 0.0
	model.prone_target = 1.0 if stance == Stance.PRONE else 0.0
	model.aim_pitch = aim_pitch + deg_to_rad(weapon.recoil_pitch)
	model.aiming = input_aim and not is_sprinting
	model.sprinting = is_sprinting and Vector2(velocity.x, velocity.z).length() > 3.0
	_air_time = 0.0 if (is_on_floor_or_simple() or is_swimming) else _air_time + delta
	model.in_air = _air_time > 0.15 and not is_dead
	model.swimming = is_swimming
	model.reload_progress = weapon.get_reload_progress() if weapon.is_reloading() else -1.0
	model.update_effects(delta)

	# Smooth the visual between physics ticks (manual interpolation).
	var offset := (_prev_pos - _curr_pos) * (1.0 - Engine.get_physics_interpolation_fraction())
	model.position = offset if offset.length_squared() < 4.0 else Vector3.ZERO

	# Animation level of detail: far / off-screen characters update less often.
	_anim_accum += delta
	if _anim_accum >= _anim_interval():
		model.animate(_anim_accum)
		_anim_accum = 0.0


func _anim_interval() -> float:
	if is_player:
		return 0.0
	var cam := Game.camera
	if cam == null or not is_instance_valid(cam):
		return 0.1
	var d := cam.global_position.distance_to(global_position)
	if not cam.is_position_in_frustum(global_position + Vector3(0, 1, 0)):
		return 0.25 if d < 60.0 else 0.5
	if d < 40.0:
		return 0.0
	if d < 100.0:
		return 1.0 / 30.0
	if d < 250.0:
		return 1.0 / 12.0
	return 0.2


func _on_footstep() -> void:
	if Game.camera == null or not is_instance_valid(Game.camera):
		return
	if Game.camera.global_position.distance_squared_to(global_position) > 40.0 * 40.0:
		return
	var vol := -14.0
	if stance == Stance.CROUCH or input_walk:
		vol = -24.0
	elif is_sprinting:
		vol = -10.0
	Sfx.play_3d(&"step", global_position, vol, 0.15, 40.0)


func _on_reload_started(_duration: float) -> void:
	_play_weapon_sound(&"mag_out")


func _on_reload_finished() -> void:
	_play_weapon_sound(&"bolt")


func _on_dry_fired() -> void:
	_play_weapon_sound(&"dry_fire")


func _play_weapon_sound(sound: StringName) -> void:
	if is_player:
		Sfx.play_2d(sound, -6.0)
	else:
		Sfx.play_3d(sound, global_position + Vector3(0, 1.2, 0), -6.0, 0.05, 40.0)
