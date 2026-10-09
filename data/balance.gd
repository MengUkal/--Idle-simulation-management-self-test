class_name Balance
## 数值配置中心 —— 所有可调数值集中在这里，改数值只改这个文件，不动逻辑代码。
##
## 已拍板决策（详见 docs/游戏设计文档.md）：
##   货币 = 吉尔(G)；等级即收入；费用指数 x1.15/级；二层门槛 Lv.10；
##   升级设定 = 向世界树献金；离线收益 MVP 不做；
##   挂机节奏 = 纯挂机 Lv.1→Lv.10 约 30 分钟以上（2026-10-09 第二次拍板）。

# ---------- 初始状态 ----------
const START_MONEY := 0.0            # 初始吉尔
const START_LEVEL := 1

# ---------- 挂机收入 ----------
const INCOME_BASE := 0.06           # 【已拍板】Lv.1 基础收入（吉尔/秒）
const INCOME_GROWTH := 1.10         # 【已拍板】每级收入倍率（指数，慢于费用倍率 → 越练越慢）
# 公式：income(level) = INCOME_BASE * INCOME_GROWTH ^ (level - 1)
# 节奏核算：纯挂机 Lv.1→Lv.10（攒够即献金）约 30.1 分钟；首升约 2 分 47 秒。

# ---------- 献金升级 ----------
const UPGRADE_BASE_COST := 10.0     # 升到 Lv.2 的费用
const UPGRADE_COST_GROWTH := 1.15   # 【已拍板】每级费用倍率（指数）
# 公式：cost(level) = UPGRADE_BASE_COST * UPGRADE_COST_GROWTH ^ (level - 1)

# ---------- 世界树层数 ----------
const FLOOR_2_LEVEL_REQ := 10       # 【已拍板】进入第二层所需等级
const FLOOR_NAMES := {
	1: "第一层 · 树根之街",
	2: "第二层 · ???（未实装）",
}

# ---------- 消消乐冒险（M2） ----------
const BOARD_SIZE := 7               # 【已拍板】棋盘 7×7
const ELEMENT_KINDS := 6            # 【已拍板】6 种元素
const BATTLE_STEPS_BASE := 10       # 【已拍板】Lv.1 步数 = 10
const BATTLE_STEPS_PER_LEVEL := 0.5 # 【已拍板】每级 +0.5 步（即每 2 级 +1）
# 第一层怪物表（2026-10-09 草案落地；数值直接改这里，不用动代码）
# 元素索引：0火 1水 2風 3土 4光 5闇；克制：火克風、風克土、土克水、水克火、光闇互克
const MONSTERS_FLOOR1 := [
	{"name": "树精史莱姆", "hp": 30, "bounty": 5, "weak": 0},
	{"name": "風狼", "hp": 45, "bounty": 8, "weak": 3},
	{"name": "岩甲龟", "hp": 70, "bounty": 12, "weak": 1},
	{"name": "水妖", "hp": 55, "bounty": 10, "weak": 3},
	{"name": "光萤", "hp": 40, "bounty": 9, "weak": 5},
	{"name": "暗影鼠", "hp": 40, "bounty": 9, "weak": 4},
]
const MONSTER_ELITE_FLOOR1 := {"name": "树根守卫", "hp": 150, "bounty": 40, "weak": 4}
const ELITE_CHANCE := 0.1           # [占位] 精英出现率
const WEAKNESS_MULT := 2.0          # 命中弱点属性的伤害倍率
const CHAIN_BONUS_PER_WAVE := 0.2   # 连锁加成：第 n 波伤害 ×(1 + 0.2×(n-1))
# 元素设定（【已拍板】全色皆攻击 + 属性克制）：
# 火 → 風 → 土 → 水 → 火 循环相克；光 ↔ 闇 互克（克制加成数值随怪物表审定）
const ELEMENT_NAMES := ["火", "水", "風", "土", "光", "闇"]
const ELEMENT_COLORS := [Color("e0564f"), Color("4f8fe0"), Color("58b46b"), Color("c2954a"), Color("f2e6c8"), Color("8a5fbf")]
const ELEMENT_TEXT_COLORS := [Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color("3a2f1b"), Color.WHITE]


static func battle_steps(level: int) -> int:
	# 本场冒险步数上限：Lv.1 = 10、Lv.10 = 15、Lv.30 = 25
	return BATTLE_STEPS_BASE + int(level * BATTLE_STEPS_PER_LEVEL)


static func damage_multiplier(element: int, monster: Dictionary) -> float:
	## 命中弱点属性返回 WEAKNESS_MULT，否则 1.0
	return WEAKNESS_MULT if element == int(monster.get("weak", -1)) else 1.0


# ---------- 元素精华与训练线（NGU 式多线成长，2026-10-09 拍板落地） ----------
const EP_PER_TILE := 1              # 每消除 1 块获得的元素精华
const EP_WEAKNESS_MULT := 2.0       # 弱点属性方块的精华倍率
const TRAIN_COST_BASE := 25.0       # 训练线 0→1 级费用（精华）
const TRAIN_COST_GROWTH := 1.35     # 训练线每级费用倍率
const TRAIN_EFFECT_PER_LEVEL := 0.05 # 每级 +5%（攻击/赏金/收入三线通用）
const MILESTONE_EP := {2: 10, 4: 15, 6: 20, 8: 30}  # 等级里程碑一次性精华


static func train_cost(level: int) -> float:
	## 训练线从 level 级升到 level+1 级的精华费用
	return TRAIN_COST_BASE * pow(TRAIN_COST_GROWTH, float(level))


static func train_multiplier(line_level: int) -> float:
	return 1.0 + TRAIN_EFFECT_PER_LEVEL * float(line_level)


# ---------- 存档 ----------
const AUTOSAVE_INTERVAL_SEC := 10.0

# ---------- 文案 ----------
const CURRENCY_SHORT := "G"
const UPGRADE_FLAVOR := "向世界树献金，换取更深的祝福"


static func income_per_sec(level: int) -> float:
	return INCOME_BASE * pow(INCOME_GROWTH, float(level - 1))


static func upgrade_cost(level: int) -> float:
	# 从 level 级升到 level+1 级所需的献金
	return UPGRADE_BASE_COST * pow(UPGRADE_COST_GROWTH, float(level - 1))


static func format_number(value: float) -> String:
	# 数值显示：<1 保留两位小数；<10 保留一位；<10000 整数千分位；
	# ≥10000 中文单位 万/亿/兆/京。例：0.06 / 6.5 / 1,234 / 1.23万
	var abs_v := absf(value)
	if abs_v < 1.0:
		return _with_sign(value, _strip_zeros("%.2f" % abs_v))
	if abs_v < 10.0:
		return _with_sign(value, _strip_zeros("%.1f" % abs_v))
	if abs_v < 10000.0:
		return _with_sign(value, _group_thousands(int(round(abs_v))))
	var units := ["万", "亿", "兆", "京"]
	var idx := -1
	while abs_v >= 10000.0 and idx < units.size() - 1:
		abs_v /= 10000.0
		idx += 1
	return _with_sign(value, _strip_zeros("%.2f" % abs_v) + units[idx])


static func _with_sign(value: float, body: String) -> String:
	return ("-" if value < 0.0 else "") + body


static func _strip_zeros(text: String) -> String:
	# "12.00" -> "12"；"1.50" -> "1.5"
	while text.ends_with("0"):
		text = text.trim_suffix("0")
	if text.ends_with("."):
		text = text.trim_suffix(".")
	return text


static func _group_thousands(n: int) -> String:
	# 1234567 -> "1,234,567"
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out
