class_name ItemDB
## Every lootable item of the game, keyed by id (StringName).
##
## Weapons use their WeaponData id (k7, v9...) and are described by WeaponDB;
## everything else lives in ITEMS below. Numbers are gameplay tuning:
##   weight  : backpack space per unit
##   stack   : amount found in one pickup on the ground
##   level   : equipment tier (backpack / helmet / vest)

enum Kind { WEAPON, AMMO, BACKPACK, HELMET, VEST, HEAL, BOOST, THROWABLE, SCOPE }

## Backpack space without any backpack.
const BASE_CAPACITY := 80.0

const ITEMS := {
	&"ammo_rifle": {"name": "Đạn 5.8 mm", "kind": Kind.AMMO, "weight": 0.5, "stack": 30, "color": Color(0.45, 0.52, 0.28)},
	&"ammo_smg": {"name": "Đạn 9 mm", "kind": Kind.AMMO, "weight": 0.4, "stack": 30, "color": Color(0.3, 0.45, 0.62)},
	&"ammo_shotgun": {"name": "Đạn 12G", "kind": Kind.AMMO, "weight": 1.25, "stack": 10, "color": Color(0.78, 0.22, 0.18)},
	&"ammo_sniper": {"name": "Đạn 7.6 mm", "kind": Kind.AMMO, "weight": 1.0, "stack": 15, "color": Color(0.52, 0.38, 0.22)},

	&"backpack_1": {"name": "Balo cấp 1", "kind": Kind.BACKPACK, "level": 1, "capacity": 100.0, "weight": 0.0, "stack": 1, "color": Color(0.72, 0.62, 0.42)},
	&"backpack_2": {"name": "Balo cấp 2", "kind": Kind.BACKPACK, "level": 2, "capacity": 150.0, "weight": 0.0, "stack": 1, "color": Color(0.42, 0.48, 0.3)},
	&"backpack_3": {"name": "Balo cấp 3", "kind": Kind.BACKPACK, "level": 3, "capacity": 200.0, "weight": 0.0, "stack": 1, "color": Color(0.3, 0.26, 0.22)},
}


static func exists(id: StringName) -> bool:
	return ITEMS.has(id) or WeaponDB.get_weapon(id) != null


static func get_info(id: StringName) -> Dictionary:
	return ITEMS.get(id, {})


static func kind_of(id: StringName) -> int:
	if ITEMS.has(id):
		return int(ITEMS[id].kind)
	return Kind.WEAPON


static func display_name(id: StringName) -> String:
	if ITEMS.has(id):
		return String(ITEMS[id].name)
	var w := WeaponDB.get_weapon(id)
	return w.display_name if w != null else String(id)


static func weight_of(id: StringName) -> float:
	return float(ITEMS[id].get("weight", 0.0)) if ITEMS.has(id) else 0.0


static func stack_of(id: StringName) -> int:
	return int(ITEMS[id].get("stack", 1)) if ITEMS.has(id) else 1


static func level_of(id: StringName) -> int:
	return int(ITEMS[id].get("level", 0)) if ITEMS.has(id) else 0


## Items that go into the backpack (counted, weigh something).
static func is_stackable(id: StringName) -> bool:
	match kind_of(id):
		Kind.AMMO, Kind.HEAL, Kind.BOOST, Kind.THROWABLE, Kind.SCOPE:
			return true
		_:
			return false


## Ids of one kind, in ITEMS order.
static func ids_of_kind(kind: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in ITEMS:
		if int(ITEMS[id].kind) == kind:
			out.append(id)
	return out
