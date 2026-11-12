class_name SvSession
extends RefCounted
## 3D 서바이벌 한 판 = SvState + 학생 명령 + 그림 제안 + 말풍선.
## 화면(Node)과 독립이라 실제 게임·자동 테스트·밸런스 도구가 같이 쓴다.
##
## 학생 명령
##  - joystick(v)              : 대표 캐릭터 이동
##  - set_principle(hero, p)   : 고른 동료 한 명의 행동 원칙 (AI는 스스로 바꾸지 않음)
##  - submit_sketch(points)    : 그림 → 해석 → 제안 (아직 아무것도 바뀌지 않음)
##  - choose_kind(kind)        : 해석이 애매할 때 학생이 종류를 고름
##  - accept_proposal() / cancel_proposal() : 학생이 승인해야만 건설·필살기가 실행됨
## 말풍선: 실제 전투 데이터에서 '지금 사실인' 것만, 동시에 최대 2개.

const MAX_BUBBLES := 2
const HERO_CD := 10.0
const GLOBAL_CD := 4.0
const SHOW := 2.4

var state: SvState
var bubbles: Array = []
var bubble_log: Array = []
var new_bubbles: Array = []
var commands: Array = []
var proposal: Dictionary = {}  # 학생에게 보여 줄 제안 (비어 있으면 없음)
var last_sketch: Dictionary = {}
var _hero_last: Dictionary = {}
var _global_last := -100.0
var _eval_t := 0.0
var _road_last: Dictionary = {}
var _wish_last: Dictionary = {}
var _recent: Array = []
var _variant: Dictionary = {}
var _retreat_seen: Dictionary = {}


func _init(team: Array) -> void:
	state = SvState.create(team)


func is_over() -> bool:
	return state.outcome != ""


func step() -> Array:
	new_bubbles = []
	if is_over():
		return []
	SvEngine.step(state, SvData.dt())
	for ev in state.events:
		var c: Dictionary = ev.duplicate()
		c["time"] = state.time
		_recent.append(c)
	while not _recent.is_empty() and state.time - float(_recent[0]["time"]) > 6.0:
		_recent.pop_front()
	var keep: Array = []
	for b in bubbles:
		if state.time < float(b["until"]):
			keep.append(b)
	bubbles = keep
	_eval_t -= SvData.dt()
	if _eval_t <= 0.0:
		_eval_t = 0.25
		_speak(triggers())
	for ev in state.events:
		if ev["type"] == "HERO_DOWN":
			var spk := _other_alive(ev["hero"])
			if spk >= 0:
				_speak([{"code": "HERO_DOWN", "hero": spk, "prio": 5,
					"params": {"ally_iga": TextUtil.iga(SvData.person(state.heroes[ev["hero"]].type))}}], true)
	return state.events


# ---------------- 학생 명령 ----------------

func joystick(v: Vector2) -> bool:
	if is_over():
		return false
	SvEngine.set_joystick(state, v)
	return true


func set_principle(hero_id: int, p: String) -> bool:
	if hero_id < 2 or hero_id >= state.heroes.size() or not GameData.principle_order().has(p):
		return false
	var h: SvState.SvHero = state.heroes[hero_id]
	h.principle = p
	commands.append({"t": state.time, "kind": "principle", "hero": hero_id, "principle": p})
	if h.alive():
		_speak([{"code": "PRINCIPLE_ACK", "hero": hero_id, "prio": 6, "params": {"principle": GameData.principle_name(p)}}], true)
	return true


func symbol_owner(kind: String) -> int:
	## 기호 → 필살기를 쓸 동료 (CIRCLE=첫째, TRIANGLE=둘째, ZIGZAG=셋째)
	var i: int = SvData.sec("sketch", "symbols", []).find(kind)
	return 2 + i if i >= 0 and 2 + i < state.heroes.size() else -1


func submit_sketch(points: PackedVector2Array) -> Dictionary:
	last_sketch = SvSketch.analyze(points)
	commands.append({"t": state.time, "kind": "sketch", "shape": last_sketch["kind"]})
	if last_sketch["kind"] == "UNKNOWN":
		proposal = {"ok": false, "reason": last_sketch["reason"], "analysis": last_sketch}
		return proposal
	if last_sketch["ambiguous"]:
		proposal = {"ok": false, "ask": true, "choices": last_sketch["choices"], "reason": last_sketch["reason"], "analysis": last_sketch}
		return proposal
	return _make_proposal(last_sketch["kind"])


func choose_kind(kind: String) -> Dictionary:
	if last_sketch.is_empty():
		return {}
	last_sketch["ambiguous"] = false
	last_sketch["kind"] = kind
	if kind == "LINE" and str(last_sketch.get("shape", "")).ends_with("?"):
		last_sketch["shape"] = "선"
	return _make_proposal(kind)


func _make_proposal(kind: String) -> Dictionary:
	if kind == "LINE":
		proposal = SvPlanner.plan_wall(state, last_sketch["simplified"], str(last_sketch.get("shape", "선")))
	else:
		var hid := symbol_owner(kind)
		if hid < 0:
			proposal = {"ok": false, "reason": "이 모양을 맡은 동료가 없어요"}
		else:
			proposal = SvPlanner.plan_ultimate(state, hid)
	proposal["analysis"] = last_sketch
	proposal["symbol"] = kind
	return proposal


func accept_proposal() -> Dictionary:
	if proposal.is_empty() or not proposal.get("ok", false):
		return {}
	var out := {}
	if proposal["kind"] == "WALL":
		var wid := SvEngine.build_wall(state, proposal["cells"])
		if wid >= 0:
			out = {"kind": "WALL", "wall": wid}
	elif proposal["kind"] == "ULT":
		out = SvEngine.cast_ultimate(state, proposal["hero"], proposal["pos"])
	commands.append({"t": state.time, "kind": "accept", "what": proposal.get("kind", ""), "done": not out.is_empty()})
	proposal = {}
	return out


func cancel_proposal() -> void:
	if not proposal.is_empty():
		commands.append({"t": state.time, "kind": "cancel", "what": proposal.get("kind", "")})
	proposal = {}


# ---------------- 전황 관찰 → 말풍선 ----------------

func triggers(pure := false) -> Array:
	## pure=true: 반복 제한 없이 '지금 사실인 조건'만 (검증용, 상태를 바꾸지 않음)
	var out: Array = []
	var s := state
	var base := SvData.base_center()
	var base_r := float(SvData.cfg["map"].get("base_attack_radius", 3.3))
	var near_base := 0
	for e in s.enemies:
		if e.alive and e.pos.distance_to(base) <= base_r + 2.0:
			near_base += 1
	if near_base >= 2:
		out.append({"code": "BASE_THREAT", "hero": _nearest_hero(base), "prio": 5, "params": {"n": near_base}})
	# 구간(윗길·가운데 길·아랫길)별 적 수
	var by_road: Dictionary = {}
	for e in s.enemies:
		if e.alive:
			var rid := str(SvData.zone_at(e.pos).get("id", ""))
			if rid != "":
				by_road[rid] = int(by_road.get(rid, 0)) + 1
	for rid in by_road.keys():
		var rn: String = SvData.zone(rid)["name"]
		var speaker := _zone_hero(rid)
		if int(by_road[rid]) >= 8 and (pure or s.time - float(_road_last.get(rid, -100.0)) > 20.0):
			out.append({"code": "SIDE_RUSH", "hero": speaker, "prio": 4, "params": {"road": rn, "road_id": rid}})
		var walled := false
		for c in s.grid.walls.keys():
			if str(SvData.zone_at(s.grid.center_of(c)).get("id", "")) == rid:
				walled = true
		if int(by_road[rid]) >= 10 and not walled and s.energy >= int(SvData.sec("build", "min_cells", 3)) \
				and (pure or s.time - float(_wish_last.get(rid, -100.0)) > 30.0):
			out.append({"code": "WALL_WISH", "hero": speaker, "prio": 3, "params": {"road": rn, "road_id": rid}})
	# 빠른 적이 아무도 막지 않은 채 마을 근처
	for e in s.enemies:
		if e.alive and e.type == "FAST" and e.pos.distance_to(base) <= 8.0:
			var guarded := false
			for h in s.heroes:
				if h.alive() and h.pos.distance_to(e.pos) <= SvAI.hero_range(h) + 1.0:
					guarded = true
			if not guarded:
				out.append({"code": "FAST_SLIPPING", "hero": _nearest_hero(e.pos), "prio": 4, "params": {}})
				break
	for h in s.heroes:
		if h.alive() and h.hp < h.max_hp * 0.35:
			var spk := _other_alive(h.id)
			if spk >= 0:
				out.append({"code": "ALLY_DANGER", "hero": spk, "prio": 4,
					"params": {"ally_iga": TextUtil.iga(SvData.person(h.type))}})
		if h.role == "companion" and h.status == "후퇴 중" and (pure or not _retreat_seen.get(h.id, false)):
			out.append({"code": "SELF_LOW", "hero": h.id, "prio": 3, "params": {}})
	if not pure:
		for h in s.heroes:
			_retreat_seen[h.id] = h.status == "후퇴 중"
	for ev in _recent:
		if ev["type"] == "SPAWN" and (ev["enemy_type"] == "ARMORED" or ev["enemy_type"] == "BOSS") and s.time - float(ev["time"]) <= 2.0:
			out.append({"code": "STRONG_COMING", "hero": _zone_hero("Z1"), "prio": 3, "params": {}})
			break
	for ev in _recent:
		if ev["type"] == "WALL_HIT" and s.time - float(ev["time"]) <= 1.0:
			out.append({"code": "WALL_HIT", "hero": s.builder().id, "prio": 3, "params": {}})
			break
	var kills_by: Dictionary = {}
	for ev in _recent:
		if ev["type"] == "KILL" and s.time - float(ev["time"]) <= 0.5 and int(ev["hero"]) >= 0:
			kills_by[ev["hero"]] = int(kills_by.get(ev["hero"], 0)) + 1
	for hid in kills_by.keys():
		if int(kills_by[hid]) >= 2:
			out.append({"code": "MULTI_KILL", "hero": hid, "prio": 1, "params": {}})
	return out


func _speak(cands: Array, force := false) -> void:
	var now := state.time
	cands.sort_custom(func(a, b): return int(a["prio"]) > int(b["prio"]))
	for t in cands:
		if bubbles.size() >= MAX_BUBBLES:
			return
		var hid: int = t["hero"]
		if hid < 0 or not state.heroes[hid].alive():
			continue
		var busy := false
		for b in bubbles:
			if int(b["hero"]) == hid or b["code"] == t["code"]:
				busy = true
		if busy:
			continue
		if not force and (now - _global_last < GLOBAL_CD or now - float(_hero_last.get(hid, -100.0)) < HERO_CD):
			continue
		var variants: Array = SvData.speech_text(t["code"])
		if variants.is_empty():
			continue
		var vi := int(_variant.get(t["code"], 0))
		_variant[t["code"]] = vi + 1
		var b := {"hero": hid, "code": t["code"], "text": TextUtil.fill(str(variants[vi % variants.size()]), t["params"]),
			"prio": t["prio"], "start": now, "until": now + SHOW}
		bubbles.append(b)
		new_bubbles.append(b)
		bubble_log.append(b)
		_hero_last[hid] = now
		_global_last = now
		if t["code"] == "SIDE_RUSH":
			_road_last[t["params"]["road_id"]] = now
		elif t["code"] == "WALL_WISH":
			_wish_last[t["params"]["road_id"]] = now


func _zone_hero(road_id: String) -> int:
	for h in state.heroes:
		if h.role == "companion" and h.zone == road_id and h.alive():
			return h.id
	return _nearest_hero(SvData.zone_guard(road_id))


func _nearest_hero(p: Vector2) -> int:
	var best := -1
	var bd := INF
	for h in state.heroes:
		if h.alive() and h.pos.distance_to(p) < bd:
			bd = h.pos.distance_to(p)
			best = h.id
	return best


func _other_alive(not_id: int) -> int:
	for h in state.heroes:
		if h.id != not_id and h.alive() and h.role == "companion":
			return h.id
	for h in state.heroes:
		if h.id != not_id and h.alive():
			return h.id
	return -1


func summary() -> Dictionary:
	var hs: Array = []
	for h in state.heroes:
		hs.append({"type": h.type, "role": h.role, "kills": h.kills, "damage": h.damage_dealt, "downs": h.downs, "principle": h.principle})
	var counts := {"principle": 0, "sketch": 0, "accept": 0, "cancel": 0}
	for c in commands:
		if counts.has(c["kind"]):
			counts[c["kind"]] += 1
	return {"outcome": state.outcome, "time": state.time, "duration": state.duration,
		"base_hp": state.base_hp, "base_hp_max": state.base_hp_max, "kills": state.kills,
		"walls": state.walls.size(), "energy": state.energy, "heroes": hs, "commands": counts}
