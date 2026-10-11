extends Node
## 一次性截屏：层守机制横幅 / 四层美术验证（禁用自动保存，仅内存构造，不碰玩家存档）。

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
	# 四层美术接入验证：强制常驻怪落英妖（立绘 petalfae.png + bg_floor4.png 自动加载）
	b.monster = Balance.MONSTERS_FLOOR4[0].duplicate()
	b.monster_hp_max = int(b.monster["hp"])
	b.monster_hp = float(b.monster_hp_max) * 0.7
	var slug: String = b.MONSTER_SLUG.get("落英妖", "")
	var tex_path := "res://assets/art/monsters/%s.png" % slug
	if ResourceLoader.exists(tex_path):
		b._enemy_portrait.texture = load(tex_path)
	b._refresh_hud()
	b._refresh_board()
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("F:/放置测试/挂机放置增量rpg/tests/cap_floor4_art.png")
	print("[capture] cap_floor4_art saved")
	get_tree().quit()
