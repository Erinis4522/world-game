class_name SvSketchPad
extends Control
## 그림 칸. 한 번에 한 획을 그린다 (다시 누르면 새로 그림). 위쪽 = 지도 북쪽.

signal stroke_finished(points: PackedVector2Array)

var points := PackedVector2Array()
var _drawing := false
var locked := false  # AI 제안을 보는 동안은 그리기 막음


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func clear() -> void:
	points = PackedVector2Array()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if locked:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drawing = true
			points = PackedVector2Array([event.position])
		else:
			_drawing = false
			if points.size() >= 2:
				stroke_finished.emit(points)
		queue_redraw()
		accept_event()
	elif event is InputEventMouseMotion and _drawing:
		if points.is_empty() or points[points.size() - 1].distance_to(event.position) > 3.0:
			points.append(event.position)
			queue_redraw()
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#f6f1e4"))
	for x in range(0, int(size.x), 60):
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0, 0, 0, 0.05), 1.0)
	for y in range(0, int(size.y), 60):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0, 0, 0, 0.05), 1.0)
	var f := get_theme_default_font()
	draw_string(f, Vector2(16, 34), "↑ 북쪽", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0, 0, 0, 0.35))
	if points.size() >= 2:
		draw_polyline(points, Color("#2b3550"), 9.0, true)
		draw_circle(points[0], 7, Color("#2b3550"))
	elif points.is_empty():
		var t := "여기에 손가락으로 그려요"
		var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
		draw_string(f, size * 0.5 - Vector2(w * 0.5, 0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(0, 0, 0, 0.25))
	draw_rect(Rect2(Vector2.ZERO, size), Color("#2b3550"), false, 4.0)
