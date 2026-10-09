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
	_test_specials()
	_test_find_any_move()
	print("---")
	print("结果：%d 项失败" % _fails)
	quit(1 if _fails > 0 else 0)


## 直接注入棋盘（并初始化平行的特效数组为无特效）
func _grid_only(b: Match3Board, g: Array) -> void:
	b.grid = g
	b.specials = []
	for r in b.size:
		var srow := []
		srow.resize(b.size)
		srow.fill(Match3Board.SPECIAL_NONE)
		b.specials.append(srow)


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
	_grid_only(b, [[1, 1, 1], [2, 3, 4], [5, 6, 2]])
	var m: Array[Vector2i] = b.find_matches()
	check("横向三连检出 3 格", m.size(), 3)
	var on_top_row := true
	for c in 3:
		if not m.has(Vector2i(c, 0)):
			on_top_row = false
	check("三连位于第 0 行", on_top_row, true)
	# 竖向
	_grid_only(b, [[2, 1, 3], [2, 1, 4], [2, 5, 6]])
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
	_grid_only(b, [[1, 2, 3], [2, 3, 1], [3, 1, 2]])
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
	_grid_only(b, [[4, 4, 5], [1, 2, 4], [2, 1, 2]])
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


func _test_specials() -> void:
	# —— 形状检测：4 连 → 直线 ——
	var b := Match3Board.new(5, 6)
	_grid_only(b, [[1, 1, 1, 1, 2], [2, 3, 2, 3, 1], [3, 2, 3, 2, 3], [2, 3, 2, 3, 1], [3, 2, 3, 2, 3]])
	var cells4: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	var spawns4: Array = b._detect_special_spawns(cells4)
	check("4 连生成直线特效", spawns4.size() == 1 and spawns4[0]["special"] == Match3Board.SPECIAL_LINE_H, true)

	# —— 形状检测：L 形 → 爆炸 ——
	var b2 := Match3Board.new(4, 6)
	_grid_only(b2, [[1, 1, 1, 2], [1, 3, 2, 3], [1, 2, 3, 2], [2, 3, 2, 3]])
	var cells_l: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(0, 2),
	]
	var spawns_l: Array = b2._detect_special_spawns(cells_l)
	check("L 形生成爆炸特效", spawns_l.size() == 1 and spawns_l[0]["special"] == Match3Board.SPECIAL_BOMB, true)

	# —— 形状检测：5 连 → 魔力鸟 ——
	var b3 := Match3Board.new(5, 6)
	_grid_only(b3, [[1, 1, 1, 1, 1], [2, 3, 2, 3, 2], [3, 2, 3, 2, 3], [2, 3, 2, 3, 2], [3, 2, 3, 2, 3]])
	var cells5: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0),
	]
	var spawns5: Array = b3._detect_special_spawns(cells5)
	check("5 连生成魔力鸟", spawns5.size() == 1 and spawns5[0]["special"] == Match3Board.SPECIAL_BIRD, true)

	# —— 直线特效激活：清整行 ——
	var b4 := Match3Board.new(3, 6)
	_grid_only(b4, [[1, 2, 3], [4, 5, 1], [2, 1, 3]])
	b4.specials[0][0] = Match3Board.SPECIAL_LINE_H
	var rep_line: Dictionary = b4.try_swap(Vector2i(0, 0), Vector2i(1, 0))
	check("直线特效激活 ok", rep_line.get("ok", false), true)
	var line_cleared: Array = rep_line["cleared"]
	var row0_gone := true
	for cell in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]:
		if not line_cleared.has(cell):
			row0_gone = false
	check("直线特效清除整行", row0_gone, true)

	# —— 爆炸特效激活：清 3×3 ——
	var b5 := Match3Board.new(3, 6)
	_grid_only(b5, [[1, 2, 3], [4, 5, 0], [1, 2, 1]])
	b5.specials[1][1] = Match3Board.SPECIAL_BOMB
	var rep_bomb: Dictionary = b5.try_swap(Vector2i(1, 1), Vector2i(2, 1))
	check("爆炸特效激活 ok", rep_bomb.get("ok", false), true)
	var bomb_cleared: Array = rep_bomb["cleared"]
	var area_gone := bomb_cleared.has(Vector2i(0, 0)) and bomb_cleared.has(Vector2i(2, 2)) and bomb_cleared.has(Vector2i(1, 1))
	check("爆炸特效清除 3×3", area_gone, true)

	# —— 魔力鸟 + 普通：清全场同色 ——
	var b6 := Match3Board.new(3, 6)
	_grid_only(b6, [[1, 3, 2], [3, 3, 1], [2, 1, 3]])
	b6.grid[0][0] = Match3Board.BIRD_ELEM
	b6.specials[0][0] = Match3Board.SPECIAL_BIRD
	var rep_bird: Dictionary = b6.try_swap(Vector2i(0, 0), Vector2i(0, 1))
	check("魔力鸟+普通 ok", rep_bird.get("ok", false), true)
	var bird_cleared: Array = rep_bird["cleared"]
	var all_threes := true
	for cell in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 2)]:
		if not bird_cleared.has(cell):
			all_threes = false
	check("魔力鸟清除全场同色", all_threes, true)

	# —— 组合：直线 + 直线 = 十字 ——
	# 注意坐标：specials[行][列]；LINE_H 放 (x=0,y=0)，LINE_V 放 (x=0,y=1)
	var b7 := Match3Board.new(3, 6)
	_grid_only(b7, [[1, 2, 3], [4, 5, 6], [2, 1, 2]])
	b7.specials[0][0] = Match3Board.SPECIAL_LINE_H
	b7.specials[1][0] = Match3Board.SPECIAL_LINE_V
	var rep_ll: Dictionary = b7.try_swap(Vector2i(0, 0), Vector2i(0, 1))
	check("直线+直线组合 ok", rep_ll.get("ok", false), true)
	var ll_cleared: Array = rep_ll["cleared"]
	check("十字清除行与列", ll_cleared.has(Vector2i(2, 0)) and ll_cleared.has(Vector2i(0, 2)), true)

	# —— 组合：魔力鸟 + 魔力鸟 = 全场清空 ——
	var b8 := Match3Board.new(3, 6)
	_grid_only(b8, [[1, 2, 3], [4, 5, 1], [2, 1, 3]])
	b8.grid[0][0] = Match3Board.BIRD_ELEM
	b8.specials[0][0] = Match3Board.SPECIAL_BIRD
	b8.grid[1][0] = Match3Board.BIRD_ELEM
	b8.specials[1][0] = Match3Board.SPECIAL_BIRD
	var rep_bb: Dictionary = b8.try_swap(Vector2i(0, 0), Vector2i(1, 0))
	check("魔力鸟+魔力鸟组合 ok", rep_bb.get("ok", false), true)
	check("全场清空连锁数 ≥1", rep_bb["chains"] >= 1, true)

	# —— 连锁：三连波及爆炸特效 → 引爆 ——
	var b9 := Match3Board.new(3, 6)
	_grid_only(b9, [[0, 1, 0], [2, 2, 2], [0, 1, 0]])
	b9.specials[1][2] = Match3Board.SPECIAL_BOMB  # (x=2, y=1) 在三连内
	var rep_chain: Dictionary = b9.try_swap(Vector2i(0, 0), Vector2i(1, 0))
	check("连锁引爆 ok", rep_chain.get("ok", false), true)
	var chain_cleared: Array = rep_chain["cleared"]
	var exploded := chain_cleared.has(Vector2i(1, 2)) and chain_cleared.has(Vector2i(2, 0))
	check("三连波及爆炸特效并引爆", exploded, true)


func _test_find_any_move() -> void:
	var b := Match3Board.new(5, 4)
	b.setup()
	check("正常棋盘存在可行交换", b.find_any_move().size(), 2)
	# 有特效的棋盘：特效参与的交换永远可行
	_grid_only(b, [[1, 2, 3, 4, 1], [2, 3, 4, 1, 2], [3, 4, 1, 2, 3], [4, 1, 2, 3, 4], [1, 2, 3, 4, 1]])
	b.specials[2][2] = Match3Board.SPECIAL_BOMB
	check("特效存在时必可行交换", b.find_any_move().size(), 2)
