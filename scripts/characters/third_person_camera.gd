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

@export var target_path: NodePath = ^".."

var target: GameCharacter
var camera: Camera3D
var spring: SpringArm3D

var _pivot_y := 1.55
var _ads_t := 0.0
var _shake := 0.0
var _death_orbit := 0.0
var _ray := PhysicsRayQueryParameters3D.new()


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
	if target.weapon != null:
		target.weapon.fired.connect(_on_fired)
	else:
		target.ready.connect(func(): target.weapon.fired.connect(_on_fired), CONNECT_ONE_SHOT)


func _on_fired() -> void:
	_shake = minf(_shake + 0.35, 1.0)


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
	_pivot_y = lerpf(_pivot_y, pivot_h, 1.0 - exp(-10.0 * delta))

	var want_ads := target.input_aim and not target.is_sprinting and not target.is_dead
	_ads_t = move_toward(_ads_t, 1.0 if want_ads else 0.0, delta * 7.0)
	var ease_t := smoothstep(0.0, 1.0, _ads_t)

	var yaw := target.aim_yaw + deg_to_rad(target.weapon.recoil_yaw)
	var pitch := target.aim_pitch + deg_to_rad(target.weapon.recoil_pitch)
	var distance := lerpf(HIP_DISTANCE, ADS_DISTANCE, ease_t)
	if target.is_dead:
		# Slow orbit around the body after death.
		_death_orbit += delta * 0.25
		yaw += _death_orbit
		pitch = -0.45
		distance = 4.5

	var yaw_basis := Basis(Vector3.UP, yaw)
	var head := visual_pos + Vector3(0, _pivot_y, 0)
	var shoulder := lerpf(HIP_SHOULDER, ADS_SHOULDER, ease_t) * (0.0 if target.is_dead else 1.0)
	var pivot := head + yaw_basis * Vector3(shoulder, 0, 0)
	# Keep the pivot out of walls when hugging them on the right side.
	_ray.from = head
	_ray.to = pivot + yaw_basis * Vector3(0.2, 0, 0)
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	if not hit.is_empty():
		pivot = head.lerp(hit.position, 0.6)

	global_transform = Transform3D(yaw_basis * Basis(Vector3.RIGHT, pitch), pivot)
	spring.spring_length = distance
	var ads_fov := target.weapon_data.ads_fov if target.weapon_data != null else 55.0
	camera.fov = lerpf(Settings.fov, ads_fov, ease_t)

	# Small shake when firing.
	_shake = move_toward(_shake, 0.0, delta * 6.0)
	camera.h_offset = randf_range(-1.0, 1.0) * 0.012 * _shake
	camera.v_offset = randf_range(-1.0, 1.0) * 0.012 * _shake
