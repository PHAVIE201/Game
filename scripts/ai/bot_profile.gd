class_name BotProfile
extends RefCounted
## Skill parameters of one bot (randomized so bots don't all feel the same).

var reaction_time := 0.5       ## seconds between spotting and first shot
var aim_error := 0.014         ## radians, std-dev of the aiming error
var turn_speed := 4.5          ## rad/s maximum turn rate
var view_distance := 170.0     ## m, detection range for a standing target
var fov := deg_to_rad(130.0)   ## field of view
var recoil_control := 0.7      ## 0..1, how well recoil is compensated
var burst_min := 3
var burst_max := 7
var crouch_chance := 0.35
var hearing_chance := 0.8
## Extra seconds of margin before heading into the next safe zone.
var zone_margin := 30.0
## Chance to look for cover in a fight / to use grenades (tactics).
var cover_chance := 0.55
var grenade_chance := 0.6
## Likes crowded drop spots (early fights) instead of quiet ones.
var hot_dropper := false


static func create(difficulty: int, rng: RandomNumberGenerator) -> BotProfile:
	var p := BotProfile.new()
	match difficulty:
		MatchConfig.Difficulty.EASY:
			p.cover_chance = 0.25
			p.grenade_chance = 0.2
			p.reaction_time = 0.85
			p.aim_error = 0.024
			p.turn_speed = 3.0
			p.view_distance = 130.0
			p.recoil_control = 0.4
		MatchConfig.Difficulty.HARD:
			p.cover_chance = 0.8
			p.grenade_chance = 0.9
			p.reaction_time = 0.3
			p.aim_error = 0.008
			p.turn_speed = 6.5
			p.view_distance = 210.0
			p.recoil_control = 0.9
		_:
			pass
	# Individual variation +-20%.
	p.reaction_time *= rng.randf_range(0.8, 1.2)
	p.aim_error *= rng.randf_range(0.8, 1.2)
	p.turn_speed *= rng.randf_range(0.85, 1.15)
	p.view_distance *= rng.randf_range(0.85, 1.1)
	p.crouch_chance = rng.randf_range(0.15, 0.5)
	p.zone_margin = rng.randf_range(10.0, 60.0)
	p.hot_dropper = rng.randf() < 0.15
	p.burst_min = rng.randi_range(2, 4)
	p.burst_max = p.burst_min + rng.randi_range(2, 4)
	return p
