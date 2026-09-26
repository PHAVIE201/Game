class_name ThrowableSystem
extends Node3D
## Thrown grenades (frag / smoke): ballistic flight with bounces, fuses,
## explosions and smoke clouds. Smoke clouds block line of sight for bots
## (smoke_blocks). The local player's throw arc is previewed with a 3D line.

const GRAVITY := 9.8
const THROW_SPEED := 19.0
## Frag: the fuse starts when the pin is pulled (hold G, release to throw).
const FRAG_FUSE := 4.5
const FRAG_RADIUS := 8.0
const FRAG_DAMAGE := 115.0
## Smoke pops a moment after landing / after the throw.
const SMOKE_FUSE := 2.2
const SMOKE_RADIUS := 7.0
const SMOKE_TIME := 32.0
const SMOKE_PUFFS := 11

class Grenade:
	extends RefCounted
	var id: StringName
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var fuse := 0.0
	var thrower: GameCharacter
	var node: MeshInstance3D
	var resting := false

class Smoke:
	extends RefCounted
	var pos := Vector3.ZERO
	var age := 0.0
	var radius := 0.0
	var node: Node3D
	var material: StandardMaterial3D

var _grenades: Array[Grenade] = []
var _smokes: Array[Smoke] = []
var _ray := PhysicsRayQueryParameters3D.new()
var _puff_mesh: SphereMesh
var _arc: MeshInstance3D
var _arc_mesh: ImmediateMesh
var _flash: OmniLight3D
var _flash_time := 0.0


func _ready() -> void:
	_ray.collision_mask = Layers.BULLET_BLOCKERS
	_puff_mesh = SphereMesh.new()
	_puff_mesh.radius = 1.0
	_puff_mesh.height = 2.0
	_puff_mesh.radial_segments = 10
	_puff_mesh.rings = 6
	_arc_mesh = ImmediateMesh.new()
	_arc = MeshInstance3D.new()
	_arc.mesh = _arc_mesh
	_arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var arc_mat := StandardMaterial3D.new()
	arc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arc_mat.albedo_color = Color(1.0, 0.95, 0.6)
	arc_mat.no_depth_test = true
	arc_mat.vertex_color_use_as_albedo = true
	_arc.material_override = arc_mat
	add_child(_arc)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.7, 0.35)
	_flash.omni_range = 18.0
	_flash.light_energy = 0.0
	add_child(_flash)


func clear() -> void:
	for g in _grenades:
		g.node.queue_free()
	_grenades.clear()
	for s in _smokes:
		s.node.queue_free()
	_smokes.clear()
	_arc_mesh.clear_surfaces()


## Mesh of a grenade (in the hand and in flight).
func get_mesh(id: StringName) -> ArrayMesh:
	return ItemModels.get_mesh(id)


## Initial velocity of a throw along `dir` (slightly lofted).
static func throw_velocity(dir: Vector3, carrier_velocity: Vector3) -> Vector3:
	return (dir + Vector3(0, 0.12, 0)).normalized() * THROW_SPEED + carrier_velocity * 0.5


## Launches a grenade. `fuse_left` < 0 = default fuse for the type.
func throw_item(thrower: GameCharacter, id: StringName, from: Vector3, vel: Vector3, fuse_left := -1.0) -> void:
	var g := Grenade.new()
	g.id = id
	g.pos = from
	g.vel = vel
	g.thrower = thrower
	g.fuse = fuse_left if fuse_left >= 0.0 else (FRAG_FUSE if id == &"grenade_frag" else SMOKE_FUSE)
	if id == &"grenade_smoke":
		g.fuse = SMOKE_FUSE
	g.node = MeshInstance3D.new()
	g.node.mesh = get_mesh(id)
	add_child(g.node)
	g.node.global_position = from
	_grenades.append(g)
	Sfx.play_3d(&"throw", from, -6.0, 0.1, 60.0)


## The fuse ran out while still holding the grenade.
func explode_in_hand(thrower: GameCharacter, id: StringName, at: Vector3) -> void:
	if id == &"grenade_frag":
		_explode(at, thrower)
	else:
		_start_smoke(at)


func _physics_process(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var i := 0
	while i < _grenades.size():
		var g := _grenades[i]
		if not g.resting:
			_move(g, delta, space)
		g.fuse -= delta
		if g.fuse <= 0.0:
			if g.id == &"grenade_frag":
				_explode(g.pos, g.thrower)
			else:
				_start_smoke(g.pos)
			g.node.queue_free()
			_grenades[i] = _grenades[_grenades.size() - 1]
			_grenades.pop_back()
		else:
			i += 1
	_update_smokes(delta)
	if _flash_time > 0.0:
		_flash_time -= delta
		_flash.light_energy = maxf(_flash_time / 0.25, 0.0) * 8.0


func _move(g: Grenade, delta: float, space: PhysicsDirectSpaceState3D) -> void:
	var next := g.pos + g.vel * delta + Vector3(0, -0.5 * GRAVITY * delta * delta, 0)
	g.vel.y -= GRAVITY * delta
	_ray.from = g.pos
	_ray.to = next
	var hit := space.intersect_ray(_ray)
	if not hit.is_empty():
		var n: Vector3 = hit.normal
		var vn := n * g.vel.dot(n)
		var vt := g.vel - vn
		g.vel = vt * 0.7 - vn * 0.35
		next = (hit.position as Vector3) + n * 0.05
		if g.vel.length() > 2.0:
			Sfx.play_3d(&"clink", next, -12.0, 0.2, 40.0)
		if g.vel.length() < 1.0 and n.y > 0.6:
			g.vel = Vector3.ZERO
			g.resting = true
	elif next.y < HeightMap.WATER_LEVEL - 0.25 and Game.world != null and Game.world.get_height(next.x, next.z) < HeightMap.WATER_LEVEL:
		# Sinks into water and stays there.
		next.y = HeightMap.WATER_LEVEL - 0.25
		g.vel = Vector3.ZERO
		g.resting = true
	g.pos = next
	g.node.global_position = next
	if not g.resting:
		g.node.rotate_x(delta * 9.0)


## Where a throw would go (up to `seconds`), for the aiming arc.
func predict(from: Vector3, vel: Vector3, seconds := 3.0) -> PackedVector3Array:
	var pts := PackedVector3Array([from])
	var space := get_world_3d().direct_space_state
	var pos := from
	var v := vel
	var dt := 1.0 / 30.0
	var t := 0.0
	var bounces := 0
	while t < seconds and bounces < 2:
		var next := pos + v * dt + Vector3(0, -0.5 * GRAVITY * dt * dt, 0)
		v.y -= GRAVITY * dt
		_ray.from = pos
		_ray.to = next
		var hit := space.intersect_ray(_ray)
		if not hit.is_empty():
			var n: Vector3 = hit.normal
			next = (hit.position as Vector3) + n * 0.05
			var vn := n * v.dot(n)
			v = (v - vn) * 0.7 - vn * 0.35
			bounces += 1
		pos = next
		pts.append(pos)
		t += dt
	return pts


## Draws (or hides with an empty array) the local player's throw arc.
func show_arc(points: PackedVector3Array) -> void:
	_arc_mesh.clear_surfaces()
	if points.size() < 2:
		return
	_arc_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for k in points.size():
		var a := 1.0 - float(k) / points.size() * 0.6
		_arc_mesh.surface_set_color(Color(1.0, 0.95, 0.6, a))
		_arc_mesh.surface_add_vertex(points[k])
	_arc_mesh.surface_end()


# --------------------------------------------------------------------------
# Frag
# --------------------------------------------------------------------------

func _explode(pos: Vector3, thrower: GameCharacter) -> void:
	_flash.global_position = pos + Vector3(0, 0.6, 0)
	_flash_time = 0.25
	_flash.light_energy = 8.0
	if Game.fx != null:
		Game.fx.spawn_explosion(pos)
	Sfx.play_3d(&"explosion", pos, 6.0, 0.08, 1200.0)
	Events.shot_fired.emit(thrower, pos, 450.0)
	Events.explosion.emit(pos, FRAG_RADIUS)
	if Game.match_manager == null:
		return
	var space := get_world_3d().direct_space_state
	var origin := pos + Vector3(0, 0.3, 0)
	for c: GameCharacter in Game.match_manager.alive.duplicate():
		if not c.is_targetable():
			continue
		var center := c.get_hitbox_center()
		var d := origin.distance_to(center)
		if d > FRAG_RADIUS:
			continue
		# Walls and terrain shield from the blast.
		_ray.from = origin
		_ray.to = center
		if not space.intersect_ray(_ray).is_empty():
			_ray.to = c.get_head_position()
			if not space.intersect_ray(_ray).is_empty():
				continue
		var k := clampf(1.0 - (d - 1.0) / (FRAG_RADIUS - 1.0), 0.0, 1.0)
		var info := DamageInfo.new()
		info.amount = FRAG_DAMAGE * pow(k, 1.4)
		info.part = DamageInfo.Part.OTHER
		info.attacker = thrower
		info.weapon_name = "Lựu đạn"
		info.hit_position = center
		info.direction = (center - pos).normalized()
		info.distance = d
		if info.amount > 0.5:
			c.apply_damage(info)


# --------------------------------------------------------------------------
# Smoke
# --------------------------------------------------------------------------

func _start_smoke(pos: Vector3) -> void:
	var s := Smoke.new()
	s.pos = pos + Vector3(0, 0.5, 0)
	s.node = Node3D.new()
	add_child(s.node)
	s.node.global_position = s.pos
	s.material = StandardMaterial3D.new()
	s.material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	s.material.albedo_color = Color(0.86, 0.88, 0.9, 0.0)
	s.material.roughness = 1.0
	s.material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(pos)
	for k in SMOKE_PUFFS:
		var puff := MeshInstance3D.new()
		puff.mesh = _puff_mesh
		puff.material_override = s.material
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 0.9), rng.randf_range(-1, 1)).normalized()
		puff.set_meta("offset", dir * rng.randf_range(0.2, 0.75))
		puff.set_meta("size", rng.randf_range(0.45, 0.7))
		s.node.add_child(puff)
	_smokes.append(s)
	Sfx.play_3d(&"smoke_hiss", pos, -4.0, 0.1, 80.0)


func _update_smokes(delta: float) -> void:
	var i := 0
	while i < _smokes.size():
		var s := _smokes[i]
		s.age += delta
		s.radius = SMOKE_RADIUS * smoothstep(0.0, 2.5, s.age)
		var alpha := 0.92 * minf(s.age / 0.8, 1.0) * clampf((SMOKE_TIME - s.age) / 5.0, 0.0, 1.0)
		s.material.albedo_color.a = alpha
		for puff: MeshInstance3D in s.node.get_children():
			var off: Vector3 = puff.get_meta("offset")
			var sz: float = puff.get_meta("size")
			puff.position = off * s.radius + Vector3(0, s.age * 0.05, 0)
			puff.scale = Vector3.ONE * maxf(s.radius * sz, 0.1)
		if s.age >= SMOKE_TIME:
			s.node.queue_free()
			_smokes[i] = _smokes[_smokes.size() - 1]
			_smokes.pop_back()
		else:
			i += 1


## True when a smoke cloud hides `to` from `from` (line of sight for bots).
func smoke_blocks(from: Vector3, to: Vector3) -> bool:
	for s in _smokes:
		if s.age < 1.0 or s.age > SMOKE_TIME - 3.0:
			continue
		var r := s.radius * 0.85
		var q := Geometry3D.get_closest_point_to_segment(s.pos, from, to)
		if q.distance_squared_to(s.pos) < r * r:
			return true
	return false


func get_smoke_count() -> int:
	return _smokes.size()
