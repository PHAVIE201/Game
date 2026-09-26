class_name BotPerception
extends RefCounted
## Vision for one bot. Scans are throttled (~4 per second, randomly staggered)
## so 63 bots don't all raycast in the same frame.

const INTERVAL := 0.25
## Enemies closer than this are noticed even outside the field of view.
const AWARENESS_RADIUS := 7.0

var brain: BotBrain
var _timer := 0.0


func _init(p_brain: BotBrain) -> void:
	brain = p_brain
	_timer = randf() * INTERVAL


func update(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = INTERVAL + randf() * 0.08
	scan()


func scan() -> void:
	var me := brain.character
	if Game.match_manager == null or Game.projectiles == null:
		return
	var eye := me.get_eye_position()
	var fwd := Vector3(-sin(me.aim_yaw), 0.0, -cos(me.aim_yaw))
	var cos_half_fov := cos(brain.profile.fov * 0.5)
	var best: GameCharacter = null
	var best_score := INF
	var now := Time.get_ticks_msec()
	for c in Game.match_manager.alive:
		if c == me or c.is_dead or not brain.can_target(c):
			continue
		var to := c.global_position - me.global_position
		var d := to.length()
		# Crouching / prone targets are harder to spot, shooting ones easier.
		var range_mult := 1.0
		if c.stance == GameCharacter.Stance.CROUCH:
			range_mult = 0.75
		elif c.stance == GameCharacter.Stance.PRONE:
			range_mult = 0.45
		if now - c.last_fire_msec < 1500:
			range_mult = maxf(range_mult, 1.3)
		if d > brain.profile.view_distance * range_mult:
			continue
		if d > AWARENESS_RADIUS:
			var flat := Vector3(to.x, 0.0, to.z)
			if flat.length_squared() > 0.001 and fwd.dot(flat.normalized()) < cos_half_fov:
				continue
		# Line of sight to the body or the head.
		if not Game.projectiles.has_line_of_sight(eye, c.get_hitbox_center()):
			if not Game.projectiles.has_line_of_sight(eye, c.get_head_position()):
				continue
		var score := d
		if c == brain.target:
			score *= 0.7   # stick to the current target
		if score < best_score:
			best_score = score
			best = c
	if best != null:
		brain.on_enemy_seen(best)
