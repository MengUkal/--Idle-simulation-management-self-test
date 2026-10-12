extends Node
## 伙伴系统无头测试：表完整性 / 蛋掉落 / 孵化图鉴 / 看板位 ×2 / Mods 来源 / 存档。
##   godot --headless --path . res://tests/pets_test.tscn
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
	print("pets_test 开始（存档已备份=%s）" % _had)
	await _run()
	if _had:
		var wf := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		wf.store_string(_backup)
		wf.close()
		SaveManager._load()
	print("---")
	print("pets_test 结果：%d 项失败" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


func _run() -> void:
	# T0 表完整性：28 只全注册、键全部合法
	check("T0 伙伴 42 只（五层35+六层7）", GamePets.PETS.size() == 42)
	var keys_ok := true
	for pname in GamePets.PETS.keys():
		var d: Dictionary = GamePets.PETS[pname]
		if str(d["kind"]) == "mult" and not (d["key"] in Mods.MULT_KEYS):
			keys_ok = false
		if str(d["kind"]) == "add" and not (d["key"] in Mods.ADD_KEYS):
			keys_ok = false
	check("T0 被动键全部合法", keys_ok)

	# T1 蛋掉落：精英首杀必掉本怪蛋
	GameState.reset()
	GameState.create_character("warrior", "human")
	GameState.debug_set_level(30)
	var egg: Dictionary = GameState.egg_drop({"name": "風羽隼"}, true, true)
	check("T1 精英首杀必掉蛋", not egg.is_empty() and str(egg["monster"]) == "風羽隼")
	var got_common := 0
	for i in 100:
		if not GameState.egg_drop({"name": "树精史莱姆"}, false, false).is_empty():
			got_common += 1
	check("T1 常驻掉率 ~2%（100 次掉 %d）", got_common > 0 and got_common < 15)
	GameState.reset()
	GameState.create_character("warrior", "human")
	check("T1 未注册怪不掉蛋", GameState.egg_drop({"name": "不存在的怪"}, true, true).is_empty())

	# T2 孵化：首点/重复计数/品质取高
	check("T2 首蛋点亮图鉴", GameState.hatch_egg("風羽隼", 1))
	check("T2 计数与品质", int(GameState.pets["風羽隼"]["count"]) == 1
		and int(GameState.pets["風羽隼"]["quality"]) == 1)
	check("T2 重复蛋计数", not GameState.hatch_egg("風羽隼", 0)
		and int(GameState.pets["風羽隼"]["count"]) == 2
		and int(GameState.pets["風羽隼"]["quality"]) == 1)
	check("T2 高品质升档", not GameState.hatch_egg("風羽隼", 3)
		and int(GameState.pets["風羽隼"]["quality"]) == 3)

	# T3 被动生效 + 看板 ×2
	var base_bd := Mods.mult("battle_damage")
	var base_steps := Mods.add("steps")
	GameState.set_pet_board("風羽隼")
	check("T3 看板位设置", GameState.pet_board == "風羽隼")
	# 風羽隼 = steps add ×1 ×品质8 ×看板2 = +16
	check("T3 看板翻倍（常驻×8 → 看板×16，差值 +8）",
		is_equal_approx(Mods.add("steps") - base_steps, 8.0))
	# 品质倍率换一只（岩甲龟 dr add ×1 常驻）
	GameState.hatch_egg("岩甲龟", 0)
	check("T3 常驻被动生效（岩甲龟 dr +1%）",
		is_equal_approx(Mods.add("dr") - 0.0, 0.01))

	# T4 未收录怪不产生被动
	var before := Mods.mult("income")
	GameState.hatch_egg("不存在的怪", 3)
	check("T4 未注册怪无被动", is_equal_approx(Mods.mult("income"), before))

	# T5 存档 roundtrip
	SaveManager.save()
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	check("T5 图鉴落盘", (data.get("pets", {}) as Dictionary).size() == 2)
	check("T5 看板落盘", str(data.get("pet_board", "")) == "風羽隼")
	check("T5 树胶落盘", int(data.get("glue", -1)) == GameState.glue)
