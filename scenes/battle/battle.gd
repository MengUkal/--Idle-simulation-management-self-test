extends Control
## M2 冒险界面：三消战斗（一场一只怪）。
## 规则【已拍板】：每次消除 = 一次攻击；命中弱点属性伤害×2；连锁第 n 波伤害 ×(1+0.2×(n-1))；
## 步数内击杀 → 获得赏金；步数耗尽未击杀 → 无赏金。
## 多线成长：消除方块获得元素精华（弱点块 ×2）；攻击/赏金线倍率在此生效。

const COL_BG := Color("191322")
const COL_GOLD := Color("ffd75e")
const COL_TEXT := Color("e8e0cf")
const COL_DIM := Color("a89f8d")
const COL_PANEL := Color("241d33")
const TILE := 84.0

var board: Match3Board
var monster: Dictionary = {}
var monster_hp := 0.0
var monster_hp_max := 1
var defeated := false
var battle_over := false
var elapsed := 0.0
var steps_left := 0
var selected := Vector2i(-1, -1)
var tiles: Array = []
var _tile_styles: Array = []

# 本局统计
var total_cleared := 0
var max_chain := 0
var total_damage := 0
var session_ep := 0

var _steps_label: Label
var _stat_cleared: Label
var _stat_chain: Label
var _stat_damage: Label
var _stat_ep: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _enemy_name: Label
var _result_panel: Control
var _result_title: Label
var _result_stats: Label
var _retreat_confirm: Control
var _toast: Label
var _toast_tween: Tween
var _bird_sb: StyleBoxFlat
var _special_style_cache := {}


func _process(delta: float) -> void:
	if not battle_over:
		elapsed += delta


func _ready() -> void:
	board = Match3Board.new(Balance.BOARD_SIZE, Balance.ELEMENT_KINDS)
	board.setup()
	board.ensure_playable()
	steps_left = Balance.battle_steps(GameState.level)
	_roll_monster()
	_build_background()
	_build_enemy_panel()
	_build_board()
	_build_side_panel()
	_build_result_panel()
	_build_retreat_confirm()
	_build_toast()
	_refresh_board()
	_refresh_hud()
	if monster.get("elite", false):
		_show_toast("遭遇精英：%s！" % monster["name"])
	if OS.is_debug_build():
		add_child(DevPanel.new())  # 开发修改器（F1 开关），release 导出自动不存在


func _roll_monster() -> void:
	## 怪物池按当前所在层切换（在哪层冒险，遇哪层的怪）
	if randf() < Balance.ELITE_CHANCE:
		monster = Balance.monster_elite(GameState.floor_index).duplicate()
		monster["elite"] = true
	else:
		var pool: Array = Balance.monster_pool(GameState.floor_index)
		monster = pool[randi() % pool.size()].duplicate()
	monster_hp_max = int(monster["hp"])
	monster_hp = float(monster_hp_max)


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
	_enemy_name = _make_label(box, "", 24, COL_GOLD)
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
	_make_label(box, "消除弱属性方块：伤害与精华双倍\n打不过也可以直接撤退", 14, COL_DIM)


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
	_stat_ep = _make_label(box, "", 20)
	var hint := _make_label(box, "四连/L形/五连生成特殊棋子（直线/爆炸/魔力鸟）\n弱属性方块：伤害与精华双倍；特效被波及会连锁引爆", 14, COL_DIM)
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
	panel.custom_minimum_size = Vector2(620, 0)
	_result_panel.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	_result_title = _make_label(box, "", 34, COL_GOLD)
	_result_stats = _make_label(box, "", 20)
	var back := Button.new()
	back.text = "返回主界面"
	back.custom_minimum_size = Vector2(220, 52)
	back.add_theme_font_size_override("font_size", 20)
	back.pressed.connect(_on_retreat_pressed)
	box.add_child(back)


func _build_retreat_confirm() -> void:
	_retreat_confirm = CenterContainer.new()
	_retreat_confirm.set_anchors_preset(Control.PRESET_FULL_RECT)
	_retreat_confirm.visible = false
	add_child(_retreat_confirm)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.set_corner_radius_all(16)
	sb.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(520, 0)
	_retreat_confirm.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	_make_label(box, "确定撤退？", 26, COL_GOLD)
	_make_label(box, "当前战斗进度与未到手的赏金将被放弃。", 19)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	box.add_child(buttons)
	var cancel := Button.new()
	cancel.text = "继续战斗"
	cancel.custom_minimum_size = Vector2(150, 48)
	cancel.add_theme_font_size_override("font_size", 20)
	cancel.pressed.connect(func() -> void: _retreat_confirm.visible = false)
	buttons.add_child(cancel)
	var confirm := Button.new()
	confirm.text = "确定撤退"
	confirm.custom_minimum_size = Vector2(150, 48)
	confirm.add_theme_font_size_override("font_size", 20)
	confirm.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
	confirm.pressed.connect(_leave_battle)
	buttons.add_child(confirm)


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
	if steps_left <= 0 or defeated:
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
	var spawned: Array = report.get("spawned", [])
	if spawned.size() > 0:
		_show_toast("生成特殊棋子！")
	steps_left -= 1
	total_cleared += (report["cleared"] as Array).size()
	max_chain = maxi(max_chain, int(report["chains"]))
	_apply_damage(report["waves"])
	if board.ensure_playable():
		_show_toast("无可行交换，棋盘已重洗")
	if steps_left <= 0 and not defeated:
		_show_result(false)
	_refresh_board()
	_refresh_hud()


func _apply_damage(waves: Array) -> void:
	var dmg_f := 0.0
	var ep := 0
	var any_weak := false
	var atk_mult := Balance.train_multiplier(GameState.atk_line)
	for i in waves.size():
		var wave_mult := 1.0 + Balance.CHAIN_BONUS_PER_WAVE * float(i)
		for entry in waves[i]:
			var m := Balance.damage_multiplier(int(entry["element"]), monster)
			if m > 1.0:
				any_weak = true
				ep += int(Balance.EP_PER_TILE * Balance.EP_WEAKNESS_MULT)
			else:
				ep += Balance.EP_PER_TILE
			dmg_f += wave_mult * m * atk_mult
	var dmg := int(ceil(dmg_f))
	total_damage += dmg
	monster_hp -= dmg
	if ep > 0:
		session_ep += ep
		GameState.add_essence(ep)
	_spawn_damage_number(dmg, any_weak)
	if monster_hp <= 0:
		_victory()


func _victory() -> void:
	if defeated:
		return
	defeated = true
	var bounty := int(ceil(int(monster["bounty"]) * Balance.train_multiplier(GameState.bounty_line)))
	GameState.add_money(float(bounty))
	GameState.set_meta("last_bounty", bounty)
	_show_result(true)


func _on_retreat_pressed() -> void:
	if _result_panel.visible:
		_leave_battle()  # 战斗已结束，直接离开
		return
	_retreat_confirm.visible = true


func debug_spawn_random_special() -> void:
	## 【修改器】随机格子生成一颗随机特殊棋子（测试视觉与引爆表现用）
	var types: Array = [
		Match3Board.SPECIAL_LINE_H, Match3Board.SPECIAL_LINE_V,
		Match3Board.SPECIAL_BOMB, Match3Board.SPECIAL_BIRD,
	]
	var t: int = types[randi() % types.size()]
	var r := randi() % board.size
	var c := randi() % board.size
	if t == Match3Board.SPECIAL_BIRD:
		board.grid[r][c] = Match3Board.BIRD_ELEM
	board.specials[r][c] = t
	_refresh_board()
	_show_toast("已在 (%d,%d) 生成特殊棋子" % [c, r])


func _leave_battle() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")


# ---------- 刷新与反馈 ----------

func _refresh_board() -> void:
	for r in Balance.BOARD_SIZE:
		for c in Balance.BOARD_SIZE:
			var b: Button = tiles[r][c]
			var v: int = board.grid[r][c]
			var sp: int = board.special_at(r, c)
			# 属性文字恒为大号单字，保证一眼可辨；特效用边框形状区分（不依赖字形）
			b.text = "鸟" if sp == Match3Board.SPECIAL_BIRD else Balance.ELEMENT_NAMES[v]
			b.add_theme_font_size_override("font_size", 40)
			if sp == Match3Board.SPECIAL_BIRD:
				b.add_theme_stylebox_override("normal", _bird_style())
				b.add_theme_color_override("font_color", COL_GOLD)
			elif sp != Match3Board.SPECIAL_NONE:
				b.add_theme_stylebox_override("normal", _special_style(v, sp))
				b.add_theme_color_override("font_color", Balance.ELEMENT_TEXT_COLORS[v])
			else:
				b.add_theme_stylebox_override("normal", _tile_style(v))
				b.add_theme_color_override("font_color", Balance.ELEMENT_TEXT_COLORS[v])
			b.modulate = Color(1.4, 1.4, 1.15) if selected == Vector2i(c, r) else Color.WHITE


func _bird_style() -> StyleBoxFlat:
	if _bird_sb == null:
		_bird_sb = StyleBoxFlat.new()
		_bird_sb.bg_color = Color("3a2f55")
		_bird_sb.set_corner_radius_all(10)
		_bird_sb.border_color = COL_GOLD
		_bird_sb.set_border_width_all(4)
	return _bird_sb


## 特殊棋子样式：元素底色 + 形状边框（横条纹=清行，竖条纹=清列，金框=爆炸）
func _special_style(element: int, sp: int) -> StyleBoxFlat:
	var key := "%d_%d" % [element, sp]
	if _special_style_cache.has(key):
		return _special_style_cache[key]
	var sb: StyleBoxFlat = _tile_style(element).duplicate()
	sb.border_color = Color(1, 1, 1, 0.95)
	match sp:
		Match3Board.SPECIAL_LINE_H:
			sb.border_width_top = 6
			sb.border_width_bottom = 6
		Match3Board.SPECIAL_LINE_V:
			sb.border_width_left = 6
			sb.border_width_right = 6
		Match3Board.SPECIAL_BOMB:
			sb.set_border_width_all(5)
			sb.border_color = COL_GOLD
	_special_style_cache[key] = sb
	return sb


func _refresh_hud() -> void:
	_steps_label.text = str(steps_left)
	_stat_cleared.text = "消除方块：%d" % total_cleared
	_stat_chain.text = "最大连锁：%d" % max_chain
	_stat_damage.text = "总输出：%d" % total_damage
	_stat_ep.text = "本局精华：+%d" % session_ep
	var weak_name: String = Balance.ELEMENT_NAMES[int(monster.get("weak", 0))]
	var elite_tag: String = "★精英 " if monster.get("elite", false) else ""
	_enemy_name.text = "%s%s（弱点：%s）" % [elite_tag, monster["name"], weak_name]
	_hp_bar.max_value = monster_hp_max
	_hp_bar.value = maxf(monster_hp, 0.0)
	_hp_label.text = "HP %d / %d" % [ceili(maxf(monster_hp, 0.0)), monster_hp_max]


func _tile_style(element: int) -> StyleBoxFlat:
	while _tile_styles.size() <= element:
		var i := _tile_styles.size()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Balance.ELEMENT_COLORS[i]
		sb.set_corner_radius_all(10)
		_tile_styles.append(sb)
	return _tile_styles[element]


func _spawn_damage_number(amount: int, weak: bool) -> void:
	var label := Label.new()
	label.text = "-%d" % amount
	label.add_theme_font_size_override("font_size", 36)
	label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4) if weak else Color(1.0, 0.85, 0.5))
	label.position = Vector2(250, 470)
	add_child(label)
	var tw := create_tween()
	tw.tween_property(label, "position:y", 400.0, 0.8)
	tw.parallel().tween_property(label, "modulate:a", 0.0, 0.8)
	tw.tween_callback(label.queue_free)


func _show_result(victory: bool) -> void:
	battle_over = true
	var time_text := "%d:%02d" % [int(elapsed / 60.0), int(elapsed) % 60]
	if victory:
		_result_title.text = "战斗胜利！"
		var bounty := int(GameState.get_meta("last_bounty", 0))
		_result_stats.text = "获得赏金 %d %s\n总输出 %d ｜ 消除 %d 块 ｜ 最大连锁 %d\n精华 +%d ｜ 用时 %s" % [
			bounty, Balance.CURRENCY_SHORT,
			total_damage, total_cleared, max_chain,
			session_ep, time_text,
		]
	else:
		_result_title.text = "步数耗尽……"
		_result_stats.text = "%s 逃走了（剩余 HP %d）\n总输出 %d ｜ 消除 %d 块 ｜ 最大连锁 %d\n精华 +%d ｜ 用时 %s" % [
			monster["name"], ceili(maxf(monster_hp, 0.0)),
			total_damage, total_cleared, max_chain,
			session_ep, time_text,
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
