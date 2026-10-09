class_name Match3Board
## 纯逻辑三消棋盘：不依赖任何 Godot 节点/自动加载单例，便于无头测试。
## 坐标约定：Vector2i(x=列, y=行)；grid[行][列]；行 0 为最上行，行 size-1 为最下行。
##
## 特殊棋子（参考开心消消乐，2026-10-09 拍板全套实装，规则有简化）：
##   直线(4连)——横4连生成 LINE_H 清本行，竖4连生成 LINE_V 清本列（简化：不随交换方向变化）
##   爆炸(L/T 形)——清自身周围 3×3
##   魔力鸟(5连直线)——与任意普通块交换 → 清全场该颜色；被其他消除波及则白白消失
##   组合技：交换两颗特效时触发（见 _resolve_combo）
## 简化项：直线方向不随交换方向变化；重洗兜底会丢失特效（罕见）。

const EMPTY := -1
const BIRD_ELEM := -2            # grid 值：魔力鸟（不可被颜色匹配）

const SPECIAL_NONE := 0
const SPECIAL_LINE_H := 1        # 清整行
const SPECIAL_LINE_V := 2        # 清整列
const SPECIAL_BOMB := 3          # 清 3×3
const SPECIAL_BIRD := 4          # 魔力鸟

var size := 7
var kinds := 6
var grid: Array = []             # grid[行][列] = 元素 0..kinds-1；EMPTY=-1；魔力鸟=BIRD_ELEM
var specials: Array = []         # specials[行][列] = SPECIAL_*（与 grid 平行）
var rng := RandomNumberGenerator.new()
var spawned_last_move: Array = []  # 上一次交换生成的特效 [{cell, special}]（供 UI 提示）


func _init(board_size: int = 7, element_kinds: int = 6) -> void:
	size = board_size
	kinds = element_kinds
	rng.randomize()


## 随机生成开局棋盘（全普通棋子，无现成三连）。
func setup() -> void:
	grid.clear()
	specials.clear()
	for r in size:
		var row := []
		var srow := []
		row.resize(size)
		srow.resize(size)
		grid.append(row)
		specials.append(srow)
		for c in size:
			var v := rng.randi_range(0, kinds - 1)
			var guard := 0
			while guard < 32 and _makes_run_at(r, c, v):
				v = rng.randi_range(0, kinds - 1)
				guard += 1
			row[c] = v
			srow[c] = SPECIAL_NONE


static func are_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) == 1


func special_at(r: int, c: int) -> int:
	return specials[r][c]


func swap_cells(a: Vector2i, b: Vector2i) -> void:
	var t: int = grid[a.y][a.x]
	grid[a.y][a.x] = grid[b.y][b.x]
	grid[b.y][b.x] = t
	var ts: int = specials[a.y][a.x]
	specials[a.y][a.x] = specials[b.y][b.x]
	specials[b.y][b.x] = ts


## 找出所有属于 ≥3 连的格子（魔力鸟/空格不参与颜色匹配）。
func find_matches() -> Array[Vector2i]:
	var result := {}
	for r in size:
		var c := 0
		while c < size:
			var v: int = grid[r][c]
			if v < 0:
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
			if v < 0:
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


## 返回一个可行交换 [a, b]；无可行交换返回 []。特效块参与的交换永远有效。
func find_any_move() -> Array:
	for r in size:
		for c in size:
			if special_at(r, c) != SPECIAL_NONE:
				for d0: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
					var nb := Vector2i(c, r) + d0
					if nb.x >= 0 and nb.y >= 0 and nb.x < size and nb.y < size:
						return [Vector2i(c, r), nb]
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


## 若无可行交换则重洗棋盘（注意：重洗会丢失特效）；返回是否发生了重洗。
func ensure_playable() -> bool:
	for attempt in 16:
		if not find_any_move().is_empty():
			return attempt > 0
		setup()
	return false


## 试图交换两格。返回 {"ok", "cleared", "chains", "waves"}（waves 元素为 {cell, element}）。
## 分支：特效+特效=组合技；魔力鸟+普通=全场同色消除；直线/爆炸+普通=激活特效；
## 普通+普通=颜色匹配（无消除则还原）。
func try_swap(a: Vector2i, b: Vector2i) -> Dictionary:
	spawned_last_move = []
	if not are_adjacent(a, b):
		return {"ok": false}
	var sa := special_at(a.y, a.x)
	var sb := special_at(b.y, b.x)
	# —— 特效 + 特效：组合技 ——
	if sa != SPECIAL_NONE and sb != SPECIAL_NONE:
		var waves_c: Array = []
		_resolve_combo(a, b, sa, sb, waves_c)
		_cascade(waves_c)
		return _report(waves_c)
	# —— 魔力鸟 + 普通：全场同色消除 ——
	if sa == SPECIAL_BIRD or sb == SPECIAL_BIRD:
		var bird_cell := a if sa == SPECIAL_BIRD else b
		var other := b if sa == SPECIAL_BIRD else a
		var waves_b: Array = []
		var wave: Array = []
		var queue: Array = []
		wave.append({"cell": bird_cell, "element": _remove_cell(bird_cell)})
		var color: int = grid[other.y][other.x]
		wave.append({"cell": other, "element": _remove_cell(other)})
		if color >= 0:
			for r in size:
				for c in size:
					if grid[r][c] == color:
						var cell := Vector2i(c, r)
						var sp := special_at(r, c)
						wave.append({"cell": cell, "element": _remove_cell(cell)})
						if sp >= SPECIAL_LINE_H and sp <= SPECIAL_BOMB:
							queue.append([cell, sp])
		_expand_chain(queue, wave)
		waves_b.append(wave)
		_cascade(waves_b)
		return _report(waves_b)
	# —— 直线/爆炸 + 普通：激活特效 ——
	if sa != SPECIAL_NONE or sb != SPECIAL_NONE:
		var sp := sa if sa != SPECIAL_NONE else sb
		var sp_cell := a if sa != SPECIAL_NONE else b
		var other2 := b if sa != SPECIAL_NONE else a
		var waves_s: Array = []
		var wave_s: Array = []
		wave_s.append({"cell": other2, "element": _remove_cell(other2)})
		waves_s.append(wave_s)
		var queue: Array = [[sp_cell, sp]]
		_expand_chain(queue, wave_s)
		_cascade(waves_s)
		return _report(waves_s)
	# —— 普通 + 普通：颜色匹配 ——
	swap_cells(a, b)
	var matches := find_matches()
	if matches.is_empty():
		swap_cells(a, b)  # 无效交换，还原
		return {"ok": false}
	var waves_n: Array = []
	_process_match_wave(matches, waves_n)
	_cascade(waves_n)
	return _report(waves_n)


# ---------- 解析内部 ----------

func _report(waves: Array) -> Dictionary:
	var total := {}
	for w in waves:
		for e in w:
			total[e["cell"]] = true
	return {
		"ok": true, "cleared": total.keys(), "chains": waves.size(),
		"waves": waves, "spawned": spawned_last_move.duplicate(),
	}


## 消除一格并返回其元素（同时清特效标记）。
func _remove_cell(cell: Vector2i) -> int:
	var el: int = grid[cell.y][cell.x]
	grid[cell.y][cell.x] = EMPTY
	specials[cell.y][cell.x] = SPECIAL_NONE
	return el


## 重力补牌后再匹配，循环直到无消除（每波含形状检测与特效连锁）。
func _cascade(waves: Array) -> void:
	while true:
		_apply_gravity_and_refill()
		var matches := find_matches()
		if matches.is_empty():
			break
		_process_match_wave(matches, waves)


## 展开连锁：队列项为 [cell, sp]（sp 在入队前读取），引爆特效并把被波及的特效继续入队。
func _expand_chain(queue: Array, wave: Array) -> void:
	var triggered := {}
	while queue.size() > 0:
		var item: Array = queue.pop_back()
		var cell: Vector2i = item[0]
		var sp: int = item[1]
		if sp < SPECIAL_LINE_H or sp > SPECIAL_BOMB:
			continue
		if triggered.has(cell):
			continue
		triggered[cell] = true
		# 特效本体计入消除（若仍在棋盘上且未计入过本波）
		if grid[cell.y][cell.x] != EMPTY and not _wave_has(wave, cell):
			wave.append({"cell": cell, "element": _remove_cell(cell)})
		var swept := _special_sweep_cells(cell, sp)
		for sc in swept:
			if sc == cell:
				continue
			if grid[sc.y][sc.x] == EMPTY:
				continue
			if _wave_has(wave, sc):
				continue
			var sc_sp := special_at(sc.y, sc.x)
			wave.append({"cell": sc, "element": _remove_cell(sc)})
			if sc_sp >= SPECIAL_LINE_H and sc_sp <= SPECIAL_BOMB:
				queue.append([sc, sc_sp])


func _wave_has(wave: Array, cell: Vector2i) -> bool:
	for w in wave:
		if w["cell"] == cell:
			return true
	return false


## 直线/爆炸的波及范围（含自身）。
func _special_sweep_cells(cell: Vector2i, sp: int) -> Array:
	var out: Array = []
	match sp:
		SPECIAL_LINE_H:
			for c in size:
				out.append(Vector2i(c, cell.y))
		SPECIAL_LINE_V:
			for r in size:
				out.append(Vector2i(cell.x, r))
		SPECIAL_BOMB:
			for r in range(cell.y - 1, cell.y + 2):
				for c in range(cell.x - 1, cell.x + 2):
					if r >= 0 and r < size and c >= 0 and c < size:
						out.append(Vector2i(c, r))
	out.append(cell)
	return out


## 处理一波颜色匹配：形状检测生成特效（4连直线/LT爆炸/5连魔力鸟），连锁展开。
func _process_match_wave(matches: Array[Vector2i], waves: Array) -> void:
	var spawns := _detect_special_spawns(matches)
	var spawn_cells := {}
	for sp in spawns:
		spawn_cells[sp["cell"]] = sp["special"]
	var wave: Array = []
	var queue: Array = []
	for cell in matches:
		if spawn_cells.has(cell):
			continue
		var sp := special_at(cell.y, cell.x)
		wave.append({"cell": cell, "element": _remove_cell(cell)})
		if sp >= SPECIAL_LINE_H and sp <= SPECIAL_BOMB:
			queue.append([cell, sp])
	for sp in spawns:
		var cell: Vector2i = sp["cell"]
		specials[cell.y][cell.x] = sp["special"]
		spawned_last_move.append({"cell": cell, "special": sp["special"]})
	_expand_chain(queue, wave)
	waves.append(wave)


## 形状检测：对本波消除的格子按颜色分组，判定应生成的特效。
## 优先级：5 连直线=魔力鸟 > L/T 交点=爆炸 > 4 连=直线。每色最多生成一个。
func _detect_special_spawns(cells: Array[Vector2i]) -> Array:
	var by_elem := {}
	for cell in cells:
		var el: int = grid[cell.y][cell.x]
		if el < 0:
			continue
		if not by_elem.has(el):
			by_elem[el] = {}
		by_elem[el][cell] = true
	var spawns: Array = []
	for el in by_elem.keys():
		var gset: Dictionary = by_elem[el]
		var h_runs := _collect_runs(gset, true)
		var v_runs := _collect_runs(gset, false)
		# 5 连直线 → 魔力鸟
		var bird_done := false
		for run in h_runs:
			if run.size() >= 5 and not bird_done:
				spawns.append({"cell": run[int(run.size() / 2.0)], "special": SPECIAL_BIRD})
				bird_done = true
		for run in v_runs:
			if run.size() >= 5 and not bird_done:
				spawns.append({"cell": run[int(run.size() / 2.0)], "special": SPECIAL_BIRD})
				bird_done = true
		if bird_done:
			continue
		# L/T 交点 → 爆炸
		var intersection := Vector2i(-1, -1)
		for h in h_runs:
			for cell in h:
				for v in v_runs:
					if v.has(cell):
						intersection = cell
						break
				if intersection.x >= 0:
					break
			if intersection.x >= 0:
				break
		if intersection.x >= 0:
			spawns.append({"cell": intersection, "special": SPECIAL_BOMB})
			continue
		# 4 连 → 直线（横4连=清行，竖4连=清列）
		var made := false
		for run in h_runs:
			if run.size() == 4:
				spawns.append({"cell": run[1], "special": SPECIAL_LINE_H})
				made = true
				break
		if not made:
			for run in v_runs:
				if run.size() == 4:
					spawns.append({"cell": run[1], "special": SPECIAL_LINE_V})
					made = true
					break
	return spawns


## 收集同色格子集合中的全部直线 run（横向或纵向），长度 ≥3。
func _collect_runs(gset: Dictionary, horizontal: bool) -> Array:
	var runs: Array = []
	var counted := {}
	for cell in gset.keys():
		if counted.has(cell):
			continue
		var back := Vector2i(cell.x - 1, cell.y) if horizontal else Vector2i(cell.x, cell.y - 1)
		if gset.has(back):
			continue  # 不是 run 起点
		var run: Array = []
		var cur: Vector2i = cell
		while gset.has(cur):
			counted[cur] = true
			run.append(cur)
			cur = Vector2i(cur.x + 1, cur.y) if horizontal else Vector2i(cur.x, cur.y + 1)
		if run.size() >= 3:
			runs.append(run)
	return runs


## 组合技（交换两颗特效）。六种组合对齐开心消消乐。
func _resolve_combo(a: Vector2i, b: Vector2i, sa: int, sb: int, waves: Array) -> void:
	var wave: Array = []
	var queue: Array = []
	var cells := {}
	var ea: int = grid[a.y][a.x]
	var eb: int = grid[b.y][b.x]
	var bird := sa == SPECIAL_BIRD or sb == SPECIAL_BIRD
	var line := sa == SPECIAL_LINE_H or sa == SPECIAL_LINE_V or sb == SPECIAL_LINE_H or sb == SPECIAL_LINE_V
	var bomb := sa == SPECIAL_BOMB or sb == SPECIAL_BOMB
	if bird and line:
		# 魔力鸟+直线：全场该颜色全部变直线并引爆
		var color := eb if sa == SPECIAL_BIRD else ea
		for r in size:
			for c in size:
				if grid[r][c] == color:
					var t := SPECIAL_LINE_H if (c + r) % 2 == 0 else SPECIAL_LINE_V
					specials[r][c] = t
					queue.append([Vector2i(c, r), t])
	elif bird and bomb:
		# 魔力鸟+爆炸：全场该颜色全部变爆炸并引爆
		var color2 := eb if sa == SPECIAL_BIRD else ea
		for r in size:
			for c in size:
				if grid[r][c] == color2:
					specials[r][c] = SPECIAL_BOMB
					queue.append([Vector2i(c, r), SPECIAL_BOMB])
	elif bird and bird:
		# 魔力鸟+魔力鸟：全场清空
		for r in size:
			for c in size:
				cells[Vector2i(c, r)] = true
	elif line and bomb:
		# 直线+爆炸：以爆炸格为中心的 3 列 + 以直线格为中心的 3 行
		var bomb_cell := a if sa == SPECIAL_BOMB else b
		var line_cell := a if sa == SPECIAL_LINE_H or sa == SPECIAL_LINE_V else b
		for dc in range(-1, 2):
			for r in size:
				cells[Vector2i(clampi(bomb_cell.x + dc, 0, size - 1), r)] = true
		for dr in range(-1, 2):
			for c in size:
				cells[Vector2i(c, clampi(line_cell.y + dr, 0, size - 1))] = true
	elif line and line:
		# 直线+直线：十字（一行 + 一列）
		for c in size:
			cells[Vector2i(c, a.y)] = true
		for r in size:
			cells[Vector2i(b.x, r)] = true
	elif bomb and bomb:
		# 爆炸+爆炸：5×5 大爆炸（以 a 为中心）
		for r in range(a.y - 2, a.y + 3):
			for c in range(a.x - 2, a.x + 3):
				if r >= 0 and r < size and c >= 0 and c < size:
					cells[Vector2i(c, r)] = true
	# 两颗本体必消
	cells[a] = true
	cells[b] = true
	for cell in cells.keys():
		if grid[cell.y][cell.x] == EMPTY:
			continue
		var sp_before := special_at(cell.y, cell.x)
		wave.append({"cell": cell, "element": _remove_cell(cell)})
		if sp_before >= SPECIAL_LINE_H and sp_before <= SPECIAL_BOMB:
			queue.append([cell, sp_before])
	_expand_chain(queue, wave)
	waves.append(wave)


func _apply_gravity_and_refill() -> void:
	for c in size:
		var write := size - 1
		for r in range(size - 1, -1, -1):
			if grid[r][c] != EMPTY:
				grid[write][c] = grid[r][c]
				specials[write][c] = specials[r][c]
				specials[r][c] = SPECIAL_NONE
				write -= 1
		for r in range(write, -1, -1):
			grid[r][c] = rng.randi_range(0, kinds - 1)
			specials[r][c] = SPECIAL_NONE


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
