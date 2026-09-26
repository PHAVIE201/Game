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
	if ItemDB.kind_of(id) == ItemDB.Kind.THROWABLE:
		# Lying on its side.
		return Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0, 0.04, 0))
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
		ItemDB.Kind.HELMET:
			mb.add_frustum(Vector3(0, 0.0, 0), 0.19, 0.17, 0.07, 8, col, false, PI / 8.0)
			mb.add_frustum(Vector3(0, 0.07, 0), 0.17, 0.11, 0.06, 8, col, false, PI / 8.0)
			mb.add_frustum(Vector3(0, 0.13, 0), 0.11, 0.0, 0.04, 8, col, false, PI / 8.0)
			mb.add_frustum(Vector3(0, 0.0, 0), 0.2, 0.2, 0.02, 8, col.darkened(0.2), true, PI / 8.0)
		ItemDB.Kind.VEST:
			# Vest lying flat, with pouches.
			mb.add_box(Vector3(0, 0.05, 0), Vector3(0.46, 0.1, 0.5), col)
			mb.add_box(Vector3(0, 0.1, 0.2), Vector3(0.3, 0.02, 0.1), col.darkened(0.25))
			for k in int(info.get("level", 1)) + 1:
				mb.add_box(Vector3(-0.15 + k * 0.1, 0.12, -0.05), Vector3(0.08, 0.05, 0.11), col.darkened(0.3))
		ItemDB.Kind.HEAL:
			_heal(mb, id, col)
		ItemDB.Kind.BOOST:
			_boost(mb, id, col)
		ItemDB.Kind.SCOPE:
			return WeaponModels.get_scope_mesh(id)
		ItemDB.Kind.THROWABLE:
			if id == &"grenade_smoke":
				mb.add_frustum(Vector3(0, -0.06, 0), 0.032, 0.032, 0.12, 8, col)
				mb.add_frustum(Vector3(0, 0.06, 0), 0.02, 0.02, 0.02, 6, Color(0.2, 0.2, 0.2))
			else:
				mb.add_sphere(Vector3.ZERO, Vector3(0.04, 0.05, 0.04), col, 8, 5)
				mb.add_box(Vector3(0, 0.055, 0), Vector3(0.025, 0.02, 0.025), Color(0.2, 0.2, 0.2))
				mb.add_box(Vector3(0.022, 0.035, 0), Vector3(0.01, 0.06, 0.015), Color(0.6, 0.6, 0.6))
		_:
			mb.add_box(Vector3(0, 0.1, 0), Vector3(0.2, 0.2, 0.2), col)
	return mb.commit(_mat())


static func _heal(mb: MeshBuilder, id: StringName, col: Color) -> void:
	var red := Color(0.85, 0.15, 0.15)
	match id:
		&"bandage":
			# A few rolls of bandage.
			for k in 3:
				mb.add_frustum(Vector3(-0.08 + k * 0.08, 0.0, k * 0.03), 0.035, 0.035, 0.07, 8, col)
		&"first_aid":
			mb.add_box(Vector3(0, 0.05, 0), Vector3(0.24, 0.1, 0.17), col)
			mb.add_box(Vector3(0, 0.101, 0), Vector3(0.12, 0.004, 0.035), red)
			mb.add_box(Vector3(0, 0.101, 0), Vector3(0.035, 0.004, 0.12), red)
		_:
			mb.add_box(Vector3(0, 0.08, 0), Vector3(0.36, 0.16, 0.26), col)
			mb.add_box(Vector3(0, 0.161, 0), Vector3(0.16, 0.004, 0.05), Color.WHITE)
			mb.add_box(Vector3(0, 0.161, 0), Vector3(0.05, 0.004, 0.16), Color.WHITE)
			mb.add_box(Vector3(0, 0.17, 0), Vector3(0.14, 0.02, 0.03), Color(0.2, 0.2, 0.2))


static func _boost(mb: MeshBuilder, id: StringName, col: Color) -> void:
	if id == &"energy_drink":
		mb.add_frustum(Vector3.ZERO, 0.035, 0.035, 0.13, 8, col)
		mb.add_frustum(Vector3(0, 0.13, 0), 0.035, 0.028, 0.012, 8, Color(0.8, 0.8, 0.82))
		mb.add_box(Vector3(0, 0.065, -0.034), Vector3(0.03, 0.05, 0.005), Color(1.0, 0.9, 0.2))
	else:
		mb.add_frustum(Vector3.ZERO, 0.04, 0.04, 0.1, 8, col)
		mb.add_frustum(Vector3(0, 0.1, 0), 0.043, 0.043, 0.03, 8, Color.WHITE)


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
