class_name ThirdPersonCamera
extends Node3D
## Over-the-shoulder camera rig: pivot (this node) -> SpringArm3D -> Camera3D.
##
## Follows the (interpolated) character position, uses the character's aim
## yaw / pitch + weapon recoil, zooms in while aiming (right mouse button) and
## avoids clipping through walls thanks to the spring arm.

const HIP_DISTANCE := 3.1
const ADS_DISTANCE := 1.55
const HIP_SHOULDER := 0.6
const ADS_SHOULDER := 0.68
const PIVOT_HEIGHTS := [1.55, 1.1, 0.5]
## Seconds the breath can be held while scoped (Shift).
const BREATH_MAX := 5.0

@export var target_path: NodePath = ^".."

var target: GameCharacter
var camera: Camera3D
var spring: SpringArm3D

var _pivot_y := 1.55
var _ads_t := 0.0
var _shake := 0.0
var _death_orbit := 0.0
var _ray := PhysicsRayQueryParameters3D.new()
var _distance := HIP_DISTANCE
var _wind: AudioStreamPlayer
## True while looking through a magnified scope / red dot (first person).
var scoped := false
## 0..1 breath left for holding it (HUD).
var breath := 1.0
var holding_breath := false
var _scope_t := 0.0
var _sway_time := 0.0
var _breath_left := BREATH_MAX
var _model_hidden := false


func _ready() -> void:
	top_level = true
	target = get_node(target_path) as GameCharacter
	spring = $SpringArm3D
	camera = $SpringArm3D/Camera3D
	spring.collision_mask = Layers.WORLD
	spring.margin = 0.15
	var probe := SphereShape3D.new()
	probe.radius = 0.2
	spring.shape = probe
	spring.spring_length = HIP_DISTANCE
	camera.fov = Settings.fov
	camera.near = 0.05
	camera.far = 1700.0
	camera.current = true
	_ray.collision_mask = Layers.WORLD
	Game.camera = camera
	Game.camera_rig = self
	_wind = AudioStreamPlayer.new()
	_wind.stream = Sfx.get_loop(&"wind")
	_wind.volume_db = -60.0
	add_child(_wind)
	target.weapon_fired.connect(_on_fired)


## Hand sway while scoped (degrees); Shift holds the breath for a few seconds.
func _update_sway(delta: float, zoom: float) -> Vector2:
	_sway_time += delta
	var amp := 0.09 * zoom
	match target.stance:
		GameCharacter.Stance.CROUCH:
			amp *= 0.6
		GameCharacter.Stance.PRONE:
			amp *= 0.3
	if Vector2(target.velocity.x, target.velocity.z).length() > 0.5:
		amp *= 2.0
	holding_breath = target.input_sprint and _breath_left > 0.0
	if holding_breath:
		_breath_left = maxf(_breath_left - delta, 0.0)
		amp *= 0.12
	else:
		_breath_left = minf(_breath_left + delta * 0.4, BREATH_MAX)
		if _breath_left < 1.0:
			amp *= 1.6   # out of breath
	return Vector2(sin(_sway_time * 0.9) + 0.4 * sin(_sway_time * 2.3), 0.7 * sin(_sway_time * 1.3 + 1.0)) * amp


## Rushing air while falling / gliding.
func _update_wind(delta: float) -> void:
	var want := -60.0
	if not target.is_dead:
		match target.air_state:
			GameCharacter.AirState.FREEFALL:
				want = linear_to_db(clampf(target.velocity.length() / 55.0, 0.05, 1.0)) - 2.0
			GameCharacter.AirState.PARACHUTE:
				want = -16.0
	_wind.volume_db = lerpf(_wind.volume_db, want, 1.0 - exp(-3.0 * delta))
	if _wind.volume_db > -50.0 and not _wind.playing:
		_wind.play()
	elif _wind.volume_db <= -55.0 and _wind.playing:
		_wind.stop()


func _on_fired() -> void:
	var kick := 0.35
	if target.weapon_data != null:
		kick = clampf(target.weapon_data.recoil_vertical * 0.45, 0.1, 1.0)
	_shake = minf(_shake + kick, 1.0)


## Mouse sensitivity is scaled down while zoomed in.
func get_sensitivity_scale() -> float:
	if camera == null:
		return 1.0
	return tan(deg_to_rad(camera.fov) * 0.5) / tan(deg_to_rad(Settings.fov) * 0.5)


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var visual_pos := target.global_position + target.model.position
	var pivot_h: float = PIVOT_HEIGHTS[target.stance]
	if target.is_swimming:
		pivot_h = 1.5
	if target.is_dead:
		pivot_h = 0.9
	var air_distance := 0.0
	match target.air_state:
		GameCharacter.AirState.PLANE:
			pivot_h = 9.0
			air_distance = 48.0
		GameCharacter.AirState.FREEFALL:
			pivot_h = 1.0
			air_distance = 6.0
		GameCharacter.AirState.PARACHUTE:
			pivot_h = 2.4
			air_distance = 8.5
	_pivot_y = lerpf(_pivot_y, pivot_h, 1.0 - exp(-10.0 * delta))
	_update_wind(delta)

	var want_ads := target.input_aim and not target.is_sprinting and not target.is_dead
	_ads_t = move_toward(_ads_t, 1.0 if want_ads else 0.0, delta * 7.0)
	var ease_t := smoothstep(0.0, 1.0, _ads_t)

	var yaw := target.aim_yaw + deg_to_rad(target.weapon.recoil_yaw)
	var pitch := target.aim_pitch + deg_to_rad(target.weapon.recoil_pitch)

	# Scope: first-person view through the sight with a little sway.
	var zoom := target.get_scope_zoom()
	var want_scope := want_ads and zoom > 1.01 and not target.is_in_air() and not target.is_swimming \
		and not target.is_switching_weapon() and not target.weapon.is_reloading()
	_scope_t = move_toward(_scope_t, 1.0 if want_scope else 0.0, delta * 6.0)
	scoped = _scope_t > 0.55
	if scoped:
		var sway := _update_sway(delta, zoom)
		yaw += deg_to_rad(sway.x)
		pitch += deg_to_rad(sway.y)
	else:
		holding_breath = false
		_breath_left = minf(_breath_left + delta * 0.6, BREATH_MAX)
	breath = _breath_left / BREATH_MAX
	var hide_body := scoped and not target.is_dead
	if hide_body != _model_hidden:
		_model_hidden = hide_body
		# The camera sits in the head: do not draw our own body.
		target.model.visible = not hide_body
	var distance := lerpf(HIP_DISTANCE, ADS_DISTANCE, ease_t)
	if air_distance > 0.0:
		distance = air_distance
	_distance = lerpf(_distance, distance, 1.0 - exp(-4.0 * delta))
	distance = _distance
	if target.is_dead:
		# Slow orbit around the body after death.
		_death_orbit += delta * 0.25
		yaw += _death_orbit
		pitch = -0.45
		distance = 4.5

	var yaw_basis := Basis(Vector3.UP, yaw)
	var head := visual_pos + Vector3(0, _pivot_y, 0)
	var shoulder := lerpf(HIP_SHOULDER, ADS_SHOULDER, ease_t) * (0.0 if target.is_dead or target.is_in_air() else 1.0)
	var pivot := head + yaw_basis * Vector3(shoulder, 0, 0)
	# Keep the pivot out of walls when hugging them on the right side.
	_ray.from = head
	_ray.to = pivot + yaw_basis * Vector3(0.2, 0, 0)
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	if not hit.is_empty():
		pivot = head.lerp(hit.position, 0.6)

	if scoped:
		pivot = target.get_eye_position() + target.model.position + yaw_basis * Vector3(0, 0.02, -0.1)
		distance = 0.0
		_distance = 0.0
	global_transform = Transform3D(yaw_basis * Basis(Vector3.RIGHT, pitch), pivot)
	spring.spring_length = distance
	var ads_fov := target.weapon_data.ads_fov if target.weapon_data != null else 55.0
	camera.fov = lerpf(Settings.fov, ads_fov, ease_t)
	if scoped:
		camera.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(Settings.fov) * 0.5) / zoom))

	camera.far = 3000.0 if target.is_in_air() else 1700.0

	# Small shake when firing.
	_shake = move_toward(_shake, 0.0, delta * 6.0)
	camera.h_offset = randf_range(-1.0, 1.0) * 0.012 * _shake
	camera.v_offset = randf_range(-1.0, 1.0) * 0.012 * _shake
