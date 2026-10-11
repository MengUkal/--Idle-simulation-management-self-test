extends Node
## 离线收益无头测试：门槛 / 上限 / 效率 / 入账 / 报告消费 / 存档 roundtrip。
##   godot --headless --path . res://tests/offline_test.tscn
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
	print("offline_test 开始（存档已备份=%s）" % _had)
	await _run()
	if _had:
		var wf := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		wf.store_string(_backup)
		wf.close()
		SaveManager._load()
	print("---")
	print("offline_test 结果：%d 项失败" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


func _write_save(text: String) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _baseline() -> float:
	## 干净基线：战士/人类 Lv.20，钱包清零；返回挂机收入（吉/秒）
	GameState.reset()
	GameState.create_character("warrior", "human")
	GameState.debug_set_level(20)
	GameState.money = 0.0
	return GameState.income_per_sec()


func _run() -> void:
	var ips := _baseline()
	check("T0 基线：Lv.20 挂机收入 > 0", ips > 0.0)

	# T1 从未存过档（last_seen=0）：不结算
	GameState.last_seen = 0.0
	check("T1 last_seen=0 → 不结算", GameState.settle_offline().is_empty())

	# T2 离开不足 5 分钟：不结算（防切屏误触）
	GameState.last_seen = Time.get_unix_time_from_system() - 240.0
	check("T2 离开4分钟 → 不结算", GameState.settle_offline().is_empty())

	# T3 离开 9.5 小时：按 8 小时上限 × 60% 结算并入账
	GameState.last_seen = Time.get_unix_time_from_system() - 9.5 * 3600.0
	var rep := GameState.settle_offline()
	var expect_gold := int(floor(ips * float(GameState.OFFLINE_CAP_SEC) * GameState.OFFLINE_RATE))
	check("T3 报告非空", not rep.is_empty())
	check("T3 计入时长=8小时上限", int(rep.get("credited_sec", -1)) == GameState.OFFLINE_CAP_SEC)
	check("T3 离开时长≈9.5小时", absf(float(rep.get("seconds", 0)) - 34200.0) < 5.0)
	check("T3 金额=收入×28800×0.6", int(rep.get("gold", -1)) == expect_gold)
	check("T3 已入账（钱包增加）", is_equal_approx(GameState.money, float(expect_gold)))
	check("T3 速率=在线×0.6", is_equal_approx(float(rep.get("rate", 0.0)), ips * 0.6))

	# T4 取走报告后清空（避免重复弹）
	var taken := GameState.take_offline_report()
	check("T4 take 取到报告且清空", not taken.is_empty() and GameState.pending_offline.is_empty())

	# T5 存档 roundtrip：老 last_seen 读档即自动结算
	_baseline()
	var payload := {
		"version": 5, "money": 0, "level": 20, "floor": 1,
		"class_id": "warrior", "race_id": "human",
		"last_seen": Time.get_unix_time_from_system() - 3600.0,
	}
	_write_save(JSON.stringify(payload))
	SaveManager._load()
	var expect2 := int(floor(GameState.income_per_sec() * 3600.0 * GameState.OFFLINE_RATE))
	check("T5 读档触发结算", not GameState.pending_offline.is_empty())
	check("T5 1小时×60% 金额正确", int(GameState.pending_offline.get("gold", -1)) == expect2)
	check("T5 入账正确", is_equal_approx(GameState.money, float(expect2)))

	# T6 save() 写入 last_seen（供下次离线结算）
	SaveManager.save()
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	check("T6 last_seen 落盘",
		float(data.get("last_seen", 0.0)) > Time.get_unix_time_from_system() - 30.0)

	# T7 reset 清理
	GameState.reset()
	check("T7 reset 清 last_seen/pending",
		GameState.last_seen == 0.0 and GameState.pending_offline.is_empty())
