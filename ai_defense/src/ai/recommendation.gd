class_name Recommendation
extends RefCounted
## 특별 전략 제안 — 상태 복제 기반 짧은 가상 전투 비교.
##
## 1. 개입 시점의 GameState를 깊은 복사한다 (실제 상태는 건드리지 않음).
## 2. 지금 화면에 있는 적만으로 같은 N초(기본 10초)를 화면 없이 계산한다. 새 적 스폰은 예지하지 않는다.
## 3. '현재 원칙 유지' 기준안과 '캐릭터 1명의 원칙만 변경'한 최대 6개 대안을 같은 시작 상태로 비교한다.
##    (전투 규칙에 난수가 없으므로 같은 상태 → 항상 같은 결과)
## 4. 목적함수 J = 기지 추가 피해 × 100 + 남은 위협 (작을수록 좋음)
## 5. 개선이 작거나 불확실하면 변경을 제안하지 않는다 → '그대로 가볼까?'


static func threat_of(state: GameState) -> float:
	var t := 0.0
	for e in state.enemies:
		if e.alive:
			t += (e.hp / 25.0) * (0.4 + 0.6 * state.progress(e))
	return t


static func _run(start: GameState, principles: Array, seconds: float, spawns: bool) -> Dictionary:
	var s := start.clone()
	s.spawns_enabled = spawns
	for i in s.heroes.size():
		s.heroes[i].principle = principles[i]
	var dt := GameData.dt()
	var steps := int(round(seconds / dt))
	var dmg0 := s.damage_taken
	var k0 := s.kills
	var l0 := s.leaked
	for i in steps:
		GameEngine.step(s, dt)
		if s.outcome != "":
			break
	return {"damage": s.damage_taken - dmg0, "kills": s.kills - k0, "leaked": s.leaked - l0,
		"threat": threat_of(s), "signature": s.signature()}


static func evaluate(state: GameState, snapshot: GameState, changes: Dictionary) -> Dictionary:
	## changes: {hero_id: principle}. 빈 사전이면 '지금 원칙 유지' 기준안.
	##  forward : 지금 상태에서 horizon초 미리 계산 (지금 있는 적만)
	##  replay  : snapshot(약 12초 전) 시점부터 지금까지를 같은 원칙으로 다시 계산
	##            (그 사이 실제로 나타났던 적만 등장 — 미래 정보 없음)
	var principles: Array = []
	for h in state.heroes:
		principles.append(changes.get(h.id, h.principle))
	var horizon := float(GameData.cfg("suggestion", "horizon_seconds", 10.0))
	var fwd := _run(state, principles, horizon, false)
	var rep: Dictionary = {}
	if snapshot != null and state.time - snapshot.time > 0.5:
		rep = _run(snapshot, principles, state.time - snapshot.time, true)
	var dmg: int = int(fwd["damage"]) + int(rep.get("damage", 0))
	var kills: int = int(fwd["kills"]) + int(rep.get("kills", 0))
	var threat: float = float(fwd["threat"]) + float(rep.get("threat", 0.0))
	var w := float(GameData.cfg("suggestion", "damage_weight", 100.0))
	return {"damage": dmg, "kills": kills, "threat": threat, "J": w * dmg + threat,
		"forward": fwd, "replay": rep, "signature": fwd["signature"]}


static func analyze(state: GameState, observer: CombatObserver, kind: String, info: Dictionary, previous: Array, snapshot: GameState = null) -> Dictionary:
	var horizon := float(GameData.cfg("suggestion", "horizon_seconds", 10.0))
	var replay_len := 0.0
	if snapshot != null:
		replay_len = maxf(0.0, state.time - snapshot.time)
	var base := evaluate(state, snapshot, {})
	var cands: Array = []
	for h in state.heroes:
		for p in GameData.principle_order():
			if p == h.principle:
				continue  # 현재 원칙을 다시 추천하지 않는다
			var r := evaluate(state, snapshot, {h.id: p})
			r["hero_id"] = h.id
			r["to"] = p
			r["improvement"] = float(base["J"]) - float(r["J"])
			cands.append(r)
	cands.sort_custom(func(a, b):
		if absf(a["improvement"] - b["improvement"]) > 1e-6:
			return a["improvement"] > b["improvement"]
		if a["hero_id"] != b["hero_id"]:
			return a["hero_id"] < b["hero_id"]
		return GameData.principle_order().find(a["to"]) < GameData.principle_order().find(b["to"]))
	var min_abs := float(GameData.cfg("suggestion", "min_improvement_abs", 0.6))
	var min_ratio := float(GameData.cfg("suggestion", "min_improvement_ratio", 0.08))
	var good: Array = []
	for r in cands:
		var fewer_damage: bool = r["damage"] < base["damage"]
		var no_more_damage: bool = r["damage"] <= base["damage"]
		var big_enough: bool = r["improvement"] >= maxf(min_abs, min_ratio * float(base["threat"]))
		if fewer_damage or (no_more_damage and big_enough):
			good.append(r)
	var pick: Dictionary = {}
	if not good.is_empty():
		pick = good[0]
		# 같은 캐릭터·원칙 제안을 반복하지 않도록, 비슷하게 좋은 다른 후보가 있으면 그쪽
		if _is_repeat(pick, previous):
			var keep_ratio := float(GameData.cfg("suggestion", "repeat_keep_ratio", 0.8))
			for r in good:
				if not _is_repeat(r, previous) and float(r["improvement"]) >= keep_ratio * float(pick["improvement"]):
					pick = r
					break
	var result := {
		"kind": kind, "info": info, "time": state.time, "horizon": horizon, "replay_seconds": replay_len,
		"base": base, "candidates": cands, "has_change": not pick.is_empty(),
		"simulated": true,
	}
	var hero_id: int
	if pick.is_empty():
		hero_id = _speaker_without_change(state, info)
		result["to"] = ""
		result["alt"] = {}
	else:
		hero_id = pick["hero_id"]
		result["to"] = pick["to"]
		result["alt"] = pick
	var h: Entities.Hero = state.heroes[hero_id]
	result["hero_id"] = hero_id
	result["hero_type"] = h.type
	result["from"] = h.principle
	_build_text(result, state, observer)
	return result


static func _is_repeat(r: Dictionary, previous: Array) -> bool:
	for p in previous:
		if int(p.get("hero_id", -1)) == int(r["hero_id"]) and str(p.get("to", "")) == str(r["to"]):
			return true
	return false


static func _speaker_without_change(state: GameState, info: Dictionary) -> int:
	var front: Entities.Enemy = null
	for e in state.enemies:
		if e.alive and (front == null or e.dist > front.dist):
			front = e
	if front == null:
		return 0
	var best := 0
	var bd := INF
	for h in state.heroes:
		var d: float = h.pos.distance_to(front.pos)
		if d < bd:
			bd = d
			best = h.id
	return best


# ---------------- 문장 만들기 ----------------

static func _build_text(r: Dictionary, state: GameState, observer: CombatObserver) -> void:
	var hero_type: String = r["hero_type"]
	var hero_name: String = GameData.hero(hero_type)["name"]
	var info: Dictionary = r["info"]
	var situation := ""
	match r["kind"]:
		"crisis":
			if info.get("reason", "") == "group":
				situation = TextUtil.fill(GameData.text("suggest", "situation_crisis_group"), {"n": info["count"]})
			else:
				var types: Dictionary = info.get("types", {})
				var main_type := ""
				for t in types.keys():
					if main_type == "" or int(types[t]) > int(types[main_type]):
						main_type = t
				situation = TextUtil.fill(GameData.text("suggest", "situation_crisis_single"),
					{"enemy": GameData.enemy(main_type).get("name", "적"), "n": types.get(main_type, 1)})
		"first_hit":
			situation = TextUtil.fill(GameData.text("suggest", "situation_hit"),
				{"before": info.get("hp_before", state.base_hp_max), "after": info.get("hp_after", state.base_hp)})
		_:
			situation = GameData.text("suggest", "situation_test")
	r["situation"] = situation
	r["evidence"] = _evidence(r, state, observer)
	var pros: Array = []
	var cons: Array = []
	var h: float = r["horizon"]
	var rs := int(round(float(r["replay_seconds"])))
	var calc := TextUtil.fill(GameData.text("suggest", "calc_both" if rs > 0 else "calc_forward"), {"h": int(h), "r": rs})
	r["calc"] = calc
	var base: Dictionary = r["base"]
	if r["has_change"]:
		var alt: Dictionary = r["alt"]
		var to: String = r["to"]
		pros.append(_principle_line("pro_principle", to, hero_type))
		if alt["damage"] < base["damage"]:
			pros.append(TextUtil.fill(GameData.text("suggest", "pro_measured_damage"), {"calc": calc, "a": base["damage"], "b": alt["damage"]}))
		var tb := float(base["threat"])
		var ta := float(alt["threat"])
		if tb > 0.01 and ta < tb and (tb - ta) / tb >= 0.05:
			pros.append(TextUtil.fill(GameData.text("suggest", "pro_measured_threat"), {"p": int(round(100.0 * (tb - ta) / tb))}))
		if alt["kills"] > base["kills"]:
			pros.append(TextUtil.fill(GameData.text("suggest", "pro_measured_kills"), {"a": base["kills"], "b": alt["kills"]}))
		if alt["kills"] < base["kills"]:
			cons.append(TextUtil.fill(GameData.text("suggest", "con_measured_kills"), {"a": base["kills"], "b": alt["kills"]}))
		if ta > tb + 0.01:
			cons.append(GameData.text("suggest", "con_measured_threat"))
		cons.append(_principle_line("con_principle", to, hero_type))
		r["ask"] = TextUtil.fill(GameData.text("suggest", "ask"), {
			"from": GameData.principle_name(r["from"]), "to": GameData.principle_name(to), "euro": TextUtil.euro_suffix(GameData.principle_name(to))})
		r["estimate"] = TextUtil.fill(GameData.text("suggest", "estimate_line"), {"calc": calc,
			"bd": base["damage"], "bk": base["kills"], "ad": alt["damage"], "ak": alt["kills"]})
	else:
		pros.append(GameData.text("suggest", "keep_pro"))
		cons.append(GameData.text("suggest", "keep_con"))
		r["ask"] = GameData.text("suggest", "keep_ask")
		r["estimate"] = TextUtil.fill(GameData.text("suggest", "estimate_keep"), {"calc": calc,
			"bd": base["damage"], "bk": base["kills"]})
	r["pros"] = pros
	r["cons"] = cons
	r["estimate_note"] = TextUtil.fill(GameData.text("suggest", "estimate_note"), {"h": int(h)})
	var parts: Array = [situation]
	if r["evidence"] != "":
		parts.append(r["evidence"])
	var msg: String = ". ".join(parts) + ".\n" + str(r["ask"])
	if r["has_change"]:
		msg += "\n" + str(pros[0]) + ". 대신 " + str(cons[cons.size() - 1]) + "."
	r["message"] = msg
	r["speaker_name"] = GameData.person(hero_type)


static func _principle_line(section: String, to: String, hero_type: String) -> String:
	var s: Dictionary = GameData.dialog.get("suggest", {}).get(section, {})
	var v: Variant = s.get(to, "")
	if v is Dictionary:
		return str(v.get(hero_type, v.get("default", "")))
	return str(v)


static func _evidence(r: Dictionary, state: GameState, observer: CombatObserver) -> String:
	## 앞서 실제로 관찰된 현상 한 가지를 인용한다. 관찰된 적이 없으면 비운다.
	var hero_type: String = r["hero_type"]
	var to: String = r["to"]
	var order: Array = []
	if to == "SPECIAL":
		match hero_type:
			"ICE": order = ["SELF_FAST_PASSED", "FAST_INCOMING"]
			"SNIPER": order = ["ARMORED_SURVIVED"]
			"SWORD", "FIRE", "BOMB", "LIGHTNING": order = ["CROWD"]
			"ARCHER": order = ["SELF_PASSED"]
			"MARK": order = ["SELF_PASSED", "CROWD"]
	elif to == "DANGER":
		order = ["SELF_FAST_PASSED", "SELF_PASSED", "LEAK"]
	elif to == "NEAREST":
		order = ["SELF_PASSED", "CROWD"]
	else:
		order = ["SELF_FAST_PASSED", "CROWD", "ARMORED_SURVIVED", "SELF_PASSED"]
	var ev_tpl: Dictionary = GameData.dialog.get("suggest", {}).get("evidence", {})
	for code in order:
		var n := 0
		if code == "SELF_FAST_PASSED":
			n = int(observer.hero_passed_fast.get(r["hero_id"], 0))
		elif code == "SELF_PASSED":
			n = int(observer.hero_passed.get(r["hero_id"], 0))
		else:
			n = observer.count(code)
		if n > 0 and ev_tpl.has(code):
			r["evidence_code"] = code
			return TextUtil.fill(str(ev_tpl[code]), {"n": n})
	r["evidence_code"] = ""
	return ""
