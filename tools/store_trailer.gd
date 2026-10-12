extends Node
## TapTap 宣传片演出（30s@30fps）：标题卡 → 主界面 → 三消 AI 实战 → 通关字卡。
## 录制: godot --path . --write-movie build/trailer.avi --fixed-fps 30 res://tools/store_trailer.tscn
## 转码: ffmpeg -i trailer.avi -i bgm_floor2.ogg -c:v libx264 -pix_fmt yuv420p -shortest 宣传片.mp4

var _busy := false


func _ready() -> void:
	_run()


func _run() -> void:
	await _title_card(4.0)
	await _main_scene(9.0)
	await _battle_demo(13.0)
	await _clear_card(4.0)
	get_tree().quit(0)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _full_rect(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _title_card(sec: float) -> void:
	var holder := Control.new()
	_full_rect(holder)
	add_child(holder)
	var bg := TextureRect.new()
	bg.texture = load("res://assets/art/bg/world_tree.png")
	if bg.texture != null:
		_full_rect(bg)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		holder.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	holder.add_child(box)
	var l := Label.new()
	l.text = "世界树"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 120)
	l.add_theme_color_override("font_color", Color(1, 0.843, 0.369))
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.02))
	l.add_theme_constant_override("outline_size", 18)
	box.add_child(l)
	var s := Label.new()
	s.text = "挂机三消 RPG · 六层世界树 · 难度五 · 彩虹桥"
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.add_theme_font_size_override("font_size", 34)
	s.add_theme_color_override("font_color", Color(0.91, 0.88, 0.81))
	s.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	s.add_theme_constant_override("outline_size", 8)
	box.add_child(s)
	await _wait(sec)
	holder.queue_free()
	await get_tree().process_frame


func _main_scene(sec: float) -> void:
	var main_scene: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main_scene)
	await _wait(sec)
	main_scene.queue_free()
	await get_tree().process_frame


func _battle_demo(sec: float) -> void:
	GameState.debug_set_level(30)
	GameState.floor_index = 2
	var battle_scene: Node = load("res://scenes/battle/battle.tscn").instantiate()
	add_child(battle_scene)
	await get_tree().process_frame
	await get_tree().process_frame
	var elapsed := 0.0
	while elapsed < sec:
		await get_tree().create_timer(0.55).timeout
		elapsed += 0.55
		var b := battle_scene
		if not is_instance_valid(b) or b.get("board") == null:
			break
		var board = b.get("board")
		var mv = board.find_any_move()
		if mv != null and not bool(b.get("_busy")):
			b.call("_try_move", mv[0], mv[1])
	battle_scene.queue_free()
	await get_tree().process_frame


func _clear_card(sec: float) -> void:
	var holder := Control.new()
	_full_rect(holder)
	add_child(holder)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.04, 0.08)
	_full_rect(bg)
	holder.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	holder.add_child(box)
	var l := Label.new()
	l.text = "—— 通 关 ——"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 96)
	l.add_theme_color_override("font_color", Color(1, 0.843, 0.369))
	box.add_child(l)
	var s := Label.new()
	s.text = "走过彩虹桥，身后的每一层都在星光里呼吸。"
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.add_theme_font_size_override("font_size", 30)
	s.add_theme_color_override("font_color", Color(0.91, 0.88, 0.81))
	box.add_child(s)
	await _wait(sec)
	holder.queue_free()
	await get_tree().process_frame
