class_name TalentsPanel
extends CanvasLayer
## 天赋面板：竖向天赋树（D4 式：树根在下、关键三选一在顶）。
## 节点 = 图标按钮（效果图标 / 关键像素图），连线随点亮状态变色；
## 点击节点 → 底部详情栏购买/退还。Esc 或按钮关闭（关闭时自动存档）。
## 美术资产：eff_*.png（效果图标）、talents/<节点id>.png（关键像素图）、bg_talent.png（背景）。

const NODE_SIZE := 84.0
const EFF_ICON := {
	"battle_damage": "eff_damage", "weakness": "eff_weakness", "income": "eff_income",
	"train_cost": "eff_train", "upgrade_cost": "eff_train", "bounty": "eff_bounty",
	"ep": "eff_ep", "steps": "eff_steps", "chain_bonus": "eff_chain",
	"fruit": "eff_fruit", "fee": "eff_bounty",
}
# 竖树布局（树区局部坐标）：圈1 底部 → 圈4 顶部
const POS := {
	1: [Vector2(290, 520), Vector2(590, 520), Vector2(890, 520)],
	2: [Vector2(290, 380), Vector2(590, 380), Vector2(890, 380)],
	3: [Vector2(590, 240)],
	4: [Vector2(290, 110), Vector2(590, 110), Vector2(890, 110)],
}

var _tree_area: Control
var _node_btns := {}
var _node_rank := {}
var _node_meta := {}
var _pos_id := {}   # 坐标 -> 节点id（连线点亮判断用）
var _points_label: Label
var _respec_btn: Button
var _detail_name: Label
var _detail_desc: Label
var _detail_tradeoff: Label
var _buy_btn: Button
var _refund_btn: Button
var _sel_id := ""
var _sb_locked: StyleBoxFlat
var _sb_avail: StyleBoxFlat
var _sb_partial: StyleBoxFlat
var _sb_maxed: StyleBoxFlat


func _ready() -> void:
	layer = 95
	_make_styleboxes()

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.82)
	add_child(dim)

	var tex_path := "res://assets/art/bg/bg_talent.png"
	if ResourceLoader.exists(tex_path):
		var art := TextureRect.new()
		art.texture = load(tex_path)
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		art.self_modulate = Color(1, 1, 1, 0.30)
		add_child(art)

	var title := Label.new()
	title.text = "天赋 · %s" % GameTalents.get_tree_for(GameState.character_class).get("name", "")
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(1, 0.843, 0.369))
	add_child(title)

	_tree_area = Control.new()
	_tree_area.set_anchors_preset(Control.PRESET_CENTER)
	_tree_area.offset_left = -590
	_tree_area.offset_right = 590
	_tree_area.offset_top = -420
	_tree_area.offset_bottom = 200
	_tree_area.draw.connect(_on_tree_draw)
	add_child(_tree_area)

	_build_nodes()

	_points_label = Label.new()
	_points_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_points_label.offset_top = 52
	_points_label.add_theme_font_size_override("font_size", 21)
	_points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_points_label)

	var detail := PanelContainer.new()
	detail.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	detail.offset_left = -590
	detail.offset_right = 590
	detail.offset_top = -216
	detail.offset_bottom = -56
	add_child(detail)
	var dbox := VBoxContainer.new()
	dbox.add_theme_constant_override("separation", 4)
	detail.add_child(dbox)
	_detail_name = Label.new()
	_detail_name.add_theme_font_size_override("font_size", 20)
	_detail_name.add_theme_color_override("font_color", Color(1, 0.843, 0.369))
	dbox.add_child(_detail_name)
	_detail_desc = Label.new()
	_detail_desc.add_theme_font_size_override("font_size", 17)
	_detail_desc.add_theme_color_override("font_color", Color(0.909, 0.878, 0.812))
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dbox.add_child(_detail_desc)
	_detail_tradeoff = Label.new()
	_detail_tradeoff.add_theme_font_size_override("font_size", 15)
	_detail_tradeoff.add_theme_color_override("font_color", Color(0.85, 0.55, 0.5))
	dbox.add_child(_detail_tradeoff)
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	dbox.add_child(btn_row)
	_buy_btn = Button.new()
	_buy_btn.custom_minimum_size = Vector2(180, 40)
	_buy_btn.pressed.connect(_on_buy)
	btn_row.add_child(_buy_btn)
	_refund_btn = Button.new()
	_refund_btn.custom_minimum_size = Vector2(140, 40)
	_refund_btn.pressed.connect(_on_refund)
	btn_row.add_child(_refund_btn)
	_buy_btn.disabled = true
	_refund_btn.disabled = true

	var bottom := HBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.offset_left = -400
	bottom.offset_right = 400
	bottom.offset_top = -50
	bottom.offset_bottom = -6
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 16)
	add_child(bottom)
	_respec_btn = Button.new()
	_respec_btn.custom_minimum_size = Vector2(320, 46)
	_respec_btn.pressed.connect(_on_respec)
	bottom.add_child(_respec_btn)
	var close := Button.new()
	close.text = "关闭（Esc）"
	close.custom_minimum_size = Vector2(220, 46)
	close.pressed.connect(close_panel)
	bottom.add_child(close)

	_refresh_all()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()


func close_panel() -> void:
	SaveManager.save()
	queue_free()


# ---------- 构建 ----------

func _make_styleboxes() -> void:
	_sb_locked = StyleBoxFlat.new()
	_sb_locked.bg_color = Color("2a2438")
	_sb_locked.set_border_width_all(2)
	_sb_locked.border_color = Color("4a4060")
	_sb_locked.set_corner_radius_all(14)
	_sb_avail = _sb_locked.duplicate()
	_sb_avail.bg_color = Color("241d33")
	_sb_avail.border_color = Color("e8e0cf")
	_sb_partial = _sb_locked.duplicate()
	_sb_partial.bg_color = Color("241d33")
	_sb_partial.border_color = Color("f2c94c")
	_sb_maxed = _sb_locked.duplicate()
	_sb_maxed.bg_color = Color("3a2f55")
	_sb_maxed.border_color = Color("f2c94c")
	_sb_maxed.set_border_width_all(4)


func _build_nodes() -> void:
	_tree_area.add_theme_constant_override("separation", 0)
	var tree: Dictionary = GameTalents.get_tree_for(GameState.character_class)
	var ring_count := {}
	for n: Dictionary in tree.get("nodes", []):
		var ring := int(n.get("ring", 1))
		if n.has("key_of"):
			continue  # 副作用副节点：不占树位（详情栏随关键节点显示）
		var idx := int(ring_count.get(ring, 0))
		ring_count[ring] = idx + 1
		var slots: Array = POS.get(ring, [Vector2(590, 380)])
		var pos: Vector2 = slots[mini(idx, slots.size() - 1)]
		var b := Button.new()
		b.position = pos - Vector2(NODE_SIZE, NODE_SIZE) / 2.0
		b.size = Vector2(NODE_SIZE, NODE_SIZE)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_node_pressed.bind(n["id"]))
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		# 节点图标：普通=效果图标，关键=专属像素图（56px 最近邻）
		var tex := _icon_for(n)
		if tex:
			var img: Image = tex.get_image()
			if img.is_compressed():
				img.decompress()
			img.resize(56, 56, Image.INTERPOLATE_NEAREST)
			b.icon = ImageTexture.create_from_image(img)
		_tree_area.add_child(b)
		_node_btns[n["id"]] = b
		_node_meta[n["id"]] = n
		_pos_id[pos] = n["id"]
		var rank_l := Label.new()
		rank_l.position = pos + Vector2(-40, NODE_SIZE / 2.0 + 2)
		rank_l.size = Vector2(80, 16)
		rank_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rank_l.add_theme_font_size_override("font_size", 14)
		_tree_area.add_child(rank_l)
		_node_rank[n["id"]] = rank_l
		var name_l := Label.new()
		name_l.position = pos + Vector2(-80, NODE_SIZE / 2.0 + 20)
		name_l.size = Vector2(160, 18)
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_l.add_theme_font_size_override("font_size", 15)
		name_l.add_theme_color_override("font_color", Color(0.909, 0.878, 0.812))
		name_l.text = n["name"]
		_tree_area.add_child(name_l)
	if not _tree_area.draw.is_connected(_on_tree_draw):
		_tree_area.draw.connect(_on_tree_draw)


func _icon_for(n: Dictionary) -> Texture2D:
	if n.has("key"):
		var p := "res://assets/art/talents/%s.png" % n["id"]
		if ResourceLoader.exists(p):
			return load(p)
	var mod := str(n.get("mod", ""))
	if EFF_ICON.has(mod):
		var e := "res://assets/art/ui/%s.png" % EFF_ICON[mod]
		if ResourceLoader.exists(e):
			return load(e)
	return null


# ---------- 状态刷新 ----------

func _refresh_all() -> void:
	var tree: Dictionary = GameTalents.get_tree_for(GameState.character_class)
	_points_label.text = "%s ｜ 可用技能点：%d ｜ 已投入：%d" % [
		tree.get("name", "天赋"), GameState.skill_points, GameState.talent_invested(),
	]
	_respec_btn.text = "整树重置（退还 %d 点 · 花费 %s G）" % [
		GameState.talent_invested(), Balance.format_number(GameState.talent_respec_cost()),
	]
	_respec_btn.disabled = GameState.talent_invested() <= 0 or GameState.money < GameState.talent_respec_cost()
	var gate: Array = GameTalents.TREE_GATE
	var invested := GameState.talent_invested()
	for id in _node_btns:
		var n: Dictionary = _node_meta[id]
		var rank := int(GameState.talents.get(id, 0))
		var max_r := int(n.get("max", 1))
		var ring := int(n.get("ring", 1))
		var locked := invested < int(gate[clampi(ring, 1, 4) - 1])
		var btn: Button = _node_btns[id]
		btn.disabled = locked
		if rank >= max_r:
			btn.add_theme_stylebox_override("normal", _sb_maxed)
		elif rank > 0:
			btn.add_theme_stylebox_override("normal", _sb_partial)
		elif locked:
			btn.add_theme_stylebox_override("normal", _sb_locked)
		else:
			btn.add_theme_stylebox_override("normal", _sb_avail)
		btn.modulate = Color(0.55, 0.55, 0.62) if locked else Color.WHITE
		var rl: Label = _node_rank[id]
		rl.text = "MAX" if rank >= max_r else "%d/%d" % [rank, max_r]
		rl.add_theme_color_override("font_color",
			Color(1, 0.843, 0.369) if rank >= max_r else Color(0.909, 0.878, 0.812))
		if rank > 0:
			btn.tooltip_text = "%s（%d/%d）\n%s" % [n["name"], rank, max_r, n.get("desc", "")]
		else:
			btn.tooltip_text = "%s\n%s" % [n["name"], n.get("desc", "")]
	_tree_area.queue_redraw()
	_refresh_detail()


func _refresh_detail() -> void:
	if _sel_id == "" or not _node_meta.has(_sel_id):
		_detail_name.text = "点击节点查看详情（购买在下方）"
		_detail_desc.text = ""
		_detail_tradeoff.text = ""
		_buy_btn.disabled = true
		_refund_btn.disabled = true
		_buy_btn.text = "升级（1 点）"
		return
	var n: Dictionary = _node_meta[_sel_id]
	var rank := int(GameState.talents.get(_sel_id, 0))
	var max_r := int(n.get("max", 1))
	var gate: Array = GameTalents.TREE_GATE
	var locked := GameState.talent_invested() < int(gate[clampi(int(n.get("ring", 1)), 1, 4) - 1])
	_detail_name.text = "%s · %d/%d%s" % [n["name"], rank, max_r, "　★ 关键" if n.has("key") else ""]
	_detail_desc.text = str(n.get("desc", ""))
	var tradeoff := ""
	if n.has("key") and str(n.get("tradeoff", "")) != "" and rank > 0:
		tradeoff = "代价：%s" % n["tradeoff"]
	_detail_tradeoff.text = tradeoff
	_buy_btn.text = "升级（1 点）"
	_buy_btn.disabled = locked or rank >= max_r or GameState.skill_points < 1
	_refund_btn.disabled = rank <= 0


# ---------- 交互 ----------

func _on_node_pressed(id: String) -> void:
	_sel_id = id
	Sfx.play("ui_open", 0.8)
	_refresh_detail()


func _on_buy() -> void:
	if _sel_id == "":
		return
	if GameState.talent_buy(_sel_id):
		Sfx.play("level_up", 1.1)
	_refresh_all()


func _on_refund() -> void:
	if _sel_id == "":
		return
	GameState.talent_refund(_sel_id)
	_refresh_all()


func _on_respec() -> void:
	if GameState.talent_respec_all():
		Sfx.play("ui_open")
		_refresh_all()


# ---------- 连线绘制 ----------

func _on_tree_draw() -> void:
	var gate: Array = GameTalents.TREE_GATE
	var invested := GameState.talent_invested()
	# 层圈门槛标注
	var font := _tree_area.get_theme_default_font()
	if font:
		for ring in [1, 2, 3, 4]:
			var y: float = POS[ring][0].y - 62.0 if ring != 1 else POS[1][0].y + 62.0
			var unlocked := invested >= int(gate[ring - 1])
			var txt := "第 %d 层 · 需投入 %d%s" % [ring, gate[ring - 1], "" if unlocked else "（未解锁）"]
			_tree_area.draw_string(font, Vector2(20, y), txt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
				Color(0.909, 0.878, 0.812, 0.9) if unlocked else Color(0.55, 0.5, 0.45, 0.9))
	# 连线（目标节点已点亮=金；层圈解锁但未点=浅奶油；层圈锁定=暗虚线）
	_link(_tree_area, Vector2(590, 596), POS[1][0], _lit_pos(POS[1][0]))
	_link(_tree_area, Vector2(590, 596), POS[1][1], _lit_pos(POS[1][1]))
	_link(_tree_area, Vector2(590, 596), POS[1][2], _lit_pos(POS[1][2]))
	for i in 3:
		_link(_tree_area, POS[1][i], POS[2][i], _lit_pos(POS[2][i]))
	_link(_tree_area, POS[2][1], POS[3][0], _lit_pos(POS[3][0]))
	for i in 3:
		_link(_tree_area, POS[3][0], POS[4][i], _lit_pos(POS[4][i]))


func _lit_pos(pos: Vector2) -> bool:
	## 连线亮起条件：目标节点已有 rank（层圈未解锁时 rank 必为 0，天然满足）
	var id: String = _pos_id.get(pos, "")
	return id != "" and int(GameState.talents.get(id, 0)) > 0


func _link(area: Control, a: Vector2, b: Vector2, lit: bool) -> void:
	if lit:
		area.draw_line(a, b, Color("f2c94c"), 4.0)
	else:
		var total := a.distance_to(b)
		if total <= 0:
			return
		var dir := (b - a) / total
		var t := 0.0
		while t < total:
			var e := minf(t + 7.0, total)
			area.draw_line(a + dir * t, a + dir * e, Color(0.45, 0.42, 0.52), 2.0)
			t = e + 6.0
