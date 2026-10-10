extends Node
## 设置系统无头测试：默认值 / 持久化 roundtrip / 脏数据容错 / 切换 / 面板 UI 同步。
##   godot --headless --path . res://tests/settings_test.tscn
## settings.json 开跑前备份、结束恢复——不碰用户已有设置。

const SAVE_PATH := "user://settings.json"

var _fails := 0
var _backup := ""
var _had := false


func check(case_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS  " + case_name)
	else:
		_fails += 1
		print("FAIL  %s  %s" % [case_name, detail])


func _ready() -> void:
	await get_tree().process_frame
	_had = FileAccess.file_exists(SAVE_PATH)
	if _had:
		var bf := FileAccess.open(SAVE_PATH, FileAccess.READ)
		_backup = bf.get_as_text()
		bf.close()
	print("settings_test 开始（已有设置已备份=%s）" % _had)
	await _run()
	if _had:
		var wf := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		wf.store_string(_backup)
		wf.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	print("---")
	print("settings_test 结果：%d 项失败" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


func _write_settings(text: String) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _run() -> void:
	# T0 干净基线
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	Settings._load()
	check("T0 无设置文件时回默认", Settings.get_value("display_mode") == Settings.DisplayMode.BORDERLESS_FULLSCREEN
		and bool(Settings.get_value("vsync")) and is_equal_approx(float(Settings.get_value("master_volume")), 0.8))

	# T1 改值即时落盘
	Settings.set_value("display_mode", Settings.DisplayMode.WINDOWED)
	Settings.set_value("window_resolution", 0)
	Settings.set_value("master_volume", 0.5)
	Settings.set_value("fx_screen_shake", false)
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	check("T1 四项改动全部落盘",
		int(data.get("display_mode", -1)) == 1 and int(data.get("window_resolution", -1)) == 0
		and is_equal_approx(float(data.get("master_volume", 0.0)), 0.5) and not bool(data.get("fx_screen_shake", true)))

	# T2 重载回读（模拟重启）
	Settings.values = Settings.DEFAULTS.duplicate()  # 先清回默认，再从盘恢复
	Settings._load()
	check("T2 重载后窗口模式/分辨率/音量/震屏保留",
		Settings.get_value("display_mode") == Settings.DisplayMode.WINDOWED
		and int(Settings.get_value("window_resolution")) == 0
		and is_equal_approx(float(Settings.get_value("master_volume")), 0.5)
		and not bool(Settings.get_value("fx_screen_shake")))

	# T3 脏数据容错：损坏 JSON → 回默认
	_write_settings("{ 不是 json")
	Settings._load()
	check("T3 损坏设置文件回退默认", Settings.get_value("display_mode") == Settings.DisplayMode.BORDERLESS_FULLSCREEN)

	# T4 未知键与类型过滤
	_write_settings('{"unknown_key": 42, "vsync": "yes", "display_mode": 1}')
	Settings._load()
	check("T4 未知键被忽略 / 类型不符被忽略 / 合法键收下",
		not Settings.values.has("unknown_key") and bool(Settings.get_value("vsync")) == true
		and Settings.get_value("display_mode") == Settings.DisplayMode.WINDOWED)

	# T5 切换全屏（先归位全屏，再验证 toggle 两个方向）
	Settings._load()
	Settings.set_value("display_mode", Settings.DisplayMode.BORDERLESS_FULLSCREEN)
	Settings.toggle_fullscreen()
	check("T5 全屏 → 窗口切换", Settings.get_value("display_mode") == Settings.DisplayMode.WINDOWED)
	Settings.toggle_fullscreen()
	check("T5 窗口 → 全屏切回", Settings.get_value("display_mode") == Settings.DisplayMode.BORDERLESS_FULLSCREEN)

	# T6 应用调用不崩（headless DisplayServer 为空实现，调用应安全）
	Settings.apply_display()
	Settings.apply_audio()
	check("T6 apply_display/apply_audio 无异常", true)

	# T7 面板 UI 与 Settings 同步
	var overlay: CanvasLayer = load("res://scenes/settings/settings_overlay.tscn").instantiate()
	add_child(overlay)
	await get_tree().process_frame
	overlay.open()
	await get_tree().process_frame
	check("T7 open 后可见", overlay.visible)
	if OS.get_cmdline_user_args().has("--capture-settings"):
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://tests/cap_settings_panel.png")
		print("[capture] settings panel saved")
	var mode_opt: OptionButton = overlay.get_node("%OptionMode")
	var h_master: HSlider = overlay.get_node("%HMaster")
	check("T7 控件回读与 Settings 一致",
		mode_opt.selected == int(Settings.get_value("display_mode"))
		and is_equal_approx(h_master.value, float(Settings.get_value("master_volume"))))
	h_master.value = 0.3
	await get_tree().process_frame
	check("T7 拖滑条 → Settings 即时更新", is_equal_approx(float(Settings.get_value("master_volume")), 0.3))
	overlay.close()
	check("T7 close 后隐藏", not overlay.visible)
	overlay.queue_free()
	await get_tree().process_frame
