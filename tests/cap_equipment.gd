extends Node
## 一次性截屏：装备面板（禁用自动保存，仅内存构造，不碰玩家存档）。

func _ready() -> void:
	await get_tree().process_frame
	SaveManager.set_process(false)
	GameState.reset()
	GameState.create_character("warrior", "human")
	GameState.debug_set_level(55)
	# 造几件演示装备：一件已穿 + 背包若干（含传奇/太古）
	var sword := GameEquipment.roll_item(2, 0, "warrior", {"name": "演示"})
	sword["slot"] = "main"
	sword["type"] = "sword"
	sword["tier"] = 2
	sword["id"] = "main_sword_L2"
	sword["name"] = GameEquipment.MAIN_BASES["sword"][1]
	sword["quality"] = 2
	sword["affixes"] = [{"id": "af_sharp", "tier": 4, "ancient": false}]
	GameState.bag.append(sword)
	GameState.equip_from_bag(0)
	var helm := GameEquipment.roll_item(4, 0, "warrior", {"name": "演示"})
	helm["slot"] = "helm"
	helm["type"] = "heavy"
	helm["tier"] = 4
	helm["id"] = "helm_heavy_L4"
	helm["name"] = GameEquipment.ARMOR_BASES["heavy"]["helm"][3]
	helm["quality"] = 3
	helm["affixes"] = [{"id": "af_zenith", "tier": 0, "ancient": false}, {"id": "af_harvest", "tier": 3, "ancient": false}, {"id": "af_studies", "tier": 2, "ancient": true}]
	GameState.equip_from_bag(GameState.bag.size() - 1)
	for i in 5:
		GameState.bag.append(GameEquipment.roll_item(3, 0, "warrior", {"name": "演示"}))
	var leg: Dictionary = GameEquipment.legendary_def("leg_oath_blade").duplicate()
	leg["legendary"] = "leg_oath_blade"
	leg["affixes"] = [{"id": "af_sharp", "tier": 3, "ancient": false}, {"id": "af_plunder", "tier": 2, "ancient": false}, {"id": "af_swift", "tier": 1, "ancient": false}]
	GameState.bag.append(leg)
	var main_scene: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main_scene)
	await get_tree().process_frame
	var panel := EquipmentPanel.new()
	main_scene.add_child(panel)
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("F:/放置测试/挂机放置增量rpg/tests/cap_equipment.png")
	print("[capture] cap_equipment saved")
	get_tree().quit()
