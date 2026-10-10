class_name GameTalents
## 天赋树定义表（7 棵职业专属树，2026-10-11 拍板：D4 经典被动树蓝本）。
##
## 节点结构（每树）：
##   圈 1：普通节点 ×3（每级 1 点，rank 上限 5，效果递增）
##   圈 2：普通节点 ×3（rank 5）
##   圈 3：重点节点 ×1（rank 3，大幅效果）
##   圈 4：关键天赋三选一（rank 1，流派定义，互斥）
## 层圈门槛 TREE_GATE：进入圈 n 需树上已投入点数达标（D4 式铺量解锁）。
##
## 节点字段：{id, ring, name, kind(mult/add), mod, per(每级效果), max(等级上限), desc}
## 关键节点另带 tradeoff_desc（副作用说明）。效果在 mods.gd 按 talents{节点id: rank} 换算。
##
## 点数分流（拍板）：Lv.60 前每级 +1 技能点进天赋树；Lv.60 起每级 +1 巅峰点（巅峰系统预留）。

const PARAGON_LEVEL := 60            # 该等级起技能点分流为巅峰点
const TREE_GATE := [0, 3, 12, 25]    # ring 1~4 的解锁所需总投入

const TREES := {
	"warrior": {
		"name": "战士 · 不屈之道",
		"nodes": [
			{"id": "war_1", "ring": 1, "name": "锻体", "kind": "mult", "mod": "battle_damage", "per": 0.03, "max": 5, "desc": "消除伤害 +3%/级"},
			{"id": "war_2", "ring": 1, "name": "掠取", "kind": "mult", "mod": "bounty", "per": 0.02, "max": 5, "desc": "赏金 +2%/级"},
			{"id": "war_3", "ring": 1, "name": "苦学", "kind": "mult", "mod": "train_cost", "per": -0.01, "max": 5, "desc": "训练费用 -1%/级"},
			{"id": "war_4", "ring": 2, "name": "战吼", "kind": "mult", "mod": "battle_damage", "per": 0.02, "max": 5, "desc": "消除伤害 +2%/级"},
			{"id": "war_5", "ring": 2, "name": "战利品", "kind": "mult", "mod": "bounty", "per": 0.02, "max": 5, "desc": "赏金 +2%/级"},
			{"id": "war_6", "ring": 2, "name": "耐力", "kind": "add", "mod": "steps", "per": 1, "max": 2, "desc": "步数 +1/级"},
			{"id": "war_7", "ring": 3, "name": "不灭战意", "kind": "mult", "mod": "battle_damage", "per": 0.05, "max": 3, "desc": "消除伤害 +5%/级"},
			{"id": "war_key_a", "ring": 4, "name": "狂战之魂", "kind": "mult", "mod": "battle_damage", "per": 0.20, "max": 1, "key": true, "desc": "消除伤害 +20%", "tradeoff": "挂机收入 -10%"},
			{"id": "war_key_a_off", "ring": 4, "name": "", "kind": "mult", "mod": "income", "per": -0.10, "max": 1, "key_of": "war_key_a"},
			{"id": "war_key_b", "ring": 4, "name": "不屈之壁", "kind": "add", "mod": "steps", "per": 3, "max": 1, "key": true, "desc": "步数 +3", "tradeoff": "训练费用 +10%"},
			{"id": "war_key_b_off", "ring": 4, "name": "", "kind": "mult", "mod": "train_cost", "per": 0.10, "max": 1, "key_of": "war_key_b"},
			{"id": "war_key_c", "ring": 4, "name": "掠夺之道", "kind": "mult", "mod": "bounty", "per": 0.25, "max": 1, "key": true, "desc": "赏金 +25%"},
		],
	},
	"mage": {
		"name": "法师 · 奥术之径",
		"nodes": [
			{"id": "mag_1", "ring": 1, "name": "元素专精", "kind": "mult", "mod": "weakness", "per": 0.03, "max": 5, "desc": "弱点倍率 +3%/级"},
			{"id": "mag_2", "ring": 1, "name": "聚能", "kind": "mult", "mod": "ep", "per": 0.04, "max": 5, "desc": "精华获取 +4%/级"},
			{"id": "mag_3", "ring": 1, "name": "冥想", "kind": "mult", "mod": "income", "per": 0.02, "max": 5, "desc": "挂机收入 +2%/级"},
			{"id": "mag_4", "ring": 2, "name": "法刃", "kind": "mult", "mod": "battle_damage", "per": 0.02, "max": 5, "desc": "消除伤害 +2%/级"},
			{"id": "mag_5", "ring": 2, "name": "汲取", "kind": "mult", "mod": "ep", "per": 0.03, "max": 5, "desc": "精华获取 +3%/级"},
			{"id": "mag_6", "ring": 2, "name": "勤修", "kind": "mult", "mod": "train_cost", "per": -0.015, "max": 5, "desc": "训练费用 -1.5%/级"},
			{"id": "mag_7", "ring": 3, "name": "奥术洪流", "kind": "mult", "mod": "ep", "per": 0.10, "max": 3, "desc": "精华获取 +10%/级"},
			{"id": "mag_key_a", "ring": 4, "name": "奥术超载", "kind": "mult", "mod": "weakness", "per": 0.50, "max": 1, "key": true, "desc": "弱点倍率 +50%"},
			{"id": "mag_key_b", "ring": 4, "name": "精华洪流", "kind": "mult", "mod": "ep", "per": 0.30, "max": 1, "key": true, "desc": "精华获取 +30%"},
			{"id": "mag_key_c", "ring": 4, "name": "秘学纲要", "kind": "mult", "mod": "train_cost", "per": -0.15, "max": 1, "key": true, "desc": "训练费用 -15%", "tradeoff": "挂机收入增益 +10%（原加成上调）"},
			{"id": "mag_key_c_off", "ring": 4, "name": "", "kind": "mult", "mod": "income", "per": 0.10, "max": 1, "key_of": "mag_key_c"},
		],
	},
	"rogue": {
		"name": "盗贼 · 影匿之道",
		"nodes": [
			{"id": "rog_1", "ring": 1, "name": "黑市人脉", "kind": "mult", "mod": "bounty", "per": 0.03, "max": 5, "desc": "赏金 +3%/级"},
			{"id": "rog_2", "ring": 1, "name": "手稳", "kind": "mult", "mod": "battle_damage", "per": 0.02, "max": 5, "desc": "消除伤害 +2%/级"},
			{"id": "rog_3", "ring": 1, "name": "眼线", "kind": "mult", "mod": "income", "per": 0.02, "max": 5, "desc": "挂机收入 +2%/级"},
			{"id": "rog_4", "ring": 2, "name": "背刺", "kind": "mult", "mod": "battle_damage", "per": 0.025, "max": 5, "desc": "消除伤害 +2.5%/级"},
			{"id": "rog_5", "ring": 2, "name": "连环", "kind": "add", "mod": "chain_bonus", "per": 0.01, "max": 5, "desc": "连锁每波加成 +1%/级"},
			{"id": "rog_6", "ring": 2, "name": "销赃", "kind": "mult", "mod": "bounty", "per": 0.02, "max": 5, "desc": "赏金 +2%/级"},
			{"id": "rog_7", "ring": 3, "name": "影中利刃", "kind": "add", "mod": "chain_bonus", "per": 0.02, "max": 3, "desc": "连锁每波加成 +2%/级"},
			{"id": "rog_key_a", "ring": 4, "name": "暗影收割", "kind": "mult", "mod": "bounty", "per": 0.30, "max": 1, "key": true, "desc": "赏金 +30%"},
			{"id": "rog_key_b", "ring": 4, "name": "致命节奏", "kind": "mult", "mod": "weakness", "per": 0.20, "max": 1, "key": true, "desc": "弱点倍率 +20%"},
			{"id": "rog_key_c", "ring": 4, "name": "神偷", "kind": "mult", "mod": "ep", "per": 0.15, "max": 1, "key": true, "desc": "精华获取 +15%", "tradeoff": "交易所手续费 +0.5%"},
			{"id": "rog_key_c_off", "ring": 4, "name": "", "kind": "add", "mod": "fee", "per": 0.005, "max": 1, "key_of": "rog_key_c"},
		],
	},
	"priest": {
		"name": "牧师 · 圣愈之道",
		"nodes": [
			{"id": "pri_1", "ring": 1, "name": "圣言", "kind": "mult", "mod": "income", "per": 0.03, "max": 5, "desc": "挂机收入 +3%/级"},
			{"id": "pri_2", "ring": 1, "name": "抚慰", "kind": "mult", "mod": "ep", "per": 0.03, "max": 5, "desc": "精华获取 +3%/级"},
			{"id": "pri_3", "ring": 1, "name": "晨祷", "kind": "mult", "mod": "bounty", "per": 0.02, "max": 5, "desc": "赏金 +2%/级"},
			{"id": "pri_4", "ring": 2, "name": "祝福", "kind": "mult", "mod": "income", "per": 0.02, "max": 5, "desc": "挂机收入 +2%/级"},
			{"id": "pri_5", "ring": 2, "name": "坚韧祷言", "kind": "add", "mod": "steps", "per": 1, "max": 2, "desc": "步数 +1/级"},
			{"id": "pri_6", "ring": 2, "name": "慈光", "kind": "mult", "mod": "battle_damage", "per": 0.015, "max": 5, "desc": "消除伤害 +1.5%/级"},
			{"id": "pri_7", "ring": 3, "name": "丰盛之恩", "kind": "mult", "mod": "income", "per": 0.05, "max": 3, "desc": "挂机收入 +5%/级"},
			{"id": "pri_key_a", "ring": 4, "name": "圣光普惠", "kind": "mult", "mod": "income", "per": 0.25, "max": 1, "key": true, "desc": "挂机收入 +25%"},
			{"id": "pri_key_b", "ring": 4, "name": "永恒祈愿", "kind": "add", "mod": "steps", "per": 4, "max": 1, "key": true, "desc": "步数 +4"},
			{"id": "pri_key_c", "ring": 4, "name": "苦修", "kind": "mult", "mod": "train_cost", "per": -0.15, "max": 1, "key": true, "desc": "训练费用 -15%", "tradeoff": "挂机收入 -8%"},
			{"id": "pri_key_c_off", "ring": 4, "name": "", "kind": "mult", "mod": "income", "per": -0.08, "max": 1, "key_of": "pri_key_c"},
		],
	},
	"paladin": {
		"name": "圣骑士 · 誓约之道",
		"nodes": [
			{"id": "pal_1", "ring": 1, "name": "誓约之力", "kind": "mult", "mod": "battle_damage", "per": 0.02, "max": 5, "desc": "消除伤害 +2%/级"},
			{"id": "pal_2", "ring": 1, "name": "节俭", "kind": "mult", "mod": "train_cost", "per": -0.01, "max": 5, "desc": "训练费用 -1%/级"},
			{"id": "pal_3", "ring": 1, "name": "什一税", "kind": "mult", "mod": "income", "per": 0.02, "max": 5, "desc": "挂机收入 +2%/级"},
			{"id": "pal_4", "ring": 2, "name": "重锤", "kind": "mult", "mod": "battle_damage", "per": 0.02, "max": 5, "desc": "消除伤害 +2%/级"},
			{"id": "pal_5", "ring": 2, "name": "纪律", "kind": "add", "mod": "steps", "per": 1, "max": 2, "desc": "步数 +1/级"},
			{"id": "pal_6", "ring": 2, "name": "丰饶", "kind": "mult", "mod": "bounty", "per": 0.02, "max": 5, "desc": "赏金 +2%/级"},
			{"id": "pal_7", "ring": 3, "name": "圣印", "kind": "mult", "mod": "battle_damage", "per": 0.04, "max": 3, "desc": "消除伤害 +4%/级"},
			{"id": "pal_key_a", "ring": 4, "name": "审判", "kind": "mult", "mod": "battle_damage", "per": 0.12, "max": 1, "key": true, "desc": "消除伤害 +12%", "tradeoff": "训练费用 +8%"},
			{"id": "pal_key_a_off", "ring": 4, "name": "", "kind": "mult", "mod": "train_cost", "per": 0.08, "max": 1, "key_of": "pal_key_a"},
			{"id": "pal_key_b", "ring": 4, "name": "壁垒誓言", "kind": "add", "mod": "steps", "per": 5, "max": 1, "key": true, "desc": "步数 +5"},
			{"id": "pal_key_c", "ring": 4, "name": "守护者之誓", "kind": "mult", "mod": "income", "per": 0.15, "max": 1, "key": true, "desc": "挂机收入 +15%", "tradeoff": "训练费用 +8%"},
			{"id": "pal_key_c_off", "ring": 4, "name": "", "kind": "mult", "mod": "train_cost", "per": 0.08, "max": 1, "key_of": "pal_key_c"},
		],
	},
	"ranger": {
		"name": "游侠 · 巡猎之道",
		"nodes": [
			{"id": "ran_1", "ring": 1, "name": "轻装", "kind": "add", "mod": "steps", "per": 1, "max": 5, "desc": "步数 +1/级"},
			{"id": "ran_2", "ring": 1, "name": "向导", "kind": "mult", "mod": "income", "per": 0.02, "max": 5, "desc": "挂机收入 +2%/级"},
			{"id": "ran_3", "ring": 1, "name": "箭雨", "kind": "mult", "mod": "battle_damage", "per": 0.02, "max": 5, "desc": "消除伤害 +2%/级"},
			{"id": "ran_4", "ring": 2, "name": "追踪", "kind": "mult", "mod": "bounty", "per": 0.025, "max": 5, "desc": "赏金 +2.5%/级"},
			{"id": "ran_5", "ring": 2, "name": "长风", "kind": "add", "mod": "chain_bonus", "per": 0.008, "max": 5, "desc": "连锁每波加成 +0.8%/级"},
			{"id": "ran_6", "ring": 2, "name": "补给", "kind": "mult", "mod": "ep", "per": 0.03, "max": 5, "desc": "精华获取 +3%/级"},
			{"id": "ran_7", "ring": 3, "name": "千里眼", "kind": "mult", "mod": "bounty", "per": 0.04, "max": 3, "desc": "赏金 +4%/级"},
			{"id": "ran_key_a", "ring": 4, "name": "鹰眼", "kind": "mult", "mod": "weakness", "per": 0.15, "max": 1, "key": true, "desc": "弱点倍率 +15%", "tradeoff": "挂机收入增益 -5%"},
			{"id": "ran_key_a_off", "ring": 4, "name": "", "kind": "mult", "mod": "income", "per": -0.05, "max": 1, "key_of": "ran_key_a"},
			{"id": "ran_key_b", "ring": 4, "name": "狩猎季节", "kind": "mult", "mod": "bounty", "per": 0.20, "max": 1, "key": true, "desc": "赏金 +20%", "tradeoff": "消除伤害 -5%"},
			{"id": "ran_key_b_off", "ring": 4, "name": "", "kind": "mult", "mod": "battle_damage", "per": -0.05, "max": 1, "key_of": "ran_key_b"},
			{"id": "ran_key_c", "ring": 4, "name": "漂泊者", "kind": "mult", "mod": "income", "per": 0.20, "max": 1, "key": true, "desc": "挂机收入 +20%", "tradeoff": "步数 -2"},
			{"id": "ran_key_c_off", "ring": 4, "name": "", "kind": "add", "mod": "steps", "per": -2, "max": 1, "key_of": "ran_key_c"},
		],
	},
	"warlock": {
		"name": "术士 · 献祭之道",
		"nodes": [
			{"id": "wrl_1", "ring": 1, "name": "血价", "kind": "mult", "mod": "battle_damage", "per": 0.04, "max": 5, "desc": "消除伤害 +4%/级"},
			{"id": "wrl_2", "ring": 1, "name": "契约", "kind": "mult", "mod": "fruit", "per": 0.02, "max": 5, "desc": "果实获取 +2%/级"},
			{"id": "wrl_3", "ring": 1, "name": "暗學", "kind": "mult", "mod": "weakness", "per": 0.02, "max": 5, "desc": "弱点倍率 +2%/级"},
			{"id": "wrl_4", "ring": 2, "name": "吞噬", "kind": "mult", "mod": "battle_damage", "per": 0.03, "max": 5, "desc": "消除伤害 +3%/级"},
			{"id": "wrl_5", "ring": 2, "name": "低语", "kind": "mult", "mod": "weakness", "per": 0.02, "max": 5, "desc": "弱点倍率 +2%/级"},
			{"id": "wrl_6", "ring": 2, "name": "魔典", "kind": "mult", "mod": "ep", "per": 0.03, "max": 5, "desc": "精华获取 +3%/级"},
			{"id": "wrl_7", "ring": 3, "name": "深渊回响", "kind": "mult", "mod": "battle_damage", "per": 0.06, "max": 3, "desc": "消除伤害 +6%/级"},
			{"id": "wrl_key_a", "ring": 4, "name": "恶魔契约·终章", "kind": "mult", "mod": "battle_damage", "per": 0.35, "max": 1, "key": true, "desc": "消除伤害 +35%", "tradeoff": "挂机收入 -25%"},
			{"id": "wrl_key_a_off", "ring": 4, "name": "", "kind": "mult", "mod": "income", "per": -0.25, "max": 1, "key_of": "wrl_key_a"},
			{"id": "wrl_key_b", "ring": 4, "name": "灵魂收割", "kind": "mult", "mod": "fruit", "per": 0.15, "max": 1, "key": true, "desc": "果实获取 +15%", "tradeoff": "挂机收入 -10%"},
			{"id": "wrl_key_b_off", "ring": 4, "name": "", "kind": "mult", "mod": "income", "per": -0.10, "max": 1, "key_of": "wrl_key_b"},
			{"id": "wrl_key_c", "ring": 4, "name": "禁忌知识", "kind": "mult", "mod": "ep", "per": 0.25, "max": 1, "key": true, "desc": "精华获取 +25%", "tradeoff": "弱点倍率 -10%"},
			{"id": "wrl_key_c_off", "ring": 4, "name": "", "kind": "mult", "mod": "weakness", "per": -0.10, "max": 1, "key_of": "wrl_key_c"},
		],
	},
}


static func get_tree_for(class_id: String) -> Dictionary:
	## 取某职业的天赋树；无匹配返回空树
	return TREES.get(class_id, {"name": "—", "nodes": []})


static func get_node_def(node_id: String) -> Dictionary:
	## 按节点 id 在全部树中查找定义
	for cid in TREES.keys():
		for n in TREES[cid]["nodes"]:
			if n["id"] == node_id:
				return n
	return {}
