class_name SearchState
extends BotState
## Under-equipped: walk to the nearest building not searched yet (inside the
## zone), then loot it.

var _building: Dictionary = {}
var _timeout := 0.0


func enter(_params: Dictionary) -> void:
	_building = brain.pick_building_to_search()
	if _building.is_empty():
		brain.fsm.change(&"wander", {"no_search": true})
		return
	var c := get_character()
	var center := _center(_building)
	brain.move_to(center, BotBrain.MoveMode.RUN, 4.0)
	brain.look_along_movement()
	c.request_stance(GameCharacter.Stance.STAND)
	_timeout = 20.0 + c.global_position.distance_to(center) / 3.5


static func _center(b: Dictionary) -> Vector3:
	return Vector3(b.center.x, b.floor_y, b.center.y)


func update(delta: float) -> void:
	_timeout -= delta
	var c := get_character()
	var d := Vector2(c.global_position.x - _building.center.x, c.global_position.z - _building.center.y).length()
	if d < 9.0 or brain.nav.arrived:
		brain.mark_searched(_building)
		brain.fsm.change(&"loot", {"budget": 35.0})
	elif brain.nav.failed or _timeout <= 0.0:
		brain.mark_searched(_building)
		brain.fsm.change(&"idle")
