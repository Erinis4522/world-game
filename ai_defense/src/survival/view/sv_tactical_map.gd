class_name SvTacticalMap
extends Control
## 터치 화면의 2D 전술 지도. 누른 곳으로 대표 캐릭터가 이동한다 (3D는 위 모니터에서만 그림).

signal map_pressed(world_pos: Vector2)

var controller: SvController
var _scale := 40.0
var _origin := Vector2.ZERO
var _press_fx: Array = []  # {pos, t}
var _now := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(delta: float) -> void:
	_now += delta
	queue_redraw()


func _layout() -> void:
	var sz := SvData.map_size()
	_scale = minf(size.x / sz.x, size.y / sz.y)
	_origin = (size - sz * _scale) * 0.5


func m2s(p: Vector2) -> Vector2:
	return _origin + p * _scale


func s2m(p: Vector2) -> Vector2:
	return (p - _origin) / _scale


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_layout()
		var m := s2m(event.position)
		var sz := SvData.map_size()
		if m.x < 0 or m.y < 0 or m.x > sz.x or m.y > sz.y:
			return
		_press_fx.append({"pos": m, "t": _now})
		map_pressed.emit(m)
		accept_event()


func _draw() -> void:
	_layout()
	var sz := SvData.map_size()
	draw_rect(Rect2(_origin, sz * _scale), Color("#9aa7b6"))
	for x in range(2, int(sz.x), 2):
		draw_line(m2s(Vector2(x, 0)), m2s(Vector2(x, sz.y)), Color(1, 1, 1, 0.12), 1.0)
	for y in range(2, int(sz.y), 2):
		draw_line(m2s(Vector2(0, y)), m2s(Vector2(sz.x, y)), Color(1, 1, 1, 0.12), 1.0)
	var font := get_theme_default_font()
	var st: SvState = controller.session.state if controller.session != null else null
	var grid: SvGrid = st.grid if st != null else null
	for o in SvData.cfg["map"]["obstacles"]:
		var r: Array = o["rect"]
		var col: Color = {"planter": Color("#5b9a55"), "crate": Color("#7f8a98"), "rock": Color("#6e737b")}.get(str(o.get("kind", "rock")), Color("#6e737b"))
		draw_rect(Rect2(m2s(Vector2(r[0], r[1])), Vector2(r[2], r[3]) * _scale), col)
	var bc := SvData.base_center()
	draw_circle(m2s(bc), _scale * 1.4, Color("#38e0d0"))
	draw_arc(m2s(bc), _scale * 1.4, 0, TAU, 32, Color.WHITE, 3.0)
	_label(font, "기지", m2s(bc) + Vector2(0, 8), 24)
	for g in SvData.cfg["map"]["gates"]:
		var gp := Vector2(float(g["pos"][0]), float(g["pos"][1]))
		draw_circle(m2s(gp), _scale * 0.7, Color("#9b4dff"))
		draw_arc(m2s(gp), _scale * 0.7, 0, TAU, 20, Color.WHITE, 2.0)
	if st == null:
		return
	for e in st.enemies:
		if not e.alive:
			continue
		var ecol := Color.from_string(str(GameData.enemy(e.type).get("color", "#48c9bd")), Color.TEAL)
		draw_circle(m2s(e.pos), maxf(6.0, e.radius * _scale * 1.1), Color(0.12, 0.13, 0.17))
		draw_circle(m2s(e.pos), maxf(4.0, e.radius * _scale * 0.7), ecol)
	for h in st.heroes:
		if not h.alive():
			continue
		var hp := m2s(h.pos)
		var hc := Color.from_string(str(GameData.hero(h.type).get("color", "#fff")), Color.WHITE)
		if h.is_player:
			if h.goal != Vector2.INF:
				draw_line(hp, m2s(h.goal), Color(1, 0.85, 0.3, 0.8), 3.0)
				draw_arc(m2s(h.goal), _scale * 0.35, 0, TAU, 16, Color(1, 0.85, 0.3), 3.0)
			draw_rect(Rect2(hp - Vector2.ONE * _scale * 0.82, Vector2.ONE * _scale * 1.64), Color(1, 0.85, 0.3))
		var tex := AssetManifest.portrait_texture(h.type)
		draw_rect(Rect2(hp - Vector2.ONE * _scale * 0.72, Vector2.ONE * _scale * 1.44), hc)
		if tex != null:
			HeroPortrait.draw(self, h.type, Rect2(hp - Vector2.ONE * _scale * 0.66, Vector2.ONE * _scale * 1.32), "head")
	for f in _press_fx:
		var k := (_now - float(f["t"])) / 0.5
		if k < 1.0:
			draw_arc(m2s(f["pos"]), _scale * (0.3 + 0.8 * k), 0, TAU, 20, Color(1, 1, 1, 1.0 - k), 3.0)
	var keep: Array = []
	for f in _press_fx:
		if _now - float(f["t"]) < 0.5:
			keep.append(f)
	_press_fx = keep


func _label(font: Font, t: String, p: Vector2, fs: int) -> void:
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string_outline(font, p - Vector2(w * 0.5, 0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.7))
	draw_string(font, p - Vector2(w * 0.5, 0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
