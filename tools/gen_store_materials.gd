extends SceneTree
## TapTap 上架物料批量生成器：用游戏内资产（world_tree/像素怪/游戏字体）摆版截屏。
## 产物 -> docs/上架/物料/*.png
## 用法（非 headless）: godot --path . --script res://tools/gen_store_materials.gd

const OUT := "res://docs/上架/物料/"


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	var specs := [
		{"name": "图标_512", "w": 512, "h": 512, "kind": "icon"},
		{"name": "横版封面_460x215", "w": 460, "h": 215, "kind": "cover_h"},
		{"name": "竖版封面_600x900", "w": 600, "h": 900, "kind": "cover_v"},
		{"name": "游戏库壁纸_3840x1240", "w": 3840, "h": 1240, "kind": "wallpaper"},
		{"name": "无Logo宣传_横_1920x1080", "w": 1920, "h": 1080, "kind": "promo_clean_h"},
		{"name": "无Logo宣传_竖_720x1080", "w": 720, "h": 1080, "kind": "promo_clean_v"},
		{"name": "宣传图_16x9_1920x1080", "w": 1920, "h": 1080, "kind": "promo_logo_h"},
		{"name": "宣传图_1x1_1440", "w": 1440, "h": 1440, "kind": "promo_logo_sq"},
	]
	for s in specs:
		await _render_one(s)
	print("[materials] 全部生成完毕 -> docs/上架/物料/")
	quit(0)


func _render_one(s: Dictionary) -> void:
	root.size = Vector2i(int(s["w"]), int(s["h"]))
	await process_frame
	await process_frame
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(holder)
	# 背景：世界树立绘铺满（星夜压暗）
	var art := TextureRect.new()
	art.texture = _tex("res://assets/art/bg/world_tree.png")
	if art.texture != null:
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		holder.add_child(art)
	var kind: String = s["kind"]
	var w := float(int(s["w"]))
	var h := float(int(s["h"]))
	# 像素怪点缀（真图优先：星望者绿圈怪放右下；两只像素怪放左下暗区）
	if kind != "icon":
		var pairs := [
			[0.76, 0.60, "stargazer", 7.0],
			[0.06, 0.62, "nightweaver", 4.5],
			[0.22, 0.74, "meteorfly", 4.0],
		]
		for pair in pairs:
			var m := TextureRect.new()
			m.texture = _tex("res://assets/art/monsters/%s.png" % pair[2])
			if m.texture == null:
				continue
			m.position = Vector2(w * pair[0], h * pair[1])
			m.custom_minimum_size = Vector2(64 * pair[3], 64 * pair[3])
			m.size = Vector2(64 * pair[3], 64 * pair[3])
			m.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			m.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			m.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			holder.add_child(m)
	match kind:
		"icon":
			pass  # 背景 world_tree 铺满即图标（无字）
		"cover_h", "cover_v", "promo_logo_h", "promo_logo_sq":
			_add_title(holder, Vector2(w * 0.5 - w * 0.30, h * 0.06), w * 0.60, true)
		"wallpaper", "promo_clean_h", "promo_clean_v":
			pass  # 无文字版：树+怪即全部
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var out_path := OUT + str(s["name"]) + ".png"
	img.save_png(ProjectSettings.globalize_path(out_path))
	holder.queue_free()
	await process_frame
	print("[materials] %s (%dx%d)" % [str(s["name"]), int(s["w"]), int(s["h"])])


func _add_tree(holder: Control, pos: Vector2, size: float) -> void:
	var t := TextureRect.new()
	t.texture = _tex("res://assets/art/bg/world_tree.png")
	if t.texture == null:
		return
	t.position = pos
	t.custom_minimum_size = Vector2(size, size)
	t.size = Vector2(size, size)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	holder.add_child(t)


func _add_title(holder: Control, pos: Vector2, width: float, with_sub: bool) -> void:
	var box := VBoxContainer.new()
	box.position = pos
	box.custom_minimum_size = Vector2(width, 0)
	holder.add_child(box)
	var l := Label.new()
	l.text = "世界树"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", int(width * 0.16))
	l.add_theme_color_override("font_color", Color(1, 0.843, 0.369))
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02))
	l.add_theme_constant_override("outline_size", int(width * 0.012))
	box.add_child(l)
	if with_sub:
		var s := Label.new()
		s.text = "挂机三消 RPG"
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s.add_theme_font_size_override("font_size", int(width * 0.07))
		s.add_theme_color_override("font_color", Color(0.91, 0.88, 0.81))
		s.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02))
		s.add_theme_constant_override("outline_size", int(width * 0.006))
		box.add_child(s)


func _tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null
