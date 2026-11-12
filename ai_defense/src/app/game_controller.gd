class_name GameController
extends Node
## 체험 한 회차의 진행(대기 → 선택 → 배치 → 전투 → 결과)을 관리하는 유일한 '게임 상태 주인'.
## 두 화면(전투 모니터·터치 화면)은 같은 프로세스 안의 두 창이라 계산은 여기서 한 번만 한다.
## 터치 화면은 command()로 명령만 보내고, 화면은 이 객체의 상태를 읽어 그린다.
##
## 명령은 순서번호(seq)로 중복을 막는다: 같은 번호가 두 번 오면 한 번만 반영하고 ACK만 다시 준다.

signal phase_changed(phase: String)
signal battle_events(events: Array)
signal bubble_shown(bubble: Dictionary)
signal suggestion_opened(suggestion: Dictionary)
signal suggestion_closed(record: Dictionary)
signal command_acked(ack: Dictionary)

const ATTRACT := "attract"
const SELECT := "select"
const PLACE := "place"
const BATTLE := "battle"
const RESULT := "result"

var phase := ATTRACT
var selected: Array = []  # 고른 캐릭터 종류 (고른 순서)
var team: Array = []  # [{type, slot, principle}]
var place_cursor := 0
var session: BattleSession = null
var result: Dictionary = {}
var state_version := 0
var last_seq := 0
var idle_time := 0.0
var phase_time := 0.0
var suggest_elapsed := 0.0
var accumulator := 0.0
var end_delay := -1.0
var show_fps := false
var games_played := 0
var last_bubble_text := ""
var last_bubble_hero := -1
var _seed_counter := 1


func _ready() -> void:
	GameData.ensure_loaded()
	process_mode = Node.PROCESS_MODE_ALWAYS


# ---------------- 명령 ----------------

func command(name: String, args: Dictionary = {}, seq: int = -1) -> Dictionary:
	if seq >= 0:
		if seq <= last_seq:
			var dup := {"seq": seq, "ok": false, "duplicate": true, "version": state_version, "command": name}
			command_acked.emit(dup)
			return dup
		last_seq = seq
	idle_time = 0.0
	var ok := _apply(name, args)
	if ok:
		state_version += 1
	var ack := {"seq": seq, "ok": ok, "duplicate": false, "version": state_version, "command": name}
	command_acked.emit(ack)
	return ack


func _apply(name: String, a: Dictionary) -> bool:
	match name:
		"start":
			if phase != ATTRACT:
				return false
			selected.clear()
			team.clear()
			_set_phase(SELECT)
			return true
		"toggle_hero":
			if phase != SELECT:
				return false
			var t: String = a.get("type", "")
			if not GameData.heroes.has(t):
				return false
			if selected.has(t):
				selected.erase(t)
			elif selected.size() < 3:
				selected.append(t)
			else:
				return false
			return true
		"confirm_hero":
			# 터치 화면 상세 패널에서 '이 캐릭터로 확정' → 위 모니터에 초상화가 뜸
			if phase != SELECT:
				return false
			var ct: String = a.get("type", "")
			if not GameData.heroes.has(ct) or selected.has(ct) or selected.size() >= 3:
				return false
			selected.append(ct)
			return true
		"unconfirm_hero":
			if phase != SELECT:
				return false
			var ut: String = a.get("type", "")
			if not selected.has(ut):
				return false
			selected.erase(ut)
			return true
		"recommended":
			if phase != SELECT:
				return false
			selected.clear()
			team.clear()
			for r in GameData.config.get("recommended_team", []):
				selected.append(r["type"])
				team.append({"type": r["type"], "slot": int(r["slot"]), "principle": _default_principle()})
			place_cursor = 0
			_set_phase(PLACE)
			return true
		"to_place":
			if phase != SELECT or selected.size() != 3:
				return false
			var old := team.duplicate(true)
			team.clear()
			for t in selected:
				var slot := -1
				var pr := _default_principle()
				for o in old:
					if o["type"] == t:
						slot = o["slot"]
						pr = o["principle"]
				team.append({"type": t, "slot": slot, "principle": pr})
			place_cursor = _first_unplaced()
			_set_phase(PLACE)
			return true
		"back":
			if phase == PLACE:
				_set_phase(SELECT)
				return true
			if phase == SELECT:
				_set_phase(ATTRACT)
				return true
			return false
		"pick_member":
			if phase != PLACE:
				return false
			var i := int(a.get("index", -1))
			if i < 0 or i >= team.size():
				return false
			place_cursor = i
			return true
		"place_slot":
			if phase != PLACE or place_cursor < 0 or place_cursor >= team.size():
				return false
			var slot := int(a.get("slot", -1))
			if slot < 0 or slot >= GameData.slots.size():
				return false
			for j in team.size():
				if j != place_cursor and team[j]["slot"] == slot:
					team[j]["slot"] = team[place_cursor]["slot"]  # 자리 맞바꾸기 (비어 있었다면 빠짐)
			team[place_cursor]["slot"] = slot
			var nxt := _first_unplaced()
			if nxt >= 0:
				place_cursor = nxt
			return true
		"set_principle":
			if phase != PLACE:
				return false
			var i := int(a.get("index", -1))
			var p: String = a.get("principle", "")
			if i < 0 or i >= team.size() or not GameData.principle_order().has(p):
				return false
			team[i]["principle"] = p
			return true
		"battle_start":
			if phase != PLACE or _first_unplaced() >= 0:
				return false
			_start_battle()
			return true
		"suggest_accept", "suggest_keep", "suggest_other":
			if phase != BATTLE or session == null or not session.is_paused():
				return false
			var choice: String = {"suggest_accept": "accept", "suggest_keep": "keep", "suggest_other": "other"}[name]
			return _resolve(choice, a.get("principle", ""))
		"next_student", "teacher_reset":
			reset_to_attract()
			return true
		"teacher_test_suggest":
			if phase != BATTLE or session == null:
				return false
			session.force_test_suggestion()
			if session.is_paused():
				suggest_elapsed = 0.0
				suggestion_opened.emit(session.active)
				return true
			return false
		"teacher_toggle_fps":
			show_fps = not show_fps
			return true
	return false


func _default_principle() -> String:
	return str(GameData.config.get("default_principle", "NEAREST"))


func _first_unplaced() -> int:
	for i in team.size():
		if int(team[i]["slot"]) < 0:
			return i
	return -1


func _set_phase(p: String) -> void:
	phase = p
	phase_time = 0.0
	idle_time = 0.0
	phase_changed.emit(p)


func reset_to_attract() -> void:
	## 이전 학생의 선택이 다음 게임에 남지 않도록 모두 지운다
	session = null
	result = {}
	selected.clear()
	team.clear()
	place_cursor = 0
	accumulator = 0.0
	end_delay = -1.0
	last_bubble_text = ""
	last_bubble_hero = -1
	_set_phase(ATTRACT)


func _start_battle() -> void:
	_seed_counter += 1
	session = BattleSession.new(team.duplicate(true), _seed_counter)
	session.start()
	accumulator = 0.0
	end_delay = -1.0
	last_bubble_text = ""
	_set_phase(BATTLE)
	battle_events.emit(session.state.events)


func _resolve(choice: String, principle: String) -> bool:
	if not session.resolve(choice, principle):
		return false
	suggest_elapsed = 0.0
	suggestion_closed.emit(session.suggestion_log[session.suggestion_log.size() - 1])
	return true


# ---------------- 진행 ----------------

func _process(delta: float) -> void:
	phase_time += delta
	idle_time += delta
	match phase:
		SELECT, PLACE:
			if idle_time >= float(GameData.cfg("timers", "idle_reset_seconds", 75)):
				reset_to_attract()
		RESULT:
			if phase_time >= float(GameData.cfg("timers", "result_auto_reset_seconds", 30)):
				reset_to_attract()
		BATTLE:
			_process_battle(delta)


func _process_battle(delta: float) -> void:
	if session == null:
		return
	if session.is_over():
		if end_delay < 0.0:
			end_delay = 0.0
		end_delay += delta
		if end_delay >= 1.6:
			_finish()
		return
	if session.is_paused():
		suggest_elapsed += delta
		if suggest_elapsed >= float(GameData.cfg("suggestion", "timeout_seconds", 30)):
			_resolve("timeout", "")  # 고르지 않으면 지금 원칙 유지
		return
	var dt := GameData.dt()
	accumulator = minf(accumulator + delta, dt * 5.0)  # 느려져도 한 번에 너무 많이 돌지 않게
	while accumulator >= dt:
		accumulator -= dt
		var events := session.step()
		if not events.is_empty():
			battle_events.emit(events)
		if not session.new_bubble.is_empty():
			last_bubble_text = session.new_bubble["text"]
			last_bubble_hero = session.new_bubble["hero"]
			bubble_shown.emit(session.new_bubble)
		if session.is_paused():
			suggest_elapsed = 0.0
			accumulator = 0.0
			suggestion_opened.emit(session.active)
			break
		if session.is_over():
			break


func _finish() -> void:
	result = session.summary()
	games_played += 1
	_set_phase(RESULT)


func interpolation_alpha() -> float:
	if session == null or session.is_paused() or session.is_over():
		return 1.0
	return clampf(accumulator / GameData.dt(), 0.0, 1.0)


func suggestion_time_left() -> float:
	return maxf(0.0, float(GameData.cfg("suggestion", "timeout_seconds", 30)) - suggest_elapsed)


func result_time_left() -> float:
	return maxf(0.0, float(GameData.cfg("timers", "result_auto_reset_seconds", 30)) - phase_time)


func note_activity() -> void:
	idle_time = 0.0
