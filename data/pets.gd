class_name GamePets
extends RefCounted
## 伙伴系统数据表（P-b，2026-10-11 第十四轮拍板 D1~D6 精简版）。
## 蛋掉落 → 图鉴点亮 → 常驻小被动全员生效；看板位一只 ×2（不重复计常驻）。
## 被动从怪物特性派生（T1 级数值，sim 可调）；蛋品质复用装备四档：每升一档加成 ×2。

const EGG_DROP_COMMON := 0.02         # 常驻怪掉本怪蛋
const EGG_DROP_ELITE := 0.15          # 精英掉本怪蛋
const BOARD_MULT := 2.0               # 看板位被动 ×2（不重复计常驻）

## 28 只怪物 → 派生被动（key/kind 与 Mods 键表一致；per 为品质 1 档基准值）
const PETS := {
	# 一层·树根之街
	"树精史莱姆": {"key": "income", "kind": "mult", "per": 0.01},
	"風狼": {"key": "battle_damage", "kind": "mult", "per": 0.01},
	"岩甲龟": {"key": "dr", "kind": "add", "per": 0.01},
	"水妖": {"key": "train_cost", "kind": "mult", "per": -0.005},
	"光萤": {"key": "income", "kind": "mult", "per": 0.01},
	"暗影鼠": {"key": "bounty", "kind": "mult", "per": 0.01},
	"树根守卫": {"key": "max_hp", "kind": "mult", "per": 0.02},
	# 二层·翠枝回廊
	"荆棘树妖": {"key": "battle_damage", "kind": "mult", "per": 0.01},
	"風羽隼": {"key": "steps", "kind": "add", "per": 1},
	"苔石巨人": {"key": "max_hp", "kind": "mult", "per": 0.02},
	"沼泽水灵": {"key": "regen", "kind": "add", "per": 1},
	"暗藤魔": {"key": "chain_bonus", "kind": "add", "per": 0.003},
	"辉羽蝶": {"key": "weakness", "kind": "mult", "per": 0.01},
	"守林古树": {"key": "fruit", "kind": "mult", "per": 0.01},
	# 三层·苍干栈道
	"旋風雀": {"key": "steps", "kind": "add", "per": 1},
	"叶隐蛙": {"key": "dr", "kind": "add", "per": 0.01},
	"風滚草": {"key": "bounty", "kind": "mult", "per": 0.01},
	"吊藤妖": {"key": "ep", "kind": "mult", "per": 0.01},
	"喇叭藤": {"key": "chain_bonus", "kind": "add", "per": 0.003},
	"刺藤果": {"key": "battle_damage", "kind": "mult", "per": 0.01},
	"镇风桩": {"key": "max_hp", "kind": "mult", "per": 0.03},
	# 四层·落英花冠
	"落英妖": {"key": "income", "kind": "mult", "per": 0.01},
	"花粉蛾": {"key": "battle_damage", "kind": "mult", "per": 0.01},
	"夜香花": {"key": "income", "kind": "mult", "per": 0.02},
	"蜜壶蜂": {"key": "ep", "kind": "mult", "per": 0.02},
	"灯芯草妖": {"key": "regen", "kind": "add", "per": 1},
	"曼陀花妖": {"key": "battle_damage", "kind": "mult", "per": 0.02},
	"千瓣祭主": {"key": "fruit", "kind": "mult", "per": 0.02},
	# 五层·云顶鹰巢
	"云雀妖": {"key": "chain_bonus", "kind": "add", "per": 0.003},
	"云绵羊": {"key": "max_hp", "kind": "mult", "per": 0.03},
	"风筝妖": {"key": "steps", "kind": "add", "per": 1},
	"露珠精": {"key": "regen", "kind": "add", "per": 1},
	"雷蜓": {"key": "battle_damage", "kind": "mult", "per": 0.02},
	"雾里鱼": {"key": "ep", "kind": "mult", "per": 0.02},
	"瞭望鹰": {"key": "fruit", "kind": "mult", "per": 0.03},
}


static func pet_def(monster_name: String) -> Dictionary:
	return PETS.get(str(monster_name), {})


## 品质倍率：每升一档 ×2（粗品×1/普通×2/精良×4/史诗×8）
static func quality_mult(quality: int) -> float:
	return pow(2.0, clampi(quality, 0, 3))


## 被动最终 per：基准 × 品质倍率 ×（看板 ×2 由调用方叠加）
static func passive_per(monster_name: String, quality: int, is_board: bool) -> float:
	var d := pet_def(monster_name)
	if d.is_empty():
		return 0.0
	var v := float(d.get("per", 0.0)) * quality_mult(quality)
	return v * BOARD_MULT if is_board else v


## 被动展示文本
static func passive_text(monster_name: String) -> String:
	var d := pet_def(monster_name)
	if d.is_empty():
		return ""
	var key := str(d.get("key", ""))
	var kind := str(d.get("kind", "mult"))
	var per := float(d.get("per", 0.0))
	if key == "steps" or key == "regen":
		return "%s +%d" % [key, int(per)]
	return "%s %+.1f%%" % [key, per * 100.0]
