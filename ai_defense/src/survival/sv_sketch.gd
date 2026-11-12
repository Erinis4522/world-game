class_name SvSketch
extends RefCounted
## 손그림 해석 (좌표·선분 기반 규칙, 신경망 아님).
##  1) 같은 간격으로 다시 찍기  2) 꺾인 곳 찾기(RDP 단순화)  3) 닫힘·꺾임 수·방향 바뀜으로 분류
## 결과 kind:
##   LINE     — 열린 선: 직선 / ㄱ자 / U자 / 곡선 → 벽 건설
##   CIRCLE   — 닫힌 둥근 모양 → 동료 1 필살기
##   TRIANGLE — 닫힌 세모 → 동료 2 필살기
##   ZIGZAG   — 지그재그(번개 모양) → 동료 3 필살기
##   UNKNOWN  — 너무 짧거나 해석 불가
## 애매하면 ambiguous=true와 후보(choices)를 돌려주고, 확정은 학생이 한다.


static func resample(pts: PackedVector2Array, n := 48) -> PackedVector2Array:
	var out := PackedVector2Array()
	if pts.size() < 2:
		return pts
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	if total <= 0.0:
		return pts
	var step := total / float(n - 1)
	out.append(pts[0])
	var acc := 0.0
	var prev := pts[0]
	var i := 1
	while i < pts.size():
		var cur := pts[i]
		var d := prev.distance_to(cur)
		if acc + d >= step and d > 0.0:
			var t := (step - acc) / d
			var q := prev.lerp(cur, t)
			out.append(q)
			prev = q
			acc = 0.0
		else:
			acc += d
			prev = cur
			i += 1
	while out.size() < n:
		out.append(pts[pts.size() - 1])
	return out


static func rdp(pts: PackedVector2Array, eps: float) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var a := pts[0]
	var b := pts[pts.size() - 1]
	var idx := -1
	var dmax := 0.0
	for i in range(1, pts.size() - 1):
		var d := Geometry2D.get_closest_point_to_segment(pts[i], a, b).distance_to(pts[i])
		if d > dmax:
			dmax = d
			idx = i
	if dmax <= eps or idx < 0:
		return PackedVector2Array([a, b])
	var left := rdp(pts.slice(0, idx + 1), eps)
	var right := rdp(pts.slice(idx), eps)
	var out := left.slice(0, left.size() - 1)
	out.append_array(right)
	return out


static func analyze(raw: PackedVector2Array) -> Dictionary:
	var r := {"kind": "UNKNOWN", "shape": "", "confidence": 0.0, "ambiguous": false, "choices": [], "simplified": PackedVector2Array(), "reason": ""}
	if raw.size() < 4:
		r["reason"] = "너무 짧아서 모양을 알 수 없어요"
		return r
	var pts := resample(raw, 48)
	var length := 0.0
	for i in range(1, pts.size()):
		length += pts[i - 1].distance_to(pts[i])
	var bb := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		bb = bb.expand(p)
	var diag := maxf(bb.size.length(), 1.0)
	if length < 60.0 or diag < 40.0:
		r["reason"] = "너무 작게 그렸어요. 조금 더 크게 그려 줘"
		return r
	var gap := pts[0].distance_to(pts[pts.size() - 1])
	var closure := gap / length  # 작을수록 닫힘
	# 방향 변화
	var sharp := 0
	var signs: Array = []
	var total_turn := 0.0
	for i in range(2, pts.size(), 2):
		var d1 := (pts[i - 1] - pts[i - 2])
		var d2 := (pts[i] - pts[i - 1])
		if d1.length() < 0.01 or d2.length() < 0.01:
			continue
		var ang := d1.angle_to(d2)
		total_turn += ang
		if absf(ang) > deg_to_rad(50):
			sharp += 1
	var simp := rdp(pts, diag * 0.08)
	var corners: Array = []  # 내부 꼭짓점의 꺾임 각
	for i in range(1, simp.size() - 1):
		var a := (simp[i] - simp[i - 1]).angle_to(simp[i + 1] - simp[i])
		if absf(a) > deg_to_rad(35):
			corners.append(a)
	var alternations := 0
	for i in range(1, corners.size()):
		if signf(corners[i]) != signf(corners[i - 1]):
			alternations += 1
	r["simplified"] = simp
	r["metrics"] = {"length": length, "closure": closure, "corners": corners.size(), "alternations": alternations,
		"total_turn_deg": rad_to_deg(total_turn)}
	# ---- 닫힌 모양 ----
	if closure < 0.14:
		var n := corners.size()
		if n <= 1 or (n >= 5 and alternations <= 1):
			return _result(r, "CIRCLE", "동그라미", 0.85)
		if n == 2 or n == 3:
			return _result(r, "TRIANGLE", "세모", 0.8)
		r["ambiguous"] = true
		r["choices"] = ["TRIANGLE", "CIRCLE"]
		r["reason"] = "꼭짓점이 %d개라 세모인지 동그라미인지 헷갈려요" % n
		return _result(r, "TRIANGLE", "세모?", 0.45)
	if closure < 0.26:
		r["ambiguous"] = true
		r["choices"] = ["CIRCLE", "LINE"] if corners.size() <= 1 else ["TRIANGLE", "LINE"]
		r["reason"] = "끝이 거의 붙어 있어서 닫힌 모양인지 선인지 헷갈려요"
		return _result(r, r["choices"][0], "닫힌 모양?", 0.45)
	# ---- 열린 모양 ----
	if corners.size() >= 3 and alternations >= 2:
		return _result(r, "ZIGZAG", "번개 모양", 0.8)
	if corners.size() == 2 and alternations == 1:
		r["ambiguous"] = true
		r["choices"] = ["ZIGZAG", "LINE"]
		r["reason"] = "번개 모양인지 꺾인 벽인지 헷갈려요"
		return _result(r, "ZIGZAG", "번개 모양?", 0.45)
	var shape := "직선"
	if corners.size() == 1:
		shape = "ㄱ자"
	elif corners.size() >= 2:
		shape = "U자" if alternations == 0 else "꺾인 선"
	elif absf(rad_to_deg(total_turn)) > 50.0:
		shape = "곡선"
	return _result(r, "LINE", shape, 0.85)


static func _result(r: Dictionary, kind: String, shape: String, conf: float) -> Dictionary:
	r["kind"] = kind
	r["shape"] = shape
	r["confidence"] = conf
	return r


static func normalized(simp: PackedVector2Array) -> PackedVector2Array:
	## 중심 (0,0), 가장 긴 변 = 1 로 맞춘 꼭짓점들 (그린 방향은 그대로: 위 = 지도 북쪽)
	var bb := Rect2(simp[0], Vector2.ZERO)
	for p in simp:
		bb = bb.expand(p)
	var c := bb.get_center()
	var s := maxf(maxf(bb.size.x, bb.size.y), 1.0)
	var out := PackedVector2Array()
	for p in simp:
		out.append((p - c) / s)
	return out
