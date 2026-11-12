class_name SvWorld3D
extends Node3D
## 일반 모니터의 3D 전투 화면. 전투 계산은 하지 않고 SvState를 보여 주기만 한다.
## 고정 쿼터뷰 카메라, 그림자·후처리 없음 (내장그래픽 기준).

var controller: SvController
var camera: Camera3D
var _heroes: Dictionary = {}  # hero id -> {root, body, arm, type}
var _enemies: Dictionary = {}  # enemy id -> node
var _enemy_pool: Dictionary = {}  # type -> [node]
var _bombs: Array = []
var _fx: Array = []  # {node, t0, dur, kind}
var _fx_pool: Array = []
var _player_ring: Node3D
var _goal_marker: Node3D
var _base: Node3D
var _gates: Array = []
var _units_root: Node3D
var _hero_anim: Dictionary = {}  # hero id -> {atk_t0, special}
var _enemy_hit: Dictionary = {}  # enemy id -> time
var _base_flash := -10.0
var now := 0.0

const HERO_VIS_SCALE := 1.75  # 보이는 크기만 키움 (충돌·사거리 계산은 그대로)
const ENEMY_VIS_SCALE := 1.5


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
	e.background_color = Color("#3d4652")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#c9d4e2")
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(-35), 0)
	sun.light_energy = 1.05
	sun.shadow_enabled = false
	add_child(sun)
	camera = Camera3D.new()
	camera.fov = 38.0
	camera.position = Vector3(sz.x * 0.5, 25.0, sz.y * 0.5 + 15.0)

	camera.current = true
	add_child(camera)
	camera.look_at(Vector3(sz.x * 0.5, 0, sz.y * 0.5 + 0.9), Vector3.UP)
	var static_root := Node3D.new()
	add_child(static_root)
	SvModels.ground(static_root, sz.x, sz.y)
	for o in SvData.cfg["map"]["obstacles"]:
		SvModels.obstacle(static_root, o["rect"], str(o.get("kind", "rock")))
	var bc := SvData.base_center()
	_base = SvModels.base_hub(static_root, Vector3(bc.x, 0, bc.y))
	for g in SvData.cfg["map"]["gates"]:
		var p := Vector2(float(g["pos"][0]), float(g["pos"][1]))
		var inward := _edge_normal(p)
		_gates.append(SvModels.gate(static_root, Vector3(p.x, 0, p.y), inward))
	_units_root = Node3D.new()
	add_child(_units_root)
	_player_ring = SvModels.player_ring()
	_units_root.add_child(_player_ring)
	_goal_marker = SvModels.goal_marker()
	_units_root.add_child(_goal_marker)


func w3(p: Vector2, y := 0.0) -> Vector3:
	return Vector3(p.x, y, p.y)


func screen_pos(p: Vector2, height := 0.0) -> Vector2:
	## HUD가 말풍선·체력바를 그릴 화면 좌표
	return camera.unproject_position(w3(p, height))


func _on_phase(p: String) -> void:
	if p == SvController.INTRO or p == SvController.ATTRACT:
		_clear_units()


func _clear_units() -> void:
	for k in _heroes.keys():
		_heroes[k]["root"].queue_free()
	_heroes.clear()
	for k in _enemies.keys():
		_release_enemy(k)
	for b in _bombs:
		b.visible = false
	for f in _fx:
		f["node"].visible = false
		_fx_pool.append(f["node"])
	_fx.clear()
	_hero_anim.clear()


# ---------------- 매 프레임 ----------------

func _process(delta: float) -> void:
	now += delta
	if _base != null:
		var cr: Node3D = _base.get_node("Crystal")
		cr.rotation.y += delta * 0.8
		cr.position.y = 1.25 + sin(now * 2.0) * 0.08
		var flash := clampf(1.0 - (now - _base_flash) / 0.3, 0.0, 1.0)
		cr.scale = Vector3.ONE * (1.0 + 0.25 * flash)
	for g in _gates:
		var portal: Node3D = g.get_node("Portal")
		portal.scale = Vector3(1.0 + 0.04 * sin(now * 3.0), 1.0, 1.0)
	_update_fx()
	var s := controller.session if controller != null else null
	if s == null:
		_player_ring.visible = false
		_goal_marker.visible = false
		return
	_sync(s.state, controller.alpha())


func _sync(st: SvState, a: float) -> void:
	# 아군
	for h in st.heroes:
		if not _heroes.has(h.id):
			var root := SvModels.hero(h.type)
			root.scale = Vector3.ONE * HERO_VIS_SCALE
			_units_root.add_child(root)
			_heroes[h.id] = {"root": root, "body": root.get_node("Body"), "arm": root.get_node("Body/Arm"), "type": h.type}
		var rec: Dictionary = _heroes[h.id]
		var root3: Node3D = rec["root"]
		var body: Node3D = rec["body"]
		var arm: Node3D = rec["arm"]
		root3.visible = h.alive()
		if not h.alive():
			continue
		var p: Vector2 = h.prev_pos.lerp(h.pos, a)
		root3.position = w3(p)
		var face: Vector2 = h.facing
		var target_rot := atan2(face.x, face.y)
		root3.rotation.y = lerp_angle(root3.rotation.y, target_rot, 0.25)
		var bob := absf(sin(now * 10.0)) * 0.08 if h.moving else sin(now * 2.2 + h.id) * 0.015
		body.position = Vector3(0, bob, 0)
		body.scale = Vector3.ONE
		arm.rotation = Vector3.ZERO
		var an: Dictionary = _hero_anim.get(h.id, {})
		if not an.is_empty():
			var k := (now - float(an["t0"])) / (0.7 if an["special"] else 0.3)
			if k < 1.0:
				var swing := sin(k * PI)
				arm.rotation.x = -1.6 * swing
				body.position.z = 0.12 * swing
				if an["special"]:
					body.position.y += sin(k * PI) * 0.6
					body.rotation.y = k * TAU
				else:
					body.rotation.y = 0.0
			else:
				body.rotation.y = 0.0
		if h.is_player:
			_player_ring.visible = true
			_player_ring.position = w3(p)
			_player_ring.get_child(1).position.y = 1.75 + sin(now * 4.0) * 0.08
			_goal_marker.visible = h.goal != Vector2.INF
			if h.goal != Vector2.INF:
				_goal_marker.position = w3(h.goal)
				_goal_marker.scale = Vector3.ONE * (1.0 + 0.1 * sin(now * 6.0))
	if not st.player().alive():
		_player_ring.visible = false
		_goal_marker.visible = false
	# 적
	var seen: Dictionary = {}
	for e in st.enemies:
		if not e.alive:
			continue
		seen[e.id] = true
		if not _enemies.has(e.id):
			_enemies[e.id] = _take_enemy(e.type)
		var n: Node3D = _enemies[e.id]
		var p2: Vector2 = e.prev_pos.lerp(e.pos, a)
		n.position = w3(p2)
		n.rotation.y = lerp_angle(n.rotation.y, atan2(e.facing.x, e.facing.y), 0.3)
		var nb: Node3D = n.get_node("Body")
		var moving: bool = e.pos.distance_to(e.prev_pos) > 0.0005
		nb.position.y = absf(sin(now * 12.0 + e.id)) * 0.06 if moving else 0.0
		nb.position.z = 0.15 * maxf(0.0, sin(now * 8.0 + e.id)) if e.attacking else 0.0
		var hit := clampf(1.0 - (now - float(_enemy_hit.get(e.id, -10.0))) / 0.15, 0.0, 1.0)
		nb.scale = Vector3.ONE * (1.0 + 0.18 * hit)
	for id in _enemies.keys():
		if not seen.has(id):
			_release_enemy(id)
	# 폭탄 투사체
	while _bombs.size() < st.projectiles.size():
		var b := MeshInstance3D.new()
		b.mesh = SvModels.sphere(0.16)
		b.material_override = SvModels.mat(Color("#1d1d22"))
		_units_root.add_child(b)
		_bombs.append(b)
	for i in _bombs.size():
		var bn: MeshInstance3D = _bombs[i]
		bn.visible = i < st.projectiles.size()
		if bn.visible:
			var pr = st.projectiles[i]
			var pp: Vector2 = pr.prev_pos.lerp(pr.pos, a)
			var total: float = maxf(0.01, pr.target.distance_to(pr.prev_pos) + pr.prev_pos.distance_to(pr.pos))
			bn.position = w3(pp, 0.4 + 1.2 * sin(clampf(pp.distance_to(pr.target) / maxf(total, 0.01), 0.0, 1.0) * PI * 0.5))


func _take_enemy(type: String) -> Node3D:
	var pool: Array = _enemy_pool.get(type, [])
	if not pool.is_empty():
		var n: Node3D = pool.pop_back()
		n.visible = true
		return n
	var m := SvModels.enemy(type)
	m.scale = Vector3.ONE * ENEMY_VIS_SCALE
	m.set_meta("type", type)
	_units_root.add_child(m)
	return m


func _release_enemy(id: int) -> void:
	var n: Node3D = _enemies[id]
	n.visible = false
	var t: String = n.get_meta("type")
	if not _enemy_pool.has(t):
		_enemy_pool[t] = []
	_enemy_pool[t].append(n)
	_enemies.erase(id)


# ---------------- 효과 ----------------

func _on_events(events: Array) -> void:
	for ev in events:
		match ev["type"]:
			"ATTACK":
				_hero_anim[ev["hero"]] = {"t0": now, "special": ev.get("special", false) and _special_ok(ev["hero"])}
				var col := Color.from_string(str(GameData.hero(ev["hero_type"]).get("color", "#ffffff")), Color.WHITE).lightened(0.25)
				var from: Vector2 = ev["from"]
				var pts: Array = ev["points"]
				match ev["hero_type"]:
					"LIGHTNING":
						var prev := from
						for p in pts:
							_beam(prev, p, Color("#e6d2ff"), 0.07, 0.18)
							prev = p
					"SWORD":
						for p in pts:
							_burst(p, Color("#f2f6ff"), 0.45, 0.18)
					"BOMB", "FIRE":
						pass
					"SNIPER":
						_beam(from, pts[0], Color("#fff2c2"), 0.06, 0.3)
					_:
						_beam(from, pts[0], col, 0.045, 0.16)
				if _hero_anim[ev["hero"]]["special"]:
					_burst(from, col, 1.6, 0.6)
			"EXPLODE":
				_burst(ev["pos"], Color("#ff8a2e") if ev.get("kind", "") == "FIRE" else Color("#ffd27a"), float(ev["radius"]), 0.35)
			"KILL":
				_burst(ev["pos"], Color("#7ff3e6"), 0.6, 0.3)
			"HIT":
				_enemy_hit[ev["enemy"]] = now
			"BASE_HIT":
				_base_flash = now


var _special_last: Dictionary = {}


func _special_ok(hero_id: int) -> bool:
	if now - float(_special_last.get(hero_id, -10.0)) < 2.2:
		return false
	_special_last[hero_id] = now
	return true


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
	var pa := w3(a, 0.8)
	var pb := w3(b, 0.5)
	var len := pa.distance_to(pb)
	n.position = (pa + pb) * 0.5
	n.scale = Vector3(1, 1, maxf(len, 0.01))
	if len > 0.01:
		n.look_at(pb, Vector3.UP)
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
		col.a = (1.0 - k) * 0.85
		(n.material_override as StandardMaterial3D).albedo_color = col
		if f["kind"] == "burst":
			n.scale = Vector3(1, 0.6, 1) * float(f["r"]) * (0.4 + 0.6 * k)
		keep.append(f)
	_fx = keep


func _edge_normal(p: Vector2) -> Vector2:
	## 게이트가 붙은 맵 가장자리에서 안쪽을 향하는 방향
	var sz := SvData.map_size()
	var d := {Vector2(1, 0): p.x, Vector2(-1, 0): sz.x - p.x, Vector2(0, 1): p.y, Vector2(0, -1): sz.y - p.y}
	var best := Vector2(1, 0)
	var bv := INF
	for k in d.keys():
		if float(d[k]) < bv:
			bv = float(d[k])
			best = k
	return best
