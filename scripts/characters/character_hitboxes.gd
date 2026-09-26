class_name CharacterHitboxes
extends RefCounted
## Body-part hitboxes as capsules attached to the procedural skeleton.
##
## Bullets are tested with analytic ray-capsule intersection in model space.
## This is far cheaper than moving 7+ physics bodies per character every frame
## and scales to 64 characters. Damage multipliers per part live in WeaponData.

const B := CharacterModel.B
const P := DamageInfo.Part

## Squared radius of the per-character bounding sphere (broadphase).
const BROADPHASE_RADIUS_SQ := 1.7 * 1.7

## [bone_a, offset_a, bone_b, offset_b, radius, part]
const CAPSULES := [
	[B.HEAD, Vector3(0, 0.12, 0), B.HEAD, Vector3(0, 0.13, 0), 0.165, P.HEAD],
	[B.HIPS, Vector3(0, -0.04, 0), B.CHEST, Vector3(0, 0.19, 0), 0.2, P.TORSO],
	[B.UPPER_ARM_L, Vector3.ZERO, B.LOWER_ARM_L, Vector3.ZERO, 0.065, P.LIMB],
	[B.LOWER_ARM_L, Vector3.ZERO, B.HAND_L, Vector3(0, -0.06, 0), 0.055, P.LIMB],
	[B.UPPER_ARM_R, Vector3.ZERO, B.LOWER_ARM_R, Vector3.ZERO, 0.065, P.LIMB],
	[B.LOWER_ARM_R, Vector3.ZERO, B.HAND_R, Vector3(0, -0.06, 0), 0.055, P.LIMB],
	[B.UPPER_LEG_L, Vector3.ZERO, B.LOWER_LEG_L, Vector3.ZERO, 0.095, P.LIMB],
	[B.LOWER_LEG_L, Vector3.ZERO, B.FOOT_L, Vector3.ZERO, 0.075, P.LIMB],
	[B.UPPER_LEG_R, Vector3.ZERO, B.LOWER_LEG_R, Vector3.ZERO, 0.095, P.LIMB],
	[B.LOWER_LEG_R, Vector3.ZERO, B.FOOT_R, Vector3.ZERO, 0.075, P.LIMB],
]

var model: CharacterModel


func _init(p_model: CharacterModel) -> void:
	model = p_model


## World-space center used for broadphase and as an aim point for bots.
func get_center() -> Vector3:
	return model.global_transform * model.bone_global[B.SPINE].origin


func get_head() -> Vector3:
	return model.global_transform * (model.bone_global[B.HEAD] * Vector3(0, 0.12, 0))


## Returns {} or { t: distance along the ray, part: DamageInfo.Part }.
## `dir` must be normalized (world space).
func intersect_ray(from: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	var inv := model.global_transform.affine_inverse()
	var ro := inv * from
	var rd := inv.basis * dir   # model has no scale => still normalized
	var best := max_dist
	var part := -1
	var g := model.bone_global
	for cap in CAPSULES:
		var a: Vector3 = g[cap[0]] * (cap[1] as Vector3)
		var b: Vector3 = g[cap[2]] * (cap[3] as Vector3)
		var t := ray_capsule(ro, rd, a, b, cap[4])
		if t >= 0.0 and t < best:
			best = t
			part = cap[5]
	if part < 0:
		return {}
	return {"t": best, "part": part}


## Ray / capsule intersection (after Inigo Quilez). Returns -1 on miss.
static func ray_capsule(ro: Vector3, rd: Vector3, pa: Vector3, pb: Vector3, r: float) -> float:
	var ba := pb - pa
	var oa := ro - pa
	var baba := ba.dot(ba)
	if baba < 0.000001:
		return ray_sphere(ro, rd, pa, r)
	var bard := ba.dot(rd)
	var baoa := ba.dot(oa)
	var rdoa := rd.dot(oa)
	var oaoa := oa.dot(oa)
	var a := baba - bard * bard
	var b := baba * rdoa - baoa * bard
	var c := baba * oaoa - baoa * baoa - r * r * baba
	var h := b * b - a * c
	if a > 0.000001 and h >= 0.0:
		var t := (-b - sqrt(h)) / a
		var y := baoa + t * bard
		if y > 0.0 and y < baba:
			return t if t >= 0.0 else -1.0
	# End caps (also handles rays parallel to the axis).
	var t0 := ray_sphere(ro, rd, pa, r)
	var t1 := ray_sphere(ro, rd, pb, r)
	if t0 < 0.0:
		return t1
	if t1 < 0.0:
		return t0
	return minf(t0, t1)


static func ray_sphere(ro: Vector3, rd: Vector3, c: Vector3, r: float) -> float:
	var oc := ro - c
	var b := oc.dot(rd)
	var cc := oc.dot(oc) - r * r
	var h := b * b - cc
	if h < 0.0:
		return -1.0
	var t := -b - sqrt(h)
	return t if t >= 0.0 else -1.0
