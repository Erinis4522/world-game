class_name SvState
extends RefCounted
## 3D 서바이벌 한 판의 상태. 좌표는 평면 격자 단위 (x = 오른쪽, y = 아래쪽 → 3D x, z).
## 아군: 0 = 나(PLAYER, 조이스틱), 1 = 건설 동료(BUILDER, 늘 내 옆), 2~4 = 고른 동료 3명(맵에 흩어져 자율 전투)

const PLAYER := 0
const BUILDER := 1


class SvHero:
	extends RefCounted
	var id := 0
	var type := "SWORD"
	var role := "companion"  # player / builder / companion
	var pos := Vector2.ZERO
	var prev_pos := Vector2.ZERO
	var facing := Vector2(0, 1)
	var hp := 100.0
	var max_hp := 100.0
	var down_t := 0.0
	var cooldown := 0.0
	var principle := "NEAREST"
	var zone := ""  # 동료가 맡은 길 id
	var target_id := -1
	var last_attack_time := -100.0
	var last_chain_count := -1
	var goal := Vector2.INF
	var path := PackedVector2Array()
	var path_i := 0
	var joy := Vector2.ZERO  # 나: 조이스틱 방향 (길이 0~1)
	var think_t := 0.0
	var status := ""
	var moving := false
	var ult_ready_t := 0.0  # 이 시각 이후 필살기 가능
	var building_until := -1.0
	var attacks := 0
	var kills := 0
	var damage_dealt := 0.0
	var downs := 0

	func clone() -> SvHero:
		var c := SvHero.new()
		Entities.copy_fields(self, c)
		return c

	func alive() -> bool:
		return down_t <= 0.0


class SvEnemy:
	extends RefCounted
	var id := 0
	var type := "NORMAL"
	var gate := "W"
	var pos := Vector2.ZERO
	var prev_pos := Vector2.ZERO
	var facing := Vector2(1, 0)
	var hp := 1.0
	var max_hp := 1.0
	var armor := 0.0
	var radius := 0.3
	var speed := 1.0
	var alive := true
	var target_hero := -1
	var atk_cd := 0.0
	var spawn_time := 0.0
	var first_hit_time := -1.0
	var last_hit_by := -1
	var slow_t := 0.0
	var slow_amt := 0.0
	var burn_t := 0.0
	var burn_dps := 0.0
	var burn_src := -1
	var mark_t := 0.0
	var mark_amt := 0.0
	var mark_src := -1
	var attacking := false
	var hitting_wall := false

	func clone() -> SvEnemy:
		var c := SvEnemy.new()
		Entities.copy_fields(self, c)
		return c

	func effective_speed() -> float:
		return speed * (1.0 - (slow_amt if slow_t > 0.0 else 0.0))

	func is_slowed() -> bool:
		return slow_t > 0.0

	func is_burning() -> bool:
		return burn_t > 0.0

	func is_marked() -> bool:
		return mark_t > 0.0


class SvProjectile:
	extends RefCounted
	var hero_id := -1
	var pos := Vector2.ZERO
	var prev_pos := Vector2.ZERO
	var target := Vector2.ZERO
	var speed := 7.0
	var damage := 0.0
	var radius := 1.2
	var alive := true

	func clone() -> SvProjectile:
		var c := SvProjectile.new()
		Entities.copy_fields(self, c)
		return c


var grid: SvGrid
var time := 0.0
var tick := 0
var duration := 180.0
var base_hp := 100.0
var base_hp_max := 100.0
var heroes: Array = []
var enemies: Array = []
var projectiles: Array = []
var walls: Array = []  # [{id, cells, built_at}]
var spawn_queue: Array = []
var spawns_enabled := true
var next_enemy_id := 1
var next_wall_id := 1
var kills := 0
var xp := 0
var energy := 0
var base_damage_taken := 0.0
var outcome := ""
var phase_index := -1
var events: Array = []


static func create(team: Array) -> SvState:
	## team: 고른 동료 3명. 나와 건설 동료는 항상 들어간다.
	SvData.ensure_loaded()
	var s := SvState.new()
	s.grid = SvGrid.from_config()
	s.duration = float(SvData.cfg.get("duration_seconds", 180))
	s.base_hp = float(SvData.cfg.get("base_hp", 100))
	s.base_hp_max = s.base_hp
	s.energy = int(SvData.sec("build", "start_energy", 8))
	var hcfg: Dictionary = SvData.cfg["hero"]
	var starts: Dictionary = SvData.cfg["map"]["hero_start"]
	var roles: Array = [["PLAYER", "player"], ["BUILDER", "builder"]]
	for t in team:
		roles.append([t, "companion"])
	var roads: Array = SvData.roads()
	for i in roles.size():
		var h := SvHero.new()
		h.id = i
		h.type = roles[i][0]
		h.role = roles[i][1]
		h.max_hp = float(hcfg.get("hp", 100))
		h.hp = h.max_hp
		h.principle = str(GameData.config.get("default_principle", "NEAREST"))
		if h.role == "player":
			h.pos = _v(starts["player"])
		elif h.role == "builder":
			h.pos = _v(starts["builder"])
		else:
			var r: Dictionary = roads[(i - 2) % roads.size()]
			h.zone = r["id"]
			h.pos = _v(r["guard"])
		h.pos = s.grid.center_of(s.grid.nearest_open(s.grid.cell_of(h.pos))) if s.grid.is_blocked(s.grid.cell_of(h.pos)) else h.pos
		h.prev_pos = h.pos
		s.heroes.append(h)
	var scale := float(SvData.cfg.get("spawn_count_scale", 1.0))
	var q: Array = []
	for g in SvData.cfg["spawns"]:
		var cnt := int(round(float(g["count"]) * scale))
		for k in cnt:
			q.append({"t": float(g["t"]) + float(g["interval"]) / scale * k, "type": g["type"], "gate": g["gate"]})
	q.sort_custom(func(a, b): return a["t"] < b["t"])
	s.spawn_queue = q
	return s


static func _v(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


func clone() -> SvState:
	var c := SvState.new()
	c.grid = grid.clone()
	c.time = time
	c.tick = tick
	c.duration = duration
	c.base_hp = base_hp
	c.base_hp_max = base_hp_max
	for h in heroes:
		c.heroes.append(h.clone())
	for e in enemies:
		c.enemies.append(e.clone())
	for p in projectiles:
		c.projectiles.append(p.clone())
	c.walls = walls.duplicate(true)
	c.spawn_queue = spawn_queue.duplicate(true)
	c.spawns_enabled = spawns_enabled
	c.next_enemy_id = next_enemy_id
	c.next_wall_id = next_wall_id
	c.kills = kills
	c.xp = xp
	c.energy = energy
	c.base_damage_taken = base_damage_taken
	c.outcome = outcome
	c.phase_index = phase_index
	return c


func player() -> SvHero:
	return heroes[PLAYER]


func builder() -> SvHero:
	return heroes[BUILDER]


func companions() -> Array:
	return heroes.slice(2)


func find_enemy(id: int) -> SvEnemy:
	for e in enemies:
		if e.id == id:
			return e
	return null


func time_left() -> float:
	return maxf(0.0, duration - time)


func signature() -> String:
	var parts: Array = [str(tick), "%.3f" % base_hp, str(kills), str(energy), str(grid.walls.size())]
	for h in heroes:
		parts.append("%.3f,%.3f,%.2f" % [h.pos.x, h.pos.y, h.hp])
	for e in enemies:
		parts.append("%d:%.3f,%.3f,%.2f" % [e.id, e.pos.x, e.pos.y, e.hp])
	return "|".join(parts)
