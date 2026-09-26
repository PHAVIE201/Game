class_name BotState
extends RefCounted
## Base class for bot behaviours. Override enter / exit / update.
##
## States reach the state machine through `brain.fsm` (no direct reference),
## otherwise StateMachine <-> BotState would form a RefCounted cycle and leak.

var brain: BotBrain
var name: StringName


func enter(_params: Dictionary) -> void:
	pass


func exit() -> void:
	pass


func update(_delta: float) -> void:
	pass


## Shortcut to the controlled character.
func get_character() -> GameCharacter:
	return brain.character
