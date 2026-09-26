class_name Settlements
extends RefCounted
## Plans towns / farms on the heightmap and builds low-poly enterable houses.
##
## Planning happens BEFORE the terrain mesh is built because building pads
## flatten the heightmap. Every building also registers "loot points" (floor
## positions inside rooms) that the phase-2 loot system will use.

enum BType { COTTAGE, LONGHOUSE, WAREHOUSE, SHED }

const TOWN_NAMES := [
	"Làng Gió", "Bến Sậy", "Xóm Đá", "Trại Thông", "Đồi Cú", "Cảng Muối",
	"Bãi Rơm", "Làng Mây", "Xóm Cối", "Trạm Sương",
]

const WALL_COLORS := [
	Color(0.93, 0.87, 0.74), Color(0.86, 0.72, 0.57), Color(0.7, 0.8, 0.88),
	Color(0.9, 0.73, 0.68), Color(0.76, 0.86, 0.7), Color(0.95, 0.94, 0.9),
]
const ROOF_COLORS := [
	Color(0.74, 0.31, 0.22), Color(0.55, 0.21, 0.2), Color(0.33, 0.4, 0.5),
	Color(0.28, 0.45, 0.34), Color(0.46, 0.32, 0.24),
]
const FOUNDATION_COLOR := Color(0.52, 0.52, 0.53)
const WOOD_COLOR := Color(0.6, 0.43, 0.25)
const TRIM_COLOR := Color(0.97, 0.97, 0.95)

const WALL_T := 0.25
const FLOOR_Y := 0.12

## { name, center: Vector2, radius, height }
var towns: Array[Dictionary] = []
## { type, center: Vector2, angle, size: Vector2, floor_y, wall_color, roof_color, town }
var buildings: Array[Dictionary] = []
## Small cover props (crates / barrels): { pos: Vector3, angle, kind }
var props: Array[Dictionary] = []
## Loot spawn points inside buildings (used from phase 2).
var loot_points := PackedVector3Array()

## Spatial hash: Vector2i cell -> Array of building dicts (fast point queries).
const GRID_CELL := 64.0
var _grid: Dictionary = {}
## Building whose walls are being built (door bookkeeping).
var _door_building: Dictionary = {}


static func footprint(type: int) -> Vector2:
	match type:
		BType.LONGHOUSE:
			return Vector2(13.0, 7.5)
		BType.WAREHOUSE:
			return Vector2(16.0, 12.0)
		BType.SHED:
			return Vector2(5.0, 4.0)
		_:
			return Vector2(8.5, 7.0)


# --------------------------------------------------------------------------
# Planning
# --------------------------------------------------------------------------

func plan(hm: HeightMap, rng: RandomNumberGenerator) -> void:
	towns.clear()
	buildings.clear()
	props.clear()
	loot_points.clear()
	_grid.clear()
	var names := TOWN_NAMES.duplicate()
	# Deterministic shuffle.
	for k in range(names.size() - 1, 0, -1):
		var r := rng.randi_range(0, k)
		var tmp = names[k]
		names[k] = names[r]
		names[r] = tmp

	var wanted_towns := 6
	for attempt in 600:
		if towns.size() >= wanted_towns:
			break
		var c := Vector2(rng.randf_range(-720.0, 720.0), rng.randf_range(-720.0, 720.0))
		if not _town_site_ok(hm, c):
			continue
		var town := {"name": names[towns.size() % names.size()], "center": c, "radius": 70.0, "height": hm.get_height(c.x, c.y)}
		towns.append(town)
		_layout_town(hm, rng, town)

	# Lone farms scattered in the countryside.
	var farms := 0
	for attempt in 400:
		if farms >= 9:
			break
		var p := Vector2(rng.randf_range(-760.0, 760.0), rng.randf_range(-760.0, 760.0))
		var h := hm.get_height(p.x, p.y)
		if h < 2.5 or h > 55.0 or hm.get_shore_distance(p.x, p.y) < 20.0:
			continue
		if _near_town(p, 150.0):
			continue
		var angle := rng.randf_range(0.0, TAU)
		if _try_place(hm, rng, BType.COTTAGE if rng.randf() < 0.7 else BType.LONGHOUSE, p, angle, ""):
			farms += 1
			var shed_pos := p + Vector2(11.0, 0.0).rotated(-angle + (PI if rng.randf() < 0.5 else 0.0))
			_try_place(hm, rng, BType.SHED, shed_pos, angle, "")


func _town_site_ok(hm: HeightMap, c: Vector2) -> bool:
	var h := hm.get_height(c.x, c.y)
	if h < 3.0 or h > 42.0:
		return false
	if hm.get_shore_distance(c.x, c.y) < 45.0:
		return false
	if hm.height_range(c.x, c.y, 45.0) > 11.0:
		return false
	for mt in hm.mountains:
		if c.distance_to(mt.center) < float(mt.radius) * 0.8:
			return false
	return not _near_town(c, 340.0)


func _near_town(p: Vector2, dist: float) -> bool:
	for t in towns:
		if p.distance_to(t.center) < dist:
			return true
	return false


func _layout_town(hm: HeightMap, rng: RandomNumberGenerator, town: Dictionary) -> void:
	var c: Vector2 = town.center
	var angle := rng.randf_range(0.0, TAU)
	var slots: Array[Vector2] = []
	for gx in range(-2, 3):
		for gz in range(-2, 3):
			if gx == 0 and gz == 0:
				continue   # keep the town square open (spawn / fights)
			slots.append(Vector2(gx * 25.0, gz * 23.0))
	# Shuffle slots.
	for k in range(slots.size() - 1, 0, -1):
		var r := rng.randi_range(0, k)
		var tmp := slots[k]
		slots[k] = slots[r]
		slots[r] = tmp
	var count := rng.randi_range(6, 11)
	var placed := 0
	for s in slots:
		if placed >= count:
			break
		var jitter := Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0))
		var p := c + (s + jitter).rotated(angle)
		var roll := rng.randf()
		var type := BType.COTTAGE
		if roll > 0.88:
			type = BType.WAREHOUSE
		elif roll > 0.62:
			type = BType.LONGHOUSE
		elif roll > 0.54:
			type = BType.SHED
		var b_angle := angle + (rng.randi() % 4) * PI * 0.5
		if _try_place(hm, rng, type, p, b_angle, town.name):
			placed += 1


func _try_place(hm: HeightMap, rng: RandomNumberGenerator, type: int, p: Vector2, angle: float, town_name: String) -> bool:
	var size := footprint(type)
	var half := size * 0.5
	var radius := half.length()
	for b in buildings:
		if p.distance_to(b.center) < radius + (b.size as Vector2).length() * 0.5 + 4.0:
			return false
	# Sample corners + center: reject steep or wet spots.
	var lo := 1.0e9
	var hi := -1.0e9
	var sum := 0.0
	var pts: Array[Vector2] = [Vector2.ZERO, Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]
	for off in pts:
		var q := p + off.rotated(-angle)
		var h := hm.get_height(q.x, q.y)
		if h < HeightMap.WATER_LEVEL + 1.5 or hm.get_shore_distance(q.x, q.y) < 10.0:
			return false
		lo = minf(lo, h)
		hi = maxf(hi, h)
		sum += h
	if hi - lo > 5.5:
		return false
	var floor_y := sum / pts.size()
	# Pad extends one terrain cell past the walls so no triangle pokes through the floor.
	hm.flatten_rect(p, half + Vector2(4.5, 4.5), -angle, floor_y, 9.0, half + Vector2(2.5, 2.5))
	var b := {
		"type": type, "center": p, "angle": angle, "size": size, "floor_y": floor_y,
		"wall_color": WALL_COLORS[rng.randi() % WALL_COLORS.size()],
		"roof_color": ROOF_COLORS[rng.randi() % ROOF_COLORS.size()],
		"town": town_name, "seed": rng.randi(),
	}
	if type == BType.WAREHOUSE:
		b.wall_color = Color(0.62, 0.67, 0.72)
		b.roof_color = Color(0.42, 0.47, 0.53)
	buildings.append(b)
	_register_in_grid(b)
	# Cover props next to the building.
	var n_props := rng.randi_range(0, 2)
	for k in n_props:
		var side := Vector2(half.x + 1.4, rng.randf_range(-half.y, half.y)) * (1.0 if rng.randf() < 0.5 else -1.0)
		var pp := p + side.rotated(-angle)
		props.append({"pos": Vector3(pp.x, floor_y, pp.y), "angle": rng.randf_range(0.0, TAU), "kind": rng.randi() % 2})
	return true


func _register_in_grid(b: Dictionary) -> void:
	var c: Vector2 = b.center
	var r: float = (b.size as Vector2).length() * 0.5 + 10.0
	for gx in range(floori((c.x - r) / GRID_CELL), floori((c.x + r) / GRID_CELL) + 1):
		for gz in range(floori((c.y - r) / GRID_CELL), floori((c.y + r) / GRID_CELL) + 1):
			var key := Vector2i(gx, gz)
			if not _grid.has(key):
				_grid[key] = []
			_grid[key].append(b)


## Is a point inside (or within `margin` m of) a building footprint?
## Uses the spatial hash, so it is cheap enough for vegetation placement.
func is_inside_building(p: Vector3, margin := 1.0) -> bool:
	var key := Vector2i(floori(p.x / GRID_CELL), floori(p.z / GRID_CELL))
	var list: Array = _grid.get(key, [])
	for b in list:
		var local := (Vector2(p.x, p.z) - (b.center as Vector2)).rotated(b.angle)
		var half: Vector2 = (b.size as Vector2) * 0.5 + Vector2(margin, margin)
		if absf(local.x) < half.x and absf(local.y) < half.y:
			return true
	return false


# --------------------------------------------------------------------------
# Building geometry
# --------------------------------------------------------------------------

## Builds all buildings under `parent`: one merged mesh + one static body per group.
func build(parent: Node3D, material: Material) -> void:
	var groups: Dictionary = {}   # group key -> Array of building dicts
	for b in buildings:
		var key: String = b.town if b.town != "" else "farm_%d_%d" % [int(b.center.x / 200.0), int(b.center.y / 200.0)]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(b)
	for key in groups:
		var list: Array = groups[key]
		var origin := Vector3.ZERO
		for b in list:
			origin += Vector3(b.center.x, b.floor_y, b.center.y)
		origin /= list.size()
		var mb := MeshBuilder.new()
		var body := StaticBody3D.new()
		body.name = "Buildings_" + str(key).replace(" ", "_")
		body.collision_layer = Layers.WORLD
		body.collision_mask = 0
		body.set_meta("surface", "building")
		body.position = origin
		parent.add_child(body)
		for b in list:
			var xf := Transform3D(Basis(Vector3.UP, b.angle), Vector3(b.center.x, b.floor_y, b.center.y) - origin)
			_build_one(mb, body, xf, b)
		# Props belonging to this group.
		for pr in props:
			var pp: Vector3 = pr.pos
			var near := false
			for b in list:
				if Vector2(pp.x, pp.z).distance_to(b.center) < 20.0:
					near = true
					break
			if near:
				_build_prop(mb, body, Transform3D(Basis(Vector3.UP, pr.angle), pp - origin), pr.kind)
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = mb.commit(material)
		mi.visibility_range_end = 1400.0
		body.add_child(mi)


func _build_one(mb: MeshBuilder, body: StaticBody3D, xf: Transform3D, b: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(b.seed)
	var size: Vector2 = b.size
	var w := size.x
	var d := size.y
	var wall_c: Color = b.wall_color
	var roof_c: Color = b.roof_color
	var type: int = b.type
	b["doors"] = []
	_door_building = b
	var wall_h := 3.0
	if type == BType.WAREHOUSE:
		wall_h = 5.5
	elif type == BType.SHED:
		wall_h = 2.5
	mb.xform = xf

	# Foundation (goes 1 m into the ground to hide terrain seams).
	_block(mb, body, xf, Vector3(0, FLOOR_Y - 0.6, 0), Vector3(w + 0.3, 1.2, d + 0.3), FOUNDATION_COLOR)

	var x0 := -w * 0.5 + WALL_T * 0.5
	var x1 := w * 0.5 - WALL_T * 0.5
	var z0 := -d * 0.5 + WALL_T * 0.5
	var z1 := d * 0.5 - WALL_T * 0.5
	var door := {"w": 1.4, "b": 0.0, "t": 2.3}
	var win := {"w": 1.2, "b": 1.0, "t": 2.1}

	match type:
		BType.SHED:
			# Three walls, open front: good cover spot.
			_add_door(Vector3(0.0, 0.0, z0), Vector3.FORWARD, false)
			_wall_x(mb, body, xf, z1, x0, x1, [], wall_h, wall_c)
			_wall_z(mb, body, xf, x0, z0, z1, [], wall_h, wall_c)
			_wall_z(mb, body, xf, x1, z0, z1, [], wall_h, wall_c)
		BType.WAREHOUSE:
			var big := {"w": 4.2, "b": 0.0, "t": 4.2}
			_wall_x(mb, body, xf, z0, x0, x1, [_op(0.0, big), _op(-5.5, win), _op(5.5, win)], wall_h, wall_c)
			_wall_x(mb, body, xf, z1, x0, x1, [_op(-4.0, win), _op(4.0, door)], wall_h, wall_c)
			_wall_z(mb, body, xf, x0, z0, z1, [_op(0.0, win)], wall_h, wall_c)
			_wall_z(mb, body, xf, x1, z0, z1, [_op(-2.0, door), _op(2.5, win)], wall_h, wall_c)
			# Stacked crates inside for cover + loot spots on top.
			_block(mb, body, xf, Vector3(-4.5, FLOOR_Y + 0.6, 2.5), Vector3(1.2, 1.2, 1.2), WOOD_COLOR)
			_block(mb, body, xf, Vector3(-3.2, FLOOR_Y + 0.6, 2.7), Vector3(1.2, 1.2, 1.2), WOOD_COLOR.darkened(0.1))
			_block(mb, body, xf, Vector3(4.0, FLOOR_Y + 0.6, -1.5), Vector3(1.2, 1.2, 1.2), WOOD_COLOR)
			_add_loot(b, [Vector3(-3.8, FLOOR_Y + 1.2, 2.6), Vector3(0, FLOOR_Y, 0), Vector3(4.0, FLOOR_Y, 3.0), Vector3(-5.0, FLOOR_Y, -3.5)])
		BType.LONGHOUSE:
			_wall_x(mb, body, xf, z0, x0, x1, [_op(-3.0, door), _op(-0.6 + 2.9, win), _op(-5.0, win), _op(5.0, win)], wall_h, wall_c)
			_wall_x(mb, body, xf, z1, x0, x1, [_op(-4.5, win), _op(-2.0, win), _op(4.5, door)], wall_h, wall_c)
			_wall_z(mb, body, xf, x0, z0, z1, [_op(0.0, win)], wall_h, wall_c)
			_wall_z(mb, body, xf, x1, z0, z1, [_op(0.0, win)], wall_h, wall_c)
			# Interior wall with a doorway: two rooms.
			_wall_z(mb, body, xf, 0.5, z0 + WALL_T, z1 - WALL_T, [_op(-1.0, door)], wall_h, wall_c.darkened(0.08))
			_block(mb, body, xf, Vector3(-4.5, FLOOR_Y + 0.38, 2.0), Vector3(1.6, 0.76, 0.9), WOOD_COLOR)
			_add_loot(b, [Vector3(-3.0, FLOOR_Y, 1.5), Vector3(-4.5, FLOOR_Y + 0.8, 2.0), Vector3(3.0, FLOOR_Y, -1.0), Vector3(4.5, FLOOR_Y, 2.0)])
		_:
			var door_x := rng.randf_range(-1.5, 1.5)
			var win_x := 2.6 if door_x < 0.0 else -2.6
			_wall_x(mb, body, xf, z0, x0, x1, [_op(door_x, door), _op(win_x, win)], wall_h, wall_c)
			_wall_x(mb, body, xf, z1, x0, x1, [_op(-2.0, win), _op(2.0, win)], wall_h, wall_c)
			_wall_z(mb, body, xf, x0, z0, z1, [_op(0.5, win)], wall_h, wall_c)
			_wall_z(mb, body, xf, x1, z0, z1, [_op(-0.5, win)], wall_h, wall_c)
			# Table and bed.
			_block(mb, body, xf, Vector3(-2.2, FLOOR_Y + 0.38, 1.6), Vector3(1.3, 0.76, 0.8), WOOD_COLOR)
			_block(mb, body, xf, Vector3(2.6, FLOOR_Y + 0.25, 1.9), Vector3(1.0, 0.5, 2.0), Color(0.75, 0.45, 0.4))
			_add_loot(b, [Vector3(-2.2, FLOOR_Y + 0.8, 1.6), Vector3(0.0, FLOOR_Y, 0.0), Vector3(2.6, FLOOR_Y + 0.5, 1.9)])

	_door_building = {}

	# Floor inside (slightly different color from the foundation sides).
	mb.add_box(Vector3(0, FLOOR_Y - 0.01, 0), Vector3(w - WALL_T * 2.0, 0.04, d - WALL_T * 2.0), Color(0.6, 0.5, 0.38))

	# Roof
	var top := FLOOR_Y + wall_h
	if type == BType.SHED:
		# Single slope roof.
		var slope := 0.25
		var roof_len := sqrt((d + 0.6) * (d + 0.6) + slope * slope)
		var ang := atan2(slope, d + 0.6)
		_block(mb, body, xf, Vector3(0, top + 0.12, 0), Vector3(w + 0.6, 0.16, roof_len), roof_c, Basis(Vector3.RIGHT, ang))
	else:
		var ridge := 1.8 if type != BType.WAREHOUSE else 1.6
		var ov := 0.45
		# Roof plane passes through the wall tops (z = +/- d/2) and the ridge (z = 0).
		var ang := atan2(ridge, d * 0.5)
		var half_span := d * 0.5 + ov
		var slab_len := half_span / cos(ang)
		for s in [-1.0, 1.0]:
			var mid_y := top + ridge - tan(ang) * half_span * 0.5 + 0.1
			var center := Vector3(0, mid_y, s * half_span * 0.5)
			# Rotate around X so the slab slopes down toward +/- Z.
			_block(mb, body, xf, center, Vector3(w + ov * 2.0, 0.18, slab_len), roof_c, Basis(Vector3.RIGHT, s * ang))
		# Gable triangles at both ends.
		for s in [-1.0, 1.0]:
			var gx: float = s * (w * 0.5 - WALL_T * 0.5)
			var p0 := Vector3(gx - WALL_T * 0.5, top, -d * 0.5)
			var p1 := Vector3(gx - WALL_T * 0.5, top, d * 0.5)
			var p2 := Vector3(gx - WALL_T * 0.5, top + ridge, 0.0)
			mb.add_prism(p0, p1, p2, Vector3.RIGHT, WALL_T, wall_c.darkened(0.05))
			var shape := ConvexPolygonShape3D.new()
			shape.points = PackedVector3Array([p0, p1, p2, p0 + Vector3(WALL_T, 0, 0), p1 + Vector3(WALL_T, 0, 0), p2 + Vector3(WALL_T, 0, 0)])
			_add_shape(body, shape, xf)
		if type == BType.COTTAGE:
			# Chimney
			_block(mb, body, xf, Vector3(w * 0.25, top + ridge * 0.7, d * 0.2), Vector3(0.6, 1.8, 0.6), Color(0.6, 0.35, 0.3))


func _build_prop(mb: MeshBuilder, body: StaticBody3D, xf: Transform3D, kind: int) -> void:
	mb.xform = xf
	if kind == 0:
		_block(mb, body, xf, Vector3(0, 0.55, 0), Vector3(1.1, 1.1, 1.1), WOOD_COLOR)
		mb.add_box(Vector3(0, 0.55, 0), Vector3(1.14, 0.12, 1.14), WOOD_COLOR.darkened(0.25))
	else:
		# Barrel (octagonal), collision approximated by a box.
		mb.add_frustum(Vector3.ZERO, 0.4, 0.4, 1.1, 8, Color(0.3, 0.45, 0.6), true)
		mb.add_frustum(Vector3(0, 0.5, 0), 0.42, 0.42, 0.1, 8, Color(0.25, 0.3, 0.35), false)
		var shape := CylinderShape3D.new()
		shape.radius = 0.4
		shape.height = 1.1
		_add_shape(body, shape, xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.55, 0)))


static func _op(x: float, spec: Dictionary) -> Dictionary:
	return {"x": x, "w": spec.w, "b": spec.b, "t": spec.t}


## Registers loot spawn points (building-local -> world space).
func _add_loot(b: Dictionary, local_points: Array) -> void:
	var world_xf := Transform3D(Basis(Vector3.UP, b.angle), Vector3(b.center.x, b.floor_y, b.center.y))
	for p in local_points:
		loot_points.append(world_xf * (p as Vector3))


## One box: mesh + collision shape.
func _block(mb: MeshBuilder, body: StaticBody3D, xf: Transform3D, center: Vector3, size: Vector3, color: Color, basis := Basis.IDENTITY) -> void:
	mb.add_box(center, size, color, basis)
	var shape := BoxShape3D.new()
	shape.size = size
	_add_shape(body, shape, xf * Transform3D(basis, center))


func _add_shape(body: StaticBody3D, shape: Shape3D, local_xf: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = local_xf
	body.add_child(cs)


## Records a doorway of the building being built (for bot navigation).
## `local` = door center on the floor, `out_local` = direction out of the room.
func _add_door(local: Vector3, out_local: Vector3, interior: bool) -> void:
	var b := _door_building
	if b.is_empty():
		return
	var wx := Transform3D(Basis(Vector3.UP, b.angle), Vector3(b.center.x, b.floor_y, b.center.y))
	var room := 0
	if int(b.type) == BType.LONGHOUSE:
		room = -1 if interior else (0 if local.x < 0.5 else 1)
	(b.doors as Array).append({"pos": wx * local, "out": (wx.basis * out_local).normalized(), "room": room})


## Room index of a world point inside a building (long houses have two).
func room_of(b: Dictionary, p: Vector3) -> int:
	if int(b.type) != BType.LONGHOUSE:
		return 0
	var local := (Vector2(p.x, p.z) - (b.center as Vector2)).rotated(b.angle)
	return 0 if local.x < 0.5 else 1


## The building whose footprint (+ margin) contains p, or {}.
func building_at(p: Vector3, margin := 0.0) -> Dictionary:
	var key := Vector2i(floori(p.x / GRID_CELL), floori(p.z / GRID_CELL))
	for b in _grid.get(key, []):
		var local := (Vector2(p.x, p.z) - (b.center as Vector2)).rotated(b.angle)
		var half: Vector2 = (b.size as Vector2) * 0.5 + Vector2(margin, margin)
		if absf(local.x) < half.x and absf(local.y) < half.y:
			return b
	return {}


## Waypoints through doorways to walk from `from` to `to` (both may be inside
## buildings). Empty when a straight line is fine.
func plan_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var bf := building_at(from, 0.1)
	var bt := building_at(to, -0.2)
	if not bf.is_empty() and bf == bt:
		var rf := room_of(bf, from)
		var rt := room_of(bt, to)
		if rf != rt:
			for d in bf.get("doors", []):
				if int(d.room) == -1:
					var dp: Vector3 = d.pos
					var out: Vector3 = d.out
					# Interior door: its "out" points toward room 1 (+X).
					var s := 1.0 if rf == 1 else -1.0
					pts.append(dp + out * 0.9 * s)
					pts.append(dp)
					pts.append(dp - out * 0.9 * s)
		return pts
	if not bf.is_empty():
		var d := _best_door(bf, room_of(bf, from), to)
		if not d.is_empty():
			pts.append(d.pos - d.out * 0.9)
			pts.append(d.pos)
			pts.append(d.pos + d.out * 1.4)
	if not bt.is_empty():
		var start := from if pts.is_empty() else pts[pts.size() - 1]
		var d := _best_door(bt, room_of(bt, to), start)
		if not d.is_empty():
			pts.append(d.pos + d.out * 1.4)
			pts.append(d.pos)
			pts.append(d.pos - d.out * 0.9)
	return pts


## Exterior doorway of a room closest to `near`.
func _best_door(b: Dictionary, room: int, near: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for d in b.get("doors", []):
		if int(d.room) == -1 or (int(d.room) != room and int(b.type) == BType.LONGHOUSE):
			continue
		var dist := (d.pos as Vector3).distance_squared_to(near)
		if dist < best_d:
			best_d = dist
			best = d
	return best


## Wall running along X at local z, from x0 to x1, with openings (doors/windows).
func _wall_x(mb: MeshBuilder, body: StaticBody3D, xf: Transform3D, z: float, x0: float, x1: float, openings: Array, h: float, color: Color) -> void:
	for op in openings:
		if float(op.b) <= 0.01:
			_add_door(Vector3(op.x, 0.0, z), Vector3(0, 0, signf(z)), false)
	for seg in _wall_segments(x0, x1, openings, h):
		var c: Vector3 = seg.center
		var s: Vector3 = seg.size
		_block(mb, body, xf, Vector3(c.x, c.y, z), Vector3(s.x, s.y, WALL_T), color)
	_add_sills(mb, openings, true, z, color)


## Wall running along Z at local x, from z0 to z1.
func _wall_z(mb: MeshBuilder, body: StaticBody3D, xf: Transform3D, x: float, z0: float, z1: float, openings: Array, h: float, color: Color) -> void:
	var interior := absf(x) < 1.0
	for op in openings:
		if float(op.b) <= 0.01:
			_add_door(Vector3(x, 0.0, op.x), Vector3(1, 0, 0) if interior else Vector3(signf(x), 0, 0), interior)
	for seg in _wall_segments(z0, z1, openings, h):
		var c: Vector3 = seg.center
		var s: Vector3 = seg.size
		_block(mb, body, xf, Vector3(x, c.y, c.x), Vector3(WALL_T, s.y, s.x), color)
	_add_sills(mb, openings, false, x, color)


func _add_sills(mb: MeshBuilder, openings: Array, along_x: bool, at: float, _color: Color) -> void:
	for op in openings:
		if float(op.b) <= 0.01:
			continue
		var y := FLOOR_Y + float(op.b) - 0.05
		if along_x:
			mb.add_box(Vector3(op.x, y, at), Vector3(float(op.w) + 0.2, 0.1, WALL_T + 0.2), TRIM_COLOR)
		else:
			mb.add_box(Vector3(at, y, op.x), Vector3(WALL_T + 0.2, 0.1, float(op.w) + 0.2), TRIM_COLOR)


## Splits a wall (1D, u from a to b) into solid boxes around the openings.
## Returns [{center: Vector3(u, y, 0), size: Vector3(len_u, height, 0)}].
func _wall_segments(a: float, b: float, openings: Array, h: float) -> Array:
	var out := []
	var ops := openings.duplicate()
	ops.sort_custom(func(p, q): return float(p.x) < float(q.x))
	var cursor := a - WALL_T * 0.5
	var end := b + WALL_T * 0.5
	for op in ops:
		var o0: float = float(op.x) - float(op.w) * 0.5
		var o1: float = float(op.x) + float(op.w) * 0.5
		if o0 > cursor + 0.01:
			out.append({"center": Vector3((cursor + o0) * 0.5, FLOOR_Y + h * 0.5, 0), "size": Vector3(o0 - cursor, h, 0)})
		var ob: float = op.b
		var ot: float = op.t
		if ob > 0.01:
			out.append({"center": Vector3((o0 + o1) * 0.5, FLOOR_Y + ob * 0.5, 0), "size": Vector3(o1 - o0, ob, 0)})
		if ot < h - 0.01:
			out.append({"center": Vector3((o0 + o1) * 0.5, FLOOR_Y + (ot + h) * 0.5, 0), "size": Vector3(o1 - o0, h - ot, 0)})
		cursor = o1
	if end > cursor + 0.01:
		out.append({"center": Vector3((cursor + end) * 0.5, FLOOR_Y + h * 0.5, 0), "size": Vector3(end - cursor, h, 0)})
	return out
