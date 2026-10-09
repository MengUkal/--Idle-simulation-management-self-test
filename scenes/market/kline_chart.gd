extends Control
## K 线图自绘控件：红涨绿跌 + 影线。数据源为 Market 自动加载单例。

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
	var count := series.size()
	var slot := size.x / float(count)
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
