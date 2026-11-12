class_name SvControlView
extends Control
## 터치 패널 (아래쪽 화면). 3D는 그리지 않고 가벼운 2D 조작 화면만.
##  - 선택: 카드 → 원화 상세(위에서 내려옴) → 확정. 첫 번째 = 내가 조종, 나머지 = AI 동료
##  - 전투: 전술 지도(누르면 이동) + 캐릭터 얼굴(동료 얼굴을 누르면 전술 명령)
## 모든 명령은 controller.command()로만 보낸다.

signal teacher_action(action: String)

var controller: SvController
var _seq := 0
var _built_key := ""
var _root: VBoxContainer
var _focus := ""
var _focus_shown := ""
var _open_hero := -1  # 전술 메뉴를 펼친 동료
var _teacher_open := false
var _teacher_info := ""
var _corner_down := -1.0
var _now := 0.0
var _live: Dictionary = {}  # 매 프레임 갱신할 라벨들

const DETAIL_H := 440.0


func setup(c: SvController) -> void:
	controller = c
	controller.phase_changed.connect(func(_p):
		_focus = ""
		_focus_shown = ""
		_open_hero = -1)


func _ready() -> void:
	theme = UiStyle.build_theme()
	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 18)
	margin.add_child(_root)


func _send(name: String, args: Dictionary = {}) -> Dictionary:
	_seq += 1
	return controller.command(name, args, _seq)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		controller.note_activity()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var corner := Rect2(Vector2(size.x - 110, 0), Vector2(110, 110))
		if event.pressed and corner.has_point(event.position):
			_corner_down = _now
		elif not event.pressed:
			_corner_down = -1.0


func toggle_teacher() -> void:
	_teacher_open = not _teacher_open
	_teacher_info = ""


func show_teacher_info(t: String) -> void:
	_teacher_info = t


func _process(delta: float) -> void:
	_now += delta
	var vr := get_viewport_rect()
	if size != vr.size:
		position = Vector2.ZERO
		size = vr.size
	if _corner_down >= 0.0 and _now - _corner_down >= 2.0:
		_corner_down = -1.0
		toggle_teacher()
	var key := "%s|%d|%s|%d|%s|%s" % [controller.phase, controller.state_version, _focus, _open_hero, str(_teacher_open), _teacher_info]
	if key != _built_key:
		_built_key = key
		_rebuild()
	_update_live()


func _rebuild() -> void:
	for c in _root.get_children():
		_root.remove_child(c)
		c.queue_free()
	_live.clear()
	if _teacher_open:
		_build_teacher()
		return
	match controller.phase:
		SvController.ATTRACT:
			_build_attract()
		SvController.SELECT:
			_build_select()
		SvController.INTRO:
			_root.add_child(_spacer())
			_root.add_child(UiStyle.label("작전 개시! 위 화면을 봐요", 64, UiStyle.C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
			_root.add_child(_spacer())
		SvController.BATTLE:
			_build_battle()
		SvController.RESULT:
			_build_result()


# ---------------- 공통 ----------------

func _spacer(v := true) -> Control:
	var c := Control.new()
	if v:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _hbox(sep := 18) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


func _hcol(t: String) -> Color:
	return Color.from_string(str(GameData.hero(t).get("color", "#888")), Color.GRAY)


# ---------------- 대기 ----------------

func _build_attract() -> void:
	_root.add_child(_spacer())
	_root.add_child(UiStyle.label("AI 디펜스", 96, UiStyle.C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	_root.add_child(UiStyle.label("캐릭터 3명을 골라요. 첫 번째 캐릭터는 내가 직접 움직이고, 두 명은 AI 동료가 스스로 싸워요.", 34, UiStyle.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var row := _hbox()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var b := UiStyle.button("시작", 520, 150, 64)
	b.pressed.connect(func(): _send("start"))
	row.add_child(b)
	_root.add_child(row)
	_root.add_child(_spacer())


# ---------------- 선택 ----------------

func _build_select() -> void:
	var n := controller.selected.size()
	var top := _hbox()
	var who := "내가 직접 움직일 캐릭터를 먼저 골라 줘" if n == 0 else ("함께 싸울 AI 동료를 골라 줘  (%d / 3)" % n)
	var title := UiStyle.label(who, 42, UiStyle.C_ACCENT, HORIZONTAL_ALIGNMENT_LEFT, false)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(UiStyle.label("카드를 누르면 자세히 볼 수 있어요", 24, UiStyle.C_SUB, HORIZONTAL_ALIGNMENT_RIGHT, false))
	_root.add_child(top)
	if _focus != "":
		_root.add_child(_detail_holder(_focus))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for t in GameData.hero_order:
		grid.add_child(_card(t))
	_root.add_child(grid)
	var bottom := _hbox()
	var back := UiStyle.button("◀ 처음으로", 240)
	back.pressed.connect(func(): _send("back"))
	bottom.add_child(back)
	var rec := UiStyle.button("추천 팀", 220)
	rec.pressed.connect(func(): _send("recommended"))
	bottom.add_child(rec)
	bottom.add_child(_spacer(false))
	var go := UiStyle.button("전투 시작 ▶", 420, 96, 40)
	go.disabled = n != 3
	if n == 3:
		UiStyle.set_selected(go, true)
	go.pressed.connect(func(): _send("battle_start"))
	bottom.add_child(go)
	_root.add_child(bottom)


func _card(t: String) -> Control:
	var d: Dictionary = GameData.hero(t)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(380, 140)
	var idx := controller.selected.find(t)
	UiStyle.set_selected(b, idx >= 0 or t == _focus)
	b.pressed.connect(func():
		if _focus == t:
			_focus = ""
			_focus_shown = ""
		else:
			_focus = t)
	var h := _hbox(10)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 8
	h.offset_right = -8
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var face := SvFace.new(t, 120)
	face.dim = controller.selected.size() >= 3 and idx < 0
	h.add_child(face)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UiStyle.label(GameData.person(t), 34, UiStyle.C_ACCENT if idx >= 0 else UiStyle.C_TEXT, HORIZONTAL_ALIGNMENT_LEFT, false))
	v.add_child(UiStyle.label("%s · %s" % [d["name"], d.get("feature", "")], 21, UiStyle.C_SUB))
	if idx >= 0:
		v.add_child(UiStyle.label("✔ " + ("내가 조종" if idx == 0 else "AI 동료"), 26, UiStyle.C_ACCENT, HORIZONTAL_ALIGNMENT_LEFT, false))
	h.add_child(v)
	b.add_child(h)
	return b


func _detail_holder(t: String) -> Control:
	## 위에서 아래로 펼쳐지며 카드 목록을 밀어 내리는 상세 패널
	var holder := Control.new()
	holder.clip_contents = true
	holder.custom_minimum_size = Vector2(0, DETAIL_H)
	var panel := _detail_panel(t)
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_top = -DETAIL_H
	holder.add_child(panel)
	if _focus_shown == "":
		holder.custom_minimum_size.y = 0.0
		var tw := holder.create_tween()
		tw.tween_property(holder, "custom_minimum_size:y", DETAIL_H, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_focus_shown = t
	return holder


func _detail_panel(t: String) -> Control:
	var d: Dictionary = GameData.hero(t)
	var idx := controller.selected.find(t)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiStyle.box(Color("#2b3a55"), 22, 4, _hcol(t)))
	var h := _hbox(26)
	h.add_child(SvFace.new(t, 380, "full"))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	var nr := _hbox(16)
	nr.add_child(UiStyle.label(GameData.person(t), 56, UiStyle.C_TEXT, HORIZONTAL_ALIGNMENT_LEFT, false))
	var role := UiStyle.label(str(d["name"]), 32, _hcol(t).lightened(0.3), HORIZONTAL_ALIGNMENT_LEFT, false)
	role.size_flags_vertical = Control.SIZE_SHRINK_END
	nr.add_child(role)
	v.add_child(nr)
	v.add_child(UiStyle.label(str(d.get("profile", "")), 26, UiStyle.C_SUB))
	v.add_child(UiStyle.label(str(d.get("bio", d.get("desc", ""))), 28, UiStyle.C_TEXT))
	var fp := PanelContainer.new()
	fp.add_theme_stylebox_override("panel", UiStyle.box(Color("#1f2a3d"), 16))
	var fv := VBoxContainer.new()
	fv.add_child(UiStyle.label("★ 특징: %s" % d.get("feature", ""), 28, UiStyle.C_ACCENT))
	fv.add_child(UiStyle.label("%s — %s" % [d.get("attack", ""), d.get("desc", "")], 24, UiStyle.C_TEXT))
	fv.add_child(UiStyle.label("사거리 %.1f칸 · %.2f초마다 자동 공격" % [SvAI.hero_range(_dummy(t)), float(d["interval"])], 22, UiStyle.C_SUB))
	fp.add_child(fv)
	v.add_child(fp)
	v.add_child(_spacer())
	var row := _hbox(16)
	if idx >= 0:
		var un := UiStyle.button("팀에서 빼기", 300, 88)
		un.pressed.connect(func():
			_send("unconfirm_hero", {"type": t})
			_focus = ""
			_focus_shown = "")
		row.add_child(un)
	else:
		var full := controller.selected.size() >= 3
		var label := "이미 3명을 골랐어요" if full else ("이 캐릭터로 직접 싸울래!" if controller.selected.is_empty() else "AI 동료로 데려갈래!")
		var ok := UiStyle.button(label, 440, 88, 34)
		ok.disabled = full
		if not full:
			UiStyle.set_selected(ok, true)
		ok.pressed.connect(func():
			_send("confirm_hero", {"type": t})
			_focus = ""
			_focus_shown = "")
		row.add_child(ok)
	var close := UiStyle.button("닫기", 180, 88)
	close.pressed.connect(func():
		_focus = ""
		_focus_shown = "")
	row.add_child(close)
	v.add_child(row)
	h.add_child(v)
	p.add_child(h)
	return p


func _dummy(t: String) -> SvState.SvHero:
	var h := SvState.SvHero.new()
	h.type = t
	return h


# ---------------- 전투 ----------------

func _build_battle() -> void:
	var st := controller.session.state
	var status := UiStyle.label("", 32, UiStyle.C_ACCENT, HORIZONTAL_ALIGNMENT_LEFT, false)
	_live["status"] = status
	_root.add_child(status)
	var body := _hbox(20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.7
	var tmap := SvTacticalMap.new()
	tmap.controller = controller
	tmap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tmap.map_pressed.connect(func(p: Vector2): _send("move_to", {"x": p.x, "y": p.y}))
	left.add_child(tmap)
	left.add_child(UiStyle.label("지도를 누르면 %s 그곳으로 이동해요. 공격은 자동이에요." % TextUtil.iga(GameData.person(st.player().type)), 24, UiStyle.C_SUB))
	body.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	for h in st.heroes:
		right.add_child(_hero_row(h))
	body.add_child(right)
	_root.add_child(body)


func _hero_row(h: SvState.SvHero) -> Control:
	var panel := PanelContainer.new()
	var open := _open_hero == h.id
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.C_CARD_SEL if open else UiStyle.C_CARD, 18, 4 if (open or h.is_player) else 0, UiStyle.C_ACCENT))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.flat = true
	btn.custom_minimum_size = Vector2(0, 120)
	btn.pressed.connect(func():
		if h.is_player:
			return
		_open_hero = -1 if _open_hero == h.id else h.id)
	var row := _hbox(12)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var face := SvFace.new(h.type, 116)
	row.add_child(face)
	var info := VBoxContainer.new()
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	var name_l := UiStyle.label("%s  ·  %s" % [GameData.person(h.type), "내가 조종" if h.is_player else "AI 동료"], 30, UiStyle.C_ACCENT if h.is_player else UiStyle.C_TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
	info.add_child(name_l)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 16)
	bar.max_value = h.max_hp
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("fill", UiStyle.box(Color("#4cd37a"), 6))
	bar.add_theme_stylebox_override("background", UiStyle.box(Color(0, 0, 0, 0.45), 6))
	info.add_child(bar)
	var st_l := UiStyle.label("", 22, UiStyle.C_SUB, HORIZONTAL_ALIGNMENT_LEFT, false)
	info.add_child(st_l)
	_live["hero%d" % h.id] = {"bar": bar, "status": st_l, "face": face}
	row.add_child(info)
	btn.add_child(row)
	v.add_child(btn)
	if open:
		v.add_child(UiStyle.label("%s에게 어떤 작전을 줄까?" % GameData.person(h.type), 26, UiStyle.C_ACCENT))
		var tr := _hbox(10)
		for t in SvData.tactic_order():
			var tb := UiStyle.button(SvData.tactic_name(t), 140, 84, 30)
			tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			UiStyle.set_selected(tb, h.tactic == t)
			var hid := h.id
			tb.pressed.connect(func():
				_send("set_tactic", {"hero": hid, "tactic": t})
				_open_hero = -1)
			tr.add_child(tb)
		v.add_child(tr)
		var desc: Array = []
		for t in SvData.tactic_order():
			desc.append("%s: %s" % [SvData.tactic_name(t), SvData.cfg["tactics"][t]["desc"]])
		v.add_child(UiStyle.label("\n".join(desc), 21, UiStyle.C_SUB))
	elif not h.is_player:
		v.add_child(UiStyle.label("얼굴을 누르면 작전을 바꿀 수 있어요", 20, UiStyle.C_SUB))
	panel.add_child(v)
	return panel


func _update_live() -> void:
	if controller.phase != SvController.BATTLE or controller.session == null:
		return
	var st := controller.session.state
	if _live.has("status"):
		var left := int(ceil(st.time_left()))
		_live["status"].text = "남은 시간 %d:%02d   ·   기지 HP %d / %d   ·   처치 %d" % [left / 60, left % 60, int(ceil(st.base_hp)), int(st.base_hp_max), st.kills]
	for h in st.heroes:
		var rec: Dictionary = _live.get("hero%d" % h.id, {})
		if rec.is_empty():
			continue
		rec["bar"].value = h.hp
		rec["face"].dim = not h.alive()
		rec["face"].queue_redraw()
		var s := ""
		if not h.alive():
			s = "쓰러짐 — %d초 뒤 기지에서 다시 일어나요" % int(ceil(h.down_t))
		elif h.is_player:
			s = "이동 중" if h.goal != Vector2.INF else "자동 공격 중 — 지도를 눌러 이동"
		else:
			s = "작전: %s  ·  %s" % [SvData.tactic_name(h.tactic), h.status]
		rec["status"].text = s


# ---------------- 결과 ----------------

func _build_result() -> void:
	var r: Dictionary = controller.result
	_root.add_child(_spacer())
	_root.add_child(UiStyle.label("기지를 지켜 냈어요!" if r.get("outcome", "") == "win" else "끝까지 잘 싸웠어요!", 64, UiStyle.C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	var secs := int(r.get("time", 0))
	_root.add_child(UiStyle.label("버틴 시간 %d:%02d · 기지 HP %d/%d · 처치 %d · 이동 명령 %d번 · 작전 변경 %d번" % [
		secs / 60, secs % 60, int(ceil(r.get("base_hp", 0))), int(r.get("base_hp_max", 100)), r.get("kills", 0), r.get("moves", 0), r.get("tactic_changes", 0)],
		30, UiStyle.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var row := _hbox()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var b := UiStyle.button("다음 학생 시작", 560, 130, 52)
	b.pressed.connect(func(): _send("next_student"))
	row.add_child(b)
	_root.add_child(row)
	var t := UiStyle.label("", 24, UiStyle.C_SUB, HORIZONTAL_ALIGNMENT_CENTER)
	_live["result_timer"] = t
	_root.add_child(t)
	_root.add_child(_spacer())


# ---------------- 교사 메뉴 ----------------

func _build_teacher() -> void:
	_root.add_child(UiStyle.label("교사용 메뉴", 52, UiStyle.C_ACCENT))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	for it in [["처음 화면으로", "reset"], ["전체 화면 켜기/끄기", "fullscreen"], ["화면 역할 바꾸기", "swap"],
			["FPS·성능 표시", "fps"], ["화면 연결 안내", "display_info"], ["이전 타워디펜스 실행", "td"],
			["메뉴 닫기", "close"], ["프로그램 종료", "quit"]]:
		var b := UiStyle.button(it[0], 360, 96, 30)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var act: String = it[1]
		b.pressed.connect(func(): _on_teacher(act))
		grid.add_child(b)
	_root.add_child(grid)
	if _teacher_info != "":
		var p := PanelContainer.new()
		p.add_child(UiStyle.label(_teacher_info, 24, UiStyle.C_TEXT))
		_root.add_child(p)
	_root.add_child(UiStyle.label("단축키: F10 메뉴 · F11 전체화면 · F9 화면 역할 바꾸기 · F3 FPS · Ctrl+R 처음으로 · Shift+Esc 종료", 22, UiStyle.C_SUB))


func _on_teacher(act: String) -> void:
	match act:
		"reset":
			_send("teacher_reset")
			_teacher_open = false
		"fps":
			_send("teacher_toggle_fps")
		"close":
			_teacher_open = false
		_:
			teacher_action.emit(act)


func _physics_process(_d: float) -> void:
	if _live.has("result_timer"):
		_live["result_timer"].text = "%d초 뒤 자동으로 처음 화면으로 돌아가요" % int(ceil(controller.result_time_left()))
