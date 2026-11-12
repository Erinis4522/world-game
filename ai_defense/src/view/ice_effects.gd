class_name IceEffects
extends RefCounted
## 생성한 얼음 결정의 투명 PNG를 시전·비행·명중 연출에서 재사용한다.

const REGION := Rect2(416, 260, 416, 670)


static func draw_crystal(ci: CanvasItem, center: Vector2, height: float, angle: float, alpha: float) -> void:
	var tex := AssetManifest.texture("effects", "ice_cast")
	if tex == null or alpha <= 0.0:
		return
	var half := Vector2(height * REGION.size.x / REGION.size.y, height) * 0.5
	var points := PackedVector2Array()
	for corner in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
		points.append(center + corner.rotated(angle))
	var uv0 := REGION.position / tex.get_size()
	var uv1 := REGION.end / tex.get_size()
	ci.draw_polygon(points, PackedColorArray([Color(1, 1, 1, alpha)]),
		PackedVector2Array([uv0, Vector2(uv1.x, uv0.y), uv1, Vector2(uv0.x, uv1.y)]), tex)
