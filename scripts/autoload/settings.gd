extends Node
## Persistent user settings (autoload "Settings"), stored in user://settings.cfg.
##
## Graphics presets are applied here so every scene uses the same values.

signal changed

enum Quality { LOW, MEDIUM, HIGH }

const SAVE_PATH := "user://settings.cfg"

## Mouse sensitivity multiplier (1.0 = default).
var mouse_sensitivity := 1.0
var invert_y := false
var fov := 75.0
var graphics_quality: int = Quality.MEDIUM
var master_volume := 0.8
var show_fps := false

## Last used match options (remembered by the main menu).
var last_bot_count := 8
var last_seed := 0


func _ready() -> void:
	load_settings()
	_apply_audio()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	mouse_sensitivity = cfg.get_value("input", "mouse_sensitivity", mouse_sensitivity)
	invert_y = cfg.get_value("input", "invert_y", invert_y)
	fov = cfg.get_value("video", "fov", fov)
	graphics_quality = cfg.get_value("video", "quality", graphics_quality)
	show_fps = cfg.get_value("video", "show_fps", show_fps)
	master_volume = cfg.get_value("audio", "master_volume", master_volume)
	last_bot_count = cfg.get_value("match", "bot_count", last_bot_count)
	last_seed = cfg.get_value("match", "seed", last_seed)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("input", "invert_y", invert_y)
	cfg.set_value("video", "fov", fov)
	cfg.set_value("video", "quality", graphics_quality)
	cfg.set_value("video", "show_fps", show_fps)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("match", "bot_count", last_bot_count)
	cfg.set_value("match", "seed", last_seed)
	cfg.save(SAVE_PATH)


## Call after changing any value: saves, re-applies and notifies listeners.
func commit() -> void:
	save_settings()
	_apply_audio()
	apply_viewport(get_viewport())
	changed.emit()


func _apply_audio() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(master_volume, 0.0001)))


# --------------------------------------------------------------------------
# Graphics presets. Values are read by GameWorld (shadows, vegetation range...)
# --------------------------------------------------------------------------

## Render scale for the 3D viewport (lower = faster, blurrier).
func get_render_scale() -> float:
	match graphics_quality:
		Quality.LOW:
			return 0.77
		_:
			return 1.0


## Distance multiplier for vegetation / LOD visibility ranges.
func get_view_distance_scale() -> float:
	match graphics_quality:
		Quality.LOW:
			return 0.65
		Quality.HIGH:
			return 1.35
		_:
			return 1.0


func get_shadow_distance() -> float:
	match graphics_quality:
		Quality.LOW:
			return 60.0
		Quality.HIGH:
			return 200.0
		_:
			return 120.0


func get_shadow_mode() -> DirectionalLight3D.ShadowMode:
	match graphics_quality:
		Quality.LOW:
			return DirectionalLight3D.SHADOW_ORTHOGONAL
		Quality.HIGH:
			return DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		_:
			return DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS


func use_ssao() -> bool:
	return graphics_quality == Quality.HIGH


func apply_viewport(vp: Viewport) -> void:
	if vp == null:
		return
	var render_scale := get_render_scale()
	# FSR 1.0 upscaling looks much sharper than bilinear at the same cost.
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if render_scale < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = render_scale
	match graphics_quality:
		Quality.LOW:
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			vp.msaa_3d = Viewport.MSAA_DISABLED
		Quality.HIGH:
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA
			vp.msaa_3d = Viewport.MSAA_DISABLED
		_:
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			vp.msaa_3d = Viewport.MSAA_DISABLED


func quality_name(q: int) -> String:
	match q:
		Quality.LOW:
			return "Thấp"
		Quality.HIGH:
			return "Cao"
		_:
			return "Trung bình"
