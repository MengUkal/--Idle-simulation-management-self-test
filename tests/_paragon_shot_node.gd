extends Node
## 【诊断工具】标题→主界面→打开巅峰面板→截屏（-- --capture-paragon 触发）
## 挂在 root 下，跨场景切换存活。输出 tests/cap_paragon.png

func _ready() -> void:
	get_tree().change_scene_to_file.call_deferred("res://scenes/main/main.tscn")
	await get_tree().create_timer(0.6).timeout
	var panel: CanvasLayer = load("res://scenes/paragon/paragon_panel.gd").new()
	get_tree().root.add_child(panel)
	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://tests/cap_paragon.png")
	print("[capture] cap_paragon saved")
	get_tree().quit()
