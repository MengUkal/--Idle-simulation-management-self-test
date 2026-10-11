extends Node
## 精华新消耗口 A+D 验证：技能强化 + 体魄训练线 + 修改器接口。
##   godot --headless --path . res://tests/essence_sink_test.tscn


var _fails := 0


func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS  " + name)
	else:
		_fails += 1
		print("FAIL  %s  %s" % [name, detail])


func _ready() -> void:
	GameState.reset()
	GameState.create_character("warrior", "human")
	GameState.essence = 1000000

	# 技能强化
	check("技能首级费用 50", GameState.skill_upgrade_cost() == 50)
	check("升级到 1", GameState.skill_upgrade() and GameState.skill_lv == 1)
	check("2 级费用 80", GameState.skill_upgrade_cost() == 80)
	GameState.debug_set_skill_lv(10)
	check("10 级封顶", not GameState.skill_upgrade())

	# 体魄训练线
	var hp0: int = GameState.player_max_hp()
	check("体魄升级", GameState.upgrade_line("body"))
	check("生命 +8%", GameState.player_max_hp() == int(ceil(hp0 * 1.08)))
	GameState.atk_line = GameState.body_line
	check("体魄线费用公式同源（同级同价）",
		GameState.train_cost_for("body") == GameState.train_cost_for("atk"))

	# 修改器接口
	GameState.debug_set_glue(500)
	check("修改器: 树胶", GameState.glue == 500)
	GameState.debug_fill_pets(1)
	check("修改器: 点亮一层图鉴 7 只", GameState.pets.size() == 7)
	check("修改器: 伙伴被动进乘区", Mods.mult("income") > 1.0 or Mods.add("dr") > 0.0
		or Mods.add("regen") > 0.0 or Mods.mult("max_hp") > 1.0
		or Mods.mult("battle_damage") > 1.0 or Mods.add("steps") > 0.0)
	GameState.debug_grant_equipment(2, 1)
	check("修改器: 发装备入包", GameState.bag.size() == 1)
	GameState.debug_add_stars(9)
	check("修改器: 产星开箱", GameState.chests_opened == 1)

	# 看板位 ×2（同怪同品质：看板 = 常驻 ×2）
	var per_base := GamePets.passive_per("树精史莱姆", 3, false)
	GameState.set_pet_board("树精史莱姆")
	var per_board := GameState.pet_passive_per("树精史莱姆")
	print("  [dbg] per_board=%s base_x2=%s" % [per_board, per_base * 2.0])
	check("看板位 ×2", is_equal_approx(per_board, per_base * 2.0))

	# 存档 roundtrip
	SaveManager.save()
	var f := FileAccess.open("user://save.json", FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	check("skill_lv/body_line/glue/stars 落盘",
		int(d.get("skill_lv", -1)) == GameState.skill_lv
		and int(d.get("body_line", -1)) == GameState.body_line
		and int(d.get("glue", -1)) == GameState.glue
		and int(d.get("stars", -1)) == GameState.stars)

	print("---")
	print("结果：%d 项失败" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
