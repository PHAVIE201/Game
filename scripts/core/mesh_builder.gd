class_name MeshBuilder
extends RefCounted
## Small helper to build flat-shaded, vertex-colored low-poly meshes in code.
##
## Everything visible in the game (terrain, trees, houses, characters, guns) is
## made with this class instead of imported models. Triangles are not indexed so
## each face gets its own normal => crisp "low-poly" flat shading.
##
## Godot treats CLOCKWISE triangles as front-facing. All add_* helpers take an
## `outward` hint and fix the winding automatically, so callers never need to
## think about vertex order.

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
## Optional skinning data (4 influences per vertex, we only use the first).
var skinned := false
var bones := PackedInt32Array()
var weights := PackedFloat32Array()
## Bone used for vertices added from now on (when skinned).
var current_bone := 0
## Transform applied to every vertex added from now on.
var xform := Transform3D.IDENTITY


func _init(p_skinned := false) -> void:
	skinned = p_skinned


func vertex_count() -> int:
	return verts.size()


## Adds a single triangle. The face will point toward `outward`
## (pass Vector3.ZERO to keep the given order, assumed clockwise).
func add_tri(a: Vector3, b: Vector3, c: Vector3, color: Color, outward := Vector3.ZERO) -> void:
	a = xform * a
	b = xform * b
	c = xform * c
	var cr := (b - a).cross(c - a)
	if cr.length_squared() < 1e-14:
		return
	if outward != Vector3.ZERO:
		var out_w := xform.basis * outward
		# Godot front face: cross(b - a, c - a) points AWAY from the viewer.
		if cr.dot(out_w) > 0.0:
			var tmp := b
			b = c
			c = tmp
			cr = -cr
	var n := -cr.normalized()
	verts.append(a)
	verts.append(b)
	verts.append(c)
	normals.append(n)
	normals.append(n)
	normals.append(n)
	colors.append(color)
	colors.append(color)
	colors.append(color)
	if skinned:
		for i in 3:
			bones.append(current_bone)
			bones.append(0)
			bones.append(0)
			bones.append(0)
			weights.append(1.0)
			weights.append(0.0)
			weights.append(0.0)
			weights.append(0.0)


## Quad a-b-c-d (in order around the edge) facing `outward`.
func add_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, outward: Vector3) -> void:
	add_tri(a, b, c, color, outward)
	add_tri(a, c, d, color, outward)


## Axis aligned (in local/xform space) box. `basis` rotates the box around its center.
func add_box(center: Vector3, size: Vector3, color: Color, basis := Basis.IDENTITY, top_color := Color(0, 0, 0, 0)) -> void:
	var h := size * 0.5
	var corners: Array[Vector3] = []
	for i in 8:
		var p := Vector3(
			h.x if (i & 1) else -h.x,
			h.y if (i & 2) else -h.y,
			h.z if (i & 4) else -h.z)
		corners.append(center + basis * p)
	var top := top_color if top_color.a > 0.0 else color
	var ax := basis.x
	var ay := basis.y
	var az := basis.z
	# -X, +X
	add_quad(corners[0], corners[2], corners[6], corners[4], color, -ax)
	add_quad(corners[1], corners[3], corners[7], corners[5], color, ax)
	# -Y, +Y
	add_quad(corners[0], corners[1], corners[5], corners[4], color, -ay)
	add_quad(corners[2], corners[3], corners[7], corners[6], top, ay)
	# -Z, +Z
	add_quad(corners[0], corners[1], corners[3], corners[2], color, -az)
	add_quad(corners[4], corners[5], corners[7], corners[6], color, az)


## Box spanning between two points (like a limb segment) with square cross section.
func add_beam(from: Vector3, to: Vector3, thickness: float, color: Color) -> void:
	var dir := to - from
	var length := dir.length()
	if length < 0.0001:
		return
	var y := dir / length
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	add_box((from + to) * 0.5, Vector3(thickness, length, thickness), color, Basis(x, y, z))


## Frustum / cylinder / cone along +Y starting at `base`. top_radius 0 => cone.
func add_frustum(base: Vector3, bottom_radius: float, top_radius: float, height: float, sides: int, color: Color, caps := true, rot_offset := 0.0, top_cap_color := Color(0, 0, 0, 0)) -> void:
	var top_center := base + Vector3(0, height, 0)
	for i in sides:
		var a0 := rot_offset + TAU * float(i) / sides
		var a1 := rot_offset + TAU * float(i + 1) / sides
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var b0 := base + d0 * bottom_radius
		var b1 := base + d1 * bottom_radius
		var t0 := top_center + d0 * top_radius
		var t1 := top_center + d1 * top_radius
		var mid := (d0 + d1).normalized()
		if top_radius > 0.0001:
			add_quad(b0, b1, t1, t0, color, mid)
		else:
			add_tri(b0, b1, top_center, color, mid + Vector3(0, 0.2, 0))
		if caps:
			add_tri(base, b0, b1, color, Vector3.DOWN)
			if top_radius > 0.0001:
				var tc := top_cap_color if top_cap_color.a > 0.0 else color
				add_tri(top_center, t0, t1, tc, Vector3.UP)


## Low-poly "blob" sphere. `jitter` randomly displaces vertices (organic look:
## tree crowns, rocks). Deterministic when an rng with fixed seed is given.
func add_sphere(center: Vector3, radius: Vector3, color: Color, lon := 8, lat := 5, jitter := 0.0, rng: RandomNumberGenerator = null, color_var := 0.0) -> void:
	# Build the vertex grid first so neighbouring faces share displaced vertices.
	var grid: Array[PackedVector3Array] = []
	for j in lat + 1:
		var row := PackedVector3Array()
		var v := float(j) / lat
		var phi := PI * v
		for i in lon:
			var theta := TAU * float(i) / lon + (0.5 if j % 2 == 1 else 0.0) * TAU / lon
			var dir := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
			var r := 1.0
			if jitter > 0.0 and rng != null and j > 0 and j < lat:
				r += rng.randf_range(-jitter, jitter)
			row.append(center + Vector3(dir.x * radius.x, dir.y * radius.y, dir.z * radius.z) * r)
		grid.append(row)
	for j in lat:
		for i in lon:
			var i1 := (i + 1) % lon
			var a := grid[j][i]
			var b := grid[j][i1]
			var c := grid[j + 1][i1]
			var d := grid[j + 1][i]
			var col := color
			if color_var > 0.0 and rng != null:
				var k := rng.randf_range(-color_var, color_var)
				col = Color(color.r + k, color.g + k, color.b + k * 0.5, color.a)
			var face_center := (a + b + c + d) * 0.25
			var outward := face_center - center
			if j == 0:
				add_tri(a, c, d, col, outward)
			elif j == lat - 1:
				add_tri(a, b, c, col, outward)
			else:
				add_tri(a, b, c, col, outward)
				add_tri(a, c, d, col, outward)


## Triangular prism (e.g. gable roof end). Points p0,p1,p2 form the triangle,
## extruded by `depth` along `axis`.
func add_prism(p0: Vector3, p1: Vector3, p2: Vector3, axis: Vector3, depth: float, color: Color) -> void:
	var off := axis.normalized() * depth
	var q0 := p0 + off
	var q1 := p1 + off
	var q2 := p2 + off
	var c := (p0 + p1 + p2 + q0 + q1 + q2) / 6.0
	add_tri(p0, p1, p2, color, -axis)
	add_tri(q0, q1, q2, color, axis)
	add_quad(p0, p1, q1, q0, color, (p0 + p1 + q1 + q0) * 0.25 - c)
	add_quad(p1, p2, q2, q1, color, (p1 + p2 + q2 + q1) * 0.25 - c)
	add_quad(p2, p0, q0, q2, color, (p2 + p0 + q0 + q2) * 0.25 - c)


func get_arrays() -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	if skinned:
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
	return arrays


## Creates (or appends a surface to) an ArrayMesh.
func commit(material: Material = null, mesh: ArrayMesh = null) -> ArrayMesh:
	if mesh == null:
		mesh = ArrayMesh.new()
	if verts.is_empty():
		return mesh
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, get_arrays())
	if material != null:
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return mesh


func clear() -> void:
	verts.clear()
	normals.clear()
	colors.clear()
	bones.clear()
	weights.clear()


## Shared vertex-colored material (one material => fewer state changes).
static func make_vertex_color_material(roughness := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	# Palette colors are authored in sRGB (like the color picker).
	m.vertex_color_is_srgb = true
	m.roughness = roughness
	m.metallic_specular = 0.25
	return m
