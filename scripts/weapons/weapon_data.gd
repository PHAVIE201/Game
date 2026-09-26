class_name WeaponData
extends Resource
## Data-driven weapon definition (one .tres per gun in resources/weapons/).
##
## Every gun of the game (and the bare fists) is one of these resources; the
## runtime Weapon class, the ProjectileSystem, the character model and the bots
## read everything from here. Register new guns in WeaponDB.

enum FireMode { SINGLE, AUTO }
enum Category { RIFLE, SMG, SHOTGUN, DMR, SNIPER, PISTOL, MELEE }

@export var id: StringName = &"k7"
@export var display_name := "K7 Kestrel"
@export var category: Category = Category.RIFLE
## Inventory ammo id ("" = no ammo, e.g. fists).
@export var ammo_type: StringName = &"ammo_rifle"
## Procedural model used by WeaponModels.
@export var model: StringName = &"rifle"
## Sound played when firing (see Sfx).
@export var shot_sound: StringName = &"rifle_shot"

@export_group("Damage")
@export var damage := 36.0
@export var head_multiplier := 2.2
@export var torso_multiplier := 1.0
@export var limb_multiplier := 0.75
## Damage falloff: full damage until falloff_start, then linearly down to
## falloff_min_factor at falloff_end.
@export var falloff_start := 80.0
@export var falloff_end := 450.0
@export var falloff_min_factor := 0.7

@export_group("Firing")
@export var rounds_per_minute := 660.0
@export var fire_modes: Array[int] = [FireMode.AUTO, FireMode.SINGLE]
@export var magazine_size := 30
@export var reload_time := 2.3
## Reload one round at a time (shotgun): reload_time is then per round and
## pulling the trigger interrupts the reload.
@export var reload_per_round := false
## Bolt action: the bolt is cycled after every shot (sound + animation).
@export var bolt_action := false
## Bullets per shot (shotgun pellets). Each pellet deals `damage`.
@export var pellets := 1
## Extra cone (degrees) the pellets are spread over.
@export var pellet_spread := 0.0
## Fists: reach of a punch in meters (0 = shoots bullets).
@export var melee_range := 0.0
@export var muzzle_velocity := 850.0
@export var bullet_gravity := 9.8
@export var max_range := 900.0
## Gunshot audible radius (bots "hear" shots within this distance).
@export var loudness_radius := 320.0

@export_group("Accuracy (degrees)")
@export var spread_hip := 1.8
@export var spread_ads := 0.35
@export var spread_move := 1.6
@export var spread_air := 5.0
@export var spread_per_shot := 0.22
@export var spread_max_bloom := 3.0
@export var spread_recovery := 6.0
@export var crouch_spread_factor := 0.8
@export var prone_spread_factor := 0.6

@export_group("Recoil (degrees)")
@export var recoil_vertical := 0.75
@export var recoil_horizontal := 0.32
## How fast accumulated recoil returns (deg/s) when not firing.
@export var recoil_recovery := 9.0

@export_group("Handling")
@export var ads_fov := 55.0
@export var ads_move_factor := 0.7
@export var tracer_color := Color(1.0, 0.8, 0.35)


func is_melee() -> bool:
	return category == Category.MELEE


func is_pistol() -> bool:
	return category == Category.PISTOL


func is_primary() -> bool:
	return category != Category.PISTOL and category != Category.MELEE


## True when the trigger must be released between shots in every mode.
func is_single_only() -> bool:
	return not fire_modes.has(FireMode.AUTO)


func get_fire_interval() -> float:
	return 60.0 / maxf(rounds_per_minute, 1.0)


func get_part_multiplier(part: int) -> float:
	match part:
		DamageInfo.Part.HEAD:
			return head_multiplier
		DamageInfo.Part.LIMB:
			return limb_multiplier
		_:
			return torso_multiplier


func get_falloff(distance: float) -> float:
	if distance <= falloff_start:
		return 1.0
	var t := clampf((distance - falloff_start) / maxf(falloff_end - falloff_start, 1.0), 0.0, 1.0)
	return lerpf(1.0, falloff_min_factor, t)
