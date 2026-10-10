extends Node
## 修饰符层：职业 / 种族 /（预留：天赋树、被动技能）的数值效果统一出口。
## mult 键连乘（默认 1.0），add 键累加（默认 0.0）。
## 重算时机：角色创建 / 重生 / 天赋变更（天赋来源在 recompute 的预留段追加）。
## 消费端：battle（伤害/弱点/连锁/步数/精华/赏金）、GameState（收入/训练费/献金/手续费/果实）。

const MULT_KEYS := ["battle_damage", "weakness", "income", "upgrade_cost", "train_cost", "bounty", "ep", "fruit"]
const ADD_KEYS := ["steps", "chain_bonus", "fee"]

var _mult := {}
var _add := {}


func _ready() -> void:
	recompute()


func recompute() -> void:
	for k in MULT_KEYS:
		_mult[k] = 1.0
	for k in ADD_KEYS:
		_add[k] = 0.0
	var sources: Array = []
	var cid: String = GameState.character_class
	if GameClasses.CLASSES.has(cid):
		sources.append(GameClasses.CLASSES[cid]["mods"])
	var rid: String = GameState.character_race
	if GameRaces.RACES.has(rid):
		sources.append(GameRaces.RACES[rid]["mods"])
	# ---- 天赋树来源（data/talents.gd，rank × 每级效果）----
	for node_id in GameState.talents.keys():
		var rank := int(GameState.talents[node_id])
		if rank <= 0:
			continue
		var def := GameTalents.get_node_def(str(node_id))
		if def.is_empty():
			continue
		var per := float(def.get("per", 0.0))
		var kind := str(def.get("kind", "mult"))
		var mod_name := str(def.get("mod", ""))
		if kind == "add" and _add.has(mod_name):
			_add[mod_name] += per * rank
		elif kind == "mult" and _mult.has(mod_name):
			_mult[mod_name] *= 1.0 + per * rank
	# ---- 预留：被动技能来源在此追加 ----
	for m in sources:
		for k: String in m.keys():
			if _mult.has(k):
				_mult[k] *= float(m[k])
			elif _add.has(k):
				_add[k] += float(m[k])


func mult(key: String) -> float:
	return _mult.get(key, 1.0)


func add(key: String) -> float:
	return _add.get(key, 0.0)


## 面板输出（模拟/平衡报告/调试用）：当前全部修饰符
func panel() -> Dictionary:
	var out := {}
	for k in MULT_KEYS:
		out[k] = mult(k)
	for k in ADD_KEYS:
		out[k] = add(k)
	return out
