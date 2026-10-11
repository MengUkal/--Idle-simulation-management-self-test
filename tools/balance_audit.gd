extends SceneTree
## 数据平衡审计（一次性工具，P5 乘区满配审计 + 模块体检）。
##   godot --headless --path . --script res://tools/balance_audit.gd
## 从真实数据表算：极限乘区 / 费用下限 / 生存 / 技能 / 经济闭环，输出供《数据审计报告》引用。

var _sec := ""


func p(s: String) -> void:
	print(s)


func sec(t: String) -> void:
	_sec = t
	p("")
	p("=== %s ===" % t)


## 某来源段里某 key 的加算合计（mult 表存 1+x 形式）
static func _src_sum(mods: Dictionary, key: String) -> float:
	return float(mods.get(key, 1.0)) - 1.0 if mods.has(key) and float(mods.get(key, 1.0)) != 0.0 else 0.0


func _init() -> void:
	# ---------- A. 消除伤害乘区 ----------
	sec("A. 消除伤害乘区（满配 BIS）")
	# A1 职业/种族
	var best_class := 0.0
	var best_class_name := ""
	for cid in GameClasses.CLASSES:
		var v := _src_sum(GameClasses.CLASSES[cid]["mods"], "battle_damage")
		if v > best_class:
			best_class = v
			best_class_name = str(cid)
	var best_race := 0.0
	var best_race_name := ""
	for rid in GameRaces.RACES:
		var v2 := _src_sum(GameRaces.RACES[rid]["mods"], "battle_damage")
		if v2 > best_race:
			best_race = v2
			best_race_name = str(rid)
	p("职业最高 +%d%%（%s）｜ 种族最高 +%d%%（%s）" % [
		round(best_class * 100), best_class_name, round(best_race * 100), best_race_name])
	# A2 天赋：全树 battle_damage 加算合计（取所有树的最大值）
	var best_tree := 0.0
	var best_tree_name := ""
	for tid in GameTalents.TREES:
		var s := 0.0
		for n in GameTalents.TREES[tid]["nodes"]:
			if str(n.get("mod", "")) == "battle_damage" and str(n.get("kind", "")) == "mult":
				s += float(n.get("per", 0.0)) * int(n.get("max", 1))
		if s > best_tree:
			best_tree = s
			best_tree_name = str(tid)
	p("天赋满树最高 +%d%%（%s）" % [round(best_tree * 100), best_tree_name])
	# A3 巅峰：全板块 battle_damage 合计
	var par := 0.0
	for bid in GameParagon.BOARDS:
		for n in GameParagon.BOARDS[bid]["nodes"]:
			if str(n.get("mod", "")) == "battle_damage" and str(n.get("kind", "")) == "mult":
				par += float(n.get("per", 0.0)) * int(n.get("max", 1))
	p("巅峰全板块 +%.0f%%" % (par * 100))
	# A4 装备 BIS：逐槽位取 battle_damage 可出词条的 T5 值
	var slot_bd := {}
	for a in GameEquipment.AFFIXES:
		if str(a["id"]) != "af_sharp":
			continue
		for s3 in a["slots"]:
			var v3 := float(a["tiers"][4])
			if not slot_bd.has(s3) or v3 > float(slot_bd[s3]):
				slot_bd[s3] = v3
	var eq_mult := 1.0
	var eq_parts := []
	for s4 in slot_bd.keys():
		eq_mult *= 1.0 + float(slot_bd[s4])
		eq_parts.append("%s+%.0f%%" % [str(s4), float(slot_bd[s4]) * 100])
	p("装备可出消除伤害的槽位：%s" % "、".join(eq_parts))
	# 传奇祖品（主手限定取最高）
	var best_leg := 0.0
	var best_leg_name := ""
	for l in GameEquipment.LEGENDARIES:
		for ef in l["special"]:
			if str(ef.get("key", "")) == "battle_damage":
				var v4 := float(ef.get("per", 0.0))
				if v4 > best_leg:
					best_leg = v4
					best_leg_name = str(l["name"])
	p("传奇祖品特效最高 +%d%%（%s，占主手）" % [round(best_leg * 100), best_leg_name])
	# A5 内在属性：攻击力（主手，层级 L）
	p("内在攻击力：L1 +%d%% / L5 +%d%% / L10 +%d%%（层级不封顶）" % [
		round(GameEquipment.intr_atk(1) * 100), round(GameEquipment.intr_atk(5) * 100),
		round(GameEquipment.intr_atk(10) * 100)])
	# A6 汇总（装备 4 槽 BIS + 主手传奇 + 内在 L5）
	var total := (1.0 + best_class + best_race + best_tree + par) \
		* eq_mult * (1.0 + best_leg) * (1.0 + GameEquipment.intr_atk(5))
	p("▶ 满配消除伤害乘区 ≈ ×%.2f（未含弱点×2/连锁/训练线/果实/蓄力窗×2）" % total)
	p("▶ 含弱点×2 与连锁 3 波（×1.4）：单波峰值 ≈ ×%.1f；蓄力窗再 ×2" % (total * 2.0 * 1.4))

	# ---------- B. 挂机收入乘区 ----------
	sec("B. 挂机收入乘区（满配 BIS）")
	var bc := 0.0
	for cid2 in GameClasses.CLASSES:
		bc = maxf(bc, _src_sum(GameClasses.CLASSES[cid2]["mods"], "income"))
	var br := 0.0
	for rid2 in GameRaces.RACES:
		br = maxf(br, _src_sum(GameRaces.RACES[rid2]["mods"], "income"))
	var bt := 0.0
	for tid2 in GameTalents.TREES:
		var s5 := 0.0
		for n2 in GameTalents.TREES[tid2]["nodes"]:
			if str(n2.get("mod", "")) == "income" and str(n2.get("kind", "")) == "mult":
				s5 += float(n2.get("per", 0.0)) * int(n2.get("max", 1))
		bt = maxf(bt, s5)
	var bp := 0.0
	for bid2 in GameParagon.BOARDS:
		for n3 in GameParagon.BOARDS[bid2]["nodes"]:
			if str(n3.get("mod", "")) == "income" and str(n3.get("kind", "")) == "mult":
				bp += float(n3.get("per", 0.0)) * int(n3.get("max", 1))
	# 装备收入 BIS：harvest 6 槽 + zenith 复合
	var inc_slots := {}
	for a2 in GameEquipment.AFFIXES:
		var has_inc := false
		var v5 := 0.0
		if str(a2.get("id")) == "af_harvest":
			has_inc = true
			v5 = float(a2["tiers"][4])
		elif a2.has("effects"):
			for ef in a2["effects"]:
				if str(ef.get("key", "")) == "income":
					has_inc = true
					v5 = maxf(v5, float(ef.get("per", 0.0)))
		if has_inc:
			for s6 in a2["slots"]:
				if not inc_slots.has(s6) or v5 > float(inc_slots[s6]):
					inc_slots[s6] = v5
	var inc_mult := 1.0
	for s7 in inc_slots.keys():
		inc_mult *= 1.0 + float(inc_slots[s7])
	# 伙伴收入：夜香花/光萤/落英妖/树精史莱姆 史诗+看板
	var pet_inc := 0.0
	for pname in GamePets.PETS:
		var pd: Dictionary = GamePets.PETS[pname]
		if str(pd["key"]) == "income":
			pet_inc += GamePets.passive_per(str(pname), 3, true)
	var total_inc := (1.0 + bc + br + bt + bp) * inc_mult * (1.0 + pet_inc)
	p("职业+%d%% 种族+%d%% 天赋+%d%% 巅峰+%.0f%% 装备×%.2f 伙伴+%.0f%%" % [
		round(bc * 100), round(br * 100), round(bt * 100), round(bp * 100), inc_mult, round(pet_inc * 100)])
	p("▶ 满配挂机收入乘区 ≈ ×%.2f（再×果实：每颗 +5%）" % total_inc)
	p("▶ 例：200 果实时 ≈ ×%.1f → Lv.60 挂机 ≈ %s/秒" % [
		(1.0 + 0.05 * 200.0),
		Balance.format_number(Balance.income_per_sec(60) * total_inc * (1.0 + 0.05 * 200.0))])

	# ---------- C. 费用下限（防负数/趋零漏洞） ----------
	sec("C. 费用下限体检")
	var uc_min := 1.0
	# 装备献金折扣：af_tithe 头/饰 ×2（-8% T5）
	uc_min *= 1.0 - 0.08
	uc_min *= 1.0 - 0.08
	# 天赋/巅峰/职业/种族献金折扣扫描
	for tid3 in GameTalents.TREES:
		for n4 in GameTalents.TREES[tid3]["nodes"]:
			if str(n4.get("mod", "")) == "upgrade_cost":
				uc_min *= 1.0 + float(n4.get("per", 0.0)) * int(n4.get("max", 1))
	for bid3 in GameParagon.BOARDS:
		for n5 in GameParagon.BOARDS[bid3]["nodes"]:
			if str(n5.get("mod", "")) == "upgrade_cost":
				uc_min *= 1.0 + float(n5.get("per", 0.0)) * int(n5.get("max", 1))
	for cid3 in GameClasses.CLASSES:
		if GameClasses.CLASSES[cid3]["mods"].has("upgrade_cost"):
			uc_min *= float(GameClasses.CLASSES[cid3]["mods"]["upgrade_cost"])
	p("献金费用满配乘区下限 ≈ %.3f（负数=漏洞）" % uc_min)
	var tc_min := 1.0
	for tid4 in GameTalents.TREES:
		for n6 in GameTalents.TREES[tid4]["nodes"]:
			if str(n6.get("mod", "")) == "train_cost":
				tc_min *= 1.0 + float(n6.get("per", 0.0)) * int(n6.get("max", 1))
	for bid4 in GameParagon.BOARDS:
		for n7 in GameParagon.BOARDS[bid4]["nodes"]:
			if str(n7.get("mod", "")) == "train_cost":
				tc_min *= 1.0 + float(n7.get("per", 0.0)) * int(n7.get("max", 1))
	for cid4 in GameClasses.CLASSES:
		if GameClasses.CLASSES[cid4]["mods"].has("train_cost"):
			tc_min *= float(GameClasses.CLASSES[cid4]["mods"]["train_cost"])
	for rid3 in GameRaces.RACES:
		if GameRaces.RACES[rid3]["mods"].has("train_cost"):
			tc_min *= float(GameRaces.RACES[rid3]["mods"]["train_cost"])
	# 果实训练折扣：train_cost_mult(fruits, rebirth) — 检查内部是否有下限
	var tc200: float = Balance.train_cost_mult(200, 0)
	var tc500: float = Balance.train_cost_mult(500, 0)
	p("训练费用：装备/天赋/职业/种族满配乘区 ≈ %.3f ｜ 果实200≈%.3f 果实500≈%.3f" % [tc_min, tc200, tc500])
	p("▶ 合计训练费用乘区下限 ≈ %.3f（<0 = 负费用漏洞；0~0.1 = 近乎免费）" % (tc_min * minf(tc200, tc500)))

	# ---------- D. 生存（玩家 HP vs 怪物攻击） ----------
	sec("D. 生存（玩家 HP vs 四层攻击）")
	for lv in [50, 60, 80, 100]:
		var hp_base := float(Balance.PLAYER_HP_BASE + Balance.PLAYER_HP_PER_LEVEL * int(lv))
		# BIS 生命：丰盈 头/身/腿 ×3（T5 +18%）+ 苔石巨人/镇风桩 max_hp 伙伴（史诗+看板）+ max_hp 装备
		var vital := pow(1.0 + 0.18, 3.0)
		var pet_hp := 1.0 + (0.02 * 8 * 2.0) + (0.03 * 8 * 2.0)
		var hp_max_v := hp_base * 1.4 * vital * pet_hp  # 战士
		var hit_f4 := 232.0 * 0.4
		p("Lv.%d 战士：基础 %d → 满配生命 ≈ %d（承受四层均伤 %.0f/发 ≈ %d 发）" % [
			int(lv), int(hp_base), int(hp_max_v), hit_f4, int(hp_max_v / hit_f4)])

	# ---------- E. 技能速览 ----------
	sec("E. 主动技能（当前数值）")
	for cid5 in GameSkills.SKILLS:
		var sk: Dictionary = GameSkills.SKILLS[cid5]
		p("%s：%s（%s）%s" % [str(cid5), str(sk.get("name", "")), str(sk.get("resource", "")),
			str(sk.get("note", sk.get("desc", "")))])

	# ---------- F. 经济闭环 ----------
	sec("F. 经济闭环（树胶洗练）")
	p("洗练成本：10 起步 ×2/次 → 10/20/40/80/160…（第 n 次 = 10×2^(n-1)）")
	p("树胶来源：粗品 5 / 普通 15（战斗自动分解 8%×掉率×60%普通系）；四层一场均 ~0.5 件普通系 ≈ 树胶 ~5/场")
	p("▶ 第 5 次洗练需 160 树胶 ≈ 32 场四层战斗——账单制成立；第 8 次(1280)即硬墙（符合拍板「成本递增」）")
	p("▶ 祭品箱：9 星/箱；三星场均产 ~2 星 → ~4.5 场一箱；EV = 0.6×150精华 + 0.3×装备 + 0.1×蛋")

	p("")
	p("=== 审计完成 ===")
	quit()
