class_name ProjectileSystem
extends Node3D
## Simulates every bullet in the match as plain data (no nodes per bullet).
##
## Each physics tick a bullet moves along its ballistic arc (velocity + gravity)
## and the traveled segment is tested against:
##   1. the world (terrain, buildings, trees, rocks) with one physics ray,
##   2. the water surface,
##   3. character hitboxes (capsules computed from the procedural skeleton, see
##      CharacterHitboxes) - cheap math, no physics bodies per body part.
## Tracers of all live bullets are drawn with a single MultiMesh.

const MAX_TRACERS := 256
const MAX_LIFETIME := 3.0
const WHIZ_RADIUS := 2.5

class Bullet:
	var pos: Vector3
	var vel: Vector3
	var shooter: GameCharacter
	var weapon: WeaponData
	var traveled := 0.0
	var age := 0.0
	var whizzed := false

var _bullets: Array[Bullet] = []
var _tracer_mm: MultiMesh
var _query := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	_query.collide_with_areas = false
	_query.collide_with_bodies = true
	_query.hit_back_faces = false

	var box := BoxMesh.new()
	box.size = Vector3(0.035, 0.035, 1.0)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/tracer.gdshader")
	box.material = mat
	_tracer_mm = MultiMesh.new()
	_tracer_mm.transform_format = MultiMesh.TRANSFORM_3D
	_tracer_mm.use_colors = true
	_tracer_mm.mesh = box
	_tracer_mm.instance_count = MAX_TRACERS
	_tracer_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Tracers"
	mmi.multimesh = _tracer_mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The tracers move every frame: a huge custom AABB avoids per-frame AABB updates.
	mmi.custom_aabb = AABB(Vector3(-3000, -500, -3000), Vector3(6000, 2000, 6000))
	add_child(mmi)


func clear() -> void:
	_bullets.clear()
	_tracer_mm.visible_instance_count = 0


func get_bullet_count() -> int:
	return _bullets.size()


## Spawns a bullet. `dir` must be normalized.
func fire(shooter: GameCharacter, origin: Vector3, dir: Vector3, weapon: WeaponData) -> void:
	var b := Bullet.new()
	b.pos = origin
	b.vel = dir * weapon.muzzle_velocity
	b.shooter = shooter
	b.weapon = weapon
	_bullets.append(b)


func _physics_process(delta: float) -> void:
	if _bullets.is_empty():
		return
	var space := get_world_3d().direct_space_state
	var i := 0
	while i < _bullets.size():
		if _step(_bullets[i], delta, space):
			# Swap-remove (order does not matter).
			_bullets[i] = _bullets[_bullets.size() - 1]
			_bullets.pop_back()
		else:
			i += 1


## Moves one bullet; returns true when it must be removed.
func _step(b: Bullet, delta: float, space: PhysicsDirectSpaceState3D) -> bool:
	b.age += delta
	var g := b.weapon.bullet_gravity
	var next := b.pos + b.vel * delta + Vector3(0.0, -0.5 * g * delta * delta, 0.0)
	b.vel.y -= g * delta
	var seg := next - b.pos
	var seg_len := seg.length()
	if seg_len < 0.0001:
		return true
	var dir := seg / seg_len

	# 1) World geometry.
	_query.from = b.pos
	_query.to = next
	_query.collision_mask = Layers.BULLET_BLOCKERS
	_query.exclude = []
	var hit := space.intersect_ray(_query)
	var best_dist := seg_len
	var hit_kind := 0   # 0 none, 1 world, 2 water, 3 character
	if not hit.is_empty():
		best_dist = b.pos.distance_to(hit.position)
		hit_kind = 1

	# 2) Water surface.
	var wl := HeightMap.WATER_LEVEL
	if b.pos.y > wl and next.y <= wl:
		var t := (b.pos.y - wl) / (b.pos.y - next.y)
		var d_water := seg_len * t
		if d_water < best_dist and Game.world != null:
			var p := b.pos + seg * t
			if Game.world.get_height(p.x, p.z) < wl:
				best_dist = d_water
				hit_kind = 2

	# 3) Characters.
	var victim: GameCharacter = null
	var part := DamageInfo.Part.TORSO
	if Game.match_manager != null:
		for c in Game.match_manager.alive:
			if c == b.shooter or c.is_dead:
				continue
			var center := c.get_hitbox_center()
			var q := Geometry3D.get_closest_point_to_segment(center, b.pos, next)
			if q.distance_squared_to(center) > CharacterHitboxes.BROADPHASE_RADIUS_SQ:
				continue
			var r := c.hitboxes.intersect_ray(b.pos, dir, best_dist)
			if not r.is_empty():
				best_dist = r.t
				part = r.part
				victim = c
				hit_kind = 3

	# Near miss "whiz" for the local player.
	if not b.whizzed and Game.player != null and b.shooter != Game.player and not Game.player.is_dead and victim != Game.player:
		var head := Game.player.get_eye_position()
		var end := b.pos + dir * best_dist
		var cq := Geometry3D.get_closest_point_to_segment(head, b.pos, end)
		if cq.distance_squared_to(head) < WHIZ_RADIUS * WHIZ_RADIUS:
			b.whizzed = true
			Sfx.play_3d(&"whiz", cq, -2.0, 0.1)

	var hit_pos := b.pos + dir * best_dist
	match hit_kind:
		1:
			var surface := "ground"
			var collider: Object = hit.get("collider")
			if collider != null and collider.has_meta("surface"):
				surface = String(collider.get_meta("surface"))
			if Game.fx != null:
				Game.fx.spawn_impact(hit_pos, hit.normal, surface)
			return true
		2:
			if Game.fx != null:
				Game.fx.spawn_impact(hit_pos, Vector3.UP, "water")
			return true
		3:
			var info := DamageInfo.new()
			var dist := b.traveled + best_dist
			info.part = part
			info.amount = b.weapon.damage * b.weapon.get_part_multiplier(part) * b.weapon.get_falloff(dist)
			info.attacker = b.shooter
			info.weapon_name = b.weapon.display_name
			info.hit_position = hit_pos
			info.direction = dir
			info.distance = dist
			victim.apply_damage(info)
			if Game.fx != null:
				Game.fx.spawn_impact(hit_pos, -dir, "blood")
			return true

	b.pos = next
	b.traveled += seg_len
	return b.age > MAX_LIFETIME or b.traveled > b.weapon.max_range or b.pos.y < -60.0


## General purpose ray against the world AND character hitboxes.
## Used by the player's crosshair and by bots' line-of-sight checks.
## Returns {} or { position, normal, distance, character (or null), part }.
func raycast(from: Vector3, to: Vector3, exclude: GameCharacter = null, include_characters := true) -> Dictionary:
	var space := get_world_3d().direct_space_state
	_query.from = from
	_query.to = to
	_query.collision_mask = Layers.BULLET_BLOCKERS
	_query.exclude = []
	var hit := space.intersect_ray(_query)
	var length := from.distance_to(to)
	if length < 0.0001:
		return {}
	var dir := (to - from) / length
	var best := length
	var result := {}
	if not hit.is_empty():
		best = from.distance_to(hit.position)
		result = {"position": hit.position, "normal": hit.normal, "distance": best, "character": null, "part": -1}
	if include_characters and Game.match_manager != null:
		for c in Game.match_manager.alive:
			if c == exclude or c.is_dead:
				continue
			var center := c.get_hitbox_center()
			var q := Geometry3D.get_closest_point_to_segment(center, from, from + dir * best)
			if q.distance_squared_to(center) > CharacterHitboxes.BROADPHASE_RADIUS_SQ:
				continue
			var r := c.hitboxes.intersect_ray(from, dir, best)
			if not r.is_empty():
				best = r.t
				result = {"position": from + dir * best, "normal": -dir, "distance": best, "character": c, "part": r.part}
	return result


## True if nothing in the world blocks the segment (characters are ignored).
func has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	_query.from = from
	_query.to = to
	_query.collision_mask = Layers.BULLET_BLOCKERS
	_query.exclude = []
	return space.intersect_ray(_query).is_empty()


func _process(_delta: float) -> void:
	# Tracers: interpolate between physics ticks for smooth motion.
	var n := mini(_bullets.size(), MAX_TRACERS)
	var frac := Engine.get_physics_interpolation_fraction() / float(Engine.physics_ticks_per_second)
	for k in n:
		var b := _bullets[k]
		var speed := b.vel.length()
		var dir := b.vel / maxf(speed, 0.001)
		var head := b.pos + b.vel * frac
		var length := minf(b.traveled + speed * frac, 6.0)
		var basis := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
		# Stretch the unit box along its own Z axis (local scale).
		basis = Basis(basis.x, basis.y, basis.z * maxf(length, 0.05))
		_tracer_mm.set_instance_transform(k, Transform3D(basis, head - dir * length * 0.5))
		var col := b.weapon.tracer_color
		col.a = 0.9
		_tracer_mm.set_instance_color(k, col)
	_tracer_mm.visible_instance_count = n
