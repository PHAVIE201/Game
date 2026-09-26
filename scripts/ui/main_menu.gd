class_name MainMenu
extends Control
## Title screen: match options (bots, map seed, difficulty) and settings.

signal start_requested(config: MatchConfig)

@onready var bots_spin: SpinBox = $Center/Panel/VBox/Grid/Bots
@onready var seed_spin: SpinBox = $Center/Panel/VBox/Grid/SeedRow/Seed
@onready var seed_random: Button = $Center/Panel/VBox/Grid/SeedRow/Random
@onready var difficulty_option: OptionButton = $Center/Panel/VBox/Grid/Difficulty
@onready var quality_option: OptionButton = $Center/Panel/VBox/Grid/Quality
@onready var sens_slider: HSlider = $Center/Panel/VBox/Grid/Sensitivity
@onready var start_button: Button = $Center/Panel/VBox/Buttons/Start
@onready var quit_button: Button = $Center/Panel/VBox/Buttons/Quit


func _ready() -> void:
	difficulty_option.add_item("Dễ", MatchConfig.Difficulty.EASY)
	difficulty_option.add_item("Thường", MatchConfig.Difficulty.NORMAL)
	difficulty_option.add_item("Khó", MatchConfig.Difficulty.HARD)
	difficulty_option.select(1)
	for q in 3:
		quality_option.add_item(Settings.quality_name(q), q)
	quality_option.select(quality_option.get_item_index(Settings.graphics_quality))
	bots_spin.value = clampi(Settings.last_bot_count, 1, 63)
	seed_spin.value = Settings.last_seed if Settings.last_seed != 0 else randi_range(1, 99999)
	sens_slider.value = Settings.mouse_sensitivity
	seed_random.pressed.connect(func(): seed_spin.value = randi_range(1, 99999))
	start_button.pressed.connect(_on_start)
	quit_button.pressed.connect(func(): get_tree().quit())
	visibility_changed.connect(func():
		if visible:
			start_button.grab_focus())
	start_button.grab_focus()


func _on_start() -> void:
	Sfx.play_2d(&"ui_click")
	var cfg := MatchConfig.new()
	cfg.bot_count = int(bots_spin.value)
	cfg.map_seed = int(seed_spin.value)
	cfg.difficulty = difficulty_option.get_selected_id()
	# Many bots: spread them wider so the start is not a massacre.
	cfg.spawn_radius = clampf(250.0 + cfg.bot_count * 12.0, 300.0, 900.0)
	Settings.last_bot_count = cfg.bot_count
	Settings.last_seed = cfg.map_seed
	Settings.graphics_quality = quality_option.get_selected_id()
	Settings.mouse_sensitivity = sens_slider.value
	Settings.commit()
	start_requested.emit(cfg)
