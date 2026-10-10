class_name ParagonPanel
extends CanvasLayer
## 巅峰面板：三板块（破坏/经济/通用），节点购买/退还（洗点免费）。
## 解锁链：前一板块的传奇节点已购任一 → 下一板块开放。
## 代码构建 UI（参考 talents_panel/character_create 先例）。

var _board_list_box: VBoxContainer
var _points_label: Label


func _ready() -> void:
	layer = 95
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	add_child(dim)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(1180, 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	scroll.add_child(box)

	var title := Label.new()
	title.text = "巅峰"
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(1, 0.843, 0.369))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_points_label = Label.new()
	_points_label.add_theme_font_size_override("font_size", 22)
	_points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_points_label)

	_board_list_box = VBoxContainer.new()
	_board_list_box.add_theme_constant_override("separation", 14)
	box.add_child(_board_list_box)

	var hint := Label.new()
	hint.text = "Esc 关闭 · 巅峰洗点免费 · 巅峰点永久保留（重生不清）"
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color(0.659, 0.624, 0.553))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)

	var close := Button.new()
	close.text = "关闭（Esc）"
	close.custom_minimum_size = Vector2(240, 48)
	close.pressed.connect(close_panel)
	var close_wrap := CenterContainer.new()
	close_wrap.add_child(close)
	box.add_child(close_wrap)

	_rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()


func close_panel() -> void:
	SaveManager.save()
	queue_free()


func _rebuild() -> void:
	for c in _board_list_box.get_children():
		_board_list_box.remove_child(c)
		c.queue_free()
	_points_label.text = "可用巅峰点：%d ｜ 已投入：%d" % [
		GameState.paragon_points,
		GameState.paragon_invested("p1") + GameState.paragon_invested("p2") + GameState.paragon_invested("p3"),
	]
	for bid: String in GameParagon.BOARD_ORDER:
		_board_list_box.add_child(_board_section(bid))


func _board_section(bid: String) -> VBoxContainer:
	var board: Dictionary = GameParagon.get_board(bid)
	var unlocked := GameState.paragon_board_unlocked(bid)
	var sec := VBoxContainer.new()
	sec.add_theme_constant_override("separation", 6)

	var head := Label.new()
	head.text = "—— %s —— %s" % [board.get("name", bid), "已开放" if unlocked else "需前一板块传奇解锁"]
	head.add_theme_font_size_override("font_size", 22)
	head.add_theme_color_override("font_color",
		Color(1, 0.843, 0.369) if unlocked else Color(0.55, 0.5, 0.45))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sec.add_child(head)

	if not unlocked:
		var locked_note := Label.new()
		locked_note.text = "在前一板块点亮任意传奇节点后开放"
		locked_note.add_theme_font_size_override("font_size", 16)
		locked_note.add_theme_color_override("font_color", Color(0.6, 0.55, 0.5))
		locked_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sec.add_child(locked_note)
		return sec

	for n: Dictionary in board.get("nodes", []):
		if str(n.get("kind", "")) == "" or n.has("key_of"):
			continue  # 副作用行在传奇购买后动态出现
		sec.add_child(_node_row(n, board))
	return sec


func _node_row(n: Dictionary, board: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var rank := int(GameState.paragon_talents.get(n["id"], 0))
	var max_r := int(n.get("max", 1))

	var name_l := Label.new()
	name_l.text = "%s（%d/%d）" % [n["name"], rank, max_r]
	if n.has("key"):
		name_l.add_theme_color_override("font_color", Color(1, 0.843, 0.369))
	name_l.custom_minimum_size = Vector2(300, 0)
	name_l.add_theme_font_size_override("font_size", 19)
	row.add_child(name_l)

	var desc := Label.new()
	desc.text = "%s%s" % [n.get("desc", ""), ("　代价：" + str(n["tradeoff"])) if str(n.get("tradeoff", "")) != "" else ""]
	desc.custom_minimum_size = Vector2(420, 0)
	desc.add_theme_font_size_override("font_size", 17)
	desc.add_theme_color_override("font_color", Color(0.909, 0.878, 0.812))
	row.add_child(desc)

	row.add_child(Control.new())
	var buy := Button.new()
	buy.text = "升级（1 巅峰点）"
	buy.custom_minimum_size = Vector2(170, 36)
	buy.disabled = rank >= max_r or GameState.paragon_points < 1
	buy.pressed.connect(func() -> void:
		GameState.paragon_buy(n["id"])
		Sfx.play("level_up", 1.1)
		_rebuild())
	row.add_child(buy)
	var refund := Button.new()
	refund.text = "退还"
	refund.custom_minimum_size = Vector2(80, 36)
	refund.disabled = rank <= 0
	refund.pressed.connect(func() -> void:
		GameState.paragon_refund(n["id"])
		_rebuild())
	row.add_child(refund)
	return row
