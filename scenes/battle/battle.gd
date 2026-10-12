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

# 主动技能（三期，2026-10-11 拍板：资源模型 charge/fixed/steps）
var skill_def := {}            # 当前职业主动技能定义（data/skills.gd）
var skill_energy := 0          # 充能池（charge 型）
var skill_frac := 0            # 充能余数（已消除但不足一格的块数）
var skill_uses := 0            # 固定次数余量（fixed 型）
var skill_targeting := false   # 瞄准模式（需选格/列的技能）
var _skill_overlay: Control    # 瞄准范围提示层（受影响格子高亮）
var _skill_hover := Vector2i(-1, -1)  # 瞄准模式下鼠标悬停的格子
var _btn_pulse: Tween          # 技能就绪呼吸脉冲
var _skill_btn: Button
var _drag_cell := Vector2i(-1, -1)   # 滑动交换：按住的格位（手机版，2026-10-12 拍板）
var _drag_pos := Vector2.ZERO
var _drag_used := false

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
var guard := GuardKit.new("")  # 层守机制包（2026-10-11 拍板；非层守 = 空包全直通）
var _banner: Label             # 当前层守机制横幅（新顶旧，防叠加）
var _smoke_left := 0           # 香雾障目剩余步数（渲染层遮蔽棋盘图案）
var player_hp := 0.0           # 玩家当前生命（战斗内即态，P-a）
var player_hp_max := 1         # 玩家生命上限（等级/职业/装备推导）
var _charge := 0               # 怪物蓄力计数（每耗 1 步 -1，归零发动攻击，P-a D7）
var _battle_bounty := 0        # 本局已入账赏金（战败作废用，D8）
var _lost_by_hp := false       # 战败原因：玩家 HP 归零
var _player_hp_bar: ProgressBar
var _player_hp_label: Label
var _charge_bar: ProgressBar   # 怪物蓄力条（怪物面板 HP 条下方，P-a）
var _charge_label: Label

@onready var _steps_label_ref: Label = %StepsLabel
@onready var _stat_cleared_ref: Label = %StatCleared
@onready var _stat_chain_ref: Label = %StatChain
@onready var _stat_damage_ref: Label = %StatDamage
@onready var _stat_ep_ref: Label = %StatEp
@onready var _side_panel_ref: VBoxContainer = %SidePanel
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
	# 第三层·苍干栈道（2026-10-11 美术会话产出接入）
	"旋風雀": "gustsparrow", "叶隐蛙": "leaffrog", "風滚草": "tumbleweed",
	"吊藤妖": "hangvine", "喇叭藤": "hornvine", "刺藤果": "thornfruit",
	"镇风桩": "windstake",
	# 第四层·落英花冠（slug 预留：美术会话产出后按名落图，缺失时留空走通用底）
	"落英妖": "petalfae", "花粉蛾": "pollenmoth", "夜香花": "nightbloom",
	"蜜壶蜂": "honeypot", "灯芯草妖": "lampgrass", "曼陀花妖": "datura",
	"千瓣祭主": "petalpriest",
	# 第五层·云顶鹰巢（slug 预留）
	"云雀妖": "cloudlark", "云绵羊": "cloudsheep", "风筝妖": "kitefiend",
	"露珠精": "dewspirit", "雷蜓": "thunderdragonfly", "雾里鱼": "mistfish",
	"瞭望鹰": "watchereagle",
	# 第六层·星梢（slug 预留：M3.0 工程提案，命名待世界观线覆写）
	"星尘蛾": "stardustmoth", "月苔鹿": "moosedeer", "霜羽鸮": "frostowl",
	"流星蜉": "meteorfly", "银露鲸": "silverwhale", "夜幕织者": "nightweaver",
	"星望者": "stargazer",
}


func _process(delta: float) -> void:
	if not battle_over:
		elapsed += delta
	# 技能瞄准：悬停格追踪 + 提示层脉冲重绘
	if skill_targeting and board_layer != null:
		var m := board_layer.get_local_mouse_position()
		var c := Vector2i(clampi(int(floor(m.x / STEP)), 0, Balance.BOARD_SIZE - 1),
			clampi(int(floor(m.y / STEP)), 0, Balance.BOARD_SIZE - 1))
		if c != _skill_hover:
			_skill_hover = c
			if _skill_overlay:
				_skill_overlay.queue_redraw()
		if _skill_overlay and _skill_overlay.visible:
			_skill_overlay.queue_redraw()  # 呼吸脉冲需要每帧重绘


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
	steps_left = Balance.battle_steps(GameState.level) + Mods.add("steps")
	_roll_monster()
	player_hp_max = GameState.player_max_hp()
	player_hp = float(player_hp_max)
	_charge = int(monster.get("speed", 6))
	_build_player_hud()
	_build_charge_hud()
	_refresh_board()
	_refresh_hud()
	# Toast 上移：避开底部玩家 HP 条（2026-10-12 重叠修复）
	_toast.offset_top -= 56.0
	_toast.offset_bottom -= 56.0
	if monster.get("elite", false):
		Sfx.play("elite_appear")  # 精英登场：暗钟压迫感（音频会话 2026-10-11）
		_show_toast("遭遇精英：%s！" % monster["name"])
	if guard.has_kit() and guard.opener().size() > 0:
		_show_banner(str(guard.opener().get("tag", "先制")), Color(0.95, 0.8, 0.35))  # 层守先制横幅
		_monster_attack(true)  # 先制 = 开场立即攻击一次（规划 §2.2）
	# 新手引导 B：首次战斗三连（引导链清单实装）
	if GameState.tip_once("battle_first"):
		_newbie_hints.call_deferred()


	if OS.is_debug_build():
		add_child(DevPanel.new())  # 开发修改器（F1 开关），release 导出自动不存在
	# 右栏信息间距（S 系列后内容变多，拉开统计/说明/按钮的呼吸感）
	if _side_panel_ref != null:
		_side_panel_ref.add_theme_constant_override("separation", 12)
	# BGM 按层五选一（bgm_floor5 已由音频会话产出，2026-10-12）
	Sfx.bgm(["bgm_floor1", "bgm_floor2", "bgm_floor3", "bgm_floor4", "bgm_floor5"][clampi(GameState.floor_index, 1, 5) - 1])
	_setup_skill()
	_build_skill_bar()
	if OS.get_cmdline_user_args().has("--capture-debug"):
		_debug_capture.call_deferred()


## 首次战斗提示三连（顶部横幅逐条弹出，避开底部玩家 HP 条）
func _newbie_hints() -> void:
	var hints := [
		"消除就是攻击。一次消得越多，连锁越痛。",
		"打弱点色：伤害与精华双双倍。",
		"技能充能靠消除；打不过，撤退不丢人。",
	]
	for h in hints:
		_show_banner(str(h), Color(0.65, 0.9, 1.0))
		await get_tree().create_timer(2.6).timeout


func _setup_skill() -> void:
	## 主动技能初始化（三期）：按职业加载定义与资源
	skill_def = GameSkills.get_skill(GameState.character_class)
	if skill_def.is_empty():
		return
	match str(skill_def.get("resource", "")):
		"fixed":
			skill_uses = int(skill_def.get("uses", 1))


## 主动技能栏：职业专属技按钮（通用道具系统未设计，此前预留灰槽已按拍板移除）
func _build_skill_bar() -> void:
	if skill_def.is_empty():
		return
	_skill_btn = Button.new()
	_skill_btn.custom_minimum_size = Vector2(86, 38)
	_skill_btn.position = Vector2(6, -46)
	_skill_btn.focus_mode = Control.FOCUS_NONE
	_skill_btn.clip_text = true
	_skill_btn.text = "⚡0"
	_skill_btn.add_theme_font_size_override("font_size", 14)
	# 职业技能图标（美术管线产物 skill_<class>.png；缺失时留纯文字）
	var skill_icon_path := "res://assets/art/ui/skill_%s.png" % GameState.character_class
	if ResourceLoader.exists(skill_icon_path):
		_skill_btn.icon = load(skill_icon_path)
		_skill_btn.expand_icon = true
	_skill_btn.pressed.connect(_on_skill_pressed)
	_skill_btn.tooltip_text = "%s\n%s" % [skill_def.get("name", ""), skill_def.get("desc", "")]
	# 瞄准范围提示层（覆盖整个棋盘，受影响格子高亮）
	_skill_overlay = Control.new()
	_skill_overlay.position = Vector2.ZERO
	_skill_overlay.size = Vector2(STEP, STEP) * Balance.BOARD_SIZE
	_skill_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skill_overlay.draw.connect(_on_skill_overlay_draw)
	_skill_overlay.visible = false
	board_layer.add_child(_skill_overlay)
	_skill_btn.disabled = not skill_ready()
	board_layer.add_child(_skill_btn)
	_refresh_skill_bar()


	_refresh_skill_bar()


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
	# 技能瞄准范围提示演示（瞄准型职业才可演示；warrior=十字范围）
	if bool(skill_def.get("targeting", false)):
		skill_energy = maxi(skill_energy, 1)
		_refresh_skill_bar()
		_on_skill_pressed()
		var center := board_layer.get_global_transform() * (Vector2(3, 3) * STEP + Vector2(TILE, TILE) / 2.0)
		Input.warp_mouse(center)
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		var img2 := get_viewport().get_texture().get_image()
		img2.save_png("F:/放置测试/挂机放置增量rpg/tests/cap_targeting.png")
		print("[capture] cap_targeting saved")
		skill_targeting = false
		_skill_overlay.visible = false
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
	# 层守机制包按怪物名装载（守林古树/镇风桩有专属机制，其余为空包）
	guard = GuardKit.new(str(monster.get("name", "")))


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
			# 强化珠 "+" 角标样式（文字仅在 plus_at 时置"+"）
			b.add_theme_font_size_override("font_size", 30)
			b.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
			b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
			b.add_theme_constant_override("outline_size", 6)
			for st in ["normal", "hover", "pressed", "disabled", "focus"]:
				b.add_theme_stylebox_override(st, sb_empty)
			b.pressed.connect(_on_tile_pressed.bind(b))
			b.button_down.connect(_on_tile_down.bind(b))
			board_layer.add_child(b)
			row.append(b)
		tiles.append(row)


func _connect_button_signals() -> void:
	%RetreatStayBtn.pressed.connect(_on_retreat_stay)
	%RetreatLeaveBtn.pressed.connect(_leave_battle)
	%ResultBackBtn.pressed.connect(_on_retreat_pressed)
	%RetreatBtn.pressed.connect(_on_retreat_pressed)


# ---------- 交互 ----------

func _notification(what: int) -> void:
	## 手机版（2026-10-12）：切后台立即存档；系统返回键 = 撤退确认/结算
	if what == NOTIFICATION_APPLICATION_PAUSED:
		SaveManager.save()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _result_panel.visible:
			_leave_battle()
		else:
			_on_retreat_pressed()


func _input(event: InputEvent) -> void:
	## 滑动交换（拍板 2026-10-12）：按住棋子拖过相邻格阈值即触发交换
	if _drag_cell.x < 0 or _busy or battle_over:
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var delta_v: Vector2 = event.position - _drag_pos
		if delta_v.length() < STEP * 0.45:
			return
		var dir := Vector2i.ZERO
		if absf(delta_v.x) > absf(delta_v.y):
			dir = Vector2i(1 if delta_v.x > 0.0 else -1, 0)
		else:
			dir = Vector2i(0, 1 if delta_v.y > 0.0 else -1)
		var target := _drag_cell + dir
		if target.x < 0 or target.y < 0 or target.x >= Balance.BOARD_SIZE or target.y >= Balance.BOARD_SIZE:
			return
		_drag_used = true
		var from := _drag_cell
		_drag_cell = Vector2i(-1, -1)
		selected = Vector2i(-1, -1)
		_refresh_board()
		_try_move(from, target)


func _on_tile_down(btn: Button) -> void:
	## 滑动交换：记录按下的格位与起点（手机版）
	_drag_cell = Vector2i(
		clampi(int(round(btn.position.x / STEP)), 0, Balance.BOARD_SIZE - 1),
		clampi(int(round(btn.position.y / STEP)), 0, Balance.BOARD_SIZE - 1))
	_drag_pos = btn.get_global_mouse_position()
	_drag_used = false


func _on_tile_pressed(btn: Button) -> void:
	## 按钮可随交换换格位（tiles 引用对调），格位从按钮当前位置反推，不能用构建期绑定的坐标
	if _drag_used:
		_drag_used = false  # 刚完成滑动交换：吞掉释放点击
		return
	if _busy or steps_left <= 0 or defeated:
		return
	var cell := Vector2i(
		clampi(int(round(btn.position.x / STEP)), 0, Balance.BOARD_SIZE - 1),
		clampi(int(round(btn.position.y / STEP)), 0, Balance.BOARD_SIZE - 1))
	if skill_targeting:
		# 技能瞄准模式：本次点击作为技能目标（格/列）
		skill_targeting = false
		_cast_skill(cell)
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
		Sfx.play("special_spawn")  # S3② 凯旋生成 stab（音频会话 2026-10-11；special_line/bomb/bird 留作引爆专用）
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
	if _smoke_left > 0:
		_smoke_left -= 1  # 香雾按玩家步数衰减
	# 怪物蓄力攻击（P-a D7）：每耗 1 步 -1，归零发动攻击并重置
	if not defeated:
		_charge -= 1
		if _charge <= 0:
			_monster_attack(false)
			_charge = int(monster.get("speed", 6))
		_update_charge_hud()
	total_cleared += (report["cleared"] as Array).size()
	max_chain = maxi(max_chain, int(report["chains"]))
	# S3③ 屏幕字（拍板第十五轮）：连锁夸赞 + 凯旋音
	var chains_now := int(report["chains"])
	if chains_now >= 2 and not defeated:
		var words := ["不错！", "漂亮！", "惊人！", "传说！！"]
		_show_banner(words[clampi(chains_now - 2, 0, 3)], Color(0.65, 0.9, 1.0))
		Sfx.play("praise_%d" % clampi(chains_now, 2, 5))
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
	_busy = false
	_refresh_skill_bar()  # _busy 复位后再刷新（否则动画中 skill_ready=false 会把按钮误灰且无人恢复）
	# 4) 结算弹窗
	if _pending_result == 1:
		_show_result(true)
	elif _pending_result == 2:
		_show_result(false)
	elif reshuffled:
		_show_toast("无可行交换，棋盘已重洗")
	_busy = false


func _apply_damage(waves: Array, from_skill := false) -> void:
	var dmg_f := 0.0
	var ep := 0
	var any_weak := false
	var atk_mult := Balance.train_multiplier(GameState.atk_line) \
		* Balance.atk_fruit_mult(GameState.fruits) * Mods.mult("battle_damage") \
		* Mods.mult("weapon_atk")  # 武器攻击力（装备内在属性，层级公式轴）
	# 层守机制修正（封印/单消盾/蓄力易伤/狂暴减伤/树皮硬化；普通怪直通）
	var mods: Dictionary = guard.move_modifiers(waves.size(), from_skill)
	for i in waves.size():
		var plus_n := 0
		for entry in waves[i]:
			if bool(entry.get("plus", false)):
				plus_n += 1
		# 强化珠：每颗对该波伤害 +6%（拍板 2026-10-11）
		var wave_mult := (1.0 + (Balance.CHAIN_BONUS_PER_WAVE + Mods.add("chain_bonus")) * float(i)) \
			* (1.0 + Match3Board.PLUS_WAVE_BONUS * float(plus_n))
		for entry in waves[i]:
			if int(entry["element"]) < 0:
				continue  # 花障碎片等非伤害条目
			var m := Balance.damage_multiplier(int(entry["element"]), monster)
			var m_final := m * Mods.mult("weakness")
			if bool(mods["sealed"]):
				m_final = 1.0  # 弱点封印：克制 ×2 与弱点精华加成失效
			elif m > 1.0:
				any_weak = true
				ep += int(Balance.EP_PER_TILE * Balance.EP_WEAKNESS_MULT)
			else:
				ep += Balance.EP_PER_TILE
			m_final *= Mods.elem_mult(int(entry["element"]))  # 装备元素专精（同色伤害+）
			var sp_amp := 1.0 + (Mods.spec_amp() if bool(entry.get("sp", false)) else 0.0)
			dmg_f += wave_mult * m_final * atk_mult * sp_amp
	var dmg := 0
	if bool(mods["blocked"]):
		dmg = 0  # 连击盾：单波消除无效（主动技能不受盾影响，是解法）
	else:
		dmg_f *= float(mods["mult"])  # 蓄力易伤 ×2 / 狂暴减伤 / 树皮硬化
		dmg = int(ceil(dmg_f))
	total_damage += dmg
	monster_hp -= dmg
	# 充能型技能：按消除块数积能量（资源模型 charge）
	if str(skill_def.get("resource", "")) == "charge":
		var was_ready := skill_energy >= 1
		var cleared_here := 0
		for w in waves.size():
			cleared_here += (waves[w] as Array).size()
		skill_frac += cleared_here
		var cap := int(skill_def.get("max", 3))
		while skill_frac >= int(skill_def.get("charge_per", 8)) and skill_energy < cap:
			skill_frac -= int(skill_def.get("charge_per", 8))
			skill_energy += 1
		if not was_ready and skill_energy >= 1:
			Sfx.play("skill_ready")  # 充能完成提示：跨过可用线的瞬间只响一次（音频会话 2026-10-11）
		_refresh_skill_bar()
	if bool(mods["blocked"]):
		_spawn_damage_number(0, false, true)  # 「盾」提示（精华照常结算，进度不白费）
	else:
		Sfx.play("monster_hit", 1.0, -4.0)  # 受击低频垫层（音效文件本身已 -9dB，再压 4dB 防吵）
	if ep > 0:
		ep = int(round(ep * Mods.mult("ep")))
		session_ep += ep
		GameState.add_essence(ep)
	if not bool(mods["blocked"]):
		_spawn_damage_number(dmg, any_weak)
		_hit_flash()
	# 再生词条（P-a）：每波消除回复
	var regen_total := int(Mods.add("regen")) * waves.size()
	if regen_total > 0 and player_hp < float(player_hp_max) and player_hp > 0.0:
		player_hp = minf(player_hp + float(regen_total), float(player_hp_max))
		_update_player_hud()
	if monster_hp <= 0:
		if guard.has_kit() and guard.on_lethal():
			# 根性：首次致死锁 1 HP 生还（限一次）——层守的最后一道门
			monster_hp = 1.0
			_show_banner("根性！", Color(0.75, 0.6, 1.0))
			Sfx.play("guard_guts")  # 专属音（音频会话 2026-10-11）
		else:
			_victory()
	else:
		# 血量阶段推进（横幅 + 音效 + 棋盘改写）
		for e in guard.after_move(float(monster_hp) / float(monster_hp_max)):
			if str(e) == "charge":
				_show_banner("%s！%d 步内受伤翻倍" % [
					str(guard.def.get("charge", {}).get("tag", "蓄力")),
					int(guard.def.get("charge", {}).get("steps", 3))], Color(0.55, 0.9, 0.6))
				Sfx.play("guard_charge")  # 专属音（音频会话 2026-10-11，下同）
			elif str(e) == "rage":
				_show_banner("狂暴！受到的伤害大幅降低", Color(1.0, 0.5, 0.4))
				Sfx.play("guard_rage")
			elif str(e) == "obstacle":
				var sealed: Array = board.seal_obstacles(
					int(guard.def.get("obstacle", {}).get("count", 3)))
				_show_banner("%s！%d 颗棋子被封入花障" % [
					str(guard.def.get("obstacle", {}).get("tag", "花瓣封印")),
					sealed.size()], Color(0.8, 0.55, 0.95))
				Sfx.play("guard_seal")
			elif str(e) == "smoke":
				_smoke_left = int(guard.def.get("smoke", {}).get("steps", 3))
				_show_banner("%s！%d 步内看不清棋盘" % [
					str(guard.def.get("smoke", {}).get("tag", "香雾障目")),
					_smoke_left], Color(0.6, 0.65, 0.8))
				Sfx.play("guard_smoke")


func _victory() -> void:
	if defeated:
		return
	defeated = true
	Sfx.play("monster_die")  # 击杀爆碎（胜利 jingle 在结算弹窗时另播）
	_kill_burst()
	# 层卡：首杀守林古树掉落「苍干栈道层卡」（P3，三层解锁凭证）
	if str(monster.get("name", "")) == "守林古树" and monster.get("elite", false):
		if GameState.unlock_floor3_card():
			Sfx.play("floor_unlock")
			_show_toast("守林古树承认了你，它吐出一枚「苍干栈道层卡」")
	# 层卡：首杀镇风桩掉落「落英花冠层卡」（P4，四层解锁凭证）
	if str(monster.get("name", "")) == "镇风桩" and monster.get("elite", false):
		if GameState.unlock_floor4_card():
			Sfx.play("floor_unlock")
			_show_toast("镇风桩轰然折服，桩底压着一枚「落英花冠层卡」")
	# 层卡：首杀千瓣祭主掉落「云顶鹰巢层卡」（P5，五层解锁凭证）
	if str(monster.get("name", "")) == "千瓣祭主" and monster.get("elite", false):
		if GameState.unlock_floor5_card():
			Sfx.play("floor_unlock")
			_show_toast("千瓣祭主凋落，花心藏着一枚「云顶鹰巢层卡」")
	# 层卡：首杀瞭望鹰掉落「星梢层卡」（M3.0，六层解锁凭证）
	if str(monster.get("name", "")) == "瞭望鹰" and monster.get("elite", false):
		if GameState.unlock_floor6_card():
			Sfx.play("floor_unlock")
			_show_toast("瞭望鹰振翅高鸣，爪下落着一枚「星梢层卡」")
	var bounty := int(ceil(int(monster["bounty"]) * Balance.train_multiplier(GameState.bounty_line) * Mods.mult("bounty")))
	GameState.add_money(float(bounty))
	_battle_bounty += bounty
	GameState.set_meta("last_bounty", bounty)
	# 伙伴蛋掉落（P-b D2：常驻 2% / 精英 15% / 层守首杀必掉；蛋品质随楼层）
	var is_first_kill := not GameState.killed_once.has(str(monster.get("name", "")))
	var egg: Dictionary = GameState.egg_drop(monster, monster.get("elite", false), is_first_kill)
	if not egg.is_empty():
		_show_toast("「%s」的蛋（%s）！树根兽栏已收录" % [
			str(egg["monster"]), GameEquipment.QUALITY_NAMES[int(egg["quality"])]])
		Sfx.play("essence_gain")
	# 装备掉落（E1：传奇定向挂点 + 全战斗小概率；粗品/普通自动分解回精华）
	var drop_text: String = GameState.battle_drop(monster, monster.get("elite", false))
	if drop_text != "":
		_show_toast(drop_text)
		# 稀有度揭示音（音频会话 2026-10-11）：太古光柱 > 传奇仪式 > 史诗轻钟 > 普通系极轻金币
		if drop_text.contains("太古"):
			Sfx.play("ancient_pillar")
			_pillar_flash.call_deferred()  # E2.2 太古光柱视觉（2026-10-12）
		elif drop_text.contains("传奇"):
			Sfx.play("rarity_legend")
		elif drop_text.contains("史诗"):
			Sfx.play("rarity_epic")
		else:
			Sfx.play("drop_common")
	# S1 结算秀：有剩余步数 → 逐颗转特殊棋子连爆后弹出结果（拍板第十五轮）
	if steps_left > 0:
		_pending_result = 0  # 结算秀结束后再弹
		_showcase_and_finish.call_deferred()
		return
	_award_stars()
	_pending_result = 1  # 结果弹窗在动画结束后弹出


## S1 结算秀（Sugar Crush 式，拍板第十五轮）：剩余步数逐颗转特殊棋子自动引爆 → 赏金/精华雨 → 产星
func _showcase_and_finish() -> void:
	var converted := mini(steps_left, 12)
	var show_steps := steps_left
	for i in converted:
		steps_left -= 1
		var cell := Vector2i(randi() % Balance.BOARD_SIZE, randi() % Balance.BOARD_SIZE)
		board.grid[cell.y][cell.x] = randi_range(0, Balance.ELEMENT_KINDS - 1)
		var kinds := [Match3Board.SPECIAL_LINE_H, Match3Board.SPECIAL_LINE_V, Match3Board.SPECIAL_BOMB]
		board.specials[cell.y][cell.x] = kinds[randi() % kinds.size()]
		Sfx.play("special_spawn", 1.0 + 0.1 * i)
		_refresh_board()
		board.skill_smash([cell])  # 自动引爆（走重力+连锁）
		GameState.add_money(Balance.showcase_reward_per(GameState.floor_index))  # 赏金雨随层缩放（原 25G 固定失控）
		session_ep += 6
		GameState.add_essence(6)
		_refresh_hud()
		await get_tree().create_timer(0.2).timeout
	_award_stars(show_steps)
	_refresh_board()
	_refresh_hud()
	_show_result(true)


## 产星（S2 星辰宝箱进度）：胜利 1 星 + 剩余步数每 10 步加 1 星，上限 3
func _award_stars(remaining := 0) -> void:
	var stars := 1 + mini(int(remaining / 10.0), 2)
	var chests: int = GameState.add_stars(stars)
	for c in chests:
		var reward: String = GameState.open_chest()
		_show_toast("★ 祭品箱开启：%s！" % reward)
		Sfx.play("chest_open")  # 开箱吱呀+星尘（音频会话 2026-10-12），rarity_epic 紧随作奖励揭示
		Sfx.play("rarity_epic")


# ---------- 玩家生命与怪物蓄力（P-a，2026-10-11 拍板 D7~D10；2026-10-12 HUD 重排） ----------

func _update_player_hud() -> void:
	if _player_hp_bar == null:
		return
	_player_hp_bar.max_value = player_hp_max
	_player_hp_bar.value = maxf(player_hp, 0.0)
	_player_hp_label.text = "HP %d / %d" % [
		ceili(maxf(player_hp, 0.0)), player_hp_max]


func _build_player_hud() -> void:
	## 玩家 HP 条（右栏顶部：剩余步数上方——玩家状态归玩家信息区，2026-10-12 重排）
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.45)
	bg.position = Vector2(1448.0, 238.0)
	bg.size = Vector2(404, 46)
	add_child(bg)
	_player_hp_bar = ProgressBar.new()
	_player_hp_bar.max_value = player_hp_max
	_player_hp_bar.value = player_hp
	_player_hp_bar.show_percentage = false
	_player_hp_bar.position = Vector2(6, 5)
	_player_hp_bar.size = Vector2(392, 18)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.35, 0.85, 0.5)
	_player_hp_bar.add_theme_stylebox_override("fill", fill)
	var fgbg := StyleBoxFlat.new()
	fgbg.bg_color = Color(0.16, 0.14, 0.2)
	_player_hp_bar.add_theme_stylebox_override("background", fgbg)
	_player_hp_label = Label.new()
	_player_hp_label.text = ""
	_player_hp_bar.add_child(_player_hp_label)
	bg.add_child(_player_hp_bar)
	_player_hp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_player_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_player_hp_label.add_theme_font_size_override("font_size", 13)
	var cap := Label.new()
	cap.text = "玩家生命"
	cap.position = Vector2(0, -22)
	cap.add_theme_font_size_override("font_size", 14)
	cap.add_theme_color_override("font_color", Color(0.65, 0.9, 0.7))
	bg.add_child(cap)


func _build_charge_hud() -> void:
	## 怪物蓄力条（怪物面板 HP 条正下方，绝对定位不挤容器）
	var hb := _hp_bar
	if hb == null:
		return
	var base := hb.get_global_rect()
	_charge_bar = ProgressBar.new()
	_charge_bar.max_value = maxi(int(monster.get("speed", 6)), 1)
	_charge_bar.value = maxi(_charge, 0)
	_charge_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.95, 0.75, 0.3)
	_charge_bar.add_theme_stylebox_override("fill", fill)
	var fgbg := StyleBoxFlat.new()
	fgbg.bg_color = Color(0.14, 0.12, 0.18)
	_charge_bar.add_theme_stylebox_override("background", fgbg)
	_charge_bar.position = base.position + Vector2(0, 42)
	_charge_bar.size = Vector2(base.size.x, 12)
	_charge_label = Label.new()
	_charge_label.text = ""
	_charge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_charge_label.add_theme_font_size_override("font_size", 13)
	_charge_label.add_theme_color_override("font_color", Color(0.95, 0.75, 0.3))
	_charge_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_charge_bar.add_child(_charge_label)
	hb.get_parent().add_child.call_deferred(_charge_bar)


func _update_charge_hud() -> void:
	if _charge_bar == null or not is_instance_valid(_charge_bar):
		return
	_charge_bar.max_value = maxi(int(monster.get("speed", 6)), 1)
	_charge_bar.value = maxi(_charge, 0)
	_charge_label.text = "蓄力 %d / %d" % [maxi(_charge, 0), _charge_bar.max_value]


func _monster_attack(opened: bool) -> void:
	## 怪物蓄力攻击：伤害 = atk × 30%~50% × 狂暴系数 × (1 - 玩家减伤)
	var atk := float(monster.get("atk", 0))
	if atk <= 0.0 or battle_over or defeated:
		return
	var dmg := int(ceil(atk * randf_range(Balance.PLAYER_ATTACK_FRAC[0], Balance.PLAYER_ATTACK_FRAC[1]) \
		* guard.atk_mult() * (1.0 - clampf(Mods.add("dr"), 0.0, 0.6))))
	player_hp -= dmg
	Sfx.play("monster_hit", 1.2, 0.0)
	_shake_board()
	_update_player_hud()
	_spawn_player_number(dmg)
	if player_hp <= 0.0:
		_lose_by_hp()


func _spawn_player_number(dmg: int) -> void:
	## 玩家受伤飘字（棋盘右上红字）
	var label := Label.new()
	label.text = "-%d" % dmg
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
	label.position = Vector2(board_layer.position.x + Balance.BOARD_SIZE * STEP + 20.0, 360.0)
	add_child(label)
	var tw := create_tween()
	tw.tween_property(label, "position:y", 290.0, 0.8)
	tw.parallel().tween_property(label, "modulate:a", 0.0, 0.8)
	tw.tween_callback(label.queue_free)


func _lose_by_hp() -> void:
	## 战败（D8）：本局赏金/精华作废；持有物不丢
	_lost_by_hp = true
	battle_over = true
	if _battle_bounty > 0:
		GameState.money = maxf(0.0, GameState.money - float(_battle_bounty))
		EventBus.money_changed.emit(GameState.money)
	if session_ep > 0:
		GameState.essence = maxi(0, GameState.essence - session_ep)
		EventBus.essence_changed.emit(GameState.essence)
	_show_result(false, true)


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
			b.modulate = Color(1.4, 1.4, 1.15) if selected == Vector2i(c, r) else Color.WHITE
			if board.is_obstacle(r, c):
				b.icon = _cached_tex("res://assets/art/tiles/obstacle_flower.png")
				b.expand_icon = true
				continue
			if _smoke_left > 0 and v >= 0:
				b.icon = _cached_tex("res://assets/art/tiles/smoke_fog.png")  # 香雾：看不清图案
				b.expand_icon = true
				continue
			b.icon = _tile_texture(v, sp)
			b.expand_icon = true
			if board.plus_at(r, c):
				b.text = "+"  # 强化珠金角标（字体样式在 _build_tiles 统一设置）


func _refresh_hud() -> void:
	_steps_label.text = str(steps_left)
	_stat_cleared.text = "消除方块：%d" % total_cleared
	_stat_chain.text = "最大连锁：%d" % max_chain
	_stat_damage.text = "总输出：%d" % total_damage
	_stat_ep.text = "本局精华：+%d" % session_ep
	var weak_name: String = Balance.ELEMENT_NAMES[int(monster.get("weak", 0))]
	var elite_tag: String = "★精英 " if monster.get("elite", false) else ""
	var gtag: String = guard.state_tag()
	if _smoke_left > 0:
		gtag += "｜香雾"
	_enemy_name.text = "%s%s（弱点：%s）%s" % [elite_tag, monster["name"], weak_name, gtag]
	_hp_bar.max_value = monster_hp_max
	_hp_bar.value = maxf(monster_hp, 0.0)
	_hp_label.text = "HP %d / %d" % [ceili(maxf(monster_hp, 0.0)), monster_hp_max]
	_update_player_hud()
	_update_charge_hud()


# ---------- 棋子图标（tools/artgen.py 程序化生成，见 docs/游戏设计文档.md §13） ----------

const ELEMENT_EN := ["fire", "water", "wind", "earth", "light", "dark"]
const TILE_TEX_FMT := "res://assets/art/tiles/tile_%d_%s_%s.png"
const CHAIN_LADDER := [0, 2, 4, 7, 9, 12, 14, 16]  # S3① 连锁爬梯半音表（大调音级，音频会话 2026-10-11）
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


## 层守机制大横幅（先制/蓄力/狂暴/根性）：棋盘上方居中，弹入-停留-淡出（拍板：大幅度提示）
func _show_banner(text: String, color: Color = Color(0.95, 0.8, 0.35)) -> void:
	if _banner and is_instance_valid(_banner):
		_banner.queue_free()  # 新横幅顶掉旧横幅，避免叠加
	var l := Label.new()
	_banner = l
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 46)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 12)
	var w := 760.0
	var board_w := Balance.BOARD_SIZE * STEP
	l.size = Vector2(w, 90)
	# board_layer 是手工布局容器（size 恒 0），以棋子实际像素宽度求中心
	l.position = Vector2(board_layer.position.x + board_w / 2.0 - w / 2.0, board_layer.position.y + 10.0)
	l.pivot_offset = Vector2(w / 2.0, 45.0)
	l.scale = Vector2(1.5, 1.5)
	l.modulate.a = 0.0
	l.z_index = 60
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "modulate:a", 1.0, 0.15)
	tw.parallel().tween_property(l, "scale", Vector2.ONE, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.3)
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(l.queue_free)


func _spawn_damage_number(amount: int, weak: bool, blocked := false) -> void:
	if not Settings.get_value("fx_damage_numbers"):
		return
	var label := Label.new()
	if blocked:
		label.text = "盾！"
		label.add_theme_font_size_override("font_size", 30)
		label.add_theme_color_override("font_color", Color(0.62, 0.76, 0.96))
	else:
		label.text = "-%d" % amount
		label.add_theme_font_size_override("font_size", 36)
		label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4) if weak else Color(1.0, 0.85, 0.5))
	label.position = Vector2(250, 470)
	add_child(label)
	var tw := create_tween()
	tw.tween_property(label, "position:y", 400.0, 0.8)
	tw.parallel().tween_property(label, "modulate:a", 0.0, 0.8)
	tw.tween_callback(label.queue_free)


func _show_result(victory: bool, lost_hp := false) -> void:
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
	elif lost_hp:
		_result_title.text = "力竭倒下……"
		_result_stats.text = "%s 击倒了你了——本局收益作废（持有物不丢，拍板 D8）\n再挑战即可，棋盘不会记仇\n总输出 %d ｜ 消除 %d 块 ｜ 最大连锁 %d ｜ 用时 %s" % [
			monster["name"], total_damage, total_cleared, max_chain, time_text,
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


## E2.2 太古光柱：金白光柱从天而降渐隐（2026-10-12；美术管线粒子光效就位前先代码实现）
func _pillar_flash() -> void:
	var vp := get_viewport_rect().size
	var pillar := ColorRect.new()
	pillar.color = Color(1.0, 0.95, 0.72, 0.0)
	pillar.position = Vector2(vp.x / 2.0 - 110.0, 0.0)
	pillar.size = Vector2(220.0, vp.y)
	pillar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pillar)
	var glow := ColorRect.new()
	glow.color = Color(1.0, 0.9, 0.6, 0.0)
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(pillar, "color:a", 0.9, 0.16)
	tw.tween_property(glow, "color:a", 0.28, 0.16)
	tw.chain().tween_interval(0.45)
	tw.chain().tween_property(pillar, "color:a", 0.0, 1.1)
	tw.parallel().tween_property(glow, "color:a", 0.0, 1.1)
	tw.chain().tween_callback(func() -> void:
		pillar.queue_free()
		glow.queue_free())


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
func _praise(chains: int) -> void:
	## S3③ 连锁屏幕字 + 夸赞音阶梯（不错/漂亮/惊人/传说，音频会话 2026-10-11）
	if chains >= 5:
		_show_banner("传说！！", Color(1.0, 0.85, 0.3))
		Sfx.play("praise_5")
	elif chains >= 4:
		_show_banner("惊人！", Color(1.0, 0.7, 0.35))
		Sfx.play("praise_4")
	elif chains >= 3:
		_show_banner("漂亮！", Color(0.65, 0.9, 1.0))
		Sfx.play("praise_3")
	elif chains >= 2:
		_show_banner("不错！", Color(0.8, 1.0, 0.75))
		Sfx.play("praise_2")


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
			# 【音频拍板 2026-10-10】消除音两类制：首波含弱点块 → 克制命中音，否则普通音
			var weak_hit := false
			for entry2: Dictionary in wave:
				if Balance.damage_multiplier(int(entry2["element"]), monster) > 1.0:
					weak_hit = true
					break
			Sfx.play("clear_effective" if weak_hit else "clear_normal")
		elif wi > 0:
			# S3① 连锁半音爬梯（大调音级上行，替代线性 pitch，音频会话 2026-10-11）
			Sfx.play("combo_chain", pow(2.0, CHAIN_LADDER[mini(wi - 1, CHAIN_LADDER.size() - 1)] / 12.0))
		var plus_n := 0
		for entry3: Dictionary in wave:
			if bool(entry3.get("plus", false)):
				plus_n += 1
		if plus_n > 0:
			Sfx.play("plus_tick", 1.0 + 0.05 * minf(float(wi), 4.0), -6.0)  # 强化珠正反馈微光
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
	# S3③ 屏幕字夸赞（不错/漂亮/惊人/传说，音频会话 2026-10-11）
	_praise(waves.size())


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


# ---------- 主动技能（三期，2026-10-11 拍板：资源模型 charge/fixed/steps，S3 正常结算） ----------

func skill_ready() -> bool:
	if skill_def.is_empty() or _busy or defeated or battle_over:
		return false
	match str(skill_def.get("resource", "")):
		"charge":
			return skill_energy >= 1
		"fixed":
			return skill_uses > 0
		"steps":
			return steps_left >= int(skill_def.get("step_cost", 2))
	return false


func _on_skill_pressed() -> void:
	if skill_targeting:
		skill_targeting = false
		_skill_overlay.visible = false
		Sfx.play("ui_open", 0.7)
		_show_toast("已取消瞄准")
		return
	if not skill_ready():
		return
	if bool(skill_def.get("targeting", false)):
		skill_targeting = true
		_skill_hover = Vector2i(-1, -1)
		_skill_overlay.visible = true
		Sfx.play("ui_open", 0.9)
		_show_toast("瞄准中：移动查看范围，左键确认 · 右键取消")
		return
	_cast_skill(Vector2i(-1, -1))


## 释放职业主动技能：资源扣除 → board 技能执行 → 正常伤害/动画结算（S3 拍板）
func _cast_skill(cell: Vector2i) -> void:
	if _busy:
		return
	_busy = true
	skill_targeting = false
	_skill_overlay.visible = false
	Sfx.play("skill_cast")  # 职业技能施法音（七职业通用；此前技能全程无声，音频会话补齐 2026-10-11）
	match str(skill_def.get("resource", "")):
		"charge":
			skill_energy -= 1
		"fixed":
			skill_uses -= 1
		"steps":
			steps_left -= int(skill_def.get("step_cost", 2))
	var slv := GameState.skill_lv
	var waves: Array = []
	match GameState.character_class:
		"warrior":
			var cells: Array = [cell,
				cell + Vector2i(1, 0), cell + Vector2i(-1, 0),
				cell + Vector2i(0, 1), cell + Vector2i(0, -1)]
			if slv >= 1:
				cells.append_array([cell + Vector2i(1, 1), cell + Vector2i(-1, -1),
					cell + Vector2i(1, -1), cell + Vector2i(-1, 1)])
			if slv >= 2:
				cells.append_array([cell + Vector2i(2, 0), cell + Vector2i(-2, 0),
					cell + Vector2i(0, 2), cell + Vector2i(0, -2)])
			var r := board.skill_smash(cells)
			waves = r["waves"]
		"mage":
			var weak := int(monster.get("weak", -1))
			if weak < 0:
				weak = board.rng.randi_range(0, Balance.ELEMENT_KINDS - 1)
			var r := board.skill_transform_random(weak, 6 + 2 * slv)
			waves = r["waves"]
		"rogue":
			board.skill_shuffle()
			if slv > 0:
				board.grant_plus_random(2 * slv)  # 偷天换日·强化：洗牌后点化强化珠
		"priest":
			steps_left += 3 + slv
		"paladin":
			board.skill_bless(cell)
			if slv > 0:
				for d0: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					board.skill_bless(cell + d0)  # 祝圣扩散：每级 +1 临格
		"ranger":
			var r := board.skill_pierce_col(cell.x)
			waves = r["waves"]
			if slv > 0:
				var extra: Array = []
				for i2 in slv * 2:
					extra.append(Vector2i(board.rng.randi_range(0, board.size - 1),
						board.rng.randi_range(0, board.size - 1)))
				var r2 := board.skill_smash(extra)
				waves.append_array(r2["waves"])
		"warlock":
			var r := board.skill_plague(2 * slv)
			waves = r["waves"]
	if waves.size() > 0:
		_apply_damage(waves, true)  # 技能伤害：穿透连击盾（盾挡普消不挡技能）
		_cast_skill_fx(cell, waves)
		_refresh_board()
		await _anim_clear(waves)
		_refresh_board()
		board.ensure_playable()
		await _anim_settle()
	else:
		_cast_skill_fx(cell, waves)
		board.ensure_playable()  # 洗牌/祝圣后同样防死局
	if defeated:
		_pending_result = 1
	elif steps_left <= 0:
		_pending_result = 2
	_refresh_board()
	_refresh_hud()
	_busy = false
	_refresh_skill_bar()
	if _pending_result == 1:
		_show_result(true)
	elif _pending_result == 2:
		_show_result(false)


func _refresh_skill_bar() -> void:
	if _skill_btn == null or skill_def.is_empty():
		return
	# 灰/亮只由资源够不够决定（_busy 动画期间的拦截交给 skill_ready）——
	# 否则刷新落在动画中时按钮被误灰且无人恢复（圣光祈祷"只能用一次"事故）
	match str(skill_def.get("resource", "")):
		"charge":
			_skill_btn.text = "⚡%d" % skill_energy
			_skill_btn.tooltip_text = "%s\n能量 %d+%d 格（每消除 %d 块 +1）" % [
				skill_def.get("name", ""), skill_energy, skill_frac, int(skill_def.get("charge_per", 8))]
			_skill_btn.disabled = skill_energy < 1
		"fixed":
			_skill_btn.text = "×%d" % skill_uses
			_skill_btn.tooltip_text = "%s\n剩余次数 %d" % [skill_def.get("name", ""), skill_uses]
			_skill_btn.disabled = skill_uses < 1
		"steps":
			_skill_btn.text = "-%d步" % int(skill_def.get("step_cost", 2))
			_skill_btn.tooltip_text = "%s\n释放消耗 %d 步" % [skill_def.get("name", ""), int(skill_def.get("step_cost", 2))]
			_skill_btn.disabled = steps_left < int(skill_def.get("step_cost", 2))
	# 就绪呼吸脉冲：资源足够时轻微提亮循环（瞄准中保持高亮）
	if _btn_pulse:
		_btn_pulse.kill()
		_btn_pulse = null
	if not _skill_btn.disabled:
		if skill_targeting:
			_skill_btn.modulate = Color(1.35, 1.3, 1.05)
		else:
			_btn_pulse = create_tween().set_loops()
			_btn_pulse.tween_property(_skill_btn, "modulate", Color(1.22, 1.18, 1.02), 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_btn_pulse.tween_property(_skill_btn, "modulate", Color.WHITE, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		_skill_btn.modulate = Color(0.62, 0.62, 0.68)


func _unhandled_input(event: InputEvent) -> void:
	# 瞄准模式：右键取消（左键确认在棋子点击流里）
	if skill_targeting and event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		skill_targeting = false
		_skill_overlay.visible = false
		Sfx.play("ui_open", 0.7)
		_show_toast("已取消瞄准")
		get_viewport().set_input_as_handled()


# ---------- 技能瞄准提示与释放特效（2026-10-11） ----------

## 当前职业在 cell 处释放会影响的格子
func _skill_affected_cells(cell: Vector2i) -> Array:
	match GameState.character_class:
		"warrior":
			return [cell, cell + Vector2i(1, 0), cell + Vector2i(-1, 0),
				cell + Vector2i(0, 1), cell + Vector2i(0, -1)]
		"ranger":
			var col_out: Array = []
			for r in Balance.BOARD_SIZE:
				col_out.append(Vector2i(cell.x, r))
			return col_out
		"paladin":
			return [cell]
	return []


func _on_skill_overlay_draw() -> void:
	if not skill_targeting:
		return
	var pulse := 0.28 + 0.10 * sin(Time.get_ticks_msec() / 170.0)
	for c in _skill_affected_cells(_skill_hover):
		if c.x < 0 or c.y < 0 or c.x >= Balance.BOARD_SIZE or c.y >= Balance.BOARD_SIZE:
			continue
		var r := Rect2(_cell_pos(c) + Vector2(2, 2), Vector2(TILE, TILE) - Vector2(4, 4))
		_skill_overlay.draw_rect(r, Color(0.40, 0.75, 1.0, pulse), true)
		_skill_overlay.draw_rect(r, Color(0.55, 0.85, 1.0, 0.85), false, 2.0)
	if _skill_hover.x >= 0:
		var rr := Rect2(_cell_pos(_skill_hover), Vector2(TILE, TILE))
		_skill_overlay.draw_rect(rr, Color(1, 0.843, 0.369, 0.95), false, 3.0)


func _wave_cells(waves: Array) -> Array:
	var out: Array = []
	for w in waves:
		for e in w:
			out.append(e["cell"])
	return out


## 释放特效入口：按职业分派（纯视觉，不影响结算）
func _cast_skill_fx(cell: Vector2i, waves: Array) -> void:
	match GameState.character_class:
		"warrior":
			var cells: Array = [cell, cell + Vector2i(1, 0), cell + Vector2i(-1, 0),
				cell + Vector2i(0, 1), cell + Vector2i(0, -1)]
			_fx_flash_cells(cells, Color(1.0, 0.5, 0.4), 0.22)
			_burst_cells(cells, Color("e0564f"), 6)
			if Settings.get_value("fx_screen_shake"):
				_shake_board()
		"mage":
			var cells := _wave_cells(waves)
			_fx_flash_cells(cells, Color(0.72, 0.45, 1.0), 0.3)
			_burst_cells(cells, Color("8a5fbf"), 5)
		"rogue":
			_fx_board_shimmer()
		"priest":
			_fx_float_text("+3 步", Vector2(960.0, 380.0), Color("ffd75e"))
		"paladin":
			_fx_flash_cells([cell], Color("ffd75e"), 0.35)
			_burst_cells([cell], Color("ffd75e"), 10)
		"ranger":
			_fx_column_flash(cell.x)
		"warlock":
			var cells := _wave_cells(waves)
			_fx_flash_cells(cells, Color(0.55, 0.3, 0.75), 0.32)
			_burst_cells(cells, Color("8a5fbf"), 4)


func _fx_flash_cells(cells: Array, col: Color, dur := 0.25) -> void:
	for c in cells:
		if c.x < 0 or c.y < 0 or c.x >= Balance.BOARD_SIZE or c.y >= Balance.BOARD_SIZE:
			continue
		var r := ColorRect.new()
		r.color = Color(col.r, col.g, col.b, 0.5)
		r.position = _cell_pos(c) + Vector2(2, 2)
		r.size = Vector2(TILE, TILE) - Vector2(4, 4)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.z_index = 20
		board_layer.add_child(r)
		var tw := create_tween()
		tw.tween_property(r, "modulate:a", 0.0, dur)
		tw.tween_callback(r.queue_free)


func _fx_column_flash(x: int) -> void:
	var r := ColorRect.new()
	r.color = Color(1.0, 0.9, 0.5, 0.4)
	r.position = _cell_pos(Vector2i(x, 0))
	r.size = Vector2(TILE, STEP * Balance.BOARD_SIZE)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.z_index = 20
	board_layer.add_child(r)
	var tw := create_tween()
	tw.tween_property(r, "modulate:a", 0.0, 0.32)
	tw.tween_callback(r.queue_free)


func _burst_cells(cells: Array, col: Color, amount := 6) -> void:
	for c in cells:
		if c.x < 0 or c.y < 0 or c.x >= Balance.BOARD_SIZE or c.y >= Balance.BOARD_SIZE:
			continue
		var p := CPUParticles2D.new()
		p.position = _cell_pos(c) + Vector2(TILE, TILE) / 2.0
		p.amount = amount
		p.lifetime = 0.5
		p.one_shot = true
		p.explosiveness = 1.0
		p.spread = 180.0
		p.gravity = Vector2(0, 500)
		p.initial_velocity_min = 100.0
		p.initial_velocity_max = 240.0
		p.scale_amount_min = 3.0
		p.scale_amount_max = 6.0
		p.color = col
		board_layer.add_child(p)
		p.emitting = true
		get_tree().create_timer(1.0).timeout.connect(p.queue_free)


func _fx_board_shimmer() -> void:
	for r in Balance.BOARD_SIZE:
		for c in Balance.BOARD_SIZE:
			var btn: Button = tiles[r][c]
			var tw := create_tween()
			tw.tween_property(btn, "modulate:a", 0.25, 0.12)
			tw.tween_property(btn, "modulate:a", 1.0, 0.14)


func _fx_float_text(text: String, pos: Vector2, col: Color) -> void:
	if not Settings.get_value("fx_damage_numbers"):
		return
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", 28)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.z_index = 30
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", pos.y - 50.0, 0.9)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.9)
	tw.tween_callback(l.queue_free)
