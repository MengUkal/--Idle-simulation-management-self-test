extends Node
## 修饰符层：职业 / 种族 /（预留：天赋树、被动技能）的数值效果统一出口。
## mult 键连乘（默认 1.0），add 键累加（默认 0.0）。
## 重算时机：角色创建 / 重生 / 天赋变更（天赋来源在 recompute 的预留段追加）。
## 消费端：battle（伤害/弱点/连锁/步数/精华/赏金）、GameState（收入/训练费/献金/手续费/果实）。

const MULT_KEYS := ["battle_damage", "weakness", "income", "upgrade_cost", "train_cost", "bounty", "ep", "fruit", "drop_rate"]
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
	# ---- 巅峰板块来源（data/paragon.gd，四层系统之巅）----
	for node_id in GameState.paragon_talents.keys():
		var prank := int(GameState.paragon_talents[node_id])
		if prank <= 0:
			continue
		var pdef := GameParagon.get_node_def(str(node_id))
		if pdef.is_empty():
			continue
		var pper := float(pdef.get("per", 0.0))
		var pkind := str(pdef.get("kind", "mult"))
		var pmod := str(pdef.get("mod", ""))
		if pkind == "add" and _add.has(pmod):
			_add[pmod] += pper * prank
		elif pkind == "mult" and _mult.has(pmod):
			_mult[pmod] *= 1.0 + pper * prank
	# ---- 装备来源（data/equipment.gd，E1：遍历 10 槽穿戴 → 词条/祖品特效贡献）----
	for slot in GameState.equipped.keys():
		var eq_item: Dictionary = GameState.equipped[slot]
		if eq_item.is_empty():
			continue
		_apply_item_affixes(eq_item)
	for m in sources:
		for k: String in m.keys():
			if _mult.has(k):
				_mult[k] *= float(m[k])
			elif _add.has(k):
				_add[k] += float(m[k])


func mult(key: String) -> float:
	return _mult.get(key, 1.0)


## 单件装备的全部词条贡献（随机词条吃太古 ×1.5；祖品特效不吃太古）
func _apply_item_affixes(item: Dictionary) -> void:
	for affix in item.get("affixes", []):
		var def := GameEquipment.affix_def(str(affix["id"]))
		if def.is_empty():
			continue
		var ancient_mult := GameEquipment.ANCIENT_MULT \
			if bool(affix.get("ancient", false)) and def.has("tiers") else 1.0
		if def.has("effects"):
			for ef in def["effects"]:
				_apply_mod_unit(str(ef["key"]), str(ef["kind"]), float(ef["per"]) * ancient_mult)
		else:
			_apply_mod_unit(str(def["key"]), str(def["kind"]), GameEquipment.affix_per(affix))
	var lid := str(item.get("legendary", ""))
	if lid == "":
		return
	var leg := GameEquipment.legendary_def(lid)
	if leg.is_empty() or not _legendary_cond_ok(leg):
		return
	for ef in leg.get("special", []):
		_apply_mod_unit(str(ef.get("key", "")), str(ef.get("kind", "mult")), float(ef.get("per", 0.0)))


func _apply_mod_unit(key: String, kind: String, per: float) -> void:
	if kind == "add" and _add.has(key):
		_add[key] += per
	elif kind == "mult" and _mult.has(key):
		_mult[key] *= 1.0 + per


## 传奇构筑条件白名单（拍板 D4.4 不做条件词条；传奇祖品的构筑条件在此窄口处理）
func _legendary_cond_ok(leg: Dictionary) -> bool:
	match str(leg.get("cond", "")):
		"dual_dagger":
			# 影牙·双生：主手匕首 + 副手匕首（盗贼双持）时生效
			var main_item: Dictionary = GameState.equipped.get("main", {})
			var off_item: Dictionary = GameState.equipped.get("off", {})
			return str(main_item.get("type", "")) == "dagger" \
				and str(off_item.get("type", "")) == "dagger"
		_:
			return true


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
