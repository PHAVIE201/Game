class_name WeaponDB
## Registry of every weapon resource (explicit preloads so exported builds work).

const FISTS: WeaponData = preload("res://resources/weapons/fists.tres")
const K7: WeaponData = preload("res://resources/weapons/k7_rifle.tres")
const V9: WeaponData = preload("res://resources/weapons/v9_smg.tres")
const B12: WeaponData = preload("res://resources/weapons/b12_shotgun.tres")
const D3: WeaponData = preload("res://resources/weapons/d3_dmr.tres")
const R8: WeaponData = preload("res://resources/weapons/r8_sniper.tres")
const P1: WeaponData = preload("res://resources/weapons/p1_pistol.tres")

const GUNS: Array[WeaponData] = [K7, V9, B12, D3, R8, P1]


static func get_weapon(id: StringName) -> WeaponData:
	for w in GUNS:
		if w.id == id:
			return w
	return FISTS if id == FISTS.id else null


static func category_name(c: int) -> String:
	match c:
		WeaponData.Category.RIFLE:
			return "Súng trường"
		WeaponData.Category.SMG:
			return "Tiểu liên"
		WeaponData.Category.SHOTGUN:
			return "Súng săn"
		WeaponData.Category.DMR:
			return "Súng trường bắn tỉa"
		WeaponData.Category.SNIPER:
			return "Súng bắn tỉa"
		WeaponData.Category.PISTOL:
			return "Súng lục"
		_:
			return "Cận chiến"
