class_name KennelPanel
extends CanvasLayer
## 树根兽栏（P-b 伙伴一期）：图鉴 28 格 + 看板位选择。
## 已孵化：显示被动/数量/品质；未收录：暗格。点已孵化格 = 设为看板位（被动 ×2）。

const ELEM_NAMES := ["火", "水", "風", "土", "光", "闇"]

var _cells := {}          # 怪物名 → 按钮
var _board_label: Label


func _ready() -> void:
	layer = 94
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
	sb.content_margin_left = 22.0
	sb.content_margin_right = 22.0
	sb.content_margin_top = 14.0
	sb.content_margin_bottom = 14.0
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "树 根 兽 栏"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	box.add_child(title)
	_board_label = Label.new()
	_board_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_board_label.add_theme_font_size_override("font_size", 15)
	box.add_child(_board_label)
	var hint := Label.new()
	hint.text = "点已收录的伙伴设为看板位（被动 ×2）；全员常驻被动自动生效"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.62, 0.6, 0.54))
	box.add_child(hint)
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for pname in GamePets.PETS.keys():
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(150, 56)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_pet_pressed.bind(str(pname)))
		grid.add_child(btn)
		_cells[str(pname)] = btn
	var close := Button.new()
	close.text = "关 闭"
	close.custom_minimum_size = Vector2(0, 38)
	close.pressed.connect(queue_free)
	box.add_child(close)
	_refresh()


func _refresh() -> void:
	var lit := 0
	for pname in GamePets.PETS.keys():
		var btn: Button = _cells[pname]
		var rec: Dictionary = GameState.pets.get(pname, {})
		var pd := GamePets.pet_def(pname)
		if rec.is_empty():
			btn.text = "%s\n未收录" % pname
			btn.modulate = Color(1, 1, 1, 0.3)
			btn.tooltip_text = ""
		else:
			lit += 1
			var q := int(rec.get("quality", 0))
			var is_board: bool = str(GameState.pet_board) == pname
			btn.text = "%s\n%s %s%s" % [
				pname, GameEquipment.QUALITY_NAMES[q],
				"×%d" % int(rec.get("count", 1)), "  ★看板" if is_board else ""]
			btn.modulate = Color.WHITE
			btn.tooltip_text = "被动：" + GamePets.passive_text(pname)
	_board_label.text = "已收录 %d / %d ｜ 看板位：%s" % [
		lit, GamePets.PETS.size(),
		str(GameState.pet_board) if str(GameState.pet_board) != "" else "（空）"]


func _on_pet_pressed(pname: String) -> void:
	if GameState.set_pet_board(pname):
		Sfx.play("ui_click")
	_refresh()
