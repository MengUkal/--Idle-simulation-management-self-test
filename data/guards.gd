class_name GuardKit
extends RefCounted
## 层守机制包（2026-10-11 拍板：Boss战斗包 + 用户指令"每个层守机制独特化"）。
## 层守 = 各层层守精英（守林古树/镇风桩，未来：千瓣祭主）；普通精英与常驻怪不受影响。
## 纯逻辑无场景依赖：battle.gd（演出）与 sim_test（AI 模拟）共用同一套状态机，保证不漂移。
## 设计对照《智龙迷城玩法拆解》§5/§6：先制/血量阈值/根性/吸收盾 → 转译为本游戏步数竞速语言
## （怪物不攻击玩家，故"蓄力/狂暴"表达为易伤窗口与减伤墙，而非敌方攻击翻倍）。

## 层守机制表（键 = 怪物名；一人一套，互不同质）：
## - 守林古树「不倒的编外层守」：硬开（树皮减伤）→ 给机会（年轮蓄力易伤窗）→ 最后一道门（根性）。
## - 镇风桩「商会的荣耀试炼」：全件套（弱点封印 + 单消盾 + 蓄力窗 + 狂暴墙 + 根性）。
const KITS := {
	"守林古树": {
		"opener": {"tag": "先制·树皮硬化", "steps": 3, "dr": 0.5},
		"charge": {"tag": "年轮蓄力", "at": 0.5, "steps": 3, "mult": 2.0},
		"resolve": {"tag": "根性"},
	},
	"镇风桩": {
		"opener": {"tag": "先制·弱点封印", "steps": 3, "seal_weak": true},
		"shield": {"tag": "连击护盾"},
		"charge": {"tag": "桩劲蓄力", "at": 0.5, "steps": 3, "mult": 2.0},
		"rage": {"tag": "狂暴", "at": 0.25, "dr": 0.4},
		"resolve": {"tag": "根性"},
	},
}

var def: Dictionary
var opener_left := 0
var charge_left := 0
var charge_used := false
var raged := false
var resolve_used := false


func _init(monster_name: String) -> void:
	def = KITS.get(str(monster_name), {})
	opener_left = int(opener().get("steps", 0))


func has_kit() -> bool:
	return not def.is_empty()


func opener() -> Dictionary:
	return def.get("opener", {})


func is_sealed() -> bool:
	## 弱点封印中：弱点克制 ×2 失效（含弱点精华加成）
	return opener_left > 0 and bool(opener().get("seal_weak", false))


## 本步伤害修正入口：{mult: 全局伤害倍率, sealed: 弱点被封印, blocked: 单消被盾挡}
func move_modifiers(waves_count: int, from_skill: bool) -> Dictionary:
	var out := {"mult": 1.0, "sealed": false, "blocked": false}
	if not has_kit():
		return out
	var mult := 1.0
	if opener_left > 0:
		mult *= 1.0 - float(opener().get("dr", 0.0))
	if charge_left > 0:
		mult *= float(def.get("charge", {}).get("mult", 1.0))
	if raged:
		mult *= 1.0 - float(def.get("rage", {}).get("dr", 0.0))
	out["mult"] = mult
	out["sealed"] = is_sealed()
	# 连击盾：单波消除无效；主动技能是解法，不受盾影响（盾挡普消不挡技能）
	out["blocked"] = bool(def.has("shield")) and not from_skill and waves_count < 2
	return out


## 伤害落定后推进状态机。返回事件标签（供战斗层播横幅/音效）：
## "charge" = 蓄力窗开启 / "rage" = 狂暴启动。计数器在本步生效后递减。
func after_move(hp_frac: float) -> Array:
	var events: Array = []
	if not has_kit():
		return events
	var charge_started := false
	if not charge_used and def.has("charge") and hp_frac <= float(def["charge"].get("at", 0.5)):
		charge_used = true
		charge_left = int(def["charge"].get("steps", 3))
		charge_started = true  # 触发步的伤害已结算完毕，窗口从下一步开始计步
		events.append("charge")
	elif def.has("rage") and not raged and charge_left <= 0 \
			and hp_frac <= float(def["rage"].get("at", 0.25)):
		raged = true
		events.append("rage")
	if opener_left > 0:
		opener_left -= 1
	if charge_left > 0 and not charge_started:
		charge_left -= 1
	return events


## 致死一击的处理：根性未用则锁 1 HP 生还（限一次）。返回是否生还。
func on_lethal() -> bool:
	if has_kit() and def.has("resolve") and not resolve_used:
		resolve_used = true
		return true
	return false


## HUD 常驻状态标签（挂在敌人名后，让规则一直可读）
func state_tag() -> String:
	if not has_kit():
		return ""
	var parts: Array = []
	if is_sealed():
		parts.append("弱点封印")
	if def.has("shield"):
		parts.append("盾·单消无效")
	if charge_left > 0:
		parts.append("蓄力×2")
	if raged:
		parts.append("狂暴减伤")
	if parts.is_empty():
		return ""
	return "｜" + "／".join(parts)
