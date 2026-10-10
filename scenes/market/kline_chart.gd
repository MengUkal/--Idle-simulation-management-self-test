extends Control
## K 线图自绘控件：红涨绿跌 + 影线 + 网格/现价虚线/右侧价格刻度。数据源为 Market 自动加载单例。

const AXIS_W := 52.0  # 右侧价格刻度区宽度
const GRID_LINES := 4

var source: Node
var target_idx := 0


func _draw() -> void:
	var bg := Color("10141f")
	draw_rect(Rect2(Vector2.ZERO, size), bg, true)
	if source == null or source.history.size() <= target_idx:
		return
	var series: Array = []
	for candle in source.history[target_idx]:
		series.append(candle)
	if target_idx < source.current_open.size():
		var o: float = source.current_open[target_idx]
		var h: float = maxf(source.live_high[target_idx], source.prices[target_idx])
		var l: float = minf(source.live_low[target_idx], source.prices[target_idx])
		series.append([o, h, l, source.prices[target_idx]])
	if series.is_empty():
		return
	var lo := INF
	var hi := -INF
	for cd in series:
		lo = minf(lo, cd[2])
		hi = maxf(hi, cd[1])
	var pad := (hi - lo) * 0.1 + 0.001
	lo -= pad
	hi += pad
	var chart_w := size.x - AXIS_W
	var font := get_theme_default_font()

	# 网格线 + 右侧价格刻度
	for i in range(GRID_LINES + 1):
		var fy := size.y * i / GRID_LINES
		draw_line(Vector2(0, fy), Vector2(chart_w, fy), Color(1, 1, 1, 0.06), 1.0)
		if font:
			var val: float = hi - (hi - lo) * i / GRID_LINES
			draw_string(font, Vector2(chart_w + 6, minf(fy + 4, size.y - 4)), "%.1f" % val,
				HORIZONTAL_ALIGNMENT_LEFT, AXIS_W, 12, Color(0.66, 0.62, 0.55, 0.9))

	# 现价虚线 + 金底价签
	var last: float = series[-1][3]
	var ly := _y_of(last, lo, hi)
	_draw_dashed(Vector2(0, ly), Vector2(chart_w, ly), Color("ffd75e", 0.55), 7.0, 5.0, 1.2)
	if font:
		var tag := "%.1f" % last
		var tag_rect := Rect2(Vector2(chart_w + 2, clampf(ly - 9, 0, size.y - 18)), Vector2(AXIS_W - 4, 18))
		draw_rect(tag_rect, Color("ffd75e"), true)
		draw_string(font, tag_rect.position + Vector2(3, 13), tag,
			HORIZONTAL_ALIGNMENT_LEFT, AXIS_W, 12, Color("191322"))

	# 蜡烛
	var count := series.size()
	var slot := chart_w / float(count)
	var bw := maxf(slot * 0.6, 2.0)
	for i in count:
		var cd: Array = series[i]
		var cx := slot * (i + 0.5)
		var up: bool = cd[3] >= cd[0]
		var col := Color("e0564f") if up else Color("58b46b")
		draw_line(Vector2(cx, _y_of(cd[1], lo, hi)), Vector2(cx, _y_of(cd[2], lo, hi)), col, 1.5)
		var top := _y_of(maxf(cd[0], cd[3]), lo, hi)
		var bot := _y_of(minf(cd[0], cd[3]), lo, hi)
		draw_rect(Rect2(Vector2(cx - bw / 2, top), Vector2(bw, maxf(bot - top, 1.5))), col, true)


func _y_of(v: float, lo: float, hi: float) -> float:
	return size.y - (v - lo) / (hi - lo) * size.y


func _draw_dashed(from: Vector2, to: Vector2, col: Color, dash: float, gap: float, width: float) -> void:
	var total := from.distance_to(to)
	if total <= 0:
		return
	var dir := (to - from) / total
	var t := 0.0
	while t < total:
		var end := minf(t + dash, total)
		draw_line(from + dir * t, from + dir * end, col, width)
		t = end + gap
