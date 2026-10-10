extends SceneTree
## 一次性工具：构建金色奇幻主题 → res://theme/fantasy.tres
## 运行：godot --headless --path . -s res://tests/_make_theme.gd

func _init() -> void:
	var t := Theme.new()

	# 按钮：深紫底 + 金边（normal/hover/pressed/disabled）
	t.set_stylebox("normal", "Button", _btn_sb(Color("3a2f55"), Color("f2c94c")))
	t.set_stylebox("hover", "Button", _btn_sb(Color("4a3d6b"), Color("ffe08a")))
	t.set_stylebox("pressed", "Button", _btn_sb(Color("241d33"), Color("c9a227")))
	t.set_stylebox("disabled", "Button", _btn_sb(Color("2a2438"), Color("4a4060")))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", Color("f2e6c8"))
	t.set_color("font_hover_color", "Button", Color("ffffff"))
	t.set_color("font_pressed_color", "Button", Color("ffd75e"))
	t.set_color("font_focus_color", "Button", Color("ffffff"))
	t.set_color("font_disabled_color", "Button", Color("8a8296"))
	t.set_font_size("font_size", "Button", 20)

	# 面板：深紫圆角（已有显式样式的面板不受影响，只兜底无样式的）
	var panel := _sb(Color("241d33"), Color("4a4060"), 1, 16)
	panel.content_margin_left = 20
	panel.content_margin_right = 20
	panel.content_margin_top = 16
	panel.content_margin_bottom = 16
	t.set_stylebox("panel", "PanelContainer", panel)

	# 进度条
	var pb_bg := _sb(Color("191322"), Color("4a4060"), 1, 6)
	var pb_fill := _sb(Color("e0564f"), Color("00000000"), 0, 6)
	t.set_stylebox("background", "ProgressBar", pb_bg)
	t.set_stylebox("fill", "ProgressBar", pb_fill)

	# 标签默认字色（节点级覆盖优先，不冲突）
	t.set_color("font_color", "Label", Color("e8e0cf"))

	DirAccess.make_dir_recursive_absolute("res://theme")
	var err := ResourceSaver.save(t, "res://theme/fantasy.tres")
	print("theme save err=", err)
	quit()


func _btn_sb(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(2)
	sb.border_color = border
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


func _sb(bg: Color, border: Color, bw: int, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	if bw > 0:
		sb.set_border_width_all(bw)
		sb.border_color = border
	sb.set_corner_radius_all(radius)
	return sb
