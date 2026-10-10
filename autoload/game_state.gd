extends Node
## 玩家数据唯一持有者：其他模块一律通过它读写，禁止各自缓存数值。
## 设定：等级 = 世界树赐予的祝福，向树献金（吉尔）即可提升。

var money := Balance.START_MONEY          # 当前吉尔
var level := Balance.START_LEVEL          # 当前等级
var floor_index := 1                      # 当前所在层（1 = 树根之街）
var total_earned := 0.0                   # 累计获得吉尔（统计用）
var essence := 0                          # 元素精华（三消获得，训练线消耗）
var atk_line := 0                         # 攻击训练线等级
var bounty_line := 0                      # 赏金训练线等级
var income_line := 0                      # 收入训练线等级
var holdings := [0, 0, 0]                 # 交易所持仓（按 Balance.MARKET_TARGETS 顺序）
var fruits := 0                           # 世界树的果实（重生永久货币，M4）
var rebirth_count := 0                    # 已重生轮数（M4）
var rebirth_guide_shown := false          # Lv.38 触墙引导已弹过（M4）
var character_class := ""                 # 职业 id（空 = 未创建，见 data/classes.gd）
var character_race := ""                  # 种族 id（见 data/races.gd）
var skill_points := 0                     # 天赋技能点（Lv.60 前每级 +1；消费于天赋树）
var paragon_points := 0                   # 巅峰点（Lv.60 起每级 +1；巅峰系统预留）
var talents := {}                         # 天赋记录 {节点id: rank}（见 data/talents.gd）
var floor3_card := false                  # 苍干栈道层卡（首杀守林古树掉落，P3）


func can_go_to_floor(index: int) -> bool:
	## 层间往返的目标层是否可去：一层自由；二层 Lv.10；三层 Lv.50 + 层卡
	match index:
		3:
			return level >= Balance.FLOOR_3_LEVEL_REQ and floor3_card
		2:
			return level >= Balance.FLOOR_2_LEVEL_REQ
		_:
			return index == 1


func unlock_floor3_card() -> bool:
	## 首杀守林古树掉落「苍干栈道层卡」；已持有返回 false
	if floor3_card:
		return false
	floor3_card = true
	EventBus.floor3_card_gained.emit()
	return true


func needs_character_creation() -> bool:
	## 未选职业（或职业 id 非法）= 需要进入角色创建
	return character_class == "" or not GameClasses.CLASSES.has(character_class) \
		or character_race == "" or not GameRaces.RACES.has(character_race)


func create_character(class_id: String, race_id: String) -> bool:
	## 角色创建（仅未创建时可调用）；创建后重算修饰符
	if character_class != "":
		return false
	if not GameClasses.CLASSES.has(class_id) or not GameRaces.RACES.has(race_id):
		return false
	character_class = class_id
	character_race = race_id
	Mods.recompute()
	EventBus.level_changed.emit(level)  # 广播一次，驱动各界面刷新
	return true


# ---------- 天赋树（二期，D4 经典被动树蓝本） ----------

func talent_invested() -> int:
	## 本职业树上已投入的总点数（层圈门槛依据）
	var total := 0
	for rank in talents.values():
		total += int(rank)
	return total


func my_tree_nodes() -> Array:
	## 当前职业天赋树的节点定义数组
	return GameTalents.get_tree_for(character_class).get("nodes", [])


func talent_buy(node_id: String) -> bool:
	## 购买/升级 1 级天赋节点（消耗 1 技能点）。校验：树归属/层圈门槛/等级上限/关键互斥/点数
	var def := GameTalents.get_node_def(node_id)
	if def.is_empty():
		return false
	var my_ids := {}
	for n in my_tree_nodes():
		my_ids[n["id"]] = true
	if not my_ids.has(node_id):
		return false
	if skill_points < 1:
		return false
	var ring := int(def.get("ring", 1))
	if talent_invested() < int(GameTalents.TREE_GATE[clampi(ring, 1, 4) - 1]):
		return false
	var rank := int(talents.get(node_id, 0))
	if rank >= int(def.get("max", 1)):
		return false
	# 关键天赋互斥：同树其他关键节点已点亮则拒绝（先退还）
	if def.has("key"):
		for n in my_tree_nodes():
			if n.has("key") and n["id"] != node_id and int(talents.get(n["id"], 0)) > 0:
				return false
	skill_points -= 1
	talents[node_id] = rank + 1
	# 关键天赋的副作用副节点（key_of 指回）同步点亮
	for n in my_tree_nodes():
		if str(n.get("key_of", "")) == node_id:
			talents[n["id"]] = 1
	Mods.recompute()
	EventBus.level_changed.emit(level)  # 广播刷新（天赋影响收入等实时数值）
	return true


func talent_refund(node_id: String) -> bool:
	## 退还 1 级天赋节点（免费，D4 式单点退还）；关键节点退还时同步撤掉副作用
	if not talents.has(node_id) or int(talents[node_id]) <= 0:
		return false
	talents[node_id] = int(talents[node_id]) - 1
	if int(talents[node_id]) <= 0:
		talents.erase(node_id)
		for n in my_tree_nodes():
			if str(n.get("key_of", "")) == node_id:
				talents.erase(n["id"])
	skill_points += 1
	Mods.recompute()
	EventBus.level_changed.emit(level)
	return true


func talent_respec_cost() -> int:
	## 整树重置费用（吉尔）：随已投入点数增长
	return talent_invested() * 50


func talent_respec_all() -> bool:
	## 整树重置：退还全部投入点数，收取吉尔（费用随投入增长）
	var invested := talent_invested()
	if invested <= 0:
		return false
	var cost := talent_respec_cost()
	if money < cost:
		EventBus.money_not_enough.emit(cost)
		return false
	money -= cost
	EventBus.money_changed.emit(money)
	talents.clear()
	skill_points += invested
	Mods.recompute()
	EventBus.level_changed.emit(level)
	return true


func income_per_sec() -> float:
	# 挂机收入 = 基础公式 × 收入训练线倍率 × 果实加成（M4）× 职业/种族修饰符
	return Balance.income_per_sec(level) * Balance.train_multiplier(income_line) \
		* Balance.income_fruit_mult(fruits) * Mods.mult("income")


func train_cost_for(kind: String) -> int:
	## 训练线升级实价 = 基础费用 × 果实折扣 × 轮数衰减 × 职业/种族修饰符
	return int(ceil(Balance.train_cost(line_level(kind)) * Balance.train_cost_mult(fruits, rebirth_count)
		* Mods.mult("train_cost")))


func add_essence(amount: int) -> void:
	if amount <= 0:
		return
	essence += amount
	EventBus.essence_changed.emit(essence)


func line_level(kind: String) -> int:
	match kind:
		"atk":
			return atk_line
		"bounty":
			return bounty_line
		"income":
			return income_line
	return 0


func upgrade_line(kind: String) -> bool:
	## 用元素精华升级训练线（NGU 式多线成长；费用乘果实折扣 × 轮数衰减 × 职业种族修饰符）
	var cost := train_cost_for(kind)
	if essence < cost:
		return false
	essence -= cost
	EventBus.essence_changed.emit(essence)
	match kind:
		"atk":
			atk_line += 1
		"bounty":
			bounty_line += 1
		"income":
			income_line += 1
	EventBus.line_changed.emit(kind, line_level(kind))
	if kind == "income":
		EventBus.income_changed.emit(income_per_sec())
	return true


# ---------- 重生转生（M4，2026-10-10 六项拍板） ----------

func rebirth_threshold() -> int:
	## 本轮重生所需等级（40 + 8×已重生轮数）
	return Balance.rebirth_threshold(rebirth_count)


func pending_fruits() -> int:
	## 若现在重生可获得的果实数（×果实获取修饰符，术士 +10%）
	return int(ceil(Balance.fruits_for_level(level) * Mods.mult("fruit")))


func rebirth_ready() -> bool:
	return level >= rebirth_threshold()


func do_rebirth() -> int:
	## 献上等级：重置换果实。返回本次获得的果实数（未达门槛返回 -1）。
	## 清零：等级/吉尔/精华/三训练线/所在层；保留：果实、持仓、行情、累计统计。
	if not rebirth_ready():
		return -1
	var gained := pending_fruits()
	fruits += gained
	rebirth_count += 1
	money = Balance.START_MONEY
	level = Balance.START_LEVEL
	floor_index = 1
	essence = 0
	atk_line = 0
	bounty_line = 0
	income_line = 0
	EventBus.money_changed.emit(money)
	EventBus.income_changed.emit(income_per_sec())
	EventBus.level_changed.emit(level)
	EventBus.floor_changed.emit(floor_index)
	EventBus.essence_changed.emit(essence)
	EventBus.line_changed.emit("atk", 0)
	EventBus.line_changed.emit("bounty", 0)
	EventBus.line_changed.emit("income", 0)
	EventBus.rebirth_performed.emit(gained, fruits, rebirth_count)
	return gained


func can_afford(cost: float) -> bool:
	return money >= cost


func add_money(amount: float) -> void:
	if amount <= 0.0:
		return
	money += amount
	total_earned += amount
	EventBus.money_changed.emit(money)


func try_spend(cost: float) -> bool:
	if not can_afford(cost):
		EventBus.money_not_enough.emit(cost)
		return false
	money -= cost
	EventBus.money_changed.emit(money)
	return true


func upgrade_level() -> bool:
	## 献金升级：花费吉尔提升等级（等级即收入）。
	if not try_spend(upgrade_cost()):
		return false
	level += 1
	if level >= GameTalents.PARAGON_LEVEL:
		paragon_points += 1  # 巅峰点分流（巅峰系统预留）
	else:
		skill_points += 1  # 天赋技能点
	EventBus.level_changed.emit(level)
	EventBus.income_changed.emit(income_per_sec())
	if level == Balance.FLOOR_2_LEVEL_REQ:
		EventBus.floor_unlocked.emit(level)
	return true


func upgrade_cost() -> float:
	## 下一级献金费用（含职业/种族修饰符）
	return ceil(Balance.upgrade_cost(level) * Mods.mult("upgrade_cost"))


func go_to_floor(index: int) -> void:
	## 层间往返（一层自由；二层需 Lv.10；三层需 Lv.50 + 层卡）
	if not can_go_to_floor(index):
		return
	floor_index = index
	EventBus.floor_changed.emit(index)


func reset() -> void:
	## 清空进度回到全新开局（只重置内存数据；删档由 SaveManager 负责）。
	money = Balance.START_MONEY
	level = Balance.START_LEVEL
	floor_index = 1
	total_earned = 0.0
	essence = 0
	atk_line = 0
	bounty_line = 0
	income_line = 0
	fruits = 0
	rebirth_count = 0
	rebirth_guide_shown = false
	character_class = ""
	character_race = ""
	skill_points = 0
	talents = {}
	floor3_card = false
	Mods.recompute()
	EventBus.money_changed.emit(money)
	EventBus.income_changed.emit(income_per_sec())
	EventBus.level_changed.emit(level)
	EventBus.floor_changed.emit(floor_index)
	EventBus.essence_changed.emit(essence)
	EventBus.line_changed.emit("atk", 0)
	EventBus.line_changed.emit("bounty", 0)
	EventBus.line_changed.emit("income", 0)
	holdings = [0, 0, 0]
	EventBus.holdings_changed.emit(0, 0)
	EventBus.holdings_changed.emit(1, 0)
	EventBus.holdings_changed.emit(2, 0)


# ---------- 交易所（M3） ----------

func market_fee_rate() -> float:
	## 当前手续费率（种族修饰符：矮人 -0.5%；下限 0）
	return maxf(0.0, Balance.MARKET_FEE_RATE + Mods.add("fee"))

func buy_stock(idx: int, shares: int) -> bool:
	## 买入标的（含手续费，手续费率受种族修饰符），成功返回 true
	if idx < 0 or idx >= holdings.size() or shares <= 0:
		return false
	var cost := Balance.trade_cost(Market.prices[idx], shares, market_fee_rate())
	if money < cost["total"]:
		EventBus.money_not_enough.emit(cost["total"])
		return false
	money -= cost["total"]
	holdings[idx] += shares
	EventBus.money_changed.emit(money)
	EventBus.holdings_changed.emit(idx, holdings[idx])
	return true


func sell_stock(idx: int, shares: int) -> bool:
	## 卖出标的（含 1% 手续费），成功返回 true
	if idx < 0 or idx >= holdings.size() or shares <= 0:
		return false
	shares = mini(shares, holdings[idx])
	if shares <= 0:
		return false
	var gain := Balance.sell_proceeds(Market.prices[idx], shares, market_fee_rate())
	money += gain
	holdings[idx] -= shares
	EventBus.money_changed.emit(money)
	EventBus.holdings_changed.emit(idx, holdings[idx])
	return true


# ---------- 开发修改器专用（release 构建不可达：修改器面板仅 debug 构建加载） ----------

func debug_set_level(new_level: int) -> void:
	## 【修改器】直接设置等级
	level = maxi(new_level, 1)
	EventBus.level_changed.emit(level)
	EventBus.income_changed.emit(income_per_sec())


func debug_add_line(kind: String, n: int) -> void:
	## 【修改器】免费提升训练线
	match kind:
		"atk":
			atk_line += n
		"bounty":
			bounty_line += n
		"income":
			income_line += n
	EventBus.line_changed.emit(kind, line_level(kind))
	if kind == "income":
		EventBus.income_changed.emit(income_per_sec())


func debug_set_line(kind: String, new_level: int) -> void:
	## 【修改器】直接设置训练线等级（可为 0，方便测试各档练度）
	var lv := maxi(new_level, 0)
	match kind:
		"atk":
			atk_line = lv
		"bounty":
			bounty_line = lv
		"income":
			income_line = lv
	EventBus.line_changed.emit(kind, line_level(kind))


func debug_set_rebirth(new_fruits: int, new_count: int) -> void:
	## 【修改器】直接设置果实与重生轮数（测试各档重生加成）
	fruits = maxi(new_fruits, 0)
	rebirth_count = maxi(new_count, 0)
	EventBus.income_changed.emit(income_per_sec())
