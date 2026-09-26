class_name Vegetation
extends Node3D
## Trees, bushes and rocks rendered with MultiMesh.
##
## Performance design (the island has ~20-30k objects):
## - Instances are grouped in 128 m cells: one MultiMeshInstance3D per cell,
##   per kind and per LOD, so frustum + distance culling work per cell.
## - Two LODs using visibility ranges (no per-frame script cost).
## - Only LOD0 casts shadows.
## - Collision (trunks / rocks) is created directly on the PhysicsServer3D:
##   a single static body per cell, no nodes per tree.

enum Kind { PINE, OAK, BIRCH, BUSH, ROCK }
const KIND_COUNT := 5

const CELL := 128.0
const GRID := 16          # 2048 / 128
const SPACING := 5.0      # candidate grid spacing (m)

## [lod0_end, lod1_end] in meters (scaled by the graphics preset).
const RANGES := {
	Kind.PINE: [180.0, 1000.0],
	Kind.OAK: [180.0, 950.0],
	Kind.BIRCH: [170.0, 850.0],
	Kind.BUSH: [110.0, 330.0],
	Kind.ROCK: [200.0, 700.0],
}

var hm: HeightMap
var tree_count := 0
var bush_count := 0
var rock_count := 0

## cell index -> kind -> Array of [Transform3D (cell-local), Color custom]
var _cells: Array = []
var _meshes: Array = []          # kind -> [lod0 ArrayMesh, lod1 ArrayMesh]
var _material: ShaderMaterial
var _lod0_nodes: Array[MultiMeshInstance3D] = []
var _lod1_nodes: Array[MultiMeshInstance3D] = []
var _lod_kinds: Array[int] = []  # parallel to _lod0_nodes / _lod1_nodes
var _bodies: Array[RID] = []
var _shapes: Array[Shape3D] = []   # keep shape resources alive
var _shape_cache: Dictionary = {}  # "kind_bucket" -> Shape3D
var _wood_tag: Node
var _stone_tag: Node


func _init() -> void:
	name = "Vegetation"


func _ready() -> void:
	# Tag nodes: ray hits on server bodies report these as `collider`,
	# so impact effects know whether a bullet hit wood or stone.
	_wood_tag = Node.new()
	_wood_tag.name = "WoodSurface"
	_wood_tag.set_meta("surface", "wood")
	add_child(_wood_tag)
	_stone_tag = Node.new()
	_stone_tag.name = "StoneSurface"
	_stone_tag.set_meta("surface", "stone")
	add_child(_stone_tag)


func _exit_tree() -> void:
	for rid in _bodies:
		PhysicsServer3D.free_rid(rid)
	_bodies.clear()


# --------------------------------------------------------------------------
# Placement
# --------------------------------------------------------------------------

func place(p_hm: HeightMap, terrain: TerrainBuilder, settlements: Settlements, map_seed: int) -> void:
	hm = p_hm
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed * 7 + 11
	_cells.clear()
	for c in GRID * GRID:
		var per_kind := []
		for k in KIND_COUNT:
			per_kind.append([])
		_cells.append(per_kind)

	var steps := int(HeightMap.SIZE / SPACING)
	for gz in steps:
		for gx in steps:
			var x := -HeightMap.HALF + (gx + 0.5) * SPACING + rng.randf_range(-2.2, 2.2)
			var z := -HeightMap.HALF + (gz + 0.5) * SPACING + rng.randf_range(-2.2, 2.2)
			if not hm.in_bounds(x, z, 6.0):
				continue
			var h := hm.get_height(x, z)
			if h < HeightMap.WATER_LEVEL + 1.3:
				continue
			if hm.get_shore_distance(x, z) < 4.0:
				continue
			var ny := hm.get_normal(x, z).y
			var roll := rng.randf()
			var kind := -1
			if ny < 0.78:
				# Steep ground: mostly bare rock, a few boulders.
				if roll < 0.05:
					kind = Kind.ROCK
			else:
				var forest := terrain.sample_forest(x, z)
				var alt_factor := 1.0 - clampf((h - 85.0) / 30.0, 0.0, 1.0)
				var p_tree := (0.012 + forest * 0.5) * alt_factor
				if roll < p_tree:
					if h > 45.0 or (forest > 0.65 and rng.randf() < 0.55):
						kind = Kind.PINE
					else:
						kind = Kind.OAK if rng.randf() < 0.58 else Kind.BIRCH
				elif roll < p_tree + 0.035 + forest * 0.06:
					kind = Kind.BUSH
				elif roll < p_tree + 0.035 + forest * 0.06 + 0.006:
					kind = Kind.ROCK
			if kind < 0:
				continue
			var p3 := Vector3(x, h, z)
			if settlements.is_inside_building(p3, 4.5 if kind != Kind.BUSH else 2.0):
				continue
			_add_instance(rng, kind, p3)


func _add_instance(rng: RandomNumberGenerator, kind: int, pos: Vector3) -> void:
	var cx := clampi(int((pos.x + HeightMap.HALF) / CELL), 0, GRID - 1)
	var cz := clampi(int((pos.z + HeightMap.HALF) / CELL), 0, GRID - 1)
	var origin := _cell_origin(cx, cz)
	# Quantized scale so collision shapes can be shared between instances.
	var bucket := rng.randi_range(0, 3)
	var s := 0.78 + bucket * 0.17
	var rot := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(s, s * rng.randf_range(0.92, 1.1), s))
	if kind == Kind.ROCK:
		rot = Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(s * 1.3, s, s * 1.1))
	var sink := 0.35 if kind != Kind.ROCK else 0.5 * s
	var xf := Transform3D(rot, pos - origin - Vector3(0, sink, 0))
	var tint := Color(rng.randf_range(0.85, 1.12), rng.randf_range(0.88, 1.1), rng.randf_range(0.8, 1.05), rng.randf())
	_cells[cz * GRID + cx][kind].append([xf, tint, bucket])
	match kind:
		Kind.BUSH:
			bush_count += 1
		Kind.ROCK:
			rock_count += 1
		_:
			tree_count += 1


func _cell_origin(cx: int, cz: int) -> Vector3:
	return Vector3(-HeightMap.HALF + (cx + 0.5) * CELL, 0.0, -HeightMap.HALF + (cz + 0.5) * CELL)


# --------------------------------------------------------------------------
# Node / physics creation (can be spread over frames with build_cells()).
# --------------------------------------------------------------------------

func prepare_meshes() -> void:
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/foliage.gdshader")
	_meshes.clear()
	for k in KIND_COUNT:
		_meshes.append([_build_mesh(k, 0), _build_mesh(k, 1)])


func cell_count() -> int:
	return GRID * GRID


## Builds nodes + collision for cells [from, to).
func build_cells(from: int, to: int, view_scale: float) -> void:
	var space := get_world_3d().space
	for c in range(from, mini(to, GRID * GRID)):
		var cx := c % GRID
		@warning_ignore("integer_division")
		var cz := c / GRID
		var origin := _cell_origin(cx, cz)
		var wood_body := RID()
		var stone_body := RID()
		for kind in KIND_COUNT:
			var list: Array = _cells[c][kind]
			if list.is_empty():
				continue
			# Both LODs share the same instances: build the raw buffer once.
			var buffer := _make_buffer(list)
			for lod in 2:
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.use_custom_data = true
				mm.mesh = _meshes[kind][lod]
				mm.instance_count = list.size()
				mm.buffer = buffer
				var mmi := MultiMeshInstance3D.new()
				mmi.multimesh = mm
				mmi.position = origin
				mmi.material_override = _material
				if lod == 0:
					mmi.visibility_range_end = float(RANGES[kind][0]) * view_scale
					mmi.visibility_range_end_margin = 8.0
					_lod0_nodes.append(mmi)
				else:
					mmi.visibility_range_begin = float(RANGES[kind][0]) * view_scale
					mmi.visibility_range_begin_margin = 8.0
					mmi.visibility_range_end = float(RANGES[kind][1]) * view_scale
					mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					_lod1_nodes.append(mmi)
				if kind == Kind.BUSH:
					mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(mmi)
			_lod_kinds.append(kind)
			# Collision
			if kind == Kind.BUSH:
				continue
			var is_rock := kind == Kind.ROCK
			var body := stone_body if is_rock else wood_body
			if not body.is_valid():
				body = _create_body(space, origin, _stone_tag if is_rock else _wood_tag)
				if is_rock:
					stone_body = body
				else:
					wood_body = body
			for item in list:
				var xf: Transform3D = item[0]
				var shape := _get_shape(kind, int(item[2]))
				var shape_xf := Transform3D(Basis.IDENTITY, xf.origin + _shape_offset(kind, int(item[2])))
				PhysicsServer3D.body_add_shape(body, shape.get_rid(), shape_xf)


## MultiMesh raw buffer: per instance a 3x4 row-major transform (12 floats)
## followed by the custom data color (4 floats). Much faster than calling
## set_instance_transform() thousands of times.
static func _make_buffer(list: Array) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(list.size() * 16)
	for n in list.size():
		var t: Transform3D = list[n][0]
		var c: Color = list[n][1]
		var b := t.basis
		var k := n * 16
		buf[k] = b.x.x
		buf[k + 1] = b.y.x
		buf[k + 2] = b.z.x
		buf[k + 3] = t.origin.x
		buf[k + 4] = b.x.y
		buf[k + 5] = b.y.y
		buf[k + 6] = b.z.y
		buf[k + 7] = t.origin.y
		buf[k + 8] = b.x.z
		buf[k + 9] = b.y.z
		buf[k + 10] = b.z.z
		buf[k + 11] = t.origin.z
		buf[k + 12] = c.r
		buf[k + 13] = c.g
		buf[k + 14] = c.b
		buf[k + 15] = c.a
	return buf


func _create_body(space: RID, origin: Vector3, tag: Node) -> RID:
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(body, space)
	PhysicsServer3D.body_set_collision_layer(body, Layers.WORLD)
	PhysicsServer3D.body_set_collision_mask(body, 0)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis.IDENTITY, origin))
	PhysicsServer3D.body_attach_object_instance_id(body, tag.get_instance_id())
	_bodies.append(body)
	return body


func _bucket_scale(bucket: int) -> float:
	return 0.78 + bucket * 0.17


func _get_shape(kind: int, bucket: int) -> Shape3D:
	var key := "%d_%d" % [kind, bucket]
	if _shape_cache.has(key):
		return _shape_cache[key]
	var s := _bucket_scale(bucket)
	var shape: Shape3D
	match kind:
		Kind.ROCK:
			var sp := SphereShape3D.new()
			sp.radius = 1.0 * s
			shape = sp
		_:
			var cy := CylinderShape3D.new()
			cy.radius = (0.3 if kind == Kind.PINE else (0.36 if kind == Kind.OAK else 0.2)) * s
			cy.height = 4.0 * s
			shape = cy
	_shape_cache[key] = shape
	_shapes.append(shape)
	return shape


func _shape_offset(kind: int, bucket: int) -> Vector3:
	var s := _bucket_scale(bucket)
	if kind == Kind.ROCK:
		return Vector3(0, 0.3 * s, 0)
	return Vector3(0, 2.0 * s, 0)


func apply_view_distance(view_scale: float) -> void:
	for n in _lod0_nodes.size():
		var kind := _lod_kinds[n]
		_lod0_nodes[n].visibility_range_end = float(RANGES[kind][0]) * view_scale
		_lod1_nodes[n].visibility_range_begin = float(RANGES[kind][0]) * view_scale
		_lod1_nodes[n].visibility_range_end = float(RANGES[kind][1]) * view_scale


# --------------------------------------------------------------------------
# Procedural meshes (vertex color alpha = 1 marks foliage for the shader).
# --------------------------------------------------------------------------

func _build_mesh(kind: int, lod: int) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + kind * 17 + lod
	var trunk := Color(0.45, 0.3, 0.19, 0.0)
	match kind:
		Kind.PINE:
			if lod == 0:
				mb.add_frustum(Vector3.ZERO, 0.3, 0.17, 2.4, 6, trunk, false)
				var greens := [Color(0.16, 0.42, 0.24, 1), Color(0.19, 0.48, 0.26, 1), Color(0.23, 0.54, 0.29, 1)]
				mb.add_frustum(Vector3(0, 1.5, 0), 2.0, 0.0, 3.0, 7, greens[0], true, 0.0)
				mb.add_frustum(Vector3(0, 3.0, 0), 1.55, 0.0, 2.7, 7, greens[1], true, 0.4)
				mb.add_frustum(Vector3(0, 4.4, 0), 1.1, 0.0, 2.4, 7, greens[2], true, 0.9)
			else:
				mb.add_frustum(Vector3(0, 1.2, 0), 1.9, 0.0, 5.6, 5, Color(0.18, 0.46, 0.26, 1), false)
		Kind.OAK:
			if lod == 0:
				mb.add_frustum(Vector3.ZERO, 0.38, 0.26, 2.8, 6, trunk, false)
				var leaf := Color(0.33, 0.62, 0.24, 1)
				mb.add_sphere(Vector3(0, 3.9, 0), Vector3(2.3, 1.9, 2.3), leaf, 7, 4, 0.12, rng, 0.04)
				mb.add_sphere(Vector3(1.1, 3.3, 0.5), Vector3(1.5, 1.3, 1.5), leaf.darkened(0.05), 6, 4, 0.1, rng, 0.04)
				mb.add_sphere(Vector3(-0.9, 3.5, -0.7), Vector3(1.6, 1.4, 1.6), leaf.lightened(0.05), 6, 4, 0.1, rng, 0.04)
			else:
				mb.add_frustum(Vector3.ZERO, 0.35, 0.3, 2.4, 4, trunk, false)
				mb.add_sphere(Vector3(0, 3.8, 0), Vector3(2.6, 2.1, 2.6), Color(0.33, 0.62, 0.24, 1), 5, 3)
		Kind.BIRCH:
			var bark := Color(0.9, 0.9, 0.85, 0.0)
			if lod == 0:
				mb.add_frustum(Vector3.ZERO, 0.2, 0.14, 3.8, 6, bark, false)
				mb.add_frustum(Vector3(0, 1.2, 0), 0.205, 0.2, 0.18, 6, Color(0.2, 0.2, 0.2, 0.0), false)
				mb.add_frustum(Vector3(0, 2.4, 0), 0.19, 0.18, 0.15, 6, Color(0.2, 0.2, 0.2, 0.0), false)
				mb.add_sphere(Vector3(0, 4.5, 0), Vector3(1.5, 2.3, 1.5), Color(0.55, 0.76, 0.3, 1), 7, 5, 0.12, rng, 0.05)
			else:
				mb.add_frustum(Vector3.ZERO, 0.18, 0.16, 3.2, 4, bark, false)
				mb.add_sphere(Vector3(0, 4.4, 0), Vector3(1.6, 2.4, 1.6), Color(0.55, 0.76, 0.3, 1), 5, 3)
		Kind.BUSH:
			var bush := Color(0.3, 0.57, 0.23, 1)
			if lod == 0:
				mb.add_sphere(Vector3(0, 0.55, 0), Vector3(1.0, 0.8, 1.0), bush, 7, 4, 0.15, rng, 0.05)
				mb.add_sphere(Vector3(0.6, 0.45, 0.3), Vector3(0.7, 0.6, 0.7), bush.lightened(0.06), 6, 3, 0.12, rng, 0.05)
			else:
				mb.add_sphere(Vector3(0, 0.55, 0), Vector3(1.1, 0.8, 1.1), bush, 5, 3)
		Kind.ROCK:
			var stone := Color(0.56, 0.55, 0.53, 0.0)
			if lod == 0:
				mb.add_sphere(Vector3(0, 0.3, 0), Vector3(1.1, 0.85, 1.0), stone, 7, 4, 0.18, rng, 0.05)
			else:
				mb.add_sphere(Vector3(0, 0.3, 0), Vector3(1.1, 0.85, 1.0), stone, 5, 3, 0.15, rng)
	return mb.commit()
