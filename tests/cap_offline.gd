extends Node
## 一次性截屏：离线收益回归弹窗（禁用自动保存，仅内存构造，不碰玩家存档）。

func _ready() -> void:
	await get_tree().process_frame
	SaveManager.set_process(false)  # 诊断期间禁用自动保存
	GameState.reset()
	GameState.create_character("priest", "human")
	GameState.debug_set_level(42)
	GameState.last_seen = Time.get_unix_time_from_system() - 3.5 * 3600.0
	GameState.settle_offline()
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("F:/放置测试/挂机放置增量rpg/tests/cap_offline.png")
	print("[capture] cap_offline saved")
	get_tree().quit()
