class_name SvEngine
extends RefCounted
## 3D 서바이벌 전투 규칙 (30Hz 고정 틱, 화면과 무관).
## 공격 효과·피해 계산은 기존 GameEngine과 같은 규칙을 자유 이동에 맞게 옮긴 것이다.
## 이벤트: SPAWN, PHASE, ATTACK, HIT, KILL, EXPLODE, ENEMY_ATTACK, HERO_HIT, HERO_DOWN, HERO_UP, BASE_HIT, OUTCOME


static func step(state: SvState, dt: float) -> void:
	state.events.clear()
	if state.outcome != "":
		return
	state.time += dt
	state.tick += 1
	_phases(state)
	if state.spawns_enabled:
		_spawns(state)
	_status(state, dt)
	_heroes_move(state, dt)
	_enemies(state, dt)
	_separate(state)
	_heroes_attack(state, dt)
	_projectiles(state, dt)
	_cleanup(state)
	if state.base_hp <= 0.0:
		state.base_hp = 0.0
		state.outcome = "lose"
		state.events.append({"type": "OUTCOME", "outcome": "lose"})
	elif state.time >= state.duration:
		state.outcome = "win"
		state.events.append({"type": "OUTCOME", "outcome": "win"})


static func _phases(state: SvState) -> void:
	var ph: Array = SvData.cfg.get("phases", [])
	var next := state.phase_index + 1
	if next < ph.size() and state.time >= float(ph[next]["t"]):
		state.phase_index = next
		state.events.append({"type": "PHASE", "index": next, "text": ph[next]["text"]})


static func _spawns(state: SvState) -> void:
	var cap := int(SvData.cfg.get("max_enemies", 20))
	while not state.spawn_queue.is_empty() and float(state.spawn_queue[0]["t"]) <= state.time:
		var alive := 0
		for e in state.enemies:
			if e.alive:
				alive += 1
		if alive >= cap:
			break  # 화면 최대 수 → 잠시 미룸
		var it: Dictionary = state.spawn_queue.pop_front()
		spawn(state, it["type"], it["gate"])


static func spawn(state: SvState, type: String, gate_id: String) -> SvState.SvEnemy:
	var d: Dictionary = SvData.enemy(type)
	var g: Dictionary = SvData.gate(gate_id)
	var e := SvState.SvEnemy.new()
	e.id = state.next_enemy_id
	state.next_enemy_id += 1
	e.type = type
	e.gate = gate_id
	var jitter := Vector2(((e.id * 7) % 5 - 2) * 0.25, ((e.id * 3) % 5 - 2) * 0.25)  # 같은 자리에 겹치지 않게 (결정적)
	e.pos = state.grid.clamp_to_map(Vector2(float(g["pos"][0]), float(g["pos"][1])) + jitter)
	e.prev_pos = e.pos
	e.max_hp = float(d.get("hp", 25)) * float(SvData.cfg.get("enemy_hp_scale", 1.0))
	e.hp = e.max_hp
	e.armor = float(d.get("armor", 0.0))
	e.radius = float(d.get("radius", 0.3))
	e.speed = float(d.get("move_speed", 1.4))
	e.spawn_time = state.time
	e.atk_cd = 0.5
	state.enemies.append(e)
	state.events.append({"type": "SPAWN", "enemy": e.id, "enemy_type": type, "gate": gate_id})
	return e


# ---------------- 상태 효과 ----------------

static func _status(state: SvState, dt: float) -> void:
	for e in state.enemies:
		if not e.alive:
			continue
		if e.burn_t > 0.0:
			var t := minf(dt, e.burn_t)
			e.burn_t -= dt
			damage(state, e, e.burn_dps * t, 1.0, e.burn_src, true)
		if e.slow_t > 0.0:
			e.slow_t -= dt
		if e.mark_t > 0.0:
			e.mark_t -= dt
			if e.mark_t <= 0.0:
				e.mark_src = -1


static func damage(state: SvState, e: SvState.SvEnemy, amount: float, pierce: float, src: int, is_dot := false) -> float:
	if not e.alive or amount <= 0.0:
		return 0.0
	var dmg := amount * float(SvData.sec("hero", "damage_scale", 1.0)) * SvAI.damage_multiplier(e, pierce)
	e.hp -= dmg
	if e.first_hit_time < 0.0:
		e.first_hit_time = state.time
	e.last_hit_by = src
	if src >= 0 and src < state.heroes.size():
		state.heroes[src].damage_dealt += dmg
	if not is_dot:
		state.events.append({"type": "HIT", "hero": src, "enemy": e.id, "amount": dmg, "pos": e.pos})
	if e.hp <= 0.0:
		e.hp = 0.0
		e.alive = false
		state.kills += 1
		var d: Dictionary = SvData.enemy(e.type)
		state.xp += int(d.get("xp", 1))
		state.energy += int(d.get("energy", 1))
		if src >= 0 and src < state.heroes.size():
			state.heroes[src].kills += 1
		state.events.append({"type": "KILL", "hero": src, "enemy": e.id, "enemy_type": e.type, "pos": e.pos})
	return dmg


# ---------------- 아군 ----------------

static func _heroes_move(state: SvState, dt: float) -> void:
	var hc: Dictionary = SvData.cfg["hero"]
	var speed := float(hc.get("move_speed", 3.4))
	var radius := float(hc.get("radius", 0.35))
	var base := SvData.base_center()
	var think_iv := float(SvData.sec("companion", "think_interval", 0.4))
	for h in state.heroes:
		h.prev_pos = h.pos
		h.moving = false
		if not h.alive():
			h.down_t -= dt
			if h.down_t <= 0.0:
				h.down_t = 0.0
				h.hp = h.max_hp
				h.pos = state.grid.clamp_to_map(base + Vector2(0, 2.2).rotated(h.id * 2.1))
				h.prev_pos = h.pos
				h.goal = Vector2.INF
				h.path = PackedVector2Array()
				h.status = ""
				state.events.append({"type": "HERO_UP", "hero": h.id})
			continue
		# 기지 근처에서는 체력 회복
		if h.pos.distance_to(base) <= float(hc.get("base_heal_radius", 3.2)):
			h.hp = minf(h.max_hp, h.hp + float(hc.get("base_heal_per_second", 6)) * dt)
		if not h.is_player:
			h.think_t -= dt
			if h.think_t <= 0.0:
				h.think_t = think_iv
				SvAI.think(state, h)
		# 경로 따라 이동
		if h.path_i < h.path.size():
			var wp: Vector2 = h.path[h.path_i]
			var to: Vector2 = wp - h.pos
			var step_len := speed * dt
			if to.length() <= maxf(step_len, 0.05):
				h.pos = state.grid.move(h.pos, to, radius)
				h.path_i += 1
			else:
				var dir: Vector2 = to.normalized()
				h.pos = state.grid.move(h.pos, dir * step_len, radius)
				h.facing = dir
			h.moving = h.pos.distance_to(h.prev_pos) > 0.0005
			if h.path_i >= h.path.size():
				h.goal = Vector2.INF


static func command_move(state: SvState, hero_id: int, target: Vector2) -> bool:
	## 학생이 터치 지도에서 누른 곳으로 대표 캐릭터 이동
	if hero_id < 0 or hero_id >= state.heroes.size():
		return false
	var h: SvState.SvHero = state.heroes[hero_id]
	var t := state.grid.clamp_to_map(target)
	if state.grid.is_blocked(state.grid.cell_of(t)):
		t = state.grid.center_of(state.grid.nearest_open(state.grid.cell_of(t)))
	h.goal = t
	h.path = state.grid.find_path(h.pos, t)
	h.path_i = 0
	return true


static func _heroes_attack(state: SvState, dt: float) -> void:
	for h in state.heroes:
		if not h.alive():
			continue
		h.cooldown -= dt
		if h.cooldown > 0.0:
			continue
		var t: SvState.SvEnemy = SvAI.select_target(state, h)
		if t == null:
			h.cooldown = 0.0
			h.target_id = -1
			continue
		var d: Dictionary = GameData.hero(h.type)
		_attack(state, h, t, d)
		h.cooldown += float(d["interval"])
		if h.cooldown < 0.0:
			h.cooldown = 0.0


static func _attack(state: SvState, h: SvState.SvHero, target: SvState.SvEnemy, d: Dictionary) -> void:
	h.target_id = target.id
	h.last_attack_time = state.time
	h.attacks += 1
	h.facing = (target.pos - h.pos).normalized() if target.pos.distance_to(h.pos) > 0.01 else h.facing
	var dmg := float(d["damage"])
	var rng := SvAI.hero_range(h)
	var hit_ids: Array = [target.id]
	var points: Array = [target.pos]
	match h.type:
		"SWORD":
			damage(state, target, dmg, 0.0, h.id)
			var others: Array = []
			for e in state.enemies:
				if e.alive and e.id != target.id and h.pos.distance_to(e.pos) <= rng:
					others.append(e)
			others.sort_custom(func(a, b): return a.pos.distance_to(target.pos) < b.pos.distance_to(target.pos))
			for i in mini(int(d.get("max_targets", 2)) - 1, others.size()):
				damage(state, others[i], dmg, 0.0, h.id)
				hit_ids.append(others[i].id)
				points.append(others[i].pos)
		"SNIPER":
			damage(state, target, dmg, float(d.get("armor_pierce", 0.5)), h.id)
		"FIRE":
			var r := float(d.get("aoe_radius", 0.9))
			var c := target.pos
			for e in state.enemies:
				if e.alive and e.pos.distance_to(c) <= r:
					damage(state, e, dmg, 0.0, h.id)
					if e.alive:
						e.burn_t = float(d.get("burn_duration", 3.0))
						e.burn_dps = float(d.get("burn_dps", 2.0))
						e.burn_src = h.id
					if e.id != target.id:
						hit_ids.append(e.id)
			state.events.append({"type": "EXPLODE", "hero": h.id, "pos": c, "radius": r, "kind": "FIRE"})
		"ICE":
			damage(state, target, dmg, 0.0, h.id)
			if target.alive:
				target.slow_t = float(d.get("slow_duration", 1.8))
				target.slow_amt = float(d.get("slow", 0.35))
		"LIGHTNING":
			damage(state, target, dmg, 0.0, h.id)
			var last := target.pos
			var cur := dmg
			var chained := 0
			for i in int(d.get("chain_count", 2)):
				var nxt: SvState.SvEnemy = null
				var best := INF
				for e in state.enemies:
					if not e.alive or hit_ids.has(e.id):
						continue
					var dd: float = e.pos.distance_to(last)
					if dd <= float(d.get("chain_range", 1.6)) and dd < best:
						best = dd
						nxt = e
				if nxt == null:
					break
				cur *= float(d.get("chain_falloff", 0.7))
				hit_ids.append(nxt.id)
				points.append(nxt.pos)
				last = nxt.pos
				damage(state, nxt, cur, 0.0, h.id)
				chained += 1
			h.last_chain_count = chained
		"BOMB":
			var p := SvState.SvProjectile.new()
			p.hero_id = h.id
			p.pos = h.pos
			p.prev_pos = h.pos
			p.target = target.pos
			p.speed = float(d.get("projectile_speed", 7.0))
			p.damage = dmg
			p.radius = float(d.get("blast_radius", 1.2))
			state.projectiles.append(p)
		"MARK":
			damage(state, target, dmg, 0.0, h.id)
			if target.alive:
				target.mark_t = float(d.get("mark_duration", 2.5))
				target.mark_amt = float(d.get("mark_amp", 0.25))
				target.mark_src = h.id
		_:
			damage(state, target, dmg, 0.0, h.id)
	var special := false
	match h.type:
		"SWORD": special = hit_ids.size() >= 2
		"ARCHER": special = not target.alive
		"SNIPER": special = target.armor > 0.0 and target.max_hp >= 80.0
		"FIRE": special = hit_ids.size() >= 2
		"ICE": special = target.type == "FAST"
		"LIGHTNING": special = h.last_chain_count >= 2
		"BOMB": special = SvAI._count_near(state, target.pos, float(d.get("blast_radius", 1.2))) >= 3
	state.events.append({"type": "ATTACK", "hero": h.id, "hero_type": h.type, "target": target.id,
		"targets": hit_ids, "points": points, "from": h.pos, "special": special})


static func _projectiles(state: SvState, dt: float) -> void:
	for p in state.projectiles:
		if not p.alive:
			continue
		p.prev_pos = p.pos
		var to: Vector2 = p.target - p.pos
		var sl: float = p.speed * dt
		if to.length() <= sl:
			p.pos = p.target
			p.alive = false
			var n := 0
			for e in state.enemies:
				if e.alive and e.pos.distance_to(p.pos) <= p.radius + e.radius * 0.5:
					damage(state, e, p.damage, 0.0, p.hero_id)
					n += 1
			state.events.append({"type": "EXPLODE", "hero": p.hero_id, "pos": p.pos, "radius": p.radius, "count": n})
		else:
			p.pos += to.normalized() * sl


# ---------------- 적 ----------------

static func _enemies(state: SvState, dt: float) -> void:
	var base := SvData.base_center()
	var base_r := float(SvData.cfg["map"].get("base_attack_radius", 2.3))
	var hero_r := float(SvData.sec("hero", "radius", 0.35))
	for e in state.enemies:
		if not e.alive:
			continue
		e.prev_pos = e.pos
		e.attacking = false
		var d: Dictionary = SvData.enemy(e.type)
		e.atk_cd -= dt
		# 표적: 가까운 아군을 쫓다가 너무 멀어지면 다시 기지로
		if e.target_hero >= 0:
			var th: SvState.SvHero = state.heroes[e.target_hero]
			if not th.alive() or th.pos.distance_to(e.pos) > float(d.get("leash", 4.0)):
				e.target_hero = -1
		if e.target_hero < 0:
			var best := -1
			var bd := float(d.get("aggro_radius", 2.2))
			for h in state.heroes:
				if h.alive() and h.pos.distance_to(e.pos) <= bd:
					bd = h.pos.distance_to(e.pos)
					best = h.id
			e.target_hero = best
		if e.target_hero >= 0:
			var th2: SvState.SvHero = state.heroes[e.target_hero]
			var dist: float = th2.pos.distance_to(e.pos)
			if dist <= float(d.get("attack_range", 0.75)) + hero_r:
				e.attacking = true
				e.facing = (th2.pos - e.pos).normalized() if dist > 0.01 else e.facing
				if e.atk_cd <= 0.0:
					e.atk_cd = float(d.get("attack_interval", 1.0))
					_hit_hero(state, th2, float(d.get("attack_damage", 5)), e)
				continue
			var dir: Vector2 = (th2.pos - e.pos).normalized()
			if not state.grid.line_clear(e.pos, th2.pos):
				dir = state.grid.flow_dir(e.pos)  # 장애물 너머면 일단 길을 따라감
			_enemy_step(state, e, dir, dt)
			continue
		# 기지로
		if e.pos.distance_to(base) <= base_r:
			e.attacking = true
			e.facing = (base - e.pos).normalized()
			if e.atk_cd <= 0.0:
				e.atk_cd = float(d.get("attack_interval", 1.0))
				var bdmg := float(d.get("base_damage", 2))
				state.base_hp -= bdmg
				state.base_damage_taken += bdmg
				state.events.append({"type": "BASE_HIT", "enemy": e.id, "enemy_type": e.type, "damage": bdmg, "hp": state.base_hp})
			continue
		var fd: Vector2 = state.grid.flow_dir(e.pos)
		if fd == Vector2.ZERO:
			fd = (base - e.pos).normalized()
		_enemy_step(state, e, fd, dt)


static func _enemy_step(state: SvState, e: SvState.SvEnemy, dir: Vector2, dt: float) -> void:
	if dir == Vector2.ZERO:
		return
	e.facing = dir
	e.pos = state.grid.move(e.pos, dir * e.effective_speed() * dt, e.radius * 0.8)


static func _hit_hero(state: SvState, h: SvState.SvHero, dmg: float, e: SvState.SvEnemy) -> void:
	h.hp -= dmg
	h.damage_taken += dmg
	state.events.append({"type": "HERO_HIT", "hero": h.id, "enemy": e.id, "damage": dmg})
	if h.hp <= 0.0:
		h.hp = 0.0
		h.down_t = float(SvData.sec("hero", "respawn_seconds", 6))
		h.downs += 1
		h.goal = Vector2.INF
		h.path = PackedVector2Array()
		h.path_i = 0
		state.events.append({"type": "HERO_DOWN", "hero": h.id})
		for o in state.enemies:
			if o.target_hero == h.id:
				o.target_hero = -1


static func _separate(state: SvState) -> void:
	## 적끼리 겹치지 않게 살짝 밀어냄 (적 20마리 기준 O(n²)로 충분)
	var n := state.enemies.size()
	for i in n:
		var a: SvState.SvEnemy = state.enemies[i]
		if not a.alive:
			continue
		for j in range(i + 1, n):
			var b: SvState.SvEnemy = state.enemies[j]
			if not b.alive:
				continue
			var d: Vector2 = b.pos - a.pos
			var min_d: float = (a.radius + b.radius) * 0.9
			var l: float = d.length()
			if l < min_d and l > 0.0001:
				var push: Vector2 = d / l * (min_d - l) * 0.5
				a.pos = state.grid.move(a.pos, -push, a.radius * 0.8)
				b.pos = state.grid.move(b.pos, push, b.radius * 0.8)


static func _cleanup(state: SvState) -> void:
	var keep: Array = []
	for e in state.enemies:
		if e.alive:
			keep.append(e)
	state.enemies = keep
	var kp: Array = []
	for p in state.projectiles:
		if p.alive:
			kp.append(p)
	state.projectiles = kp
