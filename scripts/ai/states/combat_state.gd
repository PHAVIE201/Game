class_name CombatState
extends BotState
## Fight the current target: aim with human-like error, shoot in bursts,
## strafe, crouch / go prone, reload, chase when the target breaks line of sight.

enum Tactic { HOLD, STRAFE, APPROACH, RETREAT, COVER }
enum CoverPhase { MOVE, HIDE, PEEK }

var _tactic: int = Tactic.HOLD
var _tactic_timer := 0.0
var _strafe_side := 1.0
var _burst_left := 0
var _burst_start_ammo := 0
var _pause := 0.0
var _cover_pos := Vector3.ZERO
var _cover_phase: int = CoverPhase.MOVE
var _cover_timer := 0.0
var _last_cover_search := -100.0
var _grenade_checked_at := -100.0


func enter(_params: Dictionary) -> void:
	brain.stop_moving()
	_tactic_timer = 0.0
	_burst_left = 0
	_pause = 0.0


func exit() -> void:
	var c := get_character()
	c.input_fire = false
	c.input_aim = false
	brain.direct_move = Vector3.ZERO


func update(delta: float) -> void:
	var c := get_character()
	var t := brain.target
	if t == null or t.is_dead:
		brain.clear_target()
		# Loot what the enemy dropped.
		brain.fsm.change(&"loot", {"budget": 30.0})
		return
	var visible := brain.is_target_visible()
	var lost_for := brain.time - brain.target_last_seen_time
	# The zone is closing on us: break off when the enemy is not in sight.
	if (lost_for > 1.0 or c.global_position.distance_to(t.global_position) > 60.0) and brain.zone_urgency() > 0.0:
		brain.fsm.change(&"zone")
		return
	# Badly hurt: patch up when the enemy lost sight of us, or break contact
	# behind a smoke screen.
	if c.health < 40.0 and brain.pick_heal_or_boost() != &"":
		if lost_for > 2.0:
			brain.fsm.change(&"heal")
			return
		if c.health < 30.0 and c.inventory.get_count(&"grenade_smoke") > 0 and brain.time - brain.last_throw_time > 10.0:
			brain.fsm.change(&"heal", {"smoke_toward": t.global_position})
			return
	if lost_for > 3.5:
		# Lost sight: go check the last known position.
		var last := brain.target_last_seen_pos
		brain.clear_target()
		brain.fsm.change(&"investigate", {"pos": last})
		return

	var dist := c.global_position.distance_to(t.global_position)
	if not brain.has_usable_gun():
		_fight_unarmed(t, dist, visible)
		return
	if _try_grenade(lost_for, dist):
		return
	var aim_pt := brain.get_aim_point(delta)
	brain.look_at_point(aim_pt)
	brain.select_weapon_for(dist, delta)
	var data := c.weapon_data
	c.input_aim = visible and dist > 12.0 and (_tactic != Tactic.APPROACH or data.category == WeaponData.Category.SNIPER)

	# ---- Shooting -------------------------------------------------------------
	var reacted := brain.time - brain.target_first_seen_time > brain.profile.reaction_time + dist * 0.002
	# Fire only when the gun points close enough to the (imperfect) aim point.
	var tolerance := 0.02 + 0.6 / maxf(dist, 1.0)
	var aligned := brain.aim_error_to(aim_pt) < tolerance
	var fire := false
	var single := data.is_single_only()
	if c.weapon.uses_ammo() and c.weapon.ammo == 0 and not c.weapon.is_reloading():
		c.request_reload()
	elif visible and reacted and aligned and not c.weapon.is_reloading() and not c.is_switching_weapon():
		if _pause > 0.0:
			_pause -= delta
		else:
			fire = true
			if not single and c.weapon.fire_mode != WeaponData.FireMode.AUTO:
				c.cycle_fire_mode()
	else:
		_pause = maxf(_pause - delta, 0.0)
	# Burst control: count shots through the ammo counter. Single-shot guns
	# fire "bursts" of one and release the trigger between shots.
	if fire:
		if _burst_left <= 0:
			_burst_left = brain.rng.randi_range(brain.profile.burst_min, brain.profile.burst_max)
			if dist > 120.0 or single:
				_burst_left = 1 if single else brain.rng.randi_range(1, 2)
			_burst_start_ammo = c.weapon.ammo
		if _burst_start_ammo - c.weapon.ammo >= _burst_left:
			_burst_left = 0
			_pause = _pause_after_burst(data, dist)
			fire = false
	if _tactic == Tactic.COVER and _cover_phase != CoverPhase.PEEK:
		fire = false   # hiding: no shots
	c.input_fire = fire

	# ---- Movement / tactics ---------------------------------------------------------
	_tactic_timer -= delta
	if _tactic_timer <= 0.0:
		_choose_tactic(dist, visible)
	# Hit by someone we cannot see: get behind something.
	if _tactic != Tactic.COVER and brain.time - brain.last_damaged_time < 0.3 and not visible:
		_start_cover(t)
	var to_target := t.global_position - c.global_position
	to_target.y = 0.0
	var fwd := to_target.normalized() if to_target.length_squared() > 0.01 else Vector3.FORWARD
	var side := fwd.cross(Vector3.UP) * _strafe_side
	match _tactic:
		Tactic.HOLD:
			brain.stop_moving()
		Tactic.STRAFE:
			brain.nav.stop()
			brain.move_mode = BotBrain.MoveMode.RUN
			brain.direct_move = side
		Tactic.APPROACH:
			var close := clampf(brain.preferred_range().y * 0.5, 2.0, 8.0)
			if not brain.nav.active or brain.nav.destination.distance_to(brain.target_last_seen_pos) > 5.0:
				brain.move_to(brain.target_last_seen_pos, BotBrain.MoveMode.RUN, close)
		Tactic.RETREAT:
			brain.nav.stop()
			brain.move_mode = BotBrain.MoveMode.RUN
			brain.direct_move = (-fwd + side * 0.6).normalized()
		Tactic.COVER:
			_update_cover(delta, c, visible)



## No gun: punch when the enemy is close, otherwise go find a weapon.
func _fight_unarmed(t: GameCharacter, dist: float, visible: bool) -> void:
	var c := get_character()
	if c.active_slot >= 0:
		c.holster()
	if dist > 9.0 or not visible:
		c.input_fire = false
		brain.clear_target()
		brain.fsm.change(&"loot", {"budget": 40.0})
		return
	c.request_stance(GameCharacter.Stance.STAND)
	brain.look_at_point(t.get_hitbox_center())
	c.input_aim = false
	if dist > 1.4:
		if not brain.nav.active or brain.nav.destination.distance_to(t.global_position) > 1.5:
			brain.move_to(t.global_position, BotBrain.MoveMode.SPRINT, 1.0)
	else:
		brain.stop_moving()
	c.input_fire = dist < 1.9 and brain.aim_error_to(t.get_hitbox_center()) < 0.35


func _pause_after_burst(data: WeaponData, dist: float) -> float:
	var rng := brain.rng
	match data.category:
		WeaponData.Category.SNIPER:
			return rng.randf_range(0.3, 0.8)
		WeaponData.Category.DMR:
			return rng.randf_range(0.25, 0.6) + dist * 0.002
		WeaponData.Category.SHOTGUN, WeaponData.Category.PISTOL:
			return rng.randf_range(0.12, 0.35)
		_:
			return rng.randf_range(0.25, 0.7) + dist * 0.003


## Cover: run to a spot hidden from the enemy, crouch (reload / patch up),
## stand up to shoot for a moment, hide again.
func _start_cover(t: GameCharacter) -> bool:
	if brain.time - _last_cover_search < 3.0:
		return false
	_last_cover_search = brain.time
	var spot := brain.find_cover(t.get_eye_position())
	if spot == Vector3.INF:
		return false
	_cover_pos = spot
	_cover_phase = CoverPhase.MOVE
	_tactic = Tactic.COVER
	_tactic_timer = brain.rng.randf_range(10.0, 16.0)
	brain.move_to(_cover_pos, BotBrain.MoveMode.RUN, 0.8)
	return true


func _update_cover(delta: float, c: GameCharacter, visible: bool) -> void:
	_cover_timer -= delta
	match _cover_phase:
		CoverPhase.MOVE:
			if brain.nav.arrived or Vector2(c.global_position.x - _cover_pos.x, c.global_position.z - _cover_pos.z).length() < 1.0:
				_cover_phase = CoverPhase.HIDE
				_cover_timer = brain.rng.randf_range(1.2, 2.6)
				brain.stop_moving()
				c.request_stance(GameCharacter.Stance.CROUCH)
			elif brain.nav.failed:
				_tactic_timer = 0.0
		CoverPhase.HIDE:
			brain.stop_moving()
			if c.weapon.uses_ammo() and c.weapon.ammo < c.weapon.data.magazine_size * 0.7 and not c.weapon.is_reloading():
				c.request_reload()
			if _cover_timer <= 0.0 and not c.weapon.is_reloading():
				_cover_phase = CoverPhase.PEEK
				_cover_timer = brain.rng.randf_range(1.5, 3.5)
				c.request_stance(GameCharacter.Stance.STAND)
		CoverPhase.PEEK:
			brain.stop_moving()
			if _cover_timer <= 0.0 or (c.weapon.uses_ammo() and c.weapon.ammo == 0):
				_cover_phase = CoverPhase.HIDE
				_cover_timer = brain.rng.randf_range(1.0, 2.5)
				c.request_stance(GameCharacter.Stance.CROUCH)
	if not visible and _cover_phase == CoverPhase.PEEK and _cover_timer < 0.5:
		# Nobody to shoot at: go look for the enemy.
		_tactic_timer = 0.0


## Frag at an enemy who hides (not seen for a moment, within throwing range).
func _try_grenade(lost_for: float, dist: float) -> bool:
	if lost_for < 1.2 or lost_for > 6.0 or dist < 7.0 or dist > 34.0:
		return false
	if brain.time - _grenade_checked_at < 4.0 or brain.time - brain.last_throw_time < 10.0:
		return false
	_grenade_checked_at = brain.time
	if get_character().inventory.get_count(&"grenade_frag") <= 0 or brain.rng.randf() > brain.profile.grenade_chance:
		return false
	return brain.throw_grenade_at(&"grenade_frag", brain.target_last_seen_pos, 3.5)


func _choose_tactic(dist: float, visible: bool) -> void:
	var c := get_character()
	var rng := brain.rng
	var pref := brain.preferred_range()
	_tactic_timer = rng.randf_range(0.9, 2.4)
	# Mid-range firefight: fight from cover.
	if visible and dist > 14.0 and dist < pref.y * 1.3 and rng.randf() < brain.profile.cover_chance:
		if _start_cover(brain.target):
			return
	_strafe_side = 1.0 if rng.randf() < 0.5 else -1.0
	if not visible:
		_tactic = Tactic.APPROACH
	elif dist > pref.y:
		# Out of range: close-range guns must push, others sometimes hold.
		var push := 0.85 if pref.y < 50.0 else 0.5
		_tactic = Tactic.APPROACH if rng.randf() < push else Tactic.HOLD
	elif dist < pref.x:
		_tactic = Tactic.RETREAT if rng.randf() < 0.5 else Tactic.STRAFE
	else:
		_tactic = Tactic.STRAFE if rng.randf() < 0.55 else Tactic.HOLD
	if c.weapon.is_reloading() and _tactic == Tactic.HOLD:
		_tactic = Tactic.STRAFE
	# Stance: crouch or go prone when holding position.
	if _tactic == Tactic.HOLD:
		if dist > 90.0 and rng.randf() < 0.2:
			c.request_stance(GameCharacter.Stance.PRONE)
		elif rng.randf() < brain.profile.crouch_chance:
			c.request_stance(GameCharacter.Stance.CROUCH)
		else:
			c.request_stance(GameCharacter.Stance.STAND)
	else:
		c.request_stance(GameCharacter.Stance.STAND)
