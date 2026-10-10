class_name GameRaces
## 种族定义表（9 种族，2026-10-11 拍板）。调味层：单条小杠杆，与职业自由组合。
## desc 字段为世界观线审定版（2026-10-11 第五轮风格拍板：说明书式，直白纪律）。
## 种族关系设定：矮人是尼达维勒商会的主人一族，侏儒是工匠支系（圣经 §6 同步）。

const RACES := {
	"human": {
		"name": "人类",
		"desc": "各项小幅占优，和任何职业都好搭的种族。",
		"traits": ["步数 +1", "训练费用 -3%"],
		"mods": {"steps": 1, "train_cost": 0.97},
	},
	"elf": {
		"name": "精灵",
		"desc": "精华获取更高的种族。",
		"traits": ["精华获取 +10%"],
		"mods": {"ep": 1.10},
	},
	"dwarf": {
		"name": "矮人",
		"desc": "交易所手续费减半，赏金略高的种族。",
		"traits": ["交易所手续费减半", "赏金 +5%"],
		"mods": {"fee": -0.005, "bounty": 1.05},
	},
	"giantsblood": {
		"name": "巨人血裔",
		"desc": "伤害更高，挂机收入略低的种族。",
		"traits": ["消除伤害 +8%", "挂机收入 -5%"],
		"mods": {"battle_damage": 1.08, "income": 0.95},
	},
	"orc": {
		"name": "兽人",
		"desc": "赏金更高，挂机收入略低的种族。",
		"traits": ["赏金 +10%", "挂机收入 -4%"],
		"mods": {"bounty": 1.10, "income": 0.96},
	},
	"gnome": {
		"name": "侏儒",
		"desc": "训练更便宜，精华获取略高的种族。",
		"traits": ["训练费用 -5%", "精华获取 +5%"],
		"mods": {"train_cost": 0.95, "ep": 1.05},
	},
	"troll": {
		"name": "巨魔",
		"desc": "步数更多，挂机收入略高的种族。",
		"traits": ["步数 +2", "挂机收入 +4%"],
		"mods": {"steps": 2, "income": 1.04},
	},
	"dark_elf": {
		"name": "暗精灵",
		"desc": "赏金和连锁加成略高的种族。",
		"traits": ["赏金 +6%", "连锁每波加成 +3%"],
		"mods": {"bounty": 1.06, "chain_bonus": 0.03},
	},
	"high_elf": {
		"name": "高等精灵",
		"desc": "弱点倍率和精华获取更高的种族。",
		"traits": ["弱点倍率 +5%", "精华获取 +8%"],
		"mods": {"weakness": 1.05, "ep": 1.08},
	},
}


static func get_race(id: String) -> Dictionary:
	return RACES.get(id, {})
