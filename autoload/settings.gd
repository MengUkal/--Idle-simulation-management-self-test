extends Node
## 用户设置唯一持有：显示 / 音频 / 表现。独立 user://settings.json，与游戏存档分离
## （删档不重置设置）。改动即时落盘、即时应用。
##
## 键与默认值见 DEFAULTS；表现开关（fx_*）由战斗界面等直接 get_value 查询；
## 显示与音频项在 set_value 时自动应用。

const SAVE_PATH := "user://settings.json"

enum DisplayMode { BORDERLESS_FULLSCREEN, WINDOWED }

const WINDOW_RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
]

const DEFAULTS := {
	"display_mode": DisplayMode.BORDERLESS_FULLSCREEN,  # 【已拍板】启动默认无边框全屏
	"window_resolution": 2,                              # 索引 → WINDOW_RESOLUTIONS（仅窗口模式生效）
	"vsync": true,
	"master_volume": 0.8,
	"music_volume": 0.8,
	"sfx_volume": 0.8,
	"fx_screen_shake": true,
	"fx_damage_numbers": true,
}

var values := {}


func _ready() -> void:
	_load()
	apply_display()
	apply_audio()


func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key):
		push_warning("未知设置键：%s" % key)
		return
	values[key] = value
	_save()
	match key:
		"display_mode", "window_resolution", "vsync":
			apply_display()
		"master_volume", "music_volume", "sfx_volume":
			apply_audio()
		_:
			pass  # fx_*：读取方直接查询，无需应用


func toggle_fullscreen() -> void:
	var mode := int(get_value("display_mode"))
	set_value("display_mode", DisplayMode.WINDOWED if mode == DisplayMode.BORDERLESS_FULLSCREEN
		else DisplayMode.BORDERLESS_FULLSCREEN)


# ---------- 应用 ----------

func apply_display() -> void:
	var mode := int(get_value("display_mode"))
	if mode == DisplayMode.BORDERLESS_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var res: Vector2i = WINDOW_RESOLUTIONS[clampi(int(get_value("window_resolution")), 0, WINDOW_RESOLUTIONS.size() - 1)]
		DisplayServer.window_set_size(res)
		var screen := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
		DisplayServer.window_set_position((screen - res) / 2)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if bool(get_value("vsync")) else DisplayServer.VSYNC_DISABLED)


func apply_audio() -> void:
	_apply_bus("Master", float(get_value("master_volume")))
	_apply_bus("Music", float(get_value("music_volume")))
	_apply_bus("SFX", float(get_value("sfx_volume")))


func _apply_bus(bus_name: String, linear: float) -> void:
	# 总线不存在（例如未来布局变更）时安全跳过——设置框架先行，不因缺音源报错
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var v := clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(v) if v > 0.001 else -80.0)
	AudioServer.set_bus_mute(idx, v <= 0.001)


# ---------- 持久化 ----------

func _load() -> void:
	values = DEFAULTS.duplicate()
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("设置文件损坏，使用默认设置")
		return
	for key: String in parsed.keys():
		if not DEFAULTS.has(key):
			continue  # 未知键过滤
		var def_type := typeof(DEFAULTS[key])
		var val_type := typeof(parsed[key])
		if val_type == def_type:
			values[key] = parsed[key]
		elif def_type in [TYPE_INT, TYPE_FLOAT] and val_type in [TYPE_INT, TYPE_FLOAT]:
			# JSON roundtrip 会把所有数字变 float，整数设置键在这里转回 int
			values[key] = convert(parsed[key], def_type)
		# 其余类型不符 → 忽略该键，保持默认


func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("设置写入失败（错误码 %d）" % FileAccess.get_open_error())
		return
	f.store_string(JSON.stringify(values, "\t"))
	f.close()
