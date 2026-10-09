extends SceneTree
## 交易所数值测试（无头）：价格游走边界 / K 线滚动 / 手续费数学
##   godot --headless --path . --script res://tests/market_test.gd

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
	var m = load("res://autoload/market.gd").new()
	m.reset_market()
	check("初始 3 个标的价格", m.prices.size(), 3)
	check("预生成历史 K 线 40 根", m.history[0].size(), 40)
	# 手续费数学（1% 买卖均收）
	var cost: Dictionary = Balance.trade_cost(100.0, 10)
	check("买入毛额 = 1000", cost["gross"], 1000.0)
	check("买入手续费 = 10", cost["fee"], 10.0)
	check("买入总花费 = 1010", cost["total"], 1010.0)
	check("卖出到手 = 990", Balance.sell_proceeds(100.0, 10), 990.0)
	# 行情推进 300 秒（60 跳 = 10 根 K 线）
	for i in 300:
		m._process(1.0)
	var ok_band := true
	for i in m.prices.size():
		var base: float = Balance.MARKET_TARGETS[i]["base"]
		if m.prices[i] < base * 0.2 or m.prices[i] > base * 5.0:
			ok_band = false
	check("价格在 0.2~5.0 倍基准带内", ok_band, true)
	check("K 线维持 40 根滚动窗口", m.history[0].size(), 40)
	check("三标的 K 线同步滚动", m.history[1].size(), 40)
	check("末根收盘 = 当前价", m.history[0][39][3], m.prices[0])
	# 状态持久化往返
	var state: Dictionary = m.dump_state()
	var m2 = load("res://autoload/market.gd").new()
	m2.reset_market()
	m2.apply_state(state)
	check("状态往返后价格一致", m2.prices[0], m.prices[0])
	check("状态往返后 K 线数一致", m2.history[0].size(), m.history[0].size())
	print("---")
	print("结果：%d 项失败" % _fails)
	quit(1 if _fails > 0 else 0)
