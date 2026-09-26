class_name InventoryScreen
extends CanvasLayer
## Tab screen: items on the ground nearby, backpack contents with the weight
## bar, and equipment (weapon slots, backpack). Built in code; every action
## goes through LootManager so the rules are the same as for the F key.

const COL_W := 360.0

var _ground_box: VBoxContainer
var _bag_box: VBoxContainer
var _equip_box: VBoxContainer
var _weight_bar: ProgressBar
var _weight_label: Label
var _dirty := true
var _poll := 0.0
var _ground_key: Array = []


func _ready() -> void:
	layer = 5
	visible = false
	_build()
	Events.character_died.connect(func(v, _i):
		if v == Game.player:
			close())


func is_open() -> bool:
	return visible


func open() -> void:
	var p := Game.player
	if p == null or p.is_dead or get_tree().paused:
		return
	visible = true
	_dirty = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.play_2d(&"ui_click", -10.0)


func close() -> void:
	if not visible:
		return
	visible = false
	if Game.player != null and not Game.player.is_dead and not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		if visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	var p := Game.player
	if p == null or not is_instance_valid(p) or p.is_dead:
		close()
		return
	_poll -= delta
	if _poll <= 0.0:
		_poll = 0.2
		# Rebuild when what lies around or what we carry changed.
		var key := []
		if Game.loot != null:
			for it in Game.loot.reachable(p):
				key.append(it.get_instance_id())
				key.append(it.count)
		key.append(p.inventory.items.hash())
		key.append(p.inventory.backpack)
		key.append(p.inventory.helmet)
		key.append(p.inventory.vest)
		key.append(p.active_slot)
		for w in p.slots:
			key.append(w.get_instance_id() if w != null else 0)
			key.append(w.ammo if w != null else 0)
			key.append(w.scope if w != null else &"")
		if key != _ground_key:
			_ground_key = key
			_dirty = true
	if _dirty:
		_dirty = false
		_refresh()


# --------------------------------------------------------------------------
# Layout
# --------------------------------------------------------------------------

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.08, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	center.add_child(outer)

	var title := Label.new()
	title.text = "TÚI ĐỒ"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(title)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	outer.add_child(cols)
	_ground_box = _column(cols, "MẶT ĐẤT")
	var bag_col := _column(cols, "BALO")
	_weight_label = Label.new()
	_weight_label.add_theme_font_size_override("font_size", 15)
	bag_col.add_child(_weight_label)
	_weight_bar = ProgressBar.new()
	_weight_bar.show_percentage = false
	_weight_bar.custom_minimum_size = Vector2(COL_W - 20, 10)
	bag_col.add_child(_weight_bar)
	_bag_box = VBoxContainer.new()
	_bag_box.add_theme_constant_override("separation", 4)
	bag_col.add_child(_bag_box)
	_equip_box = _column(cols, "TRANG BỊ")

	var hint := Label.new()
	hint.text = "Nhặt / Bỏ bằng các nút. Tab hoặc Esc để đóng. Có thể nhặt nhanh bằng phím F khi nhìn vào đồ."
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(hint)

	var close_btn := Button.new()
	close_btn.text = "ĐÓNG"
	close_btn.custom_minimum_size = Vector2(200, 0)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(close)
	outer.add_child(close_btn)


func _column(parent: Control, heading: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(COL_W, 520)
	parent.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var h := Label.new()
	h.text = heading
	h.add_theme_font_size_override("font_size", 20)
	h.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
	v.add_child(h)
	var sep := HSeparator.new()
	v.add_child(sep)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	return list


## One line: text + up to two buttons.
func _row(parent: Control, text: String, color: Color, actions: Array) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	parent.add_child(h)
	var l := Label.new()
	l.text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", color)
	h.add_child(l)
	for a in actions:
		var b := Button.new()
		b.text = a[0]
		b.add_theme_font_size_override("font_size", 14)
		b.focus_mode = Control.FOCUS_NONE
		var cb: Callable = a[1]
		b.pressed.connect(func():
			Sfx.play_2d(&"ui_click", -10.0)
			cb.call()
			_dirty = true)
		h.add_child(b)


func _refresh() -> void:
	var p := Game.player
	if p == null or Game.loot == null:
		return
	for box in [_ground_box, _bag_box, _equip_box]:
		for ch in box.get_children():
			ch.queue_free()

	# Ground
	var near := Game.loot.reachable(p)
	if near.is_empty():
		_row(_ground_box, "(không có gì gần đây)", Color(1, 1, 1, 0.4), [])
	for it in near:
		var pick := it
		_row(_ground_box, it.label(), _kind_color(it.id), [["Nhặt", func(): Game.loot.take(p, pick)]])

	# Backpack
	var inv := p.inventory
	var used := inv.used_weight()
	var cap := inv.capacity()
	_weight_label.text = "Sức chứa: %d / %d" % [roundi(used), roundi(cap)]
	_weight_bar.max_value = cap
	_weight_bar.value = used
	var ids := inv.items.keys()
	ids.sort_custom(func(a, b): return ItemDB.kind_of(a) < ItemDB.kind_of(b) or (ItemDB.kind_of(a) == ItemDB.kind_of(b) and String(a) < String(b)))
	if ids.is_empty():
		_row(_bag_box, "(trống)", Color(1, 1, 1, 0.4), [])
	for id in ids:
		var item_id: StringName = id
		var n := inv.get_count(item_id)
		var actions := []
		if ItemDB.kind_of(item_id) == ItemDB.Kind.SCOPE:
			for k in GameCharacter.SLOT_COUNT:
				var w := p.slots[k]
				var slot := k
				if w != null and w.can_mount(item_id):
					actions.append(["Gắn %d" % (k + 1), func(): Game.loot.mount_from_bag(p, slot, item_id)])
		if ItemDB.is_consumable(item_id):
			actions.append(["Dùng", func():
				if p.use_item(item_id):
					close()])
		if ItemDB.kind_of(item_id) == ItemDB.Kind.AMMO and n > ItemDB.stack_of(item_id):
			var part := ItemDB.stack_of(item_id)
			actions.append(["Bỏ %d" % part, func(): Game.loot.drop_item(p, item_id, part)])
		actions.append(["Bỏ", func(): Game.loot.drop_item(p, item_id, n)])
		_row(_bag_box, "%s ×%d" % [ItemDB.display_name(item_id), n], _kind_color(item_id), actions)

	# Equipment
	var names := ["Súng chính 1", "Súng chính 2", "Súng lục"]
	for k in GameCharacter.SLOT_COUNT:
		var w := p.slots[k]
		var slot := k
		if w == null:
			_row(_equip_box, "%d. %s: —" % [k + 1, names[k]], Color(1, 1, 1, 0.4), [])
			continue
		var reserve := inv.get_ammo(w.data.ammo_type)
		var text := "%d. %s  %d/%d" % [k + 1, w.data.display_name, w.ammo, reserve]
		if w.scope != &"":
			text += "  + " + ItemDB.scope_tag(w.scope)
		var col := Color(1.0, 0.85, 0.4) if k == p.active_slot else Color.WHITE
		var actions := []
		if k != p.active_slot:
			actions.append(["Cầm", func(): p.equip_slot(slot)])
		if w.scope != &"":
			actions.append(["Tháo ống", func(): Game.loot.unmount_to_bag(p, slot)])
		actions.append(["Bỏ", func(): Game.loot.drop_weapon(p, slot)])
		_row(_equip_box, text, col, actions)
	var sep := HSeparator.new()
	_equip_box.add_child(sep)
	for is_vest in [false, true]:
		var id := inv.vest if is_vest else inv.helmet
		var vest_flag: bool = is_vest
		if id == &"":
			_row(_equip_box, ("Áo giáp" if is_vest else "Mũ") + ": —", Color(1, 1, 1, 0.4), [])
		else:
			var text := "%s (%d%%)" % [ItemDB.display_name(id), roundi(inv.armor_ratio(is_vest) * 100.0)]
			_row(_equip_box, text, _kind_color(id), [["Bỏ", func(): Game.loot.drop_armor(p, vest_flag)]])
	if inv.backpack != &"":
		_row(_equip_box, ItemDB.display_name(inv.backpack), _kind_color(inv.backpack), [["Bỏ", func(): Game.loot.drop_backpack(p)]])
	else:
		_row(_equip_box, "Balo: —", Color(1, 1, 1, 0.4), [])


static func _kind_color(id: StringName) -> Color:
	match ItemDB.kind_of(id):
		ItemDB.Kind.WEAPON:
			return Color(1.0, 0.9, 0.7)
		ItemDB.Kind.AMMO:
			return Color(0.85, 0.92, 0.7)
		ItemDB.Kind.BACKPACK, ItemDB.Kind.HELMET, ItemDB.Kind.VEST:
			return Color(0.7, 0.85, 1.0)
		ItemDB.Kind.HEAL, ItemDB.Kind.BOOST:
			return Color(0.75, 1.0, 0.75)
		_:
			return Color.WHITE
