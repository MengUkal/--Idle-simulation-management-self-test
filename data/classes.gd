class_name GameClasses
## 职业定义表（7 职业，2026-10-11 拍板，效果「显著」档）。
## mods 键与 autoload/mods.gd 的 MULT_KEYS / ADD_KEYS 对齐：
##   乘数键 battle_damage / weakness / income / upgrade_cost / train_cost / bounty / ep / fruit
##   加数键 steps / chain_bonus / fee
## 数值为草案值——全职业模拟平衡报告（sim_test 第七节）出来后可微调，机制不变。
## desc 字段为世界观线审定版（2026-10-11 第五轮风格拍板：说明书式，直白纪律）。
## 天赋树【已拍板：每职业一棵专属树】——tree 字段为预留结构（本期不可消费）。

const CLASSES := {
	"warrior": {
		"name": "战士",
		"desc": "伤害和赏金更高，训练也更慢的直球职业。",
		"traits": ["消除伤害 +15%", "赏金 +10%", "训练费用 +5%"],
		"mods": {"battle_damage": 1.15, "bounty": 1.10, "train_cost": 1.05},
		"tree": "warrior",
	},
	"mage": {
		"name": "法师",
		"desc": "弱点倍率更高，精华获取更多的元素职业。",
		"traits": ["弱点倍率 +25%（2.0 → 2.5）", "精华获取 +20%"],
		"mods": {"weakness": 1.25, "ep": 1.20},
		"tree": "mage",
	},
	"rogue": {
		"name": "盗贼",
		"desc": "连锁加成和赏金更高，打得越久越占便宜的职业。",
		"traits": ["连锁每波加成 +20% → +30%", "赏金 +15%"],
		"mods": {"chain_bonus": 0.10, "bounty": 1.15},
		"tree": "rogue",
	},
	"priest": {
		"name": "牧师",
		"desc": "挂机收入更高，步数更多的稳健职业。",
		"traits": ["挂机收入 +15%", "步数 +2"],
		"mods": {"income": 1.15, "steps": 2},
		"tree": "priest",
	},
	"paladin": {
		"name": "圣骑士",
		"desc": "训练更便宜，各属性小幅占优的均衡职业。",
		"traits": ["训练费用 -10%", "步数 +1", "消除伤害 +5%"],
		"mods": {"train_cost": 0.90, "steps": 1, "battle_damage": 1.05},
		"tree": "paladin",
	},
	"ranger": {
		"name": "游侠",
		"desc": "步数最多，后期连锁收益更高的灵活职业。",
		"traits": ["步数 +3", "连锁每波加成 +5%（后期向增强）", "挂机收入 +5%"],
		"mods": {"steps": 3, "chain_bonus": 0.05, "income": 1.05},
		"tree": "ranger",
	},
	"warlock": {
		"name": "术士",
		"desc": "伤害最高但挂机收入最低，果实获取更多的冒险职业。",
		"traits": ["消除伤害 +25%", "挂机收入 -15%", "果实获取 +10%"],
		"mods": {"battle_damage": 1.25, "income": 0.85, "fruit": 1.10},
		"tree": "warlock",
	},
}


static func get_data(id: String) -> Dictionary:
	## 注意：不可命名为 get_class —— 与 Object.get_class() 原生方法撞名，4.7 下警告即报错（2026-10-10 音频会话代修）
	return CLASSES.get(id, {})
