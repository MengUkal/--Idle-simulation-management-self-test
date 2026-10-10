extends Control
## 标题画面：入口 + 存档分流（继续 / 新的开始）。
## 美术：世界树立绘全屏（tools/gen_asset.py --scene 产物），按钮吃全局奇幻主题。

const SAVE_PATH := SaveManager.SAVE_PATH

@onready var _continue_btn: Button = %ContinueBtn
@onready var _new_btn: Button = %NewBtn
@onready var _new_confirm: Control = %NewConfirm


func _ready() -> void:
	var has_save := FileAccess.file_exists(SAVE_PATH)
	_continue_btn.visible = has_save
	_new_btn.text = "新的开始" if has_save else "开始游戏"
	_continue_btn.pressed.connect(_on_start)
	_new_btn.pressed.connect(_on_new_pressed)
	%NewCancelBtn.pressed.connect(func() -> void: _new_confirm.visible = false)
	%NewApplyBtn.pressed.connect(_on_new_confirmed)
	if OS.get_cmdline_user_args().has("--capture-title"):
		_debug_capture.call_deferred()


func _on_start() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")


func _on_new_pressed() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		_new_confirm.visible = true  # 有存档：先确认清空
	else:
		_on_start()


func _on_new_confirmed() -> void:
	_new_confirm.visible = false
	SaveManager.delete_save()
	GameState.reset()
	_on_start()


## 【诊断工具】截屏标题画面（-- --capture-title 触发，输出 tests/cap_title.png）
func _debug_capture() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("F:/放置测试/挂机放置增量rpg/tests/cap_title.png")
	print("[capture] cap_title saved")
	get_tree().quit()
