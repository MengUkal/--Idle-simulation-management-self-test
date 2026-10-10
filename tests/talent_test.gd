extends Node
## 天赋树无头测试：表完整性 / 购买校验（层圈/上限/互斥）/ 退还 / 洗点 / 点数分流 / 面板。
##   godot --headless --path . res://tests/talent_test.tscn
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
	print("talent_test 开始（存档已备份=%s）" % _had)
	await _run()
	if _had:
		var wf := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		wf.store_string(_backup)
		wf.close()
		SaveManager._load()
	print("---")
	print("talent_test 结果：%d 项失败" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


func _run() -> void:
	# T0 干净基线：删除存档 + 创建战士
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	GameState.reset()
	check("T0 创建战士", GameState.create_character("warrior", "human"))

	# T1 树完整性
	var tree: Dictionary = GameTalents.get_tree_for("warrior")
	var nodes: Array = tree.get("nodes", [])
	check("T1 战士树节点 12 个（7 常规 + 3 关键 + 2 副作用）", nodes.size() == 12)
	var key_count := 0
	for n: Dictionary in nodes:
		if n.has("key"):
			key_count += 1
	check("T1 关键天赋 3 个（三选一）", key_count == 3)

	# T2 未达层圈门槛：ring 2 的 war_4 需投入 3 点
	check("T2 层圈门槛拦截（0 点买 ring2）", not GameState.talent_buy("war_4"))

	# T3 买满 war_1（rank5）：点数与 Mods 同步
	GameState.skill_points = 99
	for i in 5:
		check("T3 war_1 第 %d 级购买" % (i + 1), GameState.talent_buy("war_1"))
	check("T3 war_1 满级后再买被拒", not GameState.talent_buy("war_1"))
	check("T3 Mods 伤害 = 职业1.15 × 天赋1.15", is_equal_approx(Mods.mult("battle_damage"), 1.15 * 1.15))

	# T4 层圈解锁：已投入 5 点 ≥ 3 → ring2 可买
	check("T4 投入 5 点后 ring2 解锁", GameState.talent_buy("war_4"))

	# T5 确定性凑点：先退还 T4 的 war_4（归零），再按固定序列买满（war_2×5+war_3×5+war_4×5 = +15，合计 5+15 = 20，另补 war_5×5 = 25）
	GameState.talent_refund("war_4")
	var plan := ["war_2", "war_2", "war_2", "war_2", "war_2",
		"war_3", "war_3", "war_3", "war_3", "war_3",
		"war_4", "war_4", "war_4", "war_4", "war_4",
		"war_5", "war_5", "war_5", "war_5", "war_5"]
	var all_ok := true
	for nid in plan:
		if not GameState.talent_buy(nid):
			all_ok = false
			print("    [debug] 购买失败：%s ｜ 已投入 %d ｜ 点数 %d" % [
				nid, GameState.talent_invested(), GameState.skill_points])
	check("T5 凑点序列全部购买成功", all_ok)
	var invested_before := GameState.talent_invested()
	check("T5 投入达 25（关键解锁条件）", invested_before >= 25, "实际 %d" % invested_before)
	check("T5 购买关键 A（狂战之魂）", GameState.talent_buy("war_key_a"))
	check("T5 关键互斥：买关键 B 被拒", not GameState.talent_buy("war_key_b"))
	check("T5 副作用生效：收入 ×0.9", is_equal_approx(Mods.mult("income"), 0.9))
	check("T5 退还关键 A → 副作用同步消失", GameState.talent_refund("war_key_a")
		and is_equal_approx(Mods.mult("income"), 1.0))
	check("T5 退还后可换关键 C", GameState.talent_buy("war_key_c"))

	# T6 单点退还免费
	var sp := GameState.skill_points
	check("T6 退还 war_key_c 返还 1 点", GameState.talent_refund("war_key_c") and GameState.skill_points == sp + 1)

	# T7 整树洗点收吉尔
	var invested := GameState.talent_invested()
	var cost := GameState.talent_respec_cost()
	var sp_before := GameState.skill_points
	var money_before := GameState.money
	GameState.money += cost  # 确保买得起
	check("T7 洗点前有钱可洗", GameState.talent_respec_all())
	check("T7 洗点后天赋清空、点数返还、吉尔按价扣除",
		GameState.talents.is_empty() and GameState.skill_points == sp_before + invested
		and is_equal_approx(GameState.money, money_before))

	# T8 点数分流：Lv.60 起进巅峰点
	GameState.debug_set_level(59)
	GameState.add_money(1e12)
	GameState.upgrade_level()
	check("T8 Lv.59→60 升级进巅峰点", GameState.paragon_points == 1 and GameState.skill_points >= 0)

	# T9 面板构建
	var panel := TalentsPanel.new()
	add_child(panel)
	await get_tree().process_frame
	check("T9 天赋面板构建无异常", panel.get_child_count() > 0)
	panel.queue_free()
	await get_tree().process_frame
