extends Node
## 一次性截屏：天赋面板修复后外观（tests/cap_talents_fixed.png）

func _ready() -> void:
	await get_tree().process_frame
	SaveManager.set_process(false)  # 诊断期间禁用自动保存，不碰玩家存档
	var panel: Node = load("res://scenes/talents/talents_panel.gd").new()
	add_child(panel)
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/cap_talents_fixed.png")
	print("[capture] cap_talents_fixed saved")
	get_tree().quit()
