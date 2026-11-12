class_name CombatObserver
extends RefCounted
## 전투를 지켜보며 '실제로 일어난 일'만 기록한다.
##  - triggers : 지금 이 순간 사실인 말풍선 후보 (캐릭터별)
##  - history  : 지금까지 관찰된 현상 누적 (특별 제안의 근거로 재사용)
## 판단에 필요한 값은 모두 GameState와 엔진 이벤트에서 계산한다. 지어낸 관찰은 없다.

var recent: Array = []  # 최근 이벤트 (time 필드 추가됨)
var triggers: Array = []  # [{code, hero, prio, params}]
var history: Dictionary = {}  # code -> {count, first, last, params}
var hero_passed: Dictionary = {}  # hero id -> 사거리를 살아서 빠져나간 적 수
var hero_passed_fast: Dictionary = {}  # hero id -> 그중 빠른 적 수
var _last_eval := -100.0
var _tough_logged: Dictionary = {}
var _passed_ids: Dictionary = {}
var _cond_last: Dictionary = {}
var fresh := false  # 이번 틱에 후보를 새로 계산했는가

const KEEP_SECONDS := 2.5


func observe(state: GameState, force_eval := false) -> void:
	var now := state.time
	for ev in state.events:
		var c: Dictionary = ev.duplicate()
		c["time"] = now
		recent.append(c)
		_record_event(state, c)
	while not recent.is_empty() and now - float(recent[0]["time"]) > KEEP_SECONDS:
		recent.pop_front()
	var interval := float(GameData.cfg("speech", "eval_interval", 0.25))
	fresh = false
	if force_eval or now - _last_eval >= interval - 0.0001:
		fresh = true
		_last_eval = now
		triggers = compute_triggers(state)
		_record_conditions(state)


func _record_event(state: GameState, ev: Dictionary) -> void:
	match ev["type"]:
		"PASSED":
			var hid: int = ev["hero"]
			hero_passed[hid] = int(hero_passed.get(hid, 0)) + 1
			if ev["enemy_type"] == "FAST":
				hero_passed_fast[hid] = int(hero_passed_fast.get(hid, 0)) + 1
			# 전장 전체 기록은 '서로 다른 적' 기준으로 센다 (한 적이 여러 사거리를 지나도 1번)
			if _passed_ids.has(ev["enemy"]):
				return
			_passed_ids[ev["enemy"]] = true
			if ev["enemy_type"] == "FAST":
				_bump("FAST_PASSED", ev["time"], {"hero": hid})
			else:
				_bump("ENEMY_PASSED", ev["time"], {"hero": hid})
		"LEAK":
			_bump("LEAK", ev["time"], {"enemy_type": ev["enemy_type"]})
		"KILL":
			if ev["enemy_type"] == "ARMORED" or ev["enemy_type"] == "BOSS":
				_bump("TOUGH_DOWN", ev["time"], {"hero": ev["hero"]})


func _bump(code: String, t: float, params: Dictionary) -> void:
	var h: Dictionary = history.get(code, {"count": 0, "first": t, "last": t, "params": {}})
	h["count"] = int(h["count"]) + 1
	h["last"] = t
	h["params"] = params
	history[code] = h


func _record_episode(code: String, t: float, params: Dictionary) -> void:
	## 상태형 조건은 '연속된 한 번'을 1회로 센다
	var last := float(_cond_last.get(code, -100.0))
	_cond_last[code] = t
	if t - last > 1.0:
		_bump(code, t, params)
	else:
		var h: Dictionary = history[code]
		h["last"] = t


func _record_conditions(state: GameState) -> void:
	var now := state.time
	# 적 밀집 (어느 캐릭터든 상관없이 전장 관찰)
	for e in state.enemies:
		if e.alive and Specialty.count_near(state, e.pos, 1.2) >= 4:
			_record_episode("CROWD", now, {})
			break
	# 단단한 적이 공격받으며 3초 이상 버팀
	for e in state.enemies:
		if e.alive and (e.type == "ARMORED" or e.type == "BOSS") and e.first_hit_time >= 0.0 \
				and now - e.first_hit_time >= 3.0 and not _tough_logged.has(e.id):
			_tough_logged[e.id] = true
			_bump("ARMORED_SURVIVED", now, {"enemy_type": e.type})
	for t in triggers:
		if t["code"] == "FAST_INCOMING":
			_record_episode("FAST_INCOMING", now, t["params"])


func recent_events(state: GameState, type: String, window: float = -1.0) -> Array:
	if window < 0.0:
		window = float(GameData.cfg("speech", "recent_window", 1.0))
	var out: Array = []
	for ev in recent:
		if ev["type"] == type and state.time - float(ev["time"]) <= window + 0.0001:
			out.append(ev)
	return out


func compute_triggers(state: GameState) -> Array:
	var out: Array = []
	if state.heroes.is_empty():
		return out
	var now := state.time
	var base_pos := GameData.path.end_point()
	# 본진 피격 (최근 1초 안 실제 LEAK)
	var leaks := recent_events(state, "LEAK")
	if not leaks.is_empty():
		var last_leak: Dictionary = leaks[leaks.size() - 1]
		out.append({"code": "BASE_HIT", "hero": _nearest_hero(state, base_pos), "prio": 5,
			"params": {"hp": state.base_hp, "hp_before": last_leak["hp_before"]}})
	# 본진 직전 위기
	var front: Entities.Enemy = null
	for e in state.enemies:
		if e.alive and (front == null or e.dist > front.dist):
			front = e
	if front != null and state.progress(front) >= float(GameData.cfg("speech", "base_danger_progress", 0.85)):
		out.append({"code": "BASE_DANGER", "hero": _nearest_hero(state, front.pos), "prio": 5,
			"params": {"enemy_iga": TextUtil.iga(GameData.enemy(front.type)["name"])}})
	# 사거리 돌파
	for ev in recent_events(state, "PASSED"):
		var code := "FAST_PASSED" if ev["enemy_type"] == "FAST" else "ENEMY_PASSED"
		if code == "FAST_PASSED" and state.heroes[ev["hero"]].type != "ARCHER":
			code = "ENEMY_PASSED"  # '빠른 적을 놓쳤어'는 궁수 대사, 다른 캐릭터는 일반 돌파 대사
		out.append({"code": code, "hero": ev["hero"], "prio": 4,
			"params": {"enemy": GameData.enemy(ev["enemy_type"])["name"]}})
	# 보스 등장
	for ev in recent_events(state, "SPAWN", 2.0):
		if ev["enemy_type"] == "BOSS":
			out.append({"code": "BOSS_APPEAR", "hero": _nearest_hero(state, GameData.path.pos_at(0.0)), "prio": 3, "params": {}})
	# 캐릭터별 관찰
	for h in state.heroes:
		var d: Dictionary = GameData.hero(h.type)
		var rng := float(d["range"])
		match h.type:
			"SWORD":
				var n := 0
				for e in state.enemies:
					if e.alive and h.pos.distance_to(e.pos) <= rng + 0.5:
						n += 1
				if n >= 4:
					out.append({"code": "SWARM", "hero": h.id, "prio": 3, "params": {"n": n}})
			"ICE":
				var nf := 0
				for e in state.enemies:
					if e.alive and e.type == "FAST" and h.pos.distance_to(e.pos) <= rng + 2.0:
						nf += 1
				if nf >= 2:
					out.append({"code": "FAST_INCOMING", "hero": h.id, "prio": 3, "params": {"n": nf}})
			"SNIPER":
				for e in state.enemies:
					if e.alive and (e.type == "ARMORED" or e.type == "BOSS") and e.first_hit_time >= 0.0 \
							and now - e.first_hit_time >= 3.0 and h.pos.distance_to(e.pos) <= rng:
						out.append({"code": "TOUGH", "hero": h.id, "prio": 3,
							"params": {"enemy": GameData.enemy(e.type)["name"]}})
						break
			"LIGHTNING":
				if h.in_range.size() >= 2 and h.last_chain_count == 0 and now - h.last_attack_time <= 1.6:
					out.append({"code": "CHAIN_WEAK", "hero": h.id, "prio": 3, "params": {}})
			"MARK":
				for ev in recent_events(state, "HIT"):
					if ev["marked"] and int(ev["mark_src"]) == h.id and int(ev["hero"]) != h.id and int(ev["hero"]) >= 0:
						out.append({"code": "MARK_COOP", "hero": h.id, "prio": 2,
							"params": {"ally": GameData.hero(state.heroes[ev["hero"]].type)["name"]}})
						break
			"FIRE":
				for e in state.enemies:
					if e.alive and h.pos.distance_to(e.pos) <= rng and Specialty.count_near(state, e.pos, 1.0) >= 3:
						out.append({"code": "CLUSTER", "hero": h.id, "prio": 1, "params": {}})
						break
			"BOMB":
				var br := float(d.get("blast_radius", 1.2))
				for e in state.enemies:
					if e.alive and h.pos.distance_to(e.pos) <= rng and Specialty.count_near(state, e.pos, br) >= 3:
						out.append({"code": "BOMB_CLUSTER", "hero": h.id, "prio": 1, "params": {}})
						break
	# 단단한 적 처치 (긍정 반응)
	for ev in recent_events(state, "KILL"):
		if (ev["enemy_type"] == "ARMORED" or ev["enemy_type"] == "BOSS") and int(ev["hero"]) >= 0:
			out.append({"code": "TOUGH_DOWN", "hero": ev["hero"], "prio": 1,
				"params": {"enemy": GameData.enemy(ev["enemy_type"])["name"]}})
	return out


func has_trigger(code: String, hero_id: int) -> bool:
	for t in triggers:
		if t["code"] == code and int(t["hero"]) == hero_id:
			return true
	return false


func count(code: String) -> int:
	return int(history.get(code, {}).get("count", 0))


func _nearest_hero(state: GameState, p: Vector2) -> int:
	var best := 0
	var bd := INF
	for h in state.heroes:
		var d: float = h.pos.distance_to(p)
		if d < bd:
			bd = d
			best = h.id
	return best
