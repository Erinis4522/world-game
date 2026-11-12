class_name SvWorld3D
extends Node3D
## 일반 모니터의 3D 전투 화면. 전투 계산은 하지 않고 SvState를 보여 주기만 한다.
## 카메라는 대표 캐릭터를 따라다닌다 (맵 전체가 한 화면에 들어오지 않음). 그림자·후처리 없음.

var controller: SvController
var camera: Camera3D
var _cam_target := Vector3.ZERO
var _heroes: Dictionary = {}  # id -> SvModels.Unit
var _enemies: Dictionary = {}  # id -> Unit
var _pool: Dictionary = {}  # type -> [Unit]
var _dying: Array = []  # [{unit, until, type}]
var _walls: Dictionary = {}  # Vector2i -> {node, t0}
var _bombs: Array = []
var _fx: Array = []
var _fx_pool: Array = []
var _ghosts: Array = []
var _ghost_root: Node3D
var _units_root: Node3D
var _gates: Array = []
var _base_glow: MeshInstance3D
var _base_flash := -10.0
var now := 0.0

const CAM_OFFSET := Vector3(0, 13.5, 10.5)


func setup(c: SvController) -> void:
	controller = c
	controller.battle_events.connect(_on_events)
	controller.phase_changed.connect(_on_phase)


func _ready() -> void:
	SvData.ensure_loaded()
	var sz := SvData.map_size()
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#9cc9e6")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#dfe8f0")
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(-30), 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = false
	add_child(sun)
	camera = Camera3D.new()
	camera.fov = 45.0
	camera.current = true
	add_child(camera)
	_cam_target = Vector3(SvData.base_center().x, 0, SvData.base_center().y)
	_place_camera(_cam_target, 1.0)
	var static_root := Node3D.new()
	add_child(static_root)
	_build_terrain(static_root, sz)
	_units_root = Node3D.new()
	add_child(_units_root)
	_ghost_root = Node3D.new()
	add_child(_ghost_root)


func w3(p: Vector2, y := 0.0) -> Vector3:
	return Vector3(p.x, y, p.y)


func screen_pos(p: Vector2, height := 0.0) -> Vector2:
	return camera.unproject_position(w3(p, height))


func on_screen(p: Vector2, height := 0.0) -> bool:
	return not camera.is_position_behind(w3(p, height)) and get_viewport().get_visible_rect().grow(-10).has_point(screen_pos(p, height))


func _place_camera(target: Vector3, k: float) -> void:
	_cam_target = _cam_target.lerp(target, k)
	camera.position = _cam_target + CAM_OFFSET
	camera.look_at(_cam_target + Vector3(0, 0.6, 0), Vector3.UP)


# ---------------- 지형 ----------------

func _build_terrain(root: Node3D, sz: Vector2) -> void:
	var outer := PlaneMesh.new()
	outer.size = Vector2(sz.x + 60, sz.y + 60)
	SvModels.part(root, outer, SvModels.mat(SvModels.c("#5f9a48")), Vector3(sz.x * 0.5, -0.03, sz.y * 0.5))
	var grass := PlaneMesh.new()
	grass.size = sz
	SvModels.part(root, grass, SvModels.mat(SvModels.c("#7dbb5a")), Vector3(sz.x * 0.5, -0.01, sz.y * 0.5))
	var bc := SvData.base_center()
	SvModels.part(root, SvModels.cyl(7.5, 7.5, 0.02, 32), SvModels.mat(SvModels.c("#c9c1ad")), Vector3(bc.x, 0.0, bc.y))
	var width := float(SvData.cfg["map"].get("road_width", 3))
	for r in SvData.roads():
		var pts := SvData.road_points(r)
		for layer in [[width + 0.5, SvModels.c("#a5834f"), 0.005], [width, SvModels.c("#d2ad73"), 0.012]]:
			for i in range(1, pts.size()):
				var a := pts[i - 1]
				var b := pts[i]
				var mid := (a + b) * 0.5
				var seg := SvModels.part(root, SvModels.box(Vector3(layer[0], 0.01, a.distance_to(b))), SvModels.mat(layer[1]), Vector3(mid.x, layer[2], mid.y))
				seg.rotation.y = atan2(b.x - a.x, b.y - a.y)
			for p in pts:
				SvModels.part(root, SvModels.cyl(layer[0] * 0.5, layer[0] * 0.5, 0.01, 16), SvModels.mat(layer[1]), Vector3(p.x, layer[2], p.y))
		var inward := (pts[1] - pts[0]).normalized()
		_gates.append(SvModels.gate(root, w3(pts[0] + inward * 0.6), inward))
	var g := SvGrid.from_config()
	var tree_kinds := ["tree_single_A", "tree_single_B", "trees_A_small", "trees_B_small"]
	var buckets: Dictionary = {}
	for cell in g.kind.keys():
		if g.kind[cell] != "tree":
			continue
		var h := SvGrid._hash01(cell.x, cell.y, 99)
		var k: String = tree_kinds[int(h * tree_kinds.size()) % tree_kinds.size()]
		if not buckets.has(k):
			buckets[k] = []
		buckets[k].append(cell)
	for k in buckets.keys():
		_multimesh(root, k, buckets[k], 1.9, 0.35)
	var rocks: Array = []
	for j in g.h:
		for i in g.w:
			var cc := Vector2i(i, j)
			if not g.is_blocked(cc) and not g.is_road(cc) and SvGrid._hash01(i, j, 5) < 0.03:
				rocks.append(cc)
	_multimesh(root, "rock_single_A", rocks, 2.2, 0.0)
	for p in SvData.cfg["map"].get("village_props", []):
		var n := SvModels.prop(str(p["model"]))
		n.position = w3(Vector2(float(p["pos"][0]), float(p["pos"][1])))
		n.rotation.y = deg_to_rad(float(p.get("rot", 0)))
		n.scale = Vector3.ONE * float(p.get("scale", 2.0))
		root.add_child(n)
	_base_glow = SvModels.part(root, SvModels.cyl(4.2, 4.2, 0.02, 32), SvModels.mat(Color(0.35, 0.95, 0.9, 0.35), 0.8, true), Vector3(bc.x, 0.03, bc.y))


func _multimesh(root: Node3D, model: String, cells: Array, scale: float, jitter: float) -> void:
	var mx: Array = SvModels.first_mesh(model)
	if mx[0] == null or cells.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mx[0]
	mm.instance_count = cells.size()
	for i in cells.size():
		var cell: Vector2i = cells[i]
		var h1 := SvGrid._hash01(cell.x, cell.y, 31)
		var h2 := SvGrid._hash01(cell.x, cell.y, 57)
		var pos := Vector3(cell.x + 0.5 + (h1 - 0.5) * jitter, 0, cell.y + 0.5 + (h2 - 0.5) * jitter)
		var b := Basis(Vector3.UP, h1 * TAU).scaled(Vector3.ONE * scale * (0.85 + 0.3 * h2))
		mm.set_instance_transform(i, Transform3D(b, pos) * mx[1])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)


# ---------------- 매 프레임 ----------------

func _on_phase(p: String) -> void:
	if p == SvController.INTRO or p == SvController.ATTRACT:
		_clear_units()


func _clear_units() -> void:
	for k in _heroes.keys():
		_heroes[k].root.queue_free()
	_heroes.clear()
	for k in _enemies.keys():
		_release(k)
	for d in _dying:
		d["unit"].root.visible = false
		_pool_put(d["type"], d["unit"])
	_dying.clear()
	for c in _walls.keys():
		_walls[c]["node"].queue_free()
	_walls.clear()
	for b in _bombs:
		b.visible = false
	for f in _fx:
		f["node"].visible = false
		_fx_pool.append(f["node"])
	_fx.clear()
	_clear_ghosts()


func _process(delta: float) -> void:
	now += delta
	for g in _gates:
		var portal: Node3D = g.get_node("Portal")
		portal.scale = Vector3(1.0 + 0.04 * sin(now * 3.0), 1.0, 1.0)
	if _base_glow != null:
		var fl := clampf(1.0 - (now - _base_flash) / 0.35, 0.0, 1.0)
		_base_glow.scale = Vector3.ONE * (1.0 + 0.08 * sin(now * 2.0) + 0.15 * fl)
	_update_fx()
	var s := controller.session if controller != null else null
	if s == null or controller.phase in [SvController.ATTRACT, SvController.SELECT]:
		var bc := SvData.base_center()
		var orbit := Vector3(bc.x + sin(now * 0.12) * 8.0, 0, bc.y - 6.0 + cos(now * 0.12) * 4.0)
		_place_camera(orbit, 0.02)
		return
	var st := s.state
	var a := controller.alpha()
	var pl: SvState.SvHero = st.player()
	var follow: Vector2 = pl.prev_pos.lerp(pl.pos, a) if pl.alive() else SvData.base_center() + Vector2(0, -3)
	_place_camera(w3(follow), clampf(delta * 5.0, 0.0, 1.0))
	_sync(st, a)
	_sync_walls(st)
	_sync_ghosts(s)


func _sync(st: SvState, a: float) -> void:
	for h in st.heroes:
		if not _heroes.has(h.id):
			var u := SvModels.hero_unit(h.type)
			_units_root.add_child(u.root)
			_heroes[h.id] = u
		var hu: SvModels.Unit = _heroes[h.id]
		var p: Vector2 = h.prev_pos.lerp(h.pos, a)
		hu.root.position = w3(p)
		hu.root.rotation.y = lerp_angle(hu.root.rotation.y, atan2(h.facing.x, h.facing.y), 0.25)
		if hu.anim != null:
			hu.anim.speed_scale = maxf(controller.time_scale, 0.05)
		if not h.alive():
			if hu.current != "Death_A":
				hu.lock_until = 0.0
				hu.play_once("Death_A", now, 999.0)
			continue
		if hu.current == "Death_A":
			hu.lock_until = 0.0
			hu.current = ""
		if st.time < h.building_until:
			hu.play_loop("Interact", now)
		elif h.moving:
			hu.play_loop("Running_A", now)
		else:
			hu.play_loop("Idle", now)
	var seen: Dictionary = {}
	for e in st.enemies:
		if not e.alive:
			continue
		seen[e.id] = true
		if not _enemies.has(e.id):
			_enemies[e.id] = _pool_take(e.type)
		var eu: SvModels.Unit = _enemies[e.id]
		eu.root.position = w3(e.prev_pos.lerp(e.pos, a))
		eu.root.rotation.y = lerp_angle(eu.root.rotation.y, atan2(e.facing.x, e.facing.y), 0.3)
		if eu.anim != null:
			eu.anim.speed_scale = maxf(controller.time_scale, 0.05)
		if e.attacking:
			if now >= eu.lock_until:
				eu.play_once(eu.attack_anim, now)
		else:
			eu.play_loop("Walking_D_Skeletons" if e.type != "FAST" else "Running_A", now)
	for id in _enemies.keys():
		if not seen.has(id):
			var eu2: SvModels.Unit = _enemies[id]
			_enemies.erase(id)
			eu2.lock_until = 0.0
			var death := "Death_C_Skeletons" if eu2.anim != null and eu2.anim.has_animation("Death_C_Skeletons") else "Death_A"
			eu2.play_once(death, now, 1.0)
			_dying.append({"unit": eu2, "until": now + 1.0, "type": eu2.root.get_meta("type")})
	var keep: Array = []
	for d in _dying:
		if now >= float(d["until"]):
			d["unit"].root.visible = false
			_pool_put(d["type"], d["unit"])
		else:
			keep.append(d)
	_dying = keep
	while _bombs.size() < st.projectiles.size():
		var b := MeshInstance3D.new()
		b.mesh = SvModels.sphere(0.18)
		b.material_override = SvModels.mat(SvModels.c("#2a2a30"))
		_units_root.add_child(b)
		_bombs.append(b)
	for i in _bombs.size():
		var bn: MeshInstance3D = _bombs[i]
		bn.visible = i < st.projectiles.size()
		if bn.visible:
			var pr: SvState.SvProjectile = st.projectiles[i]
			bn.position = w3(pr.prev_pos.lerp(pr.pos, a), 0.9)


func _pool_take(type: String) -> SvModels.Unit:
	var pool: Array = _pool.get(type, [])
	if not pool.is_empty():
		var u: SvModels.Unit = pool.pop_back()
		u.root.visible = true
		u.lock_until = 0.0
		u.current = ""
		return u
	var nu := SvModels.enemy_unit(type)
	nu.root.set_meta("type", type)
	_units_root.add_child(nu.root)
	return nu


func _pool_put(type: String, u: SvModels.Unit) -> void:
	if not _pool.has(type):
		_pool[type] = []
	_pool[type].append(u)


func _release(id: int) -> void:
	var u: SvModels.Unit = _enemies[id]
	u.root.visible = false
	_pool_put(u.root.get_meta("type"), u)
	_enemies.erase(id)


# ---------------- 벽·미리보기 ----------------

func _wall_node(st: SvState, cell: Vector2i) -> Node3D:
	var n := SvModels.prop("wall_straight")
	var root := Node3D.new()
	root.add_child(n)
	n.scale = Vector3(0.58, 1.35, 1.15)
	root.position = w3(st.grid.center_of(cell))
	var wid: int = st.grid.walls[cell]["wall"]
	var horiz := st.grid.walls.has(cell + Vector2i(1, 0)) or st.grid.walls.has(cell + Vector2i(-1, 0))
	var vert := st.grid.walls.has(cell + Vector2i(0, 1)) or st.grid.walls.has(cell + Vector2i(0, -1))
	var diag_a := st.grid.walls.has(cell + Vector2i(1, 1)) or st.grid.walls.has(cell + Vector2i(-1, -1))
	var diag_b := st.grid.walls.has(cell + Vector2i(1, -1)) or st.grid.walls.has(cell + Vector2i(-1, 1))
	if horiz and not vert:
		root.rotation.y = 0.0
	elif vert and not horiz:
		root.rotation.y = PI * 0.5
	elif diag_a:
		root.rotation.y = -PI * 0.25
	elif diag_b:
		root.rotation.y = PI * 0.25
	n.set_meta("wall", wid)
	_units_root.add_child(root)
	return root


func _sync_walls(st: SvState) -> void:
	for cell in st.grid.walls.keys():
		if not _walls.has(cell):
			_walls[cell] = {"node": _wall_node(st, cell), "t0": now}
		var rec: Dictionary = _walls[cell]
		var k := clampf((now - float(rec["t0"])) / 0.6, 0.0, 1.0)
		var n: Node3D = rec["node"]
		n.position.y = -1.6 * (1.0 - k)
		var hp_r := float(st.grid.walls[cell]["hp"]) / float(st.grid.walls[cell]["max"])
		n.scale = Vector3(1.0, 0.55 + 0.45 * hp_r, 1.0)
	for cell in _walls.keys():
		if not st.grid.walls.has(cell):
			_burst(st.grid.center_of(cell), Color("#b9ad98"), 1.2, 0.5)
			_walls[cell]["node"].queue_free()
			_walls.erase(cell)


func _clear_ghosts() -> void:
	for g in _ghosts:
		g.queue_free()
	_ghosts.clear()


func _sync_ghosts(s: SvSession) -> void:
	var pr: Dictionary = s.proposal
	var key := str(pr.get("cells", pr.get("pos", ""))) if pr.get("ok", false) else ""
	if _ghost_root.has_meta("key") and str(_ghost_root.get_meta("key")) == key:
		for g in _ghosts:
			g.scale.y = 1.0 + 0.08 * sin(now * 5.0)
		return
	_ghost_root.set_meta("key", key)
	_clear_ghosts()
	if key == "":
		return
	var gm := SvModels.mat(Color(0.3, 0.75, 1.0, 0.45), 0.8, true)
	if pr["kind"] == "WALL":
		for cell in pr["cells"]:
			_ghosts.append(SvModels.part(_ghost_root, SvModels.box(Vector3(0.95, 1.3, 0.95)), gm, w3(s.state.grid.center_of(cell), 0.65)))
	else:
		var u: Dictionary = SvData.ult(pr["hero_type"])
		var h: SvState.SvHero = s.state.heroes[pr["hero"]]
		var at: Vector2 = h.pos if u.get("around_self", false) else pr["pos"]
		if str(u.get("shape", "area")) == "line":
			var dir: Vector2 = (pr["pos"] - h.pos).normalized()
			var len := float(u.get("length", 12))
			var mid: Vector2 = h.pos + dir * len * 0.5
			var g := SvModels.part(_ghost_root, SvModels.box(Vector3(float(u.get("width", 1.0)) * 2.0, 0.1, len)), SvModels.mat(Color(1, 0.6, 0.2, 0.4), 0.8, true), w3(mid, 0.1))
			g.rotation.y = atan2(dir.x, dir.y)
			_ghosts.append(g)
		else:
			var r := float(u.get("radius", float(u.get("chain_range", 4.0))))
			_ghosts.append(SvModels.part(_ghost_root, SvModels.cyl(r, r, 0.1, 32), SvModels.mat(Color(1, 0.6, 0.2, 0.35), 0.8, true), w3(at, 0.08)))


# ---------------- 효과 ----------------

func _on_events(events: Array) -> void:
	for ev in events:
		match ev["type"]:
			"ATTACK":
				var hu: SvModels.Unit = _heroes.get(ev["hero"])
				if hu != null:
					hu.play_once(hu.attack_anim, now, 0.45)
				var col := Color.from_string(str(SvData.hero(ev["hero_type"]).get("color", "#ffffff")), Color.WHITE).lightened(0.25)
				var from: Vector2 = ev["from"]
				var pts: Array = ev["points"]
				match ev["hero_type"]:
					"LIGHTNING":
						var prev := from
						for p in pts:
							_beam(prev, p, Color("#e6d2ff"), 0.08, 0.18)
							prev = p
					"SWORD", "PLAYER", "BUILDER":
						for p in pts:
							_burst(p, Color("#f2f6ff"), 0.5, 0.16)
					"BOMB", "FIRE":
						pass
					"SNIPER":
						_beam(from, pts[0], Color("#fff2c2"), 0.07, 0.3)
					_:
						_beam(from, pts[0], col, 0.05, 0.16)
			"EXPLODE":
				_burst(ev["pos"], Color("#ff8a2e") if ev.get("kind", "") == "FIRE" else Color("#ffd27a"), float(ev["radius"]), 0.35)
			"KILL":
				_burst(ev["pos"], Color("#cfe8ff"), 0.6, 0.3)
			"BASE_HIT":
				_base_flash = now
			"BUILD":
				var bu: SvModels.Unit = _heroes.get(1)
				if bu != null:
					bu.play_once("Interact", now, 1.2)
				for cell in ev["cells"]:
					_burst(Vector2(cell.x + 0.5, cell.y + 0.5), Color("#d8c7a5"), 0.9, 0.5)
			"WALL_HIT":
				_burst(Vector2(ev["cell"].x + 0.5, ev["cell"].y + 0.5), Color("#c9bba1"), 0.5, 0.2)
			"ULT":
				var uu: SvModels.Unit = _heroes.get(ev["hero"])
				if uu != null:
					uu.play_once(uu.ult_anim, now, 1.0)
				var ucol := Color.from_string(str(SvData.hero(ev["hero_type"]).get("color", "#ffffff")), Color.WHITE)
				match str(ev["shape"]):
					"line":
						_beam(ev["from"], ev["pos"], Color("#fff2c2"), 0.35, 0.6)
					"chain":
						_burst(ev["pos"], ucol.lightened(0.4), 4.0, 0.7)
					_:
						_burst(ev["pos"], ucol.lightened(0.3), float(ev["radius"]) * 1.1, 0.8)
						_burst(ev["pos"], Color(1, 1, 0.9), float(ev["radius"]) * 0.5, 0.4)


func _fx_node() -> MeshInstance3D:
	if not _fx_pool.is_empty():
		var n: MeshInstance3D = _fx_pool.pop_back()
		n.visible = true
		return n
	var mi := MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _beam(a: Vector2, b: Vector2, col: Color, width: float, dur: float) -> void:
	var n := _fx_node()
	n.mesh = SvModels.box(Vector3(width, width, 1.0))
	var pa := w3(a, 0.9)
	var pb := w3(b, 0.6)
	var l := pa.distance_to(pb)
	n.rotation = Vector3.ZERO
	n.scale = Vector3.ONE
	n.position = (pa + pb) * 0.5
	if l > 0.01:
		n.look_at(pb, Vector3.UP)
	n.scale = Vector3(1, 1, maxf(l, 0.01))
	(n.material_override as StandardMaterial3D).albedo_color = col
	_fx.append({"node": n, "t0": now, "dur": dur, "kind": "beam", "col": col})


func _burst(p: Vector2, col: Color, radius: float, dur: float) -> void:
	var n := _fx_node()
	n.mesh = SvModels.sphere(1.0, 12, 6)
	n.rotation = Vector3.ZERO
	n.position = w3(p, 0.3)
	n.scale = Vector3.ONE * radius * 0.4
	(n.material_override as StandardMaterial3D).albedo_color = col
	_fx.append({"node": n, "t0": now, "dur": dur, "kind": "burst", "col": col, "r": radius})


func _update_fx() -> void:
	var keep: Array = []
	for f in _fx:
		var k := (now - float(f["t0"])) / float(f["dur"])
		var n: MeshInstance3D = f["node"]
		if k >= 1.0:
			n.visible = false
			_fx_pool.append(n)
			continue
		var col: Color = f["col"]
		col.a = (1.0 - k) * 0.8
		(n.material_override as StandardMaterial3D).albedo_color = col
		if f["kind"] == "burst":
			n.scale = Vector3(1, 0.5, 1) * float(f["r"]) * (0.4 + 0.6 * k)
		keep.append(f)
	_fx = keep
