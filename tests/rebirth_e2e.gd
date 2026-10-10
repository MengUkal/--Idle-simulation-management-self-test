extends Node
## M4 重生系统 E2E 验收（真实 autoload + 主界面实例 + 存档备份恢复）。
##   无头断言：godot --headless --path . res://tests/rebirth_e2e.tscn
##   带渲染截图：godot --path . res://tests/rebirth_e2e.tscn -- --capture-e2e
## 存档安全：开跑前备份 user://save.json，结束时恢复——绝不碰玩家真档。

const CAPTURE := "--capture-e2e"

var _fails := 0
var _save_backup := ""
var _had_save := false


func check(case_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS  " + case_name)
	else:
		_fails += 1
		print("FAIL  %s  %s" % [case_name, detail])


func _ready() -> void:
	await get_tree().process_frame
	_backup_save()
	print("E2E 开始（存档已备份）")
	var main: Control = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await _run(main)
	_restore_save()
	print("---")
	print("E2E 结果：%d 项失败" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


func _backup_save() -> void:
	_had_save = FileAccess.file_exists(SaveManager.SAVE_PATH)
	if _had_save:
		var f := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.READ)
		_save_backup = f.get_as_text()
		f.close()


func _restore_save() -> void:
	if _had_save:
		var f := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_save_backup)
		f.close()
	else:
		SaveManager.delete_save()
	print("E2E 结束（存档已恢复）")


func _snap(fname: String) -> void:
	if not OS.get_cmdline_user_args().has(CAPTURE):
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://tests/cap_" + fname)
	print("截图：tests/cap_" + fname)


func _run(main: Control) -> void:
	# ---- T0 干净基线 ----
	SaveManager.delete_save()
	GameState.reset()
	await get_tree().process_frame
	check("T0 基线：全新开局 Lv.1 果实 0", GameState.level == 1 and GameState.fruits == 0)

	# ---- T1 触墙引导（Lv.38 首次弹，只弹一次）----
	GameState.debug_set_level(37)
	await get_tree().process_frame
	check("T1 Lv.37 未触发引导", GameState.rebirth_guide_shown == false)
	GameState.debug_set_level(38)
	await get_tree().process_frame
	check("T1 Lv.38 触墙引导置位", GameState.rebirth_guide_shown == true)
	GameState.debug_set_level(39)
	check("T1 引导只置位一次（幂等）", GameState.rebirth_guide_shown == true)

	# ---- T2 门槛判定 ----
	check("T2 Lv.38 重生未就绪（门槛 40）", GameState.rebirth_ready() == false)
	var btn: Button = main.get_node("%RebirthButton")
	check("T2 主界面重生按钮锁定", btn != null and btn.disabled)
	await _snap("e2e_locked_lv38.png")
	GameState.debug_set_level(40)
	check("T2 Lv.40 重生就绪", GameState.rebirth_ready() == true)
	check("T2 按钮解锁且显示可得果实", not btn.disabled and "果实" in btn.text)

	# ---- T3 重生前状态准备 ----
	GameState.add_money(1000.0)
	GameState.debug_add_line("atk", 5)
	GameState.debug_add_line("income", 3)
	check("T3 行情价格就绪", Market.prices.size() == 3)
	var bought := GameState.buy_stock(0, 10)
	check("T3 买入火晶石 10 股", bought)
	var holdings_before: Array = GameState.holdings.duplicate()

	# ---- T4 重生确认弹窗（UI）----
	main._on_rebirth_pressed()
	var confirm: Control = main.get_node("%RebirthConfirm")
	check("T4 确认弹窗弹出且含得失说明", confirm.visible and "果实" in main.get_node("%RebirthInfo").text)
	await _snap("e2e_confirm_dialog.png")
	main._on_rebirth_cancelled()

	# ---- T5 do_rebirth 结算 ----
	var gained := GameState.do_rebirth()
	check("T5 重生果实 = 5（Lv.40）", gained == 5)
	check("T5 等级归 1 / 吉尔清零 / 训练线清零",
		GameState.level == 1 and GameState.money == 0.0 and GameState.atk_line == 0 and GameState.income_line == 0)
	check("T5 果实累计 5 / 轮数 1 / 回第一层",
		GameState.fruits == 5 and GameState.rebirth_count == 1 and GameState.floor_index == 1)
	check("T5 交易所持仓保留", GameState.holdings == holdings_before)
	check("T5 下一轮门槛 = 45", GameState.rebirth_threshold() == 45)
	await get_tree().process_frame
	check("T5 主界面果实计数刷新（×5）", "5" in main.get_node("%FruitsLabel").text)

	# ---- T6 加成生效 ----
	check("T6 收入乘果实加成 ×1.25",
		is_equal_approx(GameState.income_per_sec(), Balance.income_per_sec(1) * Balance.income_fruit_mult(5)))
	var tcm: float = Balance.train_cost_mult(GameState.fruits, GameState.rebirth_count)
	check("T6 训练费用乘 0.98^5×0.95", is_equal_approx(tcm, pow(0.98, 5.0) * 0.95))
	var line_cost := int(ceil(Balance.train_cost(0) * tcm))
	check("T6 主界面训练按钮显示折后价", ("%d 精华" % line_cost) in main.get_node("%LineAtk").text)

	# ---- T7 存档 v4 roundtrip ----
	GameState.debug_set_level(45)
	GameState.add_money(55.5)
	SaveManager.save()
	var f := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.READ)
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	var saved: Dictionary = data if typeof(data) == TYPE_DICTIONARY else {}
	check("T7 存档 version = 4", int(saved.get("version", 0)) == 4)
	check("T7 果实/轮数/引导标记落盘",
		int(saved.get("fruits", -1)) == 5 and int(saved.get("rebirth_count", -1)) == 1
		and bool(saved.get("rebirth_guide_shown", false)))
	check("T7 持仓字段保留", (saved.get("holdings", []) as Array).size() == 3)

	# ---- T8 二轮重生 ----
	check("T8 Lv.45 二轮就绪", GameState.rebirth_ready() == true)
	var g2 := GameState.do_rebirth()
	check("T8 二轮果实 = 10（Lv.45）/ 累计 15", g2 == 10 and GameState.fruits == 15)
	check("T8 三轮门槛 = 50", GameState.rebirth_threshold() == 50)
	check("T8 轮数 = 2 / 训练衰减加深",
		GameState.rebirth_count == 2
		and is_equal_approx(Balance.train_cost_mult(0, 2), pow(0.95, 2.0)))
	await get_tree().process_frame
	await _snap("e2e_after_rebirth.png")
