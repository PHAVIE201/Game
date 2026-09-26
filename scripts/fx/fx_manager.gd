class_name FxManager
extends Node3D
## Pooled visual effects: bullet impacts (dust, wood chips, stone, blood puffs,
## water splashes) and bullet-hole decals. Nothing is instantiated during play;
## emitters and decals are reused round-robin.

const PARTICLE_POOL := 28
const DECAL_POOL := 48
const MAX_FX_DISTANCE := 180.0

const PRESETS := {
	"ground": {"color": Color(0.58, 0.47, 0.32), "speed": 4.0, "gravity": 12.0, "size": 0.07, "life": 0.55, "spread": 35.0},
	"wood": {"color": Color(0.55, 0.38, 0.2), "speed": 5.0, "gravity": 14.0, "size": 0.06, "life": 0.5, "spread": 45.0},
	"stone": {"color": Color(0.78, 0.77, 0.74), "speed": 6.0, "gravity": 14.0, "size": 0.05, "life": 0.45, "spread": 50.0},
	"building": {"color": Color(0.88, 0.84, 0.76), "speed": 5.0, "gravity": 13.0, "size": 0.06, "life": 0.5, "spread": 45.0},
	"blood": {"color": Color(0.9, 0.16, 0.12), "speed": 3.0, "gravity": 6.0, "size": 0.09, "life": 0.4, "spread": 60.0},
	"water": {"color": Color(0.85, 0.95, 1.0), "speed": 5.5, "gravity": 16.0, "size": 0.1, "life": 0.6, "spread": 18.0},
}

var _emitters: Array[CPUParticles3D] = []
var _next := 0
var _decals: Array[Decal] = []
var _next_decal := 0
var _blast: CPUParticles3D
var _blast_smoke: CPUParticles3D


func _ready() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	mesh.material = mat
	for i in PARTICLE_POOL:
		var p := CPUParticles3D.new()
		p.emitting = false
		p.one_shot = true
		p.explosiveness = 1.0
		p.amount = 10
		p.lifetime = 0.5
		p.local_coords = false
		p.mesh = mesh
		p.direction = Vector3.UP
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Particles shrink to nothing over their lifetime.
		var curve := Curve.new()
		curve.add_point(Vector2(0.0, 1.0))
		curve.add_point(Vector2(1.0, 0.0))
		p.scale_amount_curve = curve
		add_child(p)
		_emitters.append(p)

	_blast = _make_burst(mesh, 44, 0.7, Color(1.0, 0.62, 0.2), 10.0, 0.6)
	_blast_smoke = _make_burst(mesh, 28, 2.4, Color(0.35, 0.33, 0.3), 4.0, 1.5)
	_blast_smoke.gravity = Vector3(0, 1.5, 0)

	var hole_tex := _make_hole_texture()
	for i in DECAL_POOL:
		var d := Decal.new()
		d.texture_albedo = hole_tex
		d.size = Vector3(0.16, 0.3, 0.16)
		d.cull_mask = Layers.RENDER_WORLD
		d.visible = false
		d.distance_fade_enabled = true
		d.distance_fade_begin = 60.0
		d.distance_fade_length = 20.0
		add_child(d)
		_decals.append(d)


func _make_burst(mesh: Mesh, amount: int, life: float, color: Color, speed: float, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.mesh = mesh
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3(0, -6.0, 0)
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size * 1.4
	p.color = color
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	add_child(p)
	return p


## Grenade explosion: fireball sparks + a puff of dark smoke + dust.
func spawn_explosion(pos: Vector3) -> void:
	if Game.camera != null and Game.camera.global_position.distance_to(pos) > MAX_FX_DISTANCE * 2.0:
		return
	_blast.global_position = pos + Vector3(0, 0.3, 0)
	_blast.restart()
	_blast_smoke.global_position = pos + Vector3(0, 0.5, 0)
	_blast_smoke.restart()
	spawn_impact(pos, Vector3.UP, "ground")


func clear() -> void:
	for p in _emitters:
		p.emitting = false
	for d in _decals:
		d.visible = false


## Spawns an impact effect. `normal` = surface normal (effect direction).
func spawn_impact(pos: Vector3, normal: Vector3, surface: String) -> void:
	if Game.camera != null and Game.camera.global_position.distance_to(pos) > MAX_FX_DISTANCE:
		return
	var preset: Dictionary = PRESETS.get(surface, PRESETS["ground"])
	var p := _emitters[_next]
	_next = (_next + 1) % PARTICLE_POOL
	p.global_transform = Transform3D(_basis_from_normal(normal), pos)
	p.color = preset.color
	p.initial_velocity_min = float(preset.speed) * 0.5
	p.initial_velocity_max = float(preset.speed)
	p.gravity = Vector3(0.0, -float(preset.gravity), 0.0)
	p.scale_amount_min = float(preset.size) * 0.6
	p.scale_amount_max = float(preset.size) * 1.3
	p.lifetime = preset.life
	p.spread = preset.spread
	p.restart()

	match surface:
		"blood":
			pass
		"water":
			Sfx.play_3d(&"splash", pos, -8.0, 0.15, 120.0)
		_:
			_place_decal(pos, normal)
			Sfx.play_3d(&"impact", pos, -10.0, 0.2, 90.0)


func _place_decal(pos: Vector3, normal: Vector3) -> void:
	var d := _decals[_next_decal]
	_next_decal = (_next_decal + 1) % DECAL_POOL
	# Decals project along their local -Y axis, so +Y must match the surface normal.
	var rot := _basis_from_normal(normal).rotated(normal, randf() * TAU)
	d.global_transform = Transform3D(rot, pos)
	d.visible = true


static func _basis_from_normal(n: Vector3) -> Basis:
	var y := n.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


## Small procedural bullet-hole texture (dark center, soft rim).
static func _make_hole_texture() -> ImageTexture:
	var size := 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length() / c
			var a := 0.0
			var col := Color(0.08, 0.07, 0.06)
			if d < 0.45:
				a = 1.0
			elif d < 1.0:
				a = (1.0 - (d - 0.45) / 0.55) * 0.55
				col = Color(0.25, 0.22, 0.2)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	return ImageTexture.create_from_image(img)
