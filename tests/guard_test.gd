extends Node
## 层守机制包无头测试：一人一套 / 先制 / 封印 / 单消盾 / 蓄力窗 / 狂暴墙 / 根性 / 普通怪直通。
##   godot --headless --path . res://tests/guard_test.tscn

var _fails := 0


func check(case_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS  " + case_name)
	else:
		_fails += 1
		print("FAIL  %s  %s" % [case_name, detail])


func _ready() -> void:
	await get_tree().process_frame
	print("guard_test 开始")
	_run()
	print("---")
	print("guard_test 结果：%d 项失败" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


func _run() -> void:
	# T0 普通怪：空包直通
	var plain := GuardKit.new("風狼")
	check("T0 普通怪无机制包", not plain.has_kit())
	check("T0 普通怪伤害直通", float(plain.move_modifiers(1, false)["mult"]) == 1.0
		and not bool(plain.move_modifiers(1, false)["sealed"])
		and not bool(plain.move_modifiers(1, false)["blocked"]))
	check("T0 普通怪无事件无根性", plain.after_move(0.1).is_empty() and not plain.on_lethal())

	# T1 守林古树：树皮硬化 3 步减伤 50%
	var gs := GuardKit.new("守林古树")
	check("T1 古树有机制包", gs.has_kit())
	check("T1 古树开场减伤 50%", is_equal_approx(float(gs.move_modifiers(3, false)["mult"]), 0.5))
	check("T1 古树无弱点封印", not bool(gs.move_modifiers(3, false)["sealed"]))
	gs.after_move(0.9)
	gs.after_move(0.9)
	check("T1 第 3 步仍在硬化", is_equal_approx(float(gs.move_modifiers(1, false)["mult"]), 0.5))
	gs.after_move(0.9)
	check("T1 第 4 步硬化结束", float(gs.move_modifiers(1, false)["mult"]) == 1.0)

	# T2 古树蓄力窗：50% 触发、3 步 ×2、只触发一次
	var e1 := gs.after_move(0.45)
	check("T2 蓄力窗开启事件", e1 == ["charge"])
	check("T2 窗口内受伤 ×2", is_equal_approx(float(gs.move_modifiers(1, false)["mult"]), 2.0))
	gs.after_move(0.4)
	gs.after_move(0.3)
	check("T2 窗口共 3 步", gs.charge_left == 1
		and is_equal_approx(float(gs.move_modifiers(1, false)["mult"]), 2.0))
	gs.after_move(0.2)
	check("T2 窗口结束后恢复", float(gs.move_modifiers(1, false)["mult"]) == 1.0)
	check("T2 古树无狂暴", gs.after_move(0.1).is_empty() and not gs.raged)

	# T3 古树根性：仅一次
	check("T3 首次致死触发根性", gs.on_lethal())
	check("T3 第二次致死不触发", not gs.on_lethal())

	# T4 镇风桩：弱点封印 3 步
	var zf := GuardKit.new("镇风桩")
	check("T4 封印期 is_sealed", zf.is_sealed())
	check("T4 封印期不减伤", float(zf.move_modifiers(3, false)["mult"]) == 1.0)
	zf.after_move(0.9)
	zf.after_move(0.9)
	check("T4 第 3 步仍在封印", zf.is_sealed())
	zf.after_move(0.9)
	check("T4 第 4 步封印结束", not zf.is_sealed())

	# T5 镇风桩连击盾：单消无效 / 2 连有效 / 技能穿透
	check("T5 单消被盾挡", bool(zf.move_modifiers(1, false)["blocked"]))
	check("T5 双连不被挡", not bool(zf.move_modifiers(2, false)["blocked"]))
	check("T5 主动技能穿透", not bool(zf.move_modifiers(1, true)["blocked"]))

	# T6 镇风桩蓄力窗 → 狂暴墙的先后次序
	var seq: Array = []
	seq += zf.after_move(0.4)          # 蓄力开启
	seq += zf.after_move(0.3)          # 窗口 2
	seq += zf.after_move(0.2)          # 窗口 1（此时不狂暴）
	seq += zf.after_move(0.2)          # 窗口结束
	check("T6 先蓄力后狂暴（窗口期不狂暴）", seq == ["charge"])
	check("T6 狂暴在窗口结束后触发", zf.after_move(0.2) == ["rage"] and zf.raged)
	check("T6 狂暴减伤 40%", is_equal_approx(float(zf.move_modifiers(1, false)["mult"]), 0.6))

	# T7 镇风桩根性 + HUD 标签
	var zf2 := GuardKit.new("镇风桩")
	check("T7 镇风桩根性一次", zf2.on_lethal() and not zf2.on_lethal())
	check("T7 状态标签含盾与封印", "盾" in zf2.state_tag() and "封印" in zf2.state_tag())
	zf2.after_move(0.3)
	check("T7 蓄力态标签含蓄力", "蓄力" in zf2.state_tag())

	# T8 未知怪物名：安全空包
	check("T8 未知名安全", not GuardKit.new("不存在的怪").has_kit())
