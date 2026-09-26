class_name WeaponModels
## Procedural low-poly gun meshes, built once and shared by every character.
##
## Each model returns a Dictionary:
##   mesh: ArrayMesh, muzzle / grip_r / grip_l / mag / stock: Vector3 (gun space)
## Gun space: forward = -Z, origin = right-hand grip area.

static var _cache: Dictionary = {}
static var _flash_mesh: ArrayMesh


static func get_model(id: StringName) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var model: Dictionary
	match id:
		_:
			model = _build_rifle()
	_cache[id] = model
	return model


## "K7 Kestrel": compact rifle with sand-colored furniture and an orange stripe.
static func _build_rifle() -> Dictionary:
	var mb := MeshBuilder.new()
	var metal := Color(0.2, 0.21, 0.23)
	var dark := Color(0.12, 0.12, 0.13)
	var sand := Color(0.74, 0.63, 0.45)
	var accent := Color(0.95, 0.5, 0.15)
	# Receiver
	mb.add_box(Vector3(0, 0.03, -0.12), Vector3(0.07, 0.11, 0.42), metal)
	mb.add_box(Vector3(0.037, 0.035, -0.08), Vector3(0.006, 0.025, 0.18), accent)
	mb.add_box(Vector3(-0.037, 0.035, -0.08), Vector3(0.006, 0.025, 0.18), accent)
	# Barrel + muzzle brake
	mb.add_box(Vector3(0, 0.05, -0.55), Vector3(0.028, 0.028, 0.42), dark)
	mb.add_box(Vector3(0, 0.05, -0.77), Vector3(0.046, 0.046, 0.07), dark)
	# Handguard
	mb.add_box(Vector3(0, 0.035, -0.42), Vector3(0.08, 0.09, 0.26), sand)
	# Top rail and sights
	mb.add_box(Vector3(0, 0.094, -0.18), Vector3(0.03, 0.016, 0.4), dark)
	mb.add_box(Vector3(0, 0.12, -0.0), Vector3(0.032, 0.04, 0.03), dark)
	mb.add_box(Vector3(0, 0.105, -0.52), Vector3(0.012, 0.05, 0.015), dark)
	# Magazine (tilted forward)
	mb.add_box(Vector3(0, -0.11, -0.2), Vector3(0.05, 0.2, 0.085), dark, Basis(Vector3.RIGHT, -0.25))
	# Pistol grip (tilted back)
	mb.add_box(Vector3(0, -0.07, 0.03), Vector3(0.045, 0.13, 0.06), sand, Basis(Vector3.RIGHT, 0.3))
	# Stock + butt pad
	mb.add_box(Vector3(0, 0.0, 0.22), Vector3(0.05, 0.1, 0.26), sand)
	mb.add_box(Vector3(0, -0.01, 0.36), Vector3(0.06, 0.14, 0.03), dark)
	var mat := MeshBuilder.make_vertex_color_material(0.55)
	return {
		"mesh": mb.commit(mat),
		"muzzle": Vector3(0, 0.05, -0.81),
		"grip_r": Vector3(0, -0.05, 0.03),
		"grip_l": Vector3(0, -0.005, -0.33),
		"mag": Vector3(0, -0.2, -0.22),
		"stock": Vector3(0, 0.0, 0.36),
	}


## Star-shaped muzzle flash (crossed quads, additive, unshaded).
static func get_flash_mesh() -> ArrayMesh:
	if _flash_mesh != null:
		return _flash_mesh
	var mb := MeshBuilder.new()
	var c := Color(1.0, 0.75, 0.3)
	for k in 3:
		var a := k * PI / 3.0
		var side := Vector3(cos(a), sin(a), 0.0) * 0.09
		# Quad along -Z (forward), double-sided via the material.
		mb.add_quad(-side, side, side + Vector3(0, 0, -0.28), -side + Vector3(0, 0, -0.28), c, Vector3(-sin(a), cos(a), 0.0))
	# Front disc
	for k in 6:
		var a0 := k * TAU / 6.0
		var a1 := (k + 1) * TAU / 6.0
		mb.add_tri(Vector3.ZERO, Vector3(cos(a0), sin(a0), 0) * 0.07, Vector3(cos(a1), sin(a1), 0) * 0.07, c, Vector3.FORWARD)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.albedo_color = Color(2.5, 2.0, 1.2)
	_flash_mesh = mb.commit(mat)
	return _flash_mesh
