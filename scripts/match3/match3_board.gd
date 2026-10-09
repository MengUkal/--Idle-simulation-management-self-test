class_name Match3Board
## 纯逻辑三消棋盘：不依赖任何 Godot 节点/自动加载单例，便于无头测试。
## 坐标约定：Vector2i(x=列, y=行)；grid[行][列]；行 0 为最上行，行 size-1 为最下行。
## 值 = 元素索引 0..kinds-1，EMPTY = -1（正在消除/下落中）。

const EMPTY := -1

var size := 7
var kinds := 6
var grid: Array = []
var rng := RandomNumberGenerator.new()


func _init(board_size: int = 7, element_kinds: int = 6) -> void:
	size = board_size
	kinds = element_kinds
	rng.randomize()


## 随机生成开局棋盘，保证没有现成三连。
func setup() -> void:
	grid.clear()
	for r in size:
		var row := []
		row.resize(size)
		grid.append(row)
		for c in size:
			var v := rng.randi_range(0, kinds - 1)
			var guard := 0
			while guard < 32 and _makes_run_at(r, c, v):
				v = rng.randi_range(0, kinds - 1)
				guard += 1
			row[c] = v


static func are_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) == 1


## 试图交换两格：
## - 不相邻，或交换后无消除 → 自动还原，返回 {"ok": false}
## - 有效 → 完成全部消除+重力+补牌（含连锁），返回战报 {"ok", "cleared", "chains", "cleared_per_chain"}
func try_swap(a: Vector2i, b: Vector2i) -> Dictionary:
	if not are_adjacent(a, b):
		return {"ok": false}
	swap_cells(a, b)
	if find_matches().is_empty():
		swap_cells(a, b)  # 无效交换，还原
		return {"ok": false}
	var report := _resolve_board()
	report["ok"] = true
	return report


func swap_cells(a: Vector2i, b: Vector2i) -> void:
	var t: int = grid[a.y][a.x]
	grid[a.y][a.x] = grid[b.y][b.x]
	grid[b.y][b.x] = t


## 找出所有属于 ≥3 连的格子。
func find_matches() -> Array[Vector2i]:
	var result := {}
	for r in size:
		var c := 0
		while c < size:
			var v: int = grid[r][c]
			if v == EMPTY:
				c += 1
				continue
			var e := c + 1
			while e < size and grid[r][e] == v:
				e += 1
			if e - c >= 3:
				for i in range(c, e):
					result[Vector2i(i, r)] = true
			c = e
	for c in size:
		var r := 0
		while r < size:
			var v: int = grid[r][c]
			if v == EMPTY:
				r += 1
				continue
			var e := r + 1
			while e < size and grid[e][c] == v:
				e += 1
			if e - r >= 3:
				for i in range(r, e):
					result[Vector2i(c, i)] = true
			r = e
	var out: Array[Vector2i] = []
	for k in result.keys():
		out.append(k)
	return out


## 返回一个可行交换 [a, b]；无可行交换返回 []。
func find_any_move() -> Array:
	for r in size:
		for c in size:
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var b := Vector2i(c, r) + d
				if b.x >= size or b.y >= size:
					continue
				var a := Vector2i(c, r)
				swap_cells(a, b)
				var ok := not find_matches().is_empty()
				swap_cells(a, b)
				if ok:
					return [a, b]
	return []


## 若无可行交换则重洗棋盘；返回是否发生了重洗。
func ensure_playable() -> bool:
	for attempt in 16:
		if not find_any_move().is_empty():
			return attempt > 0
		setup()
	return false


# ---------- 内部 ----------

func _resolve_board() -> Dictionary:
	var total_cleared := {}
	var chain := 0
	var per_chain: Array[int] = []
	while true:
		var matches := find_matches()
		if matches.is_empty():
			break
		chain += 1
		for cell in matches:
			grid[cell.y][cell.x] = EMPTY
			total_cleared[cell] = true
		per_chain.append(matches.size())
		_apply_gravity_and_refill()
	return {"cleared": total_cleared.keys(), "chains": chain, "cleared_per_chain": per_chain}


func _apply_gravity_and_refill() -> void:
	for c in size:
		var write := size - 1
		for r in range(size - 1, -1, -1):
			if grid[r][c] != EMPTY:
				grid[write][c] = grid[r][c]
				write -= 1
		for r in range(write, -1, -1):
			grid[r][c] = rng.randi_range(0, kinds - 1)


## 生成期检查：在 (r,c) 放 v 是否与左侧/上方构成三连（右侧下方尚未填充）。
func _makes_run_at(r: int, c: int, v: int) -> bool:
	var run := 1
	if c >= 1 and grid[r][c - 1] == v:
		run += 1
		if c >= 2 and grid[r][c - 2] == v:
			run += 1
	if run >= 3:
		return true
	run = 1
	if r >= 1 and grid[r - 1][c] == v:
		run += 1
		if r >= 2 and grid[r - 2][c] == v:
			run += 1
	return run >= 3
