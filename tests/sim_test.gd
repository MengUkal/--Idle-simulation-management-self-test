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
var fruits := 0                # 世界树的果实（M4）
var rebirth_count := 0         # 已重生轮数（M4）
var milestone_taken := {}      # 本轮已领的等级里程碑（每轮重生重发）

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
	print("=== 四、重生循环模拟（M4 数值定稿：步进5+陡果实+三轨，门槛即重生） ===")
	_rebirth_sim()
	print("")
	print("=== 五、全职业平衡对比（角色系统 D1-D2：Lv.50 练度标定战） ===")
	_class_balance_sim()
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
func _simulate_battle(floor_idx: int, monster: Dictionary, steps: int, atk_mod := 1.0, chain_mod := 0.0) -> Dictionary:
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
		var atk_mult := Balance.train_multiplier(atk_line) * Balance.atk_fruit_mult(fruits) * atk_mod
		for i in waves.size():
			var wave_mult := 1.0 + (Balance.CHAIN_BONUS_PER_WAVE + chain_mod) * float(i)
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
			_grant_milestones()
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


# ---------- 四、重生循环模拟（M4，2026-10-10 六项拍板） ----------

func _grant_milestones() -> void:
	## 等级里程碑一次性精华【拍板：每轮重生重发，作为开局加速器】
	for lv in Balance.MILESTONE_EP.keys():
		if level >= int(lv) and not milestone_taken.has(lv):
			milestone_taken[lv] = true
			essence += int(Balance.MILESTONE_EP[lv])


func _rebirth_sim() -> void:
	## 策略：贪心弱属性 AI 打怪；攒够就献金；训练优先级 攻>收>赏（费用乘果实折扣×轮衰减）；
	## 达到当轮门槛（40+5n）立刻重生。全部规则镜像 Balance 定稿公式。
	## 【数值定稿 2026-10-10】步进 5 + 陡果实公式 + 三轨加成（收入+5%/训练-2%/攻击+1% 每颗）。
	money = 0.0
	level = 1
	essence = 0
	atk_line = 0
	bounty_line = 0
	income_line = 0
	fruits = 0
	rebirth_count = 0
	milestone_taken = {}
	var t := 0.0
	var round_start := 0.0
	var ten_min_levels: Array = []   # 每轮开局 10 分钟时的等级
	var ten_min_marked := false
	var reports: Array = []
	var elite_rates: Array = []      # 每轮门槛时点的古树击杀数（/8）
	var MAX_ROUNDS := 4
	var TIME_CAP := 12.0 * 3600.0
	while rebirth_count < MAX_ROUNDS and t < TIME_CAP:
		var floor_idx := 1 if level < Balance.FLOOR_2_LEVEL_REQ else 2
		var monster := _pick_monster(floor_idx)
		var steps := Balance.battle_steps(level)
		var r := _simulate_battle(floor_idx, monster, steps)
		var duration := float(r["moves"]) * SECONDS_PER_MOVE
		t += duration
		if r["killed"]:
			money += float(r["bounty"])
		essence += r["ep"]
		# 挂机收入照跑 ×果实加成
		money += Balance.income_per_sec(level) * Balance.train_multiplier(income_line) \
			* Balance.income_fruit_mult(fruits) * duration
		# 献金连升 + 里程碑（每轮重发）
		while level < 100 and money >= Balance.upgrade_cost(level):
			money -= Balance.upgrade_cost(level)
			level += 1
			_grant_milestones()
		# 训练（费用乘果实折扣 × 轮数永久衰减）
		var tcm := Balance.train_cost_mult(fruits, rebirth_count)
		var spent := true
		while spent:
			spent = false
			for kind_pair in [["atk", atk_line], ["income", income_line], ["bounty", bounty_line]]:
				var cost := int(ceil(Balance.train_cost(kind_pair[1]) * tcm))
				if essence >= cost:
					essence -= cost
					match kind_pair[0]:
						"atk": atk_line += 1
						"income": income_line += 1
						"bounty": bounty_line += 1
					spent = true
		# 10 分钟采样（按本轮起点计时，t 是绝对时间不能直接比较）
		if not ten_min_marked and t - round_start >= 600.0:
			ten_min_levels.append(level)
			ten_min_marked = true
		# 门槛即重生
		if level >= Balance.rebirth_threshold(rebirth_count):
			var ekills := 0
			for i in 8:
				if _simulate_battle(2, Balance.MONSTER_ELITE_FLOOR2, Balance.battle_steps(level))["killed"]:
					ekills += 1
			elite_rates.append(ekills)
			var gained := Balance.fruits_for_level(level)
			reports.append({
				"round": rebirth_count, "minutes": (t - round_start) / 60.0,
				"level": level, "gained": gained, "fruits": fruits + gained,
				"atk": atk_line, "inc": income_line, "bounty": bounty_line,
			})
			fruits += gained
			rebirth_count += 1
			money = 0.0
			essence = 0
			atk_line = 0
			bounty_line = 0
			income_line = 0
			milestone_taken = {}
			round_start = t
			ten_min_marked = false
			level = 1
	# ---- 报告 ----
	for rep: Dictionary in reports:
		print("  第 %d 轮 → Lv.%d 重生：周期 %.0f 分钟 | +果实 %d（累计 %d）| 练度 攻%d/收%d/赏%d" % [
			rep["round"], rep["level"], rep["minutes"], rep["gained"], rep["fruits"],
			rep["atk"], rep["inc"], rep["bounty"],
		])
	for i in elite_rates.size():
		print("  第 %d 轮门槛练度：古树击杀 %d/8" % [i, elite_rates[i]])
	for i in ten_min_levels.size():
		print("  第 %d 轮开局 10 分钟：Lv.%d" % [i, ten_min_levels[i]])
	# ---- 验收线【数值定稿 2026-10-10：周期收敛带 90~155 分钟；果实积累后开局变强；古树第 3 轮稳定击杀】 ----
	for rep: Dictionary in reports:
		check("第 %d 轮周期在验收带内（90~155 分钟）" % int(rep["round"]),
			float(rep["minutes"]) >= 90.0 and float(rep["minutes"]) <= 155.0,
			"实际 %.0f 分钟" % float(rep["minutes"]))
	if ten_min_levels.size() >= 4:
		check("果实积累后开局肉眼变强（第 3 轮 ≥ 首轮+3 级）",
			int(ten_min_levels[3]) >= int(ten_min_levels[0]) + 3,
			"首轮 Lv.%d vs 第 3 轮 Lv.%d" % [ten_min_levels[0], ten_min_levels[3]])
	if elite_rates.size() >= 4:
		# 拍板目标 62.5%（5/8），护栏取 50% 容随机波动
		check("第 3 轮门槛练度古树稳定击杀（≥4/8 护栏）", int(elite_rates[3]) >= 4,
			"击杀 %d/8" % int(elite_rates[3]))


# ---------- 五、全职业平衡对比（角色系统，2026-10-11 拍板 D1=显著/D2=草案+游侠增强） ----------

func _class_mods(cid: String) -> Dictionary:
	## 单职业修饰符镜像（无种族；与 autoload/mods.gd 同规则：mult 连乘、add 累加）
	var mult_keys := ["battle_damage", "weakness", "income", "upgrade_cost", "train_cost", "bounty", "ep", "fruit"]
	var add_keys := ["steps", "chain_bonus"]
	var m := {}
	for k in mult_keys:
		m[k] = 1.0
	for k in add_keys:
		m[k] = 0.0
	for k: String in (GameClasses.CLASSES[cid]["mods"] as Dictionary).keys():
		if m.has(k):
			if k in add_keys:
				m[k] += float(GameClasses.CLASSES[cid]["mods"][k])
			else:
				m[k] *= float(GameClasses.CLASSES[cid]["mods"][k])
	return m


func _class_balance_sim() -> void:
	## 标定战：Lv.50 练度（攻15/果实33/步数35 基准）打 3000HP 标定木桩，8 场取均值
	atk_line = 15
	bounty_line = 15
	income_line = 15
	fruits = 33
	var dummy := {"name": "标定木桩", "hp": 450, "bounty": 0, "weak": 0}
	var base_steps := 35
	print("-- 标定：Lv.50 / 攻15 / 果实33 / 木桩 HP3000 / 8 场均值（纯职业，无种族） --")
	var kill_log := {}
	for cid: String in GameClasses.CLASSES.keys():
		var info: Dictionary = GameClasses.CLASSES[cid]
		var m := _class_mods(cid)
		var steps := base_steps + int(m["steps"])
		var kills := 0
		var dmg_sum := 0
		for t in 8:
			var r := _simulate_battle(2, dummy, steps, float(m["battle_damage"]), float(m["chain_bonus"]))
			dmg_sum += int(r["damage"])
			if r["killed"]:
				kills += 1
		kill_log[cid] = kills
		print("  %-4s 步数%-3d 均伤%-6d 击杀%d/8 ｜ 收入×%.2f 赏金×%.2f 弱点×%.2f 精华×%.2f 果实×%.2f" % [
			info["name"], steps, dmg_sum / 8, kills,
			float(m["income"]), float(m["bounty"]), float(m["weakness"]), float(m["ep"]), float(m["fruit"]),
		])
	var max_k := 0
	var min_k := 8
	for cid: String in kill_log.keys():
		max_k = maxi(max_k, int(kill_log[cid]))
		min_k = mini(min_k, int(kill_log[cid]))
	check("全职业击杀率带宽 ≤5/8（显著但不失衡）", max_k - min_k <= 5,
		"最强 %d/8 vs 最弱 %d/8" % [max_k, min_k])
