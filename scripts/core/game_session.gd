class_name GameSession
extends Node3D
## Root of the game scene: wires subsystems into the `Game` service locator,
## generates the island, starts the match and handles pause / restart.
##
## Can be run on its own (F6 on scenes/game/game.tscn) with default options.

signal loading_finished
signal exit_to_menu_requested

var config: MatchConfig

@onready var world: GameWorld = $World
@onready var projectiles: ProjectileSystem = $Projectiles
@onready var fx: FxManager = $Fx
@onready var match_manager: MatchManager = $Match
@onready var loot: LootManager = $Loot
@onready var zone: ZoneManager = $Zone
@onready var hud: CanvasLayer = $HUD
@onready var end_screen: EndScreen = $EndScreen
@onready var pause_menu: PauseMenu = $PauseMenu
@onready var inventory_screen: InventoryScreen = $InventoryScreen


func _ready() -> void:
	Game.session = self
	Game.world = world
	Game.projectiles = projectiles
	Game.fx = fx
	Game.match_manager = match_manager
	Game.loot = loot
	Game.zone = zone
	Settings.apply_viewport(get_viewport())
	if config == null:
		config = MatchConfig.new()
		config.map_seed = Settings.last_seed if Settings.last_seed != 0 else 1337
	end_screen.restart_requested.connect(restart_match)
	end_screen.menu_requested.connect(quit_to_menu)
	pause_menu.resume_requested.connect(set_paused.bind(false))
	pause_menu.menu_requested.connect(quit_to_menu)
	hud.visible = false

	await world.generate(config.map_seed)
	match_manager.start_match(config)
	hud.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	loading_finished.emit()


func _exit_tree() -> void:
	if Game.session == self:
		Game.clear()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and world.is_ready and not end_screen.visible:
		set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()


func set_paused(p: bool) -> void:
	if p:
		inventory_screen.close()
	get_tree().paused = p
	pause_menu.visible = p
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if p else Input.MOUSE_MODE_CAPTURED


func restart_match() -> void:
	get_tree().paused = false
	inventory_screen.close()
	end_screen.hide_screen()
	match_manager.restart()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func quit_to_menu() -> void:
	get_tree().paused = false
	if exit_to_menu_requested.get_connections().is_empty():
		# Scene started on its own (F6): load the main menu scene instead.
		get_tree().change_scene_to_file("res://scenes/main/main.tscn")
		return
	exit_to_menu_requested.emit()
