extends Node
## 棋盘系第二批无头测试：强化珠（+珠）与花障的棋盘规则。
##   godot --headless --path . res://tests/board_plus_test.tscn

var _fails := 0


func check(case_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS  " + case_name)
	else:
		_fails += 1
		print("FAIL  %s  %s" % [case_name, detail])


func _ready() -> void:
	await get_tree().process_frame
	print("board_plus_test 开始")
	_run()
	print("---")
	print("board_plus_test 结果：%d 项失败" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


## 棋盘格填棋盘格花纹（无三连的基础底）
func _checker(b: Match3Board) -> void:
	b.setup()  # 先建好平行网格，再覆写为棋盘格花纹
	for r in b.size:
		for c in b.size:
			b.grid[r][c] = (r + c) % 2
			b.specials[r][c] = Match3Board.SPECIAL_NONE
			b.plus[r][c] = false


func _run() -> void:
	# T1 花瓣封印：随机封 3 颗
	var b := Match3Board.new(7, 6)
	_checker(b)
	var sealed: Array = b.seal_obstacles(3)
	check("T1 封 3 颗", sealed.size() == 3)
	var all_obst := true
	for c0 in sealed:
		var cell: Vector2i = c0
		all_obst = all_obst and b.is_obstacle(cell.y, cell.x)
	check("T1 全部为花障", all_obst)

	# T2 花障不可交换
	var cell0: Vector2i = sealed[0]
	var nb := Vector2i(-1, -1)
	for d0: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
		var t := cell0 + d0
		if t.x >= 0 and t.y >= 0 and t.x < 7 and t.y < 7:
			nb = t
			break
	check("T2 花障交换被拒", not bool(b.try_swap(cell0, nb).get("ok", false)))

	# T3 匹配跳过花障：一行 [3,3,障,3,3] 无三连
	var b2 := Match3Board.new(7, 6)
	_checker(b2)
	b2.grid[0][0] = 3
	b2.grid[0][1] = 3
	b2.grid[0][2] = Match3Board.OBST_ELEM
	b2.grid[0][3] = 3
	b2.grid[0][4] = 3
	check("T3 花障截断匹配", b2.find_matches().is_empty())

	# T4 邻消即碎：交换凑成紧邻花障的三连 → 花障碎裂 + 波内碎片条目
	var b3 := Match3Board.new(7, 6)
	_checker(b3)
	b3.grid[0][2] = Match3Board.OBST_ELEM
	b3.grid[0][3] = 5
	b3.grid[0][4] = 4
	b3.grid[0][5] = 4
	b3.grid[0][6] = 1
	b3.grid[1][3] = 4
	var rep4: Dictionary = b3.try_swap(Vector2i(3, 0), Vector2i(3, 1))
	check("T4 交换有效", bool(rep4.get("ok", false)))
	check("T4 花障已碎", not b3.is_obstacle(2, 0))
	var has_frag := false
	for w in rep4["waves"]:
		for e in w:
			if Vector2i(e["cell"]) == Vector2i(2, 0) and int(e["element"]) == -1:
				has_frag = true
	check("T4 波内含碎片条目(-1)", has_frag)

	# T5 +珠随重力下落
	var b5 := Match3Board.new(7, 6)
	_checker(b5)
	b5.grid[3][0] = 2
	b5.plus[3][0] = true
	b5.grid[4][0] = Match3Board.EMPTY
	b5.grid[5][0] = Match3Board.EMPTY
	b5.grid[6][0] = Match3Board.EMPTY
	b5._apply_gravity_and_refill()
	check("T5 +珠随重力下落",
		b5.grid[6][0] == 2 and b5.plus_at(6, 0) and not b5.plus_at(3, 0))

	# T6 消除波条目携带 +珠标记
	var b6 := Match3Board.new(7, 6)
	_checker(b6)
	b6.grid[6][0] = 1
	b6.grid[6][1] = 2
	b6.grid[6][2] = 3
	b6.grid[6][3] = 5
	b6.grid[6][4] = 3
	b6.grid[6][5] = 3
	b6.grid[6][6] = 0
	b6.plus[6][2] = true
	var rep6: Dictionary = b6.try_swap(Vector2i(2, 6), Vector2i(3, 6))
	check("T6 交换有效", bool(rep6.get("ok", false)))
	var plus_found := false
	for w in rep6["waves"]:
		for e in w:
			if bool(e.get("plus", false)):
				plus_found = true
	check("T6 波条目携带 +珠标记", plus_found)

	# T7 技能爆破可直接碎花障（技能=万能解）
	var b7 := Match3Board.new(7, 6)
	_checker(b7)
	b7.grid[3][3] = Match3Board.OBST_ELEM
	var r7: Dictionary = b7.skill_smash([Vector2i(3, 3)])
	check("T7 技能可碎花障", not b7.is_obstacle(3, 3) and int(r7["removed"]) == 1)

	# T8 拍板常量
	check("T8 天降 2%", is_equal_approx(Match3Board.PLUS_DROP_CHANCE, 0.02))
	check("T8 加成 6%", is_equal_approx(Match3Board.PLUS_WAVE_BONUS, 0.06))
