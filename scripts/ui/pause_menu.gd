class_name PauseMenu
extends CanvasLayer
## Esc menu: resume, mouse sensitivity, graphics quality, FPS overlay, quit.

signal resume_requested
signal menu_requested

@onready var resume_button: Button = $Dim/Panel/VBox/Resume
@onready var sens_slider: HSlider = $Dim/Panel/VBox/Sensitivity/Slider
@onready var sens_value: Label = $Dim/Panel/VBox/Sensitivity/Value
@onready var quality_option: OptionButton = $Dim/Panel/VBox/Quality/Option
@onready var fps_check: CheckBox = $Dim/Panel/VBox/ShowFps
@onready var menu_button: Button = $Dim/Panel/VBox/Menu
@onready var quit_button: Button = $Dim/Panel/VBox/Quit


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	for q in 3:
		quality_option.add_item(Settings.quality_name(q), q)
	visibility_changed.connect(_sync)
	resume_button.pressed.connect(func(): resume_requested.emit())
	menu_button.pressed.connect(func(): menu_requested.emit())
	quit_button.pressed.connect(func(): get_tree().quit())
	sens_slider.value_changed.connect(func(v: float):
		Settings.mouse_sensitivity = v
		sens_value.text = "%.2f" % v
		Settings.commit())
	quality_option.item_selected.connect(func(idx: int):
		Settings.graphics_quality = quality_option.get_item_id(idx)
		Settings.commit())
	fps_check.toggled.connect(func(on: bool):
		Settings.show_fps = on
		Settings.commit())
	_sync()


func _sync() -> void:
	if not is_node_ready():
		return
	sens_slider.set_value_no_signal(Settings.mouse_sensitivity)
	sens_value.text = "%.2f" % Settings.mouse_sensitivity
	quality_option.select(quality_option.get_item_index(Settings.graphics_quality))
	fps_check.set_pressed_no_signal(Settings.show_fps)
	if visible:
		resume_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		resume_requested.emit()
		get_viewport().set_input_as_handled()
