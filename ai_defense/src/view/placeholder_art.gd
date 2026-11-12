class_name PlaceholderArt
extends RefCounted
## 임시 도형 그림. PNG가 있으면 그 그림을, 없으면 도형을 그린다.
## 색만 다른 원이 아니라 캐릭터마다 소품 모양(방패·활·석궁·불꽃·눈송이·번개·폭탄·별)을 다르게 한다.


static func hero_color(type: String) -> Color:
	return Color.from_string(str(GameData.hero(type).get("color", "#888888")), Color.GRAY)


static func enemy_color(type: String) -> Color:
	return Color.from_string(str(GameData.enemy(type).get("color", "#88cc66")), Color.GREEN)


static func draw_hero(ci: CanvasItem, type: String, center: Vector2, radius: float, font: Font, alpha := 1.0) -> void:
	## center = 캐릭터 중심(발 위치보다 radius만큼 위). radius = 몸통 반지름(px)
	if HeroSprite.draw_static(ci, type, center + Vector2(0, radius * 1.15), radius * 3.0, alpha):
		return  # 그림(PNG/파츠 리그)이 있으면 그것으로
	var col := hero_color(type)
	col.a = alpha
	var dark := col.darkened(0.45)
	ci.draw_set_transform(center + Vector2(0, radius * 0.95), 0.0, Vector2(1.0, 0.35))
	ci.draw_circle(Vector2.ZERO, radius * 0.95, Color(0, 0, 0, 0.25 * alpha))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	ci.draw_circle(center, radius, col)
	ci.draw_arc(center, radius, 0, TAU, 32, dark, maxf(2.0, radius * 0.1), true)
	_draw_prop(ci, type, center, radius, alpha)
	if font != null:
		var fs := int(radius * 0.95)
		var glyph := str(GameData.hero(type).get("glyph", "?"))
		var sz := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		ci.draw_string_outline(font, center + Vector2(-sz.x * 0.5, fs * 0.36), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, fs / 8), Color(0, 0, 0, 0.6 * alpha))
		ci.draw_string(font, center + Vector2(-sz.x * 0.5, fs * 0.36), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, alpha))


static func _draw_prop(ci: CanvasItem, type: String, c: Vector2, r: float, a: float) -> void:
	var w := maxf(2.0, r * 0.14)
	var p := c + Vector2(r * 0.85, -r * 0.75)  # 오른쪽 위 소품 위치
	match type:
		"SWORD":
			ci.draw_circle(c + Vector2(-r * 0.9, r * 0.1), r * 0.42, Color(0.75, 0.75, 0.8, a))
			ci.draw_arc(c + Vector2(-r * 0.9, r * 0.1), r * 0.42, 0, TAU, 20, Color(0.3, 0.3, 0.35, a), w * 0.6)
			ci.draw_line(c + Vector2(r * 0.5, r * 0.2), p + Vector2(r * 0.25, -r * 0.3), Color(0.92, 0.92, 0.95, a), w)
			ci.draw_line(c + Vector2(r * 0.35, -r * 0.05), c + Vector2(r * 0.85, r * 0.35), Color(0.5, 0.35, 0.2, a), w)
		"ARCHER":
			ci.draw_arc(c + Vector2(r * 0.75, -r * 0.1), r * 0.75, -PI * 0.45, PI * 0.45, 16, Color(0.55, 0.35, 0.15, a), w)
			ci.draw_line(c + Vector2(r * 0.75, -r * 0.1) + Vector2.from_angle(-PI * 0.45) * r * 0.75,
				c + Vector2(r * 0.75, -r * 0.1) + Vector2.from_angle(PI * 0.45) * r * 0.75, Color(0.95, 0.95, 0.9, a), w * 0.4)
		"SNIPER":
			ci.draw_line(c + Vector2(-r * 0.4, r * 0.3), c + Vector2(r * 1.5, -r * 0.6), Color(0.35, 0.25, 0.15, a), w * 1.3)
			ci.draw_arc(c + Vector2(-r * 0.3, -r * 0.25), r * 0.22, 0, TAU, 14, Color(0.95, 0.85, 0.3, a), w * 0.5)
		"FIRE":
			var pts := PackedVector2Array([p + Vector2(0, -r * 0.7), p + Vector2(r * 0.35, r * 0.1), p + Vector2(0, r * 0.3), p + Vector2(-r * 0.35, r * 0.1)])
			ci.draw_colored_polygon(pts, Color(1.0, 0.45, 0.1, a))
			ci.draw_circle(p + Vector2(0, r * 0.05), r * 0.15, Color(1.0, 0.9, 0.3, a))
		"ICE":
			for i in 3:
				var d := Vector2.from_angle(PI * i / 3.0) * r * 0.45
				ci.draw_line(p - d, p + d, Color(0.85, 0.97, 1.0, a), w * 0.7)
		"LIGHTNING":
			var z := PackedVector2Array([p + Vector2(-r * 0.1, -r * 0.6), p + Vector2(r * 0.25, -r * 0.1), p + Vector2(-r * 0.1, 0), p + Vector2(r * 0.2, r * 0.55)])
			ci.draw_polyline(z, Color(1.0, 0.95, 0.4, a), w)
		"BOMB":
			ci.draw_circle(p + Vector2(0, r * 0.1), r * 0.38, Color(0.12, 0.12, 0.14, a))
			ci.draw_line(p + Vector2(r * 0.15, -r * 0.2), p + Vector2(r * 0.35, -r * 0.5), Color(0.8, 0.6, 0.3, a), w * 0.6)
			ci.draw_circle(p + Vector2(r * 0.37, -r * 0.55), r * 0.1, Color(1.0, 0.6, 0.1, a))
			ci.draw_rect(Rect2(c + Vector2(-r * 0.6, -r * 0.55), Vector2(r * 1.2, r * 0.22)), Color(0.2, 0.2, 0.2, 0.7 * a))
		"MARK":
			var star := PackedVector2Array()
			for i in 10:
				var rr := r * (0.5 if i % 2 == 0 else 0.22)
				star.append(p + Vector2.from_angle(-PI / 2 + PI * i / 5.0) * rr)
			ci.draw_colored_polygon(star, Color(1.0, 0.95, 0.5, a))


static func draw_enemy(ci: CanvasItem, type: String, center: Vector2, radius: float, alpha := 1.0) -> void:
	var tex := AssetManifest.enemy_texture(type)
	if tex != null:
		var side := radius * 2.6
		var feet := center + Vector2(0, radius)
		ci.draw_texture_rect(tex, Rect2(feet - Vector2(side * 0.5, side), Vector2(side, side)), false, Color(1, 1, 1, alpha))
		return
	var col := enemy_color(type)
	col.a = alpha
	ci.draw_set_transform(center + Vector2(0, radius * 0.85), 0.0, Vector2(1.0, 0.3))
	ci.draw_circle(Vector2.ZERO, radius, Color(0, 0, 0, 0.25 * alpha))
	ci.draw_set_transform(center, 0.0, Vector2(1.08, 0.88))
	ci.draw_circle(Vector2.ZERO, radius, col)
	ci.draw_arc(Vector2.ZERO, radius, 0, TAU, 24, col.darkened(0.45), maxf(1.5, radius * 0.1), true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var eye := radius * 0.17
	ci.draw_circle(center + Vector2(-radius * 0.32, -radius * 0.1), eye, Color(1, 1, 1, alpha))
	ci.draw_circle(center + Vector2(radius * 0.32, -radius * 0.1), eye, Color(1, 1, 1, alpha))
	ci.draw_circle(center + Vector2(-radius * 0.28, -radius * 0.08), eye * 0.55, Color(0, 0, 0, alpha))
	ci.draw_circle(center + Vector2(radius * 0.36, -radius * 0.08), eye * 0.55, Color(0, 0, 0, alpha))
	match type:
		"FAST":
			for i in 3:
				var y := -radius * 0.4 + i * radius * 0.4
				ci.draw_line(center + Vector2(-radius * 1.2, y), center + Vector2(-radius * 1.75, y), Color(1, 1, 1, 0.7 * alpha), maxf(1.5, radius * 0.12))
		"ARMORED":
			ci.draw_rect(Rect2(center + Vector2(-radius * 0.95, -radius * 0.75), Vector2(radius * 1.9, radius * 0.3)), Color(0.45, 0.5, 0.58, alpha))
			ci.draw_rect(Rect2(center + Vector2(-radius * 0.15, -radius * 1.0), Vector2(radius * 0.3, radius * 0.35)), Color(0.45, 0.5, 0.58, alpha))
		"BOSS":
			var crown := PackedVector2Array([
				center + Vector2(-radius * 0.5, -radius * 0.7), center + Vector2(-radius * 0.55, -radius * 1.2),
				center + Vector2(-radius * 0.2, -radius * 0.9), center + Vector2(0, -radius * 1.3),
				center + Vector2(radius * 0.2, -radius * 0.9), center + Vector2(radius * 0.55, -radius * 1.2),
				center + Vector2(radius * 0.5, -radius * 0.7)])
			ci.draw_colored_polygon(crown, Color(1.0, 0.82, 0.2, alpha))
