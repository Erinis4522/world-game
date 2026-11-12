class_name MapPicker
extends Control
## 터치 화면의 배치용 축소 지도. 자리(슬롯)를 누르면 신호를 보낸다.

signal slot_pressed(slot: int)

var controller: GameController
var _scale := 40.0
var _origin := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _layout() -> void:
	var W := float(GameData.config["map"]["width"])
	var H := float(GameData.config["map"]["height"])
	_scale = minf(size.x / W, size.y / H)
	_origin = (size - Vector2(W, H) * _scale) * 0.5


func w2s(p: Vector2) -> Vector2:
	return _origin + p * _scale


func _gui_input(event: InputEvent) -> void:
	var pos := Vector2.INF
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
	if pos == Vector2.INF:
		return
	_layout()
	var best := -1
	var bd := INF
	for i in GameData.slots.size():
		var d := w2s(GameData.slots[i]).distance_to(pos)
		if d < bd:
			bd = d
			best = i
	if best >= 0 and bd <= maxf(_scale * 0.9, 48.0):  # 손가락 터치 여유
		slot_pressed.emit(best)
		accept_event()


func _draw() -> void:
	_layout()
	MapArt.draw_ground(self,_origin,_scale)
	for slot in GameData.slots:
		MapArt.draw_slot(self,w2s(slot),_scale)
	var font := get_theme_default_font()
	var bp := w2s(GameData.path.end_point())
	draw_string_outline(font,bp+Vector2(-_scale*0.6,_scale*0.75),"기지",HORIZONTAL_ALIGNMENT_LEFT,-1,22,3,Color("24303b"))
	draw_string(font,bp+Vector2(-_scale*0.6,_scale*0.75),"기지",HORIZONTAL_ALIGNMENT_LEFT,-1,22,Color.WHITE)
	var used: Dictionary = {}
	for i in controller.team.size():
		var m: Dictionary = controller.team[i]
		if int(m["slot"]) >= 0:
			used[int(m["slot"])] = i
	# 지금 놓을 캐릭터의 사거리 미리보기
	for slot in used.keys():
		var m: Dictionary = controller.team[used[slot]]
		var r := float(GameData.hero(m["type"])["range"]) * _scale
		var col := PlaceholderArt.hero_color(m["type"])
		draw_circle(w2s(GameData.slots[slot]), r, Color(col.r, col.g, col.b, 0.12))
		draw_arc(w2s(GameData.slots[slot]), r, 0, TAU, 48, Color(col.r, col.g, col.b, 0.6), 2.0)
	for i in GameData.slots.size():
		var c := w2s(GameData.slots[i])
		if used.has(i):
			var idx: int = used[i]
			var m: Dictionary = controller.team[idx]
			if idx == controller.place_cursor:
				draw_circle(c, _scale * 0.75, Color(1, 0.85, 0.3, 0.5))
			PlaceholderArt.draw_hero(self, m["type"], c, _scale * 0.5, font)
		else:
			var t := str(i + 1)
			var sz := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 26)
			draw_string_outline(font,c+Vector2(-sz.x*0.5,9),t,HORIZONTAL_ALIGNMENT_LEFT,-1,26,3,Color("24303b"))
			draw_string(font, c + Vector2(-sz.x * 0.5, 9), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)
