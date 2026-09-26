class_name CharacterModel
extends Node3D
## Procedural low-poly character: skeleton + skinned mesh + gun, animated in code.
##
## - The whole body is ONE skinned MeshInstance3D (1 draw call per character),
##   built from boxes / prisms that are rigidly bound to bones.
## - Animation is procedural: gait cycle + stance blending, two-bone IK for arms
##   (hands stay on the gun) and legs (feet on the ground).
## - `bone_global` keeps model-space bone transforms after each update; the
##   hitboxes and the muzzle position are derived from it (no physics bodies).
## - The owner calls animate() at a reduced rate for far away characters (LOD).
##
## Model space: character faces -Z, +X is its right side, origin at the feet.

enum B {
	ROOT, HIPS, SPINE, CHEST, NECK, HEAD,
	UPPER_ARM_L, LOWER_ARM_L, HAND_L, UPPER_ARM_R, LOWER_ARM_R, HAND_R,
	UPPER_LEG_L, LOWER_LEG_L, FOOT_L, UPPER_LEG_R, LOWER_LEG_R, FOOT_R,
}
const BONE_COUNT := 18
const BONE_NAMES := [
	"root", "hips", "spine", "chest", "neck", "head",
	"upper_arm.L", "lower_arm.L", "hand.L", "upper_arm.R", "lower_arm.R", "hand.R",
	"upper_leg.L", "lower_leg.L", "foot.L", "upper_leg.R", "lower_leg.R", "foot.R",
]
const PARENTS := [-1, 0, 1, 2, 3, 4, 3, 6, 7, 3, 9, 10, 1, 12, 13, 1, 15, 16]
## Rest offsets relative to the parent bone.
const REST := [
	Vector3(0, 0, 0), Vector3(0, 0.95, 0), Vector3(0, 0.12, 0), Vector3(0, 0.2, 0),
	Vector3(0, 0.23, 0), Vector3(0, 0.08, 0),
	Vector3(-0.21, 0.17, 0), Vector3(0, -0.3, 0), Vector3(0, -0.28, 0),
	Vector3(0.21, 0.17, 0), Vector3(0, -0.3, 0), Vector3(0, -0.28, 0),
	Vector3(-0.1, -0.04, 0), Vector3(0, -0.42, 0), Vector3(0, -0.41, 0),
	Vector3(0.1, -0.04, 0), Vector3(0, -0.42, 0), Vector3(0, -0.41, 0),
]
const UPPER_ARM := 0.3
const LOWER_ARM := 0.28
const UPPER_LEG := 0.42
const LOWER_LEG := 0.41
const ANKLE_H := 0.08

# ---- Animation inputs (written by GameCharacter every frame) -----------------
var velocity_world := Vector3.ZERO
var crouch_target := 0.0
var prone_target := 0.0
var aim_pitch := 0.0          ## radians, + = looking up (includes recoil)
var aiming := false
var sprinting := false
var in_air := false
var swimming := false
var reload_progress := -1.0   ## 0..1 while reloading, -1 otherwise
var bolt_progress := -1.0     ## 0..1 while a bolt-action gun cycles, -1 otherwise
var swap_amount := 0.0        ## 1 = weapon lowered (switching), 0 = ready
var using_item := false       ## bandaging / drinking: gun lowered, hands together
## GameCharacter.AirState: 2 = freefall (spread-eagle), 3 = parachute.
var air_pose := 0

## Model-space transforms of every bone after the last animate().
var bone_global: Array[Transform3D] = []
var gun_transform := Transform3D.IDENTITY
var muzzle_local := Vector3.ZERO

var skeleton: Skeleton3D
var body_mesh: MeshInstance3D
var gun: MeshInstance3D
var scope_mesh: MeshInstance3D
var flash: MeshInstance3D
var flash_light: OmniLight3D
## Primary weapons carried on the back (not in the hands).
var back_guns: Array[MeshInstance3D] = []
var helmet_mesh: MeshInstance3D
var vest_mesh: MeshInstance3D
var canopy: MeshInstance3D

static var _armor_cache: Dictionary = {}

var _gun_model: Dictionary
## False when the character holds nothing (fists).
var _armed := true
var _punch := 0.0
var _punch_side := 1.0
var _use := 0.0
var _fall := 0.0
var _chute := 0.0
var _crouch := 0.0
var _prone := 0.0
var _ads := 0.0
var _sprint := 0.0
var _air := 0.0
var _swim := 0.0
var _phase := 0.0
var _hips_yaw := 0.0
var _kick := 0.0
var _flash_time := 0.0
var _dead := false
var _death_t := 0.0
var _death_axis := Vector3.RIGHT
var _step_callback: Callable
var _last_step_sign := 1.0


# --------------------------------------------------------------------------
# Construction
# --------------------------------------------------------------------------

## Builds the skeleton, body mesh and gun. `outfit` from random_outfit().
func build(outfit: Dictionary, weapon_model: StringName, use_flash_light: bool) -> void:
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton"
	add_child(skeleton)
	for b in BONE_COUNT:
		skeleton.add_bone(BONE_NAMES[b])
	for b in BONE_COUNT:
		skeleton.set_bone_parent(b, PARENTS[b])
		skeleton.set_bone_rest(b, Transform3D(Basis.IDENTITY, REST[b]))
	skeleton.reset_bone_poses()

	body_mesh = MeshInstance3D.new()
	body_mesh.name = "Body"
	body_mesh.mesh = _build_body_mesh(outfit)
	body_mesh.layers = Layers.RENDER_CHARACTERS
	# Poses (prone, death) leave the rest AABB: use a generous fixed AABB.
	body_mesh.custom_aabb = AABB(Vector3(-1.4, -0.3, -1.4), Vector3(2.8, 2.4, 2.8))
	# Bind to the parent skeleton (the default path is empty in Godot 4.7).
	body_mesh.skeleton = NodePath("..")
	skeleton.add_child(body_mesh)

	gun = MeshInstance3D.new()
	gun.name = "Gun"
	gun.layers = Layers.RENDER_CHARACTERS
	add_child(gun)

	scope_mesh = MeshInstance3D.new()
	scope_mesh.name = "Scope"
	scope_mesh.layers = Layers.RENDER_CHARACTERS
	scope_mesh.visible = false
	gun.add_child(scope_mesh)

	flash = MeshInstance3D.new()
	flash.name = "MuzzleFlash"
	flash.mesh = WeaponModels.get_flash_mesh()
	flash.visible = false
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gun.add_child(flash)
	if use_flash_light:
		flash_light = OmniLight3D.new()
		flash_light.light_color = Color(1.0, 0.75, 0.4)
		flash_light.light_energy = 0.0
		flash_light.omni_range = 7.0
		flash_light.shadow_enabled = false
		gun.add_child(flash_light)
	for k in 2:
		var bg := MeshInstance3D.new()
		bg.name = "BackGun%d" % k
		bg.layers = Layers.RENDER_CHARACTERS
		bg.visible = false
		# Small detail: not worth drawing (or casting shadows) far away.
		bg.visibility_range_end = 70.0
		add_child(bg)
		back_guns.append(bg)

	helmet_mesh = MeshInstance3D.new()
	helmet_mesh.name = "Helmet"
	helmet_mesh.layers = Layers.RENDER_CHARACTERS
	helmet_mesh.visible = false
	add_child(helmet_mesh)
	vest_mesh = MeshInstance3D.new()
	vest_mesh.name = "Vest"
	vest_mesh.layers = Layers.RENDER_CHARACTERS
	vest_mesh.visible = false
	add_child(vest_mesh)

	canopy = MeshInstance3D.new()
	canopy.name = "Parachute"
	canopy.mesh = _canopy_mesh(outfit)
	canopy.visible = false
	add_child(canopy)

	bone_global.resize(BONE_COUNT)
	set_weapon(weapon_model)
	animate(0.0)


## Rectangular ram-air canopy (curved row of cells) with suspension lines.
static func _canopy_mesh(outfit: Dictionary) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var col: Color = outfit.get("shirt", Color(0.9, 0.4, 0.2))
	var colors := [col, Color(0.97, 0.97, 0.95)]
	var cells := 7
	var span := 7.0
	for k in cells:
		var a := (float(k) / (cells - 1) - 0.5) * 1.6   # arc angle
		var x := sin(a) * span * 0.62
		var y := 4.6 + cos(a) * 1.2
		mb.add_box(Vector3(x, y, 0.0), Vector3(span / cells + 0.08, 0.28, 2.6), colors[k % 2], Basis(Vector3.BACK, -a))
		# Lines from the canopy edge to the shoulders.
		mb.add_beam(Vector3(x, y - 0.15, -0.9), Vector3(signf(x) * 0.18, 1.55, -0.05), 0.02, Color(0.2, 0.2, 0.2))
		mb.add_beam(Vector3(x, y - 0.15, 0.9), Vector3(signf(x) * 0.18, 1.55, 0.05), 0.02, Color(0.2, 0.2, 0.2))
	var mat := MeshBuilder.make_vertex_color_material(0.8)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mb.commit(mat)


## Shows the worn helmet / vest (&"" = none).
func set_armor(helmet_id: StringName, vest_id: StringName) -> void:
	helmet_mesh.visible = helmet_id != &""
	vest_mesh.visible = vest_id != &""
	if helmet_mesh.visible:
		helmet_mesh.mesh = _armor_mesh(helmet_id)
	if vest_mesh.visible:
		vest_mesh.mesh = _armor_mesh(vest_id)


## Helmet: mesh in HEAD bone space. Vest: mesh in CHEST bone space.
static func _armor_mesh(id: StringName) -> ArrayMesh:
	if _armor_cache.has(id):
		return _armor_cache[id]
	var info := ItemDB.get_info(id)
	var col: Color = info.get("color", Color.GRAY)
	var level := int(info.get("level", 1))
	var mb := MeshBuilder.new()
	if ItemDB.kind_of(id) == ItemDB.Kind.HELMET:
		# Dome above the brow (the face stays visible).
		mb.add_frustum(Vector3(0, 0.155, 0.005), 0.175, 0.155, 0.06, 8, col, false, PI / 8.0)
		mb.add_frustum(Vector3(0, 0.215, 0.005), 0.155, 0.105, 0.05, 8, col, false, PI / 8.0)
		mb.add_frustum(Vector3(0, 0.265, 0.005), 0.105, 0.0, 0.035, 8, col, false, PI / 8.0)
		mb.add_frustum(Vector3(0, 0.15, 0.005), 0.185, 0.185, 0.02, 8, col.darkened(0.2), true, PI / 8.0)
		if level >= 2:
			mb.add_box(Vector3(0, 0.24, -0.13), Vector3(0.07, 0.04, 0.03), Color(0.1, 0.1, 0.1))
		if level >= 3:
			# Visor
			mb.add_box(Vector3(0, 0.15, -0.18), Vector3(0.26, 0.05, 0.02), Color(0.15, 0.2, 0.25))
	else:
		mb.add_box(Vector3(0, 0.04, 0.0), Vector3(0.47, 0.36, 0.3), col)
		mb.add_box(Vector3(0, 0.23, 0.0), Vector3(0.3, 0.05, 0.26), col.darkened(0.2))
		for k in level + 1:
			var x := -0.14 + k * (0.28 / maxf(level, 1))
			mb.add_box(Vector3(x, -0.02, -0.16), Vector3(0.09, 0.11, 0.05), col.darkened(0.25))
	var mesh := mb.commit(MeshBuilder.make_vertex_color_material(0.8))
	_armor_cache[id] = mesh
	return mesh


## Puts a gun model in the hands (&"none" = bare fists).
func set_weapon(model_id: StringName) -> void:
	_armed = model_id != &"none" and model_id != &""
	_gun_model = WeaponModels.get_model(model_id if _armed else &"rifle")
	muzzle_local = _gun_model.muzzle
	gun.mesh = _gun_model.mesh
	flash.position = muzzle_local
	if flash_light != null:
		flash_light.position = muzzle_local + Vector3(0, 0, -0.1)
	gun.visible = _armed and not _dead


## Shows a scope on the rail of the gun in the hands (&"" = none).
func set_scope(scope_id: StringName) -> void:
	scope_mesh.visible = scope_id != &"" and _armed
	if scope_mesh.visible:
		scope_mesh.mesh = WeaponModels.get_scope_mesh(scope_id)
		scope_mesh.position = _gun_model.get("rail", Vector3(0, 0.1, -0.1))


## Shows up to two primary guns slung on the back.
func set_back_weapons(model_ids: Array[StringName]) -> void:
	for k in back_guns.size():
		var bg := back_guns[k]
		if k < model_ids.size() and model_ids[k] != &"none":
			bg.mesh = WeaponModels.get_model(model_ids[k]).mesh
			bg.visible = true
		else:
			bg.visible = false


static func random_outfit(rng: RandomNumberGenerator) -> Dictionary:
	var shirts := [Color(0.85, 0.3, 0.25), Color(0.25, 0.45, 0.78), Color(0.95, 0.76, 0.2),
		Color(0.35, 0.62, 0.36), Color(0.92, 0.92, 0.9), Color(0.56, 0.36, 0.62),
		Color(0.22, 0.22, 0.25), Color(0.2, 0.62, 0.66)]
	var pants := [Color(0.25, 0.31, 0.47), Color(0.36, 0.33, 0.27), Color(0.2, 0.2, 0.23),
		Color(0.44, 0.49, 0.33), Color(0.6, 0.52, 0.4)]
	var skins := [Color(0.98, 0.84, 0.7), Color(0.9, 0.72, 0.55), Color(0.76, 0.55, 0.4),
		Color(0.56, 0.39, 0.28), Color(0.95, 0.78, 0.62)]
	var hairs := [Color(0.14, 0.1, 0.08), Color(0.35, 0.22, 0.12), Color(0.82, 0.66, 0.35),
		Color(0.6, 0.26, 0.12), Color(0.1, 0.1, 0.1)]
	return {
		"shirt": shirts[rng.randi() % shirts.size()],
		"pants": pants[rng.randi() % pants.size()],
		"skin": skins[rng.randi() % skins.size()],
		"hair": hairs[rng.randi() % hairs.size()],
		"shoes": [Color(0.14, 0.14, 0.15), Color(0.45, 0.3, 0.2), Color(0.88, 0.88, 0.88)][rng.randi() % 3],
		"headwear": rng.randi() % 3,
		"hat": [Color(0.8, 0.2, 0.2), Color(0.2, 0.3, 0.6), Color(0.25, 0.4, 0.25), Color(0.9, 0.6, 0.15)][rng.randi() % 4],
	}


static func player_outfit() -> Dictionary:
	return {
		"shirt": Color(0.98, 0.58, 0.16), "pants": Color(0.2, 0.28, 0.45),
		"skin": Color(0.95, 0.78, 0.62), "hair": Color(0.12, 0.09, 0.07),
		"shoes": Color(0.9, 0.9, 0.9), "headwear": 2, "hat": Color(0.15, 0.17, 0.2),
	}


func _build_body_mesh(o: Dictionary) -> ArrayMesh:
	var mb := MeshBuilder.new(true)
	var shirt: Color = o.shirt
	var pants: Color = o.pants
	var skin: Color = o.skin

	mb.current_bone = B.HIPS
	mb.add_box(Vector3(0, 0.94, 0), Vector3(0.34, 0.2, 0.22), pants)
	mb.add_box(Vector3(0, 1.035, 0), Vector3(0.36, 0.04, 0.23), pants.darkened(0.35))   # belt
	mb.current_bone = B.SPINE
	mb.add_box(Vector3(0, 1.14, 0), Vector3(0.34, 0.18, 0.21), shirt)
	mb.current_bone = B.CHEST
	mb.add_box(Vector3(0, 1.34, 0), Vector3(0.42, 0.3, 0.25), shirt)
	mb.add_box(Vector3(0, 1.495, 0), Vector3(0.22, 0.04, 0.17), shirt.darkened(0.15))
	mb.current_bone = B.NECK
	mb.add_box(Vector3(0, 1.54, 0), Vector3(0.1, 0.08, 0.1), skin)

	mb.current_bone = B.HEAD
	mb.add_sphere(Vector3(0, 1.7, 0), Vector3(0.14, 0.155, 0.145), skin, 8, 6)
	mb.add_box(Vector3(-0.05, 1.72, -0.135), Vector3(0.035, 0.05, 0.02), Color(0.08, 0.08, 0.1))
	mb.add_box(Vector3(0.05, 1.72, -0.135), Vector3(0.035, 0.05, 0.02), Color(0.08, 0.08, 0.1))
	mb.add_box(Vector3(0, 1.675, -0.145), Vector3(0.03, 0.04, 0.03), skin.darkened(0.08))
	match int(o.headwear):
		1:  # beanie
			mb.add_sphere(Vector3(0, 1.765, 0.005), Vector3(0.152, 0.11, 0.155), o.hat, 8, 4)
			mb.add_box(Vector3(0, 1.72, 0), Vector3(0.3, 0.04, 0.3), (o.hat as Color).darkened(0.2))
		2:  # cap with visor
			mb.add_sphere(Vector3(0, 1.77, 0.005), Vector3(0.15, 0.1, 0.152), o.hat, 8, 4)
			mb.add_box(Vector3(0, 1.755, -0.17), Vector3(0.2, 0.025, 0.12), (o.hat as Color).darkened(0.2))
		_:  # hair
			mb.add_sphere(Vector3(0, 1.765, 0.02), Vector3(0.15, 0.1, 0.155), o.hair, 8, 4)

	for side in [-1.0, 1.0]:
		var left: bool = side < 0.0
		var sx: float = side * 0.21
		mb.current_bone = B.UPPER_ARM_L if left else B.UPPER_ARM_R
		mb.xform = Transform3D(Basis.IDENTITY, Vector3(sx, 1.14, 0))
		mb.add_frustum(Vector3.ZERO, 0.05, 0.062, 0.32, 6, shirt)
		mb.current_bone = B.LOWER_ARM_L if left else B.LOWER_ARM_R
		mb.xform = Transform3D(Basis.IDENTITY, Vector3(sx, 0.86, 0))
		mb.add_frustum(Vector3.ZERO, 0.04, 0.05, 0.29, 6, skin)
		mb.xform = Transform3D.IDENTITY
		mb.current_bone = B.HAND_L if left else B.HAND_R
		mb.add_box(Vector3(sx, 0.81, 0), Vector3(0.07, 0.1, 0.075), skin)

		var lx: float = side * 0.1
		mb.current_bone = B.UPPER_LEG_L if left else B.UPPER_LEG_R
		mb.xform = Transform3D(Basis.IDENTITY, Vector3(lx, 0.49, 0))
		mb.add_frustum(Vector3.ZERO, 0.065, 0.085, 0.44, 6, pants)
		mb.current_bone = B.LOWER_LEG_L if left else B.LOWER_LEG_R
		mb.xform = Transform3D(Basis.IDENTITY, Vector3(lx, 0.08, 0))
		mb.add_frustum(Vector3.ZERO, 0.055, 0.065, 0.42, 6, pants)
		mb.xform = Transform3D.IDENTITY
		mb.current_bone = B.FOOT_L if left else B.FOOT_R
		mb.add_box(Vector3(lx, 0.045, -0.045), Vector3(0.11, 0.09, 0.25), o.shoes)

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.8
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	return mb.commit(mat)


# --------------------------------------------------------------------------
# Events
# --------------------------------------------------------------------------

## Called when the weapon fires: muzzle flash + gun kick (or a punch).
func on_fired() -> void:
	if not _armed:
		_punch = 1.0
		_punch_side = -_punch_side
		return
	_kick = 1.0
	_flash_time = 0.05
	flash.visible = true
	flash.rotation.z = randf() * TAU
	if flash_light != null:
		flash_light.light_energy = 2.5


func set_step_callback(cb: Callable) -> void:
	_step_callback = cb


## Starts the (procedural) death fall. `dir` = world direction the body falls to.
func play_death(dir_world: Vector3) -> void:
	_dead = true
	_death_t = 0.0
	var d := global_transform.basis.inverse() * dir_world
	d.y = 0.0
	if d.length_squared() < 0.01:
		d = Vector3.BACK
	_death_axis = Vector3.UP.cross(d.normalized()).normalized()
	gun.visible = false
	flash.visible = false
	for bg in back_guns:
		bg.visible = false


func reset_pose() -> void:
	_dead = false
	_death_t = 0.0
	gun.visible = _armed
	_crouch = 0.0
	_prone = 0.0


## Visual-only per-frame update (flash timers). Cheap: run every frame.
func update_effects(delta: float) -> void:
	if _flash_time > 0.0:
		_flash_time -= delta
		if _flash_time <= 0.0:
			flash.visible = false
			if flash_light != null:
				flash_light.light_energy = 0.0


# --------------------------------------------------------------------------
# Procedural animation
# --------------------------------------------------------------------------

func animate(delta: float) -> void:
	var k := clampf(delta, 0.0, 0.25)
	_crouch = move_toward(_crouch, crouch_target, k * 5.0)
	_prone = move_toward(_prone, prone_target, k * 2.8)
	_ads = move_toward(_ads, 1.0 if aiming else 0.0, k * 9.0)
	_sprint = move_toward(_sprint, 1.0 if sprinting else 0.0, k * 6.0)
	_air = move_toward(_air, 1.0 if in_air else 0.0, k * 8.0)
	_swim = move_toward(_swim, 1.0 if swimming else 0.0, k * 3.0)
	_kick = move_toward(_kick, 0.0, k * 12.0)
	_punch = move_toward(_punch, 0.0, k * 4.5)
	_use = move_toward(_use, 1.0 if using_item else 0.0, k * 4.0)
	_fall = move_toward(_fall, 1.0 if air_pose == 2 else 0.0, k * 3.0)
	_chute = move_toward(_chute, 1.0 if air_pose == 3 else 0.0, k * 2.5)
	canopy.visible = _chute > 0.02 and not _dead
	if canopy.visible:
		# Canopy unfolds when opened.
		var open := smoothstep(0.0, 1.0, _chute)
		canopy.scale = Vector3(lerpf(0.15, 1.0, open), open, lerpf(0.3, 1.0, open))
	if _dead:
		_death_t = minf(_death_t + k * 2.2, 1.0)

	var local_vel := basis.inverse() * velocity_world
	local_vel.y = 0.0
	var speed := local_vel.length()
	var move_amt := clampf(speed / 1.5, 0.0, 1.0) * (1.0 - _air)

	# Gait phase: one cycle = two steps. Cycle length grows with speed.
	var cycle := clampf(1.0 + speed * 0.2, 1.0, 2.4)
	_phase = fmod(_phase + k * speed / cycle * TAU, TAU)
	var step_sign := signf(sin(_phase))
	if step_sign != _last_step_sign and move_amt > 0.5 and _prone < 0.5 and _step_callback.is_valid():
		_step_callback.call()
	_last_step_sign = step_sign

	# Lower body turns toward the movement direction (strafing / backpedal).
	var target_yaw := 0.0
	var backward := false
	if speed > 0.4 and _prone < 0.5:
		var ang := atan2(-local_vel.x, -local_vel.z)
		if absf(ang) > 1.95:
			backward = true
			ang = wrapf(ang - PI, -PI, PI)
		target_yaw = clampf(ang, -1.1, 1.1)
	_hips_yaw = lerp_angle(_hips_yaw, target_yaw, clampf(k * 8.0, 0.0, 1.0))

	var pitch := aim_pitch * (1.0 - _sprint * 0.7)

	# ---- Hips -------------------------------------------------------------
	var bob := sin(_phase * 2.0) * 0.025 * move_amt
	var hips_pos := Vector3(0, lerpf(0.93 + bob, 0.6 + bob * 0.5, _crouch), 0)
	var hips_pitch := -0.18 * _crouch - 0.12 * _sprint
	hips_pos = hips_pos.lerp(Vector3(0, 0.17, 0.4), _prone)
	hips_pitch = lerpf(hips_pitch, -PI * 0.5 + 0.04, _prone)
	# Swimming: body almost horizontal near the surface.
	hips_pos = hips_pos.lerp(Vector3(0, 0.85, 0.3), _swim)
	hips_pitch = lerpf(hips_pitch, -1.1, _swim)
	# Freefall: spread-eagle, face down.
	hips_pos = hips_pos.lerp(Vector3(0, 0.9, 0.2), _fall)
	hips_pitch = lerpf(hips_pitch, -1.35, _fall)
	var hips_basis := Basis(Vector3.UP, _hips_yaw) * Basis(Vector3.RIGHT, hips_pitch)

	# Death: rotate the whole skeleton around the feet.
	var root_xf := Transform3D.IDENTITY
	if _dead:
		var fall := smoothstep(0.0, 1.0, _death_t)
		root_xf = Transform3D(Basis(_death_axis, fall * (PI * 0.5 - 0.06) * (1.0 - _prone)), Vector3(0, 0.1 * fall, 0))

	var g: Array[Transform3D] = bone_global
	g[B.ROOT] = root_xf
	g[B.HIPS] = root_xf * Transform3D(hips_basis, hips_pos)

	# ---- Upper body: counter-rotate the hips yaw, distribute the aim pitch ----
	var twist := -_hips_yaw * 0.5
	var crouch_comp := -hips_pitch * (1.0 - _prone) * (1.0 - _swim)
	var spine_rot := Basis(Vector3.UP, twist) * Basis(Vector3.RIGHT, pitch * 0.3 * (1.0 - _prone) + crouch_comp * 0.5)
	var chest_rot := Basis(Vector3.UP, twist) * Basis(Vector3.RIGHT, pitch * 0.3 * (1.0 - _prone) + crouch_comp * 0.5)
	var neck_rot := Basis(Vector3.RIGHT, pitch * 0.15 + _prone * 1.25 + _swim * 0.9)
	var head_rot := Basis(Vector3.RIGHT, pitch * 0.25 + _prone * 0.2)
	g[B.SPINE] = g[B.HIPS] * Transform3D(spine_rot, REST[B.SPINE])
	g[B.CHEST] = g[B.SPINE] * Transform3D(chest_rot, REST[B.CHEST])
	g[B.NECK] = g[B.CHEST] * Transform3D(neck_rot, REST[B.NECK])
	g[B.HEAD] = g[B.NECK] * Transform3D(head_rot, REST[B.HEAD])

	# ---- Gun ------------------------------------------------------------------
	var aim_basis := Basis(Vector3.RIGHT, pitch)
	var anchor := g[B.CHEST] * Vector3(0, 0.17, 0)
	var off_hip: Vector3 = _gun_model.hip
	var off_ads: Vector3 = _gun_model.ads
	var off := off_hip.lerp(off_ads, _ads)
	# Slight inward yaw: the barrel points to the aim point, the handguard stays reachable.
	var gun_basis := aim_basis * Basis(Vector3.UP, 0.08)
	if _sprint > 0.0:
		# Rifle held diagonally across the chest while sprinting.
		var sprint_basis := Basis(Vector3.UP, 0.9) * Basis(Vector3.RIGHT, -0.55)
		gun_basis = Basis(aim_basis.get_rotation_quaternion().slerp(sprint_basis.get_rotation_quaternion(), _sprint))
		off = off.lerp(Vector3(0.02, -0.14, -0.12), _sprint)
	if reload_progress >= 0.0:
		var r := sin(clampf(reload_progress, 0.0, 1.0) * PI)
		gun_basis = gun_basis * Basis(Vector3.FORWARD, 0.5 * r) * Basis(Vector3.RIGHT, -0.25 * r)
	if bolt_progress >= 0.0:
		var bp := sin(clampf(bolt_progress * 1.6, 0.0, 1.0) * PI)
		gun_basis = gun_basis * Basis(Vector3.FORWARD, -0.25 * bp)
	var lowered := maxf(swap_amount, _use)
	if lowered > 0.0:
		# Weapon switch / using an item: the gun dips out of the way.
		gun_basis = gun_basis * Basis(Vector3.RIGHT, -0.9 * lowered)
		off += Vector3(0.0, -0.2, 0.08) * lowered
	off = off.lerp(_gun_model.prone as Vector3, _prone)
	off.z += _kick * 0.06
	gun_transform = Transform3D(gun_basis, anchor + gun_basis * off)
	gun.transform = gun_transform
	gun.visible = _armed and not _dead and _swim < 0.5 and _fall < 0.5 and _chute < 0.5

	# ---- Arms (two-bone IK to the gun grips) ---------------------------------
	var chest_b := g[B.CHEST].basis
	var hand_r := gun_transform * (_gun_model.grip_r as Vector3)
	var hand_l := gun_transform * (_gun_model.grip_l as Vector3)
	if reload_progress >= 0.0:
		hand_l = _reload_hand_path(reload_progress, hand_l, gun_transform * (_gun_model.mag as Vector3), g[B.HIPS] * Vector3(-0.18, 0.05, -0.12))
	if bolt_progress >= 0.0 and _gun_model.has("bolt"):
		# Right hand works the bolt, then returns to the grip.
		var bp := sin(clampf(bolt_progress * 1.6, 0.0, 1.0) * PI)
		hand_r = hand_r.lerp(gun_transform * (_gun_model.bolt as Vector3), bp)
	if not _armed:
		_unarmed_hands(g, move_amt)
		hand_l = _fist_l
		hand_r = _fist_r
	if _fall > 0.0:
		hand_l = hand_l.lerp(g[B.CHEST] * Vector3(-0.55, 0.15, -0.1), _fall)
		hand_r = hand_r.lerp(g[B.CHEST] * Vector3(0.55, 0.15, -0.1), _fall)
	if _chute > 0.0:
		# Hands up on the steering lines.
		hand_l = hand_l.lerp(g[B.CHEST] * Vector3(-0.24, 0.62, 0.02), _chute)
		hand_r = hand_r.lerp(g[B.CHEST] * Vector3(0.24, 0.62, 0.02), _chute)
	if _use > 0.0:
		# Hands together in front of the chest (bandaging / drinking).
		var wobble := sin(_phase * 0.5 + _death_t) * 0.02
		hand_l = hand_l.lerp(g[B.CHEST] * Vector3(-0.07, 0.05 + wobble, -0.26), _use)
		hand_r = hand_r.lerp(g[B.CHEST] * Vector3(0.06, 0.08 - wobble, -0.27), _use)
	if _dead or _swim > 0.5:
		# Relaxed arms.
		hand_l = g[B.CHEST] * Vector3(-0.3, -0.45, 0.05)
		hand_r = g[B.CHEST] * Vector3(0.3, -0.45, 0.05)
	_solve_limb(g, B.UPPER_ARM_L, B.LOWER_ARM_L, B.HAND_L, g[B.CHEST], hand_l, UPPER_ARM, LOWER_ARM, chest_b * Vector3(-0.9, -1.0, 0.5), chest_b * Vector3.FORWARD)
	_solve_limb(g, B.UPPER_ARM_R, B.LOWER_ARM_R, B.HAND_R, g[B.CHEST], hand_r, UPPER_ARM, LOWER_ARM, chest_b * Vector3(1.0, -1.0, 0.6), chest_b * Vector3.FORWARD)

	# ---- Legs (two-bone IK to foot targets) ------------------------------------
	var yaw_b := Basis(Vector3.UP, _hips_yaw)
	var stride := clampf(speed * 0.2, 0.0, 0.5) * move_amt * (1.0 if not backward else -1.0)
	var fwd_dir := yaw_b * Vector3.FORWARD
	for side in [-1.0, 1.0]:
		var left: bool = side < 0.0
		var ph := _phase + (0.0 if left else PI)
		var foot: Vector3
		var sw := -cos(ph) * stride
		var lift := maxf(sin(ph), 0.0) * 0.16 * move_amt
		foot = yaw_b * Vector3(side * (0.11 + 0.04 * _crouch), ANKLE_H + lift, 0.05 * _crouch) + fwd_dir * sw
		foot.y += _air * 0.25
		# Prone / swim: legs trail behind the hips.
		var trail: Vector3 = g[B.HIPS] * Vector3(side * 0.13, -0.84, 0.02)
		trail.y = maxf(trail.y, ANKLE_H)
		foot = foot.lerp(trail, maxf(maxf(_prone, _swim), _fall))
		if _fall > 0.0:
			foot += g[B.HIPS].basis * Vector3(side * 0.12, 0.0, 0.0) * _fall
		if _swim > 0.0:
			foot.y += sin(_phase * 3.0 + ph) * 0.12 * _swim
		if _dead:
			foot = g[B.HIPS] * Vector3(side * 0.13, -0.83, 0.0)
		var knee_pole := fwd_dir.lerp(g[B.HIPS].basis * Vector3.FORWARD, _prone)
		var ul := B.UPPER_LEG_L if left else B.UPPER_LEG_R
		var ll := B.LOWER_LEG_L if left else B.LOWER_LEG_R
		var ft := B.FOOT_L if left else B.FOOT_R
		_solve_limb(g, ul, ll, ft, g[B.HIPS], foot, UPPER_LEG, LOWER_LEG, knee_pole, fwd_dir)
		# Foot flat on the ground facing the hips direction (toes down when prone).
		var flat := Quaternion(yaw_b)
		var q := flat.slerp(g[B.HIPS].basis.get_rotation_quaternion(), maxf(_prone, _swim))
		if _dead:
			q = g[B.LOWER_LEG_L if left else B.LOWER_LEG_R].basis.get_rotation_quaternion()
		g[ft] = Transform3D(Basis(q), g[ft].origin)

	_update_back_guns(g)
	if helmet_mesh.visible:
		helmet_mesh.transform = g[B.HEAD]
	if vest_mesh.visible:
		vest_mesh.transform = g[B.CHEST]
	_apply_to_skeleton()


var _fist_l := Vector3.ZERO
var _fist_r := Vector3.ZERO


## Hand targets without a weapon: arms swing while moving, fists come up in a
## guard when aiming and shoot forward when punching.
func _unarmed_hands(g: Array[Transform3D], move_amt: float) -> void:
	var chest := g[B.CHEST]
	var swing := sin(_phase) * 0.2 * move_amt * (1.0 - _prone)
	var relax_l := chest * Vector3(-0.27, -0.4, swing)
	var relax_r := chest * Vector3(0.27, -0.4, -swing)
	var guard_l := chest * Vector3(-0.12, 0.2, -0.28)
	var guard_r := chest * Vector3(0.13, 0.18, -0.26)
	var guard := maxf(_ads, minf(_punch * 3.0, 1.0)) * (1.0 - _sprint)
	_fist_l = relax_l.lerp(guard_l, guard)
	_fist_r = relax_r.lerp(guard_r, guard)
	if _punch > 0.0:
		var ext := sin((1.0 - _punch) * PI)
		if _punch_side > 0.0:
			_fist_r = _fist_r.lerp(chest * Vector3(0.05, 0.24, -0.58), ext)
		else:
			_fist_l = _fist_l.lerp(chest * Vector3(-0.05, 0.25, -0.58), ext)


## Guns slung diagonally across the back (barrel up over a shoulder).
func _update_back_guns(g: Array[Transform3D]) -> void:
	for k in back_guns.size():
		var bg := back_guns[k]
		if not bg.visible:
			continue
		var side := -1.0 if k == 0 else 1.0
		var b := Basis(Vector3.BACK, side * 0.55) * Basis(Vector3.RIGHT, PI * 0.5)
		bg.transform = g[B.CHEST] * Transform3D(b, Vector3(side * -0.06, -0.12, 0.2 + k * 0.05))


## Left hand path during a reload: grip -> magazine -> belt pouch -> magazine -> grip.
func _reload_hand_path(t: float, grip: Vector3, mag: Vector3, pouch: Vector3) -> Vector3:
	if t < 0.2:
		return grip.lerp(mag, t / 0.2)
	if t < 0.45:
		return mag.lerp(pouch, (t - 0.2) / 0.25)
	if t < 0.7:
		return pouch.lerp(mag, (t - 0.45) / 0.25)
	if t < 0.85:
		return mag
	return mag.lerp(grip, (t - 0.85) / 0.15)


## Two-bone IK. Writes model-space transforms for the 3 bones of the chain.
func _solve_limb(g: Array[Transform3D], upper: int, lower: int, end: int, parent_xf: Transform3D, target: Vector3, la: float, lb: float, pole: Vector3, fwd_hint: Vector3) -> void:
	var root: Vector3 = parent_xf * (REST[upper] as Vector3)
	var to := target - root
	var dist := to.length()
	var dir := to / dist if dist > 0.0001 else Vector3.DOWN
	var d := clampf(dist, 0.02, la + lb - 0.001)
	var cos_a := clampf((la * la + d * d - lb * lb) / (2.0 * la * d), -1.0, 1.0)
	var along := la * cos_a
	var h := la * sqrt(maxf(1.0 - cos_a * cos_a, 0.0))
	var p := pole - dir * pole.dot(dir)
	if p.length_squared() < 0.000001:
		p = dir.cross(Vector3.RIGHT)
	p = p.normalized()
	var mid := root + dir * along + p * h
	var b_upper := _basis_down(mid - root, fwd_hint)
	var b_lower := _basis_down(root + dir * d - mid, fwd_hint)
	g[upper] = Transform3D(b_upper, root)
	g[lower] = Transform3D(b_lower, mid)
	g[end] = Transform3D(b_lower, mid + b_lower * Vector3(0, -lb, 0))


## Basis whose -Y axis points along `dir` (bones point down in the rest pose).
static func _basis_down(dir: Vector3, fwd_hint: Vector3) -> Basis:
	var y := -dir.normalized()
	var z := -(fwd_hint - y * fwd_hint.dot(y))
	if z.length_squared() < 0.000001:
		z = Vector3.BACK - y * y.z
		if z.length_squared() < 0.000001:
			z = Vector3.RIGHT
	z = z.normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, x.cross(y))


## Converts model-space bone transforms into local poses on the Skeleton3D.
func _apply_to_skeleton() -> void:
	var g := bone_global
	skeleton.set_bone_pose_position(B.ROOT, g[B.ROOT].origin)
	skeleton.set_bone_pose_rotation(B.ROOT, g[B.ROOT].basis.get_rotation_quaternion())
	for b in range(1, BONE_COUNT):
		var parent_b: Basis = g[PARENTS[b]].basis
		var local := parent_b.transposed() * g[b].basis
		skeleton.set_bone_pose_rotation(b, local.get_rotation_quaternion())
	# Hips is the only bone that moves (stance height / prone offset).
	var hips_local := g[B.ROOT].affine_inverse() * g[B.HIPS].origin
	skeleton.set_bone_pose_position(B.HIPS, hips_local)


## World position of the muzzle.
func get_muzzle_global() -> Vector3:
	return global_transform * (gun_transform * muzzle_local)


## World-space forward direction of the gun barrel.
func get_gun_forward_global() -> Vector3:
	return (global_transform.basis * (gun_transform.basis * Vector3.FORWARD)).normalized()


func get_bone_global(b: int) -> Transform3D:
	return global_transform * bone_global[b]
