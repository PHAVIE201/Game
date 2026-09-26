class_name GameWorld
extends Node3D
## The island: generates terrain, towns, vegetation and water, and answers
## world queries (height, water, spawn points) for gameplay code.
##
## Generation is a coroutine (`await world.generate(seed)`) that yields between
## steps so the loading screen stays responsive.

signal generation_finished

@export var sun_path: NodePath
@export var environment_path: NodePath

var hm: HeightMap
var terrain: TerrainBuilder
var settlements: Settlements
var vegetation: Vegetation
var is_ready := false
var generation_time_ms := 0
## Milliseconds spent in each generation step (printed + shown with F3).
var generation_steps: Dictionary = {}

var _sun: DirectionalLight3D
var _env: WorldEnvironment
var _building_material: StandardMaterial3D
var _terrain_root: Node3D
var _buildings_root: Node3D


func _ready() -> void:
	_sun = get_node_or_null(sun_path) as DirectionalLight3D
	_env = get_node_or_null(environment_path) as WorldEnvironment
	Settings.changed.connect(apply_graphics)
	apply_graphics()


# --------------------------------------------------------------------------
# Generation
# --------------------------------------------------------------------------

func generate(map_seed: int) -> void:
	var t0 := Time.get_ticks_msec()
	var view_scale := Settings.get_view_distance_scale()

	await _step("Đang tạo địa hình...", 0.02)
	hm = HeightMap.new()
	hm.generate(map_seed)

	await _step("Đang quy hoạch làng mạc...", 0.18)
	settlements = Settlements.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed + 99
	settlements.plan(hm, rng)

	await _step("Đang tô màu địa hình...", 0.24)
	terrain = TerrainBuilder.new(hm)
	terrain.prepare()

	_terrain_root = Node3D.new()
	_terrain_root.name = "Terrain"
	add_child(_terrain_root)
	var total := TerrainBuilder.CHUNKS * TerrainBuilder.CHUNKS
	for c in total:
		terrain.build_chunk(_terrain_root, c % TerrainBuilder.CHUNKS, c / TerrainBuilder.CHUNKS, view_scale)
		if c % 32 == 31:
			await _step("Đang dựng địa hình...", 0.3 + 0.3 * float(c) / total)
	terrain.build_collision(_terrain_root)
	terrain.build_occluder(_terrain_root)
	_build_boundaries()

	await _step("Đang xây nhà...", 0.62)
	_building_material = MeshBuilder.make_vertex_color_material(0.85)
	_buildings_root = Node3D.new()
	_buildings_root.name = "Buildings"
	add_child(_buildings_root)
	settlements.build(_buildings_root, _building_material)

	await _step("Đang trồng cây...", 0.7)
	vegetation = Vegetation.new()
	add_child(vegetation)
	var tv := Time.get_ticks_msec()
	vegetation.place(hm, terrain, settlements, map_seed)
	vegetation.prepare_meshes()
	generation_steps["vegetation_place"] = Time.get_ticks_msec() - tv
	var cells := vegetation.cell_count()
	var batch := 32
	for c in range(0, cells, batch):
		vegetation.build_cells(c, c + batch, view_scale)
		await _step("Đang trồng cây...", 0.72 + 0.22 * float(c) / cells)

	await _step("Đang đổ nước...", 0.96)
	_build_water()
	await _step("", 1.0)

	generation_time_ms = Time.get_ticks_msec() - t0
	print("[World] seed=%d generated in %d ms: %d towns, %d buildings, %d trees, %d bushes, %d rocks" % [
		map_seed, generation_time_ms, settlements.towns.size(), settlements.buildings.size(),
		vegetation.tree_count, vegetation.bush_count, vegetation.rock_count])
	print("[World] step times (ms): ", generation_steps)
	is_ready = true
	Events.world_generation_progress.emit("Hoàn tất", 1.0)
	generation_finished.emit()


func _step(text: String, progress: float) -> void:
	var now := Time.get_ticks_msec()
	if _last_step_name != "":
		generation_steps[_last_step_name] = int(generation_steps.get(_last_step_name, 0)) + now - _last_step_time
	_last_step_name = text
	Events.world_generation_progress.emit(text, progress)
	await get_tree().process_frame
	_last_step_time = Time.get_ticks_msec()


var _last_step_name := ""
var _last_step_time := 0


func _build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(6000.0, 6000.0)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	plane.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = plane
	mi.position.y = HeightMap.WATER_LEVEL
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Invisible walls just inside the map edge (only characters collide with them).
func _build_boundaries() -> void:
	var body := StaticBody3D.new()
	body.name = "MapBoundary"
	body.collision_layer = Layers.BOUNDARY
	body.collision_mask = 0
	var lim := HeightMap.HALF - 30.0
	var normals: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]
	for n in normals:
		var shape := WorldBoundaryShape3D.new()
		shape.plane = Plane(n, -lim)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
	add_child(body)


# --------------------------------------------------------------------------
# Graphics settings
# --------------------------------------------------------------------------

func apply_graphics() -> void:
	var view_scale := Settings.get_view_distance_scale()
	if _sun != null:
		_sun.shadow_enabled = true
		_sun.directional_shadow_mode = Settings.get_shadow_mode()
		_sun.directional_shadow_max_distance = Settings.get_shadow_distance()
	if _env != null and _env.environment != null:
		_env.environment.ssao_enabled = Settings.use_ssao()
	if terrain != null:
		terrain.apply_view_distance(view_scale)
	if vegetation != null:
		vegetation.apply_view_distance(view_scale)


# --------------------------------------------------------------------------
# Queries
# --------------------------------------------------------------------------

func get_height(x: float, z: float) -> float:
	return hm.get_height(x, z)


func get_normal(x: float, z: float) -> Vector3:
	return hm.get_normal(x, z)


func get_water_level() -> float:
	return HeightMap.WATER_LEVEL


## Water depth at (x, z) (0 on dry land).
func get_water_depth(x: float, z: float) -> float:
	return maxf(HeightMap.WATER_LEVEL - hm.get_height(x, z), 0.0)


func is_water(x: float, z: float, min_depth := 0.3) -> bool:
	return hm.is_water(x, z, min_depth)


func is_walkable(x: float, z: float) -> bool:
	if not hm.in_bounds(x, z, 50.0):
		return false
	if hm.get_height(x, z) < HeightMap.WATER_LEVEL + 0.5:
		return false
	return hm.get_normal(x, z).y > 0.8


func get_loot_points() -> PackedVector3Array:
	return settlements.loot_points


func get_towns() -> Array[Dictionary]:
	return settlements.towns


## Random walkable point in a ring around `center`.
func find_spawn_point(rng: RandomNumberGenerator, center: Vector3, min_r: float, max_r: float, tries := 60) -> Vector3:
	for t in tries:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(min_r, max_r)
		var x := center.x + cos(ang) * r
		var z := center.z + sin(ang) * r
		if not is_walkable(x, z):
			continue
		var p := Vector3(x, hm.get_height(x, z), z)
		if settlements.is_inside_building(p, 1.5):
			continue
		return p
	return random_land_point(rng)


func random_land_point(rng: RandomNumberGenerator) -> Vector3:
	for t in 500:
		var x := rng.randf_range(-800.0, 800.0)
		var z := rng.randf_range(-800.0, 800.0)
		if is_walkable(x, z):
			var p := Vector3(x, hm.get_height(x, z), z)
			if not settlements.is_inside_building(p, 1.5):
				return p
	return Vector3(0, hm.get_height(0, 0) + 2.0, 0)


## Top-down colored map (north = up). Used for debugging now and for the
## in-game map / minimap in later phases.
func make_map_image(res := 512) -> Image:
	var img := Image.create(res, res, false, Image.FORMAT_RGB8)
	var px_size := HeightMap.SIZE / res
	for py in res:
		for px in res:
			var x := -HeightMap.HALF + (px + 0.5) * px_size
			var z := -HeightMap.HALF + (py + 0.5) * px_size
			var h := hm.get_height(x, z)
			var col: Color
			if h < HeightMap.WATER_LEVEL:
				col = Color(0.3, 0.72, 0.8).lerp(Color(0.1, 0.35, 0.6), clampf(-h / 8.0, 0.0, 1.0))
			else:
				var i := clampi(roundi((x + HeightMap.HALF) / HeightMap.CELL_SIZE), 0, HeightMap.CELLS)
				var j := clampi(roundi((z + HeightMap.HALF) / HeightMap.CELL_SIZE), 0, HeightMap.CELLS)
				var vidx := j * HeightMap.VERTS + i
				col = terrain.face_color(h, hm.get_normal(x, z).y, vidx, hm.surface[vidx] != 0, 0.0)
				# Hill shading for readability.
				var n := hm.get_normal(x, z)
				col = col.darkened(clampf((n.x + n.z) * 0.8, -0.3, 0.3))
			img.set_pixel(px, py, col)
	for b in settlements.buildings:
		var c: Vector2 = b.center
		var px := int((c.x + HeightMap.HALF) / px_size)
		var py := int((c.y + HeightMap.HALF) / px_size)
		var r := maxi(1, int((b.size as Vector2).x * 0.5 / px_size))
		img.fill_rect(Rect2i(px - r, py - r, r * 2, r * 2), (b.roof_color as Color))
	return img
