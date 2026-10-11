extends Node
## 一次性截屏：第三层战斗画面（怪物头像/背景/技能图标验证，不碰玩家存档）

func _ready() -> void:
	await get_tree().process_frame
	SaveManager.set_process(false)  # 诊断期间禁用自动保存
	GameState.reset()
	GameState.create_character("ranger", "human")
	GameState.debug_set_level(55)
	GameState.floor3_card = true
	GameState.go_to_floor(3)
	var battle_scene: Node = load("res://scenes/battle/battle.tscn").instantiate()
	add_child(battle_scene)
	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/cap_floor3_battle.png")
	print("[capture] floor3 battle saved")
	get_tree().quit()
