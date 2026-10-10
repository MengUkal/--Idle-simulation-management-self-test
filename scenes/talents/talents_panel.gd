class_name TalentsPanel
extends CanvasLayer
## 天赋面板：当前职业专属树的节点购买/退还/整树洗点（全屏覆盖层，Esc 或按钮关闭）。
## 代码构建 UI（节点列表按角色动态生成，参考 dev_panel/character_create 先例）。

var _list_box: VBoxContainer
var _points_label: Label
var _respec_btn: Button


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
	box.add_theme_constant_override("separation", 10)
	scroll.add_child(box)

	var title := Label.new()
	title.text = "天赋"
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(1, 0.843, 0.369))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_points_label = Label.new()
	_points_label.add_theme_font_size_override("font_size", 22)
	_points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_points_label)

	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 6)
	box.add_child(_list_box)

	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 16)
	box.add_child(bottom)
	_respec_btn = Button.new()
	_respec_btn.custom_minimum_size = Vector2(320, 48)
	_respec_btn.pressed.connect(_on_respec)
	bottom.add_child(_respec_btn)
	var close := Button.new()
	close.text = "关闭（Esc）"
	close.custom_minimum_size = Vector2(220, 48)
	close.pressed.connect(close_panel)
	bottom.add_child(close)

	_rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()


func close_panel() -> void:
	SaveManager.save()
	queue_free()


func _rebuild() -> void:
	for c in _list_box.get_children():
		_list_box.remove_child(c)
		c.queue_free()
	var tree: Dictionary = GameTalents.get_tree_for(GameState.character_class)
	_points_label.text = "%s ｜ 可用技能点：%d ｜ 已投入：%d" % [
		tree.get("name", "天赋"), GameState.skill_points, GameState.talent_invested(),
	]
	_respec_btn.text = "整树重置（退还 %d 点 · 花费 %s G）" % [
		GameState.talent_invested(), Balance.format_number(GameState.talent_respec_cost()),
	]
	_respec_btn.disabled = GameState.talent_invested() <= 0 or GameState.money < GameState.talent_respec_cost()

	var gate := GameTalents.TREE_GATE
	var invested := GameState.talent_invested()
	for ring in [1, 2, 3, 4]:
		var gate_need := int(gate[clampi(ring, 1, 4) - 1])
		var ring_head := Label.new()
		if invested >= gate_need:
			ring_head.text = "—— 第 %d 层 ——" % ring
		else:
			ring_head.text = "—— 第 %d 层（需已投入 %d 点，当前 %d）——" % [ring, gate_need, invested]
		ring_head.add_theme_font_size_override("font_size", 19)
		ring_head.add_theme_color_override("font_color", Color(0.659, 0.624, 0.553))
		ring_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_list_box.add_child(ring_head)
		for n: Dictionary in tree.get("nodes", []):
			if int(n.get("ring", 1)) != ring:
				continue
			_list_box.add_child(_node_row(n))
			# 关键天赋的副作用说明随行展示
			if n.has("key") and str(n.get("tradeoff", "")) != "":
				var t := Label.new()
				t.text = "　　　　代价：%s" % n["tradeoff"]
				t.add_theme_font_size_override("font_size", 15)
				t.add_theme_color_override("font_color", Color(0.85, 0.55, 0.5))
				_list_box.add_child(t)
	_list_box.add_child(Control.new())  # 底部留白


func _node_row(n: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var rank := int(GameState.talents.get(n["id"], 0))
	var max_r := int(n.get("max", 1))
	var locked := GameState.talent_invested() < int(GameTalents.TREE_GATE[clampi(int(n.get("ring", 1)), 1, 4) - 1])
	var is_off := n.has("key_of")

	var name_l := Label.new()
	var state := "%d/%d" % [rank, max_r]
	if is_off and rank > 0:
		name_l.text = "　　↳ 副作用：%s" % str(n.get("mod", ""))
		name_l.add_theme_color_override("font_color", Color(0.85, 0.55, 0.5))
	else:
		name_l.text = "%s（%s）" % [n["name"], state]
		if n.has("key"):
			name_l.add_theme_color_override("font_color", Color(1, 0.843, 0.369))
	name_l.custom_minimum_size = Vector2(340, 0)
	name_l.add_theme_font_size_override("font_size", 19)
	row.add_child(name_l)

	var desc := Label.new()
	desc.text = str(n.get("desc", ""))
	desc.custom_minimum_size = Vector2(330, 0)
	desc.add_theme_font_size_override("font_size", 17)
	desc.add_theme_color_override("font_color", Color(0.909, 0.878, 0.812))
	row.add_child(desc)

	row.add_child(Control.new())  # 弹性空隙
	var buy := Button.new()
	if is_off:
		row.add_child(Control.new())  # 副作用行无购买
		row.add_child(Control.new())
		return row
	buy.text = "升级（1 点）"
	buy.custom_minimum_size = Vector2(130, 36)
	buy.disabled = locked or rank >= max_r or GameState.skill_points < 1
	buy.pressed.connect(func() -> void:
		GameState.talent_buy(n["id"])
		Sfx.play("level_up", 1.1)
		_rebuild())
	row.add_child(buy)
	var refund := Button.new()
	refund.text = "退还"
	refund.custom_minimum_size = Vector2(80, 36)
	refund.disabled = rank <= 0
	refund.pressed.connect(func() -> void:
		GameState.talent_refund(n["id"])
		_rebuild())
	row.add_child(refund)
	return row


func _on_respec() -> void:
	if GameState.talent_respec_all():
		Sfx.play("ui_open")
		_rebuild()
