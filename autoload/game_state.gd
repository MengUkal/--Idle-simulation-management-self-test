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


func income_per_sec() -> float:
	# 挂机收入 = 基础公式 × 收入训练线倍率
	return Balance.income_per_sec(level) * Balance.train_multiplier(income_line)


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
	## 用元素精华升级训练线（NGU 式多线成长）
	var cost := int(Balance.train_cost(line_level(kind)))
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
	if not try_spend(Balance.upgrade_cost(level)):
		return false
	level += 1
	EventBus.level_changed.emit(level)
	EventBus.income_changed.emit(income_per_sec())
	if level == Balance.FLOOR_2_LEVEL_REQ:
		EventBus.floor_unlocked.emit(level)
	return true


func go_to_floor(index: int) -> void:
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

func buy_stock(idx: int, shares: int) -> bool:
	## 买入标的（含 1% 手续费），成功返回 true
	if idx < 0 or idx >= holdings.size() or shares <= 0:
		return false
	var cost := Balance.trade_cost(Market.prices[idx], shares)
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
	var gain := Balance.sell_proceeds(Market.prices[idx], shares)
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
	if kind == "income":
		EventBus.income_changed.emit(income_per_sec())
