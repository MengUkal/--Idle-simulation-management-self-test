extends CanvasLayer
## 全局设置面板：Esc 唤出/关闭，F11 快切全屏/窗口。
## 控件改动 → Settings.set_value（即时应用 + 落盘）；打开面板时从 Settings 回读刷新。

@onready var _option_mode: OptionButton = %OptionMode
@onready var _option_res: OptionButton = %OptionRes
@onready var _check_vsync: CheckButton = %CheckVSync
@onready var _h_master: HSlider = %HMaster
@onready var _h_music: HSlider = %HMusic
@onready var _h_sfx: HSlider = %HSFX
@onready var _v_master: Label = %VMaster
@onready var _v_music: Label = %VMusic
@onready var _v_sfx: Label = %VSFX
@onready var _check_shake: CheckButton = %CheckShake
@onready var _check_damage: CheckButton = %CheckDamage
@onready var _close_btn: Button = %CloseBtn

var _updating := false  # 回读刷新时屏蔽控件信号，防回环写


func _ready() -> void:
	visible = false
	_connect()
	_refresh_ui()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		toggle()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		Settings.toggle_fullscreen()
		_refresh_ui()
		get_viewport().set_input_as_handled()


func open() -> void:
	_refresh_ui()
	visible = true


func close() -> void:
	visible = false


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _connect() -> void:
	_option_mode.item_selected.connect(func(idx: int) -> void:
		Settings.set_value("display_mode", idx)
		_refresh_res_availability())
	_option_res.item_selected.connect(func(idx: int) -> void:
		Settings.set_value("window_resolution", idx))
	_check_vsync.toggled.connect(func(on: bool) -> void:
		Settings.set_value("vsync", on))
	_h_master.value_changed.connect(func(v: float) -> void:
		Settings.set_value("master_volume", v)
		_v_master.text = "%d%%" % roundi(v * 100))
	_h_music.value_changed.connect(func(v: float) -> void:
		Settings.set_value("music_volume", v)
		_v_music.text = "%d%%" % roundi(v * 100))
	_h_sfx.value_changed.connect(func(v: float) -> void:
		Settings.set_value("sfx_volume", v)
		_v_sfx.text = "%d%%" % roundi(v * 100))
	_check_shake.toggled.connect(func(on: bool) -> void:
		Settings.set_value("fx_screen_shake", on))
	_check_damage.toggled.connect(func(on: bool) -> void:
		Settings.set_value("fx_damage_numbers", on))
	_close_btn.pressed.connect(close)


func _refresh_ui() -> void:
	_updating = true
	_option_mode.select(int(Settings.get_value("display_mode")))
	_option_res.select(int(Settings.get_value("window_resolution")))
	_check_vsync.button_pressed = bool(Settings.get_value("vsync"))
	_h_master.value = float(Settings.get_value("master_volume"))
	_h_music.value = float(Settings.get_value("music_volume"))
	_h_sfx.value = float(Settings.get_value("sfx_volume"))
	_v_master.text = "%d%%" % roundi(_h_master.value * 100)
	_v_music.text = "%d%%" % roundi(_h_music.value * 100)
	_v_sfx.text = "%d%%" % roundi(_h_sfx.value * 100)
	_check_shake.button_pressed = bool(Settings.get_value("fx_screen_shake"))
	_check_damage.button_pressed = bool(Settings.get_value("fx_damage_numbers"))
	_refresh_res_availability()
	_updating = false


func _refresh_res_availability() -> void:
	# 无边框全屏下分辨率无意义（拉伸自动适配），仅窗口模式可选
	_option_res.disabled = int(Settings.get_value("display_mode")) == Settings.DisplayMode.BORDERLESS_FULLSCREEN
