class_name Weapon
extends RefCounted
## Runtime state of one weapon: ammo, fire rate, reload, spread bloom and recoil.
## Owned by a GameCharacter; the same code runs for the player and every bot.

signal fired
signal reload_started(duration: float)
signal reload_finished
signal dry_fired
signal fire_mode_changed(mode: int)

var data: WeaponData
var ammo := 0
var fire_mode: int = WeaponData.FireMode.AUTO
## Extra spread (degrees) from sustained fire.
var bloom := 0.0
## Accumulated recoil offsets (degrees) added on top of the aim direction.
var recoil_pitch := 0.0
var recoil_yaw := 0.0

var _cooldown := 0.0
var _reload_left := 0.0
var _trigger_prev := false
var _since_shot := 10.0
var _rng := RandomNumberGenerator.new()


func _init(p_data: WeaponData) -> void:
	data = p_data
	ammo = data.magazine_size
	if not data.fire_modes.is_empty():
		fire_mode = data.fire_modes[0]
	_rng.randomize()


func is_reloading() -> bool:
	return _reload_left > 0.0


func get_reload_progress() -> float:
	if not is_reloading():
		return 0.0
	return 1.0 - _reload_left / maxf(data.reload_time, 0.01)


func can_reload(inventory: Inventory) -> bool:
	return not is_reloading() and ammo < data.magazine_size and inventory.get_ammo(data.ammo_type) > 0


func start_reload(inventory: Inventory) -> bool:
	if not can_reload(inventory):
		return false
	_reload_left = data.reload_time
	reload_started.emit(data.reload_time)
	return true


func cancel_reload() -> void:
	_reload_left = 0.0


func cycle_fire_mode() -> void:
	if data.fire_modes.size() < 2:
		return
	var idx := data.fire_modes.find(fire_mode)
	fire_mode = data.fire_modes[(idx + 1) % data.fire_modes.size()]
	fire_mode_changed.emit(fire_mode)


## Advances timers and returns how many shots must be fired this tick.
func update(delta: float, trigger_down: bool, can_fire: bool, inventory: Inventory) -> int:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_since_shot += delta
	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_reload_left = 0.0
			var got := inventory.take_ammo(data.ammo_type, data.magazine_size - ammo)
			ammo += got
			reload_finished.emit()

	var shots := 0
	var just_pressed := trigger_down and not _trigger_prev
	if can_fire and trigger_down and not is_reloading():
		if fire_mode == WeaponData.FireMode.AUTO or just_pressed:
			if _cooldown <= 0.0:
				if ammo <= 0:
					if just_pressed:
						dry_fired.emit()
				else:
					ammo -= 1
					shots = 1
					_cooldown = data.get_fire_interval()
					_since_shot = 0.0
					bloom = minf(bloom + data.spread_per_shot, data.spread_max_bloom)
					fired.emit()
	_trigger_prev = trigger_down

	# Recover bloom and recoil when not shooting.
	if _since_shot > 0.12:
		bloom = move_toward(bloom, 0.0, data.spread_recovery * delta)
		recoil_pitch = move_toward(recoil_pitch, 0.0, data.recoil_recovery * delta)
		recoil_yaw = move_toward(recoil_yaw, 0.0, data.recoil_recovery * delta)
	return shots


## Adds recoil for one shot. `factor` < 1 when crouched / prone / aiming.
func apply_recoil(factor: float) -> void:
	recoil_pitch += data.recoil_vertical * _rng.randf_range(0.85, 1.15) * factor
	recoil_yaw += _rng.randf_range(-data.recoil_horizontal, data.recoil_horizontal) * factor
	# Clamp so long sprays stay controllable.
	recoil_pitch = minf(recoil_pitch, 12.0)
	recoil_yaw = clampf(recoil_yaw, -4.0, 4.0)


## Current cone half-angle in degrees.
func get_spread(aiming: bool, speed: float, in_air: bool, stance_factor: float) -> float:
	var s := data.spread_ads if aiming else data.spread_hip
	s += data.spread_move * clampf(speed / 5.0, 0.0, 1.0)
	if in_air:
		s += data.spread_air
	return (s + bloom) * stance_factor
