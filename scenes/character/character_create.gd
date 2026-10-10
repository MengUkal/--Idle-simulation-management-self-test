extends Control
## 角色创建：选种族（9）→ 选职业（7）→ 特性预览 → 开始旅程。
## 提供「随机」与「默认（人类战士）」一键进入（D7 拍板：可跳过）。
## UI 代码构建（一次性流程画面，参考 dev_panel 先例）；风格继承全局主题。

const RACE_ORDER: Array[String] = [
	"human", "elf", "dwarf", "giantsblood", "orc", "gnome", "troll", "dark_elf", "high_elf",
]
const CLASS_ORDER: Array[String] = [
	"warrior", "mage", "rogue", "priest", "paladin", "ranger", "warlock",
]

var sel_race := ""
var sel_class := ""
var _race_buttons := {}
var _class_buttons := {}
var _preview: Label


func _ready() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.098, 0.075, 0.133)
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(1100, 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 14)
	scroll.add_child(box)

	var title := Label.new()
	title.text = "创造你的冒险者"
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(1, 0.843, 0.369))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	box.add_child(_section_label("种族（调味特性，与职业自由组合）"))
	var race_grid := GridContainer.new()
	race_grid.columns = 3
	race_grid.add_theme_constant_override("h_separation", 12)
	race_grid.add_theme_constant_override("v_separation", 8)
	box.add_child(race_grid)
	for rid in RACE_ORDER:
		var info: Dictionary = GameRaces.RACES[rid]
		race_grid.add_child(_pick_button(info["name"], rid, true))

	box.add_child(_section_label("职业（主特性，决定玩法风格）"))
	var class_grid := GridContainer.new()
	class_grid.columns = 4
	class_grid.add_theme_constant_override("h_separation", 12)
	class_grid.add_theme_constant_override("v_separation", 8)
	box.add_child(class_grid)
	for cid in CLASS_ORDER:
		var info: Dictionary = GameClasses.CLASSES[cid]
		class_grid.add_child(_pick_button(info["name"], cid, false))

	_preview = Label.new()
	_preview.text = "（点选种族与职业查看特性）"
	_preview.add_theme_font_size_override("font_size", 19)
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview.custom_minimum_size = Vector2(0, 110)
	box.add_child(_preview)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	box.add_child(btn_row)
	btn_row.add_child(_action_button("🎲 随机", _on_random))
	btn_row.add_child(_action_button("默认（人类战士）", _on_default))
	btn_row.add_child(_action_button("开始旅程 ▶", _on_start, Color(1, 0.843, 0.369)))
	var hint := Label.new()
	hint.text = "特性即时生效并随存档保存；职业与种族在重生后永久保留"
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color(0.659, 0.624, 0.553))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)

	if OS.get_cmdline_user_args().has("--capture"):
		_capture.call_deferred()


func _capture() -> void:
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/cap_character_create.png")
	print("[capture] character_create saved")
	get_tree().quit()


func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 24)
	l.add_theme_color_override("font_color", Color(0.909, 0.878, 0.812))
	return l


func _pick_button(text: String, id: String, is_race: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(250, 46)
	b.add_theme_font_size_override("font_size", 20)
	b.toggle_mode = true
	b.pressed.connect(_on_pick.bind(id, is_race, b))
	if is_race:
		_race_buttons[id] = b
	else:
		_class_buttons[id] = b
	return b


func _action_button(text: String, action: Callable, color := Color.WHITE) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, 52)
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", color)
	b.pressed.connect(action)
	return b


func _on_pick(id: String, is_race: bool, btn: Button) -> void:
	if is_race:
		sel_race = id
		for k in _race_buttons:
			_race_buttons[k].button_pressed = k == id
	else:
		sel_class = id
		for k in _class_buttons:
			_class_buttons[k].button_pressed = k == id
	_refresh_preview()


func _refresh_preview() -> void:
	if sel_race == "" or sel_class == "":
		_preview.text = "已选种族：%s　｜　已选职业：%s\n（两项都选后即可开始）" % [
			GameRaces.RACES[sel_race]["name"] if sel_race != "" else "—",
			GameClasses.CLASSES[sel_class]["name"] if sel_class != "" else "—",
		]
		return
	var lines: Array = []
	lines.append("【%s · %s】" % [GameRaces.RACES[sel_race]["name"], GameClasses.CLASSES[sel_class]["name"]])
	for t in GameRaces.RACES[sel_race]["traits"]:
		lines.append("· " + str(t))
	for t in GameClasses.CLASSES[sel_class]["traits"]:
		lines.append("· " + str(t))
	_preview.text = "\n".join(lines)


func _on_random() -> void:
	var rid: String = RACE_ORDER[randi() % RACE_ORDER.size()]
	var cid: String = CLASS_ORDER[randi() % CLASS_ORDER.size()]
	_finish(rid, cid)


func _on_default() -> void:
	_finish("human", "warrior")


func _on_start() -> void:
	if sel_race == "" or sel_class == "":
		_random_or_nothing()
		return
	_finish(sel_race, sel_class)


func _random_or_nothing() -> void:
	# 两项已选齐则直接开始（双击防呆）；否则随机
	if sel_race != "" and sel_class != "":
		_finish(sel_race, sel_class)
	else:
		_on_random()


func _finish(rid: String, cid: String) -> void:
	if not GameState.create_character(cid, rid):
		return
	SaveManager.save()  # 角色创建是关键节点，立即落盘
	Sfx.play("level_up")
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
