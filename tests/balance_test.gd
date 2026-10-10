extends SceneTree
## 数值公式冒烟测试（无头运行，不依赖自动加载单例）：
##   godot --headless --path . --script res://tests/balance_test.gd
## 退出码 0 = 全部通过，1 = 存在失败。

var _fails := 0


func check(case_name: String, actual: Variant, expected: Variant) -> void:
	var ok := false
	if typeof(actual) in [TYPE_FLOAT, TYPE_INT] and typeof(expected) in [TYPE_FLOAT, TYPE_INT]:
		ok = is_equal_approx(float(actual), float(expected))
	else:
		ok = actual == expected
	if ok:
		print("PASS  " + case_name)
	else:
		_fails += 1
		print("FAIL  %s  实际=%s 预期=%s" % [case_name, actual, expected])


func _init() -> void:
	# 收入公式：0.06 * 1.10^(lv-1)（30分钟+到二层节奏，2026-10-09 拍板）
	check("Lv.1 收入 = 0.06", Balance.income_per_sec(1), 0.06)
	check("Lv.10 收入 = 0.06×1.1^9", Balance.income_per_sec(10), 0.06 * pow(1.10, 9.0))
	check("Lv.11 收入 = 0.06×1.1^10", Balance.income_per_sec(11), 0.06 * pow(1.10, 10.0))
	# 献金公式：10 * 1.15^(lv-1)
	check("Lv.1→2 献金 = 10", Balance.upgrade_cost(1), 10.0)
	check("Lv.10→11 献金 = 10×1.15^9", Balance.upgrade_cost(10), 10.0 * pow(1.15, 9.0))
	# 层数门槛
	check("二层门槛 = Lv.10", Balance.FLOOR_2_LEVEL_REQ, 10)
	# 冒险步数公式：10 + level×0.5 取整（Lv.1=10、Lv.10=15、Lv.30=25）
	check("Lv.1 步数 = 10", Balance.battle_steps(1), 10)
	check("Lv.10 步数 = 15", Balance.battle_steps(10), 15)
	check("Lv.30 步数 = 25", Balance.battle_steps(30), 25)
	# 怪物表（第一层）
	check("第一层常驻怪物 6 只", Balance.MONSTERS_FLOOR1.size(), 6)
	var monsters_ok := true
	for m: Dictionary in Balance.MONSTERS_FLOOR1:
		if int(m["hp"]) <= 0 or int(m["bounty"]) <= 0:
			monsters_ok = false
		if int(m["weak"]) < 0 or int(m["weak"]) > 5:
			monsters_ok = false
	check("怪物 HP/赏金/弱点取值合法", monsters_ok, true)
	check("命中弱点倍率 = 2", Balance.damage_multiplier(0, {"weak": 0}), 2.0)
	check("非弱点倍率 = 1", Balance.damage_multiplier(1, {"weak": 0}), 1.0)
	# 训练线与里程碑（元素精华，NGU 式多线成长）
	check("训练线 0→1 费用 = 25", Balance.train_cost(0), 25.0)
	check("训练线 1→2 费用 = 25×1.35", Balance.train_cost(1), 25.0 * 1.35)
	check("训练线 2 级倍率 = 1.10", Balance.train_multiplier(2), 1.10)
	check("里程碑 Lv.8 奖励 30 精华", Balance.MILESTONE_EP[8], 30)
	# 重生公式（M4，2026-10-10 六项拍板 + 数值定稿）
	check("重生门槛：0 轮 = 40", Balance.rebirth_threshold(0), 40)
	check("重生门槛：1 轮 = 45", Balance.rebirth_threshold(1), 45)
	check("重生门槛：3 轮 = 55", Balance.rebirth_threshold(3), 55)
	check("果实结算：Lv.30 = 0", Balance.fruits_for_level(30), 0)
	check("果实结算：Lv.40 = 5", Balance.fruits_for_level(40), 5)
	check("果实结算：Lv.45 = 10", Balance.fruits_for_level(45), 10)
	check("果实结算：Lv.55 = 27", Balance.fruits_for_level(55), 27)
	check("果实收入乘数：7 颗 = 1.35", Balance.income_fruit_mult(7), 1.35)
	check("果实收入乘数：0 颗 = 1.0", Balance.income_fruit_mult(0), 1.0)
	check("果实攻击乘数：20 颗 = 1.20", Balance.atk_fruit_mult(20), 1.20)
	check("训练费用乘数：0 果 0 轮 = 1.0", Balance.train_cost_mult(0, 0), 1.0)
	check("训练费用乘数：2 果 1 轮 = 0.98²×0.95", Balance.train_cost_mult(2, 1),
		pow(0.98, 2.0) * pow(0.95, 1.0))
	# 第二层怪物表与怪物池切换
	check("第二层常驻怪物 6 只", Balance.MONSTERS_FLOOR2.size(), 6)
	check("怪物池按层切换", Balance.monster_pool(2).size(), 6)
	check("二层精英为守林古树", Balance.monster_elite(2)["name"], "守林古树")
	check("一层精英为树根守卫", Balance.monster_elite(1)["name"], "树根守卫")
	# 数值格式化
	check("格式 999", Balance.format_number(999.0), "999")
	check("格式 1234", Balance.format_number(1234.0), "1,234")
	check("格式 10000", Balance.format_number(10000.0), "1万")
	check("格式 12345678", Balance.format_number(12345678.0), "1234.57万")
	check("格式 1.5亿", Balance.format_number(150000000.0), "1.5亿")
	check("格式 负数", Balance.format_number(-20000.0), "-2万")
	check("格式 小数 0.06", Balance.format_number(0.06), "0.06")
	check("格式 6.5", Balance.format_number(6.5), "6.5")
	check("格式 6.0", Balance.format_number(6.0), "6")
	print("---")
	print("结果：%d 项失败" % _fails)
	quit(1 if _fails > 0 else 0)
