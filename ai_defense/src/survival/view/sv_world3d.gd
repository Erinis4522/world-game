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

const CAM_OFFSET := Vector3(0, 15.5, 11.0)
var _far_hide := 26.0


func setup(c: SvController) -> void:
	controller = c
	controller.battle_events.connect(_on_events)
	controller.phase_changed.connect(_on_phase)


func _ready() -> void:
	SvData.ensure_loaded()
	var sz := SvData.map_size()
	_far_hide = float(SvData.cfg.get("far_hide_distance", 26))
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#9fd3f0")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#e4ecf2")
	e.ambient_light_energy = 0.68
	e.fog_enabled = false
	e.fog_light_color = Color("#a8c4cf")
	e.fog_density = 0.004
	e.fog_sky_affect = 0.0
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(-35), 0)
	sun.light_color = Color("#fff0d8")
	sun.light_energy = 1.2
	sun.shadow_enabled = false
	add_child(sun)
	camera = Camera3D.new()
	camera.fov = 42.0
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
# 바닥: 구운 텍스처 한 장 (SvGround). 숲·바위·풀: Fantasy Stylized Pack + KayKit을 MultiMesh로, 12칸 묶음마다
# 따로 만들어 화면 밖 묶음은 그리지 않게 한다. 출현 게이트 둘레는 숲과 큰 바위, 아래는 성벽·성문·마을(KayKit 한 세트).
# 건물 위치·판정은 data/survival.json 그대로이고, 모습(모델·크기)만 여기서 정한다.

const CHUNK := 12
# 숲 나무 섞기: [팩, 모델, 비율, 목표 높이(m)]
const FOREST_MIX := [
	["TG", "pine1", 0.34, 3.3], ["TG", "pine2", 0.2, 3.9], ["TG", "pine3", 0.14, 3.6],
	["K", "tree_single_A", 0.16, 2.6], ["K", "tree_single_B", 0.16, 2.4],
]
# 출현 게이트 양옆 큰 바위 [모델, x, y, 회전도, 배율]
const GATE_ROCKS := [
	["rock_big_B_gray_2", 16.2, -0.8, 20, 0.34], ["rock_big_B_gray_4", 23.9, -0.9, -40, 0.32],
	["rock_big_B_1", 14.4, -2.2, 0, 0.28], ["rock_big_B_3", 25.8, -2.0, 60, 0.26],
]
# data 모델 이름 → 실제로 보일 KayKit 모델·크기 (여러 색으로 밝게). 빈 이름이면 그리지 않음
const VILLAGE_LOOK := {
	"building_castle_blue": ["building_castle_blue", 1.7],
	"building_home_A_blue": ["building_home_A_red", 2.2],
	"building_home_B_blue": ["building_home_B_yellow", 2.2],
	"building_windmill_blue": ["building_windmill_blue", 2.2],
	"building_tavern_blue": ["building_tavern_blue", 2.1],
	"building_well_blue": ["building_well_blue", 1.9],
	"building_market_blue": ["building_market_blue", 2.0],
	"building_tower_A_blue": ["", 0.0],  # 성문 양옆 탑으로 대신함
}
# 마을 소품 [모델, x, y, 회전도, 배율] (KayKit)
const VILLAGE_DECOR := [
	["barrel", 8.0, 57.6, 0, 2.0], ["crate_A_big", 8.9, 57.9, 20, 1.8], ["sack", 7.4, 58.3, 0, 2.0],
	["wheelbarrow", 31.6, 57.8, -30, 2.0], ["crate_B_big", 32.6, 58.4, 10, 1.8], ["resource_lumber", 37.2, 58.0, 0, 1.8],
	["bucket_water", 16.6, 63.0, 0, 2.0], ["tent", 2.6, 58.0, 20, 1.8], ["weaponrack", 24.0, 57.8, 0, 2.0],
	["trees_A_medium", 1.6, 62.6, 0, 2.0], ["trees_B_medium", 38.4, 62.4, 40, 2.0], ["trees_A_small", 10.0, 63.0, 0, 2.0],
	["trees_B_small", 30.6, 63.2, 0, 2.0],
]
const ROADSIDE_ROCKS := ["rock_small_1", "rock_small_2", "rock_small_3", "rock_small_4", "rock_small_5"]
const FIELD_ROCKS := ["rock_medium_1", "rock_medium_2", "rock_block_1", "rock_block_3"]
const BIG_ROCKS := ["rock_big_B_1", "rock_big_B_3", "rock_big_B_gray_2", "rock_big_B_gray_4"]
const WALL_SCALE := 1.7  # KayKit 성벽 조각(길이 2m)을 같은 비율로 키움 → 한 조각 약 3.4칸

var _scatter_buf: Dictionary = {}  # "팩#모델#묶음" -> [Transform3D]


func _item(pk: String, name: String) -> Array:
	match pk:
		"TG":
			return SvModels.green_item(name)
		"K":
			return SvModels.kay_item(name)
		"R":
			return SvModels.pack_item(SvModels.PACK_ROCKS, name)
	return SvModels.pack_item(SvModels.PACK_TREES, name)


func _scatter(pack: String, item: String, p: Vector2, yaw: float, scl: float) -> void:
	var ch := Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK))
	var key := "%s#%s#%d,%d" % [pack, item, ch.x, ch.y]
	if not _scatter_buf.has(key):
		_scatter_buf[key] = []
	var b := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scl)
	_scatter_buf[key].append(Transform3D(b, Vector3(p.x, 0.0, p.y)))


func _flush_scatter(root: Node3D) -> void:
	for key in _scatter_buf.keys():
		var parts: PackedStringArray = String(key).split("#")
		var it := _item(parts[0], parts[1])
		if it[0] == null:
			continue
		var list: Array = _scatter_buf[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = it[0]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, (list[i] as Transform3D) * (it[1] as Transform3D))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
	_scatter_buf.clear()


func _pick(mix: Array, h: float) -> Array:
	var acc := 0.0
	for m in mix:
		acc += float(m[2])
		if h < acc:
			return m
	return mix[mix.size() - 1]


func _tree_at(mix: Array, p: Vector2, h1: float, h2: float) -> void:
	var m := _pick(mix, h1)
	var it := _item(str(m[0]), str(m[1]))
	var sy: float = (it[2] as Vector3).y
	if sy <= 0.0:
		return
	var s := float(m[3]) / sy * (0.82 + 0.36 * h2)
	_scatter(str(m[0]), str(m[1]), p, h2 * TAU * 3.0, s)


func _kay(root: Node3D, model: String, p: Vector2, rot_deg: float, scl: float, y := 0.0) -> Node3D:
	var n := SvModels.prop(model)
	n.position = w3(p, y)
	n.rotation.y = deg_to_rad(rot_deg)
	n.scale = Vector3.ONE * scl
	root.add_child(n)
	return n


func _build_terrain(root: Node3D, sz: Vector2) -> void:
	var g := SvGrid.from_config()
	# 맵 바깥 먼 바닥(숲색) + 구운 바닥 한 장
	var outer := PlaneMesh.new()
	outer.size = Vector2(sz.x + 160, sz.y + 160)
	SvModels.part(root, outer, SvModels.mat(SvGround.FOREST), Vector3(sz.x * 0.5, -0.03, sz.y * 0.5))
	root.add_child(SvGround.plane(SvGround.build(g)))
	var bc := SvData.base_center()
	for r in SvData.roads():
		var pts := SvData.road_points(r)
		var inward := (pts[1] - pts[0]).normalized()
		_gates.append(SvModels.gate(root, w3(pts[0] + inward * 0.6), inward))
	var gate_p: Vector2 = SvData.road_points(SvData.roads()[0])[0]
	var half := float(SvData.cfg["map"].get("road_width", 4)) * 0.5
	var vy := int(SvData.cfg["map"].get("village_y", g.h))
	# 숲 (맵 안 나무 칸)
	for cell in g.kind.keys():
		if g.kind[cell] != "tree":
			continue
		var h1 := SvGrid._hash01(cell.x, cell.y, 99)
		var h2 := SvGrid._hash01(cell.x, cell.y, 57)
		if h2 < 0.12:
			continue  # 군데군데 빈틈
		var p := Vector2(cell.x + 0.5 + (h1 - 0.5) * 0.5, cell.y + 0.5 + (h2 - 0.5) * 0.5)
		_tree_at(FOREST_MIX, p, h1, h2)
	# 맵 바깥 숲 띠 (출현 게이트 둘레도 숲)
	var ring := 9
	for j in range(-ring, g.h + ring):
		for i in range(-ring, g.w + ring):
			if i >= 0 and i < g.w and j >= 0 and j < g.h:
				continue
			var h1 := SvGrid._hash01(i, j, 13)
			var h2 := SvGrid._hash01(i, j, 71)
			var p := Vector2(i + 0.5 + (h1 - 0.5) * 0.6, j + 0.5 + (h2 - 0.5) * 0.6)
			if j < 0 and absf(p.x - gate_p.x) < 3.2 and p.y > -3.0:
				continue  # 출현 게이트 바로 앞만 비움
			if h1 < 0.5:
				_tree_at(FOREST_MIX, p, SvGrid._hash01(i, j, 5), h2)
			elif h1 > 0.985:
				_scatter("R", BIG_ROCKS[int(h2 * 4) % 4], p, h2 * TAU, 0.22)
	# 풀숲·길가 돌·들판 바위
	for j in g.h:
		for i in g.w:
			var cc := Vector2i(i, j)
			if g.is_blocked(cc) or j >= vy:
				continue
			var h1 := SvGrid._hash01(i, j, 211)
			var h2 := SvGrid._hash01(i, j, 307)
			var c := Vector2(i + 0.5, j + 0.5)
			var rd := _road_dist(c)
			var p := c + Vector2(h1 - 0.5, h2 - 0.5) * 0.7
			if rd > half - 0.2 and rd < half + 1.2:
				if h1 < 0.12:
					_scatter("R", ROADSIDE_ROCKS[int(h2 * 5) % 5], p, h2 * TAU, 0.13 + 0.06 * h2)
				elif h1 > 0.8:
					_scatter("T", "grass_green_group", p, h2 * TAU, 0.42 + 0.2 * h2)
			elif rd >= half + 1.2:
				if h1 < 0.22:
					_scatter("T", "grass_green_group" if h2 < 0.75 else "grass_green", p, h2 * TAU, 0.45 + 0.25 * h2)
				elif h1 > 0.985:
					_scatter("R", FIELD_ROCKS[int(h2 * 4) % 4], p, h2 * TAU, 0.2 + 0.08 * h2)
	for m in GATE_ROCKS:
		_scatter("R", str(m[0]), Vector2(float(m[1]), float(m[2])), deg_to_rad(float(m[3])), float(m[4]))
	_flush_scatter(root)
	# 마을 건물 (위치는 data, 모습은 VILLAGE_LOOK)
	for p in SvData.cfg["map"].get("village_props", []):
		var model := str(p["model"])
		var look: Array = VILLAGE_LOOK.get(model, [model, float(p.get("scale", 2.0))])
		if str(look[0]) == "":
			continue
		_kay(root, str(look[0]), Vector2(float(p["pos"][0]), float(p["pos"][1])), float(p.get("rot", 0)), float(look[1]))
	for d in VILLAGE_DECOR:
		_kay(root, str(d[0]), Vector2(float(d[1]), float(d[2])), float(d[3]), float(d[4]))
	_build_town_wall(root, g, bc)
	_base_glow = SvModels.ring(1.9, Color(0.55, 1.0, 0.9, 0.45), 0.1)
	_base_glow.position = w3(bc - Vector2(0, 1.2), 0.05)
	root.add_child(_base_glow)


func _build_town_wall(root: Node3D, g: SvGrid, bc: Vector2) -> void:
	## 성벽 줄을 이어진 구간으로 나눠, KayKit 성벽 조각을 원래 비율 그대로(늘이지 않고) 이어 붙인다.
	## 성문 칸 자리에는 성문 조각과 양옆 탑, 탑 위 깃발.
	var wy := int(SvData.cfg["map"].get("town_wall_y", -1))
	if wy < 0:
		return
	var runs: Array = []  # [시작 x, 끝 x(포함하지 않음)]
	var start := -1
	for i in g.w + 1:
		# 성벽 줄 위의 옛 탑 자리(building)도 성벽으로 이어서 그림 (판정은 둘 다 막힌 칸)
		var is_wall: bool = i < g.w and str(g.kind.get(Vector2i(i, wy), "")) in ["townwall", "building"]
		if is_wall and start < 0:
			start = i
		elif not is_wall and start >= 0:
			runs.append([start, i])
			start = -1
	var zc := wy + 0.5
	var piece := 2.0 * WALL_SCALE
	for r in runs:
		var x0 := float(r[0])
		var x1 := float(r[1])
		var n := maxi(1, int(round((x1 - x0) / piece)))
		var s := (x1 - x0) / (2.0 * n)  # 구간 길이에 딱 맞도록 조금만 조정 (모든 축 같은 비율)
		for k in n:
			_kay(root, "wall_straight", Vector2(x0 + (k + 0.5) * 2.0 * s, zc), 0.0, s)
		# 끝에 모서리 탑 (맵 가장자리 쪽)
		if x0 <= 0.5:
			_tower(root, Vector2(x0 + 0.6, zc), "flag_yellow")
		if x1 >= g.w - 0.5:
			_tower(root, Vector2(x1 - 0.6, zc), "flag_yellow")
	# 성문 + 양옆 탑
	var gx := bc.x
	_kay(root, "wall_straight_gate", Vector2(gx, zc), 0.0, WALL_SCALE)
	_tower(root, Vector2(gx - WALL_SCALE - 0.8, zc), "flag_red")
	_tower(root, Vector2(gx + WALL_SCALE + 0.8, zc), "flag_red")


func _tower(root: Node3D, p: Vector2, flag: String) -> void:
	_kay(root, "building_tower_A_blue", p, 0.0, WALL_SCALE)
	_kay(root, flag, p + Vector2(0, 0.05), 90.0, WALL_SCALE * 1.4, 2.19 * WALL_SCALE)


func _road_dist(p: Vector2) -> float:
	var best := 999.0
	for r in SvData.roads():
		var pts := SvData.road_points(r)
		for i in range(1, pts.size()):
			best = minf(best, Geometry2D.get_closest_point_to_segment(p, pts[i - 1], pts[i]).distance_to(p))
	return best


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
		var fl := clampf(1.0 - (now - _base_flash) / 0.6, 0.0, 1.0)
		_base_glow.visible = fl > 0.0  # 성문이 맞을 때만 번쩍
		var gk := 0.7 + 0.6 * (1.0 - fl)
		_base_glow.scale = Vector3(gk, 0.15, gk)
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
		# 카메라에서 먼 적은 숨기고 애니메이션도 멈춤 (내장그래픽·CPU 부담 줄이기)
		var far := Vector2(eu.root.position.x - _cam_target.x, eu.root.position.z - _cam_target.z).length() > _far_hide
		eu.root.visible = not far
		if eu.anim != null:
			eu.anim.active = not far
		if far:
			continue
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
		if u.anim != null:
			u.anim.active = true
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
				var center: Vector2 = ev.get("center", pts[0])
				var rad := float(ev.get("radius", 0.0))
				# 광역 공격이 한눈에 보이도록: 모양별 효과
				match str(ev.get("fx", "shot")):
					"chain":
						var prev := from
						for p in pts:
							_beam(prev, p, Color("#e6d2ff"), 0.12, 0.25)
							_ring(p, 0.7, Color("#d9c2ff"), 0.25)
							prev = p
					"slash":
						_slash(from, center, rad, Color("#f2f6ff") if ev["hero_type"] != "PLAYER" else Color("#ffe58a"))
					"pierce":
						_beam(from, pts[0], Color("#fff2c2"), 0.18, 0.35)
						_beam(from, pts[0], Color(1, 1, 1), 0.07, 0.2)
					"blast":
						if ev["hero_type"] == "FIRE":
							_bolt(from, center, Color("#ff9a3c"), 0.18, 0.3)
							_ring(center, rad, Color("#ff7a1a"), 0.45, 0.18)
							_burst(center, Color("#ffb35c"), rad * 0.9, 0.35, 0.18)
					"nova":
						_bolt(from, center, col, 0.12, 0.25)
						_ring(center, rad, col, 0.45, 0.12)
					_:
						_bolt(from, center, col, 0.1, 0.18)
						if rad > 0.0:
							_ring(center, rad, col, 0.35, 0.1)
			"EXPLODE":
				_ring(ev["pos"], float(ev["radius"]), Color("#ffcf6a"), 0.45)
				_burst(ev["pos"], Color("#ff8a2e") if ev.get("kind", "") == "FIRE" else Color("#ffd27a"), float(ev["radius"]), 0.4)
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


static var _sphere_mesh: SphereMesh
static var _ring_mesh: TorusMesh


func _burst(p: Vector2, col: Color, radius: float, dur: float, delay := 0.0) -> void:
	if _sphere_mesh == null:
		_sphere_mesh = SvModels.sphere(1.0, 12, 6)
	var n := _fx_node()
	n.mesh = _sphere_mesh
	n.rotation = Vector3.ZERO
	n.position = w3(p, 0.3)
	n.scale = Vector3.ONE * radius * 0.4
	(n.material_override as StandardMaterial3D).albedo_color = col
	_fx.append({"node": n, "t0": now + delay, "dur": dur, "kind": "burst", "col": col, "r": radius})


func _ring(p: Vector2, radius: float, col: Color, dur: float, delay := 0.0) -> void:
	## 바닥에 퍼지는 충격파 고리 — 광역 공격 범위를 그대로 보여 줌
	if _ring_mesh == null:
		_ring_mesh = TorusMesh.new()
		_ring_mesh.inner_radius = 0.82
		_ring_mesh.outer_radius = 1.0
		_ring_mesh.rings = 32
		_ring_mesh.ring_segments = 4
	var n := _fx_node()
	n.mesh = _ring_mesh
	n.rotation = Vector3.ZERO
	n.position = w3(p, 0.12)
	n.scale = Vector3(radius * 0.3, 0.2, radius * 0.3)
	(n.material_override as StandardMaterial3D).albedo_color = col
	_fx.append({"node": n, "t0": now + delay, "dur": dur, "kind": "ring", "col": col, "r": maxf(radius, 0.4)})


func _slash(from: Vector2, center: Vector2, radius: float, col: Color) -> void:
	## 휘두르기: 표적 쪽 넓은 고리 + 섬광
	_ring(center, maxf(radius, 0.8), col, 0.35)
	_burst(center, col, maxf(radius, 0.8) * 0.7, 0.26)
	_beam(from, center, col, 0.12, 0.18)


func _bolt(from: Vector2, to: Vector2, col: Color, size: float, dur: float) -> void:
	## 날아가는 탄 (불덩이·화살·마법탄)
	if _sphere_mesh == null:
		_sphere_mesh = SvModels.sphere(1.0, 12, 6)
	var n := _fx_node()
	n.mesh = _sphere_mesh
	n.rotation = Vector3.ZERO
	n.scale = Vector3.ONE * size
	n.position = w3(from, 0.9)
	(n.material_override as StandardMaterial3D).albedo_color = col
	_fx.append({"node": n, "t0": now, "dur": dur, "kind": "bolt", "col": col, "from": from, "to": to})


func _update_fx() -> void:
	var keep: Array = []
	for f in _fx:
		var n: MeshInstance3D = f["node"]
		if now < float(f["t0"]):
			n.visible = false
			keep.append(f)
			continue
		n.visible = true
		var k := (now - float(f["t0"])) / float(f["dur"])
		if k >= 1.0:
			n.visible = false
			_fx_pool.append(n)
			continue
		var col: Color = f["col"]
		col.a = (1.0 - k * k) * 0.85
		(n.material_override as StandardMaterial3D).albedo_color = col
		match f["kind"]:
			"burst":
				n.scale = Vector3(1, 0.5, 1) * float(f["r"]) * (0.4 + 0.6 * k)
			"ring":
				var r := float(f["r"]) * (0.3 + 0.75 * k)
				n.scale = Vector3(r, 0.25, r)
			"bolt":
				var p: Vector2 = (f["from"] as Vector2).lerp(f["to"], k)
				n.position = w3(p, 0.9 - 0.4 * k + sin(k * PI) * 0.6)
				col.a = 1.0
				(n.material_override as StandardMaterial3D).albedo_color = col
		keep.append(f)
	_fx = keep
