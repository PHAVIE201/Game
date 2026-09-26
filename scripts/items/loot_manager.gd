class_name LootManager
extends Node3D
## Items lying on the ground: spawning in buildings, pickup queries, the loot
## rules (what happens when a character takes / drops something) and the
## death drop. Characters never manipulate pickups directly, so the player and
## the bots always follow the same rules.
##
## Pickups are plain data (Pickup) + one MeshInstance3D each with a short
## visibility range. A spatial hash answers "what is near me" cheaply.

signal pickups_changed

## Horizontal reach for picking something up (m).
const REACH := 2.3
## Items listed as "ground" in the inventory screen.
const GROUND_RADIUS := 3.2
const GRID_CELL := 8.0
const VIEW_RANGE := 85.0
## Share of building loot points that get items.
const SPOT_CHANCE := 0.82

## Relative weights of what a loot spot contains.
const SPOT_TABLE := {"weapon": 25.0, "ammo": 24.0, "backpack": 6.0, "helmet": 7.0, "vest": 7.0, "heal": 16.0, "boost": 7.0, "scope": 8.0}
const WEAPON_WEIGHTS := {&"k7": 22.0, &"v9": 22.0, &"b12": 18.0, &"d3": 9.0, &"r8": 6.0, &"p1": 23.0}
const AMMO_WEIGHTS := {&"ammo_rifle": 35.0, &"ammo_smg": 30.0, &"ammo_shotgun": 15.0, &"ammo_sniper": 20.0}
const BACKPACK_WEIGHTS := {&"backpack_1": 60.0, &"backpack_2": 30.0, &"backpack_3": 10.0}
const HELMET_WEIGHTS := {&"helmet_1": 55.0, &"helmet_2": 33.0, &"helmet_3": 12.0}
const VEST_WEIGHTS := {&"vest_1": 55.0, &"vest_2": 33.0, &"vest_3": 12.0}
const HEAL_WEIGHTS := {&"bandage": 55.0, &"first_aid": 32.0, &"medkit": 13.0}
const BOOST_WEIGHTS := {&"energy_drink": 65.0, &"painkiller": 35.0}
const SCOPE_WEIGHTS := {&"scope_reddot": 40.0, &"scope_2x": 30.0, &"scope_4x": 20.0, &"scope_8x": 10.0}


class Pickup:
	extends RefCounted
	var id: StringName
	var count := 1
	## Weapons: rounds left in the magazine.
	var mag_ammo := 0
	## Helmet / vest: remaining durability (< 0 = new).
	var durability := -1.0
	## Weapons: mounted scope.
	var scope := &""
	var pos := Vector3.ZERO
	var yaw := 0.0
	var node: MeshInstance3D
	var cell := Vector2i.ZERO
	var alive := true

	func label() -> String:
		var text := ItemDB.display_name(id)
		if count > 1:
			text += " ×%d" % count
		if durability >= 0.0:
			var full := float(ItemDB.get_info(id).get("durability", 100.0))
			text += " (%d%%)" % roundi(100.0 * durability / full)
		if scope != &"":
			text += " + " + ItemDB.scope_tag(scope)
		return text


var pickups: Array[Pickup] = []
## The pickup the local player would take with the interact key (or null).
var player_target: Pickup = null

var _grid: Dictionary = {}   # Vector2i -> Array[Pickup]
var _ray := PhysicsRayQueryParameters3D.new()
var _target_timer := 0.0


func _ready() -> void:
	_ray.collision_mask = Layers.WORLD


func clear() -> void:
	for p in pickups:
		if p.node != null:
			p.node.queue_free()
		p.alive = false
	pickups.clear()
	_grid.clear()
	player_target = null
	pickups_changed.emit()


# --------------------------------------------------------------------------
# Spawning
# --------------------------------------------------------------------------

## Fills the buildings with loot (called at every match start).
func spawn_world_loot(world: GameWorld, rng: RandomNumberGenerator) -> void:
	var t0 := Time.get_ticks_msec()
	for lp in world.get_loot_points():
		if rng.randf() > SPOT_CHANCE:
			continue
		_spawn_spot(lp, rng)
	print("[Loot] %d pickups at %d spots in %d ms" % [pickups.size(), world.get_loot_points().size(), Time.get_ticks_msec() - t0])


func _spawn_spot(at: Vector3, rng: RandomNumberGenerator) -> void:
	var what: String = _pick(SPOT_TABLE, rng)
	var yaw := rng.randf() * TAU
	match what:
		"weapon":
			var id: StringName = _pick(WEAPON_WEIGHTS, rng)
			spawn(id, 1, at, yaw, 0)
			# Ammo for it next to the gun.
			var ammo := WeaponDB.get_weapon(id).ammo_type
			for k in rng.randi_range(1, 2):
				spawn(ammo, ItemDB.stack_of(ammo), at + _ring(rng, 0.35), rng.randf() * TAU)
		"ammo":
			var id: StringName = _pick(AMMO_WEIGHTS, rng)
			spawn(id, ItemDB.stack_of(id) * rng.randi_range(1, 2), at, yaw)
		"backpack":
			spawn(_pick(BACKPACK_WEIGHTS, rng), 1, at, yaw)
		"helmet":
			spawn(_pick(HELMET_WEIGHTS, rng), 1, at, yaw)
		"vest":
			spawn(_pick(VEST_WEIGHTS, rng), 1, at, yaw)
		"heal":
			var id: StringName = _pick(HEAL_WEIGHTS, rng)
			spawn(id, ItemDB.stack_of(id), at, yaw)
		"boost":
			spawn(_pick(BOOST_WEIGHTS, rng), 1, at, yaw)
		"scope":
			spawn(_pick(SCOPE_WEIGHTS, rng), 1, at, yaw)


static func _pick(table: Dictionary, rng: RandomNumberGenerator) -> Variant:
	var total := 0.0
	for k in table:
		total += float(table[k])
	var r := rng.randf() * total
	for k in table:
		r -= float(table[k])
		if r <= 0.0:
			return k
	return table.keys()[0]


static func _ring(rng: RandomNumberGenerator, radius: float) -> Vector3:
	var a := rng.randf() * TAU
	return Vector3(cos(a), 0.0, sin(a)) * radius


## Creates a pickup at a floor position.
func spawn(id: StringName, count: int, pos: Vector3, yaw := 0.0, mag_ammo := 0) -> Pickup:
	var p := Pickup.new()
	p.id = id
	p.count = maxi(count, 1)
	p.mag_ammo = mag_ammo
	p.pos = pos
	p.yaw = yaw
	var mi := MeshInstance3D.new()
	mi.mesh = ItemModels.get_mesh(id)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = VIEW_RANGE
	mi.visibility_range_end_margin = 8.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mi)
	mi.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos) * ItemModels.get_ground_transform(id)
	p.node = mi
	p.cell = _cell_of(pos)
	var list: Array = _grid.get(p.cell, [])
	if list.is_empty():
		_grid[p.cell] = list
	list.append(p)
	pickups.append(p)
	pickups_changed.emit()
	return p


func remove(p: Pickup) -> void:
	if not p.alive:
		return
	p.alive = false
	if p.node != null:
		p.node.queue_free()
		p.node = null
	var list: Array = _grid.get(p.cell, [])
	list.erase(p)
	pickups.erase(p)
	if player_target == p:
		player_target = null
	pickups_changed.emit()


func _cell_of(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / GRID_CELL), floori(pos.z / GRID_CELL))


# --------------------------------------------------------------------------
# Queries
# --------------------------------------------------------------------------

## Pickups within `radius` (horizontal) and a floor's height of `pos`.
func find_near(pos: Vector3, radius: float, max_dy := 1.7) -> Array[Pickup]:
	var out: Array[Pickup] = []
	var r2 := radius * radius
	for gx in range(floori((pos.x - radius) / GRID_CELL), floori((pos.x + radius) / GRID_CELL) + 1):
		for gz in range(floori((pos.z - radius) / GRID_CELL), floori((pos.z + radius) / GRID_CELL) + 1):
			for p: Pickup in _grid.get(Vector2i(gx, gz), []):
				var d := p.pos - pos
				if d.x * d.x + d.z * d.z <= r2 and d.y > -max_dy and d.y < max_dy:
					out.append(p)
	return out


## Nearby pickups the character can actually reach (no wall in between),
## sorted by distance.
func reachable(c: GameCharacter, radius := GROUND_RADIUS) -> Array[Pickup]:
	var out: Array[Pickup] = []
	var eye := c.get_eye_position()
	var space := get_world_3d().direct_space_state
	for p in find_near(c.global_position, radius):
		_ray.from = eye
		_ray.to = p.pos + Vector3(0, 0.12, 0)
		if space.intersect_ray(_ray).is_empty():
			out.append(p)
	var here := c.global_position
	out.sort_custom(func(a: Pickup, b: Pickup): return a.pos.distance_squared_to(here) < b.pos.distance_squared_to(here))
	return out


## The item the character looks at (or the closest one) within reach.
func best_target(c: GameCharacter, look_dir: Vector3) -> Pickup:
	var best: Pickup = null
	var best_score := INF
	var eye := c.get_eye_position()
	for p in reachable(c, REACH):
		var to := p.pos - eye
		var dist := to.length()
		var angle := look_dir.angle_to(to / maxf(dist, 0.001))
		var score := angle * 2.0 + dist * 0.4
		if score < best_score:
			best_score = score
			best = p
	return best


func _process(delta: float) -> void:
	_target_timer -= delta
	if _target_timer > 0.0:
		return
	_target_timer = 0.1
	var pl := Game.player
	if pl == null or not is_instance_valid(pl) or pl.is_dead or Game.camera == null or not pl.can_interact():
		player_target = null
		return
	player_target = best_target(pl, -Game.camera.global_transform.basis.z)


# --------------------------------------------------------------------------
# Loot rules
# --------------------------------------------------------------------------

## Result codes of take().
enum Take { OK, PARTIAL, FULL, INVALID }

## `c` takes (up to `amount` of) a pickup. Returns a Take code.
func take(c: GameCharacter, p: Pickup, amount := -1) -> int:
	if p == null or not p.alive or c.is_dead:
		return Take.INVALID
	var id := p.id
	match ItemDB.kind_of(id):
		ItemDB.Kind.WEAPON:
			var data := WeaponDB.get_weapon(id)
			var mag := p.mag_ammo
			var scope := p.scope
			remove(p)
			var old := c.give_weapon(data, mag, not c.is_armed(), scope)
			if old != null:
				_spawn_weapon(old, drop_position(c, 0), c.aim_yaw + PI * 0.5)
			_emit_loot(c, "Đã nhặt " + data.display_name)
			return Take.OK
		ItemDB.Kind.SCOPE:
			# Mount it right away on a gun without a scope (the one in the hands first).
			var order: Array[int] = []
			if c.active_slot >= 0:
				order.append(c.active_slot)
			for k in GameCharacter.SLOT_COUNT:
				if k != c.active_slot:
					order.append(k)
			for k in order:
				var w := c.slots[k]
				if w != null and w.scope == &"" and w.can_mount(id):
					remove(p)
					c.mount_scope(k, id)
					_emit_loot(c, "Đã gắn %s lên %s" % [ItemDB.display_name(id), w.data.display_name])
					return Take.OK
			if c.inventory.add(id, 1) <= 0:
				_emit_loot(c, "Túi đồ đã đầy")
				return Take.FULL
			remove(p)
			_emit_loot(c, "Đã nhặt " + ItemDB.display_name(id))
			return Take.OK
		ItemDB.Kind.HELMET, ItemDB.Kind.VEST:
			var dur := p.durability
			remove(p)
			var old: Array = c.inventory.wear(id, dur)
			if old[0] != &"":
				var dropped := spawn(old[0], 1, drop_position(c, 0), c.aim_yaw)
				dropped.durability = old[1]
			_emit_loot(c, "Đã mặc " + ItemDB.display_name(id))
			return Take.OK
		ItemDB.Kind.BACKPACK:
			var cap_new := ItemDB.BASE_CAPACITY + float(ItemDB.get_info(id).get("capacity", 0.0))
			if not c.inventory.unlimited and c.inventory.used_weight() > cap_new + 0.01:
				_emit_loot(c, "Balo này quá nhỏ cho số đồ đang mang")
				return Take.FULL
			remove(p)
			var old_bp := c.inventory.set_backpack(id)
			if old_bp != &"":
				spawn(old_bp, 1, drop_position(c, 0), c.aim_yaw)
			_emit_loot(c, "Đã đeo " + ItemDB.display_name(id))
			return Take.OK
		_:
			var want := p.count if amount < 0 else mini(amount, p.count)
			var added := c.inventory.add(id, want)
			if added <= 0:
				_emit_loot(c, "Túi đồ đã đầy")
				return Take.FULL
			p.count -= added
			if p.count <= 0:
				remove(p)
			else:
				pickups_changed.emit()
			_emit_loot(c, "Đã nhặt %s ×%d" % [ItemDB.display_name(id), added])
			return Take.OK if added >= want else Take.PARTIAL


## Drops `amount` of a stackable item from the inventory.
func drop_item(c: GameCharacter, id: StringName, amount: int) -> void:
	var n := c.inventory.remove(id, amount)
	if n > 0:
		spawn(id, n, drop_position(c, pickups.size()), c.aim_yaw)


## Drops the weapon of a slot.
func drop_weapon(c: GameCharacter, slot: int) -> void:
	var w := c.take_weapon(slot)
	if w != null:
		_spawn_weapon(w, drop_position(c, slot), c.aim_yaw + PI * 0.5)


## A weapon on the ground keeps its magazine and scope.
func _spawn_weapon(w: Weapon, pos: Vector3, yaw: float) -> Pickup:
	var p := spawn(w.data.id, 1, pos, yaw, w.ammo)
	p.scope = w.scope
	return p


## Mounts a scope from the backpack on a slot's weapon (inventory screen).
func mount_from_bag(c: GameCharacter, slot: int, scope_id: StringName) -> void:
	var w := c.slots[slot]
	if w == null or not w.can_mount(scope_id) or c.inventory.remove(scope_id, 1) <= 0:
		return
	var old := c.mount_scope(slot, scope_id)
	if old != &"" and c.inventory.add(old, 1) <= 0:
		spawn(old, 1, drop_position(c, 3), c.aim_yaw)


## Takes the scope off a slot's weapon into the backpack (or the ground).
func unmount_to_bag(c: GameCharacter, slot: int) -> void:
	var old := c.unmount_scope(slot)
	if old != &"" and c.inventory.add(old, 1) <= 0:
		spawn(old, 1, drop_position(c, 3), c.aim_yaw)


func drop_backpack(c: GameCharacter) -> void:
	var bp := c.inventory.backpack
	if bp == &"":
		return
	if not c.inventory.unlimited and c.inventory.used_weight() > ItemDB.BASE_CAPACITY + 0.01:
		_emit_loot(c, "Không thể bỏ balo khi túi còn nhiều đồ")
		return
	c.inventory.set_backpack(&"")
	spawn(bp, 1, drop_position(c, 7), c.aim_yaw)


## Takes off the helmet or the vest and drops it.
func drop_armor(c: GameCharacter, is_vest: bool) -> void:
	var old: Array = c.inventory.take_off(is_vest)
	if old[0] != &"":
		var p := spawn(old[0], 1, drop_position(c, 5), c.aim_yaw)
		p.durability = old[1]


## Everything a dead character carried falls around the body.
func drop_everything(c: GameCharacter) -> void:
	var k := 0
	for slot in GameCharacter.SLOT_COUNT:
		var w := c.slots[slot]
		if w != null:
			_spawn_weapon(w, drop_position(c, k, 0.9), c.aim_yaw + k)
			k += 1
	for id in c.inventory.items.keys():
		var n := c.inventory.get_count(id)
		if c.inventory.unlimited:
			# Bots with endless ammo drop a sensible amount.
			n = mini(n, ItemDB.stack_of(id) * 3)
		if n > 0:
			spawn(id, n, drop_position(c, k, 0.9), k * 1.3)
			k += 1
	if c.inventory.backpack != &"":
		spawn(c.inventory.backpack, 1, drop_position(c, k, 0.9), k * 1.1)
		k += 1
	for armor in [[c.inventory.helmet, c.inventory.helmet_durability], [c.inventory.vest, c.inventory.vest_durability]]:
		if armor[0] != &"":
			var p := spawn(armor[0], 1, drop_position(c, k, 0.9), k * 0.9)
			p.durability = armor[1]
			k += 1
	c.clear_loadout()


## A floor position around the character's feet (k-th of a small spiral).
func drop_position(c: GameCharacter, k: int, radius := 0.55) -> Vector3:
	var ang := c.aim_yaw + k * 2.39996   # golden angle spiral
	var r := radius * (0.6 + 0.4 * sqrt(float(k % 8) / 8.0))
	var p := c.global_position + Vector3(-sin(ang), 0.0, -cos(ang)) * r
	return floor_at(p)


## Floor height under a point (buildings included), via a short ray.
func floor_at(p: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	_ray.from = p + Vector3(0, 1.0, 0)
	_ray.to = p - Vector3(0, 4.0, 0)
	var hit := space.intersect_ray(_ray)
	if not hit.is_empty():
		return hit.position
	if Game.world != null:
		p.y = Game.world.get_height(p.x, p.z)
	return p


func _emit_loot(c: GameCharacter, text: String) -> void:
	if c.is_player:
		Events.loot_message.emit(text)
