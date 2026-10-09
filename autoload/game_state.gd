extends Node
## 玩家数据唯一持有者：其他模块一律通过它读写，禁止各自缓存数值。
## 设定：等级 = 世界树赐予的祝福，向树献金（吉尔）即可提升。

var money := Balance.START_MONEY          # 当前吉尔
var level := Balance.START_LEVEL          # 当前等级
var floor_index := 1                      # 当前所在层（1 = 树根之街）
var total_earned := 0.0                   # 累计获得吉尔（统计用）


func income_per_sec() -> float:
	return Balance.income_per_sec(level)


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
