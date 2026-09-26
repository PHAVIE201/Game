class_name GameHUD
extends CanvasLayer
## In-game HUD: health, ammo, crosshair, compass, alive counter, kill feed,
## hit markers, damage feedback, center messages and the F3 performance overlay.

const STANCE_NAMES := ["ĐỨNG", "NGỒI", "NẰM"]

@onready var crosshair: Crosshair = $Root/Crosshair
@onready var health_bar: HealthBar = $Root/HealthBar
@onready var stance_label: Label = $Root/StanceLabel
@onready var weapon_label: Label = $Root/AmmoPanel/WeaponName
@onready var ammo_label: Label = $Root/AmmoPanel/Ammo
@onready var mode_label: Label = $Root/AmmoPanel/FireMode
@onready var alive_label: Label = $Root/TopRight/Counters/Alive
@onready var kills_label: Label = $Root/TopRight/Counters/Kills
@onready var kill_feed: KillFeed = $Root/TopRight/KillFeed
@onready var center_label: Label = $Root/CenterMessage
@onready var perf_label: Label = $Root/PerfLabel
@onready var hint_label: Label = $Root/HintLabel
@onready var vignette: TextureRect = $Root/DamageVignette

var _msg_time := 0.0
var _hint_time := 25.0
var _perf_timer := 0.0
var _vignette := 0.0


func _ready() -> void:
	Events.character_damaged.connect(_on_character_damaged)
	Events.character_died.connect(_on_character_died)
	Events.alive_count_changed.connect(_on_alive_count_changed)
	Events.hud_message.connect(show_message)
	center_label.modulate.a = 0.0
	perf_label.visible = Settings.show_fps
	vignette.modulate.a = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_perf"):
		Settings.show_fps = not Settings.show_fps
		Settings.commit()
		perf_label.visible = Settings.show_fps


func show_message(text: String, duration: float) -> void:
	center_label.text = text
	_msg_time = duration
	center_label.modulate.a = 1.0


func _process(delta: float) -> void:
	var p := Game.player
	var has_player := p != null and is_instance_valid(p)
	$Root.visible = has_player
	if not has_player:
		return

	# Ammo / weapon
	var w := p.weapon
	weapon_label.text = w.data.display_name
	ammo_label.text = "%d / %d" % [w.ammo, p.inventory.get_ammo(w.data.ammo_type)]
	ammo_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3) if w.ammo <= 5 else Color.WHITE)
	var mode := "TỰ ĐỘNG" if w.fire_mode == WeaponData.FireMode.AUTO else "PHÁT MỘT"
	mode_label.text = ("ĐANG NẠP ĐẠN..." if w.is_reloading() else mode)
	stance_label.text = "BƠI" if p.is_swimming else STANCE_NAMES[p.stance]

	kills_label.text = "HẠ GỤC  %d" % p.kills
	crosshair.visible = not p.is_dead
	health_bar.visible = not p.is_dead

	# Damage vignette (also pulses gently at low health).
	_vignette = move_toward(_vignette, 0.0, delta * 1.5)
	var low := 0.0
	if not p.is_dead and p.health < 30.0:
		low = 0.25 + 0.1 * sin(Time.get_ticks_msec() * 0.006)
	vignette.modulate.a = maxf(_vignette, low)

	# Center message fade.
	if _msg_time > 0.0:
		_msg_time -= delta
		center_label.modulate.a = clampf(_msg_time / 0.6, 0.0, 1.0)

	# Controls hint fades out after a while.
	if _hint_time > 0.0:
		_hint_time -= delta
		hint_label.modulate.a = clampf(_hint_time / 2.0, 0.0, 1.0)

	if perf_label.visible:
		_perf_timer -= delta
		if _perf_timer <= 0.0:
			_perf_timer = 0.25
			_update_perf()


func _update_perf() -> void:
	var alive := Game.match_manager.get_alive_count() if Game.match_manager != null else 0
	var bullets := Game.projectiles.get_bullet_count() if Game.projectiles != null else 0
	perf_label.text = "FPS %d  (%.1f ms)\nVẽ: %d draw call, %d vật thể, %dk tam giác\nVật lý: %.1f ms   Đạn: %d   Còn sống: %d\nBộ nhớ: %.0f MB   VRAM: %.0f MB" % [
		Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0),
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		bullets, alive,
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
	]


func _on_character_damaged(victim_node: Node, info_ref: RefCounted) -> void:
	var info := info_ref as DamageInfo
	var victim := victim_node as GameCharacter
	if info == null or victim == null:
		return
	if info.attacker == Game.player and victim != Game.player:
		crosshair.show_hit(info.is_headshot(), false)
		if info.is_headshot():
			Sfx.play_2d(&"hit_head", -4.0)
		else:
			Sfx.play_2d(&"hitmarker", -6.0)
	elif victim == Game.player:
		_vignette = minf(_vignette + 0.25 + info.amount / 100.0, 0.8)
		Sfx.play_2d(&"hit_body", -2.0)
		var attacker := info.attacker as GameCharacter
		if attacker != null:
			crosshair.add_damage_mark(attacker.global_position)


func _on_character_died(victim_node: Node, info_ref: RefCounted) -> void:
	var victim := victim_node as GameCharacter
	var info := info_ref as DamageInfo
	if victim == null:
		return
	var killer_name := ""
	var weapon := ""
	var headshot := false
	var killer: GameCharacter = null
	if info != null:
		killer = info.attacker as GameCharacter
		weapon = info.weapon_name
		headshot = info.is_headshot()
	if killer != null:
		killer_name = killer.display_name
	var involves := victim == Game.player or killer == Game.player
	kill_feed.add_entry(killer_name, victim.display_name, weapon, headshot, involves)
	if killer == Game.player and victim != Game.player:
		crosshair.show_hit(headshot, true)
		Sfx.play_2d(&"kill", -3.0)
		show_message("Bạn đã hạ gục %s%s" % [victim.display_name, " (trúng đầu)" if headshot else ""], 2.5)


func _on_alive_count_changed(alive: int, _total: int) -> void:
	alive_label.text = "CÒN SỐNG  %d" % alive
