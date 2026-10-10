class_name GameRaces
## 种族定义表（9 种族，2026-10-11 拍板）。调味层：单条小杠杆，与职业自由组合。
## 通用占位名——最终命名由世界观线按圣经风格审定（矮人已与尼达维勒商会设定天然对齐）。

const RACES := {
	"human": {
		"name": "人类",
		"desc": "什么都行，什么都不精——但树最偏爱这种不确定性。",
		"traits": ["步数 +1", "训练费用 -3%"],
		"mods": {"steps": 1, "train_cost": 0.97},
	},
	"elf": {
		"name": "精灵",
		"desc": "森林亲和，精华在指尖聚得格外快。",
		"traits": ["精华获取 +10%"],
		"mods": {"ep": 1.10},
	},
	"dwarf": {
		"name": "矮人",
		"desc": "尼达维勒商会的远房表亲，手续费？那是对外人的。",
		"traits": ["交易所手续费减半", "赏金 +5%"],
		"mods": {"fee": -0.005, "bounty": 1.05},
	},
	"giantsblood": {
		"name": "巨人血裔",
		"desc": "创世巨人的余脉，拳头比脑子先醒。",
		"traits": ["消除伤害 +8%", "挂机收入 -5%"],
		"mods": {"battle_damage": 1.08, "income": 0.95},
	},
	"orc": {
		"name": "兽人",
		"desc": "以战养战的掠夺者，账本是拿来撕的。",
		"traits": ["赏金 +10%", "挂机收入 -4%"],
		"mods": {"bounty": 1.10, "income": 0.96},
	},
	"gnome": {
		"name": "侏儒",
		"desc": "尼达维勒的发明工匠，把训练透支成效率。",
		"traits": ["训练费用 -5%", "精华获取 +5%"],
		"mods": {"train_cost": 0.95, "ep": 1.05},
	},
	"troll": {
		"name": "巨魔",
		"desc": "皮糙肉厚，站着站着就把活干完了。",
		"traits": ["步数 +2", "挂机收入 +4%"],
		"mods": {"steps": 2, "income": 1.04},
	},
	"dark_elf": {
		"name": "暗精灵",
		"desc": "阴影里的账房先生，每一刀都算过利息。",
		"traits": ["赏金 +6%", "连锁每波加成 +3%"],
		"mods": {"bounty": 1.06, "chain_bonus": 0.03},
	},
	"high_elf": {
		"name": "高等精灵",
		"desc": "奥术贵族，弱点在它们眼里是写好的标签。",
		"traits": ["弱点倍率 +5%", "精华获取 +8%"],
		"mods": {"weakness": 1.05, "ep": 1.08},
	},
}


static func get_race(id: String) -> Dictionary:
	return RACES.get(id, {})
