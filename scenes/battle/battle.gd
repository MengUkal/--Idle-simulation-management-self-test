extends Control
## M2 冒险界面：三消核心（7×7 / 6 元素 / 相邻交换 / 三连消除 / 连锁 / 步数倒数）。
## 战斗包装（正式怪物表与赏金）待数值审定，当前用"训练木桩"占位：
##   伤害 = 消除方块数（占位公式，属性克制未启用）。

const COL_BG := Color("191322")
const COL_GOLD := Color("ffd75e")
const COL_TEXT := Color("e8e0cf")
const COL_DIM := Color("a89f8d")
const COL_PANEL := Color("241d33")
const TILE := 84.0

var board: Match3Board
var steps_left := 0
var selected := Vector2i(-1, -1)
var tiles: Array = []            # tiles[行][列] = Button
var _tile_styles: Array = []     # 每种元素一枚 StyleBoxFlat 缓存

# 本局统计
var total_cleared := 0
var max_chain := 0
var total_damage := 0
var kills := 0
var dummy_hp := Balance.DUMMY_HP

var _steps_label: Label
var _stat_cleared: Label
var _stat_chain: Label
var _stat_damage: Label
var _stat_kills: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _result_panel: Control
var _result_stats: Label
var _toast: Label
var _toast_tween: Tween


func _ready() -> void:
	board = Match3Board.new(Balance.BOARD_SIZE, Balance.ELEMENT_KINDS)
	board.setup()
	board.ensure_playable()
	steps_left = Balance.battle_steps(GameState.level)
	_build_background()
	_build_enemy_panel()
	_build_board()
	_build_side_panel()
	_build_result_panel()
	_build_toast()
	_refresh_board()
	_refresh_hud()


# ---------- UI 构建 ----------

func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)


func _build_enemy_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	panel.offset_left = 80
	panel.offset_right = 80 + 360
	panel.offset_top = -240
	panel.offset_bottom = 240
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.set_corner_radius_all(16)
	sb.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	_make_label(box, "训练木桩（占位）", 24, COL_GOLD)
	var portrait := ColorRect.new()
	portrait.custom_minimum_size = Vector2(0, 170)
	portrait.color = Color("3a3350")
	box.add_child(portrait)
	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size = Vector2(0, 26)
	_hp_bar.show_percentage = false
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color("151020")
	bar_bg.set_corner_radius_all(6)
	var bar_fg := StyleBoxFlat.new()
	bar_fg.bg_color = Color("d95050")
	bar_fg.set_corner_radius_all(6)
	_hp_bar.add_theme_stylebox_override("background", bar_bg)
	_hp_bar.add_theme_stylebox_override("fill", bar_fg)
	box.add_child(_hp_bar)
	_hp_label = _make_label(box, "", 16, COL_DIM)
	_make_label(box, "正式怪物与赏金\n待数值表审定（M2 第二步）", 14, COL_DIM)


func _build_board() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var grid_box := GridContainer.new()
	grid_box.columns = Balance.BOARD_SIZE
	grid_box.add_theme_constant_override("h_separation", 4)
	grid_box.add_theme_constant_override("v_separation", 4)
	center.add_child(grid_box)
	tiles.clear()
	for r in Balance.BOARD_SIZE:
		var row := []
		for c in Balance.BOARD_SIZE:
			var b := Button.new()
			b.custom_minimum_size = Vector2(TILE, TILE)
			b.add_theme_font_size_override("font_size", 40)
			b.focus_mode = Control.FOCUS_NONE
			b.pressed.connect(_on_tile_pressed.bind(Vector2i(c, r)))
			grid_box.add_child(b)
			row.append(b)
		tiles.append(row)


func _build_side_panel() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	box.offset_left = -80 - 380
	box.offset_right = -80
	box.offset_top = -240
	box.offset_bottom = 240
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	_make_label(box, "剩余步数", 22, COL_DIM)
	_steps_label = _make_label(box, "", 72, COL_GOLD)
	_stat_cleared = _make_label(box, "", 20)
	_stat_chain = _make_label(box, "", 20)
	_stat_damage = _make_label(box, "", 20)
	_stat_kills = _make_label(box, "", 20)
	var hint := _make_label(box, "点选相邻两块交换；三连即消除并造成攻击", 15, COL_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var retreat := Button.new()
	retreat.text = "撤退（返回主界面）"
	retreat.custom_minimum_size = Vector2(380, 52)
	retreat.add_theme_font_size_override("font_size", 20)
	retreat.pressed.connect(_on_retreat_pressed)
	box.add_child(retreat)


func _build_result_panel() -> void:
	_result_panel = CenterContainer.new()
	_result_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_panel.visible = false
	add_child(_result_panel)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.set_corner_radius_all(16)
	sb.set_content_margin_all(32)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(600, 0)
	_result_panel.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	_make_label(box, "本场冒险结束", 32, COL_GOLD)
	_result_stats = _make_label(box, "", 20)
	_make_label(box, "赏金结算将在怪物表审定后加入", 15, COL_DIM)
	var back := Button.new()
	back.text = "返回主界面"
	back.custom_minimum_size = Vector2(220, 52)
	back.add_theme_font_size_override("font_size", 20)
	back.pressed.connect(_on_retreat_pressed)
	box.add_child(back)


func _build_toast() -> void:
	_toast = _make_label(self, "", 24, COL_GOLD)
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.offset_left = -500
	_toast.offset_right = 500
	_toast.offset_top = -60
	_toast.offset_bottom = -24
	_toast.visible = false


func _make_label(parent: Node, text: String, font_size: int, color: Color = COL_TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


# ---------- 交互 ----------

func _on_tile_pressed(cell: Vector2i) -> void:
	if steps_left <= 0:
		return
	if selected == Vector2i(-1, -1):
		selected = cell
	elif selected == cell:
		selected = Vector2i(-1, -1)
	elif Match3Board.are_adjacent(selected, cell):
		_try_move(selected, cell)
		selected = Vector2i(-1, -1)
	else:
		selected = cell
	_refresh_board()


func _try_move(a: Vector2i, b: Vector2i) -> void:
	var report := board.try_swap(a, b)
	if not report.get("ok", false):
		return  # 无效交换：棋盘已自动还原，静默忽略
	steps_left -= 1
	var cleared: Array = report["cleared"]
	var chains: int = report["chains"]
	total_cleared += cleared.size()
	max_chain = maxi(max_chain, chains)
	var damage := cleared.size()  # [占位] 伤害 = 消除数；属性克制随怪物表启用
	total_damage += damage
	dummy_hp -= damage
	while dummy_hp <= 0:
		kills += 1
		dummy_hp += Balance.DUMMY_HP
	if kills > 0:
		_show_toast("已击倒 %d 个训练木桩" % kills)
	if steps_left <= 0:
		_show_result()
	if board.ensure_playable():
		_show_toast("无可行交换，棋盘已重洗")
	_refresh_board()
	_refresh_hud()


func _on_retreat_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")


# ---------- 刷新 ----------

func _refresh_board() -> void:
	for r in Balance.BOARD_SIZE:
		for c in Balance.BOARD_SIZE:
			var b: Button = tiles[r][c]
			var v: int = board.grid[r][c]
			b.text = Balance.ELEMENT_NAMES[v]
			b.add_theme_stylebox_override("normal", _tile_style(v))
			b.add_theme_color_override("font_color", Balance.ELEMENT_TEXT_COLORS[v])
			b.modulate = Color(1.4, 1.4, 1.15) if selected == Vector2i(c, r) else Color.WHITE


func _refresh_hud() -> void:
	_steps_label.text = str(steps_left)
	_stat_cleared.text = "消除方块：%d" % total_cleared
	_stat_chain.text = "最大连锁：%d" % max_chain
	_stat_damage.text = "总输出：%d" % total_damage
	_stat_kills.text = "击倒木桩：%d" % kills
	_hp_bar.max_value = Balance.DUMMY_HP
	_hp_bar.value = dummy_hp
	_hp_label.text = "HP %d / %d" % [dummy_hp, Balance.DUMMY_HP]


func _tile_style(element: int) -> StyleBoxFlat:
	while _tile_styles.size() <= element:
		var i := _tile_styles.size()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Balance.ELEMENT_COLORS[i]
		sb.set_corner_radius_all(10)
		_tile_styles.append(sb)
	return _tile_styles[element]


func _show_result() -> void:
	_result_stats.text = "总输出 %d ｜ 消除 %d 块 ｜ 最大连锁 %d ｜ 击倒木桩 %d" % [
		total_damage, total_cleared, max_chain, kills,
	]
	_result_panel.visible = true


func _show_toast(text: String) -> void:
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.text = text
	_toast.modulate.a = 1.0
	_toast.visible = true
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.0)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)
	_toast_tween.tween_callback(_hide_toast)


func _hide_toast() -> void:
	_toast.visible = false
	_toast.modulate.a = 1.0
