class_name StateMachine
extends RefCounted
## Minimal finite state machine for bots.
##
## States are lightweight RefCounted objects (not nodes) so 63 bots x N states
## cost almost nothing. Add new behaviours (loot, heal, move to zone, parachute...)
## by writing a BotState subclass and registering it in BotBrain._build_states().

var brain: BotBrain
var states: Dictionary = {}   # StringName -> BotState
var current: BotState = null
var current_name: StringName = &""
var time_in_state := 0.0


func _init(p_brain: BotBrain) -> void:
	brain = p_brain


func add(state_name: StringName, state: BotState) -> void:
	state.brain = brain
	state.name = state_name
	states[state_name] = state


func change(state_name: StringName, params: Dictionary = {}) -> void:
	if not states.has(state_name):
		push_error("StateMachine: unknown state %s" % state_name)
		return
	if current != null:
		current.exit()
	current = states[state_name]
	current_name = state_name
	time_in_state = 0.0
	current.enter(params)


func update(delta: float) -> void:
	time_in_state += delta
	if current != null:
		current.update(delta)


func is_in(state_name: StringName) -> bool:
	return current_name == state_name
