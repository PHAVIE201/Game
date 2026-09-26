class_name PlayerController
extends Node
## Converts keyboard / mouse input into the parent GameCharacter's intent.

## Radians of rotation per pixel of mouse movement at sensitivity 1.0.
const BASE_SENSITIVITY := 0.0022
const PITCH_MIN := -1.4
const PITCH_MAX := 1.25

@export var camera_rig_path: NodePath = ^"../CameraRig"

var character: GameCharacter
var camera_rig: ThirdPersonCamera


func _ready() -> void:
	character = get_parent() as GameCharacter
	camera_rig = get_node(camera_rig_path) as ThirdPersonCamera


var _arc_shown := false


func _unhandled_input(event: InputEvent) -> void:
	if character.is_dead or get_tree().paused:
		return
	if event.is_action_released("throw_frag") or event.is_action_released("throw_smoke"):
		character.release_throw()
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and captured:
		var motion := event as InputEventMouseMotion
		var sens := BASE_SENSITIVITY * Settings.mouse_sensitivity * camera_rig.get_sensitivity_scale()
		character.aim_yaw = wrapf(character.aim_yaw - motion.relative.x * sens, -PI, PI)
		var dy := motion.relative.y * sens * (-1.0 if Settings.invert_y else 1.0)
		character.aim_pitch = clampf(character.aim_pitch - dy, PITCH_MIN, PITCH_MAX)
	elif event is InputEventMouseButton and not captured and event.pressed:
		# Click back into the game after the mouse was released.
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("jump"):
		character.request_jump()
	elif event.is_action_pressed("crouch"):
		character.toggle_crouch()
	elif event.is_action_pressed("prone"):
		character.toggle_prone()
	elif event.is_action_pressed("reload"):
		character.request_reload()
	elif event.is_action_pressed("fire_mode"):
		character.cycle_fire_mode()
		Sfx.play_2d(&"ui_click", -8.0)
	elif event.is_action_pressed("interact"):
		if character.air_state == GameCharacter.AirState.PLANE or character.air_state == GameCharacter.AirState.FREEFALL:
			character.request_jump()
		elif Game.loot != null and Game.loot.player_target != null:
			Game.loot.take(character, Game.loot.player_target)
	elif event.is_action_pressed("weapon_1"):
		character.equip_slot(GameCharacter.SLOT_PRIMARY_1)
	elif event.is_action_pressed("weapon_2"):
		character.equip_slot(GameCharacter.SLOT_PRIMARY_2)
	elif event.is_action_pressed("weapon_3"):
		character.equip_slot(GameCharacter.SLOT_PISTOL)
	elif event.is_action_pressed("holster"):
		character.holster()
	elif event.is_action_pressed("throw_frag") or event.is_action_pressed("throw_smoke"):
		var id := &"grenade_frag" if event.is_action_pressed("throw_frag") else &"grenade_smoke"
		if not character.begin_throw(id) and character.inventory.get_count(id) <= 0:
			Events.loot_message.emit("Không có " + ItemDB.display_name(id))
	elif event.is_action_pressed("quick_heal"):
		var id := character.pick_heal()
		if id == &"":
			Events.loot_message.emit("Không cần / không có đồ hồi máu phù hợp")
		else:
			character.use_item(id)
	elif _quick_use_key(event) != &"":
		var id := _quick_use_key(event)
		if not character.use_item(id) and character.using_item != id:
			if character.inventory.get_count(id) <= 0:
				Events.loot_message.emit("Không có " + ItemDB.display_name(id))
			else:
				Events.loot_message.emit("Chưa dùng được " + ItemDB.display_name(id))
	elif event.is_action_pressed("weapon_next"):
		character.cycle_weapon(1)
	elif event.is_action_pressed("weapon_prev"):
		character.cycle_weapon(-1)


func _quick_use_key(event: InputEvent) -> StringName:
	for id in ItemDB.QUICK_USE:
		if event.is_action_pressed("use_" + String(id)):
			return id
	return &""


func _process(_delta: float) -> void:
	if character.is_dead:
		character.input_move = Vector2.ZERO
		character.input_fire = false
		character.input_aim = false
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not get_tree().paused
	character.input_move = Input.get_vector("move_left", "move_right", "move_back", "move_forward") if captured else Vector2.ZERO
	character.input_sprint = captured and Input.is_action_pressed("sprint")
	character.input_walk = captured and Input.is_action_pressed("walk")
	character.input_aim = captured and Input.is_action_pressed("aim")
	character.input_fire = captured and Input.is_action_pressed("fire")
	_update_aim_point()
	_update_throw_arc()


## Shows where the grenade will fly while it is held.
func _update_throw_arc() -> void:
	if Game.throwables == null:
		return
	if character.throwing_item != &"" and not character.is_dead:
		Game.throwables.show_arc(Game.throwables.predict(character.get_throw_origin(), character.get_throw_velocity()))
		_arc_shown = true
	elif _arc_shown:
		Game.throwables.show_arc(PackedVector3Array())
		_arc_shown = false


## The crosshair is the screen center: find what it points at, bullets leave the
## muzzle toward that point (standard third-person shooter trick).
func _update_aim_point() -> void:
	var cam := camera_rig.camera
	if cam == null or Game.projectiles == null:
		character.has_aim_point = false
		return
	var origin := cam.global_position
	var fwd := -cam.global_transform.basis.z
	# Start the ray level with the character so objects behind it are ignored.
	var skip := maxf((character.get_eye_position() - origin).dot(fwd) - 0.3, 0.0)
	var from := origin + fwd * skip
	var to := origin + fwd * 1000.0
	var hit := Game.projectiles.raycast(from, to, character)
	character.aim_point = hit.position if not hit.is_empty() else to
	character.has_aim_point = true
