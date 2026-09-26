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
## Armor worn (&"" = none) and its remaining durability.
var helmet := &""
var helmet_durability := 0.0
var vest := &""
var vest_durability := 0.0
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


## Puts on a helmet / vest. `durability` < 0 = brand new. Returns the old
## piece as [id, durability] (id &"" if none).
func wear(id: StringName, durability := -1.0) -> Array:
	var info := ItemDB.get_info(id)
	var full := float(info.get("durability", 100.0))
	var dur := full if durability < 0.0 else durability
	var old := []
	if ItemDB.kind_of(id) == ItemDB.Kind.HELMET:
		old = [helmet, helmet_durability]
		helmet = id
		helmet_durability = dur
	else:
		old = [vest, vest_durability]
		vest = id
		vest_durability = dur
	changed.emit()
	return old


## Takes off the helmet (`vest` false) or the vest. Returns [id, durability].
func take_off(is_vest: bool) -> Array:
	var old := [vest, vest_durability] if is_vest else [helmet, helmet_durability]
	if is_vest:
		vest = &""
		vest_durability = 0.0
	else:
		helmet = &""
		helmet_durability = 0.0
	changed.emit()
	return old


## Lets the armor covering a body part soak up damage. Returns the damage
## that goes through. `broke` (out) is set when the piece is destroyed.
func absorb(part: int, amount: float, result: Dictionary) -> float:
	var head := part == DamageInfo.Part.HEAD
	var id := helmet if head else vest
	if id == &"" or part == DamageInfo.Part.LIMB:
		return amount
	var reduction := float(ItemDB.get_info(id).get("reduction", 0.0))
	var through := amount * (1.0 - reduction)
	# The armor wears down by the damage it stopped plus a share of the hit.
	var wear_amount := amount * reduction + amount * 0.25
	if head:
		helmet_durability -= wear_amount
		if helmet_durability <= 0.0:
			result["broke"] = helmet
			helmet = &""
			helmet_durability = 0.0
	else:
		vest_durability -= wear_amount
		if vest_durability <= 0.0:
			result["broke"] = vest
			vest = &""
			vest_durability = 0.0
	changed.emit()
	return through


## 0..1 durability of a worn piece (for the HUD).
func armor_ratio(is_vest: bool) -> float:
	var id := vest if is_vest else helmet
	if id == &"":
		return 0.0
	var full := float(ItemDB.get_info(id).get("durability", 100.0))
	return clampf((vest_durability if is_vest else helmet_durability) / full, 0.0, 1.0)


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
	helmet = &""
	helmet_durability = 0.0
	vest = &""
	vest_durability = 0.0
	changed.emit()
