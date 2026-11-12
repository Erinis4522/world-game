class_name SvHud
extends Control
## 일반 모니터의 3D 화면 위에 겹치는 2D 정보: 상단 바, 머리 위 이름·체력, 말풍선, 안내 배너,
## 선택·작전 개시·결과 장면의 전신 원화.

var controller: SvController
var world: SvWorld3D
var font: Font
var now := 0.0
var banner_text := ""
var banner_until := 0.0
var _lineup_t0: Dictionary = {}
var fps_text := ""
var _fps_acc := 0.0

const C_PANEL := Color(0.07, 0.09, 0.13, 0.82)


func setup(c: SvController, w: SvWorld3D) -> void:
	controller = c
	world = w
	controller.battle_events.connect(_on_events)
	controller.phase_changed.connect(_on_phase)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = get_theme_default_font()


func _process(delta: float) -> void:
	now += delta
	var vr := get_viewport_rect()
	if size != vr.size:
		position = Vector2.ZERO
		size = vr.size
	_fps_acc += delta
	if _fps_acc >= 0.5:
		_fps_acc = 0.0
		var n := controller.session.state.enemies.size() if controller.session != null else 0
		fps_text = "FPS %d · 적 %d · 3D 그리기 %d회" % [Engine.get_frames_per_second(), n,
			int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))]
	queue_redraw()


func _on_phase(p: String) -> void:
	if p == SvController.BATTLE:
		_banner("작전 개시! 기지를 지켜요", 2.0)


func _on_events(events: Array) -> void:
	for ev in events:
		match ev["type"]:
			"PHASE":
				if int(ev["index"]) > 0:
					_banner(str(ev["text"]), 2.4)
			"OUTCOME":
				_banner("기지를 지켜 냈어요!" if ev["outcome"] == "win" else "기지가 무너졌어요", 2.0)


func _banner(t: String, dur: float) -> void:
	banner_text = t
	banner_until = now + dur


# ---------------- 그리기 ----------------

func _draw() -> void:
	if controller == null:
		return
	match controller.phase:
		SvController.ATTRACT:
			_draw_attract()
		SvController.SELECT:
			_draw_lineup()
		SvController.INTRO:
			_draw_intro()
		SvController.BATTLE:
			_draw_battle()
		SvController.RESULT:
			_draw_battle()
			_draw_result()
	if controller.show_fps:
		_text(fps_text, Vector2(size.x - 16, size.y - 14), 22, Color(1, 1, 0.6), HORIZONTAL_ALIGNMENT_RIGHT, true)


func _draw_battle() -> void:
	var s := controller.session
	if s == null:
		return
	var st := s.state
	var a := controller.alpha()
	# 적 체력바
	for e in st.enemies:
		if not e.alive or e.hp >= e.max_hp:
			continue
		var p := world.screen_pos(e.prev_pos.lerp(e.pos, a), e.radius * 3.6 + 0.3)
		var bw := 44.0
		draw_rect(Rect2(p + Vector2(-bw * 0.5, 0), Vector2(bw, 6)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(p + Vector2(-bw * 0.5, 0), Vector2(bw * e.hp / e.max_hp, 6)), Color(0.95, 0.3, 0.25))
	# 아군 이름·체력
	for h in st.heroes:
		if not h.alive():
			continue
		var p := world.screen_pos(h.prev_pos.lerp(h.pos, a), 2.8)
		var name := GameData.person(h.type) + (" (나)" if h.is_player else "")
		var col := Color(1, 0.9, 0.4) if h.is_player else Color(1, 1, 1)
		_text(name, p + Vector2(0, -14), 22, col, HORIZONTAL_ALIGNMENT_CENTER, true)
		var bw := 64.0
		draw_rect(Rect2(p + Vector2(-bw * 0.5, -6), Vector2(bw, 8)), Color(0, 0, 0, 0.6))
		var r: float = h.hp / h.max_hp
		draw_rect(Rect2(p + Vector2(-bw * 0.5, -6), Vector2(bw * r, 8)), Color(0.35, 0.9, 0.45) if r > 0.35 else Color(0.95, 0.4, 0.3))
	# 말풍선 (최대 2개)
	for b in s.bubbles:
		var h: SvState.SvHero = st.heroes[b["hero"]]
		if not h.alive():
			continue
		var anchor := world.screen_pos(h.prev_pos.lerp(h.pos, a), 3.2)
		_bubble(anchor, "%s: %s" % [GameData.person(h.type), b["text"]])
	_draw_topbar(st)
	if banner_until > now:
		_draw_banner(banner_text)
	# 쓰러진 캐릭터 안내
	var y := 96.0
	for h in st.heroes:
		if not h.alive():
			_text("%s 다시 일어나는 중… %d초" % [GameData.person(h.type), int(ceil(h.down_t))], Vector2(size.x * 0.5, y + 30), 28, Color(1, 0.7, 0.6), HORIZONTAL_ALIGNMENT_CENTER, true)
			y += 36


func _draw_topbar(st: SvState) -> void:
	draw_rect(Rect2(0, 0, size.x, 76), C_PANEL)
	_text("기지 HP", Vector2(24, 50), 32, Color.WHITE)
	var bx := 150.0
	var bw := 320.0
	draw_rect(Rect2(bx, 28, bw, 24), Color(0, 0, 0, 0.5))
	var r := st.base_hp / st.base_hp_max
	draw_rect(Rect2(bx, 28, bw * r, 24), Color(0.25, 0.85, 0.8) if r > 0.35 else Color(0.95, 0.35, 0.3))
	_text("%d / %d" % [int(ceil(st.base_hp)), int(st.base_hp_max)], Vector2(bx + bw + 16, 50), 28, Color.WHITE)
	var left := int(ceil(st.time_left()))
	_text("남은 시간 %d:%02d" % [left / 60, left % 60], Vector2(size.x * 0.5, 50), 38, Color(1, 0.93, 0.6), HORIZONTAL_ALIGNMENT_CENTER)
	draw_rect(Rect2(size.x * 0.5 - 200, 62, 400, 7), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(size.x * 0.5 - 200, 62, 400 * clampf(st.time / st.duration, 0, 1), 7), Color(1, 0.85, 0.3))
	_text("처치 %d" % st.kills, Vector2(size.x - 24, 50), 32, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)


func _bubble(anchor: Vector2, t: String) -> void:
	var fs := 28
	var sz := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var box := sz + Vector2(36, 26)
	var pos := anchor + Vector2(-box.x * 0.5, -box.y - 14)
	pos.x = clampf(pos.x, 10, size.x - box.x - 10)
	pos.y = clampf(pos.y, 84, size.y - box.y - 10)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.96)
	sb.border_color = Color(0.2, 0.2, 0.25)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(14)
	var tx := clampf(anchor.x, pos.x + 20, pos.x + box.x - 20)
	draw_colored_polygon(PackedVector2Array([Vector2(tx - 12, pos.y + box.y - 2), Vector2(tx + 12, pos.y + box.y - 2), Vector2(tx, pos.y + box.y + 12)]), Color(0.2, 0.2, 0.25))
	draw_style_box(sb, Rect2(pos, box))
	draw_string(font, pos + Vector2(18, 13 + fs * 0.85), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.1, 0.1, 0.15))


func _draw_banner(t: String) -> void:
	var fs := 52
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 80
	var r := Rect2(Vector2((size.x - w) * 0.5, size.y * 0.2), Vector2(w, 96))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.16, 0.85)
	sb.border_color = Color(1, 0.85, 0.3)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(16)
	draw_style_box(sb, r)
	_text(t, Vector2(size.x * 0.5, r.position.y + 66), fs, Color(1, 0.95, 0.7), HORIZONTAL_ALIGNMENT_CENTER)


func _draw_attract() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45))
	var cx := size.x * 0.5
	_text("AI 디펜스", Vector2(cx, size.y * 0.34), 120, Color(1, 0.92, 0.55), HORIZONTAL_ALIGNMENT_CENTER, true)
	_text("AI 동료와 함께 직접 움직이며 기지를 지켜요!", Vector2(cx, size.y * 0.47), 46, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, true)
	var blink := 0.6 + 0.4 * sin(now * 3.0)
	_text("아래 터치 화면의 [시작]을 눌러 주세요", Vector2(cx, size.y * 0.78), 42, Color(1, 1, 0.6, blink), HORIZONTAL_ALIGNMENT_CENTER, true)
	_text("이 게임의 AI는 상황마다 점수를 매겨 행동을 고르는 게임 AI예요. 스스로 학습하는 신경망이나 대화형 AI가 아니에요.",
		Vector2(cx, size.y - 30), 22, Color(0.85, 0.85, 0.85), HORIZONTAL_ALIGNMENT_CENTER, true)


func _draw_lineup() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.07, 0.11, 0.8))
	var sel: Array = controller.selected
	for k in _lineup_t0.keys():
		if not sel.has(k):
			_lineup_t0.erase(k)
	for t in sel:
		if not _lineup_t0.has(t):
			_lineup_t0[t] = now
	var cx := size.x * 0.5
	_text("우리 팀 (%d / 3)" % sel.size(), Vector2(cx, 92), 62, Color(1, 0.92, 0.55), HORIZONTAL_ALIGNMENT_CENTER, true)
	var sub := "첫 번째로 고른 캐릭터를 내가 직접 움직이고, 나머지 둘은 AI 동료가 돼요"
	if sel.size() == 3:
		sub = "팀 완성! 아래 터치 화면에서 [전투 시작]을 눌러요"
	_text(sub, Vector2(cx, 146), 30, Color(0.92, 0.92, 0.92), HORIZONTAL_ALIGNMENT_CENTER)
	var fw := minf(size.x * 0.28, 540.0)
	var fh := size.y - 230.0
	var gap := (size.x - fw * 3) / 4.0
	for i in 3:
		var r := Rect2(Vector2(gap + i * (fw + gap), 190), Vector2(fw, fh))
		var role := "내가 조종" if i == 0 else "AI 동료"
		if i >= sel.size():
			_box(r, Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.25))
			_text("?", r.get_center() + Vector2(0, 40), 160, Color(1, 1, 1, 0.2), HORIZONTAL_ALIGNMENT_CENTER)
			_text(role, Vector2(r.get_center().x, r.end.y - 36), 30, Color(1, 1, 1, 0.35), HORIZONTAL_ALIGNMENT_CENTER)
			continue
		var t: String = sel[i]
		var col := Color.from_string(str(GameData.hero(t).get("color", "#888")), Color.GRAY)
		var k := clampf((now - float(_lineup_t0[t])) / 0.5, 0.0, 1.0)
		var drop := (1.0 - _ease_back(k)) * -200.0
		_box(r, Color(col.r * 0.25, col.g * 0.25, col.b * 0.3, 0.92), col.lightened(0.2) if i > 0 else Color(1, 0.85, 0.3))
		HeroPortrait.draw(self, t, Rect2(r.position + Vector2(10, 10 + drop), Vector2(fw - 20, fh * 0.72)), "full", k)
		var ty := r.position.y + fh * 0.78
		_text(GameData.person(t), Vector2(r.get_center().x, ty + 30), 48, Color(1, 1, 1, k), HORIZONTAL_ALIGNMENT_CENTER, true)
		_text("%s · %s" % [GameData.hero(t)["name"], role], Vector2(r.get_center().x, ty + 76), 28, Color(1, 0.88, 0.5, k) if i == 0 else Color(0.85, 0.92, 1, k), HORIZONTAL_ALIGNMENT_CENTER)


func _draw_intro() -> void:
	## 전투 직전 짧은 연출: 3명의 전신 원화가 옆에서 들어오며 '작전 개시'
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.05, 0.09, 0.88))
	var sel: Array = controller.selected
	var k := clampf(controller.phase_time / 0.7, 0.0, 1.0)
	var fw := size.x * 0.3
	for i in sel.size():
		var ki := clampf(k * 1.4 - i * 0.2, 0.0, 1.0)
		var x := size.x * (0.05 + i * 0.32) + (1.0 - _ease_back(ki)) * size.x
		HeroPortrait.draw(self, sel[i], Rect2(Vector2(x, size.y * 0.12), Vector2(fw, size.y * 0.78)), "full", ki)
	var a := clampf((controller.phase_time - 0.6) / 0.4, 0.0, 1.0)
	_text("작전 개시!", Vector2(size.x * 0.5, size.y * 0.55), 110, Color(1, 0.92, 0.55, a), HORIZONTAL_ALIGNMENT_CENTER, true)
	_text("%s, 지도를 눌러 움직여요" % GameData.person(sel[0]) if not sel.is_empty() else "", Vector2(size.x * 0.5, size.y * 0.66), 38, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, true)


func _draw_result() -> void:
	var r: Dictionary = controller.result
	if r.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
	var box := Rect2(Vector2(size.x * 0.12, size.y * 0.1), Vector2(size.x * 0.76, size.y * 0.8))
	_box(box, Color(0.08, 0.1, 0.16, 0.95), Color(1, 0.85, 0.3))
	var cx := size.x * 0.5
	_text("기지를 지켜 냈어요!" if r["outcome"] == "win" else "끝까지 잘 싸웠어요!", Vector2(cx, box.position.y + 96), 70, Color(1, 0.92, 0.55), HORIZONTAL_ALIGNMENT_CENTER)
	var secs := int(r["time"])
	_text("버틴 시간 %d:%02d  ·  기지 HP %d/%d  ·  처치 %d" % [secs / 60, secs % 60, int(ceil(r["base_hp"])), int(r["base_hp_max"]), r["kills"]],
		Vector2(cx, box.position.y + 160), 36, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	var hs: Array = r["heroes"]
	var pw := box.size.x / 3.0
	for i in hs.size():
		var hr := Rect2(Vector2(box.position.x + i * pw + 20, box.position.y + 200), Vector2(pw - 40, box.size.y - 330))
		HeroPortrait.draw(self, hs[i]["type"], Rect2(hr.position, Vector2(hr.size.x, hr.size.y - 90)), "bust")
		_text("%s%s" % [GameData.person(hs[i]["type"]), " (나)" if hs[i]["player"] else ""], Vector2(hr.get_center().x, hr.end.y - 50), 34, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, true)
		_text("처치 %d" % hs[i]["kills"], Vector2(hr.get_center().x, hr.end.y - 12), 26, Color(0.85, 0.92, 1), HORIZONTAL_ALIGNMENT_CENTER)
	_text("AI 동료는 스스로 판단해 싸웠고, 작전과 이동은 내가 정했어요.", Vector2(cx, box.end.y - 40), 32, Color(1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER)


# ---------------- 도우미 ----------------

func _box(r: Rect2, fill: Color, border: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(16)
	draw_style_box(sb, r)


func _ease_back(x: float) -> float:
	var c1 := 1.70158
	return 1.0 + (c1 + 1.0) * pow(x - 1.0, 3) + c1 * pow(x - 1.0, 2)


func _text(t: String, pos: Vector2, fs: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, outline := false) -> void:
	var p := pos
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		p.x -= font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		p.x -= font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if outline:
		draw_string_outline(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(3, fs / 9), Color(0, 0, 0, 0.75 * col.a))
	draw_string(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
