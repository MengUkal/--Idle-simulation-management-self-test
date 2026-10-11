extends Node
## 复现「新的开始」流程：伪造存档 → 删档重置 → 进 main → 观察跳转与错误。
##   godot --headless --path . res://tests/repro_newgame.tscn


func _ready() -> void:
	# 伪造一份 Lv.15 已创角存档（对齐用户截图状态）
	var save := {
		"version": 5, "money": 207.0, "level": 15, "floor": 1, "total_earned": 500.0,
		"essence": 75, "atk_line": 0, "bounty_line": 0, "income_line": 0,
		"holdings": [0, 0, 0], "fruits": 0, "rebirth_count": 0, "rebirth_guide_shown": false,
		"class_id": "warrior", "race_id": "human", "skill_points": 13, "talents": {},
		"paragon_points": 0, "paragon_talents": {}, "paragon_unlocked_boards": ["p1"],
		"floor3_card": false, "floor4_card": false, "floor5_card": false,
		"bag": [], "equipped": {}, "leg_claimed": [], "killed_once": {}, "glue": 0,
		"pets": {}, "pet_board": "", "stars": 0, "chests_opened": 0, "tips_seen": {},
		"skill_lv": 0, "body_line": 0,
	}
	var f := FileAccess.open("user://save.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(save))
	f.close()
	print("[repro] 已写入 Lv.15 存档")

	# 用户流程：新的开始确认 → 删档 + reset + 进 main
	SaveManager.delete_save()
	GameState.reset()
	print("[repro] after reset: level=%d money=%d class='%s' needs_char=%s" % [
		GameState.level, int(GameState.money), GameState.character_class,
		str(GameState.needs_character_creation())])

	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	for i in 5:
		await get_tree().process_frame
	var cs := get_tree().current_scene
	print("[repro] current_scene=", cs.scene_file_path if cs != null else "null")
	if cs != null and cs.get("script") != null:
		print("[repro] main 已初始化按钮信号? _connect 已在 _ready 47 行执行")
	get_tree().quit(0)
