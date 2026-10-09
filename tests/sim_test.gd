extends SceneTree
## 数值与机制模拟测试（无头）：用真实 Balance 公式 + 真实 Match3Board 引擎试玩。
##   godot --headless --path . --script res://tests/sim_test.gd
## 说明：GameState 是自动加载单例，-s 脚本模式不可用，故此处用同公式镜像一份玩家状态。

const SEED := 20261009
const SECONDS_PER_MOVE := 4.0  # 假设玩家每步思考+操作 4 秒

var money := 0.0
var level := 1
var essence := 0
var atk_line := 0
var bounty_line := 0
var income_line := 0

var _fails := 0


func check(case_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS  " + case_name)
	else:
		_fails += 1
		print("FLAG  %s  %s" % [case_name, detail])


func _init() -> void:
	seed(SEED)
	print("=== 一、单场战斗伤害表（贪心弱属性 AI，10 场取均值） ===")
	_damage_table(1, 0)
	_damage_table(10, 0)
	_damage_table(10, 10)
	_damage_table(20, 10)
	print("")
	print("=== 二、纯挂机到 Lv.10（自动献金，无战斗） ===")
	_idle_only_sim()
	print("")
	print("=== 三、主动游玩 2 小时模拟（战斗 + 献金 + 训练线） ===")
	_active_sim()
	print("")
	print("---")
	print("模拟结束：%d 项标记" % _fails)
	quit(1 if _fails > 0 else 0)


# ---------- 工具 ----------

func _pick_monster(floor_idx: int) -> Dictionary:
	if randf() < Balance.ELITE_CHANCE:
		return Balance.monster_elite(floor_idx)
	var pool: Array = Balance.monster_pool(floor_idx)
	return pool[randi() % pool.size()]


## 贪心 AI 打一场：每步枚举全部相邻交换，选弱属性加权消除最大的
func _simulate_battle(floor_idx: int, monster: Dictionary, steps: int) -> Dictionary:
	var board := Match3Board.new(Balance.BOARD_SIZE, Balance.ELEMENT_KINDS)
	board.setup()
	board.ensure_playable()
	var hp := float(int(monster["hp"]))
	var total_dmg := 0
	var ep := 0
	var moves_used := 0
	for s in steps:
		# 评估所有交换：score = 首波消除格的克制倍率之和
		var best_score := -1.0
		var best_a := Vector2i(-1, -1)
		var best_b := Vector2i(-1, -1)
		for r in Balance.BOARD_SIZE:
			for c in Balance.BOARD_SIZE:
				for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
					var b := Vector2i(c, r) + d
					if b.x >= Balance.BOARD_SIZE or b.y >= Balance.BOARD_SIZE:
						continue
					var a := Vector2i(c, r)
					board.swap_cells(a, b)
					var matches := board.find_matches()
					var score := 0.0
					for cell in matches:
						score += Balance.damage_multiplier(int(board.grid[cell.y][cell.x]), monster)
					# 特效参与的交换永远有效（近似估值）
					if board.special_at(a.y, a.x) != Match3Board.SPECIAL_NONE or board.special_at(b.y, b.x) != Match3Board.SPECIAL_NONE:
						score = maxf(score, 2.5)
					board.swap_cells(a, b)
					if score > best_score:
						best_score = score
						best_a = a
						best_b = b
		if best_score < 0.0:
			# 无颜色匹配可用时，激活场上任意直线/爆炸特效
			var sp_found := false
			for r2 in Balance.BOARD_SIZE:
				for c2 in Balance.BOARD_SIZE:
					var sp := board.special_at(r2, c2)
					if sp >= Match3Board.SPECIAL_LINE_H and sp <= Match3Board.SPECIAL_BOMB and c2 + 1 < Balance.BOARD_SIZE:
						best_a = Vector2i(c2, r2)
						best_b = Vector2i(c2 + 1, r2)
						sp_found = true
						break
				if sp_found:
					break
			if not sp_found:
				break  # 无有效交换
		var rep: Dictionary = board.try_swap(best_a, best_b)
		if not rep.get("ok", false):
			continue
		moves_used += 1
		var waves: Array = rep["waves"]
		var dmg_f := 0.0
		var atk_mult := Balance.train_multiplier(atk_line)
		for i in waves.size():
			var wave_mult := 1.0 + Balance.CHAIN_BONUS_PER_WAVE * float(i)
			for entry in waves[i]:
				var m := Balance.damage_multiplier(int(entry["element"]), monster)
				if m > 1.0:
					ep += int(Balance.EP_PER_TILE * Balance.EP_WEAKNESS_MULT)
				else:
					ep += Balance.EP_PER_TILE
				dmg_f += wave_mult * m * atk_mult
		total_dmg += int(ceil(dmg_f))
		hp -= dmg_f
		if hp <= 0.0:
			break
		board.ensure_playable()
	var killed := hp <= 0.0
	var bounty := int(ceil(int(monster["bounty"]) * Balance.train_multiplier(bounty_line)))
	return {
		"damage": total_dmg, "ep": ep, "killed": killed,
		"bounty": bounty if killed else 0, "moves": moves_used,
	}


func _damage_table(player_level: int, line_levels: int) -> void:
	atk_line = line_levels
	bounty_line = line_levels
	var steps := Balance.battle_steps(player_level)
	print("-- Lv.%d（步数 %d，攻击/赏金线 +%d 级）--" % [player_level, steps, line_levels])
	for floor_idx in [1, 2]:
		var pool: Array = Balance.monster_pool(floor_idx)
		for mi in pool.size():
			var monster: Dictionary = pool[mi]
			var kills := 0
			var dmg_sum := 0
			var ep_sum := 0
			var trials := 8
			for t in trials:
				var r := _simulate_battle(floor_idx, monster, steps)
				dmg_sum += r["damage"]
				ep_sum += r["ep"]
				if r["killed"]:
					kills += 1
			print("  F%d %-6s HP%-4d 赏金%-3d  击杀率 %2d/%d  均伤害 %-5d 均精华 %-3d" % [
				floor_idx, monster["name"], int(monster["hp"]), int(monster["bounty"]),
				kills, trials, dmg_sum / trials, ep_sum / trials,
			])
		var elite: Dictionary = Balance.monster_elite(floor_idx)
		var ekills := 0
		for t in 8:
			if _simulate_battle(floor_idx, elite, steps)["killed"]:
				ekills += 1
		print("  F%d ★%-5s HP%-4d 赏金%-3d  击杀率 %2d/8" % [
			floor_idx, elite["name"], int(elite["hp"]), int(elite["bounty"]), ekills,
		])


func _idle_only_sim() -> void:
	money = 0.0
	level = 1
	income_line = 0
	var t := 0.0
	var next_cost := Balance.upgrade_cost(level)
	while level < Balance.FLOOR_2_LEVEL_REQ and t < 7200.0:
		var inc := Balance.income_per_sec(level) * Balance.train_multiplier(income_line)
		var need := next_cost - money
		var wait := need / inc
		t += wait
		money = 0.0  # 精确攒到费用才献金，献金后归零（模拟真实扣款）
		level += 1
		next_cost = Balance.upgrade_cost(level)
	if level >= Balance.FLOOR_2_LEVEL_REQ:
		print("纯挂机到 Lv.10 用时：%.1f 分钟（拍板目标 30 分钟以上）" % (t / 60.0))
		check("纯挂机到二层 ≥ 30 分钟", t / 60.0 >= 30.0, "实际 %.1f 分钟" % (t / 60.0))
	else:
		check("纯挂机 2 小时内到二层", false, "超时未达成")


func _active_sim() -> void:
	money = 0.0
	level = 1
	essence = 0
	atk_line = 0
	bounty_line = 0
	income_line = 0
	var t := 0.0
	var lv10_time := -1.0
	var floor_idx := 1
	var battles := 0
	var kills := 0
	var floor2_kills := 0
	var floor2_battles := 0
	var timeline := [10, 20, 40, 60, 90, 120]  # 分钟采样点
	var ti := 0
	while t < 7200.0:
		# 打一场
		var monster := _pick_monster(floor_idx)
		var steps := Balance.battle_steps(level)
		var r := _simulate_battle(floor_idx, monster, steps)
		var duration := float(r["moves"]) * SECONDS_PER_MOVE
		t += duration
		battles += 1
		if r["killed"]:
			kills += 1
			if floor_idx >= 2:
				floor2_battles += 1
				floor2_kills += 1
			money += float(r["bounty"])
		else:
			if floor_idx >= 2:
				floor2_battles += 1
		essence += r["ep"]
		# 挂机收入照跑
		money += Balance.income_per_sec(level) * Balance.train_multiplier(income_line) * duration
		# 花：献金（攒够就升，可连升）
		while level < 60 and money >= Balance.upgrade_cost(level):
			money -= Balance.upgrade_cost(level)
			level += 1
		# 花：训练线（策略：攻击 > 收入 > 赏金，能升就升）
		var spent := true
		while spent:
			spent = false
			for kind_pair in [["atk", atk_line], ["income", income_line], ["bounty", bounty_line]]:
				var cost := int(Balance.train_cost(kind_pair[1]))
				if essence >= cost:
					essence -= cost
					match kind_pair[0]:
						"atk": atk_line += 1
						"income": income_line += 1
						"bounty": bounty_line += 1
					spent = true
		# Lv.10 后切二层（收益更高）
		if level >= Balance.FLOOR_2_LEVEL_REQ:
			if lv10_time < 0.0:
				lv10_time = t
			floor_idx = 2
		# 采样输出
		while ti < timeline.size() and t >= timeline[ti] * 60.0:
			print("  [%3d 分钟] Lv.%-3d 吉尔 %-7.0f 精华 %-4d 攻线 %-2d 收线 %-2d 赏线 %-2d" % [
				timeline[ti], level, money, essence, atk_line, income_line, bounty_line,
			])
			ti += 1
	print("主动游玩：%d 场战斗，击杀 %d（%.0f%%）" % [battles, kills, 100.0 * kills / maxf(battles, 1)])
	if lv10_time > 0.0:
		print("主动游玩到 Lv.10 用时：%.1f 分钟（纯挂机 %.0f 分钟的对照）" % [lv10_time / 60.0, 30.0])
		check("主动游玩明显快于纯挂机（<30 分钟）", lv10_time / 60.0 < 30.0, "%.1f 分钟" % (lv10_time / 60.0))
	print("2 小时后：Lv.%d，二层战斗 %d 场击杀 %d（%.0f%%）" % [
		level, floor2_battles, floor2_kills, 100.0 * floor2_kills / maxf(floor2_battles, 1),
	])
	check("二层在成型练度下可正常击杀（≥60%）", floor2_battles == 0 or floor2_kills * 100 / floor2_battles >= 60,
		"二层击杀率仅 %d%%" % (100 * floor2_kills / maxf(floor2_battles, 1)))
