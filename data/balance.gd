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
const FLOOR_3_LEVEL_REQ := 50       # 【已拍板 2026-10-11】进入第三层·苍干栈道所需等级（另需层卡：首杀古树掉落）
const FLOOR_NAMES := {
	1: "第一层 · 树根之街",
	2: "第二层 · 翠枝回廊",
	3: "第三层 · 苍干栈道",
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
# 第二层怪物表（2026-10-09 草案落地；数值直接改这里）
const MONSTERS_FLOOR2 := [
	{"name": "荆棘树妖", "hp": 120, "bounty": 18, "weak": 0},
	{"name": "風羽隼", "hp": 150, "bounty": 22, "weak": 3},
	{"name": "苔石巨人", "hp": 220, "bounty": 32, "weak": 1},
	{"name": "沼泽水灵", "hp": 180, "bounty": 26, "weak": 3},
	{"name": "暗藤魔", "hp": 160, "bounty": 24, "weak": 4},
	{"name": "辉羽蝶", "hp": 160, "bounty": 24, "weak": 5},
]
const MONSTER_ELITE_FLOOR2 := {"name": "守林古树", "hp": 500, "bounty": 120, "weak": 0}
# 第三层·苍干栈道怪物表（2026-10-11 拍板：命名/弱点=世界观设定包；HP/赏金=重生练度标定草案档）
# 生态：風系 + 藤蔓寄生系；练度曲线：第 2 轮门槛（Lv.50）打前四只、第 3 轮门槛（Lv.55）全开
const MONSTERS_FLOOR3 := [
	{"name": "旋風雀", "hp": 380, "bounty": 55, "weak": 3},
	{"name": "叶隐蛙", "hp": 420, "bounty": 60, "weak": 0},
	{"name": "風滚草", "hp": 460, "bounty": 62, "weak": 1},
	{"name": "吊藤妖", "hp": 500, "bounty": 68, "weak": 0},
	{"name": "喇叭藤", "hp": 550, "bounty": 72, "weak": 4},
	{"name": "刺藤果", "hp": 620, "bounty": 78, "weak": 5},
]
const MONSTER_ELITE_FLOOR3 := {"name": "镇风桩", "hp": 1100, "bounty": 200, "weak": 1}
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


static func monster_pool(floor_index: int) -> Array:
	## 各层常驻怪物池：在哪层冒险，遇哪层的怪
	if floor_index >= 3:
		return MONSTERS_FLOOR3
	return MONSTERS_FLOOR2 if floor_index >= 2 else MONSTERS_FLOOR1


static func monster_elite(floor_index: int) -> Dictionary:
	if floor_index >= 3:
		return MONSTER_ELITE_FLOOR3
	return MONSTER_ELITE_FLOOR2 if floor_index >= 2 else MONSTER_ELITE_FLOOR1


# ---------- 元素精华与训练线（NGU 式多线成长，2026-10-09 拍板落地） ----------
const EP_PER_TILE := 1              # 每消除 1 块获得的元素精华
const EP_WEAKNESS_MULT := 2.0       # 弱点属性方块的精华倍率
const TRAIN_COST_BASE := 25.0       # 训练线 0→1 级费用（精华）
const TRAIN_COST_GROWTH := 1.35     # 训练线每级费用倍率
const TRAIN_EFFECT_PER_LEVEL := 0.05 # 每级 +5%（攻击/赏金/收入三线通用）
const MILESTONE_EP := {2: 10, 4: 15, 6: 20, 8: 30}  # 等级里程碑一次性精华

# ---------- 交易所（M3，2026-10-09 拍板） ----------
const MARKET_UNLOCK_LEVEL := 15    # 【已拍板】Lv.15 解锁
const MARKET_FEE_RATE := 0.01      # 【已拍板】买卖各 1% 手续费
const MARKET_TICK_SEC := 5.0       # 价格跳动间隔（秒）
const MARKET_CANDLE_SEC := 30.0    # K 线周期（秒/根）
const MARKET_CANDLE_COUNT := 40    # 图表显示根数
const MARKET_TARGETS := [          # 【已拍板】三个元素风味标的（base=基准价 vol=每根波动率）
	{"name": "火晶石", "base": 50.0, "vol": 0.06},
	{"name": "風羽绢", "base": 80.0, "vol": 0.05},
	{"name": "生命露", "base": 120.0, "vol": 0.04},
]


static func train_cost(level: int) -> float:
	## 训练线从 level 级升到 level+1 级的精华费用
	return TRAIN_COST_BASE * pow(TRAIN_COST_GROWTH, float(level))


static func train_multiplier(line_level: int) -> float:
	return 1.0 + TRAIN_EFFECT_PER_LEVEL * float(line_level)


# ---------- 重生公式（M4） ----------

static func rebirth_threshold(rebirth_count: int) -> int:
	## 第 rebirth_count+1 轮重生所需等级：已重生 0 次 → 40，1 次 → 48…
	return REBIRTH_LEVEL_BASE + REBIRTH_LEVEL_STEP * rebirth_count


static func fruits_for_level(level: int) -> int:
	## 重生瞬间按当时等级一次性结算果实【数值定稿】
	## 曲线：Lv.40→5、Lv.45→10、Lv.50→18、Lv.55→27、Lv.60→38
	if level <= 30:
		return 0
	return int(pow((float(level) - 30.0) / FRUIT_DIV, FRUIT_POW))


static func income_fruit_mult(fruits: int) -> float:
	## 挂机收入果实乘数：每颗 +5%
	return 1.0 + FRUIT_INCOME_PER * float(fruits)


static func atk_fruit_mult(fruits: int) -> float:
	## 攻击效果果实乘数：每颗 +1%（三轨化，数值定稿 2026-10-10）
	return 1.0 + FRUIT_ATK_PER * float(fruits)


static func train_cost_mult(fruits: int, rebirth_count: int) -> float:
	## 训练费用总乘数：果实折扣 × 轮数永久衰减
	return pow(1.0 - FRUIT_TRAIN_DISCOUNT, float(fruits)) \
		* pow(1.0 - REBIRTH_TRAIN_DECAY, float(rebirth_count))


static func trade_cost(price: float, shares: int, fee_rate: float = MARKET_FEE_RATE) -> Dictionary:
	## 买入成本：含手续费（费率可由种族修饰符调整）
	var gross := price * float(shares)
	var fee := gross * fee_rate
	return {"gross": gross, "fee": fee, "total": gross + fee}


static func sell_proceeds(price: float, shares: int, fee_rate: float = MARKET_FEE_RATE) -> float:
	## 卖出到手：扣除手续费（费率可由种族修饰符调整）
	var gross := price * float(shares)
	return gross - gross * fee_rate


# ---------- 重生转生（M4，2026-10-10 六项拍板 + 数值定稿问答，详见设计文档 §14） ----------
const REBIRTH_GUIDE_LEVEL := 38     # 【已拍板】首次触墙引导等级（弹世界树引导）
const REBIRTH_LEVEL_BASE := 40      # 【已拍板】首轮重生门槛
const REBIRTH_LEVEL_STEP := 5       # 【已拍板 8 → 数值定稿 5】每轮门槛递增（40/45/50…）
const FRUIT_INCOME_PER := 0.05      # 【已拍板】每颗果实：挂机收入 +5%
const FRUIT_TRAIN_DISCOUNT := 0.02  # 【已拍板】每颗果实：训练费用 -2%
const FRUIT_ATK_PER := 0.01         # 【数值定稿】每颗果实：攻击效果 +1%（三轨化）
const REBIRTH_TRAIN_DECAY := 0.05   # 【已拍板】每轮重生：训练费用永久 -5%
const FRUIT_POW := 1.8              # 【数值定稿】果实公式幂次
const FRUIT_DIV := 4.0              # 【数值定稿】果实公式除数（等级起点固定 30）

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
