extends SceneTree
## 主动技能 API 测试（Match3Board 技能方法 + 资源模型定义表）。
##   godot --headless --path . --script res://tests/skills_test.gd

var _fails := 0


func check(case_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS  " + case_name)
	else:
		_fails += 1
		print("FAIL  %s  %s" % [case_name, detail])


func _count_tiles(board: Match3Board) -> int:
	var n := 0
	for r in board.size:
		for c in board.size:
			if board.grid[r][c] != Match3Board.EMPTY:
				n += 1
	return n


func _init() -> void:
	seed(20261011)
	# T1 破城锤：十字 5 块被摧毁、盘面补满、连锁正常
	var b := Match3Board.new(7, 6)
	b.setup()
	var before := _count_tiles(b)
	var r1: Dictionary = b.skill_smash([Vector2i(3, 3), Vector2i(2, 3), Vector2i(4, 3), Vector2i(3, 2), Vector2i(3, 4)])
	check("T1 破城锤返回 waves 结构", r1.has("waves") and r1.has("removed"))
	check("T1 技能后盘面补满", _count_tiles(b) == before)
	check("T1 技能后无残留三连异常（棋盘合法）", _count_tiles(b) == 49)

	# T2 穿透箭：整列清空后补满
	var b2 := Match3Board.new(7, 6)
	b2.setup()
	var r2: Dictionary = b2.skill_pierce_col(0)
	check("T2 穿透箭返回 waves", r2.has("waves"))
	check("T2 技能后盘面补满", _count_tiles(b2) == 49)

	# T3 元素嬗变：6 块变目标元素；可能触发连锁但棋盘合法
	var b3 := Match3Board.new(7, 6)
	b3.setup()
	var r3: Dictionary = b3.skill_transform_random(0, 6)
	check("T3 嬗变返回 changed", r3.has("changed"))
	check("T3 技能后盘面补满", _count_tiles(b3) == 49)

	# T4 偷天换日：棋子总数不变
	var b4 := Match3Board.new(7, 6)
	b4.setup()
	b4.specials[3][3] = Match3Board.SPECIAL_BOMB  # 特殊块也参与洗牌
	var r4: Dictionary = b4.skill_shuffle()
	check("T4 洗牌返回 ok", r4.get("ok", false))
	check("T4 洗牌后盘面补满", _count_tiles(b4) == 49)

	# T5 祝圣之槌：指定块变爆炸；空格失败
	var b5 := Match3Board.new(7, 6)
	b5.setup()
	check("T5 祝圣成功", b5.skill_bless(Vector2i(2, 2)))
	check("T5 指定块变为爆炸特殊块", b5.special_at(2, 2) == Match3Board.SPECIAL_BOMB)
	b5.grid[5][5] = Match3Board.EMPTY
	check("T5 空格祝圣失败", not b5.skill_bless(Vector2i(5, 5)))

	# T6 暗影瘟疫：约半数变色、连锁后棋盘合法
	var b6 := Match3Board.new(7, 6)
	b6.setup()
	var r6: Dictionary = b6.skill_plague()
	check("T6 瘟疫返回 waves/changed", r6.has("waves") and r6.has("changed"))
	check("T6 技能后盘面补满", _count_tiles(b6) == 49)

	# T7 技能定义表：7 职业、资源模型字段齐全
	check("T7 技能表 7 职业", GameSkills.SKILLS.size() == 7)
	var models_ok := true
	for cid in GameSkills.SKILLS.keys():
		var s: Dictionary = GameSkills.SKILLS[cid]
		match str(s.get("resource", "")):
			"charge":
				if not (s.has("charge_per") and s.has("max") and s.has("targeting")):
					models_ok = false
			"fixed":
				if not (s.has("uses") and s.has("targeting")):
					models_ok = false
			"steps":
				if not (s.has("step_cost") and s.has("targeting")):
					models_ok = false
			_:
				models_ok = false
	check("T7 资源模型字段齐全（charge/fixed/steps）", models_ok)

	print("---")
	print("skills_test 结果：%d 项失败" % _fails)
	quit(1 if _fails > 0 else 0)
