class_name MapPath
extends RefCounted
## 미리 정한 단일 경로. 적은 경로 위의 이동 거리(dist)만 가진다. (A* 등 길찾기 없음)

var points: PackedVector2Array = PackedVector2Array()
var cumulative: PackedFloat64Array = PackedFloat64Array()
var length := 0.0


func _init(raw: Array) -> void:
	for p in raw:
		points.append(Vector2(float(p[0]), float(p[1])))
	cumulative.append(0.0)
	for i in range(1, points.size()):
		cumulative.append(cumulative[i - 1] + points[i - 1].distance_to(points[i]))
	length = cumulative[cumulative.size() - 1]


func pos_at(d: float) -> Vector2:
	if d <= 0.0:
		return points[0]
	if d >= length:
		return points[points.size() - 1]
	for i in range(1, points.size()):
		if d <= cumulative[i]:
			var seg := cumulative[i] - cumulative[i - 1]
			var t := 0.0 if seg <= 0.0 else (d - cumulative[i - 1]) / seg
			return points[i - 1].lerp(points[i], t)
	return points[points.size() - 1]


func distance_to_path(p: Vector2) -> float:
	var best := INF
	for i in range(1, points.size()):
		var c := Geometry2D.get_closest_point_to_segment(p, points[i - 1], points[i])
		best = minf(best, c.distance_to(p))
	return best


func end_point() -> Vector2:
	return points[points.size() - 1]
