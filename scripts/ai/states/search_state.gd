class_name SearchState
extends BotState
## Under-equipped: walk to the nearest building not searched yet (inside the
## zone), then loot it. Without a gun and with no house left, go for guns
## lying around (dropped by the dead) further away.

const GUN_SEARCH_RADIUS := 260.0

var _building: Dictionary = {}
var _timeout := 0.0


func enter(params: Dictionary) -> void:
	_building = brain.pick_building_to_search(params.get("toward_zone", false))
	if _building.is_empty():
		var gun := _nearest_gun()
		if gun != Vector3.INF:
			_building = {"center": Vector2(gun.x, gun.z), "floor_y": gun.y}
		else:
			brain.fsm.change(&"wander", {"no_search": true})
			return
	var c := get_character()
	var center := _center(_building)
	brain.move_to(center, BotBrain.MoveMode.RUN, 4.0)
	brain.look_along_movement()
	c.request_stance(GameCharacter.Stance.STAND)
	_timeout = 20.0 + c.global_position.distance_to(center) / 3.5


## Closest gun on the ground in the zone (the bot "heard" the fights), or INF.
func _nearest_gun() -> Vector3:
	if brain.has_usable_gun() or Game.loot == null:
		return Vector3.INF
	var c := get_character()
	var best := Vector3.INF
	var best_d := GUN_SEARCH_RADIUS
	for p in Game.loot.find_near(c.global_position, GUN_SEARCH_RADIUS, 30.0):
		if ItemDB.kind_of(p.id) != ItemDB.Kind.WEAPON:
			continue
		if Game.zone != null and Game.zone.is_active() and not Game.zone.is_inside(p.pos, 5.0):
			continue
		var d := c.global_position.distance_to(p.pos)
		if d < best_d:
			best_d = d
			best = p.pos
	return best


static func _center(b: Dictionary) -> Vector3:
	return Vector3(b.center.x, b.floor_y, b.center.y)


func update(delta: float) -> void:
	_timeout -= delta
	var c := get_character()
	var d := Vector2(c.global_position.x - _building.center.x, c.global_position.z - _building.center.y).length()
	if d < 9.0 or brain.nav.arrived:
		if _building.has("seed"):
			brain.mark_searched(_building)
		brain.fsm.change(&"loot", {"budget": 35.0})
	elif brain.nav.failed or _timeout <= 0.0:
		brain.mark_searched(_building)
		brain.fsm.change(&"idle")
