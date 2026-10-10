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
	Sfx.bgm("bgm_floor1")  # 标题起调（进入主界面同名 BGM 不重头播，无缝衔接）
	if OS.get_cmdline_user_args().has("--capture-title"):
		_debug_capture.call_deferred()
	elif OS.get_cmdline_user_args().has("--capture-talents"):
		# 诊断链路：标题→主界面→打开天赋面板→截屏（runner 挂 root 跨场景存活）
		var runner := Node.new()
		runner.set_script(load("res://tests/_talents_shot_node.gd"))
		get_tree().root.add_child.call_deferred(runner)
	elif OS.get_cmdline_user_args().has("--capture-paragon"):
		var runner_p := Node.new()
		runner_p.set_script(load("res://tests/_paragon_shot_node.gd"))
		get_tree().root.add_child.call_deferred(runner_p)
	else:
		_play_intro.call_deferred()


## 开场动效：世界树立绘呼吸 + 文字/按钮逐个浮现
func _play_intro() -> void:
	var bg: TextureRect = %BgArt
	bg.pivot_offset = bg.size / 2.0
	var breath := create_tween().set_loops()
	breath.tween_property(bg, "scale", Vector2(1.03, 1.03), 3.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	breath.tween_property(bg, "scale", Vector2.ONE, 3.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var box: VBoxContainer = $CenterBox
	for i in box.get_child_count():
		var c: Control = box.get_child(i)
		if c == null or not c.visible:
			continue
		var home_y := c.position.y
		c.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_interval(0.09 * i)
		tw.tween_property(c, "modulate:a", 1.0, 0.35)
		tw.parallel().tween_property(c, "position:y", home_y, 0.35).from(home_y + 20)


func _on_start() -> void:
	Sfx.play("ui_click")
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
	await get_tree().create_timer(1.3).timeout  # 等开场动效播完再截
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("F:/放置测试/挂机放置增量rpg/tests/cap_title.png")
	print("[capture] cap_title saved")
	get_tree().quit()
