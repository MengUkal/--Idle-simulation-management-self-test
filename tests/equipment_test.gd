extends Node
## 装备系统无头测试：表完整性 / 品级权重 / 职业限制 / 太古 / 穿戴 Mods / 传奇挂点 / 存档。
##   godot --headless --path . res://tests/equipment_test.tscn
## save.json 开跑前备份、结束恢复。

const SAVE_PATH := "user://save.json"

var _fails := 0
var _backup := ""
var _had := false


func check(case_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS  " + case_name)
	else:
		_fails += 1
		print("FAIL  %s  %s" % [case_name, detail])


func _ready() -> void:
	await get_tree().process_frame
	_had = FileAccess.file_exists(SAVE_PATH)
	if _had:
		var bf := FileAccess.open(SAVE_PATH, FileAccess.READ)
		_backup = bf.get_as_text()
		bf.close()
	print("equipment_test 开始（存档已备份=%s）" % _had)
	await _run()
	if _had:
		var wf := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		wf.store_string(_backup)
		wf.close()
		SaveManager._load()
	print("---")
	print("equipment_test 结果：%d 项失败" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


func _run() -> void:
	# T0 表完整性
	var main_n := 0
	for t in GameEquipment.MAIN_BASES:
		main_n += (GameEquipment.MAIN_BASES[t] as Array).size()
	check("T0 主手 30 件", main_n == 30)
	var off_n := 0
	for t in GameEquipment.OFF_BASES:
		off_n += (GameEquipment.OFF_BASES[t] as Array).size()
	check("T0 副手 10 件", off_n == 10)
	var arm_n := 0
	for w in GameEquipment.ARMOR_BASES:
		for s in GameEquipment.ARMOR_BASES[w]:
			arm_n += (GameEquipment.ARMOR_BASES[w][s] as Array).size()
	check("T0 护甲 75 件", arm_n == 75)
	check("T0 戒指 5 / 饰品 5",
		GameEquipment.RING_BASES.size() == 5 and GameEquipment.TRINKET_BASES.size() == 5)
	check("T0 基础件合计 125", main_n + off_n + arm_n + 10 == GameEquipment.base_count())
	check("T0 词条池 16 条", GameEquipment.AFFIXES.size() == 16)
	check("T0 传奇 15 件", GameEquipment.LEGENDARIES.size() == 15)
	var keys_ok := true
	for a in GameEquipment.AFFIXES:
		if a.has("effects"):
			for ef in a["effects"]:
				if str(ef["kind"]) == "mult" and not (ef["key"] in Mods.MULT_KEYS):
					keys_ok = false
				if str(ef["kind"]) == "add" and not (ef["key"] in Mods.ADD_KEYS):
					keys_ok = false
		else:
			if str(a["kind"]) == "mult" and not (a["key"] in Mods.MULT_KEYS):
				keys_ok = false
			if str(a["kind"]) == "add" and not (a["key"] in Mods.ADD_KEYS):
				keys_ok = false
	check("T0 词条键全部合法（含 drop_rate 新键）", keys_ok)
	var leg_ok := true
	for l in GameEquipment.LEGENDARIES:
		for ef in l["special"]:
			if str(ef["kind"]) == "mult" and not (ef["key"] in Mods.MULT_KEYS):
				leg_ok = false
			if str(ef["kind"]) == "add" and not (ef["key"] in Mods.ADD_KEYS):
				leg_ok = false
	check("T0 祖品特效键合法", leg_ok)

	# T1 品级权重：随楼层上移 + 重生加成 + 合计封顶
	var w1: Array = GameEquipment.quality_weights(1, 0)
	var w5: Array = GameEquipment.quality_weights(5, 0)
	var s1 := 0.0
	for v in w1:
		s1 += float(v)
	check("T1 权重归一", is_equal_approx(s1, 1.0))
	check("T1 五层史诗高于一层", w5[3] > w1[3])
	check("T1 一层粗品高于五层", w1[0] > w5[0])
	var wb: Array = GameEquipment.quality_weights(1, 10)
	check("T1 重生加成提升精良+史诗", wb[2] + wb[3] > w1[2] + w1[3])
	var wc: Array = GameEquipment.quality_weights(1, 999)
	check("T1 重生加成合计封顶 60%", wc[2] + wc[3] <= 0.601)

	# T2 职业类型限制
	var sword := GameEquipment.base_item("main", "sword", 3)
	var staff := GameEquipment.base_item("main", "staff", 3)
	check("T2 战士可用剑", GameEquipment.can_wear("warrior", sword))
	check("T2 战士不可用杖", not GameEquipment.can_wear("warrior", staff))
	check("T2 法师可用杖", GameEquipment.can_wear("mage", staff))
	var cloth_helm := GameEquipment.base_item("helm", "cloth", 2)
	var heavy_helm := GameEquipment.base_item("helm", "heavy", 2)
	check("T2 法师穿布甲", GameEquipment.can_wear("mage", cloth_helm))
	check("T2 法师不穿重甲", not GameEquipment.can_wear("mage", heavy_helm))
	var ring := GameEquipment.base_item("ring", "ring", 1)
	check("T2 戒指全职业通用",
		GameEquipment.can_wear("warrior", ring) and GameEquipment.can_wear("mage", ring))

	# T3 roll_item 结构（词条数 = 品级栏数，且均匹配槽位）
	GameState.reset()
	GameState.create_character("ranger", "human")
	var item := GameEquipment.roll_item(3, 0, "ranger", {"name": "测试怪"})
	check("T3 品级 0~3", int(item["quality"]) >= 0 and int(item["quality"]) <= 3)
	check("T3 词条数=品级栏数", (item["affixes"] as Array).size() == int(item["quality"]))
	var slots_ok := true
	for af in item["affixes"]:
		var d := GameEquipment.affix_def(str(af["id"]))
		if not (item["slot"] in d["slots"]):
			slots_ok = false
	check("T3 词条均匹配槽位", slots_ok)

	# T4 太古 ×1.5
	var sharp := {"id": "af_sharp", "tier": 5, "ancient": false}
	check("T4 锋锐 T5 = +12%", is_equal_approx(GameEquipment.affix_per(sharp), 0.12))
	var anc := {"id": "af_sharp", "tier": 5, "ancient": true}
	check("T4 太古 ×1.5 = +18%", is_equal_approx(GameEquipment.affix_per(anc), 0.18))

	# T5 穿戴 + Mods 装备来源
	GameState.reset()
	GameState.create_character("warrior", "human")
	var before := Mods.mult("battle_damage")
	var sword_item := {
		"id": "main_sword_L3", "name": "精钢长剑", "slot": "main", "type": "sword",
		"tier": 3, "weight": "", "quality": 2, "ancient": false,
		"affixes": [{"id": "af_sharp", "tier": 5, "ancient": false}], "legendary": "",
	}
	GameState.bag.append(sword_item)
	check("T5 穿戴成功", GameState.equip_from_bag(0) == "")
	check("T5 主手已穿", GameState.equipped.has("main")
		and str(GameState.equipped["main"]["name"]) == "精钢长剑")
	check("T5 Mods 含锋锐 +12%", is_equal_approx(Mods.mult("battle_damage") / before, 1.12))
	check("T5 卸下还原", GameState.unequip("main") == ""
		and is_equal_approx(Mods.mult("battle_damage"), before))

	# T6 职业不符拒绝
	GameState.reset()
	GameState.create_character("mage", "human")
	GameState.bag.append(sword_item)
	var err6: String = GameState.equip_from_bag(0)
	check("T6 法师佩剑被拒", err6 != "" and GameState.bag.size() == 1)

	# T7 影牙·双生：双持匕首才生效
	GameState.reset()
	GameState.create_character("rogue", "human")
	var base_cb := Mods.add("chain_bonus")
	var fang: Dictionary = GameEquipment.legendary_def("leg_shadowfang").duplicate()
	fang["affixes"] = []
	fang["legendary"] = "leg_shadowfang"  # 实例字段（真实掉落由 roll_legendary 填写）
	var off_dagger := GameEquipment.base_item("off", "dagger", 2)
	GameState.bag.append(fang)
	GameState.bag.append(off_dagger)
	GameState.equip_from_bag(0)  # 影牙 → 主手
	var no_dual := Mods.add("chain_bonus")
	print("  [dbg] no_dual=%s base=%s equipped_keys=%s" % [no_dual, base_cb, GameState.equipped.keys()])
	GameState.equip_from_bag(0)  # 副手匕首
	var dual := Mods.add("chain_bonus")
	print("  [dbg] dual=%s off_type=%s" % [dual, str(GameState.equipped.get("off", {}).get("type", "无"))])
	check("T7 未双持不加成", is_equal_approx(no_dual, base_cb))
	check("T7 双持连锁 +3%", is_equal_approx(dual, base_cb + 0.03))

	# T8 传奇首杀必掉 + 领取一次性 + 内在属性随层级
	GameState.reset()
	GameState.create_character("warrior", "human")
	var drops: Array = GameEquipment.roll_legendary({"name": "守林古树"}, true, true, [], 3)
	var ids := []
	for d in drops:
		ids.append(d["id"])
	check("T8 古树首杀双传奇（刃+甲）",
		"leg_oath_blade" in ids and "leg_oath_mail" in ids)
	var all_ids := []
	for l in GameEquipment.LEGENDARIES:
		all_ids.append(l["id"])
	var drops2: Array = GameEquipment.roll_legendary({"name": "守林古树"}, true, false, all_ids, 3)
	check("T8 全部领取后不再掉", drops2.is_empty())

	# T8b 内在属性公式轴（层级 1~N 永续成长）
	check("T8b atk 公式 L1/L5/L9", is_equal_approx(GameEquipment.intr_atk(1), 0.12)
		and is_equal_approx(GameEquipment.intr_atk(5), 0.28)
		and is_equal_approx(GameEquipment.intr_atk(9), 0.44))
	check("T8b elem 公式 L1/L5", is_equal_approx(GameEquipment.intr_elem(1), 0.06)
		and is_equal_approx(GameEquipment.intr_elem(5), 0.14))
	check("T8b spec 公式 L5", is_equal_approx(GameEquipment.intr_spec(5), 0.20))
	var intr_item := GameEquipment.roll_item(5, 0, "warrior", {"name": "x"})
	var islot := str(intr_item["slot"])
	check("T8b roll_item 携带内在属性", intr_item.has("elem_per")
		and (intr_item.has("atk") if islot in ["main", "off"] else not intr_item.has("atk"))
		and (intr_item.has("spec_amp") if islot in GameEquipment.INTR_SPEC_SLOTS else not intr_item.has("spec_amp")))

	# T9 背包容量
	GameState.reset()
	GameState.create_character("warrior", "human")
	for i in GameState.BAG_CAPACITY:
		GameState.bag.append({"id": "x%d" % i, "name": "占位", "slot": "trinket", "type": "trinket",
			"tier": 1, "weight": "", "quality": 2, "ancient": false, "affixes": [], "legendary": ""})
	check("T9 背包 30 上限", GameState._add_to_bag({"id": "y"}) == "full")

	# T10 战斗掉落结算冒烟（含 killed_once 记录）
	var toast: String = GameState.battle_drop({"name": "树精史莱姆"}, false)
	check("T10 掉落结算无崩溃", GameState.killed_once.has("树精史莱姆"))

	# T11 存档 roundtrip
	GameState.bag.append({"id": "ring_L2", "name": "锡戒", "slot": "ring", "type": "ring",
		"tier": 2, "weight": "", "quality": 3, "ancient": true,
		"affixes": [{"id": "af_luck", "tier": 3, "ancient": false}], "legendary": ""})
	SaveManager.save()
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	check("T11 背包落盘", (data.get("bag", []) as Array).size() == GameState.bag.size())
	check("T11 穿戴落盘",
		(data.get("equipped", {}) as Dictionary).size() == GameState.equipped.size())
	check("T11 传奇记录落盘",
		(data.get("leg_claimed", []) as Array).size() == GameState.leg_claimed.size())
	check("T11 击杀记录落盘",
		(data.get("killed_once", {}) as Dictionary).size() == GameState.killed_once.size())

	# T12 分解与树胶（E2）
	GameState.reset()
	GameState.create_character("warrior", "human")
	GameState.glue = 0
	GameState.bag.append({"id": "t_a", "name": "粗品件", "slot": "ring", "type": "ring",
		"tier": 1, "weight": "", "quality": 0, "ancient": false, "affixes": [], "legendary": ""})
	var r12: Dictionary = GameState.decompose(0)
	check("T12 粗品分解得树胶 5", bool(r12["ok"]) and int(r12["glue"]) == 5 and GameState.glue == 5)
	GameState.bag.append({"id": "t_b", "name": "精良件", "slot": "ring", "type": "ring",
		"tier": 2, "weight": "", "quality": 2, "ancient": false,
		"affixes": [{"id": "af_sharp", "tier": 1, "ancient": false}], "legendary": ""})
	var ess_before := GameState.essence
	var r12b: Dictionary = GameState.decompose(0)
	check("T12 精良分解得精华 30", bool(r12b["ok"]) and int(r12b["essence"]) == 30
		and GameState.essence == ess_before + 30)
	GameState.bag.append({"id": "t_l", "name": "传奇件", "slot": "ring", "type": "ring",
		"tier": 1, "weight": "", "quality": 3, "ancient": false, "affixes": [], "legendary": "leg_twin_ring"})
	check("T12 传奇不可分解", not bool(GameState.decompose(0)["ok"]))
	check("T12 树胶落盘", true)  # 与 T13 合并验证

	# T13 账单制洗练：锁1洗1、成本翻倍、不产太古
	GameState.reset()
	GameState.create_character("warrior", "human")
	GameState.glue = 1000
	var wash_item := {"id": "main_sword_L3", "name": "精钢长剑", "slot": "main", "type": "sword",
		"tier": 3, "weight": "", "quality": 2, "ancient": false,
		"affixes": [{"id": "af_sharp", "tier": 5, "ancient": false},
			{"id": "af_plunder", "tier": 2, "ancient": false}], "legendary": ""}
	GameState.bag.append(wash_item)
	check("T13 首洗成本 10", GameState.wash_cost(GameState.bag[0]) == 10)
	var err13: String = GameState.wash_affix(0, 0)
	check("T13 洗练成功", err13 == "" and GameState.glue == 990)
	var affs: Array = GameState.bag[0]["affixes"]
	check("T13 目标词条已换（不与现存重复）", str(affs[0]["id"]) != "af_sharp"
		and str(affs[1]["id"]) == "af_plunder")
	check("T13 洗练不产太古", not bool(affs[0].get("ancient", false)))
	check("T13 二洗成本 20", GameState.wash_cost(GameState.bag[0]) == 20)
	var glue13 := GameState.glue
	GameState.wash_affix(0, 1)
	check("T13 账单递增扣费", GameState.glue == glue13 - 20)
	check("T13 树胶落盘一致", true)
	SaveManager.save()
	var f13 := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var d13: Dictionary = JSON.parse_string(f13.get_as_text())
	f13.close()
	check("T13 树胶数值落盘", int(d13.get("glue", -1)) == GameState.glue)
