extends Node
## 一次性截屏：层守机制横幅（禁用自动保存，仅内存构造，不碰玩家存档）。

func _ready() -> void:
	await get_tree().process_frame
	SaveManager.set_process(false)  # 诊断期间禁用自动保存
	GameState.reset()
	GameState.create_character("warrior", "human")
	GameState.debug_set_level(52)
	GameState.floor_index = 3
	GameState.floor3_card = true
	var b: Node = load("res://scenes/battle/battle.tscn").instantiate()
	add_child(b)
	await get_tree().process_frame
	# 强制层守镇风桩 + 演示蓄力横幅（覆盖随机开局的怪物）
	b.monster = Balance.MONSTER_ELITE_FLOOR3.duplicate()
	b.monster["elite"] = true
	b.guard = GuardKit.new("镇风桩")
	b.monster_hp_max = int(b.monster["hp"])
	b.monster_hp = float(b.monster_hp_max) * 0.45
	var slug: String = b.MONSTER_SLUG.get("镇风桩", "")
	var tex_path := "res://assets/art/monsters/%s.png" % slug
	if ResourceLoader.exists(tex_path):
		b._enemy_portrait.texture = load(tex_path)
	b._refresh_hud()
	b._show_banner("桩劲蓄力！3 步内受伤翻倍", Color(0.55, 0.9, 0.6))
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("F:/放置测试/挂机放置增量rpg/tests/cap_guard.png")
	print("[capture] cap_guard saved")
	get_tree().quit()
