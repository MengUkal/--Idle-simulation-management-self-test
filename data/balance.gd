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
