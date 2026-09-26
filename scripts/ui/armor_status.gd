class_name ArmorStatus
extends Control
## Helmet / vest indicators next to the health bar (level + remaining durability).

var _state: Array = []


func _process(_delta: float) -> void:
	var p := Game.player
	if p == null or not is_instance_valid(p):
		return
	var inv := p.inventory
	var st := [inv.helmet, snappedf(inv.armor_ratio(false), 0.02), inv.vest, snappedf(inv.armor_ratio(true), 0.02), inv.backpack]
	if st != _state:
		_state = st
		queue_redraw()


func _draw() -> void:
	var p := Game.player
	if p == null or not is_instance_valid(p):
		return
	var inv := p.inventory
	var font := get_theme_default_font()
	var entries := [["MŨ", inv.helmet, inv.armor_ratio(false)], ["GIÁP", inv.vest, inv.armor_ratio(true)], ["BALO", inv.backpack, 1.0]]
	var x := 0.0
	for e in entries:
		var id: StringName = e[1]
		var w := 54.0
		var r := Rect2(x, 0, w, size.y)
		draw_rect(r, Color(0, 0, 0, 0.4))
		if id == &"":
			draw_string(font, Vector2(x, size.y * 0.62), e[0], HORIZONTAL_ALIGNMENT_CENTER, w, 12, Color(1, 1, 1, 0.3))
		else:
			var ratio: float = e[2]
			var col := Color(0.55, 0.85, 1.0) if ratio > 0.35 else Color(1.0, 0.55, 0.35)
			draw_rect(Rect2(x, size.y - 4.0, w * ratio, 4.0), col)
			draw_string(font, Vector2(x, size.y * 0.45), e[0], HORIZONTAL_ALIGNMENT_CENTER, w, 11, Color(1, 1, 1, 0.8))
			draw_string(font, Vector2(x, size.y * 0.45 + 15.0), "cấp %d" % ItemDB.level_of(id), HORIZONTAL_ALIGNMENT_CENTER, w, 13, Color.WHITE)
		x += w + 5.0
