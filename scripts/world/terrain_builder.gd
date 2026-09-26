class_name TerrainBuilder
extends RefCounted
## Turns a HeightMap into renderable chunks, a physics collider and occluders.
##
## Performance notes:
## - 16 x 16 chunks of 128 m. Each chunk has two meshes:
##     LOD0: 4 m cells, visible up to LOD0_RANGE (casts shadows)
##     LOD1: 16 m cells + skirts, visible beyond (no shadows)
##   Switching uses GeometryInstance3D visibility ranges (no script per frame).
## - One HeightMapShape3D for the whole island (Jolt handles it very efficiently).
## - A coarse ArrayOccluder3D (slightly sunk into the ground) lets the renderer
##   cull trees / houses hidden behind hills.

const CHUNK_CELLS := 32
const CHUNKS := 16  # HeightMap.CELLS / CHUNK_CELLS
const LOD1_STEP := 4
const LOD0_RANGE := 380.0
const SKIRT_DEPTH := 8.0

const C_SAND := Color(0.93, 0.85, 0.62)
const C_SAND_WET := Color(0.74, 0.68, 0.5)
const C_ROCK := Color(0.6, 0.57, 0.53)
const C_ROCK_DARK := Color(0.47, 0.45, 0.43)
const C_DIRT := Color(0.66, 0.54, 0.38)
const C_SNOW := Color(0.94, 0.95, 0.97)
const C_MEADOW := Color(0.58, 0.79, 0.33)
const C_GRASS := Color(0.45, 0.7, 0.29)
const C_FOREST := Color(0.33, 0.56, 0.25)
const C_ALPINE := Color(0.52, 0.6, 0.38)

var hm: HeightMap
var material: StandardMaterial3D
var lod0: Array[MeshInstance3D] = []
var lod1: Array[MeshInstance3D] = []
## Per-vertex forest density 0..1 (shared with vegetation placement).
var forest := PackedFloat32Array()
var _tint := PackedFloat32Array()


func _init(p_hm: HeightMap) -> void:
	hm = p_hm
	material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.95
	material.metallic_specular = 0.2


## Precomputes per-vertex noise fields used by coloring and vegetation.
func prepare() -> void:
	var n := HeightMap.VERTS * HeightMap.VERTS
	forest.resize(n)
	_tint.resize(n)
	for j in HeightMap.VERTS:
		var z := -HeightMap.HALF + j * HeightMap.CELL_SIZE
		var row := j * HeightMap.VERTS
		for i in HeightMap.VERTS:
			var x := -HeightMap.HALF + i * HeightMap.CELL_SIZE
			forest[row + i] = smoothstep(-0.05, 0.35, hm.n_forest.get_noise_2d(x, z))
			_tint[row + i] = hm.n_color.get_noise_2d(x, z)


func sample_forest(x: float, z: float) -> float:
	var i := clampi(roundi((x + HeightMap.HALF) / HeightMap.CELL_SIZE), 0, HeightMap.CELLS)
	var j := clampi(roundi((z + HeightMap.HALF) / HeightMap.CELL_SIZE), 0, HeightMap.CELLS)
	return forest[j * HeightMap.VERTS + i]


## Stylized ground color from height, slope and surface data.
func face_color(h: float, ny: float, vidx: int, dirt: bool, rnd: float) -> Color:
	var c: Color
	var shore := hm.shore_dist[vidx]
	if h < HeightMap.WATER_LEVEL - 0.8:
		c = C_SAND_WET
	elif h < HeightMap.WATER_LEVEL + 1.4 or (shore < 2.5 and h < HeightMap.WATER_LEVEL + 2.5):
		c = C_SAND
	elif ny < 0.64:
		c = C_ROCK_DARK
	elif ny < 0.78:
		c = C_ROCK
	elif dirt:
		c = C_DIRT
	elif h > 112.0 and ny > 0.82:
		c = C_SNOW
	else:
		var f := forest[vidx]
		c = C_MEADOW.lerp(C_GRASS, clampf(f * 1.6, 0.0, 1.0))
		c = c.lerp(C_FOREST, clampf(f * 1.6 - 0.8, 0.0, 1.0))
		if h > 60.0:
			c = c.lerp(C_ALPINE, clampf((h - 60.0) / 40.0, 0.0, 0.85))
	# Low-poly patchiness: smooth noise patches + per-face random tint.
	var k := _tint[vidx] * 0.07 + rnd * 0.05
	return Color(c.r + k, c.g + k, c.b + k * 0.6)


static func _hash01(i: int, j: int, t: int) -> float:
	var hsh := (i * 73856093) ^ (j * 19349663) ^ (t * 83492791)
	hsh = (hsh ^ (hsh >> 13)) * 1274126177
	return float(hsh & 0xFFFF) / 65535.0 - 0.5


func chunk_origin(ci: int, cj: int) -> Vector3:
	return Vector3(-HeightMap.HALF + ci * CHUNK_CELLS * HeightMap.CELL_SIZE, 0.0,
		-HeightMap.HALF + cj * CHUNK_CELLS * HeightMap.CELL_SIZE)


## Builds both LOD meshes for chunk (ci, cj) under `parent`.
func build_chunk(parent: Node3D, ci: int, cj: int, view_scale: float) -> void:
	var origin := chunk_origin(ci, cj)
	var i0 := ci * CHUNK_CELLS
	var j0 := cj * CHUNK_CELLS
	var max_h := -1.0e9
	for j in range(j0, j0 + CHUNK_CELLS + 1):
		for i in range(i0, i0 + CHUNK_CELLS + 1):
			max_h = maxf(max_h, hm.heights[j * HeightMap.VERTS + i])
	var deep := max_h < HeightMap.WATER_LEVEL - 5.0

	if not deep:
		var mi0 := MeshInstance3D.new()
		mi0.name = "T%d_%d" % [ci, cj]
		mi0.mesh = _build_lod0(i0, j0)
		mi0.position = origin
		mi0.visibility_range_end = LOD0_RANGE * view_scale
		mi0.visibility_range_end_margin = 10.0
		parent.add_child(mi0)
		lod0.append(mi0)

	var mi1 := MeshInstance3D.new()
	mi1.name = "T%d_%d_far" % [ci, cj]
	mi1.mesh = _build_lod1(i0, j0)
	mi1.position = origin
	mi1.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not deep:
		mi1.visibility_range_begin = LOD0_RANGE * view_scale
		mi1.visibility_range_begin_margin = 10.0
	parent.add_child(mi1)
	lod1.append(mi1)


func _build_lod0(i0: int, j0: int) -> ArrayMesh:
	var cells := CHUNK_CELLS * CHUNK_CELLS
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(cells * 6)
	norms.resize(cells * 6)
	cols.resize(cells * 6)
	var cs := HeightMap.CELL_SIZE
	var V := HeightMap.VERTS
	var k := 0
	for j in range(j0, j0 + CHUNK_CELLS):
		for i in range(i0, i0 + CHUNK_CELLS):
			var row := j * V + i
			var h00 := hm.heights[row]
			var h10 := hm.heights[row + 1]
			var h01 := hm.heights[row + V]
			var h11 := hm.heights[row + V + 1]
			var x0 := (i - i0) * cs
			var z0 := (j - j0) * cs
			var p00 := Vector3(x0, h00, z0)
			var p10 := Vector3(x0 + cs, h10, z0)
			var p01 := Vector3(x0, h01, z0 + cs)
			var p11 := Vector3(x0 + cs, h11, z0 + cs)
			var dirt := hm.surface[row] != 0 or hm.surface[row + V + 1] != 0
			# Triangle A (00, 10, 01) - same split as Jolt's HeightMapShape3D.
			var na := Vector3(-(h10 - h00), cs, -(h01 - h00)).normalized()
			var ca := face_color((h00 + h10 + h01) / 3.0, na.y, row, dirt, _hash01(i, j, 0))
			verts[k] = p00
			verts[k + 1] = p10
			verts[k + 2] = p01
			norms[k] = na
			norms[k + 1] = na
			norms[k + 2] = na
			cols[k] = ca
			cols[k + 1] = ca
			cols[k + 2] = ca
			# Triangle B (11, 01, 10)
			var nb := Vector3(h01 - h11, cs, h10 - h11).normalized()
			var cb := face_color((h11 + h01 + h10) / 3.0, nb.y, row + V + 1, dirt, _hash01(i, j, 1))
			verts[k + 3] = p11
			verts[k + 4] = p01
			verts[k + 5] = p10
			norms[k + 3] = nb
			norms[k + 4] = nb
			norms[k + 5] = nb
			cols[k + 3] = cb
			cols[k + 4] = cb
			cols[k + 5] = cb
			k += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


func _build_lod1(i0: int, j0: int) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var cs := HeightMap.CELL_SIZE
	var steps := 8  # CHUNK_CELLS / LOD1_STEP
	var step_m := cs * LOD1_STEP
	for sj in steps:
		for si in steps:
			var i := i0 + si * LOD1_STEP
			var j := j0 + sj * LOD1_STEP
			var h00 := hm.get_vertex_height(i, j)
			var h10 := hm.get_vertex_height(i + LOD1_STEP, j)
			var h01 := hm.get_vertex_height(i, j + LOD1_STEP)
			var h11 := hm.get_vertex_height(i + LOD1_STEP, j + LOD1_STEP)
			var x0 := si * step_m
			var z0 := sj * step_m
			var p00 := Vector3(x0, h00, z0)
			var p10 := Vector3(x0 + step_m, h10, z0)
			var p01 := Vector3(x0, h01, z0 + step_m)
			var p11 := Vector3(x0 + step_m, h11, z0 + step_m)
			var mid := (j + 2) * HeightMap.VERTS + i + 2
			var dirt := hm.surface[mid] != 0
			var na := Vector3(-(h10 - h00), step_m, -(h01 - h00)).normalized()
			var nb := Vector3(h01 - h11, step_m, h10 - h11).normalized()
			mb.add_tri(p00, p10, p01, face_color((h00 + h10 + h01) / 3.0, na.y, mid, dirt, _hash01(i, j, 2)))
			mb.add_tri(p11, p01, p10, face_color((h11 + h01 + h10) / 3.0, nb.y, mid, dirt, _hash01(i, j, 3)))
	# Skirts hide cracks between neighbouring chunks at different LODs.
	var size := CHUNK_CELLS * cs
	for s in steps:
		var a := s * step_m
		var b := (s + 1) * step_m
		_skirt(mb, Vector3(a, hm.get_vertex_height(i0 + s * LOD1_STEP, j0), 0), Vector3(b, hm.get_vertex_height(i0 + (s + 1) * LOD1_STEP, j0), 0), Vector3.FORWARD)
		_skirt(mb, Vector3(a, hm.get_vertex_height(i0 + s * LOD1_STEP, j0 + CHUNK_CELLS), size), Vector3(b, hm.get_vertex_height(i0 + (s + 1) * LOD1_STEP, j0 + CHUNK_CELLS), size), Vector3.BACK)
		_skirt(mb, Vector3(0, hm.get_vertex_height(i0, j0 + s * LOD1_STEP), a), Vector3(0, hm.get_vertex_height(i0, j0 + (s + 1) * LOD1_STEP), b), Vector3.LEFT)
		_skirt(mb, Vector3(size, hm.get_vertex_height(i0 + CHUNK_CELLS, j0 + s * LOD1_STEP), a), Vector3(size, hm.get_vertex_height(i0 + CHUNK_CELLS, j0 + (s + 1) * LOD1_STEP), b), Vector3.RIGHT)
	return mb.commit(material)


func _skirt(mb: MeshBuilder, a: Vector3, b: Vector3, outward: Vector3) -> void:
	var c := C_ROCK_DARK if a.y > HeightMap.WATER_LEVEL else C_SAND_WET
	mb.add_quad(a, b, b - Vector3(0, SKIRT_DEPTH, 0), a - Vector3(0, SKIRT_DEPTH, 0), c, outward)


func apply_view_distance(view_scale: float) -> void:
	for mi in lod0:
		mi.visibility_range_end = LOD0_RANGE * view_scale
	for mi in lod1:
		if mi.visibility_range_begin > 0.0:
			mi.visibility_range_begin = LOD0_RANGE * view_scale


## One HeightMapShape3D for the whole map. The shape has 1 unit between samples,
## so the node is scaled uniformly by CELL_SIZE and heights are divided by it.
func build_collision(parent: Node3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.set_meta("surface", "ground")
	var shape := HeightMapShape3D.new()
	shape.map_width = HeightMap.VERTS
	shape.map_depth = HeightMap.VERTS
	var data := hm.heights.duplicate()
	var inv := 1.0 / HeightMap.CELL_SIZE
	for idx in data.size():
		data[idx] *= inv
	shape.map_data = data
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3.ONE * HeightMap.CELL_SIZE
	body.add_child(cs)
	parent.add_child(body)
	return body


## Coarse occluder mesh sunk below the real terrain (never hides visible objects).
func build_occluder(parent: Node3D) -> void:
	var step := 8
	var n := 65  # HeightMap.CELLS / step + 1
	var verts := PackedVector3Array()
	verts.resize(n * n)
	for gj in n:
		for gi in n:
			var lo := 1.0e9
			for dj in range(-step, step + 1, 2):
				for di in range(-step, step + 1, 2):
					lo = minf(lo, hm.get_vertex_height(gi * step + di, gj * step + dj))
			var p := HeightMap.vertex_world(gi * step, gj * step)
			verts[gj * n + gi] = Vector3(p.x, lo - 1.5, p.y)
	var idx := PackedInt32Array()
	for gj in n - 1:
		for gi in n - 1:
			var a := gj * n + gi
			idx.append_array([a, a + 1, a + n, a + n + 1, a + n, a + 1])
	var occ := ArrayOccluder3D.new()
	occ.set_arrays(verts, idx)
	var oi := OccluderInstance3D.new()
	oi.name = "TerrainOccluder"
	oi.occluder = occ
	parent.add_child(oi)
