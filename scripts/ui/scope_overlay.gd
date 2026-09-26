class_name ScopeOverlay
extends Control
## Drawn while looking through a sight: a red dot, or for magnified scopes a
## black mask around the lens with a duplex reticle (mil dots from 4x) and the
## breath bar when holding the breath (Shift).


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var rig := Game.camera_rig as ThirdPersonCamera
	var p := Game.player
	if rig == null or not is_instance_valid(rig) or not rig.scoped or p == null or not is_instance_valid(p):
		return
	var zoom := p.get_scope_zoom()
	var c := size * 0.5
	if zoom < 1.5:
		# Red dot sight: dot + faint housing ring.
		draw_arc(c, 60.0, 0.0, TAU, 48, Color(0, 0, 0, 0.35), 6.0)
		draw_circle(c, 3.2, Color(1.0, 0.15, 0.1, 0.95))
		draw_circle(c, 1.4, Color(1.0, 0.7, 0.6))
		return
	var r := size.y * 0.46
	var far := size.length()
	# Mask outside the lens: ring of quads from the lens edge to far away.
	var n := 64
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		var d0 := Vector2(cos(a0), sin(a0))
		var d1 := Vector2(cos(a1), sin(a1))
		draw_colored_polygon(PackedVector2Array([c + d0 * r, c + d1 * r, c + d1 * far, c + d0 * far]), Color.BLACK)
	draw_arc(c, r, 0.0, TAU, 96, Color(0.05, 0.05, 0.05), 10.0)
	# Duplex reticle: thick posts outside, thin lines in the middle.
	var ink := Color(0.02, 0.02, 0.02, 0.95)
	var gap := r * 0.3
	for dir in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN]:
		draw_line(c + dir * gap, c + dir * r, ink, 5.0)
		draw_line(c + dir * 4.0, c + dir * gap, ink, 1.4)
	draw_line(c + Vector2.UP * 4.0, c + Vector2.UP * r * 0.55, ink, 1.4)
	if zoom >= 3.5:
		# Mil dots for range estimation / holdover.
		for k in range(1, 5):
			for dir in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN]:
				draw_circle(c + dir * gap * k / 5.0, 2.2, ink)
	else:
		draw_arc(c, 10.0, 0.0, TAU, 24, ink, 1.5)
	draw_circle(c, 1.6, Color(0.9, 0.15, 0.1))
	# Breath bar
	if rig.holding_breath or rig.breath < 0.99:
		var w := 160.0
		var bar := Rect2(c + Vector2(-w * 0.5, r * 0.8), Vector2(w, 5.0))
		draw_rect(bar, Color(1, 1, 1, 0.25))
		draw_rect(Rect2(bar.position, Vector2(w * rig.breath, 5.0)), Color(0.85, 0.95, 1.0, 0.9))
