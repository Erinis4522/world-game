class_name Targeting
extends RefCounted
## Utility AI 표적 선정.
##   score(t, e) = wDistance × proximity + wDanger × baseDanger + wSpecial × specialtyFit
## 사거리 밖 적은 후보에서 빠진다. 동률이면 진행률이 높은 적 → 작은 id.

const EPS := 1e-9


static func candidates(state: GameState, h: Entities.Hero) -> Array:
	var rng := float(GameData.hero(h.type)["range"])
	var out: Array = []
	for e in state.enemies:
		if e.alive and h.pos.distance_to(e.pos) <= rng:
			out.append(e)
	return out


static func proximity(h: Entities.Hero, e: Entities.Enemy) -> float:
	var rng := float(GameData.hero(h.type)["range"])
	return clampf(1.0 - h.pos.distance_to(e.pos) / rng, 0.0, 1.0)


static func base_danger(state: GameState, e: Entities.Enemy) -> float:
	var ref := float(GameData.config.get("danger_ref_speed", 1.8))
	return clampf(0.75 * state.progress(e) + 0.25 * (e.effective_base_speed() / ref), 0.0, 1.0)


static func breakdown(state: GameState, h: Entities.Hero, e: Entities.Enemy, principle: String = "") -> Dictionary:
	var p := principle if principle != "" else h.principle
	var w: Dictionary = GameData.principle_weights(p)
	var prox := proximity(h, e)
	var dang := base_danger(state, e)
	var spec := Specialty.fit(state, h, e)
	var total := float(w["w_distance"]) * prox + float(w["w_danger"]) * dang + float(w["w_special"]) * spec
	return {"proximity": prox, "danger": dang, "special": spec, "score": total}


static func select(state: GameState, h: Entities.Hero, principle: String = "") -> Entities.Enemy:
	var best: Entities.Enemy = null
	var best_score := -INF
	for e in candidates(state, h):
		var s: float = breakdown(state, h, e, principle)["score"]
		if best == null or s > best_score + EPS:
			best = e
			best_score = s
		elif absf(s - best_score) <= EPS:
			if e.dist > best.dist + EPS or (absf(e.dist - best.dist) <= EPS and e.id < best.id):
				best = e
				best_score = s
	return best
