class_name MechSettingsMenu
extends CanvasLayer
## 纯视图偏好设置；模拟暂停与输入归属权保留在 main。

signal close_requested
signal settings_applied(preferences: Dictionary)

const CONFIG_PATH: String = "user://settings.cfg"
## 可选帧率上限；0 表示不限制。
const FRAME_CAPS: Array[int] = [60, 120, 144, 240, 0]
const DEFAULTS: Dictionary = {
	"fullscreen": false, "vsync": true, "max_fps": 120,
	"pan_speed": 1.0, "zoom_speed": 1.0, "edge_scroll": true,
}

var _preferences: Dictionary = DEFAULTS.duplicate()
var _load_warning: String = ""
@onready var _root: Control = $Root
@onready var _fullscreen: OptionButton = %WindowMode
@onready var _vsync: CheckButton = %VSync
@onready var _frame_cap: OptionButton = %FrameCap
@onready var _pan_speed: HSlider = %PanSpeed
@onready var _zoom_speed: HSlider = %ZoomSpeed
@onready var _edge_scroll: CheckButton = %EdgeScroll
@onready var _status: Label = %Status


func _ready() -> void:
	_root.hide()
	var config := ConfigFile.new()
	var error: Error = config.load(CONFIG_PATH)
	if error == OK:
		for key: String in DEFAULTS:
			var value: Variant = config.get_value("preferences", key, DEFAULTS[key])
			if typeof(value) == typeof(DEFAULTS[key]):
				_preferences[key] = value
		_preferences["max_fps"] = _preferences["max_fps"] if _preferences["max_fps"] in FRAME_CAPS else DEFAULTS["max_fps"]
		for key: String in ["pan_speed", "zoom_speed"]:
			var value: float = _preferences[key]
			_preferences[key] = clampf(value, 0.5, 2.0) if is_finite(value) else DEFAULTS[key]
	elif error != ERR_FILE_NOT_FOUND:
		_load_warning = "设置文件无法读取，已使用默认值。应用后将重新保存。"
	_apply_runtime()
	%Apply.pressed.connect(_apply_and_close)
	%Cancel.pressed.connect(close_requested.emit)
	%Defaults.pressed.connect(_restore_defaults)
	_pan_speed.value_changed.connect(_update_value_labels)
	_zoom_speed.value_changed.connect(_update_value_labels)
	_vsync.toggled.connect(_update_toggle_labels)
	_edge_scroll.toggled.connect(_update_toggle_labels)


## 当前生效偏好的拷贝。
func preferences() -> Dictionary:
	return _preferences.duplicate()


func is_open() -> bool:
	return _root.visible


func open() -> void:
	_populate(_preferences)
	_status.text = _load_warning
	_root.show()
	_fullscreen.grab_focus()


func close() -> void:
	_root.hide()
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null and _root.is_ancestor_of(focused):
		focused.release_focus()


func _populate(values: Dictionary) -> void:
	_fullscreen.select(1 if values["fullscreen"] else 0)
	_vsync.set_pressed_no_signal(values["vsync"])
	_frame_cap.select(FRAME_CAPS.find(values["max_fps"]))
	_pan_speed.set_value_no_signal(values["pan_speed"])
	_zoom_speed.set_value_no_signal(values["zoom_speed"])
	_edge_scroll.set_pressed_no_signal(values["edge_scroll"])
	_update_value_labels()
	_update_toggle_labels()


func _update_value_labels(_value: float = 0.0) -> void:
	%PanValue.text = "%d%%" % roundi(_pan_speed.value * 100.0)
	%ZoomValue.text = "%d%%" % roundi(_zoom_speed.value * 100.0)


func _update_toggle_labels(_pressed: bool = false) -> void:
	_vsync.text = "开启" if _vsync.button_pressed else "关闭"
	_edge_scroll.text = "开启" if _edge_scroll.button_pressed else "关闭"


func _restore_defaults() -> void:
	_populate(DEFAULTS)
	_status.text = "已恢复默认选项，点击“应用并返回”生效。"


## 应用并保存设置；写盘失败时不生效并提示用户。
func _apply_and_close() -> void:
	var draft: Dictionary = {
		"fullscreen": _fullscreen.selected == 1,
		"vsync": _vsync.button_pressed,
		"max_fps": FRAME_CAPS[_frame_cap.selected],
		"pan_speed": _pan_speed.value,
		"zoom_speed": _zoom_speed.value,
		"edge_scroll": _edge_scroll.button_pressed,
	}
	var config := ConfigFile.new()
	for key: String in draft:
		config.set_value("preferences", key, draft[key])
	var error: Error = config.save(CONFIG_PATH)
	if error != OK:
		_status.text = "保存失败（%s），设置尚未应用。请检查用户目录写入权限后重试。" % error_string(error)
		return
	_preferences = draft
	_load_warning = ""
	_apply_runtime()
	settings_applied.emit(preferences())
	close_requested.emit()


## 把偏好应用到引擎（帧率、全屏、垂直同步）；headless 环境跳过窗口设置。
func _apply_runtime() -> void:
	Engine.max_fps = _preferences["max_fps"]
	if DisplayServer.get_name() == "headless":
		return
	var mode: int = DisplayServer.window_get_mode()
	var fullscreen: bool = mode in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	if _preferences["fullscreen"] != fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if _preferences["fullscreen"] else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if _preferences["vsync"] else DisplayServer.VSYNC_DISABLED)
