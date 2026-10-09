extends Control
## M1 主界面：挂机核心循环。
## UI 由代码构建（美术阶段再迁移到场景文件编辑）。
## 设定基调：玩家在"树根之街"向世界树献金，换取等级（祝福）与登层资格。

const COL_BG := Color("191322")
const COL_GOLD := Color("ffd75e")
const COL_TEXT := Color("e8e0cf")
const COL_DIM := Color("a89f8d")
const COL_PANEL := Color("241d33")
const COL_TREE := Color("243b2e")

var _money_label: Label
var _income_label: Label
var _floor_name_label: Label
var _upgrade_button: Button
var _floor2_button: Button
var _save_label: Label
var _toast: Label
var _toast_tween: Tween
var _reset_button: Button
var _reset_confirm: Control


func _ready() -> void:
	_build_background()
	_build_top_hud()
	_build_tree_panel()
	_build_right_panel()
	_build_toast()
	_build_save_label()
	_build_reset_button()
	_build_reset_confirm()
	_connect_signals()
	_refresh_all()


# ---------- UI 构建 ----------

func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)


func _build_top_hud() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.offset_left = -400
	box.offset_right = 400
	box.offset_top = 32
	box.offset_bottom = 232
	add_child(box)
	_money_label = _make_label(box, "", 64, COL_GOLD)
	_income_label = _make_label(box, "", 24, COL_DIM)


func _build_tree_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	panel.offset_left = 96
	panel.offset_right = 96 + 520
	panel.offset_top = -220
	panel.offset_bottom = 220
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_TREE
	sb.set_corner_radius_all(16)
	sb.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	_make_label(box, "世界树", 40, COL_GOLD)
	_floor_name_label = _make_label(box, "", 28)
	_make_label(box, "（场景立绘占位）", 16, COL_DIM)


func _build_right_panel() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	box.offset_left = -96 - 460
	box.offset_right = -96
	box.offset_top = -160
	box.offset_bottom = 160
	box.add_theme_constant_override("separation", 18)
	add_child(box)

	_upgrade_button = Button.new()
	_upgrade_button.custom_minimum_size = Vector2(460, 64)
	_upgrade_button.add_theme_font_size_override("font_size", 25)
	_upgrade_button.pressed.connect(_on_upgrade_pressed)
	box.add_child(_upgrade_button)

	_floor2_button = Button.new()
	_floor2_button.custom_minimum_size = Vector2(460, 64)
	_floor2_button.add_theme_font_size_override("font_size", 25)
	_floor2_button.pressed.connect(_on_floor2_pressed)
	box.add_child(_floor2_button)

	var flavor := _make_label(box, Balance.UPGRADE_FLAVOR, 17, COL_DIM)
	flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _build_toast() -> void:
	_toast = _make_label(self, "", 26, COL_GOLD)
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.offset_left = -500
	_toast.offset_right = 500
	_toast.offset_top = -140
	_toast.offset_bottom = -100
	_toast.visible = false


func _build_save_label() -> void:
	_save_label = _make_label(self, "", 15, COL_DIM)
	_save_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_save_label.offset_left = -380
	_save_label.offset_right = -16
	_save_label.offset_top = -44
	_save_label.offset_bottom = -16


func _build_reset_button() -> void:
	_reset_button = Button.new()
	_reset_button.text = "重置存档"
	_reset_button.flat = true
	_reset_button.add_theme_font_size_override("font_size", 15)
	_reset_button.add_theme_color_override("font_color", COL_DIM)
	_reset_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_reset_button.offset_left = 16
	_reset_button.offset_right = 120
	_reset_button.offset_top = -40
	_reset_button.offset_bottom = -12
	_reset_button.pressed.connect(_on_reset_pressed)
	add_child(_reset_button)


func _build_reset_confirm() -> void:
	_reset_confirm = CenterContainer.new()
	_reset_confirm.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reset_confirm.visible = false
	add_child(_reset_confirm)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.set_corner_radius_all(16)
	sb.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(520, 0)
	_reset_confirm.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	_make_label(box, "重置存档", 28, COL_GOLD)
	_make_label(box, "确定要清空所有进度吗？\n此操作无法撤销。", 20)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	box.add_child(buttons)
	var cancel := Button.new()
	cancel.text = "取消"
	cancel.custom_minimum_size = Vector2(140, 48)
	cancel.add_theme_font_size_override("font_size", 20)
	cancel.pressed.connect(_on_reset_cancelled)
	buttons.add_child(cancel)
	var confirm := Button.new()
	confirm.text = "确定重置"
	confirm.custom_minimum_size = Vector2(140, 48)
	confirm.add_theme_font_size_override("font_size", 20)
	confirm.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
	confirm.pressed.connect(_on_reset_confirmed)
	buttons.add_child(confirm)


func _make_label(parent: Node, text: String, font_size: int, color: Color = COL_TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


# ---------- 信号 ----------

func _connect_signals() -> void:
	EventBus.money_changed.connect(_on_money_changed)
	EventBus.income_changed.connect(_on_income_changed)
	EventBus.level_changed.connect(_on_level_changed)
	EventBus.money_not_enough.connect(_on_money_not_enough)
	EventBus.floor_changed.connect(_on_floor_changed)
	EventBus.floor_unlocked.connect(_on_floor_unlocked)
	EventBus.save_completed.connect(_on_save_completed)


func _on_money_changed(total: float) -> void:
	_money_label.text = "%s %s" % [Balance.CURRENCY_SHORT, Balance.format_number(total)]


func _on_income_changed(per_sec: float) -> void:
	_income_label.text = "挂机收入 %s/秒" % Balance.format_number(per_sec)


func _on_level_changed(_new_level: int) -> void:
	_refresh_buttons()


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
	GameState.go_to_floor(2)


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


# ---------- 刷新 ----------

func _refresh_all() -> void:
	_on_money_changed(GameState.money)
	_on_income_changed(GameState.income_per_sec())
	_on_floor_changed(GameState.floor_index)
	_refresh_buttons()


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
		_floor2_button.text = "已抵达第二层（内容建设中）"
	elif unlocked:
		_floor2_button.text = "前往第二层"
	else:
		_floor2_button.text = "第二层（需 Lv.%d，当前 Lv.%d）" % [
			Balance.FLOOR_2_LEVEL_REQ, GameState.level,
		]


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
