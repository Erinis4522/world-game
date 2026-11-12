class_name SvSession
extends RefCounted
## 3D 서바이벌 한 판 = SvState + 전황 관찰 + 말풍선 + 학생 명령.
## 화면(Node)과 독립이라 실제 게임·자동 테스트·밸런스 도구가 같이 쓴다.
##
## 말풍선 규칙: 실제 전투 데이터에서 '지금 사실인' 것만, 동시에 최대 2개,
## 캐릭터별 10초·전체 4초 간격, 2.4초 표시. 전투는 멈추지 않는다.

const MAX_BUBBLES := 2
const HERO_CD := 10.0
const GLOBAL_CD := 4.0
const SHOW := 2.4

var state: SvState
var bubbles: Array = []  # [{hero, code, text, until, prio}]
var bubble_log: Array = []
var new_bubbles: Array = []
var commands: Array = []  # 학생이 내린 명령 기록 (결과 화면용)
var _hero_last: Dictionary = {}
var _global_last := -100.0
var _eval_t := 0.0
var _gate_last: Dictionary = {}
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
	# 이벤트 기반 즉시 보고 (쓰러짐)
	for ev in state.events:
		if ev["type"] == "HERO_DOWN":
			var spk := _other_alive(ev["hero"])
			if spk >= 0:
				var who := GameData.person(state.heroes[ev["hero"]].type)
				_speak([{"code": "HERO_DOWN", "hero": spk, "prio": 5, "params": {"ally_iga": TextUtil.iga(who)}}], true)
	return state.events


# ---------------- 학생 명령 ----------------

func move_player(target: Vector2) -> bool:
	if is_over() or not state.player().alive():
		return false
	var ok := SvEngine.command_move(state, 0, target)
	if ok:
		commands.append({"t": state.time, "kind": "move"})
	return ok


func set_tactic(hero_id: int, tactic: String) -> bool:
	## 동료 한 명의 전술만 바뀐다. 대표 캐릭터(학생이 조종)는 전술 대상이 아니다.
	if hero_id <= 0 or hero_id >= state.heroes.size() or not SvData.tactic_order().has(tactic):
		return false
	var h: SvState.SvHero = state.heroes[hero_id]
	h.tactic = tactic
	h.focus_id = -1
	h.think_t = 0.0  # 바로 다시 판단
	commands.append({"t": state.time, "kind": "tactic", "hero": hero_id, "tactic": tactic})
	if h.alive():
		_speak([{"code": "TACTIC_ACK", "hero": hero_id, "prio": 6, "params": {"tactic": SvData.tactic_name(tactic)}}], true)
	return true


# ---------------- 전황 관찰 → 말풍선 ----------------

func triggers(pure := false) -> Array:
	## pure=true: 말풍선 반복 제한 없이 '지금 사실인 조건'만 (테스트·검증용, 상태를 바꾸지 않음)
	var out: Array = []
	var s := state
	var base := SvData.base_center()
	var base_r := float(SvData.cfg["map"].get("base_attack_radius", 2.3))
	# 기지 주변 위협
	var near_base := 0
	for e in s.enemies:
		if e.alive and e.pos.distance_to(base) <= base_r + 1.0:
			near_base += 1
	if near_base >= 2:
		out.append({"code": "BASE_THREAT", "hero": _nearest_hero(base), "prio": 5, "params": {"n": near_base}})
	# 한쪽 게이트에서 몰려옴
	var by_gate: Dictionary = {}
	for e in s.enemies:
		if e.alive and s.time - e.spawn_time <= 8.0:
			by_gate[e.gate] = int(by_gate.get(e.gate, 0)) + 1
	for gid in by_gate.keys():
		if int(by_gate[gid]) >= 4 and (pure or s.time - float(_gate_last.get(gid, -100.0)) > 20.0):
			var g := SvData.gate(gid)
			out.append({"code": "SIDE_RUSH", "hero": _nearest_hero(Vector2(float(g["pos"][0]), float(g["pos"][1]))), "prio": 4,
				"params": {"dir": g.get("dir", gid), "gate": gid}})
	# 빠른 적이 아무도 막지 않은 채 기지 근처
	for e in s.enemies:
		if e.alive and e.type == "FAST" and e.pos.distance_to(base) <= 5.0:
			var guarded := false
			for h in s.heroes:
				if h.alive() and h.pos.distance_to(e.pos) <= SvAI.hero_range(h) + 1.0:
					guarded = true
			if not guarded:
				out.append({"code": "FAST_SLIPPING", "hero": _nearest_hero(e.pos), "prio": 4, "params": {}})
				break
	# 동료 위험 / 내 체력 낮음
	for h in s.heroes:
		if h.alive() and h.hp < h.max_hp * 0.35:
			var spk := _other_alive(h.id)
			if spk >= 0:
				out.append({"code": "ALLY_DANGER", "hero": spk, "prio": 4,
					"params": {"ally_iga": TextUtil.iga(GameData.person(h.type))}})
		if not h.is_player and h.status == "후퇴 중" and (pure or not _retreat_seen.get(h.id, false)):
			out.append({"code": "SELF_LOW", "hero": h.id, "prio": 3, "params": {}})
	if not pure:
		for h in s.heroes:
			_retreat_seen[h.id] = h.status == "후퇴 중"
	# 강한 적 등장
	for ev in _recent:
		if ev["type"] == "SPAWN" and (ev["enemy_type"] == "ARMORED" or ev["enemy_type"] == "BOSS") and s.time - float(ev["time"]) <= 2.0:
			out.append({"code": "STRONG_COMING", "hero": _nearest_hero(base), "prio": 3, "params": {}})
			break
	# 한 번에 여러 마리 처치
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
		if not force:
			if now - _global_last < GLOBAL_CD or now - float(_hero_last.get(hid, -100.0)) < HERO_CD:
				continue
		var variants: Array = SvData.speech_text(t["code"])
		if variants.is_empty():
			continue
		var vi := int(_variant.get(t["code"], 0))
		_variant[t["code"]] = vi + 1
		var text := TextUtil.fill(str(variants[vi % variants.size()]), t["params"])
		var b := {"hero": hid, "code": t["code"], "text": text, "prio": t["prio"], "start": now, "until": now + SHOW}
		bubbles.append(b)
		new_bubbles.append(b)
		bubble_log.append(b)
		_hero_last[hid] = now
		_global_last = now
		if t["code"] == "SIDE_RUSH":
			_gate_last[t["params"]["gate"]] = now


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
		if h.id != not_id and h.alive() and not h.is_player:
			return h.id
	for h in state.heroes:
		if h.id != not_id and h.alive():
			return h.id
	return -1


func summary() -> Dictionary:
	var hs: Array = []
	for h in state.heroes:
		hs.append({"type": h.type, "player": h.is_player, "kills": h.kills, "damage": h.damage_dealt,
			"downs": h.downs, "tactic": h.tactic})
	var tactic_changes := 0
	var moves := 0
	for c in commands:
		if c["kind"] == "tactic":
			tactic_changes += 1
		else:
			moves += 1
	return {"outcome": state.outcome, "time": state.time, "duration": state.duration,
		"base_hp": state.base_hp, "base_hp_max": state.base_hp_max, "kills": state.kills,
		"xp": state.xp, "energy": state.energy, "heroes": hs, "moves": moves, "tactic_changes": tactic_changes}
