class_name HeightMap
extends RefCounted
## Island heightmap: procedural generation (noise, mountains, river, lakes,
## flattened building pads) and exact height queries.
##
## The grid is VERTS x VERTS samples, CELL_SIZE meters apart, centered on the
## world origin. get_height() interpolates with the SAME triangle split as
## Jolt's HeightMapShape3D (diagonal from (1,0) to (0,1)), so gameplay queries,
## the visible mesh and the physics collider agree exactly.

const CELLS := 512
const VERTS := CELLS + 1
const CELL_SIZE := 4.0
const SIZE := CELLS * CELL_SIZE            # 2048 m (~2 x 2 km)
const HALF := SIZE * 0.5
const WATER_LEVEL := 0.0
const SEA_FLOOR := -14.0

## Surface tags stored per vertex (used for coloring / vegetation).
const SURFACE_NATURAL := 0
const SURFACE_DIRT := 1

var heights := PackedFloat32Array()
## Distance (m) from each vertex to the nearest river/lake edge (<= 0 inside water).
var shore_dist := PackedFloat32Array()
var surface := PackedByteArray()

var map_seed := 0
var river_points := PackedVector2Array()
var river_widths := PackedFloat32Array()
## Array of { center: Vector2, radius: float, height: float }
var mountains: Array[Dictionary] = []
## Array of { center: Vector2, radius: float }
var lakes: Array[Dictionary] = []

var n_base := FastNoiseLite.new()
var n_detail := FastNoiseLite.new()
var n_flat := FastNoiseLite.new()
var n_ridge := FastNoiseLite.new()
var n_coast := FastNoiseLite.new()
var n_meander := FastNoiseLite.new()
## Shared by terrain coloring and vegetation (forest density).
var n_forest := FastNoiseLite.new()
var n_color := FastNoiseLite.new()


static func index(i: int, j: int) -> int:
	return j * VERTS + i


static func vertex_world(i: int, j: int) -> Vector2:
	return Vector2(-HALF + i * CELL_SIZE, -HALF + j * CELL_SIZE)


func get_vertex_height(i: int, j: int) -> float:
	return heights[clampi(j, 0, CELLS) * VERTS + clampi(i, 0, CELLS)]


# --------------------------------------------------------------------------
# Generation
# --------------------------------------------------------------------------

func generate(p_seed: int) -> void:
	map_seed = p_seed
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	_setup_noises(p_seed)
	_plan_river(rng)
	_plan_mountains(rng)
	_plan_lakes(rng)

	heights.resize(VERTS * VERTS)
	shore_dist.resize(VERTS * VERTS)
	shore_dist.fill(1.0e6)
	surface.resize(VERTS * VERTS)
	surface.fill(SURFACE_NATURAL)

	for j in VERTS:
		var z := -HALF + j * CELL_SIZE
		var row := j * VERTS
		for i in VERTS:
			heights[row + i] = _base_height(-HALF + i * CELL_SIZE, z)

	_carve_river()
	_carve_lakes()


func _setup_noises(p_seed: int) -> void:
	var list: Array[FastNoiseLite] = [n_base, n_detail, n_flat, n_ridge, n_coast, n_meander, n_forest, n_color]
	for k in list.size():
		var n := list[k]
		n.seed = p_seed * 31 + k * 1013
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 3
		n.fractal_gain = 0.5
	n_base.frequency = 0.0016
	n_base.fractal_octaves = 4
	n_detail.frequency = 0.02
	n_detail.fractal_octaves = 2
	n_flat.frequency = 0.0012
	n_flat.fractal_octaves = 2
	n_ridge.frequency = 0.0055
	n_ridge.fractal_octaves = 4
	n_coast.frequency = 0.004
	n_meander.frequency = 0.9
	n_meander.fractal_octaves = 2
	n_forest.frequency = 0.0032
	n_color.frequency = 0.035
	n_color.fractal_octaves = 1


## Rolling island terrain + mountain massifs, before river/lake carving.
func _base_height(x: float, z: float) -> float:
	# Rounded-square island mask (superellipse) with a noisy coastline.
	var nx := absf(x / HALF)
	var nz := absf(z / HALF)
	var d := pow(nx * nx * nx * nx + nz * nz * nz * nz, 0.25)
	d += n_coast.get_noise_2d(x, z) * 0.07
	var land := 1.0 - smoothstep(0.8, 0.96, d)

	var b := n_base.get_noise_2d(x, z) * 0.5 + 0.5
	var h := 5.0 + b * 24.0
	h += n_detail.get_noise_2d(x, z) * 1.8

	# Meadows: large flatter areas (good for open fights and towns).
	var flat := smoothstep(0.0, 0.4, n_flat.get_noise_2d(x, z))
	h = lerpf(h, 6.0 + b * 7.0, flat * 0.8)

	# Mountains: ridged noise inside hand-placed massifs.
	var m := 0.0
	for mt in mountains:
		var c: Vector2 = mt.center
		var dd := Vector2(x, z).distance_to(c) / float(mt.radius)
		dd += n_detail.get_noise_2d(x * 0.3, z * 0.3) * 0.12
		if dd < 1.0:
			var fall := 1.0 - smoothstep(0.0, 1.0, dd)
			var ridge := 1.0 - absf(n_ridge.get_noise_2d(x, z))
			ridge *= ridge
			m = maxf(m, fall * (0.4 + 0.6 * ridge) * float(mt.height) * (0.6 + 0.4 * fall))
	h += m

	return lerpf(SEA_FLOOR, h, land)


## The river crosses the whole island between two coasts and meanders.
func _plan_river(rng: RandomNumberGenerator) -> void:
	river_points.clear()
	river_widths.clear()
	var angle := rng.randf_range(0.0, PI)
	var dir := Vector2(cos(angle), sin(angle))
	var perp := Vector2(-dir.y, dir.x)
	var offset := rng.randf_range(-250.0, 250.0)
	var start := -dir * 1250.0 + perp * offset
	var finish := dir * 1250.0 + perp * (offset + rng.randf_range(-200.0, 200.0))
	var segments := 90
	var phase := rng.randf() * 100.0
	for k in segments + 1:
		var t := float(k) / segments
		var p := start.lerp(finish, t)
		# Meander: two noise layers, stronger in the middle of the island.
		var env := sin(t * PI) * 0.7 + 0.3
		var off := n_meander.get_noise_1d(phase + t * 3.0) * 260.0 * env
		off += sin(t * TAU * 3.0 + phase) * 35.0 * env
		river_points.append(p + perp * off)
		river_widths.append(10.0 + (n_meander.get_noise_1d(phase * 2.0 + t * 7.0) * 0.5 + 0.5) * 12.0)


func distance_to_river(p: Vector2) -> float:
	var best := 1.0e9
	for k in river_points.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p, river_points[k], river_points[k + 1])
		best = minf(best, q.distance_to(p))
	return best


func _is_inside_island(p: Vector2, margin: float) -> bool:
	var lim := HALF * 0.78 - margin
	return absf(p.x) < lim and absf(p.y) < lim


func _plan_mountains(rng: RandomNumberGenerator) -> void:
	mountains.clear()
	var wanted := rng.randi_range(2, 3)
	for attempt in 200:
		if mountains.size() >= wanted:
			break
		var r := rng.randf_range(200.0, 320.0)
		var c := Vector2(rng.randf_range(-650.0, 650.0), rng.randf_range(-650.0, 650.0))
		if not _is_inside_island(c, r * 0.35):
			continue
		if distance_to_river(c) < r + 70.0:
			continue
		var ok := true
		for mt in mountains:
			if c.distance_to(mt.center) < (r + float(mt.radius)) * 0.9:
				ok = false
				break
		if ok:
			mountains.append({"center": c, "radius": r, "height": rng.randf_range(75.0, 130.0)})


func _plan_lakes(rng: RandomNumberGenerator) -> void:
	lakes.clear()
	var wanted := rng.randi_range(1, 2)
	for attempt in 200:
		if lakes.size() >= wanted:
			break
		var r := rng.randf_range(55.0, 105.0)
		var c := Vector2(rng.randf_range(-600.0, 600.0), rng.randf_range(-600.0, 600.0))
		if not _is_inside_island(c, r + 60.0):
			continue
		if distance_to_river(c) < r + 90.0:
			continue
		var ok := true
		for mt in mountains:
			if c.distance_to(mt.center) < float(mt.radius) * 0.85 + r:
				ok = false
				break
		for lk in lakes:
			if c.distance_to(lk.center) < float(lk.radius) + r + 150.0:
				ok = false
				break
		if ok:
			lakes.append({"center": c, "radius": r})


## Bed profile: parabolic below water inside, smooth bank blending outside.
## `q` = signed distance from the water edge (m, negative = inside water),
## `w` = half width of the water body.
static func _carve_profile(orig: float, q: float, w: float, depth: float) -> float:
	if q < 0.0:
		var t := clampf(1.0 + q / w, 0.0, 1.0)   # 0 at center, 1 at the edge
		return WATER_LEVEL - 0.25 - depth * (1.0 - t * t)
	# Bank width grows with terrain height so high ground forms a valley, not a wall.
	var bank := clampf(18.0 + orig * 1.1, 18.0, 70.0)
	if q >= bank:
		return orig
	var s := smoothstep(0.0, 1.0, q / bank)
	return lerpf(WATER_LEVEL - 0.25, orig, s)


func _carve_river() -> void:
	# Pass 1: signed distance to the river edge, only near each segment.
	var river_w := PackedFloat32Array()
	river_w.resize(VERTS * VERTS)
	for k in river_points.size() - 1:
		var a := river_points[k]
		var b := river_points[k + 1]
		var w := maxf(river_widths[k], river_widths[k + 1])
		var reach := w + 72.0
		var i0 := clampi(int((minf(a.x, b.x) - reach + HALF) / CELL_SIZE), 0, CELLS)
		var i1 := clampi(int((maxf(a.x, b.x) + reach + HALF) / CELL_SIZE) + 1, 0, CELLS)
		var j0 := clampi(int((minf(a.y, b.y) - reach + HALF) / CELL_SIZE), 0, CELLS)
		var j1 := clampi(int((maxf(a.y, b.y) + reach + HALF) / CELL_SIZE) + 1, 0, CELLS)
		for j in range(j0, j1 + 1):
			var z := -HALF + j * CELL_SIZE
			for i in range(i0, i1 + 1):
				var p := Vector2(-HALF + i * CELL_SIZE, z)
				var q := Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) - w
				var idx := j * VERTS + i
				if q < shore_dist[idx]:
					shore_dist[idx] = q
					river_w[idx] = w
	# Pass 2: carve.
	for idx in heights.size():
		var q := shore_dist[idx]
		if q < 72.0:
			heights[idx] = minf(heights[idx], _carve_profile(heights[idx], q, river_w[idx], 3.4))


func _carve_lakes() -> void:
	for lk in lakes:
		var c: Vector2 = lk.center
		var r: float = lk.radius
		var reach := r * 1.25 + 72.0
		var i0 := clampi(int((c.x - reach + HALF) / CELL_SIZE), 0, CELLS)
		var i1 := clampi(int((c.x + reach + HALF) / CELL_SIZE) + 1, 0, CELLS)
		var j0 := clampi(int((c.y - reach + HALF) / CELL_SIZE), 0, CELLS)
		var j1 := clampi(int((c.y + reach + HALF) / CELL_SIZE) + 1, 0, CELLS)
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				var p := Vector2(-HALF + i * CELL_SIZE, -HALF + j * CELL_SIZE)
				var to := p - c
				# Wobbly outline so lakes are not perfect circles.
				var ang := atan2(to.y, to.x)
				var r_eff := r * (1.0 + 0.18 * sin(ang * 3.0 + r) + 0.1 * sin(ang * 5.0 + c.x))
				var q := to.length() - r_eff
				var idx := j * VERTS + i
				shore_dist[idx] = minf(shore_dist[idx], q)
				if q < 72.0:
					heights[idx] = minf(heights[idx], _carve_profile(heights[idx], q, r_eff, 4.5))


## Flattens a rotated rectangle (building pad) to `height`, blending over `falloff` m.
func flatten_rect(center: Vector2, half_size: Vector2, angle: float, height: float, falloff: float, dirt_half := Vector2.ZERO) -> void:
	var reach := half_size.length() + falloff
	var i0 := clampi(int((center.x - reach + HALF) / CELL_SIZE), 0, CELLS)
	var i1 := clampi(int((center.x + reach + HALF) / CELL_SIZE) + 1, 0, CELLS)
	var j0 := clampi(int((center.y - reach + HALF) / CELL_SIZE), 0, CELLS)
	var j1 := clampi(int((center.y + reach + HALF) / CELL_SIZE) + 1, 0, CELLS)
	var ca := cos(-angle)
	var sa := sin(-angle)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var p := Vector2(-HALF + i * CELL_SIZE, -HALF + j * CELL_SIZE) - center
			var lx := p.x * ca - p.y * sa
			var lz := p.x * sa + p.y * ca
			var dx := maxf(absf(lx) - half_size.x, 0.0)
			var dz := maxf(absf(lz) - half_size.y, 0.0)
			var d := sqrt(dx * dx + dz * dz)
			var idx := j * VERTS + i
			if d <= 0.0:
				heights[idx] = height
			elif d < falloff:
				heights[idx] = lerpf(height, heights[idx], smoothstep(0.0, 1.0, d / falloff))
			# Dirt "yard" around the building (coloring only).
			if absf(lx) < dirt_half.x and absf(lz) < dirt_half.y:
				surface[idx] = SURFACE_DIRT


# --------------------------------------------------------------------------
# Queries
# --------------------------------------------------------------------------

## Exact terrain height (matches the physics collider).
func get_height(x: float, z: float) -> float:
	var fx := clampf((x + HALF) / CELL_SIZE, 0.0, CELLS - 0.0001)
	var fz := clampf((z + HALF) / CELL_SIZE, 0.0, CELLS - 0.0001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var row := j * VERTS + i
	var h00 := heights[row]
	var h10 := heights[row + 1]
	var h01 := heights[row + VERTS]
	var h11 := heights[row + VERTS + 1]
	if tx + tz <= 1.0:
		return h00 + (h10 - h00) * tx + (h01 - h00) * tz
	return h11 + (h01 - h11) * (1.0 - tx) + (h10 - h11) * (1.0 - tz)


## Face normal of the terrain triangle under (x, z).
func get_normal(x: float, z: float) -> Vector3:
	var fx := clampf((x + HALF) / CELL_SIZE, 0.0, CELLS - 0.0001)
	var fz := clampf((z + HALF) / CELL_SIZE, 0.0, CELLS - 0.0001)
	var i := int(fx)
	var j := int(fz)
	var row := j * VERTS + i
	var h00 := heights[row]
	var h10 := heights[row + 1]
	var h01 := heights[row + VERTS]
	var h11 := heights[row + VERTS + 1]
	var gx: float
	var gz: float
	if (fx - i) + (fz - j) <= 1.0:
		gx = (h10 - h00) / CELL_SIZE
		gz = (h01 - h00) / CELL_SIZE
	else:
		gx = (h11 - h01) / CELL_SIZE
		gz = (h11 - h10) / CELL_SIZE
	return Vector3(-gx, 1.0, -gz).normalized()


func get_shore_distance(x: float, z: float) -> float:
	var i := clampi(roundi((x + HALF) / CELL_SIZE), 0, CELLS)
	var j := clampi(roundi((z + HALF) / CELL_SIZE), 0, CELLS)
	return shore_dist[j * VERTS + i]


func is_water(x: float, z: float, min_depth := 0.0) -> bool:
	return get_height(x, z) < WATER_LEVEL - min_depth


## Max - min height of the terrain sampled over a square of half-size `r`.
func height_range(x: float, z: float, r: float) -> float:
	var lo := 1.0e9
	var hi := -1.0e9
	var steps := 3
	for a in range(-steps, steps + 1):
		for b in range(-steps, steps + 1):
			var h := get_height(x + r * a / steps, z + r * b / steps)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return hi - lo


func in_bounds(x: float, z: float, margin := 0.0) -> bool:
	return absf(x) < HALF - margin and absf(z) < HALF - margin
