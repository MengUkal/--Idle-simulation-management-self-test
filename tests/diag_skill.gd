extends Node
## 技能按钮点击无响应诊断：信号链实测 + GUI 覆盖物静态扫描。
##   godot --headless --path . res://tests/diag_skill.tscn

func _ready() -> void:
	await get_tree().process_frame
	SaveManager.set_process(false)  # 诊断期间禁用自动保存，不碰玩家存档
	var battle_scene: Node = load("res://scenes/battle/battle.tscn").instantiate()
	add_child(battle_scene)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var btn: Button = battle_scene._skill_btn
	print("== 按钮状态 ==")
	print("text=%s disabled=%s visible=%s" % [btn.text, btn.disabled, btn.is_visible_in_tree()])
	print("global_pos=%s size=%s" % [btn.global_position, btn.size])
	print("mouse_filter=%d clip=%s" % [btn.mouse_filter, btn.clip_contents])
	var p: Node = btn.get_parent()
	while p is Control:
		var pc := p as Control
		print("  祖先 %s clip=%s mouse=%d" % [pc.name, pc.clip_contents, pc.mouse_filter])
		p = pc.get_parent()
	print("== 信号链 ==")
	var energy_before: int = battle_scene.skill_energy
	btn.pressed.emit()
	await get_tree().process_frame
	print("emit pressed 后：能量 %d → %d，targeting=%s" % [
		energy_before, battle_scene.skill_energy, battle_scene.skill_targeting])
	var center: Vector2 = btn.get_global_rect().get_center()
	var suspects: Array = []
	_scan(get_tree().root, btn, center, suspects)
	print("== 覆盖嫌疑 %d 个 ==" % suspects.size())
	for s in suspects:
		print("  %s" % s)
	print("== 修复验证（真实存档角色，连放两次） ==")
	battle_scene.skill_energy = 3
	battle_scene.skill_uses = 9
	var res0: int = battle_scene.steps_left
	var uses0: int = battle_scene.skill_uses
	var en0: int = battle_scene.skill_energy
	battle_scene._on_skill_pressed()
	await get_tree().process_frame
	battle_scene._refresh_skill_bar()
	print("  第一次：disabled=%s uses=%d steps=%d energy=%d" % [
		btn.disabled, battle_scene.skill_uses, battle_scene.steps_left, battle_scene.skill_energy])
	battle_scene._on_skill_pressed()
	await get_tree().process_frame
	battle_scene._refresh_skill_bar()
	print("  第二次：disabled=%s uses=%d steps=%d energy=%d" % [
		btn.disabled, battle_scene.skill_uses, battle_scene.steps_left, battle_scene.skill_energy])
	print("  （牧师期望：uses 2→0、steps +%d；charge 期望：energy 递减）" % (int(battle_scene.skill_def.get("step_cost", 2)) * 2))
	get_tree().quit(0)


func _scan(node: Node, btn: Control, center: Vector2, out: Array) -> void:
	if node is Control:
		var c := node as Control
		if c != btn and c.is_visible_in_tree() and c.mouse_filter == Control.MOUSE_FILTER_STOP:
			var gr := c.get_global_rect()
			if gr.has_point(center):
				var parent_name: String = str(c.get_parent().name) if c.get_parent() else "?"
				out.append("%s/%s %s" % [parent_name, c.name, gr])
	for child in node.get_children():
		_scan(child, btn, center, out)
