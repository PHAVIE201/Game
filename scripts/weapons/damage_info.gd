class_name DamageInfo
extends RefCounted
## Describes one instance of damage. Created by ProjectileSystem (and later by
## grenades, zone, fall damage...) and passed to GameCharacter.apply_damage().

enum Part { HEAD, TORSO, LIMB, OTHER }

var amount := 0.0
var part: int = Part.TORSO
## GameCharacter that caused the damage (can be null for zone / fall damage).
var attacker: Node = null
var weapon_name := ""
var hit_position := Vector3.ZERO
## Direction the damage travelled (used for death fall direction / indicators).
var direction := Vector3.FORWARD
var distance := 0.0


func is_headshot() -> bool:
	return part == Part.HEAD


static func part_name(p: int) -> String:
	match p:
		Part.HEAD:
			return "đầu"
		Part.TORSO:
			return "thân"
		Part.LIMB:
			return "chân/tay"
		_:
			return "khác"
