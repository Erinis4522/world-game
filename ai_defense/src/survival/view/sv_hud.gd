class_name SvHud
extends Control
## 일반 모니터의 3D 화면 위 2D 정보: 상단 바(마을 HP·시간·에너지), 미니맵, 머리 위 이름·체력, 말풍선,
## 안내 배너, 슬로모션·그림 해석 알림, 선택·작전 개시·결과 장면의 전신 원화.

var controller: SvController
var world: SvWorld3D
var font: Font
var now := 0.0
var banner_text := ""
var banner_until := 0.0
var _lineup_t0: Dictionary = {}
var fps_text := ""
var _fps_acc := 0.0
var _mini_bg: Image
var _mini_tex: ImageTexture

const C_PANEL := Color(0.07, 0.09, 0.13, 0.8)


func setup(c: SvController, w: SvWorld3D) -> void:
	controller = c
	world = w
	controller.battle_events.connect(_on_events)
	controller.phase_changed.connect(_on_phase)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = get_theme_default_font()
	_build_minimap_bg()


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
		fps_text = "FPS %d · 적 %d · 그리기 호출 %d" % [Engine.get_frames_per_second(), n,
			int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))]
	queue_redraw()


func _on_phase(p: String) -> void:
	if p == SvController.BATTLE:
		_banner("작전 개시! 마을로 오는 길을 지켜요", 2.2)


func _on_events(events: Array) -> void:
	for ev in events:
		match ev["type"]:
			"PHASE":
				if int(ev["index"]) > 0:
					_banner(str(ev["text"]), 2.4)
			"BUILD":
				_banner("든든이가 벽을 세웠어요!", 1.6)
			"ULT":
				_banner("%s의 %s!" % [SvData.person(ev["hero_type"]), ev["name"]], 1.8)
			"OUTCOME":
				_banner("마을을 지켜 냈어요!" if ev["outcome"] == "win" else "마을이 무너졌어요", 2.0)


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
	for e in st.enemies:
		if not e.alive or e.hp >= e.max_hp:
			continue
		var ep: Vector2 = e.prev_pos.lerp(e.pos, a)
		var hh := float(SvData.enemy(e.type).get("scale", 0.6)) * 2.6
		if not world.on_screen(ep, hh):
			continue
		var p := world.screen_pos(ep, hh)
		draw_rect(Rect2(p + Vector2(-22, 0), Vector2(44, 6)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(p + Vector2(-22, 0), Vector2(44 * e.hp / e.max_hp, 6)), Color(0.95, 0.3, 0.25))
	for h in st.heroes:
		if not h.alive():
			continue
		var hp2: Vector2 = h.prev_pos.lerp(h.pos, a)
		if not world.on_screen(hp2, 1.9):
			continue
		var p := world.screen_pos(hp2, 1.9)
		var name := "나" if h.role == "player" else SvData.person(h.type)
		var col := Color(1, 0.9, 0.4) if h.role == "player" else Color.WHITE
		_text(name, p + Vector2(0, -12), 18, col, HORIZONTAL_ALIGNMENT_CENTER, true)
		var r: float = h.hp / h.max_hp
		draw_rect(Rect2(p + Vector2(-30, -6), Vector2(60, 7)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(p + Vector2(-30, -6), Vector2(60 * r, 7)), Color(0.35, 0.9, 0.45) if r > 0.35 else Color(0.95, 0.4, 0.3))
	_draw_dialog(s)
	_draw_topbar(st)
	_draw_minimap(st)
	if banner_until > now:
		_draw_banner(banner_text)
	var y := 104.0
	for h in st.heroes:
		if not h.alive():
			var who2 := "나" if h.role == "player" else SvData.person(h.type)
			_text("%s 다시 일어나는 중… %d초" % [who2, int(ceil(h.down_t))], Vector2(size.x * 0.5, y), 26, Color(1, 0.7, 0.6), HORIZONTAL_ALIGNMENT_CENTER, true)
			y += 32
	match controller.overlay:
		"principle":
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.15, 0.3, 0.18))
			_text("시간이 느려졌어요 — 아래 터치 화면에서 %s의 행동 원칙을 골라요" % SvData.person(st.heroes[controller.overlay_hero].type),
				Vector2(size.x * 0.5, 150), 30, Color(0.85, 0.95, 1.0), HORIZONTAL_ALIGNMENT_CENTER, true)
		"sketch":
			draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.22))
			var msg := "잠깐 멈춤 — 아래 터치 화면에 그림을 그려요"
			if s.proposal.get("ok", false):
				msg = "AI 제안 미리보기: %s — 터치 화면에서 승인하면 실행돼요" % ("벽 %d칸" % s.proposal["cells"].size() if s.proposal["kind"] == "WALL" else s.proposal["name"])
			_text(msg, Vector2(size.x * 0.5, 150), 30, Color(1, 0.95, 0.7), HORIZONTAL_ALIGNMENT_CENTER, true)


func _draw_topbar(st: SvState) -> void:
	draw_rect(Rect2(0, 0, size.x, 72), C_PANEL)
	_text("마을", Vector2(22, 48), 30, Color.WHITE)
	var bx := 96.0
	var bw := 260.0
	draw_rect(Rect2(bx, 26, bw, 24), Color(0, 0, 0, 0.5))
	var r := st.base_hp / st.base_hp_max
	draw_rect(Rect2(bx, 26, bw * r, 24), Color(0.3, 0.85, 0.8) if r > 0.35 else Color(0.95, 0.35, 0.3))
	_text("%d" % int(ceil(st.base_hp)), Vector2(bx + bw + 12, 48), 28, Color.WHITE)
	var left := int(ceil(st.time_left()))
	_text("남은 시간 %d:%02d" % [left / 60, left % 60], Vector2(size.x * 0.42, 48), 36, Color(1, 0.93, 0.6), HORIZONTAL_ALIGNMENT_CENTER)
	_text("에너지 %d" % st.energy, Vector2(size.x * 0.62, 48), 32, Color(0.6, 0.95, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	_text("처치 %d" % st.kills, Vector2(size.x * 0.75, 48), 30, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)


func _build_minimap_bg() -> void:
	SvData.ensure_loaded()
	var g := SvGrid.from_config()
	_mini_bg = Image.create(g.w, g.h, false, Image.FORMAT_RGBA8)
	for j in g.h:
		for i in g.w:
			var c := Vector2i(i, j)
			var col := Color("#7dbb5a")
			if g.is_road(c):
				col = Color("#d2ad73")
			if g.kind.get(c, "") == "tree":
				col = Color("#3f7a35")
			elif g.kind.get(c, "") in ["building", "base", "townwall"]:
				col = Color("#9fb0c2")
			_mini_bg.set_pixel(i, j, col)
	_mini_tex = ImageTexture.create_from_image(_mini_bg)


func _draw_minimap(st: SvState) -> void:
	var sz := SvData.map_size()
	var h := 300.0
	var w := h * sz.x / sz.y

	var r := Rect2(Vector2(size.x - w - 16, 84), Vector2(w, h))
	draw_rect(r.grow(4), Color(0, 0, 0, 0.55))
	draw_texture_rect(_mini_tex, r, false)
	var k := w / sz.x
	for cell in st.grid.walls.keys():
		draw_rect(Rect2(r.position + Vector2(cell.x, cell.y) * k, Vector2(k, k)), Color("#6b5a48"))
	var bc := SvData.base_center()
	draw_circle(r.position + bc * k, 5, Color("#38e0d0"))
	for e in st.enemies:
		if e.alive:
			draw_circle(r.position + e.pos * k, 2.6, Color(0.9, 0.2, 0.2))
	for hh in st.heroes:
		if hh.alive():
			var col := Color.from_string(str(SvData.hero(hh.type).get("color", "#fff")), Color.WHITE)
			draw_circle(r.position + hh.pos * k, 5.0 if hh.role == "player" else 3.6, Color(1, 0.85, 0.3) if hh.role == "player" else col)
	var pp: Vector2 = r.position + st.player().pos * k
	var view := Rect2(pp - Vector2(12, 7) * k * 1.6, Vector2(24, 14) * k * 1.6).intersection(r)
	if view.has_area():
		draw_rect(view, Color(1, 1, 1, 0.6), false, 1.5)


func _bubble(anchor: Vector2, t: String) -> void:
	var fs := 26
	var sz := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var box := sz + Vector2(34, 24)
	var pos := anchor + Vector2(-box.x * 0.5, -box.y - 14)
	pos.x = clampf(pos.x, 10, size.x - box.x - 10)
	pos.y = clampf(pos.y, 80, size.y - box.y - 10)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.96)
	sb.border_color = Color(0.2, 0.2, 0.25)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(14)
	var tx := clampf(anchor.x, pos.x + 20, pos.x + box.x - 20)
	draw_colored_polygon(PackedVector2Array([Vector2(tx - 12, pos.y + box.y - 2), Vector2(tx + 12, pos.y + box.y - 2), Vector2(tx, pos.y + box.y + 12)]), Color(0.2, 0.2, 0.25))
	draw_style_box(sb, Rect2(pos, box))
	draw_string(font, pos + Vector2(17, 12 + fs * 0.85), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.1, 0.1, 0.15))


func _draw_banner(t: String) -> void:
	var fs := 48
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 80
	var r := Rect2(Vector2((size.x - w) * 0.5, size.y * 0.2), Vector2(w, 90))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.16, 0.85)
	sb.border_color = Color(1, 0.85, 0.3)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(16)
	draw_style_box(sb, r)
	_text(t, Vector2(size.x * 0.5, r.position.y + 62), fs, Color(1, 0.95, 0.7), HORIZONTAL_ALIGNMENT_CENTER)


func _draw_attract() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35))
	var cx := size.x * 0.5
	_text("AI 디펜스", Vector2(cx, size.y * 0.34), 120, Color(1, 0.92, 0.55), HORIZONTAL_ALIGNMENT_CENTER, true)
	_text("AI 동료들과 함께 마을로 오는 길을 지켜요!", Vector2(cx, size.y * 0.47), 46, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, true)
	var blink := 0.6 + 0.4 * sin(now * 3.0)
	_text("아래 터치 화면의 [시작]을 눌러 주세요", Vector2(cx, size.y * 0.78), 42, Color(1, 1, 0.6, blink), HORIZONTAL_ALIGNMENT_CENTER, true)
	_text("이 게임의 AI는 점수를 매겨 행동을 고르는 게임 AI와, 그림 좌표를 계산하는 규칙이에요. 스스로 학습하는 신경망이나 대화형 AI가 아니에요.",
		Vector2(cx, size.y - 30), 22, Color(0.95, 0.95, 0.95), HORIZONTAL_ALIGNMENT_CENTER, true)


func _draw_lineup() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.07, 0.11, 0.78))
	var sel: Array = controller.selected
	for k in _lineup_t0.keys():
		if not sel.has(k):
			_lineup_t0.erase(k)
	for t in sel:
		if not _lineup_t0.has(t):
			_lineup_t0[t] = now
	var cx := size.x * 0.5
	_text("함께 싸울 동료 (%d / 3)" % sel.size(), Vector2(cx, 92), 60, Color(1, 0.92, 0.55), HORIZONTAL_ALIGNMENT_CENTER, true)
	var sub := "고른 동료는 맵 곳곳의 길을 맡아 스스로 싸워요. 나와 건설 동료 '든든이'는 항상 함께 다녀요"
	if sel.size() == 3:
		sub = "팀 완성! 아래 터치 화면에서 [전투 시작]을 눌러요"
	_text(sub, Vector2(cx, 144), 28, Color(0.92, 0.92, 0.92), HORIZONTAL_ALIGNMENT_CENTER)
	var fw := minf(size.x * 0.28, 540.0)
	var fh := size.y - 230.0
	var gap := (size.x - fw * 3) / 4.0
	var roads: Array = SvData.zones()
	for i in 3:
		var r := Rect2(Vector2(gap + i * (fw + gap), 190), Vector2(fw, fh))
		var role: String = "%s 담당" % roads[i % roads.size()]["name"]
		if i >= sel.size():
			_box(r, Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.25))
			_text("?", r.get_center() + Vector2(0, 40), 160, Color(1, 1, 1, 0.2), HORIZONTAL_ALIGNMENT_CENTER)
			_text(role, Vector2(r.get_center().x, r.end.y - 36), 30, Color(1, 1, 1, 0.35), HORIZONTAL_ALIGNMENT_CENTER)
			continue
		var t: String = sel[i]
		var col := Color.from_string(str(GameData.hero(t).get("color", "#888")), Color.GRAY)
		var k := clampf((now - float(_lineup_t0[t])) / 0.5, 0.0, 1.0)
		var drop := (1.0 - _ease_back(k)) * -200.0
		_box(r, Color(col.r * 0.25, col.g * 0.25, col.b * 0.3, 0.92), col.lightened(0.2))
		HeroPortrait.draw(self, t, Rect2(r.position + Vector2(10, 10 + drop), Vector2(fw - 20, fh * 0.72)), "full", k)
		var ty := r.position.y + fh * 0.78
		_text(GameData.person(t), Vector2(r.get_center().x, ty + 30), 48, Color(1, 1, 1, k), HORIZONTAL_ALIGNMENT_CENTER, true)
		_text("%s · %s" % [GameData.hero(t)["name"], role], Vector2(r.get_center().x, ty + 76), 28, Color(0.85, 0.92, 1, k), HORIZONTAL_ALIGNMENT_CENTER)


func _draw_intro() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.05, 0.09, 0.85))
	var sel: Array = controller.selected
	var k := clampf(controller.phase_time / 0.7, 0.0, 1.0)
	var fw := size.x * 0.3
	for i in sel.size():
		var ki := clampf(k * 1.4 - i * 0.2, 0.0, 1.0)
		var x := size.x * (0.05 + i * 0.32) + (1.0 - _ease_back(ki)) * size.x
		HeroPortrait.draw(self, sel[i], Rect2(Vector2(x, size.y * 0.12), Vector2(fw, size.y * 0.78)), "full", ki)
	var a := clampf((controller.phase_time - 0.6) / 0.4, 0.0, 1.0)
	_text("작전 개시!", Vector2(size.x * 0.5, size.y * 0.55), 110, Color(1, 0.92, 0.55, a), HORIZONTAL_ALIGNMENT_CENTER, true)
	_text("조이스틱으로 움직이고, 든든이 얼굴을 눌러 그림을 그려 봐", Vector2(size.x * 0.5, size.y * 0.66), 36, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, true)


func _draw_result() -> void:
	var r: Dictionary = controller.result
	if r.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
	var box := Rect2(Vector2(size.x * 0.1, size.y * 0.1), Vector2(size.x * 0.8, size.y * 0.8))
	_box(box, Color(0.08, 0.1, 0.16, 0.95), Color(1, 0.85, 0.3))
	var cx := size.x * 0.5
	_text("마을을 지켜 냈어요!" if r["outcome"] == "win" else "끝까지 잘 싸웠어요!", Vector2(cx, box.position.y + 92), 66, Color(1, 0.92, 0.55), HORIZONTAL_ALIGNMENT_CENTER)
	var secs := int(r["time"])
	_text("버틴 시간 %d:%02d  ·  마을 HP %d  ·  처치 %d  ·  세운 벽 %d" % [secs / 60, secs % 60, int(ceil(r["base_hp"])), r["kills"], r["walls"]],
		Vector2(cx, box.position.y + 152), 34, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	var hs: Array = []
	for h in r["heroes"]:
		if h["role"] == "companion":
			hs.append(h)
	var pw := box.size.x / 3.0
	for i in hs.size():
		var hr := Rect2(Vector2(box.position.x + i * pw + 20, box.position.y + 190), Vector2(pw - 40, box.size.y - 320))
		HeroPortrait.draw(self, hs[i]["type"], Rect2(hr.position, Vector2(hr.size.x, hr.size.y - 90)), "bust")
		_text(GameData.person(hs[i]["type"]), Vector2(hr.get_center().x, hr.end.y - 50), 34, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, true)
		_text("처치 %d · %s" % [hs[i]["kills"], GameData.principle_name(hs[i]["principle"])], Vector2(hr.get_center().x, hr.end.y - 12), 24, Color(0.85, 0.92, 1), HORIZONTAL_ALIGNMENT_CENTER)
	_text("AI 동료는 스스로 판단해 싸웠고, 원칙·그림·승인은 내가 정했어요.", Vector2(cx, box.end.y - 40), 32, Color(1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER)


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


func _draw_dialog(s: SvSession) -> void:
	## 말풍선 대신 화면 아래 대화창: 최근 보고 3개 (초상화 + 이름 + 말). 오래된 것은 흐려짐
	var recent: Array = []
	for i in range(s.bubble_log.size() - 1, -1, -1):
		var b: Dictionary = s.bubble_log[i]
		if s.state.time - float(b["start"]) > 9.0:
			break
		recent.push_front(b)
		if recent.size() >= 3:
			break
	if recent.is_empty():
		return
	var row_h := 62.0
	var w := minf(size.x * 0.56, 1000.0)
	var box := Rect2(Vector2(16, size.y - 16 - row_h * recent.size() - 16), Vector2(w, row_h * recent.size() + 16))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.12, 0.78)
	sb.border_color = Color(1, 0.85, 0.3, 0.6)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	draw_style_box(sb, box)
	for i in recent.size():
		var b: Dictionary = recent[i]
		var age := s.state.time - float(b["start"])
		var a := clampf(1.0 - (age - 5.0) / 4.0, 0.35, 1.0)
		var h: SvState.SvHero = s.state.heroes[b["hero"]]
		var y := box.position.y + 8 + i * row_h
		var face := Rect2(Vector2(box.position.x + 10, y), Vector2(row_h - 8, row_h - 8))
		if h.type in ["PLAYER", "BUILDER"] or not HeroPortrait.draw(self, h.type, face, "head", a):
			SvFace.silhouette(self, h.type, face, "head", a)
		var who := "나" if h.role == "player" else SvData.person(h.type)
		var col := Color.from_string(str(SvData.hero(h.type).get("color", "#fff")), Color.WHITE).lightened(0.35)
		_text(who, Vector2(face.end.x + 12, y + 24), 22, Color(col.r, col.g, col.b, a))
		var newest := i == recent.size() - 1
		_text(str(b["text"]), Vector2(face.end.x + 12, y + 50), 26 if newest else 23, Color(1, 1, 1, a))
