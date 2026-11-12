class_name SvEngine
extends RefCounted
## 3D 서바이벌 전투 규칙 (30Hz 고정 틱, 화면과 무관).
## 공격 효과·피해 계산은 기존 GameEngine 규칙을 자유 이동에 맞게 옮긴 것이다.
## 이벤트: SPAWN, PHASE, ATTACK, HIT, KILL, EXPLODE, HERO_HIT, HERO_DOWN, HERO_UP, BASE_HIT,
##        BUILD, WALL_HIT, WALL_BREAK, ULT, OUTCOME


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
			break
		var it: Dictionary = state.spawn_queue.pop_front()
		spawn(state, it["type"], it["gate"])


static func spawn(state: SvState, type: String, gate_id: String) -> SvState.SvEnemy:
	var d: Dictionary = SvData.enemy(type)
	var e := SvState.SvEnemy.new()
	e.id = state.next_enemy_id
	state.next_enemy_id += 1
	e.type = type
	e.gate = gate_id
	var jitter := Vector2(((e.id * 7) % 5 - 2) * 0.25, ((e.id * 3) % 5 - 2) * 0.25)
	e.pos = state.grid.clamp_to_map(SvData.gate_pos(gate_id) + jitter)
	if state.grid.is_blocked(state.grid.cell_of(e.pos)):
		e.pos = state.grid.center_of(state.grid.nearest_open(state.grid.cell_of(e.pos)))
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


# ---------------- 상태 효과·피해 ----------------

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
				h.pos = state.grid.center_of(state.grid.nearest_open(state.grid.cell_of(base + Vector2(0, -4.0).rotated(h.id * 1.3))))
				h.prev_pos = h.pos
				h.goal = Vector2.INF
				h.path = PackedVector2Array()
				h.status = ""
				state.events.append({"type": "HERO_UP", "hero": h.id})
			continue
		if h.pos.distance_to(base) <= float(hc.get("base_heal_radius", 5.0)):
			h.hp = minf(h.max_hp, h.hp + float(hc.get("base_heal_per_second", 8)) * dt)
		if h.role == "player":
			# 조이스틱: 방향·세기 그대로 이동 (막히면 장애물을 따라 미끄러짐)
			if h.joy.length() > 0.08:
				var v: Vector2 = h.joy.limit_length(1.0) * float(hc.get("move_speed", 4.2))
				h.pos = state.grid.move(h.pos, v * dt, radius)
				h.facing = h.joy.normalized()
				h.moving = h.pos.distance_to(h.prev_pos) > 0.0005
			continue
		h.think_t -= dt
		if h.think_t <= 0.0:
			h.think_t = think_iv * (0.5 if h.role == "builder" else 1.0)
			SvAI.think(state, h)
		var speed := float(hc.get("move_speed", 4.2)) * 1.2 if h.role == "builder" else float(hc.get("companion_speed", 3.6))
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


static func set_joystick(state: SvState, v: Vector2) -> void:
	state.player().joy = v.limit_length(1.0)


static func _heroes_attack(state: SvState, dt: float) -> void:
	for h in state.heroes:
		if not h.alive() or state.time < h.building_until:
			continue
		h.cooldown -= dt
		if h.cooldown > 0.0:
			continue
		var t: SvState.SvEnemy = SvAI.select_target(state, h)
		if t == null:
			h.cooldown = 0.0
			h.target_id = -1
			continue
		var d: Dictionary = SvData.hero(h.type)
		_attack(state, h, t, d)
		h.cooldown += float(d.get("interval", 1.0))
		if h.cooldown < 0.0:
			h.cooldown = 0.0


static func _attack(state: SvState, h: SvState.SvHero, target: SvState.SvEnemy, d: Dictionary) -> void:
	## 모든 공격은 광역: 표적 주변을 함께 쓸어 낸다 (data/survival.json의 aoe). 직업 고유 효과는 맞은 적 모두에게.
	h.target_id = target.id
	h.last_attack_time = state.time
	h.attacks += 1
	if target.pos.distance_to(h.pos) > 0.01 and not (h.role == "player" and h.joy.length() > 0.08):
		h.facing = (target.pos - h.pos).normalized()
	var dmg := float(d.get("damage", 5))
	var ao: Dictionary = SvData.aoe(h.type)
	var splash := float(ao.get("splash", 0.0))
	var mult := float(ao.get("mult", 1.0))
	var hit_ids: Array = []
	var points: Array = [target.pos]
	var center := target.pos
	match h.type:
		"SNIPER":
			# 일직선 관통: 나 → 표적 방향으로 사거리 끝까지
			var dir := (target.pos - h.pos).normalized()
			var b := h.pos + dir * SvAI.hero_range(h)
			var wdt := float(ao.get("pierce_width", 0.7))
			for e in state.enemies:
				if e.alive and Geometry2D.get_closest_point_to_segment(e.pos, h.pos, b).distance_to(e.pos) <= wdt:
					damage(state, e, dmg * (1.0 if e.id == target.id else mult), float(d.get("armor_pierce", 0.5)), h.id)
					hit_ids.append(e.id)
			points = [b]
		"LIGHTNING":
			damage(state, target, dmg, 0.0, h.id)
			hit_ids.append(target.id)
			var last := target.pos
			var cur := dmg
			for i in int(ao.get("chain", d.get("chain_count", 2))):
				var nxt: SvState.SvEnemy = null
				var best := INF
				for e in state.enemies:
					if not e.alive or hit_ids.has(e.id):
						continue
					var dd: float = e.pos.distance_to(last)
					if dd <= float(d.get("chain_range", 1.6)) * 1.4 and dd < best:
						best = dd
						nxt = e
				if nxt == null:
					break
				cur *= float(d.get("chain_falloff", 0.7)) * 1.15
				hit_ids.append(nxt.id)
				points.append(nxt.pos)
				last = nxt.pos
				damage(state, nxt, cur, 0.0, h.id)
			h.last_chain_count = hit_ids.size() - 1
		"BOMB":
			var p := SvState.SvProjectile.new()
			p.hero_id = h.id
			p.pos = h.pos
			p.prev_pos = h.pos
			p.target = target.pos
			p.speed = float(d.get("projectile_speed", 7.0)) * 1.4
			p.damage = dmg
			p.radius = splash if splash > 0.0 else float(d.get("blast_radius", 1.2))
			state.projectiles.append(p)
		_:
			for e in state.enemies:
				if not e.alive:
					continue
				var is_main: bool = e.id == target.id
				if not is_main and (splash <= 0.0 or e.pos.distance_to(center) > splash):
					continue
				damage(state, e, dmg * (1.0 if is_main else mult), 0.0, h.id)
				hit_ids.append(e.id)
				if not e.alive:
					continue
				match h.type:
					"FIRE":
						e.burn_t = float(d.get("burn_duration", 3.0))
						e.burn_dps = float(d.get("burn_dps", 2.0))
						e.burn_src = h.id
					"ICE":
						e.slow_t = float(d.get("slow_duration", 1.8))
						e.slow_amt = float(d.get("slow", 0.35))
					"MARK":
						e.mark_t = float(d.get("mark_duration", 2.5))
						e.mark_amt = float(d.get("mark_amp", 0.25))
						e.mark_src = h.id
	state.events.append({"type": "ATTACK", "hero": h.id, "hero_type": h.type, "target": target.id,
		"targets": hit_ids, "points": points, "from": h.pos, "center": center, "fx": str(ao.get("fx", "shot")),
		"radius": splash, "hits": hit_ids.size()})


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
	var base_r := float(SvData.cfg["map"].get("base_attack_radius", 3.3))
	var hero_r := float(SvData.sec("hero", "radius", 0.35))
	for e in state.enemies:
		if not e.alive:
			continue
		e.prev_pos = e.pos
		e.attacking = false
		e.hitting_wall = false
		var d: Dictionary = SvData.enemy(e.type)
		e.atk_cd -= dt
		if e.target_hero >= 0:
			var th: SvState.SvHero = state.heroes[e.target_hero]
			if not th.alive() or th.pos.distance_to(e.pos) > float(d.get("leash", 5.0)):
				e.target_hero = -1
		if e.target_hero < 0:
			var best := -1
			var bd := float(d.get("aggro_radius", 2.5))
			for h in state.heroes:
				if h.alive() and h.pos.distance_to(e.pos) <= bd and state.grid.line_clear(e.pos, h.pos):
					bd = h.pos.distance_to(e.pos)
					best = h.id
			e.target_hero = best
		if e.target_hero >= 0:
			var th2: SvState.SvHero = state.heroes[e.target_hero]
			var dist: float = th2.pos.distance_to(e.pos)
			if dist <= float(d.get("attack_range", 0.8)) + hero_r:
				e.attacking = true
				e.facing = (th2.pos - e.pos).normalized() if dist > 0.01 else e.facing
				if e.atk_cd <= 0.0:
					e.atk_cd = float(d.get("attack_interval", 1.0))
					_hit_hero(state, th2, float(d.get("attack_damage", 6)), e)
				continue
			if state.grid.line_clear(e.pos, th2.pos):
				_enemy_step(state, e, (th2.pos - e.pos).normalized(), dt)
				continue
			e.target_hero = -1
		# 마을(기지)로
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
		var nxt := state.grid.flow_next(e.pos)
		if state.grid.is_wall(nxt):
			# 돌아가는 길보다 벽을 부수는 게 싸다고 계산되면 벽을 공격
			e.attacking = true
			e.hitting_wall = true
			e.facing = (state.grid.center_of(nxt) - e.pos).normalized()
			if e.atk_cd <= 0.0:
				e.atk_cd = float(d.get("attack_interval", 1.0))
				var wid: int = state.grid.walls[nxt]["wall"]
				state.events.append({"type": "WALL_HIT", "enemy": e.id, "cell": nxt, "wall": wid})
				if state.grid.damage_wall(nxt, float(d.get("wall_damage", 6))):
					state.events.append({"type": "WALL_BREAK", "cell": nxt, "wall": wid})
			continue
		var dir: Vector2 = state.grid.center_of(nxt) - e.pos
		if nxt == state.grid.cell_of(e.pos) or dir.length() < 0.05:
			dir = base - e.pos
		_enemy_step(state, e, dir.normalized(), dt)


static func _enemy_step(state: SvState, e: SvState.SvEnemy, dir: Vector2, dt: float) -> void:
	if dir == Vector2.ZERO:
		return
	e.facing = dir
	e.pos = state.grid.move(e.pos, dir * e.effective_speed() * dt, e.radius * 0.8)


static func _hit_hero(state: SvState, h: SvState.SvHero, dmg: float, e: SvState.SvEnemy) -> void:
	h.hp -= dmg
	state.events.append({"type": "HERO_HIT", "hero": h.id, "enemy": e.id, "damage": dmg})
	if h.hp <= 0.0:
		h.hp = 0.0
		h.down_t = float(SvData.sec("hero", "respawn_seconds", 6))
		h.downs += 1
		h.goal = Vector2.INF
		h.path = PackedVector2Array()
		h.path_i = 0
		h.joy = Vector2.ZERO
		state.events.append({"type": "HERO_DOWN", "hero": h.id})
		for o in state.enemies:
			if o.target_hero == h.id:
				o.target_hero = -1


static func _separate(state: SvState) -> void:
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


# ---------------- 건설·필살기 (학생이 승인한 뒤에만 호출) ----------------

static func build_wall(state: SvState, cells: Array) -> int:
	var ok_cells: Array = []
	for c in cells:
		if state.grid.can_build(c):
			var on_unit := false
			for h in state.heroes:
				if h.alive() and state.grid.cell_of(h.pos) == c:
					on_unit = true
			if not on_unit:
				ok_cells.append(c)
	if ok_cells.is_empty():
		return -1
	var cost := ok_cells.size() * int(SvData.sec("build", "cost_per_cell", 1))
	if cost > state.energy:
		return -1
	state.energy -= cost
	var wid := state.next_wall_id
	state.next_wall_id += 1
	state.grid.add_wall(ok_cells, wid, float(SvData.sec("build", "wall_hp", 90)))
	state.walls.append({"id": wid, "cells": ok_cells, "built_at": state.time})
	state.builder().building_until = state.time + 1.2
	state.events.append({"type": "BUILD", "wall": wid, "cells": ok_cells, "cost": cost})
	for e in state.enemies:
		if e.alive and state.grid.is_blocked(state.grid.cell_of(e.pos)):
			e.pos = state.grid.center_of(state.grid.nearest_open(state.grid.cell_of(e.pos)))
	return wid


static func ult_ready(state: SvState, h: SvState.SvHero) -> bool:
	return h.alive() and state.time >= h.ult_ready_t and state.energy >= int(SvData.sec("ultimate", "cost", 8))


static func cast_ultimate(state: SvState, hero_id: int, at: Vector2) -> Dictionary:
	var h: SvState.SvHero = state.heroes[hero_id]
	var u: Dictionary = SvData.ult(h.type)
	if u.is_empty() or not ult_ready(state, h):
		return {}
	state.energy -= int(SvData.sec("ultimate", "cost", 8))
	h.ult_ready_t = state.time + float(SvData.sec("ultimate", "cooldown_seconds", 15))
	var hits := 0
	var center := at
	match str(u.get("shape", "area")):
		"area":
			if u.get("around_self", false):
				center = h.pos
			for e in state.enemies:
				if e.alive and e.pos.distance_to(center) <= float(u["radius"]):
					damage(state, e, float(u.get("damage", 20)), 0.0, h.id)
					hits += 1
					if e.alive:
						if u.has("burn"):
							e.burn_t = 3.0
							e.burn_dps = float(u["burn"])
							e.burn_src = h.id
						if u.has("slow"):
							e.slow_t = float(u.get("slow_duration", 3.0))
							e.slow_amt = float(u["slow"])
						if u.has("mark"):
							e.mark_t = float(u.get("mark_duration", 5.0))
							e.mark_amt = float(u["mark"])
							e.mark_src = h.id
		"line":
			var dir := (at - h.pos).normalized() if at.distance_to(h.pos) > 0.1 else h.facing
			var a := h.pos
			var b := h.pos + dir * float(u.get("length", 12))
			for e in state.enemies:
				if e.alive and Geometry2D.get_closest_point_to_segment(e.pos, a, b).distance_to(e.pos) <= float(u.get("width", 1.0)):
					damage(state, e, float(u.get("damage", 50)), 1.0, h.id)
					hits += 1
			center = b
		"chain":
			var hit: Array = []
			var last := at
			for i in int(u.get("count", 6)):
				var nxt: SvState.SvEnemy = null
				var bd := INF
				for e in state.enemies:
					var dd: float = e.pos.distance_to(last)
					if e.alive and not hit.has(e.id) and dd <= float(u.get("chain_range", 4.0)) and dd < bd:
						bd = dd
						nxt = e
				if nxt == null:
					break
				hit.append(nxt.id)
				last = nxt.pos
				damage(state, nxt, float(u.get("damage", 20)), 0.0, h.id)
				hits += 1
	h.last_attack_time = state.time
	var ev := {"type": "ULT", "hero": hero_id, "hero_type": h.type, "name": u.get("name", ""), "pos": center,
		"from": h.pos, "shape": u.get("shape", "area"), "radius": float(u.get("radius", 2.0)), "hits": hits}
	state.events.append(ev)
	return ev
