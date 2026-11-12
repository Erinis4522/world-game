class_name SvState
extends RefCounted
## 3D 서바이벌 한 판의 상태. 좌표는 평면 격자 단위 (x = 오른쪽, y = 아래쪽 → 3D에서는 x, z).
## clone()은 깊은 복사 (AI 비교 계산·테스트용).


class SvHero:
	extends RefCounted
	var id := 0
	var type := "SWORD"
	var is_player := false
	var pos := Vector2.ZERO
	var prev_pos := Vector2.ZERO
	var facing := Vector2(0, 1)
	var hp := 100.0
	var max_hp := 100.0
	var down_t := 0.0  # > 0 이면 쓰러져서 기지에서 다시 일어나는 중
	var cooldown := 0.0
	var principle := "NEAREST"
	var target_id := -1
	var last_attack_time := -100.0
	var last_chain_count := -1
	var goal := Vector2.INF  # 이동 목적지 (없으면 INF)
	var path := PackedVector2Array()
	var path_i := 0
	var tactic := "GATHER"
	var focus_id := -1
	var think_t := 0.0
	var status := ""  # 화면 표시용 한 줄 (호위 중 / 후퇴 중 …)
	var moving := false
	var attacks := 0
	var kills := 0
	var damage_dealt := 0.0
	var damage_taken := 0.0
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
	var target_hero := -1  # -1 = 기지로
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
var spawn_queue: Array = []  # [{t, type, gate}] 시간순
var spawns_enabled := true
var next_enemy_id := 1
var kills := 0
var xp := 0
var energy := 0
var base_damage_taken := 0.0
var outcome := ""
var phase_index := -1
var events: Array = []


static func create(team: Array) -> SvState:
	## team: 고른 순서의 캐릭터 종류 3개. 첫 번째가 학생이 직접 움직이는 대표 캐릭터.
	SvData.ensure_loaded()
	var s := SvState.new()
	s.grid = SvGrid.from_config()
	s.duration = float(SvData.cfg.get("duration_seconds", 180))
	s.base_hp = float(SvData.cfg.get("base_hp", 100))
	s.base_hp_max = s.base_hp
	var starts: Array = SvData.cfg["map"]["hero_start"]
	var hcfg: Dictionary = SvData.cfg["hero"]
	for i in team.size():
		var h := SvHero.new()
		h.id = i
		h.type = team[i]
		h.is_player = i == 0
		var sp: Array = starts[i % starts.size()]
		h.pos = Vector2(float(sp[0]), float(sp[1]))
		h.prev_pos = h.pos
		h.max_hp = float(hcfg.get("hp", 100))
		h.hp = h.max_hp
		h.tactic = str(SvData.cfg.get("default_tactic", "GATHER"))
		h.principle = str(GameData.config.get("default_principle", "NEAREST"))
		s.heroes.append(h)
	var q: Array = []
	for g in SvData.cfg["spawns"]:
		var cnt := int(round(float(g["count"]) * float(SvData.cfg.get("spawn_count_scale", 1.0))))
		var iv := float(g["interval"]) / float(SvData.cfg.get("spawn_count_scale", 1.0))
		for k in cnt:
			q.append({"t": float(g["t"]) + iv * k, "type": g["type"], "gate": g["gate"]})
	q.sort_custom(func(a, b): return a["t"] < b["t"])
	s.spawn_queue = q
	return s


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
	c.spawn_queue = spawn_queue.duplicate(true)
	c.spawns_enabled = spawns_enabled
	c.next_enemy_id = next_enemy_id
	c.kills = kills
	c.xp = xp
	c.energy = energy
	c.base_damage_taken = base_damage_taken
	c.outcome = outcome
	c.phase_index = phase_index
	return c


func player() -> SvHero:
	return heroes[0]


func find_enemy(id: int) -> SvEnemy:
	for e in enemies:
		if e.id == id:
			return e
	return null


func alive_enemies() -> Array:
	var out: Array = []
	for e in enemies:
		if e.alive:
			out.append(e)
	return out


func time_left() -> float:
	return maxf(0.0, duration - time)


func signature() -> String:
	var parts: Array = [str(tick), "%.3f" % base_hp, str(kills)]
	for h in heroes:
		parts.append("%.3f,%.3f,%.2f" % [h.pos.x, h.pos.y, h.hp])
	for e in enemies:
		parts.append("%d:%.3f,%.3f,%.2f" % [e.id, e.pos.x, e.pos.y, e.hp])
	return "|".join(parts)
