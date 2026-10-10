class_name GameSkills
## 主动技能定义表（7 职业，2026-10-11 拍板：S1 技能表 / S2 资源模型多样化 / S3 正常伤害结算）。
##
## 资源模型三种：
##   charge — 充能型：每消除 charge_per 块 +1 能量，上限 max 格，释放耗 1 格
##   fixed  — 固定次数型：每场战斗 uses 次
##   steps  — 代价型：释放消耗 step_cost 步（不占能量）
##
## targeting = true 的技能需要玩家点选棋盘目标（格/列）。

const SKILLS := {
	"warrior": {
		"name": "破城锤",
		"desc": "摧毁目标方块及其上下左右四块",
		"resource": "charge", "charge_per": 8, "max": 3, "targeting": true,
	},
	"mage": {
		"name": "元素嬗变",
		"desc": "随机 6 个方块变为怪物弱点属性",
		"resource": "charge", "charge_per": 6, "max": 3, "targeting": false,
	},
	"rogue": {
		"name": "偷天换日",
		"desc": "重排全盘棋子（不会自动消除）",
		"resource": "fixed", "uses": 1, "targeting": false,
	},
	"priest": {
		"name": "圣光祈祷",
		"desc": "步数 +3",
		"resource": "fixed", "uses": 2, "targeting": false,
	},
	"paladin": {
		"name": "祝圣之槌",
		"desc": "将目标方块变为爆炸特殊块",
		"resource": "charge", "charge_per": 10, "max": 2, "targeting": true,
	},
	"ranger": {
		"name": "穿透箭",
		"desc": "清除目标一整列并触发掉落连锁",
		"resource": "charge", "charge_per": 8, "max": 2, "targeting": true,
	},
	"warlock": {
		"name": "暗影瘟疫",
		"desc": "约一半方块随机变为其他颜色",
		"resource": "steps", "step_cost": 2, "targeting": false,
	},
}


static func get_skill(class_id: String) -> Dictionary:
	return SKILLS.get(class_id, {})
