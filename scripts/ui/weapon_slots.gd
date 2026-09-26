class_name WeaponSlots
extends Control
## Bottom-right list of carried weapons (1 / 2 / 3), the active one highlighted.

const ROW_H := 26.0
const KEYS := ["1", "2", "3"]

var _state: Array = []


func _process(_delta: float) -> void:
	var p := Game.player
	if p == null or not is_instance_valid(p):
		return
	var st := [p.active_slot]
	for w in p.slots:
		if w != null:
			st.append([w.data.display_name, w.ammo, w.scope])
		else:
			st.append(null)
	st.append(p.inventory.get_count(&"grenade_frag"))
	st.append(p.inventory.get_count(&"grenade_smoke"))
	if st != _state:
		_state = st
		queue_redraw()


func _draw() -> void:
	var p := Game.player
	if p == null or not is_instance_valid(p):
		return
	var font := get_theme_default_font()
	var w := size.x
	for k in GameCharacter.SLOT_COUNT:
		var y := k * (ROW_H + 4.0)
		var weapon := p.slots[k]
		var active := k == p.active_slot
		var bg := Color(0, 0, 0, 0.5) if active else Color(0, 0, 0, 0.28)
		draw_rect(Rect2(0, y, w, ROW_H), bg)
		if active:
			draw_rect(Rect2(0, y, 4, ROW_H), Color(1.0, 0.82, 0.3))
		var col := Color(1.0, 0.85, 0.4) if active else Color(1, 1, 1, 0.75)
		draw_string(font, Vector2(10, y + 19), KEYS[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.55))
		if weapon == null:
			draw_string(font, Vector2(32, y + 19), "—", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.35))
			continue
		var label := weapon.data.display_name
		if weapon.scope != &"":
			label += "  [" + ItemDB.scope_tag(weapon.scope) + "]"
		draw_string(font, Vector2(32, y + 19), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)
		draw_string(font, Vector2(w - 70, y + 19), str(weapon.ammo), HORIZONTAL_ALIGNMENT_RIGHT, 60, 16, col)
	# Throwables under the weapons.
	var ty := GameCharacter.SLOT_COUNT * (ROW_H + 4.0) + 16.0
	var frags := p.inventory.get_count(&"grenade_frag")
	var smokes := p.inventory.get_count(&"grenade_smoke")
	var text := "G  Lựu đạn ×%d      T  Bom khói ×%d" % [frags, smokes]
	draw_string(font, Vector2(4, ty), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.8 if frags + smokes > 0 else 0.35))
