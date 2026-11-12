class_name SvController
extends Node
## 3D 서바이벌 한 회차: 대기 → 동료 선택 → 작전 개시 → 전투 → 결과. 게임 상태의 유일한 주인.
## 터치 패널은 command()로 명령만 보낸다. 같은 순서번호(seq) 명령은 한 번만 반영한다.
##
## 전투 중 패널 상태(overlay)
##   ""            : 기본 (사각형으로 놓인 초상화 4개 + 가운데 조이스틱)
##   "principle"   : 고른 동료의 원화 + 행동 원칙 (게임이 아주 느려짐)
##   "sketch"      : 건설 동료의 그림 칸 (게임 멈춤)

signal phase_changed(phase: String)
signal battle_events(events: Array)
signal bubbles_shown(bubbles: Array)
signal overlay_changed(overlay: String)

const ATTRACT := "attract"
const SELECT := "select"
const INTRO := "intro"
const BATTLE := "battle"
const RESULT := "result"
const INTRO_SECONDS := 2.6

var phase := ATTRACT
var selected: Array = []
var session: SvSession = null
var result: Dictionary = {}
var state_version := 0
var last_seq := 0
var idle_time := 0.0
var phase_time := 0.0
var accumulator := 0.0
var end_delay := -1.0
var show_fps := false
var overlay := ""
var overlay_hero := -1
var time_scale := 1.0


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
	if ok and name != "joy":  # 조이스틱은 매 프레임 오므로 화면 다시 만들기 대상이 아님
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
			_set_overlay("", -1)
			_set_phase(INTRO)
			return true
		"joy":
			if phase != BATTLE or session == null or overlay == "sketch":
				return false
			return session.joystick(Vector2(float(a.get("x", 0)), float(a.get("y", 0))))
		"open_principle":
			var hid := int(a.get("hero", -1))
			if phase != BATTLE or session == null or hid < 2 or hid >= session.state.heroes.size():
				return false
			session.joystick(Vector2.ZERO)
			_set_overlay("principle", hid)
			return true
		"set_principle":
			if phase != BATTLE or session == null:
				return false
			var ok := session.set_principle(int(a.get("hero", -1)), str(a.get("principle", "")))
			if ok:
				_set_overlay("", -1)
			return ok
		"close_overlay":
			if overlay == "":
				return false
			if session != null:
				session.cancel_proposal()
			_set_overlay("", -1)
			return true
		"open_sketch":
			if phase != BATTLE or session == null:
				return false
			session.joystick(Vector2.ZERO)
			session.cancel_proposal()
			_set_overlay("sketch", 1)
			return true
		"submit_sketch":
			if overlay != "sketch" or session == null:
				return false
			var pts := PackedVector2Array()
			for p in a.get("points", []):
				pts.append(Vector2(float(p[0]), float(p[1])))
			session.submit_sketch(pts)
			return true
		"choose_kind":
			if overlay != "sketch" or session == null:
				return false
			return not session.choose_kind(str(a.get("kind", ""))).is_empty()
		"accept_proposal":
			if overlay != "sketch" or session == null:
				return false
			var res := session.accept_proposal()
			if res.is_empty():
				return false
			_set_overlay("", -1)
			if not session.state.events.is_empty():
				battle_events.emit(session.state.events)
			return true
		"redraw":
			if overlay != "sketch" or session == null:
				return false
			session.cancel_proposal()
			return true
		"next_student", "teacher_reset":
			reset_to_attract()
			return true
		"teacher_toggle_fps":
			show_fps = not show_fps
			return true
	return false


func _set_overlay(o: String, hid: int) -> void:
	overlay = o
	overlay_hero = hid
	match o:
		"principle":
			time_scale = float(SvData.cfg.get("slow_motion_scale", 0.15))
		"sketch":
			time_scale = 0.0
		_:
			time_scale = 1.0
	overlay_changed.emit(o)


func _set_phase(p: String) -> void:
	phase = p
	phase_time = 0.0
	idle_time = 0.0
	phase_changed.emit(p)


func reset_to_attract() -> void:
	session = null
	result = {}
	selected.clear()
	accumulator = 0.0
	end_delay = -1.0
	_set_overlay("", -1)
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
			if overlay != "" and idle_time >= 40.0:
				command("close_overlay")  # 패널을 열어 둔 채 떠나면 원래대로


func _battle(delta: float) -> void:
	if session == null:
		return
	if session.is_over():
		if end_delay < 0.0:
			end_delay = 0.0
			_set_overlay("", -1)
		end_delay += delta
		if end_delay >= 2.0:
			result = session.summary()
			_set_phase(RESULT)
		return
	var dt := SvData.dt()
	accumulator = minf(accumulator + delta * time_scale, dt * 5.0)
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
	if session == null or session.is_over():
		return 1.0
	return clampf(accumulator / SvData.dt(), 0.0, 1.0)


func result_time_left() -> float:
	return maxf(0.0, float(GameData.cfg("timers", "result_auto_reset_seconds", 30)) - phase_time)


func note_activity() -> void:
	idle_time = 0.0
