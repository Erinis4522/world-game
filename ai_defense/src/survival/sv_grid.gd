class_name SvGrid
extends RefCounted
## 이동 판단용 2D 평면 격자 (3D는 이 결과를 보여 주기만 함, 물리엔진 없음).
##  - 칸 (i, j) = [i, i+1) × [j, j+1). 1칸 = 3D 1m
##  - 지형: 길(road), 풀밭, 숲·건물(막힘), 기지, 건설한 벽(내구도 있음)
##  - 적: 기지까지 '비용' 흐름장 하나로 길을 찾는다. 길 1, 풀밭 offroad_cost, 벽은 부숴야 하므로 wall_break_cost
##    → 벽이 길을 막으면 돌아갈 길이 싼지, 벽을 부수는 게 싼지를 계산 결과로 고른다
##  - 아군: A* (벽·숲·건물은 못 지나감)

const INF_D := 1.0e9
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

var w := 60
var h := 40
var blocked := PackedByteArray()  # 1 = 숲·건물·기지 (영구)
var road := PackedByteArray()  # 1 = 길
var road_id: Dictionary = {}  # Vector2i -> 길 id (가장 가까운 길)
var kind: Dictionary = {}  # Vector2i -> 막힌 칸 종류 (tree/building/base)
var walls: Dictionary = {}  # Vector2i -> {hp, max, wall}
var base_cells: Array = []
var flow := PackedFloat32Array()
var version := 0
var offroad_cost := 6.0
var wall_cost := 28.0


static func from_config() -> SvGrid:
	SvData.ensure_loaded()
	var g := SvGrid.new()
	var m: Dictionary = SvData.cfg["map"]
	g.w = int(m["w"])
	g.h = int(m["h"])
	g.offroad_cost = float(SvData.sec("build", "offroad_cost", 6))
	g.wall_cost = float(SvData.sec("build", "wall_break_cost", 28))
	g.blocked.resize(g.w * g.h)
	g.blocked.fill(0)
	g.road.resize(g.w * g.h)
	g.road.fill(0)
	var half := float(m.get("road_width", 3)) * 0.5
	var road_d := PackedFloat32Array()
	road_d.resize(g.w * g.h)
	road_d.fill(INF_D)
	for r in SvData.roads():
		var pts := SvData.road_points(r)
		for j in g.h:
			for i in g.w:
				var c := Vector2(i + 0.5, j + 0.5)
				var d := INF_D
				for k in range(1, pts.size()):
					d = minf(d, Geometry2D.get_closest_point_to_segment(c, pts[k - 1], pts[k]).distance_to(c))
				var ix := j * g.w + i
				if d < road_d[ix]:
					road_d[ix] = d
					g.road_id[Vector2i(i, j)] = r["id"]
				if d <= half:
					g.road[ix] = 1
	# 기지
	var b: Array = m["base_rect"]
	for i in range(int(b[0]), int(b[0]) + int(b[2])):
		for j in range(int(b[1]), int(b[1]) + int(b[3])):
			g._set_perm(Vector2i(i, j), "base")
			g.base_cells.append(Vector2i(i, j))
	# 마을 건물 (작은 발자국)
	var bc := SvData.base_center()
	for p in m.get("village_props", []):
		var pp := Vector2(float(p["pos"][0]), float(p["pos"][1]))
		if str(p["model"]).contains("castle"):
			continue
		var c := g.cell_of(pp)
		for dx in [-1, 0]:
			for dy in [-1, 0]:
				var cc: Vector2i = c + Vector2i(dx, dy)
				if g.inside(cc) and g.road[g.idx(cc)] == 0:
					g._set_perm(cc, "building")
	# 숲: 길에서 조금 떨어진 곳, 마을 밖, 결정적 무작위
	var dens := float(m.get("forest_density", 0.2))
	var seed_v := int(m.get("forest_seed", 1))
	var margin := half + float(m.get("forest_road_margin", 2))
	var vr := float(m.get("village_radius", 8))
	for j in g.h:
		for i in g.w:
			var ix := j * g.w + i
			if g.blocked[ix] == 1 or road_d[ix] <= margin:
				continue
			var c := Vector2(i + 0.5, j + 0.5)
			if c.distance_to(bc) < vr:
				continue
			var coarse := _hash01(int(i / 3), int(j / 3), seed_v)
			var fine := _hash01(i, j, seed_v + 7)
			var edge := mini(mini(i, j), mini(g.w - 1 - i, g.h - 1 - j))
			if edge <= 1 or (coarse < dens * 1.7 and fine < 0.75) or fine < dens * 0.25:
				g._set_perm(Vector2i(i, j), "tree")
	g.rebuild_flow()
	return g


static func _hash01(a: int, b: int, s: int) -> float:
	var x := (a * 73856093) ^ (b * 19349663) ^ (s * 83492791)
	x = (x ^ (x >> 13)) * 1274126177
	x = x ^ (x >> 16)
	return float(absi(x) % 10000) / 10000.0


func _set_perm(c: Vector2i, k: String) -> void:
	if not inside(c):
		return
	blocked[idx(c)] = 1
	kind[c] = k


func clone() -> SvGrid:
	var c := SvGrid.new()
	c.w = w
	c.h = h
	c.blocked = blocked.duplicate()
	c.road = road.duplicate()
	c.road_id = road_id
	c.kind = kind
	c.walls = walls.duplicate(true)
	c.base_cells = base_cells
	c.flow = flow.duplicate()
	c.version = version
	c.offroad_cost = offroad_cost
	c.wall_cost = wall_cost
	return c


func inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h


func idx(c: Vector2i) -> int:
	return c.y * w + c.x


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x)), int(floor(p.y)))


func center_of(c: Vector2i) -> Vector2:
	return Vector2(c.x + 0.5, c.y + 0.5)


func is_perm_blocked(c: Vector2i) -> bool:
	return not inside(c) or blocked[idx(c)] == 1


func is_wall(c: Vector2i) -> bool:
	return walls.has(c)


func is_blocked(c: Vector2i) -> bool:
	## 이동 불가 (숲·건물·기지·벽)
	return is_perm_blocked(c) or walls.has(c)


func is_road(c: Vector2i) -> bool:
	return inside(c) and road[idx(c)] == 1


func road_of(p: Vector2) -> String:
	return str(road_id.get(cell_of(p), ""))


func can_build(c: Vector2i) -> bool:
	return inside(c) and not is_blocked(c)


func walkable_pos(p: Vector2) -> bool:
	return not is_blocked(cell_of(p))


func _diag_ok(c: Vector2i, d: Vector2i, for_enemy := false) -> bool:
	if d.x == 0 or d.y == 0:
		return true
	var a := c + Vector2i(d.x, 0)
	var b := c + Vector2i(0, d.y)
	if for_enemy:
		return not is_perm_blocked(a) and not is_perm_blocked(b) and not walls.has(a) and not walls.has(b)
	return not is_blocked(a) and not is_blocked(b)


# ---------------- 벽 ----------------

func add_wall(cells: Array, wall_id: int, hp: float) -> void:
	for c in cells:
		if can_build(c):
			walls[c] = {"hp": hp, "max": hp, "wall": wall_id}
	version += 1
	rebuild_flow()


func damage_wall(c: Vector2i, dmg: float) -> bool:
	## 부서지면 true
	if not walls.has(c):
		return false
	walls[c]["hp"] = float(walls[c]["hp"]) - dmg
	if float(walls[c]["hp"]) <= 0.0:
		walls.erase(c)
		version += 1
		rebuild_flow()
		return true
	return false


# ---------------- 흐름장 (적 → 기지) ----------------

func step_cost(n: Vector2i) -> float:
	if walls.has(n):
		return wall_cost
	return 1.0 if road[idx(n)] == 1 else offroad_cost


func rebuild_flow() -> void:
	flow.resize(w * h)
	flow.fill(INF_D)
	# 다익스트라 (이진 힙: 비용 배열 + 칸 번호 배열)
	var hk := PackedFloat32Array()
	var hv := PackedInt32Array()
	for bc in base_cells:
		for d in DIRS:
			var n: Vector2i = bc + d
			if inside(n) and not is_perm_blocked(n) and flow[idx(n)] > 0.0:
				flow[idx(n)] = 0.0
				_hpush(hk, hv, 0.0, idx(n))
	while not hk.is_empty():
		var dc := hk[0]
		var ci := hv[0]
		_hpop(hk, hv)
		if dc > flow[ci] + 1e-4:
			continue
		var c := Vector2i(ci % w, ci / w)
		for d in DIRS:
			var n: Vector2i = c + d
			if is_perm_blocked(n) or not _diag_ok(c, d, true):
				continue
			var nd := dc + step_cost(n) * (1.41421 if d.x != 0 and d.y != 0 else 1.0)
			var ni := idx(n)
			if nd < flow[ni] - 1e-4:
				flow[ni] = nd
				_hpush(hk, hv, nd, ni)
	version += 1


static func _hpush(hk: PackedFloat32Array, hv: PackedInt32Array, k: float, v: int) -> void:
	hk.append(k)
	hv.append(v)
	var i := hk.size() - 1
	while i > 0:
		var p := (i - 1) / 2
		if hk[p] <= hk[i]:
			break
		var tk := hk[p]
		hk[p] = hk[i]
		hk[i] = tk
		var tv := hv[p]
		hv[p] = hv[i]
		hv[i] = tv
		i = p


static func _hpop(hk: PackedFloat32Array, hv: PackedInt32Array) -> void:
	var last := hk.size() - 1
	hk[0] = hk[last]
	hv[0] = hv[last]
	hk.resize(last)
	hv.resize(last)
	var i := 0
	var n := hk.size()
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var m := i
		if l < n and hk[l] < hk[m]:
			m = l
		if r < n and hk[r] < hk[m]:
			m = r
		if m == i:
			break
		var tk := hk[m]
		hk[m] = hk[i]
		hk[i] = tk
		var tv := hv[m]
		hv[m] = hv[i]
		hv[i] = tv
		i = m


func flow_distance(p: Vector2) -> float:
	var c := cell_of(p)
	if is_perm_blocked(c):
		return INF_D
	return flow[idx(c)]


func flow_next(p: Vector2) -> Vector2i:
	## 적이 다음에 갈 칸 (벽 칸일 수 있음 → 그러면 부숴야 함)
	var c := cell_of(p)
	if is_perm_blocked(c) or walls.has(c):
		return nearest_open(c)
	var best := c
	var bd := flow[idx(c)]
	for d in DIRS:
		var n: Vector2i = c + d
		if is_perm_blocked(n) or not _diag_ok(c, d, true):
			continue
		if flow[idx(n)] < bd - 1e-4:
			bd = flow[idx(n)]
			best = n
	return best


func nearest_open(c: Vector2i) -> Vector2i:
	if inside(c) and not is_blocked(c):
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

func find_path(from: Vector2, to: Vector2, max_nodes := 3000) -> PackedVector2Array:
	var s := nearest_open(cell_of(from))
	var g := nearest_open(cell_of(clamp_to_map(to)))
	var out := PackedVector2Array()
	if s == g or line_clear(from, center_of(g)):
		out.append(center_of(g) if is_blocked(cell_of(to)) else clamp_to_map(to))
		return out
	var gscore: Dictionary = {s: 0.0}
	var came: Dictionary = {}
	var open: Array = [s]
	var fscore: Dictionary = {s: center_of(s).distance_to(center_of(g))}
	var guard := 0
	while not open.is_empty() and guard < max_nodes:
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


func path_length(from: Vector2, to: Vector2) -> float:
	var p := find_path(from, to)
	var l := 0.0
	var prev := from
	for q in p:
		l += prev.distance_to(q)
		prev = q
	if p.is_empty() or p[p.size() - 1].distance_to(to) > 1.5:
		return INF_D
	return l
