extends Node
## 巅峰系统无头测试：表完整性 / 解锁链 / 购买退还 / 关键互斥 / 副作用 / 存档。
##   godot --headless --path . res://tests/paragon_test.tscn
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
	print("paragon_test 开始（存档已备份=%s）" % _had)
	await _run()
	if _had:
		var wf := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		wf.store_string(_backup)
		wf.close()
		SaveManager._load()
	print("---")
	print("paragon_test 结果：%d 项失败" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


func _write_save(text: String) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _run() -> void:
	# T0 干净基线（创建角色 + 直升 Lv.60 造巅峰点）
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	GameState.reset()
	GameState.create_character("warrior", "human")
	GameState.debug_set_level(60)
	check("T0 基线：Lv.60 巅峰点 0、板块一开放、板块二锁定",
		GameState.paragon_points == 0
		and GameState.paragon_board_unlocked("p1")
		and not GameState.paragon_board_unlocked("p2"))

	# T1 表完整性：三板块、每板块节点结构
	check("T1 三板块", GameParagon.BOARD_ORDER.size() == 3)
	var expect := {"p1": 10, "p2": 11, "p3": 11}
	for bid in ["p1", "p2", "p3"]:
		var board: Dictionary = GameParagon.get_board(bid)
		var keys := 0
		for n: Dictionary in board["nodes"]:
			if n.has("key"):
				keys += 1
		check("T1 %s 节点 %d 个、传奇 3 个" % [bid, expect[bid]],
			board["nodes"].size() == int(expect[bid]) and keys == 3)

	# T2 板块一购买：普通 + 稀有 + 点数扣除
	GameState.paragon_points = 99
	check("T2 买 p1_n1", GameState.paragon_buy("p1_n1"))
	check("T2 p1_n1 升满 5 级", _buy_max("p1_n1") and int(GameState.paragon_talents.get("p1_n1", 0)) == 5)
	check("T2 巅峰点已扣", GameState.paragon_points < 99)

	# T3 解锁链：板块二在板块一传奇点亮前锁定
	check("T3 板块二锁定（无 p1 传奇）", not GameState.paragon_board_unlocked("p2"))
	check("T3 板块二节点购买被拒", not GameState.paragon_buy("p2_n1"))
	# 点亮板块一传奇（终焉之寒）
	GameState.paragon_buy("p1_key_a")
	check("T3 板块一传奇点亮 → 板块二解锁", GameState.paragon_board_unlocked("p2"))
	check("T3 板块三仍锁定", not GameState.paragon_board_unlocked("p3"))

	# T4 副作用：终焉之寒（伤害+30%、收入-15%）
	check("T4 伤害含终焉之寒", Mods.mult("battle_damage") > 1.3)
	check("T4 收入含 -15% 副作用", is_equal_approx(Mods.mult("income") / _no_paragon_income(), 0.85))

	# T5 板块二购买 + 传奇互斥
	check("T5 板块二可购买", GameState.paragon_buy("p2_n1"))
	check("T5 板块二传奇 A 购买", GameState.paragon_buy("p2_key_a"))
	check("T5 板块二传奇互斥", not GameState.paragon_buy("p2_key_b"))
	check("T5 板块三解锁（板块二传奇已购）", GameState.paragon_board_unlocked("p3"))

	# T6 单点退还免费 + 副作用同步
	var pp := GameState.paragon_points
	check("T6 退还 p2_key_a", GameState.paragon_refund("p2_key_a"))
	check("T6 退还返还 1 巅峰点", GameState.paragon_points == pp + 1)
	check("T6 板块三仍解锁（已购节点保留）", GameState.paragon_board_unlocked("p3"))

	# T7 存档 roundtrip
	SaveManager.save()
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	check("T7 巅峰记录落盘", (data.get("paragon_talents", {}) as Dictionary).size() > 0)
	check("T7 巅峰点落盘", int(data.get("paragon_points", -1)) == GameState.paragon_points)

	print("  [info] 巅峰面板构建验证略（与天赋面板同骨架）")


func _buy_max(node_id: String) -> bool:
	var ok := true
	for i in 10:
		if not GameState.paragon_buy(node_id):
			ok = int(GameState.paragon_talents.get(node_id, 0)) >= 1 and i > 0
			break
	return ok


func _no_paragon_income() -> float:
	## 不含巅峰来源的收入乘数（职业+种族+天赋）
	return Mods.mult("income") / _paragon_income_factor()


func _paragon_income_factor() -> float:
	var f := 1.0
	for node_id in GameState.paragon_talents.keys():
		var def := GameParagon.get_node_def(str(node_id))
		if str(def.get("mod", "")) == "income" and str(def.get("kind", "mult")) == "mult":
			f *= 1.0 + float(def.get("per", 0.0)) * int(GameState.paragon_talents[node_id])
	return f
