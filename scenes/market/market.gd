extends Control
## M3 交易所：K 线行情 + 低买高卖。
## 【已拍板】三标的 / 纯随机游走 / Lv.15 解锁 / 买卖各 1% 手续费。

const COL_BG := Color("191322")
const COL_GOLD := Color("ffd75e")
const COL_TEXT := Color("e8e0cf")
const COL_DIM := Color("a89f8d")
const COL_PANEL := Color("241d33")
const UP_RED := Color("e0564f")      # 涨（中式红涨）
const DOWN_GREEN := Color("58b46b")  # 跌
const KLINE_CHART := preload("res://scenes/market/kline_chart.gd")

var selected := 0
var _chart: Control
var _target_buttons: Array = []
var _price_label: Label
var _hold_label: Label
var _value_label: Label
var _amount_input: LineEdit
var _lock_panel: Control
var _last_prices: Array = []


func _ready() -> void:
	_build_background()
	_build_topbar()
	_build_target_list()
	_build_chart()
	_build_trade_panel()
	_build_lock_panel()
	Market.prices_changed.connect(_refresh_quotes)
	Market.candle_closed.connect(_refresh_quotes)
	_refresh_all()
	if OS.get_cmdline_user_args().has("--bake-ui"):
		_bake_ui.call_deferred()


## 【场景化迁移】把运行时构建的 UI 树烘焙进 market.tscn（一次性工具）
func _bake_ui() -> void:
	_set_owner_recursive(self)
	var keep: Array = [_price_label, _hold_label, _value_label, _amount_input,
		_chart, _lock_panel]
	keep += _target_buttons
	for n in keep:
		if n != null:
			n.unique_name_in_owner = true
	var ps := PackedScene.new()
	var err := ps.pack(self)
	print("[bake] pack=", err)
	if err == OK:
		err = ResourceSaver.save(ps, "res://scenes/market/market.tscn")
	print("[bake] save=", err)
	get_tree().quit()


func _set_owner_recursive(node: Node) -> void:
	if node != self:
		node.owner = self
	for c in node.get_children():
		_set_owner_recursive(c)


func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)


func _build_topbar() -> void:
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_LEFT)
	top.offset_left = 24
	top.offset_top = 20
	top.offset_right = 24 + 900
	top.offset_bottom = 70
	top.add_theme_constant_override("separation", 20)
	add_child(top)
	var title := Label.new()
	title.text = "交易所（树根之街支行）"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", COL_GOLD)
	top.add_child(title)
	var fee_note := Label.new()
	fee_note.text = "手续费 1%（买卖均收）"
	fee_note.add_theme_font_size_override("font_size", 16)
	fee_note.add_theme_color_override("font_color", COL_DIM)
	fee_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(fee_note)
	var back := Button.new()
	back.text = "返回主界面"
	back.custom_minimum_size = Vector2(170, 44)
	back.add_theme_font_size_override("font_size", 18)
	back.pressed.connect(_on_back_pressed)
	top.add_child(back)


func _build_target_list() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	panel.offset_left = 60
	panel.offset_right = 60 + 400
	panel.offset_top = -160
	panel.offset_bottom = 160
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.set_corner_radius_all(16)
	sb.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var head := Label.new()
	head.text = "标的行情"
	head.add_theme_font_size_override("font_size", 22)
	head.add_theme_color_override("font_color", COL_GOLD)
	box.add_child(head)
	for i in Balance.MARKET_TARGETS.size():
		var t: Dictionary = Balance.MARKET_TARGETS[i]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 56)
		btn.add_theme_font_size_override("font_size", 20)
		btn.text = t["name"]
		btn.pressed.connect(_on_target_pressed.bind(i))
		box.add_child(btn)
		_target_buttons.append(btn)
	_hold_label = _make_label(box, "", 18, COL_TEXT)
	_value_label = _make_label(box, "", 16, COL_DIM)


func _build_chart() -> void:
	# 居中偏移摆放（PRESET_CENTER 会把控件左上角钉在屏幕中心导致右下坠，需手动配平偏移）
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -445
	panel.offset_right = 445
	panel.offset_top = -310
	panel.offset_bottom = 150
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.set_corner_radius_all(16)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	_price_label = _make_label(box, "", 24, COL_GOLD)
	_chart = KLINE_CHART.new()
	_chart.source = Market
	_chart.custom_minimum_size = Vector2(0, 380)
	_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_chart)


func _build_trade_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	panel.offset_left = -60 - 400
	panel.offset_right = -60
	panel.offset_top = -170
	panel.offset_bottom = 170
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.set_corner_radius_all(16)
	sb.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var head := Label.new()
	head.text = "交易"
	head.add_theme_font_size_override("font_size", 22)
	head.add_theme_color_override("font_color", COL_GOLD)
	box.add_child(head)
	var qty_row := HBoxContainer.new()
	qty_row.add_theme_constant_override("separation", 8)
	box.add_child(qty_row)
	var qty_lab := Label.new()
	qty_lab.text = "数量"
	qty_lab.custom_minimum_size = Vector2(60, 0)
	qty_lab.add_theme_font_size_override("font_size", 18)
	qty_row.add_child(qty_lab)
	_amount_input = LineEdit.new()
	_amount_input.text = "10"
	_amount_input.custom_minimum_size = Vector2(120, 36)
	_amount_input.add_theme_font_size_override("font_size", 18)
	qty_row.add_child(_amount_input)
	var buy := Button.new()
	buy.text = "买入"
	buy.custom_minimum_size = Vector2(0, 40)
	buy.add_theme_font_size_override("font_size", 18)
	buy.pressed.connect(_act_buy)
	box.add_child(buy)
	var sell := Button.new()
	sell.text = "卖出"
	sell.custom_minimum_size = Vector2(0, 40)
	sell.add_theme_font_size_override("font_size", 18)
	sell.pressed.connect(_act_sell)
	box.add_child(sell)
	_make_label(box, "低买高卖，赚取差价\n价格每 5 秒波动一次", 15, COL_DIM)


func _build_lock_panel() -> void:
	_lock_panel = CenterContainer.new()
	_lock_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lock_panel.visible = false
	add_child(_lock_panel)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.set_corner_radius_all(16)
	sb.set_content_margin_all(32)
	panel.add_theme_stylebox_override("panel", sb)
	_lock_panel.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var t := Label.new()
	t.text = "侏儒的名言：\n天上不会掉钱，但树上会。"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 30)
	t.add_theme_color_override("font_color", COL_GOLD)
	box.add_child(t)
	var s := Label.new()
	s.text = "交易所 Lv.%d 解锁——先在世界树练练级吧" % Balance.MARKET_UNLOCK_LEVEL
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.add_theme_font_size_override("font_size", 18)
	s.add_theme_color_override("font_color", COL_DIM)
	box.add_child(s)
	var back := Button.new()
	back.text = "返回主界面"
	back.custom_minimum_size = Vector2(200, 48)
	back.add_theme_font_size_override("font_size", 18)
	back.pressed.connect(_on_back_pressed)
	box.add_child(back)


func _make_label(parent: Node, text: String, font_size: int, color: Color = COL_TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


# ---------- 交互与刷新 ----------

func _on_target_pressed(idx: int) -> void:
	selected = idx
	_chart.target_idx = idx
	_chart.queue_redraw()
	_refresh_quotes()


func _act_buy() -> void:
	if GameState.buy_stock(selected, _to_i(_amount_input.text)):
		_show_toast("买入成功！")
	else:
		_show_toast("吉尔不足或数量无效")
	_refresh_quotes()


func _act_sell() -> void:
	if GameState.sell_stock(selected, _to_i(_amount_input.text)):
		_show_toast("卖出成功！")
	else:
		_show_toast("没有足够持仓")
	_refresh_quotes()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")


func _to_i(text: String) -> int:
	return maxi(0, int(text) if text.is_valid_int() else 0)


func _show_toast(text: String) -> void:
	_price_label.text = text  # 复用现价栏做轻提示（下一刷新自动恢复）


func _refresh_quotes() -> void:
	_chart.target_idx = selected
	_chart.queue_redraw()
	for i in _target_buttons.size():
		var btn: Button = _target_buttons[i]
		var t: Dictionary = Balance.MARKET_TARGETS[i]
		var prev: float = t["base"]
		if Market.history[i].size() > 0:
			prev = Market.history[i][Market.history[i].size() - 1][3]
		var chg: float = (Market.prices[i] - prev) / maxf(prev, 0.01) * 100.0
		var arrow := "↑" if chg >= 0.0 else "↓"
		btn.text = "%s  %.1f G  %s%.1f%%" % [t["name"], Market.prices[i], arrow, absf(chg)]
		btn.modulate = Color(1.35, 1.35, 1.05) if i == selected else Color.WHITE
	var t2: Dictionary = Balance.MARKET_TARGETS[selected]
	_price_label.text = "%s 现价 %.1f G" % [t2["name"], Market.prices[selected]]
	_hold_label.text = "持仓：%d 股 ｜ 市值：%.0f G" % [
		GameState.holdings[selected], GameState.holdings[selected] * Market.prices[selected],
	]
	var total_value := GameState.money
	for i in GameState.holdings.size():
		total_value += GameState.holdings[i] * Market.prices[i]
	_value_label.text = "现金 %.0f G ｜ 总资产 %.0f G" % [GameState.money, total_value]


func _refresh_all() -> void:
	_chart.target_idx = selected
	var locked := GameState.level < Balance.MARKET_UNLOCK_LEVEL
	_lock_panel.visible = locked
	_refresh_quotes()
