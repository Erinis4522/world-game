class_name SvAI
extends RefCounted
## 3D 서바이벌의 AI 판단 (Utility AI, 가중치 점수). 신경망·생성형 AI가 아니다.
##  - 표적 선택: 기존 행동 원칙(가까운 적 / 위험한 적 / 특기 활용) 가중치.
##    '위험'은 마을까지 남은 길(흐름장 거리)·아군을 노리는지·빠르기로 계산
##  - 동료 3명: 각자 맡은 길(구역)을 지키며, 근처에 더 위험한 적이 있으면 도우러 간다.
##    체력이 낮으면 마을로 물러나 회복. 학생이 정한 원칙은 스스로 바꾸지 않는다.
##  - 건설 동료: 항상 대표 캐릭터 옆을 따라다닌다.


static func hero_range(h: SvState.SvHero) -> float:
	return float(SvData.hero(h.type).get("range", 2.0)) * float(SvData.sec("hero", "range_scale", 1.0))


static func danger(state: SvState, e: SvState.SvEnemy) -> float:
	var fd := state.grid.flow_distance(e.pos)
	var near := clampf(1.0 - fd / 50.0, 0.0, 1.0) if fd < SvGrid.INF_D else 0.0
	var hunting := 1.0 if e.target_hero >= 0 else 0.0
	var spd := clampf(e.effective_speed() / 2.7, 0.0, 1.0)
	return clampf(0.6 * near + 0.2 * hunting + 0.2 * spd, 0.0, 1.0)


static func count_near(state: SvState, c: Vector2, r: float, exclude := -1) -> int:
	var n := 0
	for e in state.enemies:
		if e.alive and e.id != exclude and e.pos.distance_to(c) <= r:
			n += 1
	return n


static func damage_multiplier(e: SvState.SvEnemy, pierce: float) -> float:
	return (1.0 - e.armor * (1.0 - pierce)) * (1.0 + (e.mark_amt if e.mark_t > 0.0 else 0.0))


static func specialty(state: SvState, h: SvState.SvHero, e: SvState.SvEnemy) -> float:
	var d: Dictionary = SvData.hero(h.type)
	match h.type:
		"SWORD":
			return clampf(count_near(state, e.pos, float(d.get("cluster_radius", 1.2)), e.id) / 2.0, 0.0, 1.0)
		"ARCHER":
			return clampf(float(d["damage"]) * damage_multiplier(e, 0.0) / maxf(e.hp, 0.01), 0.0, 1.0)
		"SNIPER":
			return 0.5 * clampf(e.hp / float(d.get("hp_ref", 200.0)), 0.0, 1.0) + 0.5 * clampf(e.armor / 0.3, 0.0, 1.0)
		"FIRE":
			return clampf(count_near(state, e.pos, float(d.get("aoe_radius", 0.9))) / 4.0, 0.0, 1.0) * (0.4 if e.is_burning() else 1.0)
		"ICE":
			return clampf(e.speed / 2.7, 0.0, 1.0) * (0.25 if e.is_slowed() else 1.0)
		"LIGHTNING":
			var c := mini(count_near(state, e.pos, float(d.get("chain_range", 1.6)), e.id), int(d.get("chain_count", 2)))
			return float(c) / float(d.get("chain_count", 2))
		"BOMB":
			return clampf(count_near(state, e.pos, float(d.get("blast_radius", 1.2))) / 4.0, 0.0, 1.0)
		"MARK":
			if e.is_marked():
				return 0.1
			var allies := 0
			for o in state.heroes:
				if o.id != h.id and o.alive() and o.pos.distance_to(e.pos) <= hero_range(o) + 1.0:
					allies += 1
			return clampf(0.4 * danger(state, e) + 0.6 * minf(allies, 2) / 2.0, 0.0, 1.0)
	return 0.0


static func score(state: SvState, h: SvState.SvHero, e: SvState.SvEnemy) -> float:
	var w: Dictionary = GameData.principle_weights(h.principle)
	var prox := clampf(1.0 - h.pos.distance_to(e.pos) / maxf(hero_range(h), 0.1), 0.0, 1.0)
	return float(w["w_distance"]) * prox + float(w["w_danger"]) * danger(state, e) + float(w["w_special"]) * specialty(state, h, e)


static func select_target(state: SvState, h: SvState.SvHero) -> SvState.SvEnemy:
	var rng := hero_range(h)
	var best: SvState.SvEnemy = null
	var bs := -INF
	for e in state.enemies:
		if not e.alive or h.pos.distance_to(e.pos) > rng + e.radius * 0.5:
			continue
		var s: float = score(state, h, e)
		if best == null or s > bs + 1e-9 or (absf(s - bs) <= 1e-9 and e.id < best.id):
			best = e
			bs = s
	return best


# ---------------- 이동 판단 ----------------

static func think(state: SvState, h: SvState.SvHero) -> void:
	if not h.alive():
		return
	match h.role:
		"builder":
			_think_builder(state, h)
		"companion":
			_think_companion(state, h)


static func _think_builder(state: SvState, h: SvState.SvHero) -> void:
	if state.time < h.building_until:
		h.status = "건설 중"
		h.goal = Vector2.INF
		h.path = PackedVector2Array()
		return
	var p: SvState.SvHero = state.player()
	var anchor := p.pos if p.alive() else SvData.base_center()
	var back := -p.facing if p.facing.length() > 0.1 else Vector2(0, 1)
	var want := anchor + (back * 0.8 + back.orthogonal() * 0.9).normalized() * float(SvData.sec("companion", "follow_distance", 1.6))
	if h.pos.distance_to(want) > 1.0:
		_set_goal(state, h, want)
	h.status = "따라가는 중"


static func _think_companion(state: SvState, h: SvState.SvHero) -> void:
	var cc: Dictionary = SvData.cfg["companion"]
	var base := SvData.base_center()
	var rng := hero_range(h)
	if h.hp < h.max_hp * float(SvData.sec("hero", "retreat_hp_ratio", 0.3)) or (h.status == "후퇴 중" and h.hp < h.max_hp * 0.7):
		_set_goal(state, h, base + Vector2(0, -4.0).rotated(h.id * 1.3))
		h.status = "후퇴 중"
		return
	var guard := SvData.zone_guard(h.zone)
	var zr := float(cc.get("zone_radius", 9.0))
	var help := float(cc.get("help_radius", 16.0))
	var target: SvState.SvEnemy = null
	var bu := -INF
	for e in state.enemies:
		if not e.alive:
			continue
		var dg: float = e.pos.distance_to(guard)
		var dh: float = e.pos.distance_to(h.pos)
		if dg > zr and dh > help:
			continue
		var u: float = 0.6 * danger(state, e) + 0.4 * clampf(1.0 - dh / 16.0, 0.0, 1.0)
		if str(SvData.zone_at(e.pos).get("id", "")) == h.zone:
			u += 0.25  # 내가 맡은 길의 적부터
		if dg > zr:
			u -= 0.15  # 구역 밖이면 정말 위험할 때만
		if u > bu:
			bu = u
			target = e
	if target != null:
		var away := h.pos - target.pos
		if away.length() < 0.01:
			away = Vector2(1, 0)
		_set_goal(state, h, target.pos + away.normalized() * rng * float(cc.get("engage_fraction", 0.8)))
		h.status = "%s 지키는 중" % SvData.zone(h.zone)["name"] if target.pos.distance_to(guard) <= zr else "도우러 가는 중"
		return
	if h.pos.distance_to(guard) > 1.5:
		_set_goal(state, h, guard)
	h.status = "%s 지키는 중" % SvData.zone(h.zone)["name"]


static func _set_goal(state: SvState, h: SvState.SvHero, g: Vector2) -> void:
	g = state.grid.clamp_to_map(g)
	if state.grid.is_blocked(state.grid.cell_of(g)):
		g = state.grid.center_of(state.grid.nearest_open(state.grid.cell_of(g)))
	if h.goal != Vector2.INF and h.goal.distance_to(g) < 0.8 and h.path_i < h.path.size():
		return
	h.goal = g
	h.path = state.grid.find_path(h.pos, g)
	h.path_i = 0
