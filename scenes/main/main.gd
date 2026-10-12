extends Control
## M1 主界面：挂机核心循环。
## 场景化迁移完成：节点结构见 main.tscn（编辑器内可拖动调整），
## 脚本通过 %唯一名 绑定节点——重命名/移动节点不会破坏引用，删除才会。

const LINE_NAMES := {"atk": "攻击训练", "bounty": "赏金训练", "income": "收入训练", "body": "体魄训练"}

var _line_buttons := {}
var _toast_tween: Tween

@onready var _money_label: Label = %MoneyLabel
@onready var _income_label: Label = %IncomeLabel
@onready var _countdown_label: Label = %CountdownLabel
@onready var _floor_name_label: Label = %FloorNameLabel
@onready var _upgrade_button: Button = %UpgradeButton
@onready var _floor2_button: Button = %Floor2Button
@onready var _adventure_button: Button = %AdventureButton
@onready var _market_button: Button = %MarketButton
@onready var _essence_label: Label = %EssenceLabel
@onready var _line_atk: Button = %LineAtk
@onready var _line_bounty: Button = %LineBounty
@onready var _line_income: Button = %LineIncome
@onready var _save_label: Label = %SaveLabel
@onready var _toast: Label = %Toast
@onready var _reset_button: Button = %ResetButton
@onready var _reset_confirm: Control = %ResetConfirm
@onready var _reset_cancel_btn: Button = %ResetCancelBtn
@onready var _reset_apply_btn: Button = %ResetApplyBtn
@onready var _fruits_label: Label = %FruitsLabel
@onready var _rebirth_button: Button = %RebirthButton
@onready var _rebirth_confirm: Control = %RebirthConfirm
@onready var _rebirth_info: Label = %RebirthInfo
@onready var _rebirth_cancel_btn: Button = %RebirthCancelBtn
@onready var _rebirth_apply_btn: Button = %RebirthApplyBtn
@onready var _settings_button: Button = %SettingsButton
@onready var _talents_button: Button = %TalentsButton
@onready var _paragon_button: Button = %ParagonButton
@onready var _bg_art: TextureRect = %BgArt


func _ready() -> void:
	if GameState.needs_character_creation() and get_tree().current_scene == self:
		# 角色系统：未选职业/种族（新档或旧档被删）→ 先去创建角色。
		# 仅当 main 是真正的当前场景时才跳转（被测试/预览实例化为子节点时不触发）。
		get_tree().change_scene_to_file.call_deferred("res://scenes/character/character_create.tscn")
		return
	_init_line_buttons()
	_connect_signals()
	_refresh_all()
	# 离线收益回归弹窗（金额已在读档时结算入账，这里只负责展示）
	if not GameState.pending_offline.is_empty():
		add_child(OfflinePanel.new())
	# BGM 按层五选一（bgm_floor5 已由音频会话产出，2026-10-12）
	Sfx.bgm(["bgm_floor1", "bgm_floor2", "bgm_floor3", "bgm_floor4", "bgm_floor5"][clampi(GameState.floor_index, 1, 5) - 1])
	if OS.is_debug_build():
		add_child(DevPanel.new())  # 开发修改器（F1 开关），release 导出自动不存在
	# 系统入口三连（E1.5/P-b）：挂主界面根节点、底部左侧空地带与「重置存档」并排
	# （不进设置所在容器——容器布局会重排覆盖 position，压到天赋/巅峰文字）
	var entry_defs := [
		["兽栏", "树根兽栏：伙伴图鉴与看板位", func() -> void:
			Sfx.play("ui_open")
			add_child(KennelPanel.new())],
		["属性", "角色属性总览（四组修饰符 + 来源明细）", func() -> void:
			Sfx.play("ui_open")
			add_child(StatsPanel.new())],
		["背包", "打开背包与装备（30 格背包 / 10 槽穿戴）", func() -> void:
			Sfx.play("ui_open")
			add_child(EquipmentPanel.new())],
		["彩虹桥", "终局挑战：彩虹桥的守门者在等你（击败难5星望者后解锁）", func() -> void:
			Sfx.play("floor_switch")
			GameState.final_battle_pending = true
			get_tree().change_scene_to_file("res://scenes/battle/battle.tscn")],
	]
	for i in entry_defs.size():
		if str(entry_defs[i][0]) == "彩虹桥":
			pass
	for i in entry_defs.size():
		var def: Array = entry_defs[i]
		var btn := Button.new()
		btn.text = str(def[0])
		btn.tooltip_text = str(def[1])
		btn.position = Vector2(176.0 + 132.0 * i, 1010.0)
		btn.custom_minimum_size = Vector2(118, 40)
		btn.focus_mode = Control.FOCUS_NONE
		btn.visible = GameState.final_bridge_unlocked if str(def[0]) == "彩虹桥" else true
		btn.pressed.connect(def[2])
		add_child(btn)
	# 难度切换按钮（暗黑4式难1~5，2026-10-12 拍板）：循环 1~已解锁上限，切难度回一层爬升
	var diff_btn := Button.new()
	diff_btn.text = "难度 %d" % GameState.difficulty
	diff_btn.custom_minimum_size = Vector2(118, 40)
	diff_btn.focus_mode = Control.FOCUS_NONE
	diff_btn.pressed.connect(_on_difficulty_pressed)
	add_child(diff_btn)
	_diff_button = diff_btn
	diff_btn.tooltip_text = "切换难度（通关上一难度六层解锁下一难度；切难度回到该难度一层）"
	diff_btn.position = Vector2(176.0 + 132.0 * entry_defs.size(), 1010.0)
	diff_btn.custom_minimum_size = Vector2(118, 40)
	diff_btn.focus_mode = Control.FOCUS_NONE
	diff_btn.pressed.connect(_on_difficulty_pressed)
	add_child(diff_btn)
	_diff_button = diff_btn
	# 新手引导 A：首次进入主界面三连（引导链清单实装）
	if GameState.tip_once("main_first"):
		GameState.pending_tips.append("欢迎来到世界树。吉尔会自己长——挂机收入，自动到账。")
		GameState.pending_tips.append("变强只有一件事：攒吉尔，向树献金，升级。")
		GameState.pending_tips.append("准备好了就点「出发冒险」。消除就是攻击。")
	# 右下角重排（2026-10-12 拍板）：设置/天赋/巅峰移至右上空区，训练列让出底部；
	# 「重置存档」与标题「新的开始」功能重合，按钮移除（tscn 节点隐藏保留）。
	_reset_button.visible = false
	_reset_confirm.visible = false
	for c: Control in [_settings_button, _talents_button, _paragon_button]:
		c.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_settings_button.position = Vector2(1752.0, 200.0)
	_paragon_button.position = Vector2(1408.0, 204.0)
	_talents_button.position = Vector2(1408.0, 244.0)
	if OS.get_cmdline_user_args().has("--capture-main"):
		_debug_capture.call_deferred()


var _tip_timer := 0.0
var _diff_button: Button


func _on_difficulty_pressed() -> void:
	## 难度循环切换（暗黑4式）：切回该难度一层重新爬升
	Sfx.play("floor_switch")
	GameState.cycle_difficulty()
	_diff_button.text = "难度 %d" % GameState.difficulty
	_refresh_all()
	_show_toast("已切换到难度 %d（等级门槛提升，怪物与赏金指数增长）" % GameState.difficulty)


func _notification(what: int) -> void:
	## 手机版（2026-10-12）：切后台立即存档；主界面返回键 = 退出（自动保存触发）
	if what == NOTIFICATION_APPLICATION_PAUSED:
		SaveManager.save()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().quit()


func _process(delta: float) -> void:
	## 新手提示队列：每 4.5 秒弹一条（引导链清单实装）
	if GameState.pending_tips.is_empty():
		return
	_tip_timer += delta
	if _tip_timer >= 4.5:
		_tip_timer = 0.0
		_show_toast(GameState.pending_tips.pop_front())


## 【诊断工具】截屏主界面（-- --capture-main 触发，输出 tests/cap_main.png）
func _debug_capture() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("F:/放置测试/挂机放置增量rpg/tests/cap_main.png")
	print("[capture] cap_main saved")
	get_tree().quit()


func _init_line_buttons() -> void:
	_line_buttons = {"atk": _line_atk, "bounty": _line_bounty, "income": _line_income}
	# 体魄训练线（第四线，精华；代码生成按钮——生命上限 +8%/级）
	var body_btn := Button.new()
	body_btn.text = "体魄训练"
	_line_income.add_sibling(body_btn)
	body_btn.position = _line_income.position + Vector2(0, 52)
	body_btn.pressed.connect(_on_line_pressed.bind("body"))
	_line_buttons["body"] = body_btn
	# 技能强化（第五条训练位，精华；主动技能主数值升级，10 级封顶）
	var skill_btn := Button.new()
	skill_btn.text = "技能强化"
	_line_buttons["body"].add_sibling(skill_btn)
	skill_btn.position = _line_buttons["body"].position + Vector2(0, 52)
	skill_btn.pressed.connect(_on_skill_upgrade_pressed)
	_line_buttons["skill"] = skill_btn


func _connect_signals() -> void:
	EventBus.money_changed.connect(_on_money_changed)
	EventBus.income_changed.connect(_on_income_changed)
	EventBus.level_changed.connect(_on_level_changed)
	EventBus.money_not_enough.connect(_on_money_not_enough)
	EventBus.floor_changed.connect(_on_floor_changed)
	EventBus.floor_unlocked.connect(_on_floor_unlocked)
	EventBus.save_completed.connect(_on_save_completed)
	EventBus.essence_changed.connect(_on_essence_changed)
	EventBus.line_changed.connect(_on_line_changed)
	EventBus.rebirth_performed.connect(_on_rebirth_performed)
	EventBus.floor3_card_gained.connect(_refresh_buttons)
	EventBus.floor4_card_gained.connect(_refresh_buttons)
	EventBus.floor5_card_gained.connect(_refresh_buttons)
	_upgrade_button.pressed.connect(_on_upgrade_pressed)
	_floor2_button.pressed.connect(_on_floor2_pressed)
	_adventure_button.pressed.connect(_on_adventure_pressed)
	_market_button.pressed.connect(_on_market_pressed)
	_rebirth_button.pressed.connect(_on_rebirth_pressed)
	_rebirth_cancel_btn.pressed.connect(_on_rebirth_cancelled)
	_rebirth_apply_btn.pressed.connect(_on_rebirth_confirmed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_talents_button.pressed.connect(_on_talents_pressed)
	_paragon_button.pressed.connect(_on_paragon_pressed)
	_line_atk.pressed.connect(_on_line_pressed.bind("atk"))
	_line_bounty.pressed.connect(_on_line_pressed.bind("bounty"))
	_line_income.pressed.connect(_on_line_pressed.bind("income"))


func _on_settings_pressed() -> void:
	SettingsOverlay.open()


# ---------- 信号处理 ----------

func _on_money_changed(total: float) -> void:
	_money_label.text = "%s %s" % [Balance.CURRENCY_SHORT, Balance.format_number(total)]
	_update_countdown()


func _on_income_changed(per_sec: float) -> void:
	_income_label.text = "挂机收入 %s/秒" % Balance.format_number(per_sec)
	_update_countdown()


func _on_level_changed(new_level: int) -> void:
	_refresh_buttons()
	_refresh_rebirth()
	_check_milestone(new_level)
	_check_rebirth_guide(new_level)


func _on_money_not_enough(_needed: float) -> void:
	Sfx.play("money_not_enough")
	_flash(_upgrade_button)


func _on_floor_changed(new_floor: int) -> void:
	_floor_name_label.text = ("难%d · " % GameState.difficulty if GameState.difficulty > 1 else "") + str(Balance.FLOOR_NAMES.get(new_floor, "未知层"))
	_refresh_buttons()
	# 场景背景按层切换（tools/gen_asset.py --scene 产物；缺失时保持上一张/空）
	var bg_path := "res://assets/art/bg/bg_floor%d.png" % new_floor
	_bg_art.texture = load(bg_path) if ResourceLoader.exists(bg_path) else null


func _on_floor_unlocked(_req_level: int) -> void:
	Sfx.play("floor_unlock")
	_show_toast("枝务厅通知：您的登层签证已下发。树的祝福随函附上——不用谢。")


func _on_save_completed() -> void:
	_save_label.text = "已自动保存 %s" % Time.get_time_string_from_system().substr(0, 5)


# ---------- 交互 ----------

func _on_upgrade_pressed() -> void:
	if GameState.upgrade_level():
		Sfx.play("level_up")


func _on_floor2_pressed() -> void:
	## 层间往返：循环 1→2→3→4→5→6→1（三层 Lv.50+卡；四层 Lv.60+卡；五层 Lv.70+卡；六层 Lv.85+卡）
	var nxt := GameState.floor_index % 6 + 1
	if GameState.can_go_to_floor(nxt):
		Sfx.play("floor_switch")
		GameState.go_to_floor(nxt)
	else:
		Sfx.play("money_not_enough", 1.0, -6.0)
		_flash(_floor2_button)


func _on_adventure_pressed() -> void:
	Sfx.play("ui_click")
	get_tree().change_scene_to_file("res://scenes/battle/battle.tscn")


func _on_market_pressed() -> void:
	Sfx.play("ui_click")
	get_tree().change_scene_to_file("res://scenes/market/market.tscn")


func _on_skill_upgrade_pressed() -> void:
	if GameState.skill_upgrade():
		Sfx.play("line_up")
		_refresh_training()
	else:
		Sfx.play("money_not_enough", 1.0, -6.0)


func _on_line_pressed(kind: String) -> void:
	if GameState.upgrade_line(kind):
		Sfx.play("line_up")


# ---------- 重生转生（M4） ----------

func _check_rebirth_guide(new_level: int) -> void:
	## 【已拍板】Lv.38 首次触墙：世界树引导（仅首轮回弹一次，弹过即记档）
	if GameState.rebirth_count > 0 or GameState.rebirth_guide_shown:
		return
	if new_level < Balance.REBIRTH_GUIDE_LEVEL:
		return
	GameState.rebirth_guide_shown = true
	_show_toast("世界树低语：献金越来越重了……把等级献给我，我将结出果实回赠")


func _on_rebirth_pressed() -> void:
	if not GameState.rebirth_ready():
		return
	var gained := GameState.pending_fruits()
	_rebirth_info.text = "你将失去：等级、吉尔、精华。\n你将保留：果实、持仓，以及记忆——\n毕竟挨过冬天的，都记性好。\n\n本次献上可得：世界树的果实 ×%d\n此后每颗果实：挂机收入 +5%%、训练费用 -2%%、攻击效果 +1%%\n（交易所持仓与行情保留）" % [
		gained,
	]
	_rebirth_confirm.visible = true


func _on_rebirth_cancelled() -> void:
	_rebirth_confirm.visible = false


func _on_rebirth_confirmed() -> void:
	_rebirth_confirm.visible = false
	var gained := GameState.do_rebirth()
	if gained < 0:
		return
	SaveManager.save()  # 重生是关键节点，立即落盘
	_refresh_all()


func _on_rebirth_performed(gained: int, total: int, count: int) -> void:
	Sfx.play("rebirth")
	_show_toast("献上等级！世界树结出果实 ×%d（累计 %d，第 %d 轮）" % [gained, total, count])


func _refresh_rebirth() -> void:
	_fruits_label.text = "世界树的果实 ×%d" % GameState.fruits
	var threshold := GameState.rebirth_threshold()
	if GameState.rebirth_ready():
		_rebirth_button.disabled = false
		_rebirth_button.text = "献上等级（可得果实 ×%d）" % GameState.pending_fruits()
	else:
		_rebirth_button.disabled = true
		_rebirth_button.text = "献上等级（需 Lv.%d，当前 Lv.%d）" % [threshold, GameState.level]


# ---------- 刷新 ----------

func _refresh_all() -> void:
	_on_money_changed(GameState.money)
	_on_income_changed(GameState.income_per_sec())
	_on_floor_changed(GameState.floor_index)
	_refresh_buttons()
	_refresh_training()
	_refresh_rebirth()
	_refresh_talents()


func _refresh_talents() -> void:
	_talents_button.text = "天赋 · %d 点（%s）" % [
		GameState.skill_points + GameState.paragon_points,
		("巅峰 %d" % GameState.paragon_points) if GameState.level >= GameTalents.PARAGON_LEVEL else "升级积累中",
	]
	_talents_button.disabled = false
	_talents_button.tooltip_text = "打开天赋树：消耗技能点强化你的职业流派"
	# 巅峰入口：Lv.60 解锁（D-P6 三板块全做）
	var paragon_unlocked := GameState.level >= GameTalents.PARAGON_LEVEL
	_paragon_button.disabled = not paragon_unlocked
	_paragon_button.text = "巅峰 · %d 点" % GameState.paragon_points if paragon_unlocked \
		else "巅峰（需 Lv.%d）" % GameTalents.PARAGON_LEVEL
	_paragon_button.tooltip_text = "打开巅峰板块：巅峰点是后期专属的成长资源"


func _on_talents_pressed() -> void:
	add_child(TalentsPanel.new())


func _on_paragon_pressed() -> void:
	add_child(ParagonPanel.new())


func _refresh_buttons() -> void:
	var cost := GameState.upgrade_cost()
	_upgrade_button.text = "献金升级 → Lv.%d（%s %s）" % [
		GameState.level + 1,
		Balance.format_number(cost),
		Balance.CURRENCY_SHORT,
	]
	# 层间按钮：循环 1→2→3→4→5→6→1；不可去时置灰，完整条件放悬停提示（按钮文字保持一行内）
	var cur := GameState.floor_index
	var nxt := cur % 6 + 1
	var nxt_name: String = Balance.FLOOR_NAMES.get(nxt, "未知层")
	if GameState.can_go_to_floor(nxt):
		_floor2_button.disabled = false
		_floor2_button.text = "前往%s" % nxt_name
		_floor2_button.tooltip_text = "前往%s" % nxt_name
	else:
		_floor2_button.disabled = true
		var req6 := Balance.diff_floor_req(Balance.FLOOR_6_LEVEL_REQ, GameState.difficulty)
		var req5 := Balance.diff_floor_req(Balance.FLOOR_5_LEVEL_REQ, GameState.difficulty)
		var req4 := Balance.diff_floor_req(Balance.FLOOR_4_LEVEL_REQ, GameState.difficulty)
		var req3 := Balance.diff_floor_req(Balance.FLOOR_3_LEVEL_REQ, GameState.difficulty)
		var req2 := Balance.diff_floor_req(Balance.FLOOR_2_LEVEL_REQ, GameState.difficulty)
		var diff_tag := ("难%d · " % GameState.difficulty) if GameState.difficulty > 1 else ""
		if nxt == 6:
			_floor2_button.text = "前往第六层（需层卡）"
			_floor2_button.tooltip_text = "%s第六层 · 星梢：需 Lv.%d + 层卡（首杀瞭望鹰掉落），当前 Lv.%d" % [
				diff_tag, req6, GameState.level,
			]
		elif nxt == 5:
			_floor2_button.text = "前往第五层（需层卡）"
			_floor2_button.tooltip_text = "%s第五层 · 云顶鹰巢：需 Lv.%d + 层卡（首杀千瓣祭主掉落），当前 Lv.%d" % [
				diff_tag, req5, GameState.level,
			]
		elif nxt == 4:
			_floor2_button.text = "前往第四层（需层卡）"
			_floor2_button.tooltip_text = "%s第四层 · 落英花冠：需 Lv.%d + 层卡（首杀镇风桩掉落），当前 Lv.%d" % [
				diff_tag, req4, GameState.level,
			]
		elif nxt == 3:
			_floor2_button.text = "前往第三层（需层卡）"
			_floor2_button.tooltip_text = "%s第三层 · 苍干栈道：需 Lv.%d + 层卡（首杀守林古树掉落），当前 Lv.%d" % [
				diff_tag, req3, GameState.level,
			]
		else:
			_floor2_button.text = "前往第二层（需 Lv.%d）" % req2
			_floor2_button.tooltip_text = "%s第二层 · 翠枝回廊：需 Lv.%d，当前 Lv.%d" % [
				diff_tag, req2, GameState.level]
	var market_unlocked := GameState.level >= Balance.MARKET_UNLOCK_LEVEL
	_market_button.disabled = not market_unlocked
	_market_button.text = "交易所" if market_unlocked else "交易所（需 Lv.%d）" % Balance.MARKET_UNLOCK_LEVEL


func _refresh_training() -> void:
	_essence_label.text = "元素精华：%d" % GameState.essence
	for kind: String in _line_buttons.keys():
		var btn: Button = _line_buttons[kind]
		if kind == "skill":
			# 技能强化（第五条训练位）：精华升级主动技能主数值，10 级封顶
			var lv := GameState.skill_lv
			var maxed := lv >= GameState.SKILL_LV_MAX
			var cost := GameState.skill_upgrade_cost()
			btn.text = "技能强化 Lv.%d → %d（%d 精华）" % [lv, lv + 1, cost] if not maxed \
				else "技能强化 已满级（Lv.%d）" % lv
			btn.disabled = maxed or GameState.essence < cost
			continue
		var lv := GameState.line_level(kind)
		var cost := GameState.train_cost_for(kind)
		btn.text = "%s Lv.%d → %d（%d 精华）" % [LINE_NAMES[kind], lv, lv + 1, cost]
		btn.disabled = GameState.essence < cost


func _update_countdown() -> void:
	## QoL：距下次献金的预计时间（NGU 进度条文化）
	var remain := GameState.upgrade_cost() - GameState.money
	if remain <= 0.0:
		_countdown_label.text = "现在就能献金！"
		return
	var inc := GameState.income_per_sec()
	if inc <= 0.0:
		_countdown_label.text = ""
		return
	var secs := remain / inc
	if secs < 90.0:
		_countdown_label.text = "距下次献金约 %d 秒" % int(ceil(secs))
	elif secs < 5400.0:
		_countdown_label.text = "距下次献金约 %d 分钟" % int(ceil(secs / 60.0))
	else:
		_countdown_label.text = "距下次献金约 %.1f 小时" % (secs / 3600.0)


func _check_milestone(new_level: int) -> void:
	## QoL：等级里程碑一次性精华奖励（NGU 式"升级有新东西"）
	if not Balance.MILESTONE_EP.has(new_level):
		return
	var reward := int(Balance.MILESTONE_EP[new_level])
	GameState.add_essence(reward)
	_show_toast("里程碑！Lv.%d 达成，奖励 %d 元素精华" % [new_level, reward])


func _on_essence_changed(_total: int) -> void:
	_refresh_training()


func _on_line_changed(_kind: String, _level: int) -> void:
	_refresh_training()


# ---------- 特效 ----------

func _flash(button: Button) -> void:
	var tween := create_tween()
	tween.tween_property(button, "modulate", Color(1.0, 0.45, 0.45), 0.08)
	tween.tween_property(button, "modulate", Color.WHITE, 0.25)


func _show_toast(text: String) -> void:
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.text = text
	_toast.modulate.a = 1.0
	_toast.visible = true
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.5)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.6)
	_toast_tween.tween_callback(_hide_toast)


func _hide_toast() -> void:
	_toast.visible = false
	_toast.modulate.a = 1.0
