class_name SvGrid
extends RefCounted
## 이동 판단용 2D 평면 격자. 3D 화면은 이 결과를 보여 주기만 한다 (정밀 물리엔진 사용 안 함).
##  - 칸 (i, j)는 [i, i+1) × [j, j+1) 영역. 좌표는 '칸' 단위 (1칸 = 3D에서 1m)
##  - 적: 기지까지의 흐름장(flow field) 하나로 모두 길을 찾는다 → 적이 많아도 계산이 가볍다
##  - 아군: 목적지까지 A* + 직선 구간 줄이기
##  - 나중에 방어벽을 세우면 set_blocked() 후 rebuild_flow() 만 다시 하면 된다

const INF_D := 1.0e9
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

var w := 32
var h := 18
var blocked := PackedByteArray()  # 1 = 지나갈 수 없음
var kind: Dictionary = {}  # Vector2i -> 장애물 종류 (그리기용)
var base_cells: Array = []  # Array[Vector2i]
var flow := PackedFloat32Array()  # 기지까지 거리 (칸)
var version := 0  # 격자가 바뀔 때마다 증가


static func from_config() -> SvGrid:
	SvData.ensure_loaded()
	var g := SvGrid.new()
	var m: Dictionary = SvData.cfg["map"]
	g.w = int(m["w"])
	g.h = int(m["h"])
	g.blocked.resize(g.w * g.h)
	g.blocked.fill(0)
	for o in m["obstacles"]:
		var r: Array = o["rect"]
		for i in range(int(r[0]), int(r[0]) + int(r[2])):
			for j in range(int(r[1]), int(r[1]) + int(r[3])):
				g.set_blocked(Vector2i(i, j), true, str(o.get("kind", "rock")))
	var b: Array = m["base_rect"]
	for i in range(int(b[0]), int(b[0]) + int(b[2])):
		for j in range(int(b[1]), int(b[1]) + int(b[3])):
			g.set_blocked(Vector2i(i, j), true, "base")
			g.base_cells.append(Vector2i(i, j))
	g.rebuild_flow()
	return g


func clone() -> SvGrid:
	var c := SvGrid.new()
	c.w = w
	c.h = h
	c.blocked = blocked.duplicate()
	c.kind = kind.duplicate()
	c.base_cells = base_cells.duplicate()
	c.flow = flow.duplicate()
	c.version = version
	return c


func inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h


func idx(c: Vector2i) -> int:
	return c.y * w + c.x


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x)), int(floor(p.y)))


func center_of(c: Vector2i) -> Vector2:
	return Vector2(c.x + 0.5, c.y + 0.5)


func is_blocked(c: Vector2i) -> bool:
	return not inside(c) or blocked[idx(c)] == 1


func set_blocked(c: Vector2i, on: bool, k := "rock") -> void:
	if not inside(c):
		return
	blocked[idx(c)] = 1 if on else 0
	if on:
		kind[c] = k
	else:
		kind.erase(c)
	version += 1


func walkable_pos(p: Vector2) -> bool:
	return not is_blocked(cell_of(p))


func _diag_ok(c: Vector2i, d: Vector2i) -> bool:
	## 대각선 이동 시 모서리를 파고들지 않게
	if d.x == 0 or d.y == 0:
		return true
	return not is_blocked(c + Vector2i(d.x, 0)) and not is_blocked(c + Vector2i(0, d.y))


# ---------------- 흐름장 (적 → 기지) ----------------

func rebuild_flow() -> void:
	flow.resize(w * h)
	flow.fill(INF_D)
	var open: Array = []  # 간단한 다익스트라 (칸 수가 적어 정렬 배열로 충분)
	for bc in base_cells:
		for d in DIRS:
			var n: Vector2i = bc + d
			if inside(n) and not is_blocked(n) and flow[idx(n)] > 0.0:
				flow[idx(n)] = 0.0
				open.append(n)
	while not open.is_empty():
		var best_i := 0
		for k in range(1, open.size()):
			if flow[idx(open[k])] < flow[idx(open[best_i])]:
				best_i = k
		var c: Vector2i = open[best_i]
		open.remove_at(best_i)
		var dc := flow[idx(c)]
		for d in DIRS:
			var n: Vector2i = c + d
			if is_blocked(n) or not _diag_ok(c, d):
				continue
			var nd := dc + (1.41421 if d.x != 0 and d.y != 0 else 1.0)
			if nd < flow[idx(n)] - 1e-4:
				if flow[idx(n)] >= INF_D:
					open.append(n)
				flow[idx(n)] = nd
	version += 1


func flow_distance(p: Vector2) -> float:
	var c := cell_of(p)
	if is_blocked(c):
		return INF_D
	return flow[idx(c)]


func flow_dir(p: Vector2) -> Vector2:
	## 기지 쪽으로 가는 다음 칸 방향 (막힌 칸 안에 있으면 가장 가까운 열린 칸 쪽)
	var c := cell_of(p)
	if is_blocked(c):
		var n := nearest_open(c)
		return (center_of(n) - p).normalized()
	var best := c
	var bd := flow[idx(c)]
	for d in DIRS:
		var n: Vector2i = c + d
		if is_blocked(n) or not _diag_ok(c, d):
			continue
		if flow[idx(n)] < bd - 1e-4:
			bd = flow[idx(n)]
			best = n
	if best == c:
		return Vector2.ZERO  # 기지 바로 옆 (또는 막혀서 갈 곳 없음)
	return (center_of(best) - p).normalized()


func nearest_open(c: Vector2i) -> Vector2i:
	if not is_blocked(c):
		return c
	for r in range(1, maxi(w, h)):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var n := c + Vector2i(dx, dy)
				if inside(n) and not is_blocked(n):
					return n
	return c


func clamp_to_map(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, 0.3, w - 0.3), clampf(p.y, 0.3, h - 0.3))


# ---------------- 이동 (충돌) ----------------

func move(p: Vector2, delta: Vector2, radius: float) -> Vector2:
	## 축별로 나눠 움직이며 막힌 칸에 반지름만큼 붙으면 멈춘다 (벽을 따라 미끄러짐)
	var out := p
	var nx := out + Vector2(delta.x, 0)
	if _free_circle(nx, radius):
		out = nx
	var ny := out + Vector2(0, delta.y)
	if _free_circle(ny, radius):
		out = ny
	return clamp_to_map(out)


func _free_circle(p: Vector2, r: float) -> bool:
	for o in [Vector2(-r, -r), Vector2(r, -r), Vector2(-r, r), Vector2(r, r), Vector2.ZERO]:
		if is_blocked(cell_of(p + o * 0.85)):
			return false
	return true


func line_clear(a: Vector2, b: Vector2) -> bool:
	var d := a.distance_to(b)
	var steps := int(ceil(d / 0.25))
	for i in range(1, steps + 1):
		if is_blocked(cell_of(a.lerp(b, float(i) / steps))):
			return false
	return true


# ---------------- A* (아군) ----------------

func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var s := nearest_open(cell_of(from))
	var g := nearest_open(cell_of(clamp_to_map(to)))
	var out := PackedVector2Array()
	if s == g:
		out.append(center_of(g) if is_blocked(cell_of(to)) else to)
		return out
	var gscore: Dictionary = {s: 0.0}
	var came: Dictionary = {}
	var open: Array = [s]
	var fscore: Dictionary = {s: center_of(s).distance_to(center_of(g))}
	var guard := 0
	while not open.is_empty() and guard < 4000:
		guard += 1
		var bi := 0
		for k in range(1, open.size()):
			if fscore[open[k]] < fscore[open[bi]]:
				bi = k
		var c: Vector2i = open[bi]
		if c == g:
			break
		open.remove_at(bi)
		for d in DIRS:
			var n: Vector2i = c + d
			if is_blocked(n) or not _diag_ok(c, d):
				continue
			var ng: float = gscore[c] + (1.41421 if d.x != 0 and d.y != 0 else 1.0)
			if not gscore.has(n) or ng < gscore[n] - 1e-4:
				gscore[n] = ng
				came[n] = c
				fscore[n] = ng + center_of(n).distance_to(center_of(g))
				if not open.has(n):
					open.append(n)
	if not came.has(g):
		out.append(center_of(s))
		return out
	var cells: Array = [g]
	var cur := g
	while came.has(cur):
		cur = came[cur]
		cells.push_front(cur)
	# 직선으로 갈 수 있는 중간 칸은 건너뛰기
	var pts: Array = []
	for c in cells:
		pts.append(center_of(c))
	pts[pts.size() - 1] = to if not is_blocked(cell_of(to)) else center_of(g)
	var anchor: Vector2 = from
	var i := 0
	while i < pts.size():
		var j := pts.size() - 1
		while j > i and not line_clear(anchor, pts[j]):
			j -= 1
		out.append(pts[j])
		anchor = pts[j]
		i = j + 1
	return out
