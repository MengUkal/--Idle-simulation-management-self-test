extends Node
## 一次性截屏：装备面板（禁用自动保存，仅内存构造，不碰玩家存档）。

func _ready() -> void:
	await get_tree().process_frame
	SaveManager.set_process(false)
	GameState.reset()
	GameState.create_character("warrior", "human")
	GameState.debug_set_level(55)
	# 造几件演示装备：确定性构造（先 base_item 再内在属性，槽位/属性一致）
	var sword := GameEquipment.base_item("main", "sword", 2)
	sword["quality"] = 2
	sword["affixes"] = [{"id": "af_sharp", "tier": 4, "ancient": false}]
	GameEquipment._apply_intrinsics(sword)
	GameState.bag.append(sword)
	GameState.equip_from_bag(0)
	var helm := GameEquipment.base_item("helm", "heavy", 4)
	helm["quality"] = 3
	helm["affixes"] = [{"id": "af_zenith", "tier": 0, "ancient": false}, {"id": "af_harvest", "tier": 3, "ancient": false}, {"id": "af_studies", "tier": 2, "ancient": true}]
	GameEquipment._apply_intrinsics(helm)
	GameState.bag.append(helm)
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
	await get_tree().process_frame
	panel._sel_bag = 0  # 选中背包首件 → 展示分解/洗练区
	panel._refresh()
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("F:/放置测试/挂机放置增量rpg/tests/cap_equipment.png")
	print("[capture] cap_equipment saved")
	# 第二张：属性面板
	panel.queue_free()
	await get_tree().process_frame
	var stats := StatsPanel.new()
	main_scene.add_child(stats)
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var img2 := get_viewport().get_texture().get_image()
	img2.save_png("F:/放置测试/挂机放置增量rpg/tests/cap_stats.png")
	print("[capture] cap_stats saved")
	get_tree().quit()
