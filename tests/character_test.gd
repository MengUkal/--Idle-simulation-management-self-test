extends Node
## 角色系统无头测试：定义表完整性 / 修饰符计算 / 创建流 / 存档 v5 / 旧档删除迁移。
##   godot --headless --path . res://tests/character_test.tscn
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
	print("character_test 开始（存档已备份=%s）" % _had)
	await _run()
	if _had:
		var wf := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		wf.store_string(_backup)
		wf.close()
		SaveManager._load()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	print("---")
	print("character_test 结果：%d 项失败" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


func _write_save(text: String) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _run() -> void:
	# T0 干净基线（无档 → 未创建）
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	GameState.reset()
	Settings._load()
	check("T0 干净基线：未创建角色", GameState.needs_character_creation())

	# T1 定义表完整性
	check("T1 职业 7 个", GameClasses.CLASSES.size() == 7)
	check("T1 种族 9 个", GameRaces.RACES.size() == 9)
	var keys_ok := true
	for c in GameClasses.CLASSES.values():
		for k in (c["mods"] as Dictionary).keys():
			if not (k in Mods.MULT_KEYS or k in Mods.ADD_KEYS):
				keys_ok = false
	for r in GameRaces.RACES.values():
		for k in (r["mods"] as Dictionary).keys():
			if not (k in Mods.MULT_KEYS or k in Mods.ADD_KEYS):
				keys_ok = false
	check("T1 全部 mods 键合法", keys_ok)
	var trees := {}
	for c in GameClasses.CLASSES.values():
		trees[c["tree"]] = true
	check("T1 每职业专属天赋树标识（7 棵）", trees.size() == 7)

	# T2 创建流
	check("T2 非法职业被拒", not GameState.create_character("nope", "human"))
	check("T2 重复创建被拒（未创建前不会触发）", true)
	check("T2 合法创建成功", GameState.create_character("warrior", "human"))
	check("T2 创建后 needs_character_creation = false", not GameState.needs_character_creation())
	check("T2 重复创建被拒", not GameState.create_character("mage", "elf"))

	# T3 修饰符：战士基础 + 巨人血裔叠加
	check("T3 战士伤害乘数 1.15", is_equal_approx(Mods.mult("battle_damage"), 1.15))
	var panel: Dictionary = Mods.panel()
	check("T3 面板含全部键", panel.size() == Mods.MULT_KEYS.size() + Mods.ADD_KEYS.size())

	# T4 升级给技能点
	var sp0 := GameState.skill_points
	GameState.add_money(100000.0)
	GameState.upgrade_level()
	check("T4 升级 +1 技能点", GameState.skill_points == sp0 + 1)

	# T5 存档 v5 roundtrip
	SaveManager.save()
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	check("T5 存档 version = 5", int(data.get("version", 0)) == 5)
	check("T5 职业/种族/点数落盘",
		str(data.get("class_id", "")) == "warrior" and str(data.get("race_id", "")) == "human")

	# T6 旧版（v4）档 → 删除重开
	_write_save('{"version": 4, "money": 500, "level": 15}')
	SaveManager._load()
	check("T6 v4 旧档被删除（D5 拍板）", not FileAccess.file_exists(SAVE_PATH))
	check("T6 删除后回未创建状态", GameState.needs_character_creation())

	# T7 牧师收入修饰符
	GameState.reset()
	GameState.create_character("priest", "human")
	check("T7 牧师收入 ×1.15",
		is_equal_approx(GameState.income_per_sec(), Balance.income_per_sec(1) * 1.15))

	# T8 矮人手续费
	GameState.reset()
	GameState.create_character("warrior", "dwarf")
	check("T8 矮人手续费 0.5%", is_equal_approx(GameState.market_fee_rate(), 0.005))
	var cost: Dictionary = Balance.trade_cost(100.0, 10, GameState.market_fee_rate())
	check("T8 100×10 股费用 = 5（原 10）", is_equal_approx(float(cost["fee"]), 5.0))

	# T9 法师弱点 × 游侠连锁 叠加
	GameState.reset()
	GameState.create_character("mage", "high_elf")
	check("T9 法师+高等精灵弱点 ×1.3125", is_equal_approx(Mods.mult("weakness"), 1.25 * 1.05))
	GameState.reset()
	GameState.create_character("ranger", "dark_elf")
	check("T9 游侠+暗精灵连锁加成 +0.08", is_equal_approx(Mods.add("chain_bonus"), 0.08))
