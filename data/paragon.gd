class_name GameParagon
## 巅峰板块定义表（2026-10-11 拍板：板块列表式 / 天赋 2 倍数值 / 传奇解锁链 / 洗点免费）。
##
## 每板块结构：普通 ×4（rank 0~5）+ 稀有 ×2（rank 0~3）+ 传奇三选一（rank 0~1，互斥）。
## 数值 = 同级天赋的 2 倍（天赋普通 +3%/级 → 巅峰普通 +6%/级）。
## 解锁链：板块 N 需板块 N-1 的传奇节点已购（任选其一）。
## 板块主题与节点名已世界观线审定（圣经第八轮）：世界之冬 / 尼达维勒分号 / 枝务厅编制。

const BOARDS := {
	"p1": {
		"name": "世界之冬（破坏）",
		"desc": "世界之冬从未真正结束，只是化进了每一次撞击里。",
		"requires_legendary_of": "",
		"nodes": [
			{"id": "p1_n1", "ring": 1, "name": "冻风磨砺", "kind": "mult", "mod": "battle_damage", "per": 0.06, "max": 5, "desc": "消除伤害 +6%/级"},
			{"id": "p1_n2", "ring": 1, "name": "碎冰认知", "kind": "mult", "mod": "weakness", "per": 0.06, "max": 5, "desc": "弱点倍率 +6%/级"},
			{"id": "p1_n3", "ring": 1, "name": "寒髓提炼", "kind": "mult", "mod": "ep", "per": 0.06, "max": 5, "desc": "精华获取 +6%/级"},
			{"id": "p1_n4", "ring": 1, "name": "凝霜果实", "kind": "mult", "mod": "fruit", "per": 0.04, "max": 5, "desc": "果实获取 +4%/级"},
			{"id": "p1_r1", "ring": 2, "name": "深冬之击", "kind": "mult", "mod": "battle_damage", "per": 0.12, "max": 3, "desc": "消除伤害 +12%/级"},
			{"id": "p1_r2", "ring": 2, "name": "永冻库", "kind": "mult", "mod": "ep", "per": 0.12, "max": 3, "desc": "精华获取 +12%/级"},
			{"id": "p1_key_a", "ring": 3, "name": "终焉之寒", "kind": "mult", "mod": "battle_damage", "per": 0.30, "max": 1, "key": true, "desc": "消除伤害 +30%", "tradeoff": "挂机收入 -15%"},
			{"id": "p1_key_a_off", "ring": 3, "name": "", "kind": "mult", "mod": "income", "per": -0.15, "max": 1, "key_of": "p1_key_a"},
			{"id": "p1_key_b", "ring": 3, "name": "蚀骨之冬", "kind": "mult", "mod": "weakness", "per": 0.40, "max": 1, "key": true, "desc": "弱点倍率 +40%"},
			{"id": "p1_key_c", "ring": 3, "name": "万象冻结", "kind": "add", "mod": "chain_bonus", "per": 0.08, "max": 1, "key": true, "desc": "连锁每波加成 +8%"},
		],
	},
	"p2": {
		"name": "尼达维勒分号（经济）",
		"desc": "商会西迁后的第一个分号，专营巅峰生意。",
		"requires_legendary_of": "p1",
		"nodes": [
			{"id": "p2_n1", "ring": 1, "name": "行情特权", "kind": "mult", "mod": "income", "per": 0.06, "max": 5, "desc": "挂机收入 +6%/级"},
			{"id": "p2_n2", "ring": 1, "name": "收购价", "kind": "mult", "mod": "bounty", "per": 0.06, "max": 5, "desc": "赏金 +6%/级"},
			{"id": "p2_n3", "ring": 1, "name": "会员折扣", "kind": "mult", "mod": "train_cost", "per": -0.06, "max": 5, "desc": "训练费用 -6%/级"},
			{"id": "p2_n4", "ring": 1, "name": "免申特权", "kind": "add", "mod": "fee", "per": -0.003, "max": 5, "desc": "手续费 -0.3%/级"},
			{"id": "p2_r1", "ring": 2, "name": "西迁专营", "kind": "mult", "mod": "income", "per": 0.12, "max": 3, "desc": "挂机收入 +12%/级"},
			{"id": "p2_r2", "ring": 2, "name": "行会背书", "kind": "mult", "mod": "bounty", "per": 0.12, "max": 3, "desc": "赏金 +12%/级"},
			{"id": "p2_key_a", "ring": 3, "name": "商会分红", "kind": "mult", "mod": "income", "per": 0.30, "max": 1, "key": true, "desc": "挂机收入 +30%"},
			{"id": "p2_key_b", "ring": 3, "name": "垄断专营", "kind": "mult", "mod": "bounty", "per": 0.35, "max": 1, "key": true, "desc": "赏金 +35%", "tradeoff": "挂机收入 -10%"},
			{"id": "p2_key_b_off", "ring": 3, "name": "", "kind": "mult", "mod": "income", "per": -0.10, "max": 1, "key_of": "p2_key_b"},
			{"id": "p2_key_c", "ring": 3, "name": "快递垄断", "kind": "mult", "mod": "fruit", "per": 0.20, "max": 1, "key": true, "desc": "果实获取 +20%", "tradeoff": "挂机收入 +10%"},
			{"id": "p2_key_c_off", "ring": 3, "name": "", "kind": "mult", "mod": "income", "per": 0.10, "max": 1, "key_of": "p2_key_c"},
		],
	},
	"p3": {
		"name": "枝务厅编制（通用）",
		"desc": "从编外枝叶转正的那一刻，树的祝福直通到根。",
		"requires_legendary_of": "p2",
		"nodes": [
			{"id": "p3_n1", "ring": 1, "name": "编制津贴", "kind": "add", "mod": "steps", "per": 1, "max": 3, "desc": "步数 +1/级"},
			{"id": "p3_n2", "ring": 1, "name": "公文速批", "kind": "mult", "mod": "train_cost", "per": -0.04, "max": 5, "desc": "训练费用 -4%/级"},
			{"id": "p3_n3", "ring": 1, "name": "在编精华", "kind": "mult", "mod": "ep", "per": 0.05, "max": 5, "desc": "精华获取 +5%/级"},
			{"id": "p3_n4", "ring": 1, "name": "年轮津贴", "kind": "mult", "mod": "fruit", "per": 0.03, "max": 5, "desc": "果实获取 +3%/级"},
			{"id": "p3_r1", "ring": 2, "name": "铁饭碗", "kind": "mult", "mod": "train_cost", "per": -0.10, "max": 3, "desc": "训练费用 -10%/级"},
			{"id": "p3_r2", "ring": 2, "name": "在编果篮", "kind": "mult", "mod": "fruit", "per": 0.08, "max": 3, "desc": "果实获取 +8%/级"},
			{"id": "p3_key_a", "ring": 3, "name": "登层特权", "kind": "add", "mod": "steps", "per": 8, "max": 1, "key": true, "desc": "步数 +8"},
			{"id": "p3_key_b", "ring": 3, "name": "枝务厅徽章", "kind": "mult", "mod": "train_cost", "per": -0.25, "max": 1, "key": true, "desc": "训练费用 -25%", "tradeoff": "挂机收入 -10%"},
			{"id": "p3_key_b_off", "ring": 3, "name": "", "kind": "mult", "mod": "income", "per": -0.10, "max": 1, "key_of": "p3_key_b"},
			{"id": "p3_key_c", "ring": 3, "name": "编制保障", "kind": "mult", "mod": "income", "per": 0.15, "max": 1, "key": true, "desc": "挂机收入 +15%", "tradeoff": "弱点倍率 -15%"},
			{"id": "p3_key_c_off", "ring": 3, "name": "", "kind": "mult", "mod": "weakness", "per": -0.15, "max": 1, "key_of": "p3_key_c"},
		],
	},
}

const BOARD_ORDER: Array[String] = ["p1", "p2", "p3"]


static func get_board(board_id: String) -> Dictionary:
	return BOARDS.get(board_id, {})


static func get_node_def(node_id: String) -> Dictionary:
	for bid in BOARDS.keys():
		for n in BOARDS[bid]["nodes"]:
			if n["id"] == node_id:
				var out := {}  # 手动复制：const 字典浅拷贝会继承只读标志
				for k in n.keys():
					out[k] = n[k]
				out["board"] = bid
				return out
	return {}
