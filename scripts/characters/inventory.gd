class_name Inventory
extends RefCounted
## Items carried by a character (weapons live in GameCharacter.slots).
##
## - `items`: stackable items (ammo, heals, boosts, throwables, scopes) and counts.
## - equipment: backpack level (more space), helmet and vest (see ItemDB).
## Space is limited by weight (ItemDB.weight_of). All loot rules go through
## here so the player and bots follow exactly the same rules.

signal changed

var items: Dictionary = {}   # StringName -> int
var backpack := &""
## Bots of the early phases carry unlimited ammo and ignore weight.
var unlimited := false


func get_count(id: StringName) -> int:
	return int(items.get(id, 0))


func capacity() -> float:
	var cap := ItemDB.BASE_CAPACITY
	if backpack != &"":
		cap += float(ItemDB.get_info(backpack).get("capacity", 0.0))
	return cap


func used_weight() -> float:
	var w := 0.0
	for id in items:
		w += ItemDB.weight_of(id) * int(items[id])
	return w


## How many units of `id` still fit.
func room_for(id: StringName) -> int:
	var unit := ItemDB.weight_of(id)
	if unlimited or unit <= 0.0:
		return 1 << 30
	return maxi(floori((capacity() - used_weight()) / unit + 0.0001), 0)


## Adds up to `amount` units (limited by space). Returns how many were added.
func add(id: StringName, amount: int) -> int:
	var n := mini(amount, room_for(id))
	if n <= 0:
		return 0
	items[id] = get_count(id) + n
	changed.emit()
	return n


## Removes up to `amount` units, returns how many were actually taken.
func remove(id: StringName, amount: int) -> int:
	var have := get_count(id)
	var taken := mini(have, amount)
	if taken <= 0:
		return 0
	if have - taken <= 0:
		items.erase(id)
	else:
		items[id] = have - taken
	changed.emit()
	return taken


## Swaps the backpack. Returns the previous one (&"" if none).
func set_backpack(id: StringName) -> StringName:
	var old := backpack
	backpack = id
	changed.emit()
	return old


## Ammo helpers used by Weapon (ammo is just another stackable item).
func get_ammo(type: StringName) -> int:
	return get_count(type)


func add_ammo(type: StringName, amount: int) -> int:
	return add(type, amount)


func take_ammo(type: StringName, amount: int) -> int:
	return remove(type, amount)


func clear() -> void:
	items.clear()
	backpack = &""
	changed.emit()
