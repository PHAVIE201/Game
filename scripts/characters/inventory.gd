class_name Inventory
extends RefCounted
## Items carried by a character.
##
## Phase 1 only tracks ammo. Phase 2 will add weapon slots, attachments,
## equipment (helmet / vest / backpack with levels), consumables (bandage, medkit,
## energy drink) and throwables. Keep all item logic here so both the player and
## bots use exactly the same rules.

signal changed

var ammo: Dictionary = {}   # StringName -> int


func get_ammo(type: StringName) -> int:
	return int(ammo.get(type, 0))


func add_ammo(type: StringName, amount: int) -> void:
	ammo[type] = get_ammo(type) + amount
	changed.emit()


## Removes up to `amount` rounds, returns how many were actually taken.
func take_ammo(type: StringName, amount: int) -> int:
	var have := get_ammo(type)
	var taken := mini(have, amount)
	ammo[type] = have - taken
	changed.emit()
	return taken
