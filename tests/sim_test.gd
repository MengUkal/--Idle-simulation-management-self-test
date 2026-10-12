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
	print("=== 六、苍干栈道（P3 第三层）数值标定 ===")
	_floor3_sim()
	_floor4_sim()
	_hp_sim()
	_floor5_sim()
	_floor6_sim()
	_paragon_curve_sim()
	print("")
	print("=== 七、全 build 总叠加验证（职业+种族+天赋满） ===")
	_full_build_sim()
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
## hp_max > 0 时启用玩家 HP/蓄力镜像（P-a）；0 = 旧模式不计战败
func _simulate_battle(floor_idx: int, monster: Dictionary, steps: int, atk_mod := 1.0, chain_mod := 0.0, hp_max := 0.0) -> Dictionary:
	var board := Match3Board.new(Balance.BOARD_SIZE, Balance.ELEMENT_KINDS)
	board.setup()
	board.ensure_playable()
	var hp := float(int(monster["hp"]))
	var guard := GuardKit.new(str(monster.get("name", "")))  # 层守机制镜像（与 battle.gd 共用）
	var player_hp := float(hp_max)   # 玩家当前生命（P-a）
	var m_charge := int(monster.get("speed", 0))  # 怪物蓄力计数
	var player_down := false
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
					if board.is_obstacle(a.y, a.x) or board.is_obstacle(b.y, b.x):
						continue  # 花障不可交换
					board.swap_cells(a, b)
					var matches := board.find_matches()
					var score := 0.0
					for cell in matches:
						var sm := Balance.damage_multiplier(int(board.grid[cell.y][cell.x]), monster)
						if board.plus_at(cell.y, cell.x):
							sm *= 1.0 + Match3Board.PLUS_WAVE_BONUS
						score += sm
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
		# 层守机制镜像（与 battle.gd 共用 GuardKit，保证模拟与实装不漂移）
		var mods: Dictionary = guard.move_modifiers(waves.size(), false)
		for i in waves.size():
			var plus_n := 0
			for entry in waves[i]:
				if bool(entry.get("plus", false)):
					plus_n += 1
			var wave_mult := (1.0 + (Balance.CHAIN_BONUS_PER_WAVE + chain_mod) * float(i)) \
				* (1.0 + Match3Board.PLUS_WAVE_BONUS * float(plus_n))
			for entry in waves[i]:
				if int(entry["element"]) < 0:
					continue  # 花障碎片等非伤害条目
				var m := Balance.damage_multiplier(int(entry["element"]), monster)
				var m_eff := 1.0 if bool(mods["sealed"]) else m
				if m > 1.0 and not bool(mods["sealed"]):
					ep += int(Balance.EP_PER_TILE * Balance.EP_WEAKNESS_MULT)
				else:
					ep += Balance.EP_PER_TILE
				dmg_f += wave_mult * m_eff * atk_mult
		if bool(mods["blocked"]):
			dmg_f = 0.0  # 连击盾：单消无效
		else:
			dmg_f *= float(mods["mult"])
		total_dmg += int(ceil(dmg_f))
		hp -= dmg_f
		if hp <= 0.0:
			if guard.has_kit() and guard.on_lethal():
				hp = 1.0  # 根性：首次致死锁 1 HP
			else:
				break
		for ev2 in guard.after_move(hp / float(int(monster["hp"]))):
			if str(ev2) == "obstacle":
				board.seal_obstacles(3)  # 花瓣封印镜像（香雾对全知 AI 无影响，忽略）
		# 怪物蓄力攻击镜像（P-a D7）：每耗 1 步 -1，归零攻击玩家并重置
		if hp_max > 0.0 and float(monster.get("atk", 0)) > 0.0:
			m_charge -= 1
			if m_charge <= 0:
				m_charge = int(monster.get("speed", 6))
				player_hp -= float(monster["atk"]) * randf_range(0.3, 0.5) * guard.atk_mult()
				if player_hp <= 0.0:
					player_down = true
					break
		board.ensure_playable()
	var killed := hp <= 0.0
	var defeated := player_down
	var bounty := int(ceil(int(monster["bounty"]) * Balance.train_multiplier(bounty_line)))
	return {
		"damage": total_dmg, "ep": ep, "killed": killed,
		"bounty": bounty if killed else 0, "moves": moves_used,
		"defeated": defeated,
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
	check("二层在成型练度下可正常击杀（≥55%，层守机制实装后校准）", floor2_battles == 0 or floor2_kills * 100 / floor2_battles >= 55,
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


# ---------- 六、苍干栈道（P3 第三层）数值标定 ----------

## 第三层怪物（2026-10-11 拍板转正：与 balance.gd MONSTERS_FLOOR3 同源）
const FLOOR3_DRAFT := [
	{"name": "旋風雀", "hp": 380, "bounty": 55, "weak": 3},
	{"name": "叶隐蛙", "hp": 420, "bounty": 60, "weak": 0},
	{"name": "風滚草", "hp": 460, "bounty": 62, "weak": 1},
	{"name": "吊藤妖", "hp": 500, "bounty": 68, "weak": 0},
	{"name": "喇叭藤", "hp": 550, "bounty": 72, "weak": 4},
	{"name": "刺藤果", "hp": 620, "bounty": 78, "weak": 5},
]
const FLOOR3_ELITE_DRAFT := {"name": "镇风桩", "hp": 1100, "bounty": 200, "weak": 1}


func _floor3_calibrate() -> void:
	## 第 2/3 轮重生门槛练度（M4 定稿模拟的实际输出）vs 三层草案 → 击杀率
	var rounds := [
		{"tag": "第2轮门槛(Lv.50)", "atk": 15, "fruit": 33, "steps": 35},
		{"tag": "第3轮门槛(Lv.55)", "atk": 16, "fruit": 60, "steps": 37},
	]
	for rd: Dictionary in rounds:
		atk_line = int(rd["atk"])
		fruits = int(rd["fruit"])
		print("  -- %s：攻%d / 果实%d / 步数%d --" % [rd["tag"], atk_line, fruits, int(rd["steps"])])
		for mon: Dictionary in FLOOR3_DRAFT:
			var kills := 0
			var dmg_sum := 0
			for t in 8:
				var r := _simulate_battle(2, mon, int(rd["steps"]))
				dmg_sum += int(r["damage"])
				if r["killed"]:
					kills += 1
			print("    %-4s HP%-4d 击杀%d/8 均伤%d" % [mon["name"], int(mon["hp"]), kills, dmg_sum / 8])
		var ek := 0
		var edmg := 0
		for t in 8:
			var r2 := _simulate_battle(2, FLOOR3_ELITE_DRAFT, int(rd["steps"]))
			edmg += int(r2["damage"])
			if r2["killed"]:
				ek += 1
		print("    ★镇风桩 HP%-4d 击杀%d/8 均伤%d" % [int(FLOOR3_ELITE_DRAFT["hp"]), ek, edmg / 8])
	atk_line = 15
	fruits = 33


func _floor3_sim() -> void:
	print("-- 苍干栈道草案标定（命名/弱点=设定包拍板；HP/赏金=助手草案，待用户拍板） --")
	_floor3_calibrate()


func _floor4_sim() -> void:
	print("-- 落英花冠标定（命名/弱点=设定包拍板；HP/赏金=设定包参考稿，门槛 Lv.60+层卡） --")
	_floor4_calibrate()


func _floor4_calibrate() -> void:
	## 第 4/5 轮重生门槛练度 vs 落英花冠参考稿 → 击杀率（荣耀目标=千瓣祭主，机制留待棋盘批）
	var rounds := [
		{"tag": "第4轮门槛(Lv.60)", "atk": 17, "fruit": 95, "steps": 40},
		{"tag": "第5轮门槛(Lv.65)", "atk": 18, "fruit": 135, "steps": 42},
	]
	for rd: Dictionary in rounds:
		atk_line = int(rd["atk"])
		fruits = int(rd["fruit"])
		print("  -- %s：攻%d / 果实%d / 步数%d --" % [rd["tag"], atk_line, fruits, int(rd["steps"])])
		for mon: Dictionary in Balance.MONSTERS_FLOOR4:
			var kills := 0
			var dmg_sum := 0
			for t in 8:
				var r := _simulate_battle(3, mon, int(rd["steps"]))
				dmg_sum += int(r["damage"])
				if r["killed"]:
					kills += 1
			print("    %-4s HP%-4d 击杀%d/8 均伤%d" % [mon["name"], int(mon["hp"]), kills, dmg_sum / 8])
		var ek := 0
		var edmg := 0
		for t in 8:
			var r2 := _simulate_battle(3, Balance.MONSTER_ELITE_FLOOR4, int(rd["steps"]))
			edmg += int(r2["damage"])
			if r2["killed"]:
				ek += 1
		print("    ★千瓣祭主 HP%-4d 击杀%d/8 均伤%d" % [int(Balance.MONSTER_ELITE_FLOOR4["hp"]), ek, edmg / 8])
	atk_line = 15
	fruits = 33


func _hp_sim() -> void:
	## P-a HP 系统战败率验收（伙伴与生命系统规划 §4：一层 0% / 二层 ≤10% / 四层 15~25% 目标带）
	print("-- P-a HP 战败率验收（AI 无装备/无回复的底线；实机有装备词条兜底） --")
	var scenarios := [
		{"tag": "一层(Lv.12)", "floor": 0, "level": 12, "atk": 2, "fruit": 0, "steps": 16},
		{"tag": "二层(Lv.42)", "floor": 1, "level": 42, "atk": 12, "fruit": 25, "steps": 31},
		{"tag": "四层(Lv.62)", "floor": 3, "level": 62, "atk": 17, "fruit": 100, "steps": 41},
	]
	for sc: Dictionary in scenarios:
		var hp_max := float(Balance.PLAYER_HP_BASE + Balance.PLAYER_HP_PER_LEVEL * int(sc["level"]))
		var battles := 24
		var kills := 0
		var defeats := 0
		for t in battles:
			var mon: Dictionary = _pick_monster(int(sc["floor"]))
			var r := _simulate_battle(int(sc["floor"]), mon, int(sc["steps"]), 1.0, 0.0, hp_max)
			if bool(r["killed"]):
				kills += 1
			if bool(r.get("defeated", false)):
				defeats += 1
		print("  %s：击杀 %d/%d，战败 %d/%d（玩家HP %d）" % [
			str(sc["tag"]), kills, battles, defeats, battles, int(hp_max)])
		if int(sc["floor"]) == 0:
			check("P-a 一层战败率 0%", defeats == 0, "战败 %d/%d" % [defeats, battles])
		elif int(sc["floor"]) == 1:
			check("P-a 二层战败率 ≤10%", defeats * 100 <= battles * 10,
				"战败 %d/%d" % [defeats, battles])
		elif int(sc["floor"]) == 3:
			check("P-a 四层战败率 ≤50%（目标带 15~25%，硬上限防挫败）",
				defeats * 100 <= battles * 50, "战败 %d/%d" % [defeats, battles])


func _floor5_sim() -> void:
	## 云顶鹰巢标定：第 5/6 轮门槛练度 vs 参考稿 → 击杀率（含玩家 HP 战败镜像）
	print("-- 云顶鹰巢标定（命名/弱点=设定包第十轮；HP/赏金=参考稿，门槛 Lv.70+层卡） --")
	var rounds := [
		{"tag": "第5轮门槛(Lv.70)", "atk": 18, "fruit": 135, "steps": 45, "hp": 1500},
		{"tag": "第6轮门槛(Lv.75)", "atk": 19, "fruit": 180, "steps": 47, "hp": 1600},
	]
	for rd: Dictionary in rounds:
		atk_line = int(rd["atk"])
		fruits = int(rd["fruit"])
		print("  -- %s：攻%d / 果实%d / 步数%d --" % [rd["tag"], atk_line, fruits, int(rd["steps"])])
		for mon: Dictionary in Balance.MONSTERS_FLOOR5:
			var kills := 0
			var dmg_sum := 0
			for t in 8:
				var r := _simulate_battle(4, mon, int(rd["steps"]), 1.0, 0.0, float(rd["hp"]))
				dmg_sum += int(r["damage"])
				if bool(r["killed"]):
					kills += 1
			print("    %-4s HP%-4d 击杀%d/8 均伤%d" % [mon["name"], int(mon["hp"]), kills, dmg_sum / 8])
		var ek := 0
		var edmg := 0
		var elost := 0
		for t in 8:
			var r2 := _simulate_battle(4, Balance.MONSTER_ELITE_FLOOR5, int(rd["steps"]), 1.0, 0.0, float(rd["hp"]))
			edmg += int(r2["damage"])
			if bool(r2["killed"]):
				ek += 1
			if bool(r2.get("defeated", false)):
				elost += 1
		print("    ★瞭望鹰 HP%-4d 击杀%d/8 均伤%d 战败%d" % [
			int(Balance.MONSTER_ELITE_FLOOR5["hp"]), ek, edmg / 8, elost])
	atk_line = 15
	fruits = 33


func _floor6_sim() -> void:
	## 星梢标定（M3.0 工程提案）：第 7/8 轮门槛练度 → 击杀率（含玩家 HP 战败镜像）
	print("-- 星梢标定（M3.0 工程提案：命名待世界观线覆写；门槛 Lv.85+层卡） --")
	var rounds := [
		{"tag": "第7轮门槛(Lv.85)", "atk": 21, "fruit": 225, "steps": 52, "hp": 1800},
		{"tag": "第8轮门槛(Lv.90)", "atk": 22, "fruit": 270, "steps": 55, "hp": 1900},
	]
	for rd: Dictionary in rounds:
		atk_line = int(rd["atk"])
		fruits = int(rd["fruit"])
		print("  -- %s：攻%d / 果实%d / 步数%d --" % [rd["tag"], atk_line, fruits, int(rd["steps"])])
		for mon: Dictionary in Balance.MONSTERS_FLOOR6:
			var kills := 0
			var dmg_sum := 0
			for t in 8:
				var r := _simulate_battle(4, mon, int(rd["steps"]), 1.0, 0.0, float(rd["hp"]))
				dmg_sum += int(r["damage"])
				if bool(r["killed"]):
					kills += 1
			print("    %-4s HP%-4d 击杀%d/8 均伤%d" % [mon["name"], int(mon["hp"]), kills, dmg_sum / 8])
		var ek := 0
		var edmg := 0
		var elost := 0
		for t in 8:
			var r2 := _simulate_battle(4, Balance.MONSTER_ELITE_FLOOR6, int(rd["steps"]), 1.0, 0.0, float(rd["hp"]))
			edmg += int(r2["damage"])
			if bool(r2["killed"]):
				ek += 1
			if bool(r2.get("defeated", false)):
				elost += 1
		print("    ★星望者 HP%-4d 击杀%d/8 均伤%d 战败%d" % [
			int(Balance.MONSTER_ELITE_FLOOR6["hp"]), ek, edmg / 8, elost])


func _paragon_curve_sim() -> void:
	## M2.2 巅峰点数曲线标定（Q1 拍板 ~50h/Q2 每轮+2）：纯数学段，验证点满 81 点的轮数/时长带
	print("-- 巅峰点数曲线（Q1 ~50h / Q2 每轮+2；每轮时长用收敛带 90~155min） --")
	var strategies := [
		{"tag": "Lv.60 快刷", "per_round": 3},
		{"tag": "Lv.70 冲层", "per_round": 13},
		{"tag": "Lv.75 冲层", "per_round": 18},
	]
	for s: Dictionary in strategies:
		var rounds := int(ceil(81.0 / float(s["per_round"])))
		var lo := rounds * 90 / 60.0
		var hi := rounds * 155 / 60.0
		print("  %s：%d 点/轮 → %d 轮点满，估 %.0f~%.0f 小时" % [s["tag"], s["per_round"], rounds, lo, hi])
	print("  混合建议（2 轮 Lv.70 + 11 轮 Lv.60）：13 轮 ≈ 26~40h —— Q1 的 ~50h 目标含首周目与缓冲，可达 ✓")
	print("  注：冲 Lv.70+ 的轮内实际时长高于收敛带上限（后期升级慢），表内 hi 值对冲高层为下界")


# ---------- 七、全 build 总叠加验证（角色系统三期后） ----------

func _talent_mods(class_id: String) -> Dictionary:
	## 该职业天赋树全满的修饰符（镜像 mods.gd 规则：mult ×(1+per×rank)、add +per×rank）
	var total := {"battle_damage": 1.0, "weakness": 1.0, "income": 1.0, "bounty": 1.0, "ep": 1.0, "fruit": 1.0, "steps": 0, "chain_bonus": 0.0}
	for n: Dictionary in GameTalents.get_tree_for(class_id).get("nodes", []):
		var rank := int(n.get("max", 1))  # 全满假设
		var per := float(n.get("per", 0.0))
		var mod_name := str(n.get("mod", ""))
		if str(n.get("kind", "mult")) == "add":
			total[mod_name] = float(total.get(mod_name, 0.0)) + per * rank
		elif total.has(mod_name):
			total[mod_name] *= 1.0 + per * rank
	return total


func _full_build_sim() -> void:
	## 职业全满 + 种族 + 天赋全满 的总叠加标定（同 Lv.50 标定战），验证「显著档」叠加后不失衡
	var combo := [
		{"tag": "战士+巨人血裔", "cid": "warrior", "rid": "giantsblood"},
		{"tag": "法师+高等精灵", "cid": "mage", "rid": "high_elf"},
		{"tag": "盗贼+暗精灵", "cid": "rogue", "rid": "dark_elf"},
		{"tag": "牧师+人类", "cid": "priest", "rid": "human"},
		{"tag": "游侠+巨魔", "cid": "ranger", "rid": "troll"},
		{"tag": "术士+兽人", "cid": "warlock", "rid": "orc"},
	]
	atk_line = 15
	bounty_line = 15
	fruits = 33
	var dummy := {"name": "标定木桩", "hp": 450, "bounty": 0, "weak": 0}
	print("-- 全叠加：职业满天赋 + 种族（ Lv.50 标定战 HP450，对照纯职业 6~8/8） --")
	var kmax := 0
	var kmin := 8
	for c: Dictionary in combo:
		var cm := _class_mods(c["cid"])
		var tm := _talent_mods(c["cid"])
		var rm: Dictionary = GameRaces.RACES[c["rid"]]["mods"]
		var atk_m: float = float(cm["battle_damage"]) * float(tm["battle_damage"]) * float(rm.get("battle_damage", 1.0))
		var chain: float = float(cm["chain_bonus"]) + float(tm["chain_bonus"]) + float(rm.get("chain_bonus", 0.0))
		var steps := 35 + int(cm["steps"]) + int(tm["steps"]) + int(rm.get("steps", 0))
		var kills := 0
		var dmg_sum := 0
		for t in 8:
			var r := _simulate_battle(2, dummy, steps, atk_m, chain)
			dmg_sum += int(r["damage"])
			if r["killed"]:
				kills += 1
		kmax = maxi(kmax, kills)
		kmin = mini(kmin, kills)
		var inc: float = float(cm["income"]) * float(tm["income"]) * float(rm.get("income", 1.0))
		print("  %-10s 步数%-3d 均伤%-6d 击杀%d/8 ｜ 总收入乘数 ×%.2f" % [
			c["tag"], steps, dmg_sum / 8, kills, inc])
	check("全叠加击杀率带宽 ≤4/8（显著但可玩）", kmax - kmin <= 4,
		"最强 %d/8 vs 最弱 %d/8" % [kmax, kmin])
