extends Node
## 交易所行情引擎：纯随机游走价格 + K 线聚合。
## 【已拍板】三标的 / 纯随机 / 每 5 秒一跳 / 每 30 秒一根 K 线 / 图表保留 40 根。

signal prices_changed()
signal candle_closed()

var prices: Array = []        # 当前价 prices[标的]
var history: Array = []       # 已收盘 K 线 history[标的] = [[open, high, low, close] × N]
var current_open: Array = []  # 当前未收盘 K 线的开盘价
var live_high: Array = []     # 当前 K 线最高
var live_low: Array = []      # 当前 K 线最低
var _tick_accum := 0.0
var _candle_accum := 0.0


func _ready() -> void:
	if prices.size() < Balance.MARKET_TARGETS.size():
		reset_market()


## 重置行情到基准价并预生成历史 K 线（让图表一解锁就有内容）
func reset_market() -> void:
	prices = []
	history = []
	current_open = []
	live_high = []
	live_low = []
	for t in Balance.MARKET_TARGETS:
		var base: float = t["base"]
		prices.append(base)
		current_open.append(base)
		live_high.append(base)
		live_low.append(base)
		history.append(_seed_history(base, t["vol"]))


func _process(delta: float) -> void:
	_tick_accum += delta
	_candle_accum += delta
	var ticked := false
	var closed := false
	while _tick_accum >= Balance.MARKET_TICK_SEC:
		_tick_accum -= Balance.MARKET_TICK_SEC
		ticked = true
		for i in Balance.MARKET_TARGETS.size():
			var t: Dictionary = Balance.MARKET_TARGETS[i]
			prices[i] = clampf(prices[i] * (1.0 + randfn(0.0, t["vol"])), t["base"] * 0.2, t["base"] * 5.0)
			live_high[i] = maxf(live_high[i], prices[i])
			live_low[i] = minf(live_low[i], prices[i])
	while _candle_accum >= Balance.MARKET_CANDLE_SEC:
		_candle_accum -= Balance.MARKET_CANDLE_SEC
		closed = true
		for i in Balance.MARKET_TARGETS.size():
			history[i].append([current_open[i], live_high[i], live_low[i], prices[i]])
			if history[i].size() > Balance.MARKET_CANDLE_COUNT:
				history[i].pop_front()
			current_open[i] = prices[i]
			live_high[i] = prices[i]
			live_low[i] = prices[i]
	if ticked:
		prices_changed.emit()
	if closed:
		candle_closed.emit()


func dump_state() -> Dictionary:
	return {
		"prices": prices.duplicate(true),
		"history": history.duplicate(true),
		"open": current_open.duplicate(true),
		"high": live_high.duplicate(true),
		"low": live_low.duplicate(true),
	}


func apply_state(d: Dictionary) -> void:
	var p: Array = d.get("prices", [])
	if p.size() == Balance.MARKET_TARGETS.size():
		prices = p.duplicate(true)
		history = d.get("history", []).duplicate(true)
		current_open = d.get("open", []).duplicate(true)
		live_high = d.get("high", []).duplicate(true)
		live_low = d.get("low", []).duplicate(true)


func _seed_history(base: float, vol: float) -> Array:
	var out: Array = []
	var p := base
	var ticks_per := int(Balance.MARKET_CANDLE_SEC / Balance.MARKET_TICK_SEC)
	for i in Balance.MARKET_CANDLE_COUNT:
		var o := p
		var h := p
		var l := p
		for t in ticks_per:
			p = maxf(p * (1.0 + randfn(0.0, vol)), base * 0.2)
			h = maxf(h, p)
			l = minf(l, p)
		out.append([o, h, l, p])
	return out
