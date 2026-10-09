extends Node
## 挂机收入引擎：等级即收入，按真实帧时间累积吉尔（与帧率无关）。
## M2 的消消乐（战斗）收入也将汇入这里。

func _process(delta: float) -> void:
	var inc := GameState.income_per_sec()
	if inc > 0.0 and delta > 0.0:
		GameState.add_money(inc * delta)
