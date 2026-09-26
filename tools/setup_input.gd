extends Node
## One-off tool: writes the input map into project.godot.
## Usage: godot --headless --path . res://tools/setup_input.tscn
## (Actions can also be edited later in Project Settings > Input Map.)

const KEYS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT],
	"walk": [KEY_CTRL],
	"jump": [KEY_SPACE],
	"crouch": [KEY_C],
	"prone": [KEY_Z],
	"reload": [KEY_R],
	"fire_mode": [KEY_B],
	"pause": [KEY_ESCAPE],
	"toggle_perf": [KEY_F3],
	"interact": [KEY_F],
	"inventory": [KEY_TAB],
	"map": [KEY_M],
	"weapon_1": [KEY_1],
	"weapon_2": [KEY_2],
	"weapon_3": [KEY_3],
	"holster": [KEY_X],
}
const MOUSE := {
	"fire": MOUSE_BUTTON_LEFT,
	"aim": MOUSE_BUTTON_RIGHT,
	"weapon_next": MOUSE_BUTTON_WHEEL_DOWN,
	"weapon_prev": MOUSE_BUTTON_WHEEL_UP,
}


func _ready() -> void:
	for action in KEYS:
		var events := []
		for key in KEYS[action]:
			var ev := InputEventKey.new()
			ev.device = -1   # all devices
			ev.physical_keycode = key
			events.append(ev)
		ProjectSettings.set_setting("input/" + action, {"deadzone": 0.2, "events": events})
	for action in MOUSE:
		var ev := InputEventMouseButton.new()
		ev.device = -1
		ev.button_index = MOUSE[action]
		ProjectSettings.set_setting("input/" + action, {"deadzone": 0.2, "events": [ev]})
	var err := ProjectSettings.save()
	print("[setup_input] saved project.godot: ", error_string(err))
	get_tree().quit()
