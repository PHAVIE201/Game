class_name WeaponModels
## Procedural low-poly gun meshes, built once and shared by every character.
##
## Each model returns a Dictionary:
##   mesh: ArrayMesh, muzzle / grip_r / grip_l / mag / stock / rail: Vector3 (gun space)
##   hip / ads / prone: Vector3 grip offsets from the chest (see CharacterModel)
##   one_handed: bool (pistol pose)
## Gun space: forward = -Z, origin = right-hand grip area.

const METAL := Color(0.2, 0.21, 0.23)
const DARK := Color(0.12, 0.12, 0.13)
const SAND := Color(0.74, 0.63, 0.45)
const WOOD := Color(0.55, 0.34, 0.18)
const OLIVE := Color(0.36, 0.41, 0.27)

static var _cache: Dictionary = {}
static var _flash_mesh: ArrayMesh
static var _material: StandardMaterial3D


static func get_model(id: StringName) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var model: Dictionary
	match id:
		&"smg":
			model = _build_smg()
		&"shotgun":
			model = _build_shotgun()
		&"dmr":
			model = _build_dmr()
		&"sniper":
			model = _build_sniper()
		&"pistol":
			model = _build_pistol()
		_:
			model = _build_rifle()
	_finish(model)
	_cache[id] = model
	return model


## Fills in the default hold offsets: the butt of the stock rests on the shoulder.
static func _finish(m: Dictionary) -> void:
	var stock: Vector3 = m.stock
	var z := 0.26 - stock.z
	if not m.has("hip"):
		m["hip"] = Vector3(0.15, -0.08, z)
	if not m.has("ads"):
		m["ads"] = Vector3(0.12, 0.04, z)
	if not m.has("prone"):
		m["prone"] = Vector3(0.1, 0.12, z - 0.1)
	if not m.has("one_handed"):
		m["one_handed"] = false


static func _mat() -> StandardMaterial3D:
	if _material == null:
		_material = MeshBuilder.make_vertex_color_material(0.55)
	return _material


## "K7 Kestrel": compact rifle with sand-colored furniture and an orange stripe.
static func _build_rifle() -> Dictionary:
	var mb := MeshBuilder.new()
	var accent := Color(0.95, 0.5, 0.15)
	# Receiver
	mb.add_box(Vector3(0, 0.03, -0.12), Vector3(0.07, 0.11, 0.42), METAL)
	mb.add_box(Vector3(0.037, 0.035, -0.08), Vector3(0.006, 0.025, 0.18), accent)
	mb.add_box(Vector3(-0.037, 0.035, -0.08), Vector3(0.006, 0.025, 0.18), accent)
	# Barrel + muzzle brake
	mb.add_box(Vector3(0, 0.05, -0.55), Vector3(0.028, 0.028, 0.42), DARK)
	mb.add_box(Vector3(0, 0.05, -0.77), Vector3(0.046, 0.046, 0.07), DARK)
	# Handguard
	mb.add_box(Vector3(0, 0.035, -0.42), Vector3(0.08, 0.09, 0.26), SAND)
	# Top rail and sights
	mb.add_box(Vector3(0, 0.094, -0.18), Vector3(0.03, 0.016, 0.4), DARK)
	mb.add_box(Vector3(0, 0.12, -0.0), Vector3(0.032, 0.04, 0.03), DARK)
	mb.add_box(Vector3(0, 0.105, -0.52), Vector3(0.012, 0.05, 0.015), DARK)
	# Magazine (tilted forward)
	mb.add_box(Vector3(0, -0.11, -0.2), Vector3(0.05, 0.2, 0.085), DARK, Basis(Vector3.RIGHT, -0.25))
	# Pistol grip (tilted back)
	mb.add_box(Vector3(0, -0.07, 0.03), Vector3(0.045, 0.13, 0.06), SAND, Basis(Vector3.RIGHT, 0.3))
	# Stock + butt pad
	mb.add_box(Vector3(0, 0.0, 0.22), Vector3(0.05, 0.1, 0.26), SAND)
	mb.add_box(Vector3(0, -0.01, 0.36), Vector3(0.06, 0.14, 0.03), DARK)
	return {
		"mesh": mb.commit(_mat()),
		"muzzle": Vector3(0, 0.05, -0.81),
		"grip_r": Vector3(0, -0.05, 0.03),
		"grip_l": Vector3(0, -0.005, -0.33),
		"mag": Vector3(0, -0.2, -0.22),
		"stock": Vector3(0, 0.0, 0.36),
		"rail": Vector3(0, 0.102, -0.14),
	}


## "V9 Vespa": boxy SMG with a long straight magazine, wire stock, teal accents.
static func _build_smg() -> Dictionary:
	var mb := MeshBuilder.new()
	var teal := Color(0.2, 0.72, 0.68)
	mb.add_box(Vector3(0, 0.03, -0.08), Vector3(0.065, 0.1, 0.3), METAL)
	mb.add_box(Vector3(0.034, 0.05, -0.1), Vector3(0.006, 0.02, 0.2), teal)
	mb.add_box(Vector3(-0.034, 0.05, -0.1), Vector3(0.006, 0.02, 0.2), teal)
	# Barrel shroud + barrel
	mb.add_box(Vector3(0, 0.045, -0.29), Vector3(0.055, 0.06, 0.13), DARK)
	mb.add_box(Vector3(0, 0.05, -0.39), Vector3(0.028, 0.028, 0.09), DARK)
	# Straight magazine
	mb.add_box(Vector3(0, -0.12, -0.13), Vector3(0.038, 0.2, 0.05), DARK)
	# Grip + vertical fore grip
	mb.add_box(Vector3(0, -0.07, 0.03), Vector3(0.042, 0.12, 0.055), METAL, Basis(Vector3.RIGHT, 0.25))
	mb.add_box(Vector3(0, -0.055, -0.27), Vector3(0.035, 0.09, 0.035), METAL)
	# Rail + sights
	mb.add_box(Vector3(0, 0.088, -0.1), Vector3(0.028, 0.014, 0.24), DARK)
	mb.add_box(Vector3(0, 0.105, 0.03), Vector3(0.03, 0.03, 0.02), DARK)
	# Wire stock
	mb.add_beam(Vector3(0.02, 0.05, 0.07), Vector3(0.02, 0.02, 0.28), 0.014, DARK)
	mb.add_beam(Vector3(-0.02, 0.05, 0.07), Vector3(-0.02, 0.02, 0.28), 0.014, DARK)
	mb.add_beam(Vector3(0, -0.02, 0.07), Vector3(0, -0.02, 0.28), 0.014, DARK)
	mb.add_box(Vector3(0, 0.0, 0.29), Vector3(0.05, 0.11, 0.02), teal)
	return {
		"mesh": mb.commit(_mat()),
		"muzzle": Vector3(0, 0.05, -0.44),
		"grip_r": Vector3(0, -0.05, 0.03),
		"grip_l": Vector3(0, -0.09, -0.27),
		"mag": Vector3(0, -0.2, -0.13),
		"stock": Vector3(0, 0.0, 0.29),
		"rail": Vector3(0, 0.095, -0.12),
	}


## "B12 Bison": pump shotgun with wooden furniture.
static func _build_shotgun() -> Dictionary:
	var mb := MeshBuilder.new()
	mb.add_box(Vector3(0, 0.035, -0.08), Vector3(0.07, 0.1, 0.3), METAL)
	# Barrel + magazine tube
	mb.add_box(Vector3(0, 0.07, -0.53), Vector3(0.036, 0.036, 0.62), DARK)
	mb.add_box(Vector3(0, 0.025, -0.45), Vector3(0.03, 0.03, 0.48), METAL)
	mb.add_box(Vector3(0, 0.094, -0.83), Vector3(0.01, 0.014, 0.01), Color(0.9, 0.85, 0.6))
	# Pump
	mb.add_box(Vector3(0, 0.022, -0.4), Vector3(0.062, 0.062, 0.2), WOOD)
	for k in 4:
		mb.add_box(Vector3(0, -0.01, -0.33 - k * 0.045), Vector3(0.064, 0.008, 0.012), WOOD.darkened(0.3))
	# Grip + stock (one piece of wood)
	mb.add_box(Vector3(0, -0.04, 0.06), Vector3(0.046, 0.11, 0.08), WOOD, Basis(Vector3.RIGHT, 0.35))
	mb.add_box(Vector3(0, -0.02, 0.22), Vector3(0.05, 0.1, 0.28), WOOD, Basis(Vector3.RIGHT, 0.08))
	mb.add_box(Vector3(0, -0.035, 0.365), Vector3(0.056, 0.14, 0.03), Color(0.45, 0.12, 0.1))
	return {
		"mesh": mb.commit(_mat()),
		"muzzle": Vector3(0, 0.07, -0.85),
		"grip_r": Vector3(0, -0.05, 0.04),
		"grip_l": Vector3(0, -0.015, -0.4),
		"mag": Vector3(0, -0.02, -0.1),
		"stock": Vector3(0, -0.03, 0.37),
		"rail": Vector3(0, 0.09, -0.08),
	}


## "D3 Heron": long semi-automatic marksman rifle, olive and black.
static func _build_dmr() -> Dictionary:
	var mb := MeshBuilder.new()
	mb.add_box(Vector3(0, 0.03, -0.1), Vector3(0.07, 0.11, 0.44), OLIVE)
	mb.add_box(Vector3(0, 0.05, -0.64), Vector3(0.026, 0.026, 0.5), DARK)
	mb.add_box(Vector3(0, 0.05, -0.91), Vector3(0.046, 0.046, 0.08), DARK)
	mb.add_box(Vector3(0, 0.04, -0.47), Vector3(0.075, 0.085, 0.34), DARK)
	mb.add_box(Vector3(0, 0.098, -0.26), Vector3(0.03, 0.016, 0.56), DARK)
	# Magazine (short, 10 rounds)
	mb.add_box(Vector3(0, -0.09, -0.17), Vector3(0.05, 0.14, 0.08), DARK, Basis(Vector3.RIGHT, -0.12))
	mb.add_box(Vector3(0, -0.07, 0.03), Vector3(0.045, 0.13, 0.06), OLIVE, Basis(Vector3.RIGHT, 0.3))
	# Adjustable stock with cheek riser
	mb.add_box(Vector3(0, 0.0, 0.24), Vector3(0.05, 0.09, 0.28), OLIVE)
	mb.add_box(Vector3(0, 0.06, 0.22), Vector3(0.04, 0.03, 0.16), DARK)
	mb.add_box(Vector3(0, -0.01, 0.38), Vector3(0.058, 0.14, 0.03), DARK)
	# Folded bipod under the handguard
	mb.add_box(Vector3(0.018, -0.02, -0.52), Vector3(0.012, 0.012, 0.2), DARK)
	mb.add_box(Vector3(-0.018, -0.02, -0.52), Vector3(0.012, 0.012, 0.2), DARK)
	return {
		"mesh": mb.commit(_mat()),
		"muzzle": Vector3(0, 0.05, -0.96),
		"grip_r": Vector3(0, -0.05, 0.03),
		"grip_l": Vector3(0, -0.0, -0.42),
		"mag": Vector3(0, -0.17, -0.18),
		"stock": Vector3(0, 0.0, 0.39),
		"rail": Vector3(0, 0.106, -0.2),
	}


## "R8 Raven": bolt-action sniper rifle with a green one-piece stock.
static func _build_sniper() -> Dictionary:
	var mb := MeshBuilder.new()
	var green := Color(0.3, 0.42, 0.3)
	# One-piece stock
	mb.add_box(Vector3(0, 0.005, -0.2), Vector3(0.06, 0.08, 0.55), green)
	mb.add_box(Vector3(0, -0.045, 0.05), Vector3(0.045, 0.1, 0.08), green, Basis(Vector3.RIGHT, 0.4))
	mb.add_box(Vector3(0, -0.015, 0.23), Vector3(0.052, 0.12, 0.26), green, Basis(Vector3.RIGHT, 0.1))
	mb.add_box(Vector3(0, -0.03, 0.37), Vector3(0.056, 0.15, 0.03), DARK)
	# Receiver + bolt
	mb.add_box(Vector3(0, 0.055, -0.08), Vector3(0.048, 0.05, 0.26), METAL)
	mb.add_box(Vector3(0.045, 0.055, 0.02), Vector3(0.05, 0.014, 0.014), METAL)
	mb.add_box(Vector3(0.07, 0.05, 0.02), Vector3(0.022, 0.022, 0.022), DARK)
	# Long barrel
	mb.add_box(Vector3(0, 0.055, -0.66), Vector3(0.028, 0.028, 0.66), DARK)
	mb.add_box(Vector3(0, 0.055, -1.0), Vector3(0.04, 0.04, 0.05), DARK)
	# Small internal magazine plate
	mb.add_box(Vector3(0, -0.045, -0.1), Vector3(0.04, 0.03, 0.08), METAL)
	return {
		"mesh": mb.commit(_mat()),
		"muzzle": Vector3(0, 0.055, -1.03),
		"grip_r": Vector3(0, -0.05, 0.05),
		"grip_l": Vector3(0, -0.02, -0.36),
		"mag": Vector3(0, -0.06, -0.1),
		"stock": Vector3(0, -0.02, 0.38),
		"rail": Vector3(0, 0.08, -0.08),
		"bolt": Vector3(0.07, 0.05, 0.02),
	}


## "P1 Sparrow": pistol held with both hands at arm's length.
static func _build_pistol() -> Dictionary:
	var mb := MeshBuilder.new()
	var accent := Color(0.95, 0.5, 0.15)
	mb.add_box(Vector3(0, 0.04, -0.06), Vector3(0.032, 0.036, 0.19), METAL)
	mb.add_box(Vector3(0, 0.05, -0.06), Vector3(0.034, 0.006, 0.14), accent)
	mb.add_box(Vector3(0, 0.014, -0.05), Vector3(0.03, 0.02, 0.16), DARK)
	mb.add_box(Vector3(0, -0.04, 0.02), Vector3(0.03, 0.1, 0.045), DARK, Basis(Vector3.RIGHT, 0.2))
	mb.add_box(Vector3(0, -0.01, -0.03), Vector3(0.008, 0.03, 0.04), DARK)
	mb.add_box(Vector3(0, 0.062, -0.14), Vector3(0.008, 0.012, 0.008), DARK)
	return {
		"mesh": mb.commit(_mat()),
		"muzzle": Vector3(0, 0.04, -0.16),
		"grip_r": Vector3(0, -0.04, 0.02),
		"grip_l": Vector3(-0.03, -0.05, 0.025),
		"mag": Vector3(0, -0.09, 0.03),
		"stock": Vector3(0, 0.0, 0.05),
		"rail": Vector3(0, 0.06, -0.06),
		"hip": Vector3(0.1, -0.12, -0.34),
		"ads": Vector3(0.05, 0.02, -0.42),
		"prone": Vector3(0.06, 0.1, -0.45),
		"one_handed": true,
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
