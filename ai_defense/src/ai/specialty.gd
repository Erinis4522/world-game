class_name Specialty
extends RefCounted
## 캐릭터별 specialtyFit (0~1). 적 종류가 아니라 '지금 이 적을 치면 내 고유 효과가 얼마나 잘 통하는가'.


static func count_near(state: GameState, center: Vector2, radius: float, exclude_id: int = -1) -> int:
	var n := 0
	for e in state.enemies:
		if e.alive and e.id != exclude_id and e.pos.distance_to(center) <= radius:
			n += 1
	return n


static func allies_in_range(state: GameState, h: Entities.Hero, e: Entities.Enemy) -> int:
	var n := 0
	for o in state.heroes:
		if o.id == h.id:
			continue
		if o.pos.distance_to(e.pos) <= float(GameData.hero(o.type)["range"]):
			n += 1
	return n


static func fit(state: GameState, h: Entities.Hero, e: Entities.Enemy) -> float:
	var d: Dictionary = GameData.hero(h.type)
	match h.type:
		"SWORD":
			# 그 적 주변에 함께 벨 적이 많을수록 (2인 타격 효율)
			var r := float(d["range"])
			var n := 0
			for o in state.enemies:
				if o.alive and o.id != e.id and h.pos.distance_to(o.pos) <= r \
						and o.pos.distance_to(e.pos) <= float(d.get("cluster_radius", 1.2)):
					n += 1
			return clampf(n / 2.0, 0.0, 1.0)
		"ARCHER":
			# 이번 화살로 처치할 가능성 (남은 HP 대비 실제 피해)
			var eff := float(d["damage"]) * GameEngine.damage_multiplier(e, 0.0)
			return clampf(eff / maxf(e.hp, 0.01), 0.0, 1.0)
		"SNIPER":
			# 현재 HP가 많거나 방어가 높은 적
			var hp_part := clampf(e.hp / float(d.get("hp_ref", 200.0)), 0.0, 1.0)
			var armor_part := clampf(e.armor / 0.3, 0.0, 1.0)
			return 0.5 * hp_part + 0.5 * armor_part
		"FIRE":
			# 주변이 밀집했고 아직 화상이 없는 대상
			var k := count_near(state, e.pos, float(d.get("aoe_radius", 0.9)))
			var dense := clampf(k / 4.0, 0.0, 1.0)
			return dense * (0.4 if e.is_burning() else 1.0)
		"ICE":
			# 빠르고 아직 감속되지 않은 적
			var ref := float(GameData.config.get("danger_ref_speed", 1.8))
			var fast := clampf(e.base_speed / ref, 0.0, 1.0)
			return fast * (0.25 if e.is_slowed() else 1.0)
		"LIGHTNING":
			# 주변 적 2명 이상에게 이어질 수 있는 대상
			var c := count_near(state, e.pos, float(d.get("chain_range", 1.6)), e.id)
			return clampf(float(mini(c, int(d.get("chain_count", 2)))) / float(d.get("chain_count", 2)), 0.0, 1.0)
		"BOMB":
			# 폭발 반경에 들어올 적 수
			var k2 := count_near(state, e.pos, float(d.get("blast_radius", 1.2)))
			return clampf(k2 / 4.0, 0.0, 1.0)
		"MARK":
			# 아직 표식이 없고, 다른 아군도 칠 수 있는 위협적인 적
			if e.is_marked():
				return 0.1
			var allies := allies_in_range(state, h, e)
			return clampf(0.4 * Targeting.base_danger(state, e) + 0.6 * minf(allies, 2) / 2.0, 0.0, 1.0)
	return 0.0
