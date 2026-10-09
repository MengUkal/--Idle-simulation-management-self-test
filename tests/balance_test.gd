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
	# 收入公式：1 + 2*(lv-1)
	check("Lv.1 收入 = 1", Balance.income_per_sec(1), 1.0)
	check("Lv.10 收入 = 19", Balance.income_per_sec(10), 19.0)
	check("Lv.11 收入 = 21", Balance.income_per_sec(11), 21.0)
	# 献金公式：10 * 1.15^(lv-1)
	check("Lv.1→2 献金 = 10", Balance.upgrade_cost(1), 10.0)
	check("Lv.10→11 献金 = 10×1.15^9", Balance.upgrade_cost(10), 10.0 * pow(1.15, 9.0))
	# 层数门槛
	check("二层门槛 = Lv.10", Balance.FLOOR_2_LEVEL_REQ, 10)
	# 大数格式化
	check("格式 999", Balance.format_number(999.0), "999")
	check("格式 1234", Balance.format_number(1234.0), "1,234")
	check("格式 10000", Balance.format_number(10000.0), "1万")
	check("格式 12345678", Balance.format_number(12345678.0), "1234.57万")
	check("格式 1.5亿", Balance.format_number(150000000.0), "1.5亿")
	check("格式 负数", Balance.format_number(-20000.0), "-2万")
	print("---")
	print("结果：%d 项失败" % _fails)
	quit(1 if _fails > 0 else 0)
