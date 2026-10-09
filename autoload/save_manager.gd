extends Node
## 存档管理：JSON 落盘 + 定时自动保存 + 关窗前保存。
## 【已拍板】离线收益 MVP 不做：关游戏期间不产出，读档回到离开时的数值。

const SAVE_PATH := "user://save.json"
const SCHEMA_VERSION := 3

var _autosave_timer := 0.0


func _ready() -> void:
	_load()


func _process(delta: float) -> void:
	_autosave_timer += delta
	if _autosave_timer >= Balance.AUTOSAVE_INTERVAL_SEC:
		_autosave_timer = 0.0
		save()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save()  # 关窗前抢存一次（默认随后即退出）


func save() -> void:
	var data := {
		"version": SCHEMA_VERSION,
		"money": GameState.money,
		"level": GameState.level,
		"floor": GameState.floor_index,
		"total_earned": GameState.total_earned,
		"essence": GameState.essence,
		"atk_line": GameState.atk_line,
		"bounty_line": GameState.bounty_line,
		"income_line": GameState.income_line,
		"holdings": GameState.holdings.duplicate(),
		"market": Market.dump_state(),
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("存档写入失败（错误码 %d）" % FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(data, "\t"))
	EventBus.save_completed.emit()


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return  # 全新开局
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("存档损坏或格式不符，忽略并使用全新开局")
		return
	var data: Dictionary = parsed
	GameState.money = float(data.get("money", Balance.START_MONEY))
	GameState.level = int(data.get("level", Balance.START_LEVEL))
	GameState.floor_index = int(data.get("floor", 1))
	GameState.total_earned = float(data.get("total_earned", 0.0))
	# schema v2 字段（v1 旧档缺省为 0，天然兼容）
	GameState.essence = int(data.get("essence", 0))
	GameState.atk_line = int(data.get("atk_line", 0))
	GameState.bounty_line = int(data.get("bounty_line", 0))
	GameState.income_line = int(data.get("income_line", 0))
	# schema v3 字段（交易所）
	var h: Array = data.get("holdings", [])
	if h.size() == GameState.holdings.size():
		GameState.holdings = h.duplicate()
	Market.apply_state(data.get("market", {}))


func delete_save() -> void:
	## 删除磁盘存档（配合"重置存档"按钮）。之后由下一次自动保存写入全新数据。
	var abs_path := ProjectSettings.globalize_path(SAVE_PATH)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(abs_path)
