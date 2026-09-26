extends Node
## Test automation, only created when the game is started with user args:
##
##   --autotest[=seconds]     start a match at once, drive the player with an
##                            autopilot, exercise restart / death / victory and
##                            print statistics, then quit.
##   --screenshots=<dir>      start a match and capture screenshots (needs a
##                            real renderer, e.g. under xvfb), then quit.
##   --duel=d1,d2,...         bot accuracy test: one bot shoots at the (immortal,
##                            standing) player from each distance for 10 s.
##   --bots=N  --seed=S       match options for all modes.
##
## Example (headless smoke test):
##   godot --headless --path . -- --autotest=60 --bots=8

var main: Node
var mode := ""
var duration := 40.0
var out_dir := "user://screenshots"
var bots := 8
var map_seed := 1337

var _t := 0.0
var _phase := 0
var _rng := RandomNumberGenerator.new()
var _move_timer := 0.0
var _burst_timer := 0.0
var _stats := {"shots": 0, "hits": 0, "deaths": 0, "headshots": 0, "results": [], "restarts": 0}
var _fps_samples: Array[float] = []
var _cpu_process := 0.0
var _cpu_physics := 0.0
var _cpu_samples := 0
var _swim_state := 0          # 0 = not done, 1 = in water, 2 = done
var _swim_until := 0.0
var _swim_return := Vector3.ZERO
var _pause_state := 0
var _menu_state := 0
var _menu_time := 0.0
var _log_timer := 0.0
var _screens_started := false
var _duel_distances: Array[float] = [15.0, 40.0, 80.0, 150.0]
var _duel_started := false


func _ready() -> void:
	main = get_parent()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 42
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autotest"):
			mode = "autotest"
			if "=" in a:
				duration = float(a.split("=")[1])
		elif a.begins_with("--screenshots"):
			mode = "screenshots"
			if "=" in a:
				out_dir = a.split("=")[1]
		elif a.begins_with("--duel"):
			mode = "duel"
			_duel_distances.clear()
			for d in a.split("=")[1].split(","):
				_duel_distances.append(float(d))
		elif a.begins_with("--bots="):
			bots = int(a.split("=")[1])
		elif a.begins_with("--seed="):
			map_seed = int(a.split("=")[1])
	Events.shot_fired.connect(func(_s, _p, _r): _stats.shots += 1)
	Events.character_damaged.connect(func(_v, info):
		_stats.hits += 1
		if (info as DamageInfo).is_headshot():
			_stats.headshots += 1)
	Events.character_died.connect(func(_v, _i): _stats.deaths += 1)
	Events.player_match_result.connect(func(r): _stats.results.append(r))
	var cfg := MatchConfig.new()
	cfg.bot_count = bots
	cfg.map_seed = map_seed
	print("[auto] mode=%s bots=%d seed=%d" % [mode, bots, map_seed])
	main.call_deferred("start_game", cfg)


func _session_ready() -> bool:
	if _menu_state != 0:
		return false
	var s: GameSession = main.session
	return s != null and s.world != null and s.world.is_ready and Game.player != null \
		and Game.match_manager != null and Game.match_manager.state != MatchManager.State.IDLE


func _process(delta: float) -> void:
	if not _session_ready():
		return
	_t += delta
	if delta > 0.0:
		_fps_samples.append(1.0 / delta)
	_cpu_process += Performance.get_monitor(Performance.TIME_PROCESS)
	_cpu_physics += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	_cpu_samples += 1
	if mode == "autotest" and _menu_state == 0:
		_run_autotest(delta)
	elif mode == "screenshots" and not _screens_started:
		_screens_started = true
		_run_screenshots()
	elif mode == "duel" and not _duel_started:
		_duel_started = true
		_run_duels()


# --------------------------------------------------------------------------
# Autotest
# --------------------------------------------------------------------------

func _run_autotest(delta: float) -> void:
	var s: GameSession = main.session
	var mm := Game.match_manager
	_log_timer -= delta
	if _log_timer <= 0.0:
		_log_timer = 5.0
		_log_status()
	match _phase:
		0:
			_autopilot(delta)
			_swim_test()
			if _t > duration * 0.4:
				print("[auto] --- restart match ---")
				s.restart_match()
				_stats.restarts += 1
				_phase = 1
		1:
			_autopilot(delta)
			# Pause / unpause (the automation keeps running while paused).
			if _pause_state == 0 and _t > duration * 0.55:
				s.set_paused(true)
				_pause_state = 1
			elif _pause_state == 1:
				print("[auto] paused=%s pause_menu_visible=%s" % [get_tree().paused, s.pause_menu.visible])
				s.set_paused(false)
				_pause_state = 2
			if _t > duration * 0.7:
				# Force the player's death by a bot to test the defeat flow.
				print("[auto] --- forcing player death ---")
				var killer: GameCharacter = null
				for c in mm.alive:
					if not c.is_player:
						killer = c
						break
				var info := DamageInfo.new()
				info.amount = 500.0
				info.part = DamageInfo.Part.HEAD
				info.attacker = killer
				info.weapon_name = "K7 Kestrel"
				info.direction = Vector3.FORWARD
				info.distance = 42.0
				Game.player.apply_damage(info)
				_phase = 2
		2:
			if _t > duration * 0.8:
				print("[auto] --- restart + force victory ---")
				s.restart_match()
				_stats.restarts += 1
				_phase = 3
		3:
			if _t > duration * 0.85:
				for c in mm.alive.duplicate():
					if not c.is_player:
						var info := DamageInfo.new()
						info.amount = 500.0
						info.attacker = Game.player
						info.weapon_name = "K7 Kestrel"
						c.apply_damage(info)
				_phase = 4
		4:
			if _t > duration:
				_finish()


## Drops the player into deep water for a few seconds to exercise swimming.
func _swim_test() -> void:
	var p := Game.player
	if p == null or p.is_dead:
		return
	if _swim_state == 0 and _t > duration * 0.15:
		var hm := Game.world.hm
		var target := Vector2.ZERO
		if not hm.lakes.is_empty():
			target = hm.lakes[0].center
		else:
			target = hm.river_points[hm.river_points.size() / 2]
		_swim_return = p.global_position
		p.global_position = Vector3(target.x, 0.2, target.y)
		p.velocity = Vector3.ZERO
		_swim_state = 1
		_swim_until = _t + 3.0
	elif _swim_state == 1 and _t > _swim_until:
		print("[auto] swim test: swimming=%s y=%.2f depth=%.1f" % [p.is_swimming, p.global_position.y,
			Game.world.get_water_depth(p.global_position.x, p.global_position.z)])
		p.global_position = _swim_return + Vector3(0, 0.5, 0)
		_swim_state = 2


func _autopilot(delta: float) -> void:
	var p := Game.player
	if p == null or p.is_dead:
		return
	var ctrl := p.get_node_or_null("PlayerController")
	if ctrl != null and ctrl.is_processing():
		ctrl.set_process(false)
		ctrl.set_process_unhandled_input(false)
	_move_timer -= delta
	if _move_timer <= 0.0:
		_move_timer = _rng.randf_range(1.0, 3.0)
		p.input_move = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-0.3, 1)).limit_length(1.0)
		p.input_sprint = _rng.randf() < 0.3
		var r := _rng.randf()
		if r < 0.1:
			p.toggle_crouch()
		elif r < 0.15:
			p.toggle_prone()
		elif r < 0.25:
			p.request_jump()
		elif r < 0.3:
			p.request_reload()
		elif r < 0.33:
			p.cycle_fire_mode()
	# Shoot at the nearest visible enemy.
	var best: GameCharacter = null
	var best_d := 160.0
	for c in Game.match_manager.alive:
		if c == p:
			continue
		var d := p.global_position.distance_to(c.global_position)
		if d < best_d and Game.projectiles.has_line_of_sight(p.get_eye_position(), c.get_hitbox_center()):
			best_d = d
			best = c
	_burst_timer -= delta
	if best != null:
		var to := best.get_hitbox_center() - p.get_eye_position()
		p.aim_yaw = atan2(-to.x, -to.z)
		p.aim_pitch = atan2(to.y, Vector2(to.x, to.z).length())
		p.aim_point = best.get_hitbox_center()
		p.has_aim_point = true
		p.input_aim = best_d > 25.0
		if _burst_timer <= 0.0:
			_burst_timer = _rng.randf_range(0.4, 1.2)
		p.input_fire = _burst_timer > 0.3
	else:
		p.input_fire = false
		p.input_aim = false
		p.has_aim_point = false


func _log_status() -> void:
	var mm := Game.match_manager
	var states := {}
	for c in mm.alive:
		var b := c.get_node_or_null("BotBrain") as BotBrain
		if b != null:
			states[b.fsm.current_name] = int(states.get(b.fsm.current_name, 0)) + 1
	var p := Game.player
	print("[auto] t=%.0fs alive=%d/%d bullets=%d player_hp=%.0f stance=%d swim=%s pos=%s bot_states=%s" % [
		_t, mm.alive.size(), mm.participants.size(), Game.projectiles.get_bullet_count(),
		p.health if p != null else -1.0, p.stance if p != null else -1, p.is_swimming if p != null else false,
		str(p.global_position.round()) if p != null else "-", str(states)])


func _finish() -> void:
	if _menu_state == 0:
		# Exercise "back to main menu" before quitting.
		_menu_state = 1
		main.back_to_menu()
		await get_tree().create_timer(0.5, true).timeout
		print("[auto] back to menu: menu_visible=%s session=%s game_active=%s" % [main.menu.visible, main.session, Game.is_active()])
	# Average frame time (not average FPS, which is skewed by very short frames).
	var total_time := 0.0
	for f in _fps_samples:
		total_time += 1.0 / f
	var avg := _fps_samples.size() / maxf(total_time, 0.0001)
	print("[auto] shots=%d hits=%d headshots=%d deaths=%d restarts=%d avg_fps(headless)=%.0f" % [
		_stats.shots, _stats.hits, _stats.headshots, _stats.deaths, _stats.restarts, avg])
	print("[auto] avg CPU per frame: process=%.2f ms, physics=%.2f ms" % [
		_cpu_process / maxf(_cpu_samples, 1) * 1000.0, _cpu_physics / maxf(_cpu_samples, 1) * 1000.0])
	for r in _stats.results:
		print("[auto] result: won=%s place=%d/%d kills=%d killer=%s" % [r.won, r.placement, r.total, r.kills, r.killer_name])
	var ok: bool = _stats.results.size() >= 2 and not _stats.results[0].won and _stats.results[_stats.results.size() - 1].won
	print("[auto] AUTOTEST ", "PASSED" if ok else "FAILED (missing defeat/victory results)")
	get_tree().quit(0 if ok else 1)


# --------------------------------------------------------------------------
# Duel (bot accuracy) test
# --------------------------------------------------------------------------

func _run_duels() -> void:
	var p := Game.player
	var ctrl := p.get_node("PlayerController")
	ctrl.set_process(false)
	ctrl.set_process_unhandled_input(false)
	p.max_health = 1.0e9
	p.health = 1.0e9
	var mm := Game.match_manager
	var bots: Array[GameCharacter] = []
	for c in mm.alive:
		if not c.is_player:
			bots.append(c)
	var duelist := bots[0]
	# Park every other bot far away with its brain disabled.
	for k in range(1, bots.size()):
		bots[k].get_node("BotBrain").set_physics_process(false)
		bots[k].global_position = Vector3(900, 50, 900 - k * 5.0)
	var hits := {"n": 0, "head": 0}
	var on_dmg := func(v, info):
		if v == p:
			hits.n += 1
			if (info as DamageInfo).is_headshot():
				hits.head += 1
	Events.character_damaged.connect(on_dmg)
	var shots := {"n": 0}
	var on_shot := func(s, _pos, _r):
		if s == duelist:
			shots.n += 1
	Events.shot_fired.connect(on_shot)
	var brain := duelist.get_node("BotBrain") as BotBrain
	for dist in _duel_distances:
		# Find a direction with a clear line of sight at this distance.
		var placed := false
		for k in 24:
			var ang := k * TAU / 24.0
			var pos := p.global_position + Vector3(cos(ang), 0, sin(ang)) * dist
			pos.y = Game.world.get_height(pos.x, pos.z)
			if Game.world.is_water(pos.x, pos.z, 0.2):
				continue
			if Game.projectiles.has_line_of_sight(pos + Vector3(0, 1.6, 0), p.get_hitbox_center()):
				duelist.global_position = pos + Vector3(0, 0.1, 0)
				placed = true
				break
		if not placed:
			print("[duel] %.0fm: no clear line of sight, skipped" % dist)
			continue
		duelist.health = 100.0
		duelist.weapon.ammo = duelist.weapon.data.magazine_size
		brain.clear_target()
		brain.fsm.change(&"idle")
		await _wait(0.3)
		hits.n = 0
		hits.head = 0
		shots.n = 0
		var t0 := Time.get_ticks_msec()
		var first_hit := -1.0
		brain.on_enemy_seen(p)
		while Time.get_ticks_msec() - t0 < 10000:
			# Keep both in place so the distance stays fixed.
			duelist.input_move = Vector2.ZERO
			brain.direct_move = Vector3.ZERO
			brain.nav.stop()
			if first_hit < 0.0 and hits.n > 0:
				first_hit = (Time.get_ticks_msec() - t0) / 1000.0
			await get_tree().physics_frame
		var rate: float = 100.0 * hits.n / maxf(shots.n, 1)
		print("[duel] %4.0fm: shots=%3d hits=%3d (%.0f%%) head=%d first_hit=%.2fs dmg/10s=%.0f" % [
			dist, shots.n, hits.n, rate, hits.head, first_hit, hits.n * 30.0])
	get_tree().quit()


# --------------------------------------------------------------------------
# Screenshots
# --------------------------------------------------------------------------

func _run_screenshots() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var p := Game.player
	var ctrl := p.get_node("PlayerController")
	ctrl.set_process(false)
	ctrl.set_process_unhandled_input(false)
	await _wait(1.5)
	p.aim_pitch = -0.08
	await _wait(0.6)
	await _shot("01_player_tpp")
	# Aim down sights while firing.
	p.input_aim = true
	await _wait(0.5)
	p.input_fire = true
	await _wait(0.12)
	await _shot("02_ads_firing")
	p.input_fire = false
	p.input_aim = false
	p.request_stance(GameCharacter.Stance.PRONE)
	await _wait(1.2)
	await _shot("03_prone")
	p.request_stance(GameCharacter.Stance.STAND)

	# Free cameras for overview shots.
	var cam := Camera3D.new()
	cam.far = 3000.0
	cam.fov = 60.0
	main.session.add_child(cam)
	cam.current = true
	Game.camera = cam
	cam.global_position = Vector3(0, 900, 1150)
	cam.look_at(Vector3(0, 0, 50))
	await _wait(0.8)
	await _shot("04_island_overview")

	var world: GameWorld = Game.world
	var towns := world.get_towns()
	if not towns.is_empty():
		var c: Vector2 = towns[0].center
		var h := world.get_height(c.x, c.y)
		cam.global_position = Vector3(c.x + 55, h + 28, c.y + 55)
		cam.look_at(Vector3(c.x, h + 2, c.y))
		await _wait(0.5)
		await _shot("05_town")
		cam.global_position = Vector3(c.x + 14, h + 1.7, c.y + 3)
		cam.look_at(Vector3(c.x - 10, h + 1.5, c.y - 8))
		await _wait(0.5)
		await _shot("06_street_level")

	# Close-up of a bot (and the player) posing.
	var bot: GameCharacter = null
	for ch in Game.match_manager.alive:
		if not ch.is_player:
			bot = ch
			break
	if bot != null:
		var brain := bot.get_node("BotBrain")
		brain.set_physics_process(false)
		bot.input_move = Vector2.ZERO
		bot.aim_pitch = 0.1
		await _wait(0.4)
		var fwd := Vector3(-sin(bot.aim_yaw), 0, -cos(bot.aim_yaw))
		var right := Vector3(cos(bot.aim_yaw), 0, -sin(bot.aim_yaw))
		cam.global_position = bot.global_position + fwd * 3.2 + right * 1.2 + Vector3(0, 1.5, 0)
		cam.look_at(bot.global_position + Vector3(0, 1.0, 0))
		await _wait(0.4)
		await _shot("07_bot_closeup")
		bot.request_stance(GameCharacter.Stance.CROUCH)
		await _wait(0.8)
		await _shot("08_bot_crouch")
		bot.request_stance(GameCharacter.Stance.PRONE)
		await _wait(1.5)
		cam.global_position = bot.global_position + right * 3.0 + Vector3(0, 1.2, 0)
		cam.look_at(bot.global_position + Vector3(0, 0.3, 0))
		await _wait(0.2)
		await _shot("09_bot_prone")

	# Forest + river views.
	var hm := world.hm
	for k in 200:
		var x := _rng.randf_range(-700, 700)
		var z := _rng.randf_range(-700, 700)
		if world.terrain.sample_forest(x, z) > 0.8 and hm.get_height(x, z) > 5.0 and hm.get_normal(x, z).y > 0.9:
			cam.global_position = Vector3(x, hm.get_height(x, z) + 1.7, z)
			cam.look_at(cam.global_position + Vector3(1, -0.05, 0.3))
			await _wait(0.5)
			await _shot("10_forest")
			break
	if hm.river_points.size() > 40:
		var rp: Vector2 = hm.river_points[40]
		var rq: Vector2 = hm.river_points[44]
		var side := (rq - rp).normalized().orthogonal() * 45.0
		cam.global_position = Vector3(rp.x + side.x, hm.get_height(rp.x + side.x, rp.y + side.y) + 6.0, rp.y + side.y)
		cam.look_at(Vector3(rq.x, 0.0, rq.y))
		await _wait(0.5)
		await _shot("11_river")
	print("[auto] screenshots done")
	get_tree().quit()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	if img == null or img.is_empty():
		print("[auto] screenshot %s: no image (headless renderer?)" % shot_name)
		return
	img.save_png(path)
	print("[auto] saved %s  draw_calls=%d objects=%d primitives=%dk" % [path,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0)])
