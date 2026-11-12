class_name SvJoystick
extends Control
## 스마트폰 게임식 가상 조이스틱. 누른 채 끌면 그 방향·세기(0~1)로 대표 캐릭터가 움직인다.
## 화면 위쪽 = 지도 북쪽 (3D 카메라도 북쪽을 보고 있어 방향이 같다).

signal moved(v: Vector2)

var value := Vector2.ZERO
var _dragging := false
var _last_sent := Vector2(99, 99)
var _send_t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _radius() -> float:
	return minf(size.x, size.y) * 0.42


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			_update(event.position)
		else:
			value = Vector2.ZERO
			_emit(true)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_update(event.position)
		accept_event()


func _update(p: Vector2) -> void:
	var v := (p - size * 0.5) / _radius()
	value = v.limit_length(1.0)
	_emit(false)


func _emit(force: bool) -> void:
	if force or value.distance_to(_last_sent) > 0.06:
		_last_sent = value
		moved.emit(value)


func _process(delta: float) -> void:
	_send_t += delta
	if _dragging and _send_t > 0.25:
		_send_t = 0.0
		moved.emit(value)  # 손을 가만히 대고 있어도 주기적으로 다시 보냄 (명령 유실 대비)
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := _radius()
	draw_circle(c, r, Color(1, 1, 1, 0.08))
	draw_arc(c, r, 0, TAU, 64, Color(1, 1, 1, 0.5), 4.0, true)
	for i in 4:
		var d := Vector2.from_angle(i * PI * 0.5 - PI * 0.5)
		var tip := c + d * (r - 18)
		draw_colored_polygon(PackedVector2Array([tip, tip - d * 22 + d.orthogonal() * 14, tip - d * 22 - d.orthogonal() * 14]), Color(1, 1, 1, 0.35))
	var knob := c + value * r
	draw_circle(knob, r * 0.36, Color(1, 0.85, 0.3, 0.9 if _dragging else 0.65))
	draw_arc(knob, r * 0.36, 0, TAU, 40, Color.WHITE, 4.0, true)
	var f := get_theme_default_font()
	var t := "끌어서 이동"
	var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	draw_string(f, c + Vector2(-w * 0.5, r + 46), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 1, 1, 0.7))
