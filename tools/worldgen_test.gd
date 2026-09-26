extends Node
## Headless check: generates the island and writes a top-down map PNG.
## Usage: godot --headless --path . res://tools/worldgen_test.tscn -- [seed] [out.png]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var map_seed := int(args[0]) if args.size() > 0 else 1337
	var out := args[1] if args.size() > 1 else "user://map.png"
	var world := GameWorld.new()
	add_child(world)
	await world.generate(map_seed)
	var t0 := Time.get_ticks_msec()
	var img := world.make_map_image(512)
	img.save_png(out)
	print("[worldgen_test] map image in %d ms, saved %s" % [Time.get_ticks_msec() - t0, out])
	get_tree().quit()
