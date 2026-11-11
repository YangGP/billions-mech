extends Control
## 菜单只选择现有玩法配置；进入战场后由组合根创建独立模拟。

const BATTLE_SCENE: String = "res://scenes/main_3d.tscn"
const SETTINGS: MechFoundationSettings = preload("res://content/development_128.tres")
const MISSIONS: Array[MechFoundationSettings] = [SETTINGS,
	preload("res://content/tutorial_coast.tres"), preload("res://content/validation_river.tres")]
const CAMPAIGN_META: StringName = &"mech_campaign_mode"

var _launching: bool = false
@onready var _home: VBoxContainer = %Home
@onready var _levels: VBoxContainer = %Levels
@onready var _mode: OptionButton = %Mode
@onready var _map_choice: OptionButton = %MapChoice
@onready var _settings: MechSettingsMenu = $Settings


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		var usable: Rect2i = DisplayServer.screen_get_usable_rect()
		var position: Vector2i = get_window().position
		position.x = clampi(position.x, usable.position.x, maxi(usable.position.x, usable.end.x - get_window().size.x))
		position.y = clampi(position.y, usable.position.y, maxi(usable.position.y, usable.end.y - get_window().size.y))
		get_window().position = position
	%Version.text = "开发版本 %s" % ProjectSettings.get_setting("application/config/version")
	%Play.pressed.connect(_show_levels)
	%SettingsButton.pressed.connect(_open_settings)
	%Quit.pressed.connect(get_tree().quit)
	%Back.pressed.connect(_show_home)
	%Start.pressed.connect(_start_selected)
	_mode.item_selected.connect(_update_mission)
	for mission: MechFoundationSettings in MISSIONS:
		_map_choice.add_item(mission.scenario_name)
	_map_choice.item_selected.connect(_select_map)
	_settings.close_requested.connect(_close_settings)
	_update_mission()
	_show_home()
	if get_tree().has_meta(&"mech_show_main_menu"):
		get_tree().remove_meta(&"mech_show_main_menu")
		return
	# 保留已有命令行诊断/战役入口，普通启动只显示菜单，不创建模拟。
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	for flag: String in ["--battle", "--campaign", "--stress", "--perf", "--overview", "--settings"]:
		if arguments.has(flag):
			_mode.select(1 if arguments.has("--campaign") else 0)
			_start_selected.call_deferred()
			break


func _show_levels() -> void:
	_home.hide()
	_levels.show()
	_map_choice.grab_focus()


func _show_home() -> void:
	_levels.hide()
	_home.show()
	%Play.grab_focus()


func _update_mission(_index: int = 0) -> void:
	var settings: MechFoundationSettings = MISSIONS[_map_choice.selected]
	var layout: String = ["四向防守 · 中央基地", "单隘口 · 西岸边缘基地", "双通道 · 东南边缘基地"][_map_choice.selected]
	%MapInfo.text = "正方形战区  /  %s" % layout
	%Objective.text = settings.scenario_brief if not settings.scenario_brief.is_empty() else "建立基地并守住 %d 波攻势，清除末波敌军即可获胜。" % settings.total_waves
	if _mode.selected == 1:
		%Objective.text = "三阶段战役候选配置。发展至主脑 III 与科技 III 后，按 T 请求终波并完成清场。"
	var announce: int = roundi(settings.silence_seconds)
	var release: int = roundi(settings.silence_seconds + settings.wave_announce_seconds)
	var mode_label: String = ["标准防守", "基础训练", "玩法验证"][_map_choice.selected]
	_mode.set_item_text(0, "%s · %d 波生存" % [mode_label, settings.total_waves])
	%MissionInfo.text = "首波：%d:%02d 预告，%d:%02d 出兵。\n开局：%d 算力币 · %d 金属矿 · %d 名侦察兵。\n清除末波敌军获胜；主脑被摧毁则失败。" % [announce / 60, announce % 60, release / 60, release % 60, settings.starting_resources.get(&"coins", 0), settings.starting_resources.get(&"metal_ore", 0), settings.starting_unit_cells.size()]


func _select_map(_index: int) -> void:
	# 新关卡使用各自固定的教学/验证节奏，战役候选仍保留在四隘盆地。
	_mode.select(0)
	_mode.set_item_disabled(1, _map_choice.selected != 0)
	_update_mission()


func _start_selected() -> void:
	if _launching:
		return
	_launching = true
	%Start.disabled = true
	%Status.text = "正在部署战场…"
	get_tree().set_meta(CAMPAIGN_META, _mode.selected == 1)
	get_tree().set_meta(&"mech_session_settings", MISSIONS[_map_choice.selected])
	var error: Error = get_tree().change_scene_to_file(BATTLE_SCENE)
	if error != OK:
		get_tree().remove_meta(CAMPAIGN_META)
		get_tree().remove_meta(&"mech_session_settings")
		_launching = false
		%Start.disabled = false
		%Status.text = "战场加载失败（%s），请重试。" % error_string(error)


func _open_settings() -> void:
	_settings.open()
	# 隐藏底层控件，避免 Tab 导航进入被遮挡的按钮。
	$Layout.hide()


func _close_settings() -> void:
	_settings.close()
	$Layout.show()
	%SettingsButton.grab_focus()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _settings.is_open():
			_close_settings()
		elif _levels.visible:
			_show_home()
		get_viewport().set_input_as_handled()
