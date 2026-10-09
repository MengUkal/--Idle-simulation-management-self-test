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


func _ready() -> void:
	_init_line_buttons()
	_connect_signals()
	_refresh_all()
	if OS.is_debug_build():
		add_child(DevPanel.new())  # 开发修改器（F1 开关），release 导出自动不存在


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
	_upgrade_button.pressed.connect(_on_upgrade_pressed)
	_floor2_button.pressed.connect(_on_floor2_pressed)
	_adventure_button.pressed.connect(_on_adventure_pressed)
	_market_button.pressed.connect(_on_market_pressed)
	_reset_button.pressed.connect(_on_reset_pressed)
	_reset_cancel_btn.pressed.connect(_on_reset_cancelled)
	_reset_apply_btn.pressed.connect(_on_reset_confirmed)
	_line_atk.pressed.connect(_on_line_pressed.bind("atk"))
	_line_bounty.pressed.connect(_on_line_pressed.bind("bounty"))
	_line_income.pressed.connect(_on_line_pressed.bind("income"))


# ---------- 信号处理 ----------

func _on_money_changed(total: float) -> void:
	_money_label.text = "%s %s" % [Balance.CURRENCY_SHORT, Balance.format_number(total)]
	_update_countdown()


func _on_income_changed(per_sec: float) -> void:
	_income_label.text = "挂机收入 %s/秒" % Balance.format_number(per_sec)
	_update_countdown()


func _on_level_changed(new_level: int) -> void:
	_refresh_buttons()
	_check_milestone(new_level)


func _on_money_not_enough(_needed: float) -> void:
	_flash(_upgrade_button)


func _on_floor_changed(new_floor: int) -> void:
	_floor_name_label.text = Balance.FLOOR_NAMES.get(new_floor, "未知层")
	_refresh_buttons()


func _on_floor_unlocked(req_level: int) -> void:
	_show_toast("祝福降临！等级已达 Lv.%d，第二层解锁" % req_level)


func _on_save_completed() -> void:
	_save_label.text = "已自动保存 %s" % Time.get_time_string_from_system().substr(0, 5)


# ---------- 交互 ----------

func _on_upgrade_pressed() -> void:
	GameState.upgrade_level()


func _on_floor2_pressed() -> void:
	## 层间往返：一层 ↔ 二层（低练度回一层速刷，练度够了上二层）
	if GameState.floor_index >= 2:
		GameState.go_to_floor(1)
	else:
		GameState.go_to_floor(2)


func _on_adventure_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/battle/battle.tscn")


func _on_market_pressed() -> void:
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
	GameState.upgrade_line(kind)


# ---------- 刷新 ----------

func _refresh_all() -> void:
	_on_money_changed(GameState.money)
	_on_income_changed(GameState.income_per_sec())
	_on_floor_changed(GameState.floor_index)
	_refresh_buttons()
	_refresh_training()


func _refresh_buttons() -> void:
	var cost := Balance.upgrade_cost(GameState.level)
	_upgrade_button.text = "献金升级 → Lv.%d（%s %s）" % [
		GameState.level + 1,
		Balance.format_number(cost),
		Balance.CURRENCY_SHORT,
	]
	var at_floor2 := GameState.floor_index >= 2
	var unlocked := GameState.level >= Balance.FLOOR_2_LEVEL_REQ
	_floor2_button.disabled = at_floor2 or not unlocked
	if at_floor2:
		_floor2_button.text = "返回第一层"
	elif unlocked:
		_floor2_button.text = "前往第二层"
	else:
		_floor2_button.text = "第二层（需 Lv.%d，当前 Lv.%d）" % [
			Balance.FLOOR_2_LEVEL_REQ, GameState.level,
		]
	var market_unlocked := GameState.level >= Balance.MARKET_UNLOCK_LEVEL
	_market_button.disabled = not market_unlocked
	_market_button.text = "交易所" if market_unlocked else "交易所（需 Lv.%d）" % Balance.MARKET_UNLOCK_LEVEL


func _refresh_training() -> void:
	_essence_label.text = "元素精华：%d" % GameState.essence
	for kind: String in _line_buttons.keys():
		var btn: Button = _line_buttons[kind]
		var lv := GameState.line_level(kind)
		var cost := int(Balance.train_cost(lv))
		btn.text = "%s Lv.%d → %d（%d 精华）" % [LINE_NAMES[kind], lv, lv + 1, cost]
		btn.disabled = GameState.essence < cost


func _update_countdown() -> void:
	## QoL：距下次献金的预计时间（NGU 进度条文化）
	var remain := Balance.upgrade_cost(GameState.level) - GameState.money
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
