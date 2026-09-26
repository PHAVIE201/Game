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

	# Armor: `reduction` = share of the damage absorbed, `durability` = damage it can take.
	&"helmet_1": {"name": "Mũ cấp 1", "kind": Kind.HELMET, "level": 1, "reduction": 0.3, "durability": 80.0, "stack": 1, "color": Color(0.55, 0.58, 0.4)},
	&"helmet_2": {"name": "Mũ cấp 2", "kind": Kind.HELMET, "level": 2, "reduction": 0.4, "durability": 150.0, "stack": 1, "color": Color(0.3, 0.38, 0.3)},
	&"helmet_3": {"name": "Mũ cấp 3", "kind": Kind.HELMET, "level": 3, "reduction": 0.55, "durability": 230.0, "stack": 1, "color": Color(0.16, 0.17, 0.19)},
	&"vest_1": {"name": "Áo giáp cấp 1", "kind": Kind.VEST, "level": 1, "reduction": 0.3, "durability": 200.0, "stack": 1, "color": Color(0.6, 0.6, 0.45)},
	&"vest_2": {"name": "Áo giáp cấp 2", "kind": Kind.VEST, "level": 2, "reduction": 0.4, "durability": 220.0, "stack": 1, "color": Color(0.32, 0.4, 0.3)},
	&"vest_3": {"name": "Áo giáp cấp 3", "kind": Kind.VEST, "level": 3, "reduction": 0.55, "durability": 250.0, "stack": 1, "color": Color(0.2, 0.21, 0.24)},

	# Healing: `heal` HP up to `heal_cap`; boosts fill the boost bar instead.
	&"bandage": {"name": "Băng gạc", "kind": Kind.HEAL, "heal": 10.0, "heal_cap": 75.0, "use_time": 4.0, "weight": 2.0, "stack": 5, "color": Color(0.95, 0.93, 0.85)},
	&"first_aid": {"name": "Bộ sơ cứu", "kind": Kind.HEAL, "heal": 100.0, "heal_cap": 75.0, "use_time": 6.0, "weight": 10.0, "stack": 1, "color": Color(0.92, 0.92, 0.9)},
	&"medkit": {"name": "Hộp y tế", "kind": Kind.HEAL, "heal": 100.0, "heal_cap": 100.0, "use_time": 8.0, "weight": 20.0, "stack": 1, "color": Color(0.85, 0.2, 0.2)},
	&"energy_drink": {"name": "Nước tăng lực", "kind": Kind.BOOST, "boost": 40.0, "use_time": 4.0, "weight": 4.0, "stack": 1, "color": Color(0.2, 0.75, 0.95)},
	&"painkiller": {"name": "Thuốc giảm đau", "kind": Kind.BOOST, "boost": 60.0, "use_time": 6.0, "weight": 10.0, "stack": 1, "color": Color(0.95, 0.65, 0.2)},

	# Scopes: `level` 1..4 (WeaponData.max_scope limits what fits), `zoom` = magnification.
	&"scope_reddot": {"name": "Ống ngắm chấm đỏ", "kind": Kind.SCOPE, "level": 1, "zoom": 1.3, "weight": 5.0, "stack": 1, "color": Color(0.2, 0.2, 0.22)},
	&"scope_2x": {"name": "Ống ngắm 2x", "kind": Kind.SCOPE, "level": 2, "zoom": 2.0, "weight": 5.0, "stack": 1, "color": Color(0.25, 0.25, 0.27)},
	&"scope_4x": {"name": "Ống ngắm 4x", "kind": Kind.SCOPE, "level": 3, "zoom": 4.0, "weight": 5.0, "stack": 1, "color": Color(0.22, 0.26, 0.22)},
	&"scope_8x": {"name": "Ống ngắm 8x", "kind": Kind.SCOPE, "level": 4, "zoom": 8.0, "weight": 5.0, "stack": 1, "color": Color(0.18, 0.18, 0.2)},

	# Throwables (see ThrowableSystem).
	&"grenade_frag": {"name": "Lựu đạn", "kind": Kind.THROWABLE, "weight": 12.0, "stack": 1, "color": Color(0.3, 0.38, 0.24)},
	&"grenade_smoke": {"name": "Bom khói", "kind": Kind.THROWABLE, "weight": 10.0, "stack": 1, "color": Color(0.55, 0.58, 0.6)},
}

## Heals / boosts in the order of the quick-use keys (4..8).
const QUICK_USE: Array[StringName] = [&"bandage", &"first_aid", &"medkit", &"energy_drink", &"painkiller"]


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


## Magnification of a scope (1 = iron sights).
static func zoom_of(id: StringName) -> float:
	return float(ITEMS[id].get("zoom", 1.0)) if ITEMS.has(id) else 1.0


## Short tag for the HUD ("4x", "chấm đỏ").
static func scope_tag(id: StringName) -> String:
	if id == &"":
		return ""
	if id == &"scope_reddot":
		return "chấm đỏ"
	return "%dx" % roundi(zoom_of(id))


static func is_armor(id: StringName) -> bool:
	var k := kind_of(id)
	return k == Kind.HELMET or k == Kind.VEST


static func is_consumable(id: StringName) -> bool:
	var k := kind_of(id)
	return k == Kind.HEAL or k == Kind.BOOST


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
