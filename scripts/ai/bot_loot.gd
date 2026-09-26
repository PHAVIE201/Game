class_name BotLoot
## How much a bot wants an item on the ground (0 = ignore). Shared by the loot
## state and opportunistic looting; the same loot rules as the player apply
## when it is actually taken (LootManager.take).

## Preference between guns (bots like versatile rifles most).
const WEAPON_TIER := {&"k7": 1.0, &"d3": 0.85, &"v9": 0.8, &"b12": 0.72, &"r8": 0.75, &"p1": 0.35}
## How many of each consumable a bot wants to carry.
const WANT := {&"bandage": 10, &"first_aid": 3, &"medkit": 1, &"energy_drink": 3, &"painkiller": 2,
	&"grenade_frag": 2, &"grenade_smoke": 2}


static func value(c: GameCharacter, p: LootManager.Pickup) -> float:
	var id := p.id
	var inv := c.inventory
	match ItemDB.kind_of(id):
		ItemDB.Kind.WEAPON:
			return _weapon_value(c, WeaponDB.get_weapon(id), p.scope != &"")
		ItemDB.Kind.AMMO:
			var used := false
			for w in c.slots:
				if w != null and w.data.ammo_type == id:
					used = true
			if not used:
				return 0.0
			var have := inv.get_count(id)
			var want := 150 if id != &"ammo_sniper" else 45
			if id == &"ammo_shotgun":
				want = 40
			return clampf(0.75 * (1.0 - float(have) / want), 0.0, 0.75)
		ItemDB.Kind.HELMET:
			return _armor_value(ItemDB.level_of(id), ItemDB.level_of(inv.helmet), inv.armor_ratio(false))
		ItemDB.Kind.VEST:
			return _armor_value(ItemDB.level_of(id), ItemDB.level_of(inv.vest), inv.armor_ratio(true))
		ItemDB.Kind.BACKPACK:
			return 0.45 if ItemDB.level_of(id) > ItemDB.level_of(inv.backpack) else 0.0
		ItemDB.Kind.SCOPE:
			for w in c.slots:
				if w != null and w.scope == &"" and w.can_mount(id):
					return 0.3
			return 0.0
		_:
			var n := inv.get_count(id)
			var want: int = WANT.get(id, 0)
			if n >= want:
				return 0.0
			var base := 0.35 if ItemDB.kind_of(id) == ItemDB.Kind.HEAL else 0.25
			if id == &"medkit" or id == &"first_aid":
				base = 0.45
			return base * (1.0 - float(n) / want)


static func _armor_value(new_level: int, cur_level: int, cur_ratio: float) -> float:
	if new_level > cur_level:
		return 0.55 + 0.15 * (new_level - cur_level)
	if new_level == cur_level and cur_ratio < 0.4:
		return 0.3
	return 0.0


static func _weapon_value(c: GameCharacter, data: WeaponData, scoped: bool) -> float:
	if data == null:
		return 0.0
	var tier: float = WEAPON_TIER.get(data.id, 0.5) + (0.08 if scoped else 0.0)
	# No gun at all: anything is great.
	if not c.has_any_gun():
		return 1.2 + tier * 0.3
	if data.is_pistol():
		return 0.25 if c.slots[GameCharacter.SLOT_PISTOL] == null and c.slots[GameCharacter.SLOT_PRIMARY_1] == null else 0.0
	# Already carrying this model: not needed.
	var worst := INF
	var free := false
	for k in [GameCharacter.SLOT_PRIMARY_1, GameCharacter.SLOT_PRIMARY_2]:
		var w := c.slots[k]
		if w == null:
			free = true
			continue
		if w.data.id == data.id:
			return 0.0
		worst = minf(worst, float(WEAPON_TIER.get(w.data.id, 0.5)))
	if free:
		return 0.7 + tier * 0.3
	return maxf((tier - worst) * 1.5, 0.0)


## Best pickup around the bot: value weighted by distance. Returns null if
## nothing is worth the walk.
static func best_pickup(c: GameCharacter, radius: float, ignore: Dictionary) -> LootManager.Pickup:
	if Game.loot == null:
		return null
	var best: LootManager.Pickup = null
	var best_score := 0.12
	var pos := c.global_position
	for p in Game.loot.find_near(pos, radius, 4.0):
		if ignore.has(p.get_instance_id()):
			continue
		var v := value(c, p)
		if v <= 0.0:
			continue
		var score := v / (1.0 + pos.distance_to(p.pos) / 12.0)
		if score > best_score:
			best_score = score
			best = p
	return best
