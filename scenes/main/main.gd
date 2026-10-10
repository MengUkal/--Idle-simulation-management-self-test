extends Control
## M1 主界面：挂机核心循环。
## 场景化迁移完成：节点结构见 main.tscn（编辑器内可拖动调整），
## 脚本通过 %唯一名 绑定节点——重命名/移动节点不会破坏引用，删除才会。

const LINE_NAMES := {"atk": "攻击训练", "bounty": "赏金训练", "income": "收入训练"}

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
	Sfx.bgm("bgm_floor1" if GameState.floor_index < 2 else "bgm_floor2")
	if OS.is_debug_build():
		add_child(DevPanel.new())  # 开发修改器（F1 开关），release 导出自动不存在
	if OS.get_cmdline_user_args().has("--capture-main"):
		_debug_capture.call_deferred()


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
	_upgrade_button.pressed.connect(_on_upgrade_pressed)
	_floor2_button.pressed.connect(_on_floor2_pressed)
	_adventure_button.pressed.connect(_on_adventure_pressed)
	_market_button.pressed.connect(_on_market_pressed)
	_reset_button.pressed.connect(_on_reset_pressed)
	_reset_cancel_btn.pressed.connect(_on_reset_cancelled)
	_reset_apply_btn.pressed.connect(_on_reset_confirmed)
	_rebirth_button.pressed.connect(_on_rebirth_pressed)
	_rebirth_cancel_btn.pressed.connect(_on_rebirth_cancelled)
	_rebirth_apply_btn.pressed.connect(_on_rebirth_confirmed)
	_settings_button.pressed.connect(_on_settings_pressed)
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
	_floor_name_label.text = Balance.FLOOR_NAMES.get(new_floor, "未知层")
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
	## 层间往返：循环 1→2→3→1（三层·苍干栈道需 Lv.50 + 层卡）
	var nxt := GameState.floor_index % 3 + 1
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


func _on_reset_pressed() -> void:
	_reset_confirm.visible = true


func _on_reset_cancelled() -> void:
	_reset_confirm.visible = false


func _on_reset_confirmed() -> void:
	_reset_confirm.visible = false
	SaveManager.delete_save()
	GameState.reset()
	_refresh_all()
	_show_toast("存档已重置，重新开始你的登树之旅")


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
	## 天赋树预留入口：技能点随升级积累，本版本不可消费
	_talents_button.text = "天赋 · %d 点（即将开放）" % GameState.skill_points
	_talents_button.tooltip_text = "每升 1 级获得 1 点技能点；天赋树将在后续版本开放"


func _refresh_buttons() -> void:
	var cost := GameState.upgrade_cost()
	_upgrade_button.text = "献金升级 → Lv.%d（%s %s）" % [
		GameState.level + 1,
		Balance.format_number(cost),
		Balance.CURRENCY_SHORT,
	]
	# 层间按钮：循环 1→2→3→1；不可去时置灰并显示条件（三层需 Lv.50 + 层卡）
	var cur := GameState.floor_index
	var nxt := cur % 3 + 1
	var nxt_name: String = Balance.FLOOR_NAMES.get(nxt, "未知层")
	if GameState.can_go_to_floor(nxt):
		_floor2_button.disabled = false
		_floor2_button.text = "前往%s" % nxt_name
	else:
		_floor2_button.disabled = true
		if nxt == 3:
			var need := "需 Lv.%d + 层卡（首杀守林古树）" % Balance.FLOOR_3_LEVEL_REQ
			if GameState.level >= Balance.FLOOR_3_LEVEL_REQ and not GameState.floor3_card:
				need = "需层卡（首杀守林古树）"
			_floor2_button.text = "%s（%s，当前 Lv.%d）" % [nxt_name, need, GameState.level]
		else:
			_floor2_button.text = "%s（需 Lv.%d，当前 Lv.%d）" % [
				nxt_name, Balance.FLOOR_2_LEVEL_REQ, GameState.level,
			]
	var market_unlocked := GameState.level >= Balance.MARKET_UNLOCK_LEVEL
	_market_button.disabled = not market_unlocked
	_market_button.text = "交易所" if market_unlocked else "交易所（需 Lv.%d）" % Balance.MARKET_UNLOCK_LEVEL


func _refresh_training() -> void:
	_essence_label.text = "元素精华：%d" % GameState.essence
	for kind: String in _line_buttons.keys():
		var btn: Button = _line_buttons[kind]
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
