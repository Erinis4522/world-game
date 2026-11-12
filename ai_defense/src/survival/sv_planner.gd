class_name SvPlanner
extends RefCounted
## 그림 → 실제 건설·필살기 제안 (AI 판단, 실제 지형·전황 계산).
## 벽: 모양(꼭짓점 배치와 방향)은 학생이 그린 그대로 두고, '크기'와 '위치'만 AI가 고른다.
##  1) 대표 캐릭터 주변 search_radius 안의 칸을 후보 중심으로, 크기 4~9칸 후보를 만든다
##  2) 빠른 점수: 길을 가로지르는가, 다가오는 적과 마을 사이인가, 건설 가능한 칸 비율, 거리, 에너지
##  3) 상위 후보만 격자 복사본에 실제로 세워 보고 흐름장을 다시 계산:
##     적이 마을까지 가는 비용이 얼마나 늘어나는지 + 우리(대표 캐릭터)가 마을로 가는 길이 막히지 않는지
##  4) 가장 좋은 안 + 장점·단점을 학생에게 보여 주고, 승인해야만 건설한다
## 필살기: 그 동료 주변에서 적이 가장 많이 맞는 위치를 계산해 제안한다.


static func rasterize(norm: PackedVector2Array, center: Vector2, size_cells: float) -> Array:
	var cells: Dictionary = {}
	for i in range(1, norm.size()):
		var a := center + norm[i - 1] * size_cells
		var b := center + norm[i] * size_cells
		var steps := int(ceil(a.distance_to(b) / 0.35)) + 1
		for k in steps + 1:
			var p := a.lerp(b, float(k) / float(steps))
			cells[Vector2i(int(floor(p.x)), int(floor(p.y)))] = true
	return cells.keys()


static func plan_wall(state: SvState, simplified: PackedVector2Array, shape_name: String) -> Dictionary:
	var g := state.grid
	var norm := SvSketch.normalized(simplified)
	var p: SvState.SvHero = state.player()
	var origin := p.pos if p.alive() else SvData.base_center()
	var bcfg: Dictionary = SvData.cfg["build"]
	var max_cells := int(bcfg.get("max_cells", 9))
	var min_cells := int(bcfg.get("min_cells", 3))
	var per := int(bcfg.get("cost_per_cell", 1))
	var radius := float(bcfg.get("search_radius", 14))
	var base := SvData.base_center()
	var cands: Array = []
	for size_c in [4.0, 5.0, 6.0, 7.0, 8.0]:
		for dy in range(-int(radius), int(radius) + 1):
			for dx in range(-int(radius), int(radius) + 1):
				var c := Vector2(floor(origin.x) + dx + 0.5, floor(origin.y) + dy + 0.5)
				if c.distance_to(origin) > radius:
					continue
				var cc := g.cell_of(c)
				if not g.inside(cc) or not g.is_road(cc):
					continue  # 중심은 길 위 (길을 막는 벽이 의미 있음)
				var cells := rasterize(norm, c, size_c)
				var ok: Array = []
				for k in cells:
					if g.can_build(k):
						ok.append(k)
				if ok.size() < min_cells or ok.size() > max_cells or ok.size() * per > state.energy:
					continue
				if float(ok.size()) / float(cells.size()) < 0.7:
					continue  # 그린 모양이 많이 잘리면 탈락
				var road_cells := 0
				for k in ok:
					if g.is_road(k):
						road_cells += 1
				var fd := g.flow_distance(c)
				var upstream := 0
				for e in state.enemies:
					if e.alive and e.pos.distance_to(c) < 12.0 and g.flow_distance(e.pos) > fd:
						upstream += 1
				# 길을 가로지르는가: 벽 양 끝이 길 밖이면 길 폭 전체를 막는다 (길과 나란히 놓인 벽은 효과가 적음)
				var ends_off := 0
				for endp in [c + norm[0] * size_c, c + norm[norm.size() - 1] * size_c]:
					if not g.is_road(g.cell_of(endp)):
						ends_off += 1
				var s := minf(road_cells, 5.0) + ends_off * 2.5 + upstream * 0.4 - c.distance_to(origin) * 0.4
				if fd < 4.0:
					s -= 3.0  # 마을 바로 앞은 우리 길도 막힘
				cands.append({"center": c, "size": size_c, "cells": ok, "road_cells": road_cells, "upstream": upstream, "ends_off": ends_off, "quick": s})
	if cands.is_empty():
		var why := "에너지가 부족해요 (지금 %d)" % state.energy if state.energy < min_cells * per else "근처 길 위에 이 모양을 세울 자리가 없어요. 길 가까이 가서 다시 그려 줘"
		return {"ok": false, "reason": why}
	cands.sort_custom(func(a, b): return a["quick"] > b["quick"])
	var best: Dictionary = {}
	var best_score := -INF
	var base_path := g.walk_steps(origin, base + Vector2(0, -3.5))
	for cand in cands.slice(0, 4):
		var gg := g.clone()
		gg.add_wall(cand["cells"], 999, 1.0)
		var detour := 0.0
		var affected := 0
		for e in state.enemies:
			if not e.alive:
				continue
			var before := g.flow_distance(e.pos)
			var after := gg.flow_distance(e.pos)
			if after > before + 0.5 and after < SvGrid.INF_D:
				detour += minf(after - before, 30.0)
				affected += 1
		var road_id := g.road_of(cand["center"])
		# 적이 없어도 '그 길을 따라 오는 적'에게 얼마나 길어지는지 (게이트에서 측정)
		var gate_gain := 0.0
		if road_id != "":
			var gp := SvData.gate_pos(road_id)
			gate_gain = maxf(0.0, gg.flow_distance(gp) - g.flow_distance(gp))
		var ally_path := gg.walk_steps(origin, base + Vector2(0, -3.5))
		var ally_cut := ally_path >= SvGrid.INF_D
		var ally_extra := 0.0 if ally_cut or base_path >= SvGrid.INF_D else maxf(0.0, ally_path - base_path)
		var score: float = cand["quick"] + detour * 0.15 + minf(gate_gain, 40.0) * 0.5 - ally_extra * 0.2 - (25.0 if ally_cut else 0.0)
		if score > best_score:
			best_score = score
			best = cand.duplicate()
			best["detour"] = detour
			best["affected"] = affected
			best["gate_gain"] = gate_gain
			best["ally_cut"] = ally_cut
			best["ally_extra"] = ally_extra
			best["road"] = road_id
	var pros: Array = []
	var cons: Array = []
	var road_name: String = str(SvData.zone_at(best["center"]).get("name", "길"))
	if best["road_cells"] > 0 and best["gate_gain"] > 1.0:
		pros.append("%s을 막아서 적 무리가 돌아가거나 벽을 부숴야 해요" % road_name)
	if best["gate_gain"] > 1.0:
		pros.append("그 길로 오는 적이 마을까지 가는 데 더 오래 걸려요 (계산상 이동 비용 +%d)" % int(best["gate_gain"]))
	if best["affected"] > 0:
		pros.append("지금 다가오는 적 %d마리의 길이 바뀌어요" % best["affected"])
	if best["ally_cut"]:
		cons.append("우리도 이쪽으로 마을에 돌아가기 어려워질 수 있어요")
	elif best["ally_extra"] > 2.0:
		cons.append("우리 이동 길도 좁아져요 (마을까지 %d칸 더 돌아가요)" % int(best["ally_extra"]))
	cons.append("벽은 부서질 수 있어요 (한 칸 내구도 %d)" % int(SvData.sec("build", "wall_hp", 90)))
	cons.append("에너지 %d 사용 (남는 에너지 %d)" % [best["cells"].size() * per, state.energy - best["cells"].size() * per])
	if pros.is_empty():
		pros.append("길 옆에 세워 적이 우회하는 공간을 줄여요")
	return {"ok": true, "kind": "WALL", "shape": shape_name, "cells": best["cells"], "center": best["center"],
		"size": best["size"], "cost": best["cells"].size() * per, "road": best["road"], "road_name": road_name,
		"pros": pros, "cons": cons, "candidates": cands.size(),
		"metrics": {"detour": best["detour"], "affected": best["affected"], "gate_gain": best["gate_gain"], "ally_extra": best["ally_extra"], "ally_cut": best["ally_cut"]}}


static func plan_ultimate(state: SvState, hero_id: int) -> Dictionary:
	var h: SvState.SvHero = state.heroes[hero_id]
	var u: Dictionary = SvData.ult(h.type)
	var name := str(u.get("name", "필살기"))
	var person := SvData.person(h.type)
	if not h.alive():
		return {"ok": false, "reason": "%s 지금 쓰러져 있어요" % TextUtil.iga(person)}
	var cost := int(SvData.sec("ultimate", "cost", 8))
	if state.energy < cost:
		return {"ok": false, "reason": "에너지가 부족해요 (필요 %d, 지금 %d)" % [cost, state.energy]}
	if state.time < h.ult_ready_t:
		return {"ok": false, "reason": "%s의 %s 준비 중이에요 (%d초)" % [person, name, int(ceil(h.ult_ready_t - state.time))]}
	var sr := float(SvData.sec("ultimate", "search_radius", 10))
	var best := h.pos
	var best_n := 0
	var shape := str(u.get("shape", "area"))
	for e in state.enemies:
		if not e.alive or e.pos.distance_to(h.pos) > sr:
			continue
		var n := 0
		match shape:
			"area":
				var c: Vector2 = h.pos if u.get("around_self", false) else e.pos
				n = SvAI.count_near(state, c, float(u.get("radius", 3.0)))
			"line":
				var dir: Vector2 = (e.pos - h.pos).normalized()
				var b := h.pos + dir * float(u.get("length", 12))
				for o in state.enemies:
					if o.alive and Geometry2D.get_closest_point_to_segment(o.pos, h.pos, b).distance_to(o.pos) <= float(u.get("width", 1.0)):
						n += 1
			"chain":
				n = mini(int(u.get("count", 6)), SvAI.count_near(state, e.pos, float(u.get("chain_range", 4.0)) * 2.0))
		if n > best_n:
			best_n = n
			best = e.pos
	var pros: Array = []
	var cons: Array = ["에너지 %d 사용, %d초 동안 다시 못 써요" % [cost, int(SvData.sec("ultimate", "cooldown_seconds", 15))]]
	if best_n > 0:
		pros.append("%s 근처에서 적 약 %d마리를 한꺼번에 노릴 수 있어요" % [person, best_n])
	else:
		cons.push_front("지금 %s 근처에는 적이 없어서 효과가 거의 없을 수 있어요" % person)
	return {"ok": true, "kind": "ULT", "hero": hero_id, "hero_type": h.type, "name": name, "pos": best, "expected": best_n,
		"pros": pros, "cons": cons, "cost": cost}
