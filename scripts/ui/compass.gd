class_name Compass
extends Control
## Horizontal compass strip (top of the screen). North (B) = -Z.
## Letters are Vietnamese: B = Bắc (N), Đ = Đông (E), N = Nam (S), T = Tây (W).

const SPAN_DEG := 160.0
const LABELS := {0: "B", 45: "ĐB", 90: "Đ", 135: "ĐN", 180: "N", 225: "TN", 270: "T", 315: "TB"}

var _heading := 0.0


func _process(_delta: float) -> void:
	var cam := Game.camera
	if cam == null or not is_instance_valid(cam):
		return
	var fwd := -cam.global_transform.basis.z
	var h := fposmod(rad_to_deg(atan2(fwd.x, -fwd.z)), 360.0)
	if absf(h - _heading) > 0.05:
		_heading = h
		queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.28))
	var half := SPAN_DEG * 0.5
	for deg in range(0, 360, 5):
		var diff := wrapf(deg - _heading, -180.0, 180.0)
		if absf(diff) > half:
			continue
		var x := w * 0.5 + diff / half * (w * 0.5)
		var fade := 1.0 - pow(absf(diff) / half, 3.0)
		if deg % 45 == 0:
			var text: String = LABELS[deg]
			var col := Color(1.0, 0.82, 0.3, fade) if deg == 0 else Color(1, 1, 1, fade)
			draw_string(font, Vector2(x - 30.0, h * 0.62), text, HORIZONTAL_ALIGNMENT_CENTER, 60.0, 22, col)
			draw_line(Vector2(x, h - 10.0), Vector2(x, h), Color(1, 1, 1, fade), 2.0)
		elif deg % 15 == 0:
			draw_string(font, Vector2(x - 20.0, h * 0.58), str(deg), HORIZONTAL_ALIGNMENT_CENTER, 40.0, 13, Color(1, 1, 1, 0.75 * fade))
			draw_line(Vector2(x, h - 8.0), Vector2(x, h), Color(1, 1, 1, 0.8 * fade), 1.5)
		else:
			draw_line(Vector2(x, h - 5.0), Vector2(x, h), Color(1, 1, 1, 0.5 * fade), 1.0)
	# Center marker + numeric heading.
	var cx := w * 0.5
	draw_colored_polygon(PackedVector2Array([Vector2(cx - 7, h + 9), Vector2(cx + 7, h + 9), Vector2(cx, h + 1)]), Color(1.0, 0.82, 0.3))
	draw_string(font, Vector2(cx - 30.0, h + 28.0), "%03d" % int(round(_heading)) , HORIZONTAL_ALIGNMENT_CENTER, 60.0, 16, Color.WHITE)
