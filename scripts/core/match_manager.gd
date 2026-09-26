class_name MatchManager
extends Node
## Match rules: spawning, alive tracking, win / lose, restart.
##
## States are ready for later phases:
##   IDLE -> (phase 2: PLANE / DROPPING) -> IN_PROGRESS -> ENDED
## Phase 1 spawns everyone on the ground directly.

enum State { IDLE, IN_PROGRESS, ENDED }

const PLAYER_SCENE := preload("res://scenes/characters/player.tscn")
const BOT_SCENE := preload("res://scenes/characters/bot.tscn")

@export var characters_root_path: NodePath

var config: MatchConfig
var state: int = State.IDLE
var participants: Array[GameCharacter] = []
var alive: Array[GameCharacter] = []
var player: GameCharacter = null
var match_start_msec := 0

var _characters_root: Node3D
var _brains: Array[BotBrain] = []
var _rng := RandomNumberGenerator.new()
var _player_result_sent := false


func _ready() -> void:
	_characters_root = get_node(characters_root_path) as Node3D
	Events.character_died.connect(_on_character_died)
	Events.shot_fired.connect(_on_shot_fired)


func start_match(p_config: MatchConfig) -> void:
	config = p_config
	_rng.randomize()
	_player_result_sent = false
	var world := Game.world
	if Game.loot != null:
		Game.loot.spawn_world_loot(world, _rng)

	# Player: start in a random town square (open area by design).
	var player_pos: Vector3
	var towns := world.get_towns()
	if not towns.is_empty():
		var town: Dictionary = towns[_rng.randi() % towns.size()]
		var c: Vector2 = town.center
		player_pos = world.find_spawn_point(_rng, Vector3(c.x, 0.0, c.y), 0.0, 8.0)
	else:
		player_pos = world.random_land_point(_rng)
	player = _spawn(PLAYER_SCENE, player_pos, _rng.randf() * TAU, "Bạn")
	Game.player = player
	_give_starting_kit(player)

	# Bots around the player (phase 2 replaces this with the plane drop).
	var used_names := {}
	for i in config.bot_count:
		var p := world.find_spawn_point(_rng, player_pos, config.min_spawn_distance, config.spawn_radius)
		var bot := _spawn(BOT_SCENE, p, _rng.randf() * TAU, NameGenerator.generate(_rng, used_names))
		_give_starting_kit(bot)
		var brain := bot.get_node("BotBrain") as BotBrain
		if brain != null:
			_brains.append(brain)

	match_start_msec = Time.get_ticks_msec()
	state = State.IN_PROGRESS
	Events.match_started.emit()
	Events.match_state_changed.emit(state)
	Events.alive_count_changed.emit(alive.size(), participants.size())
	Events.hud_message.emit("%d người chơi - Hãy là người sống sót cuối cùng!" % participants.size(), 4.0)


func _spawn(scene: PackedScene, pos: Vector3, yaw: float, display_name: String) -> GameCharacter:
	var c := scene.instantiate() as GameCharacter
	c.display_name = display_name
	c.position = pos + Vector3(0, 0.15, 0)
	c.aim_yaw = yaw
	_characters_root.add_child(c)
	participants.append(c)
	alive.append(c)
	Events.character_spawned.emit(c)
	return c


## Weapons a character starts with (until looting replaces it).
func _give_starting_kit(c: GameCharacter) -> void:
	var primaries: Array[WeaponData] = [WeaponDB.K7, WeaponDB.V9, WeaponDB.B12, WeaponDB.D3, WeaponDB.R8]
	var weights: Array[float] = [0.32, 0.24, 0.16, 0.15, 0.13]
	if c.is_player:
		# A pistol to defend yourself while looting the town.
		c.give_weapon(WeaponDB.P1)
		c.inventory.add_ammo(WeaponDB.P1.ammo_type, 30)
		return
	# Bots cannot loot yet: they start armed, with endless ammo.
	c.inventory.unlimited = true
	var main := primaries[_weighted_pick(weights)]
	c.give_weapon(main)
	c.inventory.add_ammo(main.ammo_type, 9999)
	if _rng.randf() < 0.5:
		c.give_weapon(WeaponDB.P1, -1, false)
		c.inventory.add_ammo(WeaponDB.P1.ammo_type, 9999)


func _weighted_pick(weights: Array[float]) -> int:
	var total := 0.0
	for w in weights:
		total += w
	var r := _rng.randf() * total
	for k in weights.size():
		r -= weights[k]
		if r <= 0.0:
			return k
	return weights.size() - 1


## Removes every character and starts a new match on the same island.
func restart() -> void:
	clear()
	start_match(config)


func clear() -> void:
	state = State.IDLE
	for c in participants:
		if is_instance_valid(c):
			c.queue_free()
	participants.clear()
	alive.clear()
	_brains.clear()
	player = null
	Game.player = null
	if Game.projectiles != null:
		Game.projectiles.clear()
	if Game.fx != null:
		Game.fx.clear()
	if Game.loot != null:
		Game.loot.clear()


func get_alive_count() -> int:
	return alive.size()


func get_elapsed_seconds() -> float:
	return (Time.get_ticks_msec() - match_start_msec) / 1000.0


func _on_character_died(victim_node: Node, info_ref: RefCounted) -> void:
	var victim := victim_node as GameCharacter
	if victim == null or not alive.has(victim):
		return
	alive.erase(victim)
	if Game.loot != null:
		Game.loot.drop_everything(victim)
	var info := info_ref as DamageInfo
	Events.alive_count_changed.emit(alive.size(), participants.size())
	if state != State.IN_PROGRESS:
		return
	if victim == player:
		_send_player_result(false, alive.size() + 1, info)
		if alive.size() <= 1:
			state = State.ENDED
			Events.match_state_changed.emit(state)
	elif alive.size() == 1 and alive[0] == player:
		state = State.ENDED
		Events.match_state_changed.emit(state)
		_send_player_result(true, 1, null)
	elif alive.size() <= 5 and alive.size() > 1:
		Events.hud_message.emit("Còn %d người sống sót" % alive.size(), 2.5)


func _send_player_result(won: bool, placement: int, info: DamageInfo) -> void:
	if _player_result_sent or player == null:
		return
	_player_result_sent = true
	var killer_name := ""
	var weapon_name := ""
	var headshot := false
	var distance := 0.0
	if info != null:
		var killer := info.attacker as GameCharacter
		if killer != null:
			killer_name = killer.display_name
		weapon_name = info.weapon_name
		headshot = info.is_headshot()
		distance = info.distance
	Events.player_match_result.emit({
		"won": won,
		"placement": placement,
		"total": participants.size(),
		"kills": player.kills,
		"damage": player.damage_dealt,
		"time_alive": player.get_time_alive(),
		"killer_name": killer_name,
		"weapon": weapon_name,
		"headshot": headshot,
		"distance": distance,
	})


## Bots "hear" gunshots within the weapon's loudness radius.
func _on_shot_fired(shooter_node: Node, pos: Vector3, radius: float) -> void:
	var shooter := shooter_node as GameCharacter
	if shooter == null:
		return
	for b in _brains:
		if is_instance_valid(b) and not b.character.is_dead:
			b.on_heard_shot(pos, shooter, radius)
