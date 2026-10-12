class_name EquipmentPanel
extends CanvasLayer
## 装备面板（E1.5）：左侧 10 槽纸娃娃 + 右侧 30 格背包 + 详情/穿卸。
## 图标：assets/art/equipment/{type}_{quality}.png（美术会话产出，缺失时品级色块兜底）。

const SLOT_NAMES := {
	"main": "主手", "off": "副手", "helm": "头盔", "body": "身体", "shoulder": "肩膀",
	"legs": "护腿", "boots": "鞋", "ring_a": "戒指A", "ring_b": "戒指B", "trinket": "饰品",
}
const QUALITY_FILE := ["common", "fine", "rare", "legendary"]  # 粗品/普通/精良/史诗 → 美术命名

var _bag_btns := []            # 背包格按钮（30）
var _equip_btns := {}          # slot → 按钮
var _detail_name: Label
var _detail_body: RichTextLabel
var _bag_title: Label
var _glue_label: Label         # 树胶/精华持有（E2）
var _affix_box: VBoxContainer  # 洗练目标选择（E2 账单制锁1洗1）
var _wash_btn: Button
var _decompose_btn: Button
var _wash_sel := -1
var _sel_bag := -1
var _sel_slot := ""


func _ready() -> void:
	layer = 94
	_build_ui()
	_refresh()


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.82)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.11, 0.97)
	sb.border_color = Color(0.85, 0.72, 0.35)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 24.0
	sb.content_margin_right = 24.0
	sb.content_margin_top = 18.0
	sb.content_margin_bottom = 18.0
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var title := Label.new()
	title.text = "背 包 与 装 备"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	panel.add_child(title)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	panel.add_child(cols)

	# ---- 左：纸娃娃 10 槽 ----
	var doll := VBoxContainer.new()
	doll.add_theme_constant_override("separation", 8)
	cols.add_child(doll)
	var doll_title := Label.new()
	doll_title.text = "穿戴（10 槽）"
	doll_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	doll.add_child(doll_title)
	var doll_grid := GridContainer.new()
	doll_grid.columns = 2
	doll_grid.add_theme_constant_override("h_separation", 10)
	doll_grid.add_theme_constant_override("v_separation", 10)
	doll.add_child(doll_grid)
	for slot in GameEquipment.EQUIP_SLOTS:
		var cell := VBoxContainer.new()
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(92, 92)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_equip_slot.bind(slot))
		btn.tooltip_text = SLOT_NAMES[slot]
		_equip_btns[slot] = btn
		cell.add_child(btn)
		var lab := Label.new()
		lab.text = SLOT_NAMES[slot]
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.add_theme_font_size_override("font_size", 13)
		cell.add_child(lab)
		doll_grid.add_child(cell)

	# ---- 中：详情 ----
	var detail := VBoxContainer.new()
	detail.custom_minimum_size = Vector2(330, 0)
	cols.add_child(detail)
	_detail_name = Label.new()
	_detail_name.text = "（点击装备查看）"
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_name.add_theme_font_size_override("font_size", 19)
	_detail_name.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	detail.add_child(_detail_name)
	_detail_body = RichTextLabel.new()
	_detail_body.bbcode_enabled = true
	_detail_body.fit_content = true
	_detail_body.custom_minimum_size = Vector2(330, 330)
	detail.add_child(_detail_body)
	var act_row := HBoxContainer.new()
	detail.add_child(act_row)
	var wear_btn := Button.new()
	wear_btn.text = "穿 戴"
	wear_btn.custom_minimum_size = Vector2(0, 40)
	wear_btn.pressed.connect(_on_wear_pressed)
	act_row.add_child(wear_btn)
	var off_btn := Button.new()
	off_btn.text = "卸 下"
	off_btn.custom_minimum_size = Vector2(0, 40)
	off_btn.pressed.connect(_on_unequip_pressed)
	act_row.add_child(off_btn)
	# E2：分解 + 洗练（账单制锁1洗1）
	var dec_row := HBoxContainer.new()
	detail.add_child(dec_row)
	_decompose_btn = Button.new()
	_decompose_btn.text = "分 解"
	_decompose_btn.custom_minimum_size = Vector2(0, 36)
	_decompose_btn.pressed.connect(_on_decompose_pressed)
	dec_row.add_child(_decompose_btn)
	var dec_all := Button.new()
	dec_all.text = "一键分解粗/普"
	dec_all.custom_minimum_size = Vector2(0, 36)
	dec_all.pressed.connect(func() -> void:
		var n: int = GameState.decompose_all_common()
		Sfx.play("trade_sell" if n > 0 else "money_not_enough", 1.0, -4.0)
		if n > 0:
			_panel_toast("一键分解 %d 件（树胶已入账）" % n)
		_sel_bag = -1
		_refresh())
	dec_row.add_child(dec_all)
	_affix_box = VBoxContainer.new()
	_affix_box.add_theme_constant_override("separation", 4)
	detail.add_child(_affix_box)
	_wash_btn = Button.new()
	_wash_btn.text = "洗 练"
	_wash_btn.custom_minimum_size = Vector2(0, 36)
	_wash_btn.pressed.connect(_on_wash_pressed)
	detail.add_child(_wash_btn)

	# ---- 右：背包 6×5 ----
	var bag_box := VBoxContainer.new()
	bag_box.add_theme_constant_override("separation", 8)
	cols.add_child(bag_box)
	_bag_title = Label.new()
	_bag_title.text = "背包（0/%d）" % GameState.BAG_CAPACITY
	_bag_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bag_box.add_child(_bag_title)
	_glue_label = Label.new()
	_glue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_glue_label.add_theme_font_size_override("font_size", 14)
	_glue_label.add_theme_color_override("font_color", Color(0.65, 0.8, 0.6))
	bag_box.add_child(_glue_label)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	bag_box.add_child(grid)
	for i in GameState.BAG_CAPACITY:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(74, 74)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_bag_pressed.bind(i))
		grid.add_child(btn)
		_bag_btns.append(btn)

	var close := Button.new()
	close.text = "关 闭"
	close.custom_minimum_size = Vector2(0, 40)
	close.pressed.connect(queue_free)
	bag_box.add_child(close)


func _refresh() -> void:
	# 纸娃娃
	for slot in GameEquipment.EQUIP_SLOTS:
		var btn: Button = _equip_btns[slot]
		var item: Dictionary = GameState.equipped.get(slot, {})
		if item.is_empty():
			btn.icon = null
			btn.text = ""
			btn.modulate = Color(1, 1, 1, 0.35)
			btn.tooltip_text = SLOT_NAMES[slot] + "（空）"
		else:
			btn.icon = _icon_for(item)
			btn.expand_icon = true
			btn.modulate = Color.WHITE
			btn.tooltip_text = "%s\n%s" % [SLOT_NAMES[slot], _item_summary(item)]
	# 背包
	for i in GameState.BAG_CAPACITY:
		var btn: Button = _bag_btns[i]
		if i < GameState.bag.size():
			var item: Dictionary = GameState.bag[i]
			btn.icon = _icon_for(item)
			btn.expand_icon = true
			btn.modulate = Color.WHITE
			btn.tooltip_text = _item_summary(item)
		else:
			btn.icon = null
			btn.modulate = Color(1, 1, 1, 0.25)
			btn.tooltip_text = ""
	# 详情跟随选择
	if _sel_bag >= 0 and _sel_bag < GameState.bag.size():
		_show_detail(GameState.bag[_sel_bag], false)
	elif _sel_slot != "" and GameState.equipped.has(_sel_slot):
		_show_detail(GameState.equipped[_sel_slot], true)
	# 背包计数与货币
	_bag_title.text = "背包（%d/%d）" % [GameState.bag.size(), GameState.BAG_CAPACITY]
	_glue_label.text = "树胶 %d ｜ 精华 %d" % [GameState.glue, GameState.essence]
	# 洗练/分解可用性（仅背包件；洗练需选中一条词条）
	var bag_sel := _sel_bag >= 0 and _sel_bag < GameState.bag.size()
	_decompose_btn.visible = bag_sel
	_wash_btn.visible = bag_sel and _wash_sel >= 0
	if bag_sel:
		var wi: Dictionary = GameState.bag[_sel_bag]
		_wash_btn.text = "洗练该词条（树胶 %d）" % GameState.wash_cost(wi)
		_wash_btn.disabled = GameState.glue < GameState.wash_cost(wi)
	_rebuild_affix_buttons()


func _show_detail(item: Dictionary, worn: bool) -> void:
	var q := int(item.get("quality", 0))
	var qname: String = GameEquipment.QUALITY_NAMES[q]
	var col: Color = GameEquipment.QUALITY_COLORS[q]
	var tag := "  已穿戴" if worn else ""
	_detail_name.text = "%s\n%s%s" % [
		str(item.get("name", "?")), qname, "  太古" if bool(item.get("ancient", false)) else ""]
	_detail_name.add_theme_color_override("font_color", col)
	var lines := []
	lines.append("部位：%s ｜ 层级 L%d" % [SLOT_NAMES.get(str(item["slot"]), str(item["slot"])), int(item.get("tier", 1))])
	for af in item.get("affixes", []):
		var mark := " [color=#ffd75e]太古[/color]" if bool(af.get("ancient", false)) else ""
		lines.append("· %s%s" % [GameEquipment.affix_text(af), mark])
	var lid := str(item.get("legendary", ""))
	if lid != "":
		var leg := GameEquipment.legendary_def(lid)
		for ef in leg.get("special", []):
			lines.append("[color=#ffd75e]★ 祖品：%s %+.0f%%[/color]" % [str(ef.get("key", "")), float(ef.get("per", 0.0)) * 100.0])
	if worn:
		lines.append("")
		lines.append("[color=#8a93ad]点击「卸下」放回背包[/color]")
	else:
		var affixes_n := (item.get("affixes", []) as Array).size()
		if not GameEquipment.can_wear(GameState.character_class, item):
			lines.append("[color=#ff8080]与当前职业不符，无法穿戴[/color]")
		if affixes_n > 0:
			lines.append("[color=#8a93ad]点下方词条选中后可洗练（树胶账单制 ×2）｜ 分解换树胶/精华[/color]")
	_detail_body.text = "\n".join(lines)


func _item_summary(item: Dictionary) -> String:
	var parts := [GameEquipment.QUALITY_NAMES[int(item.get("quality", 0))]]
	for af in item.get("affixes", []):
		parts.append(GameEquipment.affix_text(af))
	return str(item.get("name", "?")) + "｜" + "；".join(parts)


func _icon_for(item: Dictionary) -> Texture2D:
	var q := clampi(int(item.get("quality", 0)), 0, 3)
	var slot := str(item.get("slot", ""))
	var key := ""
	match slot:
		"main":
			key = "%s_%s" % [str(item.get("type", "sword")), QUALITY_FILE[q]]
		"off":
			key = "%s_%s" % [str(item.get("type", "shield")), QUALITY_FILE[q]]
		"trinket":
			key = "amulet_%s" % QUALITY_FILE[q]
		"ring_a", "ring_b", "ring":
			key = "ring_%s" % QUALITY_FILE[q]
		_:
			var weight := str(item.get("weight", item.get("type", "cloth")))
			var base: String = {"helm": "helm", "body": "chest", "shoulder": "shoulders", "legs": "legs", "boots": "boots"}.get(slot, "chest")
			key = "%s_%s_%s" % [base, weight, QUALITY_FILE[q]]
	var path := "res://assets/art/equipment/%s.png" % key
	if ResourceLoader.exists(path):
		return load(path)
	return null  # 缺图：按钮显示品级色底（modulate 兜底）


func _on_bag_pressed(idx: int) -> void:
	_sel_bag = idx
	_sel_slot = ""
	_wash_sel = -1
	_refresh()


func _on_equip_slot(slot: String) -> void:
	_sel_slot = slot
	_sel_bag = -1
	_wash_sel = -1
	_refresh()


func _on_wear_pressed() -> void:
	if _sel_bag < 0:
		return
	Sfx.play("ui_click")
	var err: String = GameState.equip_from_bag(_sel_bag)
	if err != "":
		Sfx.play("money_not_enough", 1.0, -6.0)
	else:
		Sfx.play("equip_on")  # 装备上身专属音（音频会话 2026-10-11）
	_sel_bag = -1
	_refresh()


func _on_unequip_pressed() -> void:
	if _sel_slot == "":
		return
	Sfx.play("equip_off")  # 卸下布料软扑（音频会话 2026-10-11）
	GameState.unequip(_sel_slot)
	_sel_slot = ""
	_refresh()


## 洗练目标选择：为选中背包件的每条词条生成按钮（E2 账单制锁1洗1；太古不可洗）
func _rebuild_affix_buttons() -> void:
	for c in _affix_box.get_children():
		c.queue_free()
	if not (_sel_bag >= 0 and _sel_bag < GameState.bag.size()):
		return
	var item: Dictionary = GameState.bag[_sel_bag]
	var affixes: Array = item.get("affixes", [])
	for i in affixes.size():
		var idx := i
		var af: Dictionary = affixes[i]
		var btn := Button.new()
		btn.text = "%d. %s%s" % [i + 1, GameEquipment.affix_text(af),
			"  [太古·不可洗]" if bool(af.get("ancient", false)) else ""]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 14)
		btn.disabled = bool(af.get("ancient", false))
		if _wash_sel == idx and not btn.disabled:
			btn.modulate = Color(0.6, 1.0, 0.6)
		btn.pressed.connect(_on_affix_pick.bind(idx))
		_affix_box.add_child(btn)


func _on_affix_pick(idx: int) -> void:
	_wash_sel = idx if _wash_sel != idx else -1
	_refresh()


func _on_wash_pressed() -> void:
	if _wash_sel < 0:
		return
	Sfx.play("ui_click")
	var err: String = GameState.wash_affix(_sel_bag, _wash_sel)
	if err != "":
		Sfx.play("money_not_enough", 1.0, -6.0)
	else:
		Sfx.play("line_up")  # 洗练完成（复用训练线上行拨弦）
	_wash_sel = -1
	_refresh()


func _on_decompose_pressed() -> void:
	if _sel_bag < 0:
		return
	var r: Dictionary = GameState.decompose(_sel_bag)
	if not bool(r.get("ok", false)):
		Sfx.play("money_not_enough", 1.0, -6.0)
		_panel_toast("无法分解")
	elif int(r.get("glue", 0)) > 0 and int(r.get("essence", 0)) > 0:
		Sfx.play("decompose_glue")
		_panel_toast("祖品分解：树胶 +%d ｜ 精华 +%d" % [int(r["glue"]), int(r["essence"])])
	elif int(r.get("glue", 0)) > 0:
		Sfx.play("decompose_glue")
		_panel_toast("分解获得 树胶 +%d" % int(r["glue"]))
	else:
		Sfx.play("essence_gain")
		_panel_toast("分解获得 精华 +%d" % int(r["essence"]))
	_sel_bag = -1
	_wash_sel = -1
	_refresh()


## 面板内浮字反馈（顶部居中，2.2s 渐隐）——分解/洗练结果的可见反馈
func _panel_toast(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 8)
	l.set_anchors_preset(Control.PRESET_TOP_WIDE)
	l.position.y = -34.0
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	var tw := create_tween()
	tw.tween_interval(1.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.45)
	tw.tween_callback(l.queue_free)
