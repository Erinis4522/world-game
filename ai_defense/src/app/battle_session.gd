class_name BattleSession
extends RefCounted
## 전투 한 판 = GameState + 관찰기 + 말풍선 + 특별 제안 2회 규칙.
## 화면(Node)과 독립이라 실제 게임과 테스트·밸런스 도구가 똑같이 사용한다.
##
## 특별 제안 규칙
##  - 'crisis'    : 첫 방어선 위기 (게임당 최대 1회)
##  - 'first_hit' : 본진 최초 피격 (게임당 최대 1회, 실제로 HP가 줄었을 때만)
##  - 앞 제안이 끝난 뒤 전투 시간으로 최소 18초 간격. 그 전에 생기면 보관했다가 간격 후 제안.
##  - 게임이 끝나면 보관된 제안은 취소된다.
##  - 제안이 열려 있는 동안 전투는 멈춘다. 학생이 고르기 전에는 아무 원칙도 바뀌지 않는다.

var state: GameState
var observer := CombatObserver.new()
var speech := SpeechScheduler.new()
var crisis_fired := false
var hit_fired := false
var crisis_time := -1.0
var first_hit_time := -1.0
var pending: Array = []  # [{kind, info, time}]
var active: Dictionary = {}  # 열려 있는 제안 (비어 있으면 없음)
var suggestion_log: Array = []  # 결정 기록
var cancelled: Array = []
var last_suggestion_end := -1000.0
var new_bubble: Dictionary = {}  # 이번 틱에 새로 뜬 말풍선
var initial_principles: Array = []
var snapshots: Array = []  # 약 1초마다 저장한 상태 복사본 (다시 계산용, 최근 것만 보관)
var _last_snapshot_time := -100.0


func _init(team: Array, seed_value: int = 12345) -> void:
	GameData.ensure_loaded()
	state = GameState.create(team, seed_value)
	for h in state.heroes:
		initial_principles.append(h.principle)


func start() -> void:
	GameEngine.start_battle(state)
	observer.observe(state, true)


func is_paused() -> bool:
	return not active.is_empty()


func is_over() -> bool:
	return state.outcome != ""


func step() -> Array:
	## 한 틱 진행. 제안이 열려 있거나 끝났으면 아무것도 하지 않는다.
	new_bubble = {}
	if is_paused() or is_over():
		return []
	_store_snapshot()
	GameEngine.step(state, GameData.dt())
	observer.observe(state)
	if observer.fresh:
		new_bubble = speech.update(state, observer)
	elif not speech.current.is_empty() and state.time >= float(speech.current["until"]):
		speech.clear()
	_detect_events()
	if is_over():
		for p in pending:
			cancelled.append(p)
		pending.clear()
		speech.clear()
	else:
		_maybe_open()
	return state.events


func _detect_events() -> void:
	if not crisis_fired:
		var c := CrisisDetection.check(state)
		if not c.is_empty():
			crisis_fired = true
			crisis_time = state.time
			pending.append({"kind": "crisis", "info": c, "time": state.time})
	if not hit_fired:
		for ev in state.events:
			if ev["type"] == "LEAK":
				hit_fired = true
				first_hit_time = state.time
				pending.append({"kind": "first_hit", "info": ev.duplicate(), "time": state.time})
				break


func _maybe_open() -> void:
	if pending.is_empty() or is_paused():
		return
	var gap := float(GameData.cfg("suggestion", "min_gap_seconds", 18.0))
	if state.time - last_suggestion_end < gap:
		return
	var p: Dictionary = pending.pop_front()
	open_suggestion(p["kind"], p["info"])


func open_suggestion(kind: String, info: Dictionary) -> void:
	speech.clear()
	active = Recommendation.analyze(state, observer, kind, info, suggestion_log, replay_snapshot())


func resolve(choice: String, principle: String = "") -> bool:
	## choice: accept / keep / other(principle) / timeout
	## 제안한 그 캐릭터 한 명의 원칙만 바뀐다.
	if active.is_empty():
		return false
	var h: Entities.Hero = state.heroes[active["hero_id"]]
	var before := h.principle
	match choice:
		"accept":
			if not active["has_change"]:
				return false
			h.principle = active["to"]
		"other":
			if not GameData.principle_order().has(principle):
				return false
			h.principle = principle
		"keep", "timeout":
			pass
		_:
			return false
	suggestion_log.append({
		"kind": active["kind"], "hero_id": h.id, "hero_type": h.type,
		"from": before, "to": active["to"], "has_change": active["has_change"],
		"choice": choice, "final": h.principle, "time": state.time,
	})
	last_suggestion_end = state.time
	active = {}
	return true


func force_test_suggestion() -> void:
	## 교사 메뉴의 테스트용. 게임당 1·2회 제안 기록에는 넣지 않는다.
	if is_paused() or is_over():
		return
	open_suggestion("test", {})


func summary() -> Dictionary:
	var finals: Array = []
	for h in state.heroes:
		finals.append({"type": h.type, "principle": h.principle, "kills": h.kills, "damage": h.damage_dealt})
	var sc: Dictionary = GameData.config.get("score", {})
	var score := int(state.time * float(sc.get("per_second", 10))) + state.base_hp * int(sc.get("per_hp", 50)) \
		+ state.kills * int(sc.get("per_kill", 5)) + (int(sc.get("win_bonus", 300)) if state.outcome == "win" else 0)
	return {
		"outcome": state.outcome, "time": state.time, "wave": state.wave_index, "hp": state.base_hp,
		"hp_max": state.base_hp_max, "kills": state.kills, "leaked": state.leaked,
		"heroes": finals, "initial": initial_principles, "decisions": suggestion_log.duplicate(true),
		"score": score,
	}


func _store_snapshot() -> void:
	if state.time - _last_snapshot_time < 1.0 - 0.0001:
		return
	_last_snapshot_time = state.time
	snapshots.append(state.clone())
	var keep := int(GameData.cfg("suggestion", "replay_seconds", 12)) + 3
	while snapshots.size() > keep:
		snapshots.pop_front()


func replay_snapshot() -> GameState:
	## 지금으로부터 replay_seconds초 전에 가장 가까운(그보다 최근인) 저장 상태
	var want := state.time - float(GameData.cfg("suggestion", "replay_seconds", 12))
	for s in snapshots:
		if s.time >= want - 0.0001:
			return s
	return null
