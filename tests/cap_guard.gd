extends Node
## 一次性截屏：层守机制横幅（禁用自动保存，仅内存构造，不碰玩家存档）。

func _ready() -> void:
	await get_tree().process_frame
	SaveManager.set_process(false)  # 诊断期间禁用自动保存
	GameState.reset()
	GameState.create_character("warrior", "human")
	GameState.debug_set_level(62)
	GameState.floor_index = 4
	GameState.floor3_card = true
	GameState.floor4_card = true
	var b: Node = load("res://scenes/battle/battle.tscn").instantiate()
	add_child(b)
	await get_tree().process_frame
	# 强制层守千瓣祭主 + 演示花瓣封印（花障）与香雾（灰雾）
	b.monster = Balance.MONSTER_ELITE_FLOOR4.duplicate()
	b.monster["elite"] = true
	b.guard = GuardKit.new("千瓣祭主")
	b.monster_hp_max = int(b.monster["hp"])
	b.monster_hp = float(b.monster_hp_max) * 0.4
	var slug: String = b.MONSTER_SLUG.get("千瓣祭主", "")
	var tex_path := "res://assets/art/monsters/%s.png" % slug
	if ResourceLoader.exists(tex_path):
		b._enemy_portrait.texture = load(tex_path)
	b.board.seal_obstacles(3)
	b._smoke_left = 3
	b._refresh_hud()
	b._refresh_board()
	b._show_banner("香雾障目！3 步内看不清棋盘", Color(0.6, 0.65, 0.8))
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("F:/放置测试/挂机放置增量rpg/tests/cap_guard.png")
	print("[capture] cap_guard saved")
	get_tree().quit()
