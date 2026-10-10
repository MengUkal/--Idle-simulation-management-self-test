extends Control
## M2 冒险界面：三消战斗（一场一只怪）。
## 场景化迁移完成：节点结构见 battle.tscn（编辑器内可拖动调整），
## 脚本通过 %唯一名 绑定节点——重命名/移动节点不会破坏引用，删除才会。
## 规则【已拍板】：每次消除 = 一次攻击；弱点 ×2；连锁每波 +20%；
## 步数内击杀得赏金；耗尽无赏金。特殊棋子：直线/爆炸/魔力鸟 + 组合技。
## 棋子视觉：assets/art/tiles/ 图标纹理（tools/artgen.py 程序化生成，2026-10-10 接入）。

const TILE := 84.0
const STEP := 88.0  # TILE + 间距

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
var _tex_cache := {}  # 棋子图标纹理缓存（tools/artgen.py 产物，按路径懒加载）

# 本局统计
var total_cleared := 0
var max_chain := 0
var total_damage := 0
var session_ep := 0

var board_layer: Control
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
var _busy := false
var _pending_result := 0  # 0 无 / 1 胜利 / 2 失败（动画结束后再弹结算）

@onready var _steps_label_ref: Label = %StepsLabel
@onready var _stat_cleared_ref: Label = %StatCleared
@onready var _stat_chain_ref: Label = %StatChain
@onready var _stat_damage_ref: Label = %StatDamage
@onready var _stat_ep_ref: Label = %StatEp
@onready var _hp_bar_ref: ProgressBar = %HpBar
@onready var _hp_label_ref: Label = %HpLabel
@onready var _enemy_name_ref: Label = %EnemyName
@onready var _result_panel_ref: Control = %ResultPanel
@onready var _result_title_ref: Label = %ResultTitle
@onready var _result_stats_ref: Label = %ResultStats
@onready var _retreat_confirm_ref: Control = %RetreatConfirm
@onready var _toast_ref: Label = %Toast
@onready var _board_layer_ref: Control = %BoardLayer
@onready var _enemy_portrait: TextureRect = %EnemyPortrait
@onready var _bg_art: TextureRect = %BgArt

## 怪物名 -> 头像文件标识（assets/art/monsters/<slug>.png，与 tools/gen_asset.py 的 MONSTERS 对应）
const MONSTER_SLUG := {
	"树精史莱姆": "slime", "風狼": "windwolf", "岩甲龟": "turtle", "水妖": "nymph",
	"光萤": "firefly", "暗影鼠": "rat", "树根守卫": "guardian",
	"荆棘树妖": "thorntree", "風羽隼": "falcon", "苔石巨人": "golem",
	"沼泽水灵": "bogspirit", "暗藤魔": "vine", "辉羽蝶": "butterfly", "守林古树": "ancient",
}


func _process(delta: float) -> void:
	if not battle_over:
		elapsed += delta


func _ready() -> void:
	board_layer = _board_layer_ref
	_steps_label = _steps_label_ref
	_stat_cleared = _stat_cleared_ref
	_stat_chain = _stat_chain_ref
	_stat_damage = _stat_damage_ref
	_stat_ep = _stat_ep_ref
	_hp_bar = _hp_bar_ref
	_hp_label = _hp_label_ref
	_enemy_name = _enemy_name_ref
	_result_panel = _result_panel_ref
	_result_title = _result_title_ref
	_result_stats = _result_stats_ref
	_retreat_confirm = _retreat_confirm_ref
	_toast = _toast_ref
	_build_tiles()
	_connect_button_signals()
	# 场景背景按层切换（美术管线产物；缺失时留空走暗色底）
	var bg_path := "res://assets/art/bg/bg_floor%d.png" % GameState.floor_index
	_bg_art.texture = load(bg_path) if ResourceLoader.exists(bg_path) else null
	board = Match3Board.new(Balance.BOARD_SIZE, Balance.ELEMENT_KINDS)
	board.setup()
	board.ensure_playable()
	steps_left = Balance.battle_steps(GameState.level)
	_roll_monster()
	_refresh_board()
	_refresh_hud()
	if monster.get("elite", false):
		_show_toast("遭遇精英：%s！" % monster["name"])
	if OS.is_debug_build():
		add_child(DevPanel.new())  # 开发修改器（F1 开关），release 导出自动不存在
	Sfx.bgm("bgm_floor1" if GameState.floor_index < 2 else "bgm_floor2")
	if OS.get_cmdline_user_args().has("--capture-debug"):
		_debug_capture.call_deferred()


## 【诊断工具】自动生成特效、自动走一步并分段截屏（-- --capture-debug 触发）
func _debug_capture() -> void:
	await get_tree().process_frame
	debug_spawn_random_special()
	debug_spawn_random_special()
	debug_spawn_random_special()
	await get_tree().process_frame
	var mv := board.find_any_move()
	print("[capture] move=", mv)
	if mv.size() == 2:
		_try_move(mv[0], mv[1])
	var plan := [[0.06, "cap_swap"], [0.22, "cap_clear"], [0.4, "cap_fall"], [0.95, "cap_done"]]
	for step in plan:
		await get_tree().create_timer(step[0]).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("F:/放置测试/挂机放置增量rpg/tests/%s.png" % step[1])
		print("[capture] %s saved" % step[1])
	get_tree().quit()


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
	# 敌人头像：按怪物名加载像素风头像（tools/gen_asset.py 产物；缺失时留空）
	var slug: String = MONSTER_SLUG.get(monster["name"], "")
	var tex_path := "res://assets/art/monsters/%s.png" % slug
	_enemy_portrait.texture = load(tex_path) if slug != "" and ResourceLoader.exists(tex_path) else null


## 棋子为运行时动态生成（49 颗，位置由棋盘算法决定），挂载到场景中的 BoardLayer 下
func _build_tiles() -> void:
	tiles.clear()
	var sb_empty := StyleBoxEmpty.new()  # 棋子按钮豁免全局主题（紫底金边会从图标透明边角透出）
	for r in Balance.BOARD_SIZE:
		var row := []
		for c in Balance.BOARD_SIZE:
			var b := Button.new()
			b.position = _cell_pos(Vector2i(c, r))
			b.size = Vector2(TILE, TILE)
			b.focus_mode = Control.FOCUS_NONE
			for st in ["normal", "hover", "pressed", "disabled", "focus"]:
				b.add_theme_stylebox_override(st, sb_empty)
			b.pressed.connect(_on_tile_pressed.bind(b))
			board_layer.add_child(b)
			row.append(b)
		tiles.append(row)


func _connect_button_signals() -> void:
	%RetreatStayBtn.pressed.connect(_on_retreat_stay)
	%RetreatLeaveBtn.pressed.connect(_leave_battle)
	%ResultBackBtn.pressed.connect(_on_retreat_pressed)


# ---------- 交互 ----------

func _on_tile_pressed(btn: Button) -> void:
	## 按钮可随交换换格位（tiles 引用对调），格位从按钮当前位置反推，不能用构建期绑定的坐标
	if _busy or steps_left <= 0 or defeated:
		return
	var cell := Vector2i(
		clampi(int(round(btn.position.x / STEP)), 0, Balance.BOARD_SIZE - 1),
		clampi(int(round(btn.position.y / STEP)), 0, Balance.BOARD_SIZE - 1))
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
	if _busy:
		return
	var report := board.try_swap(a, b)
	if not report.get("ok", false):
		_busy = true
		Sfx.play("swap_fail")
		await _anim_invalid_swap(a, b)
		_busy = false
		_refresh_board()
		return
	_busy = true
	Sfx.play("swap_ok")
	var spawned: Array = report.get("spawned", [])
	if spawned.size() > 0:
		_show_toast("生成特殊棋子！")
		for sp_entry: Dictionary in spawned:
			match int(sp_entry["special"]):
				Match3Board.SPECIAL_LINE_H, Match3Board.SPECIAL_LINE_V:
					Sfx.play("special_line")
				Match3Board.SPECIAL_BOMB:
					Sfx.play("special_bomb")
				Match3Board.SPECIAL_BIRD:
					Sfx.play("special_bird")
	# 1) 交换补间。普通三连（逻辑已换位）：按钮跟随块走——滑到新格位后停住、
	#    tiles 引用对调，之后的消除/下落/刷新全部按新映射，视觉与逻辑一致。
	#    特效激活（逻辑不换位）：只播撞击回弹，明确"这块没有换过去"。
	if report.get("swapped", false):
		await _anim_swap_move(a, b)
		var ba2: Button = tiles[a.y][a.x]
		var bb2: Button = tiles[b.y][b.x]
		tiles[a.y][a.x] = bb2
		tiles[b.y][b.x] = ba2
	else:
		await _anim_invalid_swap(a, b)
	steps_left -= 1
	total_cleared += (report["cleared"] as Array).size()
	max_chain = maxi(max_chain, int(report["chains"]))
	_apply_damage(report["waves"])
	var reshuffled := board.ensure_playable()
	if defeated:
		_pending_result = 1
	elif steps_left <= 0:
		_pending_result = 2
	# 2) 消除：按连锁波分批播（每格用逻辑记录的元素渲染，颜色与实际消除一致）
	await _anim_clear(report["waves"])
	# 3) 重力下落 + 补牌空降
	_refresh_board()
	_apply_motion_targets(report)
	if int(report["chains"]) >= 2:
		_shake_board()
	await _anim_settle()
	_refresh_board()
	_refresh_hud()
	# 4) 结算弹窗
	if _pending_result == 1:
		_show_result(true)
	elif _pending_result == 2:
		_show_result(false)
	elif reshuffled:
		_show_toast("无可行交换，棋盘已重洗")
	_busy = false


func _apply_damage(waves: Array) -> void:
	var dmg_f := 0.0
	var ep := 0
	var any_weak := false
	var atk_mult := Balance.train_multiplier(GameState.atk_line) \
		* Balance.atk_fruit_mult(GameState.fruits)
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
	_hit_flash()
	if monster_hp <= 0:
		_victory()


func _victory() -> void:
	if defeated:
		return
	defeated = true
	_kill_burst()
	var bounty := int(ceil(int(monster["bounty"]) * Balance.train_multiplier(GameState.bounty_line)))
	GameState.add_money(float(bounty))
	GameState.set_meta("last_bounty", bounty)
	_pending_result = 1  # 结果弹窗在动画结束后弹出


func _on_retreat_pressed() -> void:
	if _result_panel.visible:
		_leave_battle()  # 战斗已结束，直接离开
		return
	_retreat_confirm.visible = true


func _on_retreat_stay() -> void:
	_retreat_confirm.visible = false


func _leave_battle() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")


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


# ---------- 刷新与反馈 ----------

func _refresh_board() -> void:
	for r in Balance.BOARD_SIZE:
		for c in Balance.BOARD_SIZE:
			var b: Button = tiles[r][c]
			var v: int = board.grid[r][c]
			var sp: int = board.special_at(r, c)
			b.text = ""
			b.icon = _tile_texture(v, sp)
			b.expand_icon = true
			b.modulate = Color(1.4, 1.4, 1.15) if selected == Vector2i(c, r) else Color.WHITE


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


# ---------- 棋子图标（tools/artgen.py 程序化生成，见 docs/游戏设计文档.md §13） ----------

const ELEMENT_EN := ["fire", "water", "wind", "earth", "light", "dark"]
const TILE_TEX_FMT := "res://assets/art/tiles/tile_%d_%s_%s.png"
const TEX_BIRD := "res://assets/art/tiles/tile_bird.png"


func _tile_texture(v: int, sp: int) -> Texture2D:
	## 普通棋子 = 元素图标；直线/爆炸 = 压暗底 + 白色标记组合图标；魔力鸟 = 专属图标
	if sp == Match3Board.SPECIAL_BIRD:
		return _cached_tex(TEX_BIRD)
	var tag := "plain"
	match sp:
		Match3Board.SPECIAL_LINE_H:
			tag = "lh"
		Match3Board.SPECIAL_LINE_V:
			tag = "lv"
		Match3Board.SPECIAL_BOMB:
			tag = "bomb"
	return _cached_tex(TILE_TEX_FMT % [v, ELEMENT_EN[clampi(v, 0, 5)], tag])


func _cached_tex(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path)
	return _tex_cache[path]


func _spawn_damage_number(amount: int, weak: bool) -> void:
	if not Settings.get_value("fx_damage_numbers"):
		return
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
	Sfx.play("battle_win" if victory else "battle_retreat")
	var time_text := "%d:%02d" % [int(elapsed / 60.0), int(elapsed) % 60]
	if victory:
		_result_title.text = "战斗胜利！"
		var bounty := int(GameState.get_meta("last_bounty", 0))
		_result_stats.text = "获得赏金 %d %s\n总输出 %d ｜ 消除 %d 块 ｜ 最大连锁 %d\n精华 +%d ｜ 用时 %s" % [
			bounty, "G",
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


# ---------- 动画 ----------

func _cell_pos(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * STEP, cell.y * STEP)


## 有效交换：两钮互换位置并停留在新格位（调用方随后对调 tiles 引用，按钮从此跟随块走）
func _anim_swap_move(a: Vector2i, b: Vector2i) -> void:
	var ba: Button = tiles[a.y][a.x]
	var bb: Button = tiles[b.y][b.x]
	var tw := create_tween().set_parallel(true)
	tw.tween_property(ba, "position", _cell_pos(b), 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(bb, "position", _cell_pos(a), 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw.finished


## 无效交换：走到一半弹回
func _anim_invalid_swap(a: Vector2i, b: Vector2i) -> void:
	var ba: Button = tiles[a.y][a.x]
	var bb: Button = tiles[b.y][b.x]
	var mid := (_cell_pos(a) + _cell_pos(b)) * 0.5
	var pa := _cell_pos(a)
	var pb := _cell_pos(b)
	var tw1 := create_tween().set_parallel(true)
	tw1.tween_property(ba, "position", mid, 0.07)
	tw1.tween_property(bb, "position", mid, 0.07)
	await tw1.finished
	var tw2 := create_tween().set_parallel(true)
	tw2.tween_property(ba, "position", pa, 0.09)
	tw2.tween_property(bb, "position", pb, 0.09)
	await tw2.finished


## 消除：按连锁波分批播（缩小消失）。每格纹理用 waves 里记录的逻辑元素，
## 不信按钮上的旧纹理——修复"消掉的块颜色和预期不一样"的视觉错位。
func _anim_clear(waves: Array) -> void:
	for wi in waves.size():
		var wave: Array = waves[wi]
		# 波音：首波按主元素播 clear_*；后续波播连锁音并按波次升调
		var elem_count := {}
		for entry in wave:
			var el_c := int(entry["element"])
			if el_c >= 0:
				elem_count[el_c] = int(elem_count.get(el_c, 0)) + 1
		var main_el := -1
		var best := 0
		for el_k in elem_count.keys():
			if int(elem_count[el_k]) > best:
				best = int(elem_count[el_k])
				main_el = int(el_k)
		if wi == 0 and main_el >= 0:
			Sfx.play("clear_%s" % ELEMENT_EN[main_el])
		elif wi > 0:
			Sfx.play("combo_chain", 1.0 + 0.12 * wi)
		var tw := create_tween().set_parallel(true)
		for entry in wave:
			var cell: Vector2i = entry["cell"]
			var btn: Button = tiles[cell.y][cell.x]
			var el: int = int(entry["element"])
			if el == Match3Board.BIRD_ELEM:
				btn.icon = _cached_tex(TEX_BIRD)
			else:
				btn.icon = _tile_texture(el, Match3Board.SPECIAL_NONE)
			_spawn_burst(cell, el)  # 元素色粒子飞溅（S3 反馈特效）
			btn.pivot_offset = btn.size / 2.0
			btn.z_index = 10
			tw.tween_property(btn, "scale", Vector2(0.05, 0.05), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(btn, "modulate:a", 0.15, 0.16)
		await tw.finished
		for entry in wave:
			var cell2: Vector2i = entry["cell"]
			var btn2: Button = tiles[cell2.y][cell2.x]
			btn2.scale = Vector2.ONE
			btn2.modulate = Color.WHITE
			btn2.z_index = 0
			btn2.icon = null  # 已消除：视觉清空，待本步末尾 refresh 补上落定后的块
		if wi < waves.size() - 1:
			await get_tree().create_timer(0.06).timeout  # 波间停顿：连锁节奏可见


## 按重力记录设置下落/补牌的起始位置
func _apply_motion_targets(report: Dictionary) -> void:
	var drop_from := {}
	for mv in report["moves"]:
		# 同一格在多波连锁里会被多次搬运，取最后一次（最终占据者的真实起点）
		drop_from[mv["to"]] = mv["from"]
	for to: Vector2i in drop_from.keys():
		var btn: Button = tiles[to.y][to.x]
		btn.position = _cell_pos(drop_from[to])
	for cell: Vector2i in report["refills"]:
		var btn: Button = tiles[cell.y][cell.x]
		btn.position = _cell_pos(cell) + Vector2(0, -STEP * 1.35)


## 所有偏位的按钮滑回棋盘格（下落/补牌的收尾）；时长随下落距离缩放，避免远距离瞬移感
func _anim_settle() -> void:
	var tw := create_tween().set_parallel(true)
	var moved := false
	for r in Balance.BOARD_SIZE:
		for c in Balance.BOARD_SIZE:
			var btn: Button = tiles[r][c]
			var target := _cell_pos(Vector2i(c, r))
			var dist := btn.position.distance_to(target)
			if dist > 1.0:
				var dur: float = clampf(0.09 + 0.05 * dist / STEP, 0.09, 0.34)
				tw.tween_property(btn, "position", target, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				moved = true
	if moved:
		await tw.finished
	for r in Balance.BOARD_SIZE:
		for c in Balance.BOARD_SIZE:
			tiles[r][c].position = _cell_pos(Vector2i(c, r))


## 连锁 ≥2 时棋盘轻微震屏（可在设置关闭）
func _shake_board() -> void:
	if not Settings.get_value("fx_screen_shake"):
		return
	var origin := board_layer.position
	var tw := create_tween()
	for i in 3:
		tw.tween_property(board_layer, "position", origin + Vector2(7, 0), 0.045)
		tw.tween_property(board_layer, "position", origin - Vector2(7, 0), 0.045)
	tw.tween_property(board_layer, "position", origin, 0.045)


# ---------- 反馈特效（S3，2026-10-10） ----------

## 单格消除粒子：元素色小方块飞溅
func _spawn_burst(cell: Vector2i, el: int) -> void:
	var col := Color("ffd75e")
	if el >= 0 and el < Balance.ELEMENT_KINDS:
		col = Balance.ELEMENT_COLORS[el]
	var p := CPUParticles2D.new()
	p.position = _cell_pos(cell) + Vector2(TILE, TILE) / 2.0
	p.amount = 8
	p.lifetime = 0.45
	p.one_shot = true
	p.explosiveness = 1.0
	p.spread = 180.0
	p.gravity = Vector2(0, 900)
	p.initial_velocity_min = 120.0
	p.initial_velocity_max = 260.0
	p.scale_amount_min = 4.0
	p.scale_amount_max = 7.0
	p.color = col
	board_layer.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


## 怪物受击：头像闪白 + 缩放顿挫
func _hit_flash() -> void:
	if _enemy_portrait.texture == null:
		return
	var tw := create_tween()
	_enemy_portrait.pivot_offset = _enemy_portrait.size / 2.0
	tw.tween_property(_enemy_portrait, "modulate", Color(2.5, 2.5, 2.5), 0.05)
	tw.parallel().tween_property(_enemy_portrait, "scale", Vector2(1.08, 1.08), 0.08)
	tw.tween_property(_enemy_portrait, "modulate", Color.WHITE, 0.15)
	tw.tween_property(_enemy_portrait, "scale", Vector2.ONE, 0.12)


## 击杀：头像位置金色爆碎
func _kill_burst() -> void:
	var p := CPUParticles2D.new()
	p.position = _enemy_portrait.global_position + _enemy_portrait.size / 2.0
	p.amount = 26
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 1.0
	p.spread = 180.0
	p.gravity = Vector2(0, 500)
	p.initial_velocity_min = 180.0
	p.initial_velocity_max = 420.0
	p.scale_amount_min = 3.0
	p.scale_amount_max = 7.0
	p.color = Color("ffd75e")
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)
