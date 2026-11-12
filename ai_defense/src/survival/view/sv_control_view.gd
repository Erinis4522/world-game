class_name SvControlView
extends Control
## 터치 패널 (아래 화면). 3D는 그리지 않는 가벼운 2D 조작 화면.
##  - 선택: 카드 → 원화 상세(위에서 내려옴) → 확정. 고른 3명 = 맵 곳곳을 맡아 스스로 싸우는 동료
##  - 전투 기본: 사각형 네 모서리 = 동료 3명 + 건설 동료 든든이, 가운데 = 조이스틱(나)
##  - 동료 초상화 → 게임이 아주 느려지고 원화 + 행동 원칙 3개 → 고르면 기본 화면으로
##  - 든든이 초상화 → 게임 멈춤, 그림 칸 → AI 해석·제안 → 승인 / 다시 그리기 / 취소
## 모든 명령은 controller.command()로만 보낸다.

signal teacher_action(action: String)

var controller: SvController
var _seq := 0
var _built_key := ""
var _root: VBoxContainer
var _focus := ""
var _focus_shown := ""
var _teacher_open := false
var _teacher_info := ""
var _corner_down := -1.0
var _now := 0.0
var _live: Dictionary = {}
var _pad: SvSketchPad

const DETAIL_H := 440.0


func setup(c: SvController) -> void:
	controller = c
	controller.phase_changed.connect(func(_p):
		_focus = ""
		_focus_shown = "")


func _ready() -> void:
	theme = UiStyle.build_theme()
	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 16)
	margin.add_child(_root)


func _send(name: String, args: Dictionary = {}) -> Dictionary:
	_seq += 1
	return controller.command(name, args, _seq)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		controller.note_activity()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var corner := Rect2(Vector2(size.x - 90, 0), Vector2(90, 70))
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
	var key := "%s|%d|%s|%s|%d|%s|%s" % [controller.phase, controller.state_version, _focus, controller.overlay,
		controller.overlay_hero, str(_teacher_open), _teacher_info]
	if key != _built_key:
		_built_key = key
		_rebuild()
	_update_live()


func _rebuild() -> void:
	for c in _root.get_children():
		_root.remove_child(c)
		c.queue_free()
	_live.clear()
	_pad = null
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
			match controller.overlay:
				"principle":
					_build_principle()
				"sketch":
					_build_sketch()
				_:
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


func _hbox(sep := 16) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


func _vbox(sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


func _hcol(t: String) -> Color:
	return Color.from_string(str(SvData.hero(t).get("color", "#888")), Color.GRAY)


func _bar(col: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 16)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("fill", UiStyle.box(col, 6))
	bar.add_theme_stylebox_override("background", UiStyle.box(Color(0, 0, 0, 0.45), 6))
	return bar


# ---------------- 대기 ----------------

func _build_attract() -> void:
	_root.add_child(_spacer())
	_root.add_child(UiStyle.label("AI 디펜스", 96, UiStyle.C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	_root.add_child(UiStyle.label("동료 3명을 골라요. 동료들은 마을로 오는 길을 나눠 맡아 스스로 싸우고,\n나는 조이스틱으로 움직이며 건설 동료 '든든이'와 함께 그림으로 벽과 필살기를 불러요.", 32, UiStyle.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
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
	var title := UiStyle.label("함께 싸울 동료 3명을 골라 줘  (%d / 3)" % n, 42, UiStyle.C_ACCENT, HORIZONTAL_ALIGNMENT_LEFT, false)
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
	v.add_child(UiStyle.label("%s · 필살기 %s" % [d["name"], SvData.ult(t).get("name", "")], 21, UiStyle.C_SUB))
	if idx >= 0:
		v.add_child(UiStyle.label("✔ %s 담당" % SvData.roads()[idx % SvData.roads().size()]["name"], 24, UiStyle.C_ACCENT, HORIZONTAL_ALIGNMENT_LEFT, false))
	h.add_child(v)
	b.add_child(h)
	return b


func _detail_holder(t: String) -> Control:
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
	var v := _vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nr := _hbox(16)
	nr.add_child(UiStyle.label(GameData.person(t), 56, UiStyle.C_TEXT, HORIZONTAL_ALIGNMENT_LEFT, false))
	var role := UiStyle.label(str(d["name"]), 32, _hcol(t).lightened(0.3), HORIZONTAL_ALIGNMENT_LEFT, false)
	role.size_flags_vertical = Control.SIZE_SHRINK_END
	nr.add_child(role)
	v.add_child(nr)
	v.add_child(UiStyle.label(str(d.get("profile", "")), 26, UiStyle.C_SUB))
	v.add_child(UiStyle.label(str(d.get("bio", d.get("desc", ""))), 27, UiStyle.C_TEXT))
	var fp := PanelContainer.new()
	fp.add_theme_stylebox_override("panel", UiStyle.box(Color("#1f2a3d"), 16))
	var fv := VBoxContainer.new()
	fv.add_child(UiStyle.label("★ 특징: %s" % d.get("feature", ""), 27, UiStyle.C_ACCENT))
	fv.add_child(UiStyle.label("%s — %s" % [d.get("attack", ""), d.get("desc", "")], 23, UiStyle.C_TEXT))
	fv.add_child(UiStyle.label("필살기: %s (그림으로 불러요)" % SvData.ult(t).get("name", ""), 23, UiStyle.C_SUB))
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
		var ok := UiStyle.button("이미 3명을 골랐어요" if full else "동료로 데려갈래!", 420, 88, 34)
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


# ---------------- 전투 기본: 사각형 배치 + 조이스틱 ----------------

func _build_battle() -> void:
	var st := controller.session.state
	var status := UiStyle.label("", 30, UiStyle.C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER, false)
	_live["status"] = status
	_root.add_child(status)
	var body := _hbox(18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var comps: Array = st.companions()
	var left := _vbox(18)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(_companion_card(comps[0]))
	left.add_child(_companion_card(comps[2]))
	var mid := _vbox(0)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.size_flags_stretch_ratio = 1.05
	var joy := SvJoystick.new()
	joy.size_flags_vertical = Control.SIZE_EXPAND_FILL
	joy.moved.connect(func(v: Vector2): _send("joy", {"x": v.x, "y": v.y}))
	mid.add_child(joy)
	var right := _vbox(18)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(_companion_card(comps[1]))
	right.add_child(_builder_card(st.builder()))
	body.add_child(left)
	body.add_child(mid)
	body.add_child(right)
	_root.add_child(body)


func _card_button(h: SvState.SvHero, on_press: Callable, border: Color) -> Array:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 300)
	b.add_theme_stylebox_override("normal", UiStyle.box(UiStyle.C_CARD, 20, 4, border))
	b.add_theme_stylebox_override("hover", UiStyle.box(UiStyle.C_CARD, 20, 4, border.lightened(0.3)))
	b.add_theme_stylebox_override("pressed", UiStyle.box(UiStyle.C_CARD_SEL, 20, 5, UiStyle.C_ACCENT))
	b.pressed.connect(on_press)
	var row := _hbox(14)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 14
	row.offset_right = -14
	row.offset_top = 14
	row.offset_bottom = -14
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var face := SvFace.new(h.type, 210)
	row.add_child(face)
	var info := _vbox(6)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(info)
	b.add_child(row)
	return [b, info, face]


func _companion_card(h: SvState.SvHero) -> Control:
	var hid := h.id
	var parts := _card_button(h, func(): _send("open_principle", {"hero": hid}), _hcol(h.type))
	var info: VBoxContainer = parts[1]
	info.add_child(UiStyle.label(SvData.person(h.type), 36, UiStyle.C_TEXT, HORIZONTAL_ALIGNMENT_LEFT, false))
	info.add_child(UiStyle.label("%s · %s 담당" % [GameData.hero(h.type)["name"], SvData.road(h.zone)["name"]], 21, UiStyle.C_SUB))
	var bar := _bar(Color("#4cd37a"))
	bar.max_value = h.max_hp
	info.add_child(bar)
	var pr := UiStyle.label("", 24, UiStyle.C_ACCENT, HORIZONTAL_ALIGNMENT_LEFT, false)
	info.add_child(pr)
	var stl := UiStyle.label("", 20, UiStyle.C_SUB)
	info.add_child(stl)
	_live["hero%d" % hid] = {"bar": bar, "principle": pr, "status": stl, "face": parts[2]}
	return parts[0]


func _builder_card(h: SvState.SvHero) -> Control:
	var parts := _card_button(h, func(): _send("open_sketch"), Color("#ffd84a"))
	var info: VBoxContainer = parts[1]
	info.add_child(UiStyle.label("든든이 · 그림 그리기", 34, UiStyle.C_ACCENT, HORIZONTAL_ALIGNMENT_LEFT, false))
	info.add_child(UiStyle.label("선 = 벽 건설", 22, UiStyle.C_TEXT))
	var syms: Array = SvData.sec("sketch", "symbols", [])
	var names: Dictionary = SvData.sec("sketch", "symbol_names", {})
	var comps: Array = controller.session.state.companions()
	for i in mini(syms.size(), comps.size()):
		info.add_child(UiStyle.label("%s = %s의 %s" % [names.get(syms[i], syms[i]), SvData.person(comps[i].type), SvData.ult(comps[i].type).get("name", "")], 20, UiStyle.C_SUB))
	var en := UiStyle.label("", 22, Color(0.6, 0.95, 1.0), HORIZONTAL_ALIGNMENT_LEFT, false)
	info.add_child(en)
	_live["energy"] = en
	return parts[0]


func _update_live() -> void:
	if controller.session == null:
		return
	var st := controller.session.state
	if _live.has("status"):
		var left := int(ceil(st.time_left()))
		_live["status"].text = "남은 시간 %d:%02d   ·   마을 HP %d   ·   에너지 %d   ·   처치 %d" % [left / 60, left % 60, int(ceil(st.base_hp)), st.energy, st.kills]
	if _live.has("energy"):
		_live["energy"].text = "에너지 %d (벽 1칸 = 1, 필살기 = %d)" % [st.energy, int(SvData.sec("ultimate", "cost", 8))]
	for h in st.heroes:
		var rec: Dictionary = _live.get("hero%d" % h.id, {})
		if rec.is_empty():
			continue
		rec["bar"].value = h.hp
		rec["face"].dim = not h.alive()
		rec["face"].queue_redraw()
		rec["principle"].text = "원칙: " + GameData.principle_name(h.principle)
		var s: String = h.status
		if not h.alive():
			s = "쓰러짐 — %d초 뒤 마을에서 일어나요" % int(ceil(h.down_t))
		var cd: float = h.ult_ready_t - st.time
		s += "  ·  필살기 " + ("준비" if cd <= 0.0 else "%d초" % int(ceil(cd)))
		rec["status"].text = s
	if _live.has("result_timer"):
		_live["result_timer"].text = "%d초 뒤 자동으로 처음 화면으로 돌아가요" % int(ceil(controller.result_time_left()))


# ---------------- 동료 원칙 (슬로모션) ----------------

func _build_principle() -> void:
	var h: SvState.SvHero = controller.session.state.heroes[controller.overlay_hero]
	_root.add_child(UiStyle.label("시간이 느려졌어요 — %s에게 어떤 원칙으로 싸울지 알려 줘" % SvData.person(h.type), 34, UiStyle.C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	var body := _hbox(30)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_spacer(false))
	var art := SvFace.new(h.type, 600, "full")
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(art)
	var col := _vbox(16)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 1.6
	col.add_child(UiStyle.label(SvData.person(h.type), 64, UiStyle.C_TEXT, HORIZONTAL_ALIGNMENT_LEFT, false))
	col.add_child(UiStyle.label("%s · %s 담당 · %s" % [GameData.hero(h.type)["name"], SvData.road(h.zone)["name"], h.status], 26, UiStyle.C_SUB))
	for p in GameData.principle_order():
		var w: Dictionary = GameData.config["principles"][p]
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 130)
		b.text = "%s\n%s%s" % [w["name"], w["desc"], "   (지금)" if h.principle == p else ""]
		b.add_theme_font_size_override("font_size", 32)
		UiStyle.set_selected(b, h.principle == p)
		var hid := h.id
		b.pressed.connect(func(): _send("set_principle", {"hero": hid, "principle": p}))
		col.add_child(b)
	var back := UiStyle.button("그대로 두고 돌아가기", 380, 90)
	back.pressed.connect(func(): _send("close_overlay"))
	col.add_child(back)
	body.add_child(col)
	body.add_child(_spacer(false))
	_root.add_child(body)


# ---------------- 그림 (멈춤) ----------------

func _build_sketch() -> void:
	var s := controller.session
	_root.add_child(UiStyle.label("잠깐 멈춤 — 든든이에게 그림으로 부탁해요", 34, UiStyle.C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	var body := _hbox(24)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pad = SvSketchPad.new()
	_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pad.size_flags_stretch_ratio = 1.3
	_pad.locked = not s.proposal.is_empty()
	if s.last_sketch.has("points_drawn") and not s.proposal.is_empty():
		_pad.points = s.last_sketch["points_drawn"]
	_pad.stroke_finished.connect(func(pts: PackedVector2Array):
		var arr: Array = []
		for p in pts:
			arr.append([p.x, p.y])
		_send("submit_sketch", {"points": arr})
		if controller.session != null:
			controller.session.last_sketch["points_drawn"] = pts)
	body.add_child(_pad)
	var side := _vbox(12)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if s.proposal.is_empty():
		_sketch_legend(side, s)
	else:
		_sketch_proposal(side, s)
	body.add_child(side)
	_root.add_child(body)


func _sketch_legend(side: VBoxContainer, s: SvSession) -> void:
	side.add_child(UiStyle.label("이렇게 그려요", 36, UiStyle.C_ACCENT))
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiStyle.box(Color("#1f2a3d"), 16))
	var v := _vbox(10)
	v.add_child(UiStyle.label("선 (직선·ㄱ자·U자·곡선)  →  든든이가 그 모양대로 벽을 세워요\n   크기와 위치는 AI가 길·적·우리 이동 길을 보고 정해요", 25, UiStyle.C_TEXT))
	var syms: Array = SvData.sec("sketch", "symbols", [])
	var names: Dictionary = SvData.sec("sketch", "symbol_names", {})
	var comps: Array = s.state.companions()
	for i in mini(syms.size(), comps.size()):
		var h: SvState.SvHero = comps[i]
		var ready := SvEngine.ult_ready(s.state, h)
		v.add_child(UiStyle.label("%s  →  %s의 필살기 '%s' %s" % [names.get(syms[i], syms[i]), SvData.person(h.type), SvData.ult(h.type).get("name", ""), "(준비됨)" if ready else "(아직 준비 안 됨)"], 25, UiStyle.C_TEXT if ready else UiStyle.C_SUB))
	p.add_child(v)
	side.add_child(p)
	side.add_child(UiStyle.label("에너지 %d  ·  벽 1칸 = 1  ·  필살기 = %d" % [s.state.energy, int(SvData.sec("ultimate", "cost", 8))], 26, Color(0.6, 0.95, 1.0)))
	side.add_child(_spacer())
	var row := _hbox(14)
	var clr := UiStyle.button("지우기", 220, 90)
	clr.pressed.connect(func():
		if _pad != null:
			_pad.clear())
	row.add_child(clr)
	var close := UiStyle.button("닫기 (전투로)", 300, 90)
	close.pressed.connect(func(): _send("close_overlay"))
	row.add_child(close)
	side.add_child(row)


func _sketch_proposal(side: VBoxContainer, s: SvSession) -> void:
	var pr: Dictionary = s.proposal
	var an: Dictionary = pr.get("analysis", {})
	var kind_names := {"LINE": "선", "CIRCLE": "동그라미", "TRIANGLE": "세모", "ZIGZAG": "번개 모양"}
	if pr.get("ask", false):
		side.add_child(UiStyle.label("AI가 헷갈려요", 38, UiStyle.C_ACCENT))
		side.add_child(UiStyle.label(str(pr.get("reason", "")), 27, UiStyle.C_TEXT))
		side.add_child(UiStyle.label("어떤 걸 그린 거야?", 28, UiStyle.C_TEXT))
		for k in pr.get("choices", []):
			var b := UiStyle.button("%s 볼게" % TextUtil.euro(str(kind_names.get(k, k))), 360, 90)
			var kk: String = k
			b.pressed.connect(func(): _send("choose_kind", {"kind": kk}))
			side.add_child(b)
	elif not pr.get("ok", false):
		side.add_child(UiStyle.label("이건 실행할 수 없어요", 38, UiStyle.C_ACCENT))
		side.add_child(UiStyle.label(str(pr.get("reason", "")), 28, UiStyle.C_TEXT))
	else:
		var title := ""
		if pr["kind"] == "WALL":
			title = "AI 해석: %s → %s 벽 %d칸 (%s)" % [kind_names.get(an.get("kind", "LINE"), "선"), pr.get("shape", ""), pr["cells"].size(), pr.get("road_name", "")]
		else:
			title = "AI 해석: %s → %s의 %s" % [kind_names.get(pr.get("symbol", ""), ""), SvData.person(pr["hero_type"]), pr["name"]]
		side.add_child(UiStyle.label(title, 30, UiStyle.C_ACCENT))
		side.add_child(UiStyle.label("위 화면에 파란(벽) / 주황(필살기) 미리보기가 보여요", 22, UiStyle.C_SUB))
		var cards := _hbox(12)
		cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cards.add_child(_list_card("기대 효과", pr.get("pros", []), UiStyle.C_PRO))
		cards.add_child(_list_card("조심할 점", pr.get("cons", []), UiStyle.C_CON))
		side.add_child(cards)
	side.add_child(_spacer())
	var row := _hbox(12)
	if pr.get("ok", false):
		var go := UiStyle.button("건설!" if pr["kind"] == "WALL" else "필살기 사용!", 260, 96, 36)
		UiStyle.set_selected(go, true)
		go.pressed.connect(func(): _send("accept_proposal"))
		row.add_child(go)
	var redraw := UiStyle.button("다시 그리기", 240, 96)
	redraw.pressed.connect(func(): _send("redraw"))
	row.add_child(redraw)
	var cancel := UiStyle.button("취소", 160, 96)
	cancel.pressed.connect(func(): _send("close_overlay"))
	row.add_child(cancel)
	side.add_child(row)


func _list_card(title: String, items: Array, col: Color) -> Control:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", UiStyle.box(col, 16))
	var v := _vbox(8)
	v.add_child(UiStyle.label(title, 28, UiStyle.C_ACCENT))
	for it in items:
		v.add_child(UiStyle.label("• " + str(it), 22, UiStyle.C_TEXT))
	p.add_child(v)
	return p


# ---------------- 결과 ----------------

func _build_result() -> void:
	var r: Dictionary = controller.result
	_root.add_child(_spacer())
	_root.add_child(UiStyle.label("마을을 지켜 냈어요!" if r.get("outcome", "") == "win" else "끝까지 잘 싸웠어요!", 64, UiStyle.C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	var secs := int(r.get("time", 0))
	var cm: Dictionary = r.get("commands", {})
	_root.add_child(UiStyle.label("버틴 시간 %d:%02d · 마을 HP %d · 처치 %d · 세운 벽 %d · 그림 %d번 · 원칙 변경 %d번" % [
		secs / 60, secs % 60, int(ceil(r.get("base_hp", 0))), r.get("kills", 0), r.get("walls", 0), cm.get("sketch", 0), cm.get("principle", 0)],
		28, UiStyle.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
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
