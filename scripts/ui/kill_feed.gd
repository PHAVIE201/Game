class_name KillFeed
extends VBoxContainer
## Top-right list of recent eliminations.

const MAX_ENTRIES := 5
const LIFETIME := 7.0


func add_entry(killer: String, victim: String, weapon: String, headshot: bool, involves_player: bool) -> void:
	var label := Label.new()
	var how := weapon if weapon != "" else "?"
	if headshot:
		how += ", trúng đầu"
	if killer == "":
		label.text = "%s đã bị loại" % victim
	else:
		label.text = "%s  [%s]  %s" % [killer, how, victim]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3) if involves_player else Color(0.95, 0.95, 0.95))
	add_child(label)
	while get_child_count() > MAX_ENTRIES:
		var old := get_child(0)
		remove_child(old)
		old.queue_free()
	var tw := label.create_tween()
	tw.tween_interval(LIFETIME)
	tw.tween_property(label, "modulate:a", 0.0, 0.8)
	tw.tween_callback(label.queue_free)
