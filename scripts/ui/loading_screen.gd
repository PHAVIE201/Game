class_name LoadingScreen
extends CanvasLayer
## Full screen loading overlay fed by Events.world_generation_progress.

@onready var status_label: Label = $Bg/Center/VBox/Status
@onready var bar: ProgressBar = $Bg/Center/VBox/Bar
@onready var tip_label: Label = $Bg/Center/VBox/Tip

const TIPS := [
	"Mẹo: nằm xuống (Z) giúp giảm độ giật và khó bị phát hiện hơn.",
	"Mẹo: bắn trúng đầu gây sát thương gấp đôi.",
	"Mẹo: tiếng súng có thể khiến bot tìm đến bạn.",
	"Mẹo: giữ chuột phải để ngắm, đạn sẽ chụm hơn.",
	"Mẹo: đạn bay có độ rơi - ngắm cao hơn một chút khi bắn xa.",
	"Mẹo: nhấn F3 để xem FPS và thông số hiệu năng.",
]


func _ready() -> void:
	visible = false
	Events.world_generation_progress.connect(_on_progress)


func show_loading() -> void:
	bar.value = 0.0
	status_label.text = "Đang chuẩn bị..."
	tip_label.text = TIPS[randi() % TIPS.size()]
	visible = true


func hide_loading() -> void:
	visible = false


func _on_progress(step: String, progress: float) -> void:
	status_label.text = step
	bar.value = progress * 100.0
