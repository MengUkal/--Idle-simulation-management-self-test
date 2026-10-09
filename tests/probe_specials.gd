extends SceneTree
## 诊断：特殊方块的实际生成/存活频率（贪心 AI 打 400 步）

const SEED := 424242


func _count_specials(board: Match3Board) -> int:
	var n := 0
	for r in board.size:
		for c in board.size:
			if board.special_at(r, c) != Match3Board.SPECIAL_NONE:
				n += 1
	return n


func _init() -> void:
	seed(SEED)
	var board := Match3Board.new(7, 6)
	board.setup()
	board.ensure_playable()
	var moves := 400
	var ok_moves := 0
	var net_spawn_total := 0
	var survived_events := 0
	var consumed_events := 0
	var big_waves := 0  # 单波 ≥4 格（可能是 4 连/特效）
	var moves_end_with_special := 0
	var type_count := {}
	for m in moves:
		var before := _count_specials(board)
		# 贪心 AI：选消除格数最多的交换（特效参与给保底分）
		var best_score := -1.0
		var best_a := Vector2i(-1, -1)
		var best_b := Vector2i(-1, -1)
		for r in board.size:
			for c in board.size:
				for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
					var b := Vector2i(c, r) + d
					if b.x >= board.size or b.y >= board.size:
						continue
					var a := Vector2i(c, r)
					board.swap_cells(a, b)
					var matches := board.find_matches()
					var score := float(matches.size())
					if board.special_at(a.y, a.x) != Match3Board.SPECIAL_NONE or board.special_at(b.y, b.x) != Match3Board.SPECIAL_NONE:
						score = maxf(score, 2.5)
					board.swap_cells(a, b)
					if score > best_score:
						best_score = score
						best_a = a
						best_b = b
		if best_score < 0.0:
			board.setup()
			continue
		var rep: Dictionary = board.try_swap(best_a, best_b)
		if not rep.get("ok", false):
			continue
		ok_moves += 1
		var after := _count_specials(board)
		var net := after - before
		net_spawn_total += net
		if net > 0:
			survived_events += 1
		if net < 0:
			consumed_events += 1
		if after > 0:
			moves_end_with_special += 1
		for w in rep["waves"]:
			if (w as Array).size() >= 4:
				big_waves += 1
			for entry in w:
				if board.special_at((entry["cell"] as Vector2i).y, (entry["cell"] as Vector2i).x) != Match3Board.SPECIAL_NONE:
					pass
	# 统计场上存量按类型
	for r in board.size:
		for c in board.size:
			var sp := board.special_at(r, c)
			if sp != Match3Board.SPECIAL_NONE:
				var k := str(sp)
				type_count[k] = int(type_count.get(k, 0)) + 1
	print("有效步数: %d / %d" % [ok_moves, moves])
	print("单波≥4格(可能含4连/特效): %d 次" % big_waves)
	print("特效净增加事件: %d 次（生成后存活到回合结束）" % survived_events)
	print("特效净减少事件: %d 次（被引爆/消耗）" % consumed_events)
	print("特效净生成总数: %d" % net_spawn_total)
	print("以特效在场结束的回合: %d / %d（%.0f%%）" % [moves_end_with_special, ok_moves, 100.0 * moves_end_with_special / maxf(ok_moves, 1)])
	print("终局场上特效: %s" % type_count)
	quit(0)
