extends Node3D
## Renders every procedural animation pose of CharacterModel into one contact
## sheet image (side view). Needs a real renderer:
##   godot --path . res://tools/pose_gallery.tscn -- <out.png>

const TILE := Vector2i(400, 450)
const COLS := 5

## [label, speed (m/s, forward), strafe (m/s, right), crouch, prone, aim, sprint, air, swim, reload, dead, extras]
## extras (optional): { gun: model id, back: [model ids], bolt: 0..1, swap: 0..1 }
const POSES := [
	["dung yen", 0.0, 0.0, 0, 0, false, false, false, false, -1.0, false],
	["di bo", 1.9, 0.0, 0, 0, false, false, false, false, -1.0, false],
	["chay", 4.8, 0.0, 0, 0, false, false, false, false, -1.0, false],
	["chay nhanh", 6.4, 0.0, 0, 0, false, true, false, false, -1.0, false],
	["di ngang", 0.0, 4.0, 0, 0, false, false, false, false, -1.0, false],
	["lui", -3.5, 0.0, 0, 0, false, false, false, false, -1.0, false],
	["ngam", 0.0, 0.0, 0, 0, true, false, false, false, -1.0, false],
	["nap dan", 0.0, 0.0, 0, 0, false, false, false, false, 0.35, false],
	["ngoi", 0.0, 0.0, 1, 0, false, false, false, false, -1.0, false],
	["ngoi di", 2.4, 0.0, 1, 0, false, false, false, false, -1.0, false],
	["nam", 0.0, 0.0, 0, 1, false, false, false, false, -1.0, false],
	["nam bo", 1.0, 0.0, 0, 1, false, false, false, false, -1.0, false],
	["nhay", 3.0, 0.0, 0, 0, false, false, true, false, -1.0, false],
	["boi", 2.0, 0.0, 0, 0, false, false, false, true, -1.0, false],
	["chet", 0.0, 0.0, 0, 0, false, false, false, false, -1.0, true],
	["tieu lien", 0.0, 0.0, 0, 0, true, false, false, false, -1.0, false, {"gun": &"smg"}],
	["sung san", 0.0, 0.0, 0, 0, false, false, false, false, -1.0, false, {"gun": &"shotgun"}],
	["sung san nap", 0.0, 0.0, 0, 0, false, false, false, false, 0.3, false, {"gun": &"shotgun"}],
	["DMR ngam", 0.0, 0.0, 0, 0, true, false, false, false, -1.0, false, {"gun": &"dmr"}],
	["ban tia", 0.0, 0.0, 0, 0, true, false, false, false, -1.0, false, {"gun": &"sniper"}],
	["keo khoa", 0.0, 0.0, 0, 0, true, false, false, false, -1.0, false, {"gun": &"sniper", "bolt": 0.3}],
	["ban tia nam", 0.0, 0.0, 0, 1, true, false, false, false, -1.0, false, {"gun": &"sniper"}],
	["sung luc", 0.0, 0.0, 0, 0, false, false, false, false, -1.0, false, {"gun": &"pistol", "back": [&"rifle", &"sniper"]}],
	["sung luc ngam", 0.0, 0.0, 0, 0, true, false, false, false, -1.0, false, {"gun": &"pistol"}],
	["sung luc chay", 4.8, 0.0, 0, 0, false, false, false, false, -1.0, false, {"gun": &"pistol"}],
	["tay khong", 1.9, 0.0, 0, 0, false, false, false, false, -1.0, false, {"gun": &"none", "back": [&"smg"]}],
	["tay khong thu", 0.0, 0.0, 0, 0, true, false, false, false, -1.0, false, {"gun": &"none"}],
	["chay tay khong", 6.4, 0.0, 0, 0, false, true, false, false, -1.0, false, {"gun": &"none", "back": [&"shotgun", &"dmr"]}],
	["doi sung", 0.0, 0.0, 0, 0, false, false, false, false, -1.0, false, {"gun": &"rifle", "swap": 0.6}],
	["giap cap 1", 0.0, 0.0, 0, 0, false, false, false, false, -1.0, false, {"helmet": &"helmet_1", "vest": &"vest_1"}],
	["giap cap 2", 2.0, 0.0, 0, 0, true, false, false, false, -1.0, false, {"helmet": &"helmet_2", "vest": &"vest_2", "gun": &"smg"}],
	["giap cap 3", 0.0, 0.0, 1, 0, true, false, false, false, -1.0, false, {"helmet": &"helmet_3", "vest": &"vest_3", "gun": &"dmr"}],
	["bang bo", 1.5, 0.0, 0, 0, false, false, false, false, -1.0, false, {"use": true, "vest": &"vest_2"}],
	["uong nuoc", 0.0, 0.0, 1, 0, false, false, false, false, -1.0, false, {"use": true, "gun": &"none"}],
]

var _cam: Camera3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://poses.png"
	get_window().size = TILE
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.75, 0.85, 0.95)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.7, 0)
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	ground.mesh = pm
	add_child(ground)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	add_child(_cam)
	_cam.current = true

	var sheet := Image.create(TILE.x * COLS, TILE.y * int(ceil(POSES.size() / float(COLS))), false, Image.FORMAT_RGB8)
	for k in POSES.size():
		var pose: Array = POSES[k]
		var model := CharacterModel.new()
		add_child(model)
		var extras: Dictionary = pose[11] if pose.size() > 11 else {}
		model.build(CharacterModel.player_outfit(), extras.get("gun", &"rifle"), false)
		if extras.has("back"):
			var back: Array[StringName] = []
			for b in extras.back:
				back.append(b)
			model.set_back_weapons(back)
		model.bolt_progress = extras.get("bolt", -1.0)
		model.swap_amount = extras.get("swap", 0.0)
		model.set_armor(extras.get("helmet", &""), extras.get("vest", &""))
		model.using_item = extras.get("use", false)
		model.velocity_world = Vector3(float(pose[2]), 0, -float(pose[1]))
		model.crouch_target = float(pose[3])
		model.prone_target = float(pose[4])
		model.aiming = pose[5]
		model.sprinting = pose[6]
		model.in_air = pose[7]
		model.swimming = pose[8]
		model.reload_progress = pose[9]
		if pose[10]:
			model.play_death(Vector3.BACK)
		for f in 100:
			model.animate(1.0 / 60.0)
		# 3/4 side view.
		var target := Vector3(0, 0.8, 0)
		if float(pose[4]) > 0.5 or pose[10]:
			target = Vector3(0, 0.3, 0)
		_cam.global_position = target + Vector3(3.6, 0.9, -1.4)
		_cam.look_at(target)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		img.resize(TILE.x, TILE.y)
		@warning_ignore("integer_division")
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, TILE), Vector2i((k % COLS) * TILE.x, (k / COLS) * TILE.y))
		print("[poses] ", pose[0])
		model.queue_free()
		await get_tree().process_frame
	sheet.save_png(out)
	print("[poses] saved ", out)
	get_tree().quit()
