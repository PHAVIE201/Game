class_name EndScreen
extends CanvasLayer
## Death / victory screen with match stats and "play again".

signal restart_requested
signal menu_requested

@onready var title_label: Label = $Dim/Panel/VBox/Title
@onready var subtitle_label: Label = $Dim/Panel/VBox/Subtitle
@onready var place_label: Label = $Dim/Panel/VBox/Stats/Place/Value
@onready var kills_label: Label = $Dim/Panel/VBox/Stats/Kills/Value
@onready var damage_label: Label = $Dim/Panel/VBox/Stats/Damage/Value
@onready var time_label: Label = $Dim/Panel/VBox/Stats/Time/Value
@onready var restart_button: Button = $Dim/Panel/VBox/Buttons/Restart
@onready var menu_button: Button = $Dim/Panel/VBox/Buttons/Menu
@onready var quit_button: Button = $Dim/Panel/VBox/Buttons/Quit


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	Events.player_match_result.connect(_on_result)
	restart_button.pressed.connect(func():
		Sfx.play_2d(&"ui_click")
		restart_requested.emit())
	menu_button.pressed.connect(func():
		Sfx.play_2d(&"ui_click")
		menu_requested.emit())
	quit_button.pressed.connect(func(): get_tree().quit())


func _on_result(r: Dictionary) -> void:
	# Let the death / victory moment play before showing the panel.
	await get_tree().create_timer(1.2 if r.won else 2.2, true).timeout
	if not is_inside_tree():
		return
	show_result(r)


func show_result(r: Dictionary) -> void:
	if r.won:
		title_label.text = "CHIẾN THẮNG!"
		title_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.25))
		subtitle_label.text = "Bạn là người sống sót cuối cùng trên đảo.\nThắng lớn - tối nay ăn lẩu!"
	else:
		title_label.text = "BẠN ĐÃ BỊ HẠ GỤC"
		title_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.32))
		if r.killer_name != "":
			var extra := " (trúng đầu)" if r.headshot else ""
			subtitle_label.text = "Bị hạ bởi %s bằng %s%s từ %d m" % [r.killer_name, r.weapon, extra, int(r.distance)]
		else:
			subtitle_label.text = "Bạn đã bị loại khỏi trận đấu."
	place_label.text = "#%d / %d" % [r.placement, r.total]
	kills_label.text = str(r.kills)
	damage_label.text = str(int(r.damage))
	var t := int(r.time_alive)
	time_label.text = "%d:%02d" % [floori(t / 60.0), t % 60]
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	restart_button.grab_focus()


func hide_screen() -> void:
	visible = false
