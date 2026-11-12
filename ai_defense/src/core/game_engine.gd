class_name GameEngine
extends RefCounted
## 전투 규칙. 고정 timestep(기본 30Hz)으로 GameState를 한 틱씩 진행한다.
## 실제 전투와 AI 가상 전투가 똑같이 이 함수를 쓴다. 화면 그리기와 무관하다.
##
## 이벤트(state.events)는 매 틱 새로 채워진다:
##   SPAWN, WAVE_START, WAVE_CLEAR, ATTACK, HIT, KILL, LEAK, PASSED, EXPLODE, OUTCOME


static func start_battle(state: GameState) -> void:
	GameData.ensure_loaded()
	state.events.clear()
	_start_wave(state, 0)


static func step(state: GameState, dt: float) -> void:
	state.events.clear()
	if state.outcome != "":
		return
	state.time += dt
	state.tick += 1
	if state.spawns_enabled:
		_update_waves(state, dt)
	_update_status(state, dt)
	_move_enemies(state, dt)
	_update_projectiles(state, dt)
	_update_heroes(state, dt)
	_cleanup(state)
	_check_outcome(state)


# ---------------- 웨이브 ----------------

static func _start_wave(state: GameState, index: int) -> void:
	state.wave_index = index
	state.wave_time = 0.0
	state.wave_state = "active"
	var q: Array = []
	var wave: Dictionary = GameData.waves[index]
	for g in wave["groups"]:
		for i in int(g["count"]):
			q.append({"t": float(g["start"]) + float(g["interval"]) * i, "type": g["type"]})
	q.sort_custom(func(a, b): return a["t"] < b["t"])
	state.spawn_queue = q
	state.events.append({"type": "WAVE_START", "wave": index})


static func _update_waves(state: GameState, dt: float) -> void:
	match state.wave_state:
		"active":
			state.wave_time += dt
			var max_enemies := int(GameData.config.get("max_enemies", 40))
			while not state.spawn_queue.is_empty() and state.spawn_queue[0]["t"] <= state.wave_time:
				if _alive_count(state) >= max_enemies:
					break  # 화면 최대 수를 넘지 않도록 잠시 미룬다
				var item: Dictionary = state.spawn_queue.pop_front()
				_spawn(state, item["type"])
			if state.spawn_queue.is_empty():
				var duration := float(GameData.waves[state.wave_index]["duration"])
				var field_clear := _alive_count(state) == 0
				var is_last := state.wave_index >= GameData.waves.size() - 1
				if is_last:
					if field_clear:
						state.wave_state = "done"
				elif field_clear or state.wave_time >= duration:
					state.wave_state = "gap"
					state.gap_time = 0.0
					state.events.append({"type": "WAVE_CLEAR", "wave": state.wave_index})
		"gap":
			state.gap_time += dt
			if state.gap_time >= float(GameData.config.get("wave_gap_seconds", 4)):
				_start_wave(state, state.wave_index + 1)


static func _spawn(state: GameState, type: String) -> void:
	var d: Dictionary = GameData.enemy(type)
	var e := Entities.Enemy.new()
	e.id = state.next_enemy_id
	state.next_enemy_id += 1
	e.type = type
	e.max_hp = float(d["hp"])
	e.hp = e.max_hp
	e.base_speed = float(d["speed"])
	e.speed = e.base_speed * float(GameData.config.get("enemy_speed_scale", 1.0))
	e.armor = float(d.get("armor", 0.0))
	e.base_damage = int(d.get("base_damage", 1))
	e.radius = float(d.get("radius", 0.3))
	e.dist = 0.0
	e.pos = GameData.path.pos_at(0.0)
	e.prev_pos = e.pos
	e.spawn_time = state.time
	state.enemies.append(e)
	state.events.append({"type": "SPAWN", "enemy": e.id, "enemy_type": type})


static func _alive_count(state: GameState) -> int:
	var n := 0
	for e in state.enemies:
		if e.alive:
			n += 1
	return n


# ---------------- 상태 효과 ----------------

static func _update_status(state: GameState, dt: float) -> void:
	for e in state.enemies:
		if not e.alive:
			continue
		if e.burn_t > 0.0:
			var t := minf(dt, e.burn_t)
			e.burn_t -= dt
			apply_damage(state, e, e.burn_dps * t, 1.0, e.burn_src, true)
		if e.slow_t > 0.0:
			e.slow_t -= dt
		if e.mark_t > 0.0:
			e.mark_t -= dt
			if e.mark_t <= 0.0:
				e.mark_src = -1


static func _move_enemies(state: GameState, dt: float) -> void:
	var length := GameData.path.length
	for e in state.enemies:
		if not e.alive:
			continue
		e.prev_pos = e.pos
		e.dist += e.effective_speed() * dt
		if e.dist >= length:
			e.alive = false
			e.leaked = true
			e.pos = GameData.path.end_point()
			var before := state.base_hp
			state.base_hp = maxi(0, state.base_hp - e.base_damage)
			state.damage_taken += e.base_damage
			state.leaked += 1
			state.events.append({"type": "LEAK", "enemy": e.id, "enemy_type": e.type,
				"damage": e.base_damage, "hp_before": before, "hp_after": state.base_hp})
		else:
			e.pos = GameData.path.pos_at(e.dist)


# ---------------- 피해 ----------------

static func damage_multiplier(e: Entities.Enemy, pierce: float) -> float:
	var armor_mult := 1.0 - e.armor * (1.0 - pierce)
	var mark_mult := 1.0 + (e.mark_amt if e.mark_t > 0.0 else 0.0)
	return armor_mult * mark_mult


static func apply_damage(state: GameState, e: Entities.Enemy, amount: float, pierce: float, src: int, is_dot := false) -> float:
	if not e.alive or amount <= 0.0:
		return 0.0
	var dmg := amount * damage_multiplier(e, pierce)
	e.hp -= dmg
	if e.first_hit_time < 0.0:
		e.first_hit_time = state.time
	e.last_hit_time = state.time
	e.last_hit_by = src
	if src >= 0 and src < state.heroes.size():
		state.heroes[src].damage_dealt += dmg
	if not is_dot:
		state.events.append({"type": "HIT", "hero": src, "enemy": e.id, "amount": dmg,
			"marked": e.mark_t > 0.0, "mark_src": e.mark_src})
	if e.hp <= 0.0:
		e.hp = 0.0
		e.alive = false
		state.kills += 1
		if src >= 0 and src < state.heroes.size():
			state.heroes[src].kills += 1
		state.events.append({"type": "KILL", "hero": src, "enemy": e.id, "enemy_type": e.type, "pos": e.pos})
	return dmg


# ---------------- 투사체 ----------------

static func _update_projectiles(state: GameState, dt: float) -> void:
	for p in state.projectiles:
		if not p.alive:
			continue
		p.prev_pos = p.pos
		var to: Vector2 = p.target - p.pos
		var step_len: float = p.speed * dt
		if to.length() <= step_len:
			p.pos = p.target
			p.alive = false
			_explode(state, p.hero_id, p.pos, p.radius, p.damage)
		else:
			p.pos += to.normalized() * step_len


static func _explode(state: GameState, hero_id: int, at: Vector2, radius: float, dmg: float) -> void:
	var hit := 0
	for e in state.enemies:
		if e.alive and e.pos.distance_to(at) <= radius + e.radius * 0.5:
			apply_damage(state, e, dmg, 0.0, hero_id)
			hit += 1
	state.events.append({"type": "EXPLODE", "hero": hero_id, "pos": at, "radius": radius, "count": hit})


# ---------------- 캐릭터 ----------------

static func _update_heroes(state: GameState, dt: float) -> void:
	for h in state.heroes:
		var d: Dictionary = GameData.hero(h.type)
		var rng := float(d["range"])
		# 사거리 출입 추적: 살아 있는 채로 사거리를 벗어나면 '지나감'
		var now_in: Dictionary = {}
		for e in state.enemies:
			if e.alive and h.pos.distance_to(e.pos) <= rng:
				now_in[e.id] = true
		for id in h.in_range.keys():
			if not now_in.has(id):
				var pe := state.find_enemy(id)
				if pe != null and pe.alive:
					state.events.append({"type": "PASSED", "hero": h.id, "enemy": id, "enemy_type": pe.type})
		h.in_range = now_in
		# 공격
		h.cooldown -= dt
		if h.cooldown <= 0.0:
			var target: Entities.Enemy = Targeting.select(state, h)
			if target == null:
				h.cooldown = 0.0
				h.last_target_id = -1
			else:
				_attack(state, h, target, d)
				h.cooldown += float(d["interval"])
				if h.cooldown < 0.0:
					h.cooldown = 0.0


static func _attack(state: GameState, h: Entities.Hero, target: Entities.Enemy, d: Dictionary) -> void:
	h.last_target_id = target.id
	h.last_attack_time = state.time
	h.attacks += 1
	var dmg := float(d["damage"])
	var rng := float(d["range"])
	var hit_ids: Array = [target.id]
	var points: Array = [target.pos]
	match h.type:
		"SWORD":
			apply_damage(state, target, dmg, 0.0, h.id)
			var extra := int(d.get("max_targets", 2)) - 1
			var others: Array = []
			for e in state.enemies:
				if e.alive and e.id != target.id and h.pos.distance_to(e.pos) <= rng:
					others.append(e)
			others.sort_custom(func(a, b):
				var da: float = a.pos.distance_to(target.pos)
				var db: float = b.pos.distance_to(target.pos)
				return da < db if da != db else a.id < b.id)
			for i in mini(extra, others.size()):
				apply_damage(state, others[i], dmg, 0.0, h.id)
				hit_ids.append(others[i].id)
				points.append(others[i].pos)
		"ARCHER":
			apply_damage(state, target, dmg, 0.0, h.id)
		"SNIPER":
			apply_damage(state, target, dmg, float(d.get("armor_pierce", 0.5)), h.id)
		"FIRE":
			var r := float(d.get("aoe_radius", 0.9))
			var center := target.pos
			for e in state.enemies:
				if e.alive and e.pos.distance_to(center) <= r:
					apply_damage(state, e, dmg, 0.0, h.id)
					if e.alive:
						# 같은 종류 상태효과는 1개만, 지속시간 갱신
						e.burn_t = float(d.get("burn_duration", 3.0))
						e.burn_dps = float(d.get("burn_dps", 2.0))
						e.burn_src = h.id
					if e.id != target.id:
						hit_ids.append(e.id)
			state.events.append({"type": "EXPLODE", "hero": h.id, "pos": center, "radius": r, "count": hit_ids.size(), "kind": "FIRE"})
		"ICE":
			apply_damage(state, target, dmg, 0.0, h.id)
			if target.alive:
				target.slow_t = float(d.get("slow_duration", 1.8))
				target.slow_amt = float(d.get("slow", 0.35))
		"LIGHTNING":
			apply_damage(state, target, dmg, 0.0, h.id)
			var chain_n := int(d.get("chain_count", 2))
			var chain_r := float(d.get("chain_range", 1.6))
			var falloff := float(d.get("chain_falloff", 0.7))
			var last_pos := target.pos
			var cur := dmg
			var chained := 0
			for i in chain_n:
				var nxt: Entities.Enemy = null
				var best := INF
				for e in state.enemies:
					if not e.alive or hit_ids.has(e.id):
						continue
					var dd: float = e.pos.distance_to(last_pos)
					if dd <= chain_r and dd < best:  # 배열은 id 순이므로 동률이면 작은 id
						best = dd
						nxt = e
				if nxt == null:
					break
				cur *= falloff
				hit_ids.append(nxt.id)
				points.append(nxt.pos)
				last_pos = nxt.pos
				apply_damage(state, nxt, cur, 0.0, h.id)
				chained += 1
			h.last_chain_count = chained
		"BOMB":
			var p := Entities.Projectile.new()
			p.hero_id = h.id
			p.kind = "BOMB"
			p.pos = h.pos
			p.prev_pos = h.pos
			p.target = target.pos
			p.speed = float(d.get("projectile_speed", 7.0))
			p.damage = dmg
			p.radius = float(d.get("blast_radius", 1.2))
			state.projectiles.append(p)
		"MARK":
			apply_damage(state, target, dmg, 0.0, h.id)
			if target.alive:
				target.mark_t = float(d.get("mark_duration", 2.5))
				target.mark_amt = float(d.get("mark_amp", 0.25))
				target.mark_src = h.id
		_:
			apply_damage(state, target, dmg, 0.0, h.id)
	state.events.append({"type": "ATTACK", "hero": h.id, "hero_type": h.type, "target": target.id,
		"targets": hit_ids, "points": points, "from": h.pos, "special": _is_special(state, h, target, hit_ids, d)})


static func _is_special(state: GameState, h: Entities.Hero, target: Entities.Enemy, hit_ids: Array, d: Dictionary) -> bool:
	## 화면 연출용 표시: 이번 공격에서 캐릭터 고유 특기가 '제대로' 발휘됐는가. 전투 결과에는 영향 없음.
	match h.type:
		"SWORD": return hit_ids.size() >= 2
		"ARCHER": return not target.alive
		"SNIPER": return target.type == "ARMORED" or target.type == "BOSS"
		"FIRE": return hit_ids.size() >= 2
		"ICE": return target.type == "FAST"
		"LIGHTNING": return h.last_chain_count >= 2
		"BOMB": return Specialty.count_near(state, target.pos, float(d.get("blast_radius", 1.2))) >= 3
		"MARK": return Specialty.allies_in_range(state, h, target) >= (1 if target.max_hp >= 80.0 else 2)
	return false


# ---------------- 정리 ----------------

static func _cleanup(state: GameState) -> void:
	var keep: Array = []
	for e in state.enemies:
		if e.alive:
			keep.append(e)
	state.enemies = keep
	var keep_p: Array = []
	for p in state.projectiles:
		if p.alive:
			keep_p.append(p)
	state.projectiles = keep_p


static func _check_outcome(state: GameState) -> void:
	if state.base_hp <= 0:
		state.outcome = "lose"
		state.events.append({"type": "OUTCOME", "outcome": "lose"})
	elif state.spawns_enabled and state.wave_state == "done":
		state.outcome = "win"
		state.events.append({"type": "OUTCOME", "outcome": "win"})
