class_name ChibiArt
extends RefCounted
## 그림 파일이 아직 없는 캐릭터용 '도형으로 그린 SD 인물'.
## data/heroes.json 의 look(피부·머리 모양·수염·안경·모자·옷 색)으로 그린다.
## 좌표: 발 = (0,0), 위쪽이 음수. 단위는 캐릭터 키(H). 호출 전에 애니메이션 변환이 적용되어 있다.
## 최종 그림(PNG/파츠 리그)이 들어오면 자동으로 그쪽이 쓰인다.

const SEG := 22


static func _c(look: Dictionary, key: String, def: String) -> Color:
	return Color.from_string(str(look.get(key, def)), Color.from_string(def, Color.GRAY))


static func _ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color, rot := 0.0) -> void:
	var pts := PackedVector2Array()
	for i in SEG:
		var a := TAU * i / SEG
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry).rotated(rot))
	ci.draw_colored_polygon(pts, col)


static func _poly(ci: CanvasItem, pts: Array, col: Color, H: float) -> void:
	var p := PackedVector2Array()
	for v in pts:
		p.append(Vector2(v[0], v[1]) * H)
	ci.draw_colored_polygon(p, col)


static func draw(ci: CanvasItem, type: String, H: float, alpha: float, pose_arm: float) -> bool:
	var d: Dictionary = GameData.hero(type)
	var look: Dictionary = d.get("look", {})
	if look.is_empty():
		return false
	var a := alpha
	var skin := _c(look, "skin", "#f3cfa8")
	var hair := _c(look, "hair", "#333333")
	var outfit := _c(look, "outfit", "#446688")
	var accent := _c(look, "accent", "#dddddd")
	var boots := _c(look, "boots", "#3a2a1c")
	var eyes := _c(look, "eyes", "#2a2a2a")
	skin.a = a; hair.a = a; outfit.a = a; accent.a = a; boots.a = a; eyes.a = a
	var line := Color(0.12, 0.1, 0.12, 0.9 * a)
	var elder: bool = look.get("elder", false)
	var wide := 1.15 if look.get("big", false) else 1.0
	var style := str(look.get("hair_style", "short"))
	var head_c := Vector2(0, -0.70) * H
	var head_r := 0.2 * H

	# ---- 뒷머리 (몸보다 뒤) ----
	match style:
		"long":
			_poly(ci, [[-0.21, -0.74], [0.21, -0.74], [0.24, -0.36], [-0.24, -0.36]], hair, H)
		"ponytail":
			_ellipse(ci, Vector2(0.22, -0.62) * H, 0.07 * H, 0.17 * H, hair, -0.35)
		"bun":
			_ellipse(ci, Vector2(0, -0.93) * H, 0.09 * H, 0.08 * H, hair)

	# ---- 다리·신발 ----
	for sx in [-1.0, 1.0]:
		ci.draw_rect(Rect2(Vector2(sx * 0.075 - 0.045, -0.27) * H, Vector2(0.09, 0.2) * H), outfit.darkened(0.35))
		_ellipse(ci, Vector2(sx * 0.08, -0.04) * H, 0.065 * H, 0.045 * H, boots)

	# ---- 몸통 ----
	var bw := 0.16 * wide
	_poly(ci, [[-bw, -0.5], [bw, -0.5], [bw + 0.04, -0.24], [-bw - 0.04, -0.24]], outfit, H)
	ci.draw_rect(Rect2(Vector2(-bw - 0.03, -0.32) * H, Vector2(bw * 2 + 0.06, 0.04) * H), accent.darkened(0.15))
	if elder:
		ci.draw_rect(Rect2(Vector2(-0.025, -0.5) * H, Vector2(0.05, 0.18) * H), accent)  # 조끼 단추줄 느낌

	# ---- 팔 (무기 팔은 공격 때 앞으로) ----
	var swing := clampf(pose_arm, -0.4, 1.0)
	var l_sh := Vector2(-bw - 0.01, -0.47) * H
	var r_sh := Vector2(bw + 0.01, -0.47) * H
	var l_hand := l_sh + Vector2(-0.04, 0.17).rotated(-0.2 * swing) * H
	var r_hand := r_sh + Vector2(0.05, 0.16).rotated(-1.1 * maxf(0.0, swing) + 0.3 * minf(0.0, swing)) * H
	ci.draw_line(l_sh, l_hand, outfit.darkened(0.1), 0.075 * H)
	ci.draw_line(r_sh, r_hand, outfit.darkened(0.1), 0.075 * H)

	# ---- 머리 ----
	if style != "bald_sides":
		_ellipse(ci, head_c + Vector2(0, -0.025 * H), head_r * 1.08, head_r * 1.02, hair)
		_ellipse(ci, head_c + Vector2(0, 0.025 * H), head_r * 0.9, head_r * 0.86, skin)
	else:
		_ellipse(ci, head_c, head_r, head_r * 0.97, skin)
		_ellipse(ci, head_c + Vector2(-0.19, 0.0) * H, 0.05 * H, 0.07 * H, hair)
		_ellipse(ci, head_c + Vector2(0.19, 0.0) * H, 0.05 * H, 0.07 * H, hair)
	ci.draw_arc(head_c, head_r * 1.05, 0, TAU, 28, Color(line.r, line.g, line.b, 0.35 * a), maxf(1.0, 0.008 * H))
	# 앞머리
	match style:
		"spiky":
			for i in 5:
				var x := -0.16 + i * 0.08
				_poly(ci, [[x - 0.05, -0.80], [x + 0.05, -0.80], [x + 0.01, -0.95 - 0.02 * (i % 2)]], hair, H)
			_poly(ci, [[-0.18, -0.80], [0.18, -0.80], [0.1, -0.72], [0.0, -0.76], [-0.1, -0.72]], hair, H)
		"messy":
			for i in 6:
				var ang := -PI * 0.9 + i * PI * 0.16
				_ellipse(ci, head_c + Vector2(cos(ang), sin(ang)) * head_r * 1.05, 0.05 * H, 0.035 * H, hair, ang)
			_poly(ci, [[-0.17, -0.79], [0.17, -0.79], [0.12, -0.71], [0.02, -0.75], [-0.08, -0.7]], hair, H)
		"bald_sides":
			pass
		_:
			_poly(ci, [[-0.18, -0.81], [0.18, -0.81], [0.15, -0.72], [0.05, -0.76], [-0.05, -0.72], [-0.15, -0.75]], hair, H)

	# ---- 얼굴 ----
	var ey := -0.67
	for sx in [-1.0, 1.0]:
		var ec := Vector2(sx * 0.075, ey) * H
		if elder:
			ci.draw_arc(ec, 0.025 * H, PI * 1.1, PI * 1.9, 8, line, maxf(1.5, 0.012 * H))
			ci.draw_line(ec + Vector2(-0.035, -0.045) * H, ec + Vector2(0.035, -0.05) * H, hair.lightened(0.2), maxf(2.0, 0.018 * H))
		else:
			_ellipse(ci, ec, 0.028 * H, 0.038 * H, eyes)
			ci.draw_circle(ec + Vector2(-0.008, -0.012) * H, 0.01 * H, Color(1, 1, 1, a))
	_ellipse(ci, Vector2(-0.12, -0.61) * H, 0.03 * H, 0.016 * H, Color(1.0, 0.55, 0.55, 0.35 * a))
	_ellipse(ci, Vector2(0.12, -0.61) * H, 0.03 * H, 0.016 * H, Color(1.0, 0.55, 0.55, 0.35 * a))
	ci.draw_arc(Vector2(0, -0.615) * H, 0.025 * H, 0.2, PI - 0.2, 8, line, maxf(1.0, 0.01 * H))

	match str(look.get("beard", "")):
		"full":
			_poly(ci, [[-0.15, -0.62], [0.15, -0.62], [0.11, -0.5], [0.0, -0.45], [-0.11, -0.5]], hair, H)
			_ellipse(ci, Vector2(-0.04, -0.6) * H, 0.05 * H, 0.018 * H, hair)
			_ellipse(ci, Vector2(0.04, -0.6) * H, 0.05 * H, 0.018 * H, hair)
		"stubble":
			_ellipse(ci, Vector2(0, -0.585) * H, 0.12 * H, 0.05 * H, Color(0.1, 0.08, 0.08, 0.28 * a))

	match str(look.get("glasses", "")):
		"monocle":
			var mc := Vector2(0.075, ey) * H
			ci.draw_arc(mc, 0.045 * H, 0, TAU, 16, Color(0.85, 0.7, 0.25, a), maxf(1.5, 0.012 * H))
			ci.draw_line(mc + Vector2(0.04, 0.02) * H, Vector2(0.12, -0.45) * H, Color(0.85, 0.7, 0.25, 0.8 * a), maxf(1.0, 0.006 * H))
		"goggles":
			ci.draw_line(Vector2(-0.2, -0.79) * H, Vector2(0.2, -0.79) * H, Color(0.25, 0.2, 0.15, a), 0.03 * H)
			for sx in [-1.0, 1.0]:
				ci.draw_circle(Vector2(sx * 0.07, -0.8) * H, 0.045 * H, Color(0.45, 0.32, 0.18, a))
				ci.draw_circle(Vector2(sx * 0.07, -0.8) * H, 0.032 * H, Color(0.6, 0.85, 0.95, a))

	match str(look.get("hat", "")):
		"captain":
			_poly(ci, [[-0.17, -0.84], [0.17, -0.84], [0.15, -0.95], [-0.15, -0.95]], Color(0.12, 0.16, 0.25, a), H)
			_poly(ci, [[-0.2, -0.84], [0.22, -0.84], [0.25, -0.8], [-0.2, -0.81]], Color(0.08, 0.08, 0.1, a), H)
			ci.draw_circle(Vector2(0, -0.9) * H, 0.022 * H, Color(0.9, 0.75, 0.3, a))
		"bandana":
			_poly(ci, [[-0.2, -0.84], [0.2, -0.84], [0.19, -0.77], [-0.19, -0.77]], Color(0.75, 0.15, 0.12, a), H)
			_poly(ci, [[0.19, -0.81], [0.28, -0.86], [0.27, -0.74]], Color(0.75, 0.15, 0.12, a), H)
		"headscarf":
			_poly(ci, [[-0.22, -0.78], [0.22, -0.78], [0.16, -0.92], [0.0, -0.96], [-0.16, -0.92]], Color(0.55, 0.62, 0.35, a), H)
		"beret":
			_ellipse(ci, Vector2(-0.03, -0.88) * H, 0.2 * H, 0.07 * H, Color(0.15, 0.12, 0.18, a), -0.15)

	# ---- 직업 소품 (오른손 / 왼손) ----
	_draw_prop(ci, type, H, a, l_hand, r_hand, swing)
	return true


static func _draw_prop(ci: CanvasItem, type: String, H: float, a: float, lh: Vector2, rh: Vector2, swing: float) -> void:
	var w := maxf(2.0, 0.025 * H)
	match type:
		"SWORD":
			ci.draw_circle(lh + Vector2(-0.02, 0.0) * H, 0.1 * H, Color(0.72, 0.74, 0.8, a))
			ci.draw_arc(lh + Vector2(-0.02, 0.0) * H, 0.1 * H, 0, TAU, 20, Color(0.35, 0.36, 0.42, a), w * 0.6)
			var dir := Vector2(0.35, -1.0).rotated(1.6 * maxf(0.0, swing)).normalized()
			ci.draw_line(rh, rh + dir * 0.32 * H, Color(0.9, 0.92, 0.96, a), w)
			ci.draw_line(rh - dir.orthogonal() * 0.04 * H, rh + dir.orthogonal() * 0.04 * H, Color(0.45, 0.32, 0.18, a), w)
		"ARCHER":
			ci.draw_arc(rh + Vector2(0.02, -0.06) * H, 0.2 * H, -PI * 0.45, PI * 0.45, 14, Color(0.55, 0.35, 0.15, a), w)
		"SNIPER":
			var s := rh + Vector2(-0.12, 0.02) * H
			var e := rh + Vector2(0.28, -0.12) * H
			ci.draw_line(s, e, Color(0.38, 0.27, 0.16, a), w * 1.6)
			ci.draw_line(e + Vector2(-0.04, -0.07) * H, e + Vector2(-0.04, 0.07) * H, Color(0.3, 0.22, 0.14, a), w)
			ci.draw_rect(Rect2(rh + Vector2(0.02, -0.11) * H, Vector2(0.1, 0.03) * H), Color(0.15, 0.15, 0.18, a))
		"FIRE":
			var top := rh + Vector2(0.06, -0.22) * H
			ci.draw_line(rh + Vector2(0, 0.04) * H, top, Color(0.42, 0.28, 0.16, a), w)
			ci.draw_rect(Rect2(top + Vector2(-0.07, -0.05) * H, Vector2(0.14, 0.08) * H), Color(0.3, 0.3, 0.34, a))
			var f := top + Vector2(0, -0.08) * H
			ci.draw_colored_polygon(PackedVector2Array([f + Vector2(0, -0.1) * H, f + Vector2(0.05, 0.02) * H, f + Vector2(-0.05, 0.02) * H]), Color(1.0, 0.5, 0.1, a))
		"ICE":
			var top2 := rh + Vector2(0.03, -0.42) * H
			ci.draw_line(rh + Vector2(0, 0.1) * H, top2, Color(0.5, 0.4, 0.3, a), w)
			ci.draw_colored_polygon(PackedVector2Array([top2 + Vector2(0, -0.08) * H, top2 + Vector2(0.04, 0) * H, top2 + Vector2(0, 0.06) * H, top2 + Vector2(-0.04, 0) * H]), Color(0.6, 0.9, 1.0, a))
		"LIGHTNING":
			var top3 := rh + Vector2(0.03, -0.36) * H
			ci.draw_line(rh + Vector2(0, 0.08) * H, top3, Color(0.35, 0.3, 0.45, a), w)
			ci.draw_circle(top3, 0.04 * H, Color(0.9, 0.85, 0.4, a))
			ci.draw_polyline(PackedVector2Array([top3 + Vector2(0.03, -0.03) * H, top3 + Vector2(0.09, -0.08) * H, top3 + Vector2(0.06, -0.1) * H, top3 + Vector2(0.12, -0.16) * H]), Color(1.0, 0.95, 0.4, a), w * 0.7)
		"BOMB":
			ci.draw_circle(rh + Vector2(0.03, -0.02) * H, 0.075 * H, Color(0.12, 0.12, 0.14, a))
			ci.draw_line(rh + Vector2(0.06, -0.08) * H, rh + Vector2(0.1, -0.13) * H, Color(0.8, 0.6, 0.3, a), w * 0.6)
			ci.draw_circle(rh + Vector2(0.105, -0.14) * H, 0.02 * H, Color(1.0, 0.6, 0.1, a))
		"MARK":
			ci.draw_rect(Rect2(rh + Vector2(-0.04, -0.12) * H, Vector2(0.1, 0.13) * H), Color(0.35, 0.22, 0.45, a))
			ci.draw_circle(rh + Vector2(0.01, -0.06) * H, 0.025 * H, Color(1.0, 0.9, 0.4, a))
