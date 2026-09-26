class_name AirPlane
extends Node3D
## The transport plane: flies a straight line across the island at the start of
## a match with every participant on board. Doors open above the island;
## whoever is still aboard when it leaves the island is thrown out.

signal route_finished

const ALTITUDE := 480.0
const SPEED := 65.0
## Distance from the island center where the route starts / ends.
const ROUTE_HALF := 1300.0
## Doors are open while the plane is this far inside the map edge.
const DOOR_MARGIN := 170.0

var start := Vector3.ZERO
var end := Vector3.ZERO
var dir := Vector3.FORWARD
var length := 0.0
## Meters flown along the route.
var progress := 0.0
var doors_open := false
var passengers: Array[GameCharacter] = []

var _props: Array[Node3D] = []
var _was_open := false
var _engine: AudioStreamPlayer3D


func setup(rng: RandomNumberGenerator) -> void:
	var angle := rng.randf() * TAU
	dir = Vector3(cos(angle), 0.0, sin(angle))
	var side := Vector3(-dir.z, 0.0, dir.x)
	var offset := rng.randf_range(-420.0, 420.0)
	start = side * offset - dir * ROUTE_HALF + Vector3(0, ALTITUDE, 0)
	end = side * offset + dir * ROUTE_HALF + Vector3(0, ALTITUDE, 0)
	length = start.distance_to(end)
	progress = 0.0
	global_position = start
	look_at(end, Vector3.UP)
	_build_mesh()


## Point on the route (ground plane) at `meters` from the start.
func point_at(meters: float) -> Vector3:
	return start + dir * meters


## Closest route distance (meters from the start) to a ground point.
func project(p: Vector3) -> float:
	return clampf((p - start).dot(dir), 0.0, length)


## Horizontal distance from a point to the flight line.
func lateral_distance(p: Vector3) -> float:
	var q := point_at(project(p))
	return Vector2(p.x - q.x, p.z - q.z).length()


## Route distances between which the doors are open.
func door_range() -> Vector2:
	var lim := HeightMap.HALF - DOOR_MARGIN
	var a := INF
	var b := -INF
	var m := 0.0
	while m <= length:
		var p := point_at(m)
		if absf(p.x) < lim and absf(p.z) < lim:
			a = minf(a, m)
			b = maxf(b, m)
		m += 20.0
	return Vector2(a, b)


func get_velocity() -> Vector3:
	return dir * SPEED


func board(c: GameCharacter) -> void:
	passengers.append(c)


func leave(c: GameCharacter) -> void:
	passengers.erase(c)


func is_active() -> bool:
	return progress < length


func _physics_process(delta: float) -> void:
	if not is_active():
		return
	progress = minf(progress + SPEED * delta, length)
	global_position = point_at(progress)
	var lim := HeightMap.HALF - DOOR_MARGIN
	var over := absf(global_position.x) < lim and absf(global_position.z) < lim
	doors_open = over
	if over and not _was_open:
		_was_open = true
		Events.plane_doors_changed.emit(true)
	elif not over and _was_open:
		# Leaving the island: everybody out.
		_was_open = false
		doors_open = false
		Events.plane_doors_changed.emit(false)
		for c in passengers.duplicate():
			c.jump_from_plane()
	if progress >= length:
		for c in passengers.duplicate():
			c.jump_from_plane()
		visible = false
		if _engine != null:
			_engine.stop()
		route_finished.emit()


func _process(delta: float) -> void:
	for p in _props:
		p.rotate_object_local(Vector3.FORWARD, delta * 40.0)


# --------------------------------------------------------------------------
# Low-poly model (forward = -Z): fuselage, high wing, 4 engines, tail.
# --------------------------------------------------------------------------

func _build_mesh() -> void:
	var mb := MeshBuilder.new()
	var body := Color(0.9, 0.9, 0.88)
	var stripe := Color(0.95, 0.5, 0.15)
	var dark := Color(0.25, 0.27, 0.3)
	# Fuselage + nose + tail cone
	mb.add_box(Vector3(0, 0, 0), Vector3(4.2, 4.2, 22.0), body)
	mb.add_box(Vector3(0, -0.4, 0), Vector3(4.25, 0.6, 22.05), stripe)
	mb.add_box(Vector3(0, -0.3, -12.5), Vector3(3.6, 3.4, 3.0), body)
	mb.add_box(Vector3(0, 0.3, -13.6), Vector3(2.6, 1.0, 1.2), Color(0.3, 0.5, 0.65))
	mb.add_box(Vector3(0, 0.6, 13.5), Vector3(2.8, 2.8, 6.0), body)
	# Cargo ramp (open at the back)
	mb.add_box(Vector3(0, -1.9, 12.0), Vector3(3.6, 0.3, 4.0), dark, Basis(Vector3.RIGHT, -0.35))
	# Wing
	mb.add_box(Vector3(0, 2.3, -2.0), Vector3(36.0, 0.5, 4.2), body)
	mb.add_box(Vector3(0, 2.56, -2.0), Vector3(36.0, 0.05, 0.8), stripe)
	# Tail
	mb.add_box(Vector3(0, 4.2, 15.5), Vector3(0.5, 6.0, 3.2), body)
	mb.add_box(Vector3(0, 1.8, 16.0), Vector3(13.0, 0.4, 2.8), body)
	mb.add_box(Vector3(0, 6.6, 15.8), Vector3(0.55, 1.2, 2.6), stripe)
	# Engines
	var engines := [-12.0, -6.0, 6.0, 12.0]
	for x in engines:
		mb.add_box(Vector3(x, 1.5, -4.2), Vector3(1.4, 1.4, 4.0), dark)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit(MeshBuilder.make_vertex_color_material(0.6))
	add_child(mi)
	# Propellers (spinning)
	var prop_mb := MeshBuilder.new()
	for k in 3:
		var a := k * TAU / 3.0
		prop_mb.add_box(Vector3(cos(a), sin(a), 0) * 1.1, Vector3(0.35, 2.2, 0.08), Color(0.15, 0.15, 0.15), Basis(Vector3.BACK, a + PI * 0.5))
	var prop_mesh := prop_mb.commit(MeshBuilder.make_vertex_color_material(0.6))
	for x in engines:
		var pivot := Node3D.new()
		pivot.position = Vector3(x, 1.5, -6.3)
		add_child(pivot)
		var pm := MeshInstance3D.new()
		pm.mesh = prop_mesh
		pivot.add_child(pm)
		_props.append(pivot)
	_engine = AudioStreamPlayer3D.new()
	_engine.stream = Sfx.get_loop(&"plane_engine")
	_engine.unit_size = 60.0
	_engine.max_distance = 2500.0
	_engine.volume_db = 2.0
	add_child(_engine)
	_engine.play()
