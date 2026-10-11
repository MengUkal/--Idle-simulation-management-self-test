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
var skill_lv := 0                         # 主动技能强化等级（精华购买，转生保留——职业永久）
var body_line := 0                        # 体魄训练线（生命上限 +8%/级，精华）
var paragon_points := 0                   # 巅峰点（Lv.60 起每级 +1；消费于巅峰板块）
var talents := {}                         # 天赋记录 {节点id: rank}（见 data/talents.gd）
var paragon_talents := {}                 # 巅峰记录 {节点id: rank}（见 data/paragon.gd）
var paragon_unlocked_boards := ["p1"]     # 已解锁板块（点亮传奇即永久解锁，退还不清）
var floor3_card := false                  # 苍干栈道层卡（首杀守林古树掉落，P3）
var floor4_card := false                  # 落英花冠层卡（首杀镇风桩掉落，P4）
var floor5_card := false                  # 云顶鹰巢层卡（首杀千瓣祭主掉落，P5）
var bag: Array = []                       # 装备背包（≤30 件实例，E1）
var equipped: Dictionary = {}             # 穿戴栏（slot → 实例，E1）
var leg_claimed: Array = []               # 已获得的传奇 id（首杀挂点一次性）
var killed_once: Dictionary = {}          # 击杀过的目标 {名字: true}（传奇首杀判定）
var glue := 0                             # 树胶（洗练货币，分解粗品/普通获得，E2）
var tips_seen := {}                       # 已读新手提示 {key: true}（存档，每条只出现一次）
var pending_tips: Array = []              # 待展示提示文本队列（主界面逐条弹出）
var stars := 0                            # 累计星星（S1 结算秀产星，S2 星辰宝箱）
var chests_opened := 0                    # 已开启的祭品箱数（每 9 星一箱）
var pets: Dictionary = {}                 # 伙伴图鉴 {怪物名: {count, quality}}（P-b）
var pet_board := ""                       # 看板位怪物名（其被动 ×2）
var last_seen := 0.0                      # 最近一次存档的 Unix 时间戳（0 = 从未存过，离线收益用）
var pending_offline := {}                 # 待展示的离线收益报告（主界面弹窗消费，不落盘）


# ---------- 巅峰板块（四层系统之巅，2026-10-11 拍板） ----------

func paragon_board_unlocked(board_id: String) -> bool:
	## 板块解锁链：点亮前一板块任意传奇即永久解锁（退还不清）
	return board_id in paragon_unlocked_boards


func paragon_invested(board_id: String) -> int:
	var total := 0
	for n in GameParagon.BOARDS[board_id]["nodes"]:
		total += int(paragon_talents.get(n["id"], 0))
	return total


func paragon_buy(node_id: String) -> bool:
	## 购买/升级 1 级巅峰节点（消耗 1 巅峰点）。校验：板块解锁/等级上限/关键互斥/巅峰点
	var def := GameParagon.get_node_def(node_id)
	if def.is_empty():
		return false
	if not paragon_board_unlocked(str(def.get("board", ""))):
		return false
	if paragon_points < 1:
		return false
	var rank := int(paragon_talents.get(node_id, 0))
	if rank >= int(def.get("max", 1)):
		return false
	if def.has("key"):
		for n in GameParagon.BOARDS[str(def.get("board", ""))]["nodes"]:
			if n.has("key") and n["id"] != node_id and int(paragon_talents.get(n["id"], 0)) > 0:
				return false
	paragon_points -= 1
	paragon_talents[node_id] = rank + 1
	for n in GameParagon.BOARDS[str(def.get("board", ""))]["nodes"]:
		if str(n.get("key_of", "")) == node_id:
			paragon_talents[n["id"]] = 1
	# 解锁链：点亮传奇 → 下一板块永久解锁
	if def.has("key"):
		var board_id := str(def.get("board", ""))
		var idx := GameParagon.BOARD_ORDER.find(board_id)
		if idx >= 0 and idx + 1 < GameParagon.BOARD_ORDER.size():
			var next_board: String = GameParagon.BOARD_ORDER[idx + 1]
			if not (next_board in paragon_unlocked_boards):
				paragon_unlocked_boards.append(next_board)
	Mods.recompute()
	EventBus.level_changed.emit(level)
	return true


func paragon_refund(node_id: String) -> bool:
	## 退还 1 级巅峰节点（免费）；关键节点退还时同步撤掉副作用
	if not paragon_talents.has(node_id) or int(paragon_talents[node_id]) <= 0:
		return false
	var bid := str(GameParagon.get_node_def(node_id).get("board", ""))
	paragon_talents[node_id] = int(paragon_talents[node_id]) - 1
	if int(paragon_talents[node_id]) <= 0:
		paragon_talents.erase(node_id)
		for n in GameParagon.BOARDS[bid]["nodes"]:
			if str(n.get("key_of", "")) == node_id:
				paragon_talents.erase(n["id"])
	paragon_points += 1
	Mods.recompute()
	EventBus.level_changed.emit(level)
	return true


func can_go_to_floor(index: int) -> bool:
	## 层间往返的目标层是否可去：一层自由；二层 Lv.10；三层 Lv.50 + 层卡
	match index:
		5:
			return level >= Balance.FLOOR_5_LEVEL_REQ and floor5_card
		4:
			return level >= Balance.FLOOR_4_LEVEL_REQ and floor4_card
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


func unlock_floor4_card() -> bool:
	## 首杀镇风桩掉落「落英花冠层卡」；已持有返回 false
	if floor4_card:
		return false
	floor4_card = true
	EventBus.floor4_card_gained.emit()
	return true


func unlock_floor5_card() -> bool:
	## 首杀千瓣祭主掉落「云顶鹰巢层卡」；已持有返回 false
	if floor5_card:
		return false
	floor5_card = true
	EventBus.floor5_card_gained.emit()
	return true


# ---------- 装备（E1，2026-10-11 22 项拍板 + 内容包 v2） ----------

const BAG_CAPACITY := 30
const DECOMPOSE_GLUE := [5, 15]           # 粗品/普通分解得树胶（洗练货币，内容包 v2）
const DECOMPOSE_ESSENCE := [30, 80]       # 精良/史诗分解得元素精华
const WASH_BASE_COST := 10                # 洗练基础树胶价
const WASH_COST_GROWTH := 2.0             # 账单制：同一件每洗一次 ×2（拍板 D5.2 递增）


## 分解背包第 idx 件。返回 {"ok", "glue", "essence", "name"}。
func decompose(idx: int) -> Dictionary:
	if idx < 0 or idx >= bag.size():
		return {"ok": false}
	var item: Dictionary = bag[idx]
	if str(item.get("legendary", "")) != "":
		return {"ok": false, "reason": "传奇不可分解"}
	var q := int(item.get("quality", 0))
	var out := {"ok": true, "glue": 0, "essence": 0, "name": str(item.get("name", ""))}
	if q <= 1:
		var g: int = DECOMPOSE_GLUE[q]
		glue += g
		out["glue"] = g
	else:
		var e: int = DECOMPOSE_ESSENCE[q - 2]
		add_essence(e)
		out["essence"] = e
	bag.remove_at(idx)
	return out


## 一键分解全部粗品/普通。返回分解件数。
func decompose_all_common() -> int:
	var n := 0
	for i in range(bag.size() - 1, -1, -1):
		if int(bag[i].get("quality", 0)) <= 1 and str(bag[i].get("legendary", "")) == "":
			var r: Dictionary = decompose(i)
			if bool(r.get("ok", false)):
				n += 1
	return n


## 洗练账单价：同一件每洗一次翻倍（树胶）
func wash_cost(item: Dictionary) -> int:
	return int(ceil(WASH_BASE_COST * pow(WASH_COST_GROWTH, int(item.get("wash_count", 0)))))


## 账单制洗 1：重 roll 装备实例的第 affix_idx 条词条（同槽位池、不与现存重复、
## 档位 T1~T5 独立 roll、太古只能发现不能洗出）。返回错误文本（空 = 成功）。
func wash_affix(idx: int, affix_idx: int) -> String:
	if idx < 0 or idx >= bag.size():
		return "无效的背包格"
	var item: Dictionary = bag[idx]
	var affixes: Array = item.get("affixes", [])
	if affix_idx < 0 or affix_idx >= affixes.size():
		return "无效的词条"
	var cost := wash_cost(item)
	if glue < cost:
		return "树胶不足（需 %d）" % cost
	var old_id := str(affixes[affix_idx]["id"])
	var slot := str(item["slot"])
	var pool := []
	for a in GameEquipment.AFFIXES:
		if slot in a["slots"] and (affixes.size() >= 2 or not a.has("effects")) \
				and str(a["id"]) != old_id:
			var dup := false
			for other in affixes:
				if other is Dictionary and int(affixes.find(other)) != affix_idx \
						and str(other.get("id", "")) == str(a["id"]):
					dup = true
			if not dup:
				pool.append(a)
	if pool.is_empty():
		return "该槽位无可替换词条"
	pool.shuffle()
	var pick: Dictionary = pool[0]
	var fresh := {"id": str(pick["id"]), "tier": randi_range(1, 5), "ancient": false}
	if pick.has("effects"):
		fresh["tier"] = 0
	affixes[affix_idx] = fresh
	item["affixes"] = affixes
	item["wash_count"] = int(item.get("wash_count", 0)) + 1
	glue -= cost
	Mods.recompute()
	EventBus.money_changed.emit(money)  # 刷新面板数值（词条可能含经济键）
	return ""


## 战斗掉落结算（在赏金之后调用）。返回 toast 文本（空 = 无可展示掉落）。
## 粗品/普通自动分解回精华（拍板 D3.1 配套，默认开）；传奇定向挂点首杀必掉。
func battle_drop(monster: Dictionary, is_elite: bool) -> String:
	var mname := str(monster.get("name", ""))
	var is_first := not killed_once.has(mname)
	killed_once[mname] = true
	var toasts: Array = []
	for drop in GameEquipment.roll_legendary(monster, is_elite, is_first, leg_claimed, floor_index):
		leg_claimed.append(str(drop["id"]))
		if _add_to_bag(drop) == "":
			toasts.append("★ 传奇「%s」掉落！" % str(drop["name"]))
		else:
			add_essence(50)
			toasts.append("背包已满，「%s」折算 50 精华" % str(drop["name"]))
	if randf() < GameEquipment.DROP_BASE_CHANCE * Mods.mult("drop_rate"):
		var item := GameEquipment.roll_item(floor_index, rebirth_count, character_class, monster)
		var q := int(item.get("quality", 0))
		if q <= 1:
			glue += DECOMPOSE_GLUE[q]  # 粗品/普通自动分解得树胶（内容包 v2）
		elif _add_to_bag(item) == "":
			toasts.append("获得 %s（%s）" % [str(item["name"]), GameEquipment.QUALITY_NAMES[q]])
	if toasts.is_empty():
		return ""
	return " / ".join(toasts)


func _add_to_bag(item: Dictionary) -> String:
	## 入包；背包满返回 "full"
	if bag.size() >= BAG_CAPACITY:
		return "full"
	bag.append(item)
	# 引导链 #7：首件装备入包
	tip_once("equip_first", "掉了件装备。去背包装上，别让它吃灰。")
	return ""


## 穿戴背包第 idx 件。返回错误文本（空 = 成功）；同槽旧件回包；戒指自动落 A/B。
func equip_from_bag(idx: int) -> String:
	if idx < 0 or idx >= bag.size():
		return "无效的背包格"
	var item: Dictionary = bag[idx]
	if not GameEquipment.can_wear(character_class, item):
		return "%s 与职业不符" % str(item.get("name", "该装备"))
	var slot := str(item["slot"])
	if slot == "ring":
		slot = "ring_a" if not equipped.has("ring_a") else "ring_b"
	var old: Dictionary = equipped.get(slot, {})
	equipped[slot] = item
	bag.remove_at(idx)
	if not old.is_empty():
		bag.append(old)
	Mods.recompute()
	return ""


## 卸下穿戴栏。返回错误文本（空 = 成功）。
func unequip(slot: String) -> String:
	if not equipped.has(slot):
		return "该栏位为空"
	var err := _add_to_bag(equipped[slot])
	if err != "":
		return "背包已满"
	equipped.erase(slot)
	Mods.recompute()
	return ""


# ---------- 伙伴系统（P-b，2026-10-11 第十四轮拍板精简版） ----------

## 蛋掉落判定（击杀后调用）。命中返回 {"monster", "quality"}，否则空。
func egg_drop(monster: Dictionary, is_elite: bool, is_first_kill: bool) -> Dictionary:
	var mname := str(monster.get("name", ""))
	if GamePets.pet_def(mname).is_empty():
		return {}
	# 层守首杀必掉专属蛋；精英 15%；常驻 2%
	var hit := false
	if is_elite:
		hit = is_first_kill or randf() < GamePets.EGG_DROP_ELITE
	else:
		hit = randf() < GamePets.EGG_DROP_COMMON
	if not hit:
		return {}
	var q := GameEquipment.roll_quality(floor_index, rebirth_count)
	return {"monster": mname, "quality": q}


## 孵化入图鉴：新怪点亮 / 重复计数量 / 品质取最高。未注册怪拒绝。返回是否首次点亮。
func hatch_egg(monster_name: String, quality: int) -> bool:
	if GamePets.pet_def(monster_name).is_empty():
		return false
	var old: Dictionary = pets.get(monster_name, {})
	var first := old.is_empty()
	pets[monster_name] = {
		"count": int(old.get("count", 0)) + 1,
		"quality": maxi(int(old.get("quality", 0)), quality),
	}
	Mods.recompute()  # 新被动/升档即时生效
	return first


## 设看板位（须已孵化）。返回是否成功。
func set_pet_board(monster_name: String) -> bool:
	if not pets.has(monster_name):
		return false
	pet_board = monster_name
	Mods.recompute()
	return true


## 伙伴被动总和（Mods 装备段后调用）：全员常驻 + 看板位 ×2
func pet_passive_per(monster_name: String) -> float:
	var rec: Dictionary = pets.get(monster_name, {})
	if rec.is_empty():
		return 0.0
	return GamePets.passive_per(monster_name, int(rec.get("quality", 0)), str(pet_board) == monster_name)


# ---------- 新手提示（引导链清单实装，2026-10-12） ----------

## 一次性提示：首次调用入展示队列并存档标记；text 为空则只做标记（多连提示用）
func tip_once(key: String, text: String = "") -> bool:
	if tips_seen.has(key):
		return false
	tips_seen[key] = true
	if text != "":
		pending_tips.append(text)
	return true


# ---------- 技能强化与体魄训练线（精华新消耗口，2026-10-12 拍板 A+D） ----------

const SKILL_LV_MAX := 10
const SKILL_LV_BASE_COST := 50
const SKILL_LV_GROWTH := 1.6
const BODY_LINE_HP_PER_LEVEL := 0.08


func skill_upgrade_cost() -> int:
	return int(ceil(float(SKILL_LV_BASE_COST) * pow(SKILL_LV_GROWTH, skill_lv)))


func skill_upgrade() -> bool:
	## 主动技能强化：精华购买技能等级（主数值成长；转生保留——职业永久）
	if skill_lv >= SKILL_LV_MAX:
		return false
	var cost := skill_upgrade_cost()
	if essence < cost:
		return false
	essence -= cost
	skill_lv += 1
	return true


# ---------- 星辰宝箱（S1 产星 / S2 祭品箱，第十五轮拍板） ----------

const CHEST_EVERY := 9                    # 每 9 星开一箱（落英花冠祭品箱）


## 产星。返回本次触发的宝箱数（由调用方逐个开启并展示）。
func add_stars(n: int) -> int:
	stars += n
	var chests := 0
	while stars >= CHEST_EVERY * (chests_opened + 1):
		chests_opened += 1
		chests += 1
	return chests


## 开祭品箱：60% 精华 / 30% 装备(保底精良) / 10% 伙伴蛋(精良)。返回奖励描述。
func open_chest() -> String:
	var roll := randf()
	if roll < 0.6:
		add_essence(150)
		return "精华 ×150"
	elif roll < 0.9:
		var it := GameEquipment.roll_item(clampi(floor_index, 2, 5), rebirth_count, character_class, {"name": "祭品箱"})
		if int(it["quality"]) < 2:
			it["quality"] = 2
			it["affixes"] = GameEquipment.roll_affixes(str(it["slot"]), 2)
		if _add_to_bag(it) != "":
			add_essence(100)
			return "装备「%s」（背包满折算精华 100）" % str(it["name"])
		return "装备「%s」" % str(it["name"])
	var species := GamePets.PETS.keys()
	var mname: String = species[randi() % species.size()]
	hatch_egg(mname, 2)
	return "伙伴蛋「%s」" % mname


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


## 玩家生命上限（P-a 拍板 D9 全构成：基础+等级成长+职业修正+装备词条+体魄训练线）
func player_max_hp() -> int:
	var base := Balance.PLAYER_HP_BASE + Balance.PLAYER_HP_PER_LEVEL * level
	var cm: float = Balance.CLASS_HP_MOD.get(character_class, 1.0)
	return int(ceil(base * cm * Mods.mult("max_hp") * (1.0 + BODY_LINE_HP_PER_LEVEL * body_line)))


func train_cost_for(kind: String) -> int:
	## 训练线升级实价 = 基础费用 × 果实折扣 × 轮数衰减 × 职业/种族/天赋/巅峰/装备修饰符
	## 硬下限 5% 基价（审计 2026-10-12：极端折扣堆叠后训练仍须是消耗口）
	return int(ceil(maxf(0.05, Balance.train_cost_mult(fruits, rebirth_count)
		* Mods.mult("train_cost")) * Balance.train_cost(line_level(kind))))


func add_essence(amount: int) -> void:
	if amount <= 0:
		return
	essence += amount
	EventBus.essence_changed.emit(essence)
	# 引导链 #3：首次获得精华
	tip_once("essence_first", "精华到账。三条训练线，各管一样：打人、拿钱、挣钱。")


func line_level(kind: String) -> int:
	match kind:
		"atk":
			return atk_line
		"bounty":
			return bounty_line
		"income":
			return income_line
		"body":
			return body_line
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
		"body":
			body_line += 1
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
	body_line = 0
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


# ---------- 离线收益（2026-10-11 拍板：只金币 / 上限 8 小时 / 效率 60% / 回归弹窗） ----------

const OFFLINE_CAP_SEC := 8 * 3600   # 离线收益计入时长上限
const OFFLINE_RATE := 0.6           # 离线效率 = 在线挂机收入的 60%
const OFFLINE_MIN_SEC := 300.0      # 离开不足 5 分钟不结算、不弹窗（防切屏误触）


func settle_offline() -> Dictionary:
	## 读档末尾调用：按离开时长结算离线金币（立即入账防丢），返回报告供回归弹窗展示。
	## 基准 = 当前挂机收入 income_per_sec()（含训练线/果实/职业/种族/天赋/巅峰全部修饰符）。
	if last_seen <= 0.0:
		return {}
	var elapsed: float = maxf(0.0, Time.get_unix_time_from_system() - last_seen)
	if elapsed < OFFLINE_MIN_SEC:
		return {}
	var credited: float = minf(elapsed, OFFLINE_CAP_SEC)
	var gold := floorf(income_per_sec() * credited * OFFLINE_RATE)
	if gold < 1.0:
		return {}
	add_money(gold)
	pending_offline = {
		"seconds": int(elapsed),
		"credited_sec": int(credited),
		"rate": income_per_sec() * OFFLINE_RATE,
		"gold": int(gold),
	}
	return pending_offline


func take_offline_report() -> Dictionary:
	## 弹窗取走报告（取走即清空，避免重复弹）
	var r := pending_offline
	pending_offline = {}
	return r


func can_afford(cost: float) -> bool:
	return money >= cost


func add_money(amount: float) -> void:
	if amount <= 0.0:
		return
	money += amount
	total_earned += amount
	EventBus.money_changed.emit(money)
	# 引导链 #1：首次吉尔攒到 10
	if money >= 10.0:
		tip_once("money10", "攒够 10 G 了。献金升级，树的祝福明码标价。")


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
		tip_once("paragon_first", "巅峰点开始积累。后期的事，现在知道也不亏。")
	else:
		skill_points += 1  # 天赋技能点
		tip_once("skill_first", "技能点 +1。去天赋页，点亮你的第一格。")
	EventBus.level_changed.emit(level)
	EventBus.income_changed.emit(income_per_sec())
	if level == Balance.FLOOR_2_LEVEL_REQ:
		EventBus.floor_unlocked.emit(level)
	return true


func upgrade_cost() -> float:
	## 下一级献金费用（含职业/种族/天赋/巅峰/装备修饰符；下限 0.30 防折扣堆叠趋零——审计 2026-10-12）
	return ceil(Balance.upgrade_cost(level) * maxf(0.30, Mods.mult("upgrade_cost")))


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
	paragon_points = 0
	talents = {}
	paragon_talents = {}
	paragon_unlocked_boards = ["p1"]
	floor3_card = false
	floor4_card = false
	floor5_card = false
	bag = []
	equipped = {}
	leg_claimed = []
	killed_once = {}
	glue = 0
	pets = {}
	pet_board = ""
	stars = 0
	chests_opened = 0
	tips_seen = {}
	pending_tips = []
	skill_lv = 0
	body_line = 0
	last_seen = 0.0
	pending_offline = {}
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
