class_name DevPanel
extends Control
## 开发阶段内置修改器（按 F1 开关）。
## 仅 debug 构建（编辑器 / F5 运行）加载；导出的 release 版自动不存在。
## 功能：加吉尔/精华、设等级、快进挂机收入、训练线直调、层间传送、清档、实时状态。

const COL_BG := Color(0.09, 0.07, 0.15, 0.94)
const COL_GOLD := Color("ffd75e")
const COL_TEXT := Color("e8e0cf")
const COL_DIM := Color("a89f8d")

var _stats: Label
var _refresh_accum := 0.0
var _line_set_input: LineEdit


func _ready() -> void:
	visible = false
	_build_panel()


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_accum += delta
	if _refresh_accum >= 0.5:
		_refresh_accum = 0.0
		_refresh_stats()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		visible = not visible
		if visible:
			_refresh_stats()


# ---------- 构建 ----------

func _build_panel() -> void:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_BG
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 16
	panel.offset_top = 16
	panel.offset_right = 16 + 430
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var title := Label.new()
	title.text = "开发修改器（F1 开关 · 仅开发构建）"
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", COL_GOLD)
	box.add_child(title)

	# 吉尔
	var gil_input := _add_action_row(box, "吉尔 +", "1000", "添加", _act_add_gil)
	# 精华
	var ep_input := _add_action_row(box, "精华 +", "100", "添加", _act_add_ep)
	# 等级
	var lv_input := _add_action_row(box, "等级设为", "10", "设置", _act_set_level)
	# 快进
	_add_action_row(box, "快进挂机(秒)", "600", "执行", _act_skip_time)

	# 训练线直调
	var line_row := HBoxContainer.new()
	line_row.add_theme_constant_override("separation", 8)
	box.add_child(line_row)
	var line_lab := Label.new()
	line_lab.text = "训练线 +1"
	line_lab.custom_minimum_size = Vector2(92, 0)
	line_lab.add_theme_font_size_override("font_size", 16)
	line_lab.add_theme_color_override("font_color", COL_TEXT)
	line_row.add_child(line_lab)
	for pair in [["atk", "攻"], ["bounty", "赏"], ["income", "收"]]:
		var btn := Button.new()
		btn.text = "%s+1" % pair[1]
		btn.custom_minimum_size = Vector2(66, 32)
		btn.add_theme_font_size_override("font_size", 15)
		btn.pressed.connect(_act_add_line.bind(pair[0]))
		line_row.add_child(btn)

	# 训练线直接设为指定等级
	var set_row := HBoxContainer.new()
	set_row.add_theme_constant_override("separation", 8)
	box.add_child(set_row)
	var set_lab := Label.new()
	set_lab.text = "训练线设为"
	set_lab.custom_minimum_size = Vector2(92, 0)
	set_lab.add_theme_font_size_override("font_size", 16)
	set_lab.add_theme_color_override("font_color", COL_TEXT)
	set_row.add_child(set_lab)
	_line_set_input = LineEdit.new()
	_line_set_input.text = "20"
	_line_set_input.custom_minimum_size = Vector2(90, 32)
	_line_set_input.add_theme_font_size_override("font_size", 16)
	set_row.add_child(_line_set_input)
	for pair in [["atk", "攻"], ["bounty", "赏"], ["income", "收"]]:
		var sbtn := Button.new()
		sbtn.text = "%s设" % pair[1]
		sbtn.custom_minimum_size = Vector2(66, 32)
		sbtn.add_theme_font_size_override("font_size", 15)
		sbtn.pressed.connect(_act_set_line.bind(pair[0]))
		set_row.add_child(sbtn)

	# 传送
	var tp_row := HBoxContainer.new()
	tp_row.add_theme_constant_override("separation", 8)
	box.add_child(tp_row)
	var tp_lab := Label.new()
	tp_lab.text = "层间传送"
	tp_lab.custom_minimum_size = Vector2(92, 0)
	tp_lab.add_theme_font_size_override("font_size", 16)
	tp_lab.add_theme_color_override("font_color", COL_TEXT)
	tp_row.add_child(tp_lab)
	var to_f2 := Button.new()
	to_f2.text = "去第二层"
	to_f2.custom_minimum_size = Vector2(100, 32)
	to_f2.add_theme_font_size_override("font_size", 15)
	to_f2.pressed.connect(func() -> void: GameState.go_to_floor(2))
	tp_row.add_child(to_f2)
	var to_f1 := Button.new()
	to_f1.text = "回第一层"
	to_f1.custom_minimum_size = Vector2(100, 32)
	to_f1.add_theme_font_size_override("font_size", 15)
	to_f1.pressed.connect(func() -> void: GameState.go_to_floor(1))
	tp_row.add_child(to_f1)

	# 清档
	var wipe := Button.new()
	wipe.text = "清空存档（全新开局）"
	wipe.custom_minimum_size = Vector2(0, 34)
	wipe.add_theme_font_size_override("font_size", 15)
	wipe.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
	wipe.pressed.connect(_act_wipe)
	box.add_child(wipe)

	# 状态
	_stats = Label.new()
	_stats.text = ""
	_stats.add_theme_font_size_override("font_size", 15)
	_stats.add_theme_color_override("font_color", COL_DIM)
	box.add_child(_stats)


func _add_action_row(parent: Control, label_text: String, default_value: String, button_text: String, action: Callable) -> LineEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var lab := Label.new()
	lab.text = label_text
	lab.custom_minimum_size = Vector2(92, 0)
	lab.add_theme_font_size_override("font_size", 16)
	lab.add_theme_color_override("font_color", COL_TEXT)
	row.add_child(lab)
	var input := LineEdit.new()
	input.text = default_value
	input.custom_minimum_size = Vector2(90, 32)
	input.add_theme_font_size_override("font_size", 16)
	row.add_child(input)
	var btn := Button.new()
	btn.text = button_text
	btn.custom_minimum_size = Vector2(110, 32)
	btn.add_theme_font_size_override("font_size", 15)
	btn.pressed.connect(action.bind(input))
	row.add_child(btn)
	return input


# ---------- 动作 ----------

func _to_f(text: String) -> float:
	return maxf(0.0, float(text) if text.is_valid_float() else 0.0)


func _to_i(text: String) -> int:
	return maxi(0, int(text) if text.is_valid_int() else 0)


func _act_add_gil(input: LineEdit) -> void:
	GameState.add_money(_to_f(input.text))
	_refresh_stats()


func _act_add_ep(input: LineEdit) -> void:
	GameState.add_essence(_to_i(input.text))
	_refresh_stats()


func _act_set_level(input: LineEdit) -> void:
	GameState.debug_set_level(_to_i(input.text))
	_refresh_stats()


func _act_skip_time(input: LineEdit) -> void:
	# 快进：立刻结算 X 秒的挂机收入（不影响真实时间与离线规则）
	var secs := _to_f(input.text)
	GameState.add_money(GameState.income_per_sec() * secs)
	_refresh_stats()


func _act_add_line(kind: String) -> void:
	GameState.debug_add_line(kind, 1)
	_refresh_stats()


func _act_set_line(kind: String) -> void:
	GameState.debug_set_line(kind, _to_i(_line_set_input.text))
	_refresh_stats()


func _act_wipe() -> void:
	SaveManager.delete_save()
	GameState.reset()
	_refresh_stats()


func _refresh_stats() -> void:
	_stats.text = "Lv.%d ｜ 吉尔 %s ｜ 精华 %d\n收入 %s/秒 ｜ 攻/赏/收线 %d/%d/%d ｜ 所在层 %d" % [
		GameState.level,
		Balance.format_number(GameState.money),
		GameState.essence,
		Balance.format_number(GameState.income_per_sec()),
		GameState.atk_line, GameState.bounty_line, GameState.income_line,
		GameState.floor_index,
	]
