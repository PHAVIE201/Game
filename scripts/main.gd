extends Node
## Application entry point: main menu <-> game session, loading overlay.

const GAME_SCENE := preload("res://scenes/game/game.tscn")

@onready var menu: MainMenu = $MainMenu
@onready var loading: LoadingScreen = $LoadingScreen

var session: GameSession = null


func _ready() -> void:
	menu.start_requested.connect(start_game)
	Settings.apply_viewport(get_viewport())
	# Optional automation for headless tests / screenshots (see tools/README).
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--autotest") or a.begins_with("--screenshots") or a.begins_with("--duel"):
			var script := load("res://scripts/debug/automation.gd") as GDScript
			if script == null or not script.can_instantiate():
				push_error("Automation script failed to load")
				get_tree().quit(1)
				return
			var auto: Node = script.new()
			auto.name = "Automation"
			add_child(auto)
			break


func start_game(config: MatchConfig) -> void:
	if session != null:
		return
	menu.hide()
	loading.show_loading()
	session = GAME_SCENE.instantiate() as GameSession
	session.config = config
	session.loading_finished.connect(loading.hide_loading)
	session.exit_to_menu_requested.connect(back_to_menu)
	add_child(session)


func back_to_menu() -> void:
	if session != null:
		session.queue_free()
		session = null
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu.show()
