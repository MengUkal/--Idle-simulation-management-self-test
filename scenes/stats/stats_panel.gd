class_name StatsPanel
extends CanvasLayer
## 角色属性整合面板（2026-10-12 拍板：四组全览 + 修饰符来源明细）。
## 数据源：Mods.panel() / panel_sources() / elem_mult / spec_amp + GameState 派生值。

const MULT_LABELS := {
	"battle_damage": "消除伤害", "weakness": "弱点倍率", "income": "挂机收入",
	"upgrade_cost": "献金费用", "train_cost": "训练费用", "bounty": "赏金",
	"ep": "精华获取", "fruit": "果实加成", "drop_rate": "掉落率", "weapon_atk": "武器攻击力",
}
const ADD_LABELS := {"steps": "步数", "chain_bonus": "连锁加成", "fee": "手续费"}
const ELEM_NAMES := ["火", "水", "風", "土", "光", "闇"]

var _body: RichTextLabel


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
	sb.content_margin_left = 26.0
	sb.content_margin_right = 26.0
	sb.content_margin_top = 16.0
	sb.content_margin_bottom = 16.0
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "角 色 属 性"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	box.add_child(title)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.custom_minimum_size = Vector2(620, 560)
	box.add_child(_body)
	var close := Button.new()
	close.text = "关 闭"
	close.custom_minimum_size = Vector2(0, 40)
	close.pressed.connect(queue_free)
	box.add_child(close)
	_refresh()


func _refresh() -> void:
	var L: Array = []
	var p := Mods.panel()
	var src: Dictionary = Mods.panel_sources()
	L.append("[b]── 战斗 ──[/b]")
	L.append(_mult_line("battle_damage", p, src))
	L.append(_mult_line("weakness", p, src))
	L.append(_mult_line("weapon_atk", p, src))
	L.append("连锁加成 %+.1f%%" % (Mods.add("chain_bonus") * 100.0))
	L.append("步数 +%d" % int(Mods.add("steps")))
	L.append("特效增幅 %+.1f%%" % (Mods.spec_amp() * 100.0))
	for e in 6:
		var em := Mods.elem_mult(e) - 1.0
		if absf(em) > 0.0001:
			L.append("%s属性专精 %+.1f%%" % [ELEM_NAMES[e], em * 100.0])
	L.append("")
	L.append("[b]── 经济 ──[/b]")
	L.append(_mult_line("income", p, src))
	L.append(_mult_line("upgrade_cost", p, src))
	L.append(_mult_line("train_cost", p, src))
	L.append(_mult_line("bounty", p, src))
	L.append("手续费 %+.2f%%" % (Mods.add("fee") * 100.0))
	L.append("")
	L.append("[b]── 功能 ──[/b]")
	L.append(_mult_line("ep", p, src))
	L.append(_mult_line("fruit", p, src))
	L.append(_mult_line("drop_rate", p, src))
	L.append("")
	L.append("[b]── 挂机现状 ──[/b]")
	L.append("当前收入 %s/秒 ｜ 等级 Lv.%d" % [Balance.format_number(GameState.income_per_sec()), GameState.level])
	L.append("下一级献金 %s G ｜ 重生门槛 Lv.%d" % [
		Balance.format_number(GameState.upgrade_cost()), GameState.rebirth_threshold()])
	L.append("步数/场 %d ｜ 层 %s" % [
		Balance.battle_steps(GameState.level) + int(Mods.add("steps")),
		Balance.FLOOR_NAMES.get(GameState.floor_index, "?")])
	L.append("")
	L.append("[color=#8a93ad]%s（%s）｜ 装备 %d 件在身[/color]" % [
		GameState.character_class, GameState.character_race, GameState.equipped.size()])
	_body.text = "\n".join(L)


func _mult_line(key: String, p: Dictionary, src: Dictionary) -> String:
	var total := float(p.get(key, 1.0))
	var line := "%s ×%.2f" % [MULT_LABELS.get(key, key), total]
	var s: Dictionary = src.get(key, {})
	if s.is_empty():
		return line + "  [color=#8a93ad]（无来源）[/color]"
	var parts := []
	for label in s.keys():
		parts.append("%s %+.1f%%" % [str(label), float(s[label]) * 100.0])
	return line + "  [color=#8a93ad]" + "｜".join(parts) + "[/color]"
