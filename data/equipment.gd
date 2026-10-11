class_name GameEquipment
extends RefCounted
## 装备系统数据表（E1，2026-10-11 拍板：设计文档 §15 22 项 + 《装备内容包 v2》第十二轮）。
## 纯逻辑无节点依赖：面板/掉落/Mods/模拟器共用。
##
## 结构纪律（内容包 §5 接口备忘）：
## - 词条即数据：{id, name, key, kind, tiers:[T1..T5], slots}（与 talents/paragon 同构）
## - 复合词条：effects 数组（精良及以上可出，占 1 栏 ≈ 0.8 条强度）
## - 品级即数据：实例带 quality 0~3（粗品/普通/精良/史诗 → 词条栏 0/1/2/3）
## - 传奇独立掉落：3 词条随机 + 祖品特效（E1 数值型）+ 定向挂点（提案，可调）
## - 太古：任意掉落 8% 形态（词条数值 ×1.5），只能发现不能洗出
## - 层级 = 掉落楼层（L1~L5）

const SLOTS := ["main", "off", "helm", "body", "shoulder", "legs", "boots", "ring", "trinket"]
## 穿戴栏（10 槽，戒指分 A/B；掉落件的 "ring" 可入任意一栏）
const EQUIP_SLOTS := ["main", "off", "helm", "body", "shoulder", "legs", "boots", "ring_a", "ring_b", "trinket"]
const SLOT_NAMES := {
	"main": "主手", "off": "副手", "helm": "头盔", "body": "身体", "shoulder": "肩膀",
	"legs": "护腿", "boots": "鞋", "ring_a": "戒指", "ring_b": "戒指", "trinket": "饰品",
}
# 护甲五部位（吃布/皮/重权重）；戒指A/B 与饰品全职业通用
const ARMOR_SLOTS := ["helm", "body", "shoulder", "legs", "boots"]

const QUALITY_NAMES := ["粗品", "普通", "精良", "史诗"]
const QUALITY_COLORS := [
	Color(0.85, 0.85, 0.85), Color(0.45, 0.65, 1.0), Color(0.7, 0.5, 1.0), Color(1.0, 0.8, 0.25),
]
# 品级权重：一层 → 五层线性（内容包 v2 §0）；重生每轮精良+史诗合计 +2%，合计上限 60%
const QUALITY_W_F1 := [45.0, 40.0, 12.0, 3.0]
const QUALITY_W_F5 := [5.0, 25.0, 40.0, 30.0]
const QUALITY_REBIRTH_BONUS := 2.0     # 每轮重生精良+史诗合计加成（百分点）
const QUALITY_RB_CAP := 60.0           # 精良+史诗合计权重上限

const ANCIENT_CHANCE := 0.08           # 太古形态概率（数值 ×1.5）
const ANCIENT_MULT := 1.5
const DROP_BASE_CHANCE := 0.08         # 全战斗基础掉落概率（× drop_rate 修饰符）
## 分解产出在 GameState（DECOMPOSE_GLUE/DECOMPOSE_ESSENCE，E2：树胶/精华）

# ---------- 内在属性维度（2026-10-12 拍板：层级 1~N 永续成长的三条公式轴） ----------
## 与品级（词条栏数）正交：品级管词条数量，层级管这三条内在属性的数值。
## 公式化（非查表）→ 层数加到 L6/L7… 装备跟着变强，永不封顶。

const INTR_ATK_BASE := 0.12            # 主手/副手：攻击力（weapon_atk 乘区）L1 值
const INTR_ATK_STEP := 0.04            # 每层级 +4%
const INTR_ELEM_BASE := 0.06           # 全部位：元素专精（同色消除伤害 +）L1 值
const INTR_ELEM_STEP := 0.02           # 每层级 +2%
const INTR_SPEC_BASE := 0.08           # 主手/副手/鞋：特效增幅（特效波伤害 +）L1 值
const INTR_SPEC_STEP := 0.03           # 每层级 +3%
const INTR_SPEC_SLOTS := ["main", "off", "boots"]


static func intr_atk(tier: int) -> float:
	## 攻击力加成（百分比 per，进 weapon_atk 乘区）
	return INTR_ATK_BASE + INTR_ATK_STEP * float(clampi(tier, 1, 999) - 1)


static func intr_elem(tier: int) -> float:
	## 元素专精加成（同色消除伤害 +）
	return INTR_ELEM_BASE + INTR_ELEM_STEP * float(clampi(tier, 1, 999) - 1)


static func intr_spec(tier: int) -> float:
	## 特效增幅加成（特效波伤害 +）
	return INTR_SPEC_BASE + INTR_SPEC_STEP * float(clampi(tier, 1, 999) - 1)

# ---------- 职业类型限制（设计文档 §15.2，WoW 式） ----------

const CLASS_TYPES := {
	"warrior": {"main": ["sword", "axe", "mace"], "off": ["shield"], "armor": "heavy"},
	"paladin": {"main": ["sword", "mace"], "off": ["shield"], "armor": "heavy"},
	"rogue": {"main": ["sword", "dagger"], "off": ["dagger"], "armor": "leather"},
	"ranger": {"main": ["bow", "dagger"], "off": [], "armor": "leather"},
	"mage": {"main": ["staff"], "off": ["catalyst"], "armor": "cloth"},
	"warlock": {"main": ["staff", "dagger"], "off": ["catalyst"], "armor": "cloth"},
	"priest": {"main": ["mace", "staff"], "off": ["catalyst"], "armor": "cloth"},
}

# ---------- 词条池（16 条：12 单键 + 4 复合；per 数值与内容包 §1 一致） ----------

const AFFIXES := [
	{"id": "af_sharp", "name": "锋锐", "key": "battle_damage", "kind": "mult",
		"tiers": [0.04, 0.06, 0.08, 0.10, 0.12], "slots": ["main", "off", "ring", "trinket"]},
	{"id": "af_insight", "name": "弱点洞察", "key": "weakness", "kind": "mult",
		"tiers": [0.05, 0.08, 0.11, 0.14, 0.18], "slots": ["main", "ring", "trinket"]},
	{"id": "af_harvest", "name": "丰收", "key": "income", "kind": "mult",
		"tiers": [0.04, 0.06, 0.08, 0.10, 0.12],
		"slots": ["helm", "body", "shoulder", "legs", "boots", "trinket"]},
	{"id": "af_tithe", "name": "献金折扣", "key": "upgrade_cost", "kind": "mult",
		"tiers": [-0.02, -0.03, -0.04, -0.06, -0.08], "slots": ["helm", "trinket"]},
	{"id": "af_studies", "name": "修行折扣", "key": "train_cost", "kind": "mult",
		"tiers": [-0.02, -0.03, -0.04, -0.05, -0.06],
		"slots": ["helm", "body", "shoulder", "legs", "boots", "ring"]},
	{"id": "af_plunder", "name": "掠夺", "key": "bounty", "kind": "mult",
		"tiers": [0.03, 0.05, 0.06, 0.08, 0.10], "slots": ["main", "legs", "boots", "ring"]},
	{"id": "af_extract", "name": "萃取", "key": "ep", "kind": "mult",
		"tiers": [0.03, 0.04, 0.06, 0.08, 0.10], "slots": SLOTS},
	{"id": "af_fruitful", "name": "果熟", "key": "fruit", "kind": "mult",
		"tiers": [0.02, 0.03, 0.04, 0.06, 0.08], "slots": SLOTS},
	{"id": "af_swift", "name": "轻捷", "key": "steps", "kind": "add",
		"tiers": [1, 1, 2, 2, 3], "slots": ["boots"]},
	{"id": "af_chain", "name": "连锁之心", "key": "chain_bonus", "kind": "add",
		"tiers": [0.005, 0.008, 0.012, 0.016, 0.02], "slots": ["ring", "trinket"]},
	{"id": "af_broker", "name": "掮客", "key": "fee", "kind": "add",
		"tiers": [-0.001, -0.002, -0.003, -0.004, -0.005], "slots": ["trinket"]},
	{"id": "af_luck", "name": "星运", "key": "drop_rate", "kind": "mult",
		"tiers": [0.05, 0.09, 0.13, 0.17, 0.22], "slots": ["ring", "trinket", "boots"]},
	# 复合词条（精良及以上可出；固定数值 ≈ 两条单键 T3 的 80%，占 1 栏）
	{"id": "af_spoils", "name": "战利品直觉", "slots": ["main", "legs", "ring"],
		"effects": [{"key": "bounty", "kind": "mult", "per": 0.05}, {"key": "ep", "kind": "mult", "per": 0.04}]},
	{"id": "af_zenith", "name": "禅定", "slots": ["helm", "body", "shoulder"],
		"effects": [{"key": "train_cost", "kind": "mult", "per": -0.04}, {"key": "income", "kind": "mult", "per": 0.04}]},
	{"id": "af_cadence", "name": "掠夺节奏", "slots": ["boots", "trinket"],
		"effects": [{"key": "chain_bonus", "kind": "add", "per": 0.01}, {"key": "bounty", "kind": "mult", "per": 0.04}]},
	{"id": "af_atlas", "name": "星图", "slots": ["ring", "trinket"],
		"effects": [{"key": "fruit", "kind": "mult", "per": 0.05}, {"key": "drop_rate", "kind": "mult", "per": 0.10}]},
	# 生命系统三词条（P-a，伙伴与生命系统规划 §2.4）
	{"id": "af_vital", "name": "丰盈", "key": "max_hp", "kind": "mult",
		"tiers": [0.06, 0.09, 0.12, 0.15, 0.18], "slots": ["helm", "body", "legs"]},
	{"id": "af_regen", "name": "再生", "key": "regen", "kind": "add",
		"tiers": [1, 1, 2, 2, 3], "slots": ["ring", "trinket"]},
	{"id": "af_guard", "name": "坚壁", "key": "dr", "kind": "add",
		"tiers": [0.03, 0.045, 0.06, 0.075, 0.09], "slots": ["body", "shoulder", "off"]},
]

# ---------- 基础件（125 件：层级 = 掉落楼层 L1~L5） ----------

const MAIN_BASES := {
	"sword": ["铁剑", "阔刃剑", "精钢长剑", "月刃长剑", "树心古剑"],
	"axe": ["砍木斧", "双齿斧", "裂石斧", "裂冠斧", "断枝战斧"],
	"mace": ["铜锤", "八棱锤", "碎石锤", "崩岩锤", "巨木重锤"],
	"dagger": ["短刃", "刺针", "淬毒小刀", "弯钩刃", "影牙"],
	"staff": ["木杖", "橡木杖", "星纹杖", "鸦羽杖", "世界树枝杖"],
	"bow": ["猎弓", "短猎弓", "长风弓", "连珠弓", "鹰巢长弓"],
}
const MAIN_TYPE_NAMES := {"sword": "剑", "axe": "斧", "mace": "锤", "dagger": "匕首", "staff": "杖", "bow": "弓"}
const OFF_BASES := {
	"shield": ["圆木盾", "铁箍盾", "鸢花盾", "纹章盾", "古树塔盾"],
	"catalyst": ["旧典", "新典", "月纹法典", "日纹法典", "生命露晶球"],
}
const OFF_TYPE_NAMES := {"shield": "盾", "catalyst": "法器"}
const ARMOR_BASES := {
	"cloth": {
		"helm": ["学徒兜帽", "织纹兜帽", "秘纹兜帽", "星辉兜帽", "星辰兜帽"],
		"body": ["学徒长袍", "织纹长袍", "秘纹长袍", "星辉长袍", "星辰长袍"],
		"shoulder": ["学徒披肩", "织纹披肩", "秘纹披肩", "星辉披肩", "星辰披肩"],
		"legs": ["学徒长裤", "织纹长裤", "秘纹长裤", "星辉长裤", "星辰长裤"],
		"boots": ["学徒便鞋", "织纹便鞋", "秘纹便鞋", "星辉便鞋", "星辰便鞋"],
	},
	"leather": {
		"helm": ["猎手软帽", "逐风软帽", "风行软帽", "穿云软帽", "鹰眼软帽"],
		"body": ["猎手皮衣", "逐风皮衣", "风行皮衣", "穿云皮衣", "鹰眼皮衣"],
		"shoulder": ["猎手护肩", "逐风护肩", "风行护肩", "穿云护肩", "鹰眼护肩"],
		"legs": ["猎手裤", "逐风裤", "风行裤", "穿云裤", "鹰眼裤"],
		"boots": ["猎手靴", "逐风靴", "风行靴", "穿云靴", "鹰眼靴"],
	},
	"heavy": {
		"helm": ["卫兵盔", "铁卫盔", "誓约盔", "金誓盔", "树冠卫盔"],
		"body": ["卫兵甲", "铁卫甲", "誓约甲", "金誓甲", "树冠卫甲"],
		"shoulder": ["卫兵肩甲", "铁卫肩甲", "誓约肩甲", "金誓肩甲", "树冠卫肩"],
		"legs": ["卫兵腿甲", "铁卫腿甲", "誓约腿甲", "金誓腿甲", "树冠卫腿"],
		"boots": ["卫兵铁靴", "铁卫铁靴", "誓约铁靴", "金誓铁靴", "树冠卫靴"],
	},
}
const ARMOR_WEIGHT_NAMES := {"cloth": "布甲", "leather": "皮甲", "heavy": "重甲"}
const RING_BASES := ["铜戒", "锡戒", "玛瑙戒", "琥珀戒", "枝冠指环"]
const TRINKET_BASES := ["麻绳吊坠", "木符坠", "银叶坠", "金叶坠", "世界树果坠"]

# ---------- 传奇件（15 = 12 + 3 祖品；挂点为提案，概率可调） ----------

const LEGENDARIES := [
	{"id": "leg_oath_blade", "name": "誓约之刃", "slot": "main", "type": "sword",
		"special": [{"key": "battle_damage", "kind": "mult", "per": 0.25}],
		"hook": {"type": "first_kill", "monster": "守林古树"}},
	{"id": "leg_shadowfang", "name": "影牙·双生", "slot": "main", "type": "dagger",
		"special": [{"key": "chain_bonus", "kind": "add", "per": 0.03}], "cond": "dual_dagger",
		"hook": {"type": "kill", "monster": "暗藤魔", "chance": 0.05}},
	{"id": "leg_worldstaff", "name": "世界树芯杖", "slot": "main", "type": "staff",
		"special": [{"key": "ep", "kind": "mult", "per": 0.30}],
		"hook": {"type": "kill", "monster": "镇风桩", "chance": 0.10}},
	{"id": "leg_rootshield", "name": "古树根盾", "slot": "off", "type": "shield",
		"special": [{"key": "steps", "kind": "add", "per": 4}],
		"hook": {"type": "kill", "monster": "镇风桩", "chance": 0.10}},
	{"id": "leg_ritual_orb", "name": "祭露晶球", "slot": "off", "type": "catalyst",
		"special": [{"key": "fruit", "kind": "mult", "per": 0.20}],
		"hook": {"type": "first_kill", "monster": "千瓣祭主"}},
	{"id": "leg_nightcrown", "name": "夜香冠", "slot": "helm", "type": "cloth",
		"special": [{"key": "income", "kind": "mult", "per": 0.20}],
		"hook": {"type": "kill", "monster": "夜香花", "chance": 0.03}},
	{"id": "leg_oath_mail", "name": "古树誓甲", "slot": "body", "type": "heavy",
		"special": [{"key": "train_cost", "kind": "mult", "per": -0.20}],
		"hook": {"type": "first_kill", "monster": "守林古树"}},
	{"id": "leg_feather_pauldron", "name": "辉羽护肩", "slot": "shoulder", "type": "leather",
		"special": [{"key": "weakness", "kind": "mult", "per": 0.20}],
		"hook": {"type": "kill", "monster": "辉羽蝶", "chance": 0.05}},
	{"id": "leg_thousand_greaves", "name": "千瓣腿甲", "slot": "legs", "type": "heavy",
		"special": [{"key": "bounty", "kind": "mult", "per": 0.25}],
		"hook": {"type": "kill", "monster": "千瓣祭主", "chance": 0.15}},
	{"id": "leg_falcon_boots", "name": "隼羽轻靴", "slot": "boots", "type": "leather",
		"special": [{"key": "steps", "kind": "add", "per": 5}],
		"hook": {"type": "kill", "monster": "風羽隼", "chance": 0.05}},
	{"id": "leg_twin_ring", "name": "枝冠指环「双生戒」", "slot": "ring", "type": "ring",
		"special": [{"key": "ep", "kind": "mult", "per": 0.15}, {"key": "bounty", "kind": "mult", "per": 0.15}],
		"hook": {"type": "elite_kill", "chance": 0.02}},
	{"id": "leg_first_fruit", "name": "初果坠", "slot": "trinket", "type": "trinket",
		"special": [{"key": "drop_rate", "kind": "mult", "per": 0.50}],
		"hook": {"type": "guard_kill", "chance": 0.03}},
	{"id": "leg_forge_axe", "name": "开炉斧", "slot": "main", "type": "axe",
		"special": [{"key": "battle_damage", "kind": "mult", "per": 0.22}],
		"hook": {"type": "guard_kill", "chance": 0.03}},  # 尼达维勒商会（挂点提案：层守通用代管）
	{"id": "leg_scale_hammer", "name": "定秤锤", "slot": "main", "type": "mace",
		"special": [{"key": "bounty", "kind": "mult", "per": 0.20}],
		"hook": {"type": "elite_kill", "chance": 0.02}},  # 交易所校秤祖锤（挂点提案：精英通用代管）
	{"id": "leg_eagle_bow", "name": "鹰唳长弓", "slot": "main", "type": "bow",
		"special": [{"key": "steps", "kind": "add", "per": 4}],
		"hook": {"type": "none"}},  # 云顶鹰巢（第五层实装后挂瞭望鹰）
]


# ---------- 基础件查询 ----------

## 返回基础件定义 {id, name, slot, type, tier, weight?}；type 语义随 slot（武器类型/护甲权重）
static func base_item(slot: String, type: String, tier: int) -> Dictionary:
	var t := clampi(tier, 1, 5)
	var item := {"slot": slot, "type": type, "tier": t}
	match slot:
		"main":
			item["name"] = MAIN_BASES[type][t - 1]
			item["id"] = "main_%s_L%d" % [type, t]
		"off":
			# 副手 2 类（盾/法器）；盗贼双持的副手匕首回落主手匕首系列（设计文档 §15.2）
			item["name"] = (OFF_BASES[type][t - 1] if OFF_BASES.has(type) else MAIN_BASES[type][t - 1])
			item["id"] = "off_%s_L%d" % [type, t]
		"helm", "body", "shoulder", "legs", "boots":
			item["name"] = ARMOR_BASES[type][slot][t - 1]
			item["weight"] = type
			item["id"] = "%s_%s_L%d" % [slot, type, t]
		"ring":
			item["name"] = RING_BASES[t - 1]
			item["type"] = "ring"
			item["id"] = "ring_L%d" % t
		"trinket":
			item["name"] = TRINKET_BASES[t - 1]
			item["type"] = "trinket"
			item["id"] = "trinket_L%d" % t
	return item


static func base_count() -> int:
	## 基础件总数断言用：30 主手 + 10 副手 + 75 护甲 + 5 戒指 + 5 饰品 = 125
	return 125


static func affix_def(affix_id: String) -> Dictionary:
	for a in AFFIXES:
		if str(a["id"]) == affix_id:
			return a
	return {}


static func legendary_def(leg_id: String) -> Dictionary:
	for l in LEGENDARIES:
		if str(l["id"]) == leg_id:
			return l
	return {}


# ---------- 穿戴校验 ----------

## 职业能否穿戴该件（按槽位语义：主手看武器类型 / 副手看副手类型 / 护甲看权重 / 首饰通用）
static func can_wear(class_id: String, item: Dictionary) -> bool:
	var ct: Dictionary = CLASS_TYPES.get(class_id, {})
	if ct.is_empty():
		return false
	var slot := str(item.get("slot", ""))
	match slot:
		"main":
			return str(item.get("type", "")) in ct["main"]
		"off":
			return str(item.get("type", "")) in ct["off"]
		"helm", "body", "shoulder", "legs", "boots":
			return str(item.get("weight", item.get("type", ""))) == str(ct["armor"])
		_:
			return true  # 戒指/饰品全职业通用


# ---------- 掉落生成 ----------

## 品级权重（随楼层线性 + 重生加成 + 归一化）。返回 [粗品, 普通, 精良, 史诗] 概率。
static func quality_weights(floor_index: int, rebirth_count: int) -> Array:
	var t := clampf((float(floor_index) - 1.0) / 4.0, 0.0, 1.0)
	var w := []
	for i in 4:
		w.append(lerpf(QUALITY_W_F1[i], QUALITY_W_F5[i], t))
	var bonus := minf(QUALITY_REBIRTH_BONUS * float(rebirth_count),
		maxf(0.0, QUALITY_RB_CAP - (w[2] + w[3])))
	w[2] += bonus / 2.0
	w[3] += bonus / 2.0
	var total := 0.0
	for v in w:
		total += float(v)
	var out := []
	for v in w:
		out.append(float(v) / total)
	return out


static func roll_quality(floor_index: int, rebirth_count: int) -> int:
	var roll := randf()
	var acc := 0.0
	var weights := quality_weights(floor_index, rebirth_count)
	for i in 4:
		acc += float(weights[i])
		if roll <= acc:
			return i
	return 3


## 词条 roll：按品级栏数从该槽位可用池中不重复抽取，每条独立 roll T1~T5 + 太古判定。
static func roll_affixes(slot: String, quality: int) -> Array:
	var out := []
	if quality <= 0:
		return out
	var pool := []
	for a in AFFIXES:
		if slot in a["slots"] and (quality >= 2 or not a.has("effects")):
			pool.append(a)
	pool.shuffle()
	for a in pool.slice(0, mini(quality, pool.size())):
		if a.has("effects"):
			out.append({"id": a["id"], "tier": 0, "ancient": false})  # 复合词条固定数值
		else:
			out.append({"id": a["id"], "tier": randi_range(1, 5),
				"ancient": randf() < ANCIENT_CHANCE})
	return out


## 掉落槽位族（戒指掉落记为 "ring"，穿戴时可入 ring_a/ring_b 任意栏）
const DROP_SLOTS := ["main", "off", "helm", "body", "shoulder", "legs", "boots", "ring", "trinket"]

## 组装一件普通装备实例（品质 roll → 词条 roll → 内在属性 → 太古标记）。
## 内在属性（层级公式轴，2026-10-12 拍板）：主/副手攻击力；全件元素专精（随机绑定一元素）；主/副/鞋特效增幅。
static func roll_item(floor_index: int, rebirth_count: int, class_id: String, monster: Dictionary) -> Dictionary:
	var quality := roll_quality(floor_index, rebirth_count)
	var slot: String = DROP_SLOTS[randi() % DROP_SLOTS.size()]
	var type := _roll_type(slot, floor_index, class_id)
	var base := base_item(slot, type, clampi(floor_index, 1, 5))
	var item := {
		"id": base["id"], "name": base["name"], "slot": slot, "type": base.get("type", type),
		"tier": base["tier"], "weight": base.get("weight", ""),
		"quality": quality, "ancient": false, "affixes": roll_affixes(slot, quality),
		"legendary": "", "monster": str(monster.get("name", "")),
	}
	_apply_intrinsics(item)
	return item


## 按层级公式写入内在属性（攻击力/元素专精/特效增幅）。
static func _apply_intrinsics(item: Dictionary) -> void:
	var slot := str(item.get("slot", ""))
	var tier := int(item.get("tier", 1))
	if slot in ["main", "off"]:
		item["atk"] = intr_atk(tier)
	if slot in INTR_SPEC_SLOTS:
		item["spec_amp"] = intr_spec(tier)
	item["elem"] = randi() % 6
	item["elem_per"] = intr_elem(tier)


## 内在属性展示文本（面板用）
static func intr_text(item: Dictionary) -> String:
	var lines := []
	if item.has("atk"):
		lines.append("攻击力 +%d%%" % int(round(float(item["atk"]) * 100.0)))
	if item.has("elem_per"):
		var names := ["火", "水", "風", "土", "光", "闇"]
		var eid := int(item.get("elem", 0))
		lines.append("%s属性方块伤害 +%d%%" % [names[eid % 6], int(round(float(item["elem_per"]) * 100.0))])
	if item.has("spec_amp"):
		lines.append("特殊方块效果 +%d%%" % int(round(float(item["spec_amp"]) * 100.0)))
	return "\n".join(lines)


## 掉落类型 roll：80% 职业可用偏向（拍板 D2.2），20% 全池随机。
static func _roll_type(slot: String, floor_index: int, class_id: String) -> String:
	var ct: Dictionary = CLASS_TYPES.get(class_id, {})
	match slot:
		"main":
			var types: Array = MAIN_BASES.keys()
			if randf() < 0.8 and not ct.is_empty():
				types = ct["main"]
			return types[randi() % types.size()]
		"off":
			var types2: Array = OFF_BASES.keys()
			if randf() < 0.8 and not ct.is_empty() and not (ct["off"] as Array).is_empty():
				types2 = ct["off"]
			return types2[randi() % types2.size()]
		"helm", "body", "shoulder", "legs", "boots":
			if randf() < 0.8 and not ct.is_empty():
				return str(ct["armor"])
			var weights: Array = ARMOR_BASES.keys()
			return weights[randi() % weights.size()]
		_:
			return slot  # ring/trinket


## 传奇判定：击杀结算时调用。返回命中的全部传奇实例（首杀挂点可多件同落；
## kill 概率挂点命中后继续评估其余件）。claimed = 已获得过的传奇 id（存档持久化）。
## 传奇同样吃层级内在属性（tier = 掉落楼层），高层传奇不贬值。
static func roll_legendary(monster: Dictionary, is_elite: bool, is_first_kill: bool, claimed: Array, floor_index: int) -> Array:
	var out := []
	var mname := str(monster.get("name", ""))
	for leg in LEGENDARIES:
		var lid := str(leg["id"])
		if lid in claimed:
			continue
		var hook: Dictionary = leg["hook"]
		var hit := false
		match str(hook.get("type", "none")):
			"first_kill":
				hit = is_first_kill and mname == str(hook.get("monster", ""))
			"kill":
				hit = mname == str(hook.get("monster", "")) and randf() < float(hook.get("chance", 0.05))
			"elite_kill":
				hit = is_elite and randf() < float(hook.get("chance", 0.02))
			"guard_kill":
				hit = mname in ["守林古树", "镇风桩", "千瓣祭主"] and randf() < float(hook.get("chance", 0.03))
		if not hit:
			continue
		var affixes := roll_affixes(str(leg["slot"]), 3)
		var inst := {
			"id": lid, "name": str(leg["name"]), "slot": str(leg["slot"]),
			"type": str(leg["type"]), "tier": clampi(floor_index, 1, 999), "weight": "", "quality": 3,
			"ancient": false, "affixes": affixes, "legendary": lid,
			"monster": mname,
		}
		_apply_intrinsics(inst)
		out.append(inst)
	return out


## 词条数值（含太古 ×1.5）。返回 mult 语义的 per（add 键同样是 per）。
static func affix_per(affix: Dictionary) -> float:
	var def := affix_def(str(affix["id"]))
	if def.is_empty() or not def.has("tiers"):
		return 0.0
	var tier := int(affix.get("tier", 1))
	if tier <= 0:
		return 0.0  # 复合词条走 effects
	var v := float(def["tiers"][clampi(tier, 1, 5) - 1])
	return v * (ANCIENT_MULT if bool(affix.get("ancient", false)) else 1.0)


## 词条展示文本（面板/toast 用）
static func affix_text(affix: Dictionary) -> String:
	var def := affix_def(str(affix["id"]))
	if def.is_empty():
		return ""
	if def.has("effects"):
		var parts := []
		for ef in def["effects"]:
			parts.append(_per_text(str(ef["key"]), str(ef["kind"]), float(ef["per"])))
		return "%s：%s" % [str(def["name"]), " & ".join(parts)]
	return "%s：%s" % [str(def["name"]), _per_text(str(def["key"]), str(def["kind"]), affix_per(affix))]


static func _per_text(key: String, kind: String, per: float) -> String:
	if key == "steps":
		return "步数 +%d" % int(round(per))
	if kind == "add":
		return "%s %+.1f%%" % [key, per * 100.0]
	return "%s %+.0f%%" % [key, per * 100.0]
