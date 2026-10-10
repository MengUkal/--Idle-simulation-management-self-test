extends Node
## 【诊断工具】标题→主界面→打开天赋面板→截屏（-- --capture-talents 触发）
## 挂在 root 下，跨场景切换存活。输出 tests/cap_talents.png

func _ready() -> void:
	get_tree().change_scene_to_file.call_deferred("res://scenes/main/main.tscn")
	await get_tree().create_timer(0.6).timeout
	# 存档若无角色（v5 迁移前/新档），临时给默认人类战士以便展示战士树
	if GameState.character_class == "":
		GameState.create_character("warrior", "human")
	var panel: CanvasLayer = load("res://scenes/talents/talents_panel.gd").new()
	get_tree().root.add_child(panel)
	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://tests/cap_talents.png")
	print("[capture] cap_talents saved")
	get_tree().quit()
