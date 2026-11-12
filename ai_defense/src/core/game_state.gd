class_name GameState
extends RefCounted
## 전투 한 판의 전체 상태. 렌더링과 무관한 순수 데이터.
## clone()은 깊은 복사이며, 가상 전투 비교는 항상 복사본에서만 진행한다.

var time := 0.0  # 전투 시뮬레이션 시각(초). 일시정지 동안은 흐르지 않는다.
var tick := 0
var base_hp := 10
var base_hp_max := 10
var damage_taken := 0
var enemies: Array = []  # Array[Entities.Enemy]
var heroes: Array = []  # Array[Entities.Hero]
var projectiles: Array = []  # Array[Entities.Projectile]
var next_enemy_id := 1
var wave_index := -1
var wave_time := 0.0
var wave_state := "pending"  # pending / active / gap / done
var gap_time := 0.0
var spawn_queue: Array = []  # [{t, type}] 시간순
var spawns_enabled := true
var kills := 0
var leaked := 0
var outcome := ""  # "" / win / lose
var events: Array = []  # 이번 틱에 일어난 일 (뷰·관찰기가 읽음)
var rng_seed := 0
var rng_state := 0


static func create(team: Array, seed_value: int = 12345) -> GameState:
	## team: [{type, slot, principle}]
	GameData.ensure_loaded()
	var s := GameState.new()
	s.base_hp = int(GameData.config.get("base_hp", 10))
	s.base_hp_max = s.base_hp
	s.rng_seed = seed_value
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	s.rng_state = r.state
	for i in team.size():
		var t: Dictionary = team[i]
		var h := Entities.Hero.new()
		h.id = i
		h.type = t["type"]
		h.slot = int(t["slot"])
		h.pos = GameData.slots[h.slot]
		h.principle = t.get("principle", GameData.config.get("default_principle", "NEAREST"))
		s.heroes.append(h)
	return s


func clone() -> GameState:
	var c := GameState.new()
	c.time = time
	c.tick = tick
	c.base_hp = base_hp
	c.base_hp_max = base_hp_max
	c.damage_taken = damage_taken
	for e in enemies:
		c.enemies.append(e.clone())
	for h in heroes:
		c.heroes.append(h.clone())
	for p in projectiles:
		c.projectiles.append(p.clone())
	c.next_enemy_id = next_enemy_id
	c.wave_index = wave_index
	c.wave_time = wave_time
	c.wave_state = wave_state
	c.gap_time = gap_time
	c.spawn_queue = spawn_queue.duplicate(true)
	c.spawns_enabled = spawns_enabled
	c.kills = kills
	c.leaked = leaked
	c.outcome = outcome
	c.events = []
	c.rng_seed = rng_seed
	c.rng_state = rng_state
	return c


func alive_enemies() -> Array:
	var out: Array = []
	for e in enemies:
		if e.alive:
			out.append(e)
	return out


func find_enemy(id: int) -> Entities.Enemy:
	for e in enemies:
		if e.id == id:
			return e
	return null


func progress(e: Entities.Enemy) -> float:
	return clampf(e.dist / GameData.path.length, 0.0, 1.0)


func eta(e: Entities.Enemy) -> float:
	var sp := e.effective_speed()
	if sp <= 0.0001:
		return INF
	return maxf(0.0, GameData.path.length - e.dist) / sp


func total_waves() -> int:
	return GameData.waves.size()


func signature() -> String:
	## 재현성 테스트용 요약 문자열
	var parts: Array = [str(tick), str(base_hp), str(kills), str(leaked)]
	for e in enemies:
		parts.append("%d:%.4f:%.4f" % [e.id, e.hp, e.dist])
	for h in heroes:
		parts.append("%s:%.4f:%d" % [h.principle, h.cooldown, h.last_target_id])
	return ",".join(parts)
