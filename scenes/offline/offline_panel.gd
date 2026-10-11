class_name OfflinePanel
extends CanvasLayer
## 离线收益回归弹窗（2026-10-11 拍板：只结算金币 / 上限 8 小时 / 效率 60%）。
## 金额已在读档时由 GameState.settle_offline() 入账；本面板只负责展示与「收下」。

var _report: Dictionary


func _ready() -> void:
	layer = 96
	_report = GameState.take_offline_report()
	_build_ui()


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.78)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.08, 0.12, 0.97)
	sb.border_color = Color(0.85, 0.72, 0.35)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 38.0
	sb.content_margin_right = 38.0
	sb.content_margin_top = 26.0
	sb.content_margin_bottom = 26.0
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	_title(box, "欢 迎 回 来", 30, Color(0.95, 0.85, 0.55))
	box.add_child(HSeparator.new())

	var secs := int(_report.get("seconds", 0))
	var credited := int(_report.get("credited_sec", 0))
	_line(box, "离开了 %s" % _fmt_dur(secs))
	if credited < secs:
		_line(box, "计入收益 %s（离线上限 8 小时）" % _fmt_dur(credited))
	else:
		_line(box, "计入收益 %s" % _fmt_dur(credited))
	_line(box, "离线收益速率 %s 吉尔/秒（在线挂机收入的 60%%）"
		% Balance.format_number(float(_report.get("rate", 0.0))))

	_title(box, "+%s 吉尔" % Balance.format_number(float(_report.get("gold", 0))),
		34, Color(1.0, 0.84, 0.3))
	var note := _line(box, "已自动存入钱包")
	note.add_theme_color_override("font_color", Color(0.62, 0.60, 0.54))
	note.add_theme_font_size_override("font_size", 14)

	box.add_child(HSeparator.new())

	var btn := Button.new()
	btn.text = "收 下"
	btn.custom_minimum_size = Vector2(0, 48)
	btn.add_theme_font_size_override("font_size", 20)
	btn.pressed.connect(_on_claim)
	box.add_child(btn)


func _title(parent: Node, text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


func _line(parent: Node, text: String) -> Label:
	return _title(parent, text, 17, Color(0.88, 0.86, 0.80))


func _on_claim() -> void:
	Sfx.play("trade_sell")
	queue_free()


func _fmt_dur(sec: int) -> String:
	var total_min := int(sec / 60.0)
	var h := int(total_min / 60.0)
	var m := total_min % 60
	if h > 0:
		return "%d小时%d分" % [h, m]
	if m > 0:
		return "%d分" % m
	return "%d秒" % sec
