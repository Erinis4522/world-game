class_name SvAI
extends RefCounted
## 3D 서바이벌의 AI 판단 (Utility AI, 가중치 점수).
##  - 표적 선택: 기존 원칙 가중치(거리·위험·특기)를 그대로 쓰되,
##    '위험'은 고정 경로 진행률 대신 기지까지 거리·아군을 노리는지·빠르기로 계산
##  - 동료 이동: 전술(집결 / 기지 방어 / 집중공격)에 따라 지킬 곳을 정하고,
##    그 주변 적 중 점수가 가장 높은 적에게 사거리만큼 다가간다. 체력이 낮으면 기지로 물러난다.
## 학생이 정한 전술은 AI가 스스로 바꾸지 않는다.


static func hero_range(h: SvState.SvHero) -> float:
	return float(GameData.hero(h.type)["range"]) * float(SvData.sec("hero", "range_scale", 1.0))


static func danger(state: SvState, e: SvState.SvEnemy) -> float:
	var bd := e.pos.distance_to(SvData.base_center())
	var near_base := clampf(1.0 - bd / 12.0, 0.0, 1.0)
	var hunting := 1.0 if e.target_hero >= 0 else 0.0
	var spd := clampf(e.effective_speed() / 2.7, 0.0, 1.0)
	return clampf(0.55 * near_base + 0.25 * hunting + 0.2 * spd, 0.0, 1.0)


static func _count_near(state: SvState, c: Vector2, r: float, exclude := -1) -> int:
	var n := 0
	for e in state.enemies:
		if e.alive and e.id != exclude and e.pos.distance_to(c) <= r:
			n += 1
	return n


static func damage_multiplier(e: SvState.SvEnemy, pierce: float) -> float:
	return (1.0 - e.armor * (1.0 - pierce)) * (1.0 + (e.mark_amt if e.mark_t > 0.0 else 0.0))


static func specialty(state: SvState, h: SvState.SvHero, e: SvState.SvEnemy) -> float:
	## 기존 Specialty.fit과 같은 기준 (캐릭터 고유 효과가 얼마나 잘 통하는가)
	var d: Dictionary = GameData.hero(h.type)
	match h.type:
		"SWORD":
			return clampf(_count_near(state, e.pos, float(d.get("cluster_radius", 1.2)), e.id) / 2.0, 0.0, 1.0)
		"ARCHER":
			return clampf(float(d["damage"]) * damage_multiplier(e, 0.0) / maxf(e.hp, 0.01), 0.0, 1.0)
		"SNIPER":
			return 0.5 * clampf(e.hp / float(d.get("hp_ref", 200.0)), 0.0, 1.0) + 0.5 * clampf(e.armor / 0.3, 0.0, 1.0)
		"FIRE":
			return clampf(_count_near(state, e.pos, float(d.get("aoe_radius", 0.9))) / 4.0, 0.0, 1.0) * (0.4 if e.is_burning() else 1.0)
		"ICE":
			return clampf(e.speed / 2.7, 0.0, 1.0) * (0.25 if e.is_slowed() else 1.0)
		"LIGHTNING":
			var c := mini(_count_near(state, e.pos, float(d.get("chain_range", 1.6)), e.id), int(d.get("chain_count", 2)))
			return float(c) / float(d.get("chain_count", 2))
		"BOMB":
			return clampf(_count_near(state, e.pos, float(d.get("blast_radius", 1.2))) / 4.0, 0.0, 1.0)
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
	var s := float(w["w_distance"]) * prox + float(w["w_danger"]) * danger(state, e) + float(w["w_special"]) * specialty(state, h, e)
	if not h.is_player and h.tactic == "FOCUS" and e.id == h.focus_id:
		s += 0.6  # 집중공격 대상이 사거리 안이면 먼저
	return s


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


# ---------------- 동료 이동 판단 ----------------

static func strongest_enemy(state: SvState) -> SvState.SvEnemy:
	var best: SvState.SvEnemy = null
	var bv := -1.0
	for e in state.enemies:
		if not e.alive:
			continue
		var v: float = e.hp * (1.0 + e.armor) * (0.6 + danger(state, e))
		if v > bv:
			bv = v
			best = e
	return best


static func think(state: SvState, h: SvState.SvHero) -> void:
	if h.is_player or not h.alive():
		return
	var cc: Dictionary = SvData.cfg["companion"]
	var base := SvData.base_center()
	var rng := hero_range(h)
	var p: SvState.SvHero = state.player()
	# 1) 위험 회피: 체력이 낮으면 기지로 물러나 회복
	if h.hp < h.max_hp * float(SvData.sec("hero", "retreat_hp_ratio", 0.3)) or (h.status == "후퇴 중" and h.hp < h.max_hp * 0.7):
		_set_goal(state, h, base + Vector2(0, 2.2).rotated(h.id * 2.1))
		h.status = "후퇴 중"
		return
	var anchor := base
	var radius := float(cc.get("defend_radius", 6.5))
	if h.tactic == "GATHER":
		anchor = p.pos if p.alive() else base
		radius = float(cc.get("gather_radius", 4.0))
	var target: SvState.SvEnemy = null
	if h.tactic == "FOCUS":
		target = state.find_enemy(h.focus_id)
		if target == null or not target.alive:
			target = strongest_enemy(state)
			h.focus_id = target.id if target != null else -1
	else:
		var bu := -INF
		for e in state.enemies:
			if not e.alive or e.pos.distance_to(anchor) > radius + rng:
				continue
			var u: float = 0.6 * danger(state, e) + 0.4 * clampf(1.0 - h.pos.distance_to(e.pos) / 12.0, 0.0, 1.0)
			if h.tactic == "GATHER" and e.target_hero == p.id:
				u += 0.3  # 대표 캐릭터를 노리는 적부터
			if u > bu:
				bu = u
				target = e
	if target != null:
		var away := h.pos - target.pos
		if away.length() < 0.01:
			away = Vector2(1, 0)
		var stand := target.pos + away.normalized() * rng * float(cc.get("engage_fraction", 0.8))
		_set_goal(state, h, stand)
		h.status = SvData.tactic_status(h.tactic)
		return
	# 3) 적이 없으면 지킬 곳 근처 대형 위치로
	var off := Vector2(float(cc.get("follow_distance", 1.6)), 0).rotated(PI * 0.6 + h.id * PI * 0.8)
	_set_goal(state, h, anchor + off)
	h.status = "대기 중" if h.tactic != "GATHER" else "따라가는 중"


static func _set_goal(state: SvState, h: SvState.SvHero, g: Vector2) -> void:
	g = state.grid.clamp_to_map(g)
	if h.goal != Vector2.INF and h.goal.distance_to(g) < 0.6 and h.path_i < h.path.size():
		return  # 거의 같은 목적지면 경로 유지
	h.goal = g
	h.path = state.grid.find_path(h.pos, g)
	h.path_i = 0
