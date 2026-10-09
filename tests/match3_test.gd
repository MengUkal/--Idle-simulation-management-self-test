extends SceneTree
## 三消逻辑冒烟测试（无头运行，不依赖自动加载单例）：
##   godot --headless --path . --script res://tests/match3_test.gd
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
	_test_setup()
	_test_find_matches()
	_test_swap_rules()
	_test_resolve()
	_test_find_any_move()
	print("---")
	print("结果：%d 项失败" % _fails)
	quit(1 if _fails > 0 else 0)


func _test_setup() -> void:
	var b := Match3Board.new()
	b.setup()
	check("棋盘 7 行", b.grid.size(), 7)
	check("棋盘 7 列", b.grid[0].size(), 7)
	var in_range := true
	for r in 7:
		for c in 7:
			var v: int = b.grid[r][c]
			if v < 0 or v > 5:
				in_range = false
	check("元素取值都在 0..5", in_range, true)
	check("开局无现成三连", b.find_matches().is_empty(), true)


func _test_find_matches() -> void:
	var b := Match3Board.new(3, 6)
	b.grid = [[1, 1, 1], [2, 3, 4], [5, 6, 2]]
	var m: Array[Vector2i] = b.find_matches()
	check("横向三连检出 3 格", m.size(), 3)
	var on_top_row := true
	for c in 3:
		if not m.has(Vector2i(c, 0)):
			on_top_row = false
	check("三连位于第 0 行", on_top_row, true)
	# 竖向
	b.grid = [[2, 1, 3], [2, 1, 4], [2, 5, 6]]
	m = b.find_matches()
	check("竖向三连检出 3 格", m.size(), 3)
	var on_col0 := true
	for r in 3:
		if not m.has(Vector2i(0, r)):
			on_col0 = false
	check("三连位于第 0 列", on_col0, true)


func _test_swap_rules() -> void:
	# 无三连棋盘：交换后无消除 → 自动还原
	var b := Match3Board.new(3, 6)
	b.grid = [[1, 2, 3], [2, 3, 1], [3, 1, 2]]
	var rep: Dictionary = b.try_swap(Vector2i(0, 0), Vector2i(1, 0))
	check("无效交换返回 ok=false", rep.get("ok", true), false)
	check("无效交换已还原", b.grid[0][0], 1)
	# 非相邻交换直接拒绝
	var rep2: Dictionary = b.try_swap(Vector2i(0, 0), Vector2i(2, 0))
	check("非相邻交换返回 ok=false", rep2.get("ok", true), false)
	check("非相邻交换未改动棋盘", b.grid[0][0], 1)


func _test_resolve() -> void:
	# 构造：把 (2,1) 的 4 换到 (2,0) 使首行成 [4,4,4]
	var b := Match3Board.new(3, 6)
	b.rng.seed = 20261009  # 固定补牌随机序列，保证可复现
	b.grid = [[4, 4, 5], [1, 2, 4], [2, 1, 2]]
	var rep: Dictionary = b.try_swap(Vector2i(2, 0), Vector2i(2, 1))
	check("有效交换返回 ok=true", rep.get("ok", false), true)
	var cleared: Array = rep["cleared"]
	check("消除格数 ≥ 3", cleared.size() >= 3, true)
	var first_row_cleared := true
	for c in 3:
		if not cleared.has(Vector2i(c, 0)):
			first_row_cleared = false
	check("首行三连被消除", first_row_cleared, true)
	check("连锁数 ≥ 1", rep["chains"] >= 1, true)
	var waves: Array = rep["waves"]
	check("waves 波数与 chains 一致", waves.size(), rep["chains"])
	var first_wave_uniform := true
	for entry in waves[0]:
		if int(entry["element"]) != 4:
			first_wave_uniform = false
	check("首波元素全为 4", first_wave_uniform, true)
	var full := true
	for r in 3:
		for c in 3:
			var v: int = b.grid[r][c]
			if v == Match3Board.EMPTY or v < 0 or v > 5:
				full = false
	check("结算后棋盘无空洞且元素合法", full, true)
	check("结算后无残留三连", b.find_matches().is_empty(), true)


func _test_find_any_move() -> void:
	var b := Match3Board.new(5, 4)
	b.setup()
	check("正常棋盘存在可行交换", b.find_any_move().size(), 2)
