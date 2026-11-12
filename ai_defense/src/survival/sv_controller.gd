class_name SvController
extends Node
## 3D 서바이벌 한 회차 진행: 대기 → 캐릭터 선택 → 전투 → 결과. 게임 상태의 유일한 주인.
## 터치 화면은 command()로 명령만 보낸다. 같은 순서번호(seq) 명령은 한 번만 반영한다.

signal phase_changed(phase: String)
signal battle_events(events: Array)
signal bubbles_shown(bubbles: Array)

const ATTRACT := "attract"
const SELECT := "select"
const INTRO := "intro"  # 전투 직전 3명 원화 연출 (짧게)
const BATTLE := "battle"
const RESULT := "result"
const INTRO_SECONDS := 2.6

var phase := ATTRACT
var selected: Array = []  # 고른 순서. 첫 번째 = 학생이 직접 움직이는 대표 캐릭터
var session: SvSession = null
var result: Dictionary = {}
var state_version := 0
var last_seq := 0
var idle_time := 0.0
var phase_time := 0.0
var accumulator := 0.0
var end_delay := -1.0
var show_fps := false
var paused := false


func _ready() -> void:
	SvData.ensure_loaded()
	process_mode = Node.PROCESS_MODE_ALWAYS


func command(name: String, args: Dictionary = {}, seq: int = -1) -> Dictionary:
	if seq >= 0:
		if seq <= last_seq:
			return {"seq": seq, "ok": false, "duplicate": true, "version": state_version, "command": name}
		last_seq = seq
	idle_time = 0.0
	var ok := _apply(name, args)
	if ok:
		state_version += 1
	return {"seq": seq, "ok": ok, "duplicate": false, "version": state_version, "command": name}


func _apply(name: String, a: Dictionary) -> bool:
	match name:
		"start":
			if phase != ATTRACT:
				return false
			selected.clear()
			_set_phase(SELECT)
			return true
		"confirm_hero":
			var t: String = a.get("type", "")
			if phase != SELECT or not GameData.heroes.has(t) or selected.has(t) or selected.size() >= 3:
				return false
			selected.append(t)
			return true
		"unconfirm_hero":
			var u: String = a.get("type", "")
			if phase != SELECT or not selected.has(u):
				return false
			selected.erase(u)
			return true
		"recommended":
			if phase != SELECT:
				return false
			selected.clear()
			for r in GameData.config.get("recommended_team", []):
				selected.append(r["type"])
			return true
		"back":
			if phase == SELECT:
				_set_phase(ATTRACT)
				return true
			return false
		"battle_start":
			if phase != SELECT or selected.size() != 3:
				return false
			session = SvSession.new(selected.duplicate())
			accumulator = 0.0
			end_delay = -1.0
			_set_phase(INTRO)
			return true
		"move_to":
			if phase != BATTLE or session == null:
				return false
			return session.move_player(Vector2(float(a.get("x", 0)), float(a.get("y", 0))))
		"set_tactic":
			if phase != BATTLE or session == null:
				return false
			return session.set_tactic(int(a.get("hero", -1)), str(a.get("tactic", "")))
		"next_student", "teacher_reset":
			reset_to_attract()
			return true
		"teacher_toggle_fps":
			show_fps = not show_fps
			return true
	return false


func _set_phase(p: String) -> void:
	phase = p
	phase_time = 0.0
	idle_time = 0.0
	phase_changed.emit(p)


func reset_to_attract() -> void:
	## 이전 학생의 선택·기록이 남지 않게 모두 지운다
	session = null
	result = {}
	selected.clear()
	accumulator = 0.0
	end_delay = -1.0
	_set_phase(ATTRACT)


func _process(delta: float) -> void:
	phase_time += delta
	idle_time += delta
	match phase:
		SELECT:
			if idle_time >= float(GameData.cfg("timers", "idle_reset_seconds", 75)):
				reset_to_attract()
		INTRO:
			if phase_time >= INTRO_SECONDS:
				_set_phase(BATTLE)
		RESULT:
			if phase_time >= float(GameData.cfg("timers", "result_auto_reset_seconds", 30)):
				reset_to_attract()
		BATTLE:
			_battle(delta)


func _battle(delta: float) -> void:
	if session == null:
		return
	if session.is_over():
		if end_delay < 0.0:
			end_delay = 0.0
		end_delay += delta
		if end_delay >= 2.0:
			result = session.summary()
			_set_phase(RESULT)
		return
	if paused:
		return
	var dt := SvData.dt()
	accumulator = minf(accumulator + delta, dt * 5.0)
	while accumulator >= dt:
		accumulator -= dt
		var evs := session.step()
		if not evs.is_empty():
			battle_events.emit(evs)
		if not session.new_bubbles.is_empty():
			bubbles_shown.emit(session.new_bubbles)
		if session.is_over():
			break


func alpha() -> float:
	if session == null or session.is_over() or paused:
		return 1.0
	return clampf(accumulator / SvData.dt(), 0.0, 1.0)


func result_time_left() -> float:
	return maxf(0.0, float(GameData.cfg("timers", "result_auto_reset_seconds", 30)) - phase_time)


func note_activity() -> void:
	idle_time = 0.0
