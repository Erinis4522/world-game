class_name SvFace
extends Control
## 캐릭터 얼굴·원화. 원화가 없는 인물(나, 건설 동료 든든이)은 실루엣으로 그린다 (원화가 생기면 교체).

var hero_type := "SWORD"
var dim := false
var mode := "head"


func _init(t: String = "SWORD", px: float = 120.0, m := "head") -> void:
	hero_type = t
	mode = m
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var a := 0.4 if dim else 1.0
	if hero_type in ["PLAYER", "BUILDER"] or not HeroPortrait.draw(self, hero_type, Rect2(Vector2.ZERO, size), mode, a):
		silhouette(self, hero_type, Rect2(Vector2.ZERO, size), mode, a)


static func silhouette(ci: CanvasItem, type: String, r: Rect2, mode: String, a: float) -> void:
	## 임시 실루엣: 어두운 사람 모양 + 역할 색 테두리
	var col := Color.from_string(str(SvData.hero(type).get("color", "#888")), Color.GRAY)
	ci.draw_rect(r, Color(col.r * 0.35, col.g * 0.35, col.b * 0.4, a))
	var dark := Color(0.08, 0.09, 0.12, a)
	var c := r.get_center()
	var s := minf(r.size.x, r.size.y)
	if mode == "full":
		var head := Vector2(c.x, r.position.y + r.size.y * 0.2)
		var hr := r.size.y * 0.085
		ci.draw_circle(head, hr, dark)
		ci.draw_colored_polygon(PackedVector2Array([
			head + Vector2(-hr * 1.9, hr * 1.4), head + Vector2(hr * 1.9, hr * 1.4),
			head + Vector2(hr * 1.6, r.size.y * 0.45), head + Vector2(hr * 0.9, r.size.y * 0.75),
			head + Vector2(-hr * 0.9, r.size.y * 0.75), head + Vector2(-hr * 1.6, r.size.y * 0.45)]), dark)
		if type == "BUILDER":
			ci.draw_line(head + Vector2(hr * 2.2, hr * 1.2), head + Vector2(hr * 3.4, r.size.y * 0.42), dark, hr * 0.35)
			ci.draw_rect(Rect2(head + Vector2(hr * 2.6, hr * 0.6), Vector2(hr * 1.6, hr * 1.0)), dark)
	else:
		var head2 := Vector2(c.x, r.position.y + r.size.y * 0.42)
		var hr2 := s * 0.2
		ci.draw_circle(head2, hr2, dark)
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(c.x - s * 0.42, r.end.y), Vector2(c.x - s * 0.3, head2.y + hr2 * 1.1),
			Vector2(c.x + s * 0.3, head2.y + hr2 * 1.1), Vector2(c.x + s * 0.42, r.end.y)]), dark)
	var f: Font = ci.get_theme_default_font()
	var fs := int(s * (0.18 if mode != "full" else 0.08))
	var q := "?"
	var w: float = f.get_string_size(q, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string(f, Vector2(c.x - w * 0.5, r.position.y + r.size.y * (0.47 if mode != "full" else 0.23)), q, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col.r, col.g, col.b, 0.8 * a))
	ci.draw_rect(r, Color(col.r, col.g, col.b, 0.9 * a), false, 3.0)
