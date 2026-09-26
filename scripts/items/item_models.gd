class_name ItemModels
## Low-poly meshes for items lying on the ground (built once, shared).
## Weapons reuse the WeaponModels mesh, laid on their side.

static var _cache: Dictionary = {}
static var _material: StandardMaterial3D


static func get_mesh(id: StringName) -> ArrayMesh:
	if _cache.has(id):
		return _cache[id]
	var mesh := _build(id)
	_cache[id] = mesh
	return mesh


## Transform (relative to the pickup position on the floor) for the mesh.
static func get_ground_transform(id: StringName) -> Transform3D:
	if ItemDB.kind_of(id) == ItemDB.Kind.WEAPON:
		# Gun on its side: its right side (+X) faces up, barrel along -Z.
		return Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, 0.045, 0.15))
	return Transform3D.IDENTITY


static func _mat() -> StandardMaterial3D:
	if _material == null:
		_material = MeshBuilder.make_vertex_color_material(0.6)
	return _material


static func _build(id: StringName) -> ArrayMesh:
	var kind := ItemDB.kind_of(id)
	if kind == ItemDB.Kind.WEAPON:
		var w := WeaponDB.get_weapon(id)
		return WeaponModels.get_model(w.model if w != null else &"rifle").mesh
	var info := ItemDB.get_info(id)
	var col: Color = info.get("color", Color(0.8, 0.8, 0.8))
	var mb := MeshBuilder.new()
	match kind:
		ItemDB.Kind.AMMO:
			_ammo_box(mb, col)
		ItemDB.Kind.BACKPACK:
			_backpack(mb, col, int(info.get("level", 1)))
		_:
			mb.add_box(Vector3(0, 0.1, 0), Vector3(0.2, 0.2, 0.2), col)
	return mb.commit(_mat())


static func _ammo_box(mb: MeshBuilder, col: Color) -> void:
	# Two small boxes of cartridges with a bright band (easy to spot).
	mb.add_box(Vector3(-0.08, 0.07, 0), Vector3(0.14, 0.14, 0.22), col)
	mb.add_box(Vector3(-0.08, 0.07, 0), Vector3(0.145, 0.03, 0.225), Color(0.95, 0.82, 0.3))
	mb.add_box(Vector3(0.09, 0.055, 0.02), Vector3(0.14, 0.11, 0.2), col.darkened(0.15), Basis(Vector3.UP, 0.3))
	mb.add_box(Vector3(0.09, 0.075, 0.02), Vector3(0.145, 0.025, 0.205), Color(0.95, 0.82, 0.3), Basis(Vector3.UP, 0.3))


static func _backpack(mb: MeshBuilder, col: Color, level: int) -> void:
	var h := 0.36 + level * 0.06
	var dark := col.darkened(0.3)
	mb.add_box(Vector3(0, 0.1, 0), Vector3(0.36, 0.2, h), col)            # main bag (lying down)
	mb.add_box(Vector3(0, 0.2, -h * 0.1), Vector3(0.3, 0.06, h * 0.6), dark)   # top pocket
	mb.add_box(Vector3(0, 0.12, h * 0.5 + 0.03), Vector3(0.26, 0.14, 0.06), dark)  # lid
	for side in [-1.0, 1.0]:
		mb.add_box(Vector3(side * 0.1, 0.01, 0), Vector3(0.05, 0.02, h * 0.9), Color(0.15, 0.15, 0.15))   # straps
	# Level stripes.
	for k in level:
		mb.add_box(Vector3(-0.1 + k * 0.1, 0.205, h * 0.3), Vector3(0.05, 0.012, 0.05), Color(1.0, 0.85, 0.3))
