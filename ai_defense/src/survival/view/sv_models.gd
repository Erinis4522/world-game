class_name SvModels
extends RefCounted
## 임시 3D 로우폴리 모델 (기본 도형 조합). 정식 모델이 오면 이 함수들만 바꾸면 된다.
## 좌표: 격자 1칸 = 1m, 평면 (x, y) → 3D (x, 0, y).
## 캐릭터는 공통 구조(몸통·머리·머리카락·무기)에 data/heroes.json의 look 색과 직업별 무기만 바꾼다.

static var _mats: Dictionary = {}


static func mat(col: Color, emissive := 0.0, unshaded := false) -> StandardMaterial3D:
	var key := "%s|%.2f|%s" % [col.to_html(), emissive, str(unshaded)]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.85
	if col.a < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emissive
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats[key] = m
	return m


static func c(hex: String) -> Color:
	return Color.from_string(hex, Color.GRAY)


static func part(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func box(sz: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = sz
	return b


static func sphere(r: float, seg := 10, rings := 6) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg
	s.rings = rings
	return s


static func cyl(top: float, bottom: float, h: float, seg := 8) -> CylinderMesh:
	var cm := CylinderMesh.new()
	cm.top_radius = top
	cm.bottom_radius = bottom
	cm.height = h
	cm.radial_segments = seg
	cm.rings = 1
	return cm


static func prism(sz: Vector3) -> PrismMesh:
	var p := PrismMesh.new()
	p.size = sz
	return p


static func shadow(parent: Node3D, r: float) -> void:
	part(parent, cyl(r, r, 0.01, 12), mat(Color(0, 0, 0, 0.28), 0.0, true), Vector3(0, 0.012, 0))


# ---------------- 캐릭터 ----------------

static func hero(type: String) -> Node3D:
	## 반환: 루트(위치·방향). 자식 "Body"를 애니메이션에서 흔든다.
	var d: Dictionary = GameData.hero(type)
	var look: Dictionary = d.get("look", {})
	var outfit := c(str(look.get("outfit", d.get("color", "#446688"))))
	var accent := c(str(d.get("color", "#dddddd")))
	var skin := c(str(look.get("skin", "#f3cfa8")))
	var hair := c(str(look.get("hair", "#333333")))
	var boots := c(str(look.get("boots", "#3a2a1c")))
	var root := Node3D.new()
	shadow(root, 0.38)
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	part(body, cyl(0.07, 0.08, 0.36), mat(boots), Vector3(-0.1, 0.18, 0))
	part(body, cyl(0.07, 0.08, 0.36), mat(boots), Vector3(0.1, 0.18, 0))
	part(body, cyl(0.2, 0.25, 0.5, 8), mat(outfit), Vector3(0, 0.6, 0))
	part(body, cyl(0.255, 0.255, 0.07, 8), mat(accent), Vector3(0, 0.42, 0))  # 직업 색 띠
	part(body, cyl(0.06, 0.06, 0.38), mat(outfit.darkened(0.15)), Vector3(-0.27, 0.62, 0), Vector3(0, 0, 0.25))
	var arm := Node3D.new()
	arm.name = "Arm"
	arm.position = Vector3(0.27, 0.8, 0)
	body.add_child(arm)
	part(arm, cyl(0.06, 0.06, 0.38), mat(outfit.darkened(0.15)), Vector3(0, -0.17, 0))
	part(body, sphere(0.22, 12, 8), mat(skin), Vector3(0, 1.08, 0))
	part(body, sphere(0.235, 12, 6), mat(hair), Vector3(0, 1.15, -0.03), Vector3.ZERO, Vector3(1.0, 0.75, 1.0))
	_weapon(type, arm, accent)
	return root


static func _weapon(type: String, arm: Node3D, accent: Color) -> void:
	var hand := Vector3(0, -0.36, 0.06)
	match type:
		"SWORD":
			part(arm, box(Vector3(0.05, 0.08, 0.7)), mat(c("#dfe6ef"), 0.2), hand + Vector3(0, 0, 0.36))
			part(arm, box(Vector3(0.22, 0.05, 0.05)), mat(c("#6b4a2b")), hand + Vector3(0, 0, 0.02))
		"ARCHER":
			var t := TorusMesh.new()
			t.inner_radius = 0.3
			t.outer_radius = 0.34
			t.rings = 12
			t.ring_segments = 4
			part(arm, t, mat(c("#7a4d24")), hand + Vector3(0, 0.05, 0.12), Vector3(0, PI * 0.5, PI * 0.5), Vector3(1, 1, 0.55))
		"SNIPER":
			part(arm, box(Vector3(0.07, 0.09, 0.95)), mat(c("#3a3f47")), hand + Vector3(0, 0.05, 0.38))
			part(arm, cyl(0.04, 0.04, 0.22), mat(c("#1d2126")), hand + Vector3(0, 0.12, 0.25), Vector3(PI * 0.5, 0, 0))
		"FIRE", "ICE", "LIGHTNING", "MARK":
			var tip: Color = {"FIRE": c("#ff7a1a"), "ICE": c("#8fe3ff"), "LIGHTNING": c("#ffe14a"), "MARK": c("#ffd84a")}[type]
			part(arm, cyl(0.03, 0.03, 1.0), mat(c("#4a3b2e")), hand + Vector3(0, 0.25, 0.05))
			if type == "ICE":
				part(arm, prism(Vector3(0.18, 0.28, 0.18)), mat(tip, 1.2), hand + Vector3(0, 0.82, 0.05))
			elif type == "MARK":
				part(arm, box(Vector3(0.22, 0.28, 0.05)), mat(c("#4b2f6b")), Vector3(-0.0, -0.32, 0.18))
				part(arm, sphere(0.08), mat(tip, 1.5), hand + Vector3(0, 0.8, 0.05))
			else:
				part(arm, sphere(0.1), mat(tip, 1.5), hand + Vector3(0, 0.8, 0.05))
		"BOMB":
			part(arm, sphere(0.15), mat(c("#1d1d22")), hand + Vector3(0, 0, 0.1))
			part(arm, sphere(0.04), mat(c("#ff9a2e"), 2.0), hand + Vector3(0, 0.17, 0.12))


static func player_ring() -> Node3D:
	var n := Node3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.48
	t.outer_radius = 0.58
	t.rings = 24
	t.ring_segments = 4
	part(n, t, mat(c("#ffd84a"), 1.0, true), Vector3(0, 0.03, 0), Vector3.ZERO, Vector3(1, 0.15, 1))
	part(n, prism(Vector3(0.28, 0.3, 0.12)), mat(c("#ffd84a"), 1.0, true), Vector3(0, 1.75, 0), Vector3(PI, 0, 0))
	return n


static func goal_marker() -> Node3D:
	var n := Node3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.3
	t.outer_radius = 0.38
	t.rings = 20
	t.ring_segments = 4
	part(n, t, mat(Color(1, 0.85, 0.3, 0.8), 1.0, true), Vector3(0, 0.04, 0), Vector3.ZERO, Vector3(1, 0.2, 1))
	return n


# ---------------- 적 ----------------

static func enemy(type: String) -> Node3D:
	var d: Dictionary = GameData.enemy(type)
	var col := c(str(d.get("color", "#48c9bd")))
	var dark := c("#2a3140")
	var r := float(d.get("radius", 0.3))
	var root := Node3D.new()
	shadow(root, r * 1.3)
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	match type:
		"FAST":
			part(body, sphere(r * 1.1, 8, 5), mat(dark), Vector3(0, r * 1.2, 0), Vector3.ZERO, Vector3(0.9, 0.75, 1.7))
			part(body, sphere(r * 0.7, 8, 5), mat(dark), Vector3(0, r * 1.5, r * 1.6))
			for i in 3:
				part(body, prism(Vector3(r * 0.5, r * 0.9, r * 0.4)), mat(col, 0.8), Vector3(0, r * 1.9, r * (0.6 - i * 0.6)), Vector3(-0.5, 0, 0))
			part(body, cyl(0.02, 0.05, r * 2.0), mat(col, 0.8), Vector3(0, r * 1.3, -r * 2.0), Vector3(-1.2, 0, 0))
			_legs(body, r, dark, 4, 1.3)
		"ARMORED":
			part(body, sphere(r * 1.25, 10, 5), mat(c("#7d8798")), Vector3(0, r * 1.0, 0), Vector3.ZERO, Vector3(1.3, 0.75, 1.3))
			part(body, sphere(r * 0.45, 8, 5), mat(dark), Vector3(0, r * 0.9, r * 1.45))
			for i in 3:
				part(body, prism(Vector3(r * 0.5, r * 0.8, r * 0.5)), mat(col, 0.8), Vector3((i - 1) * r * 0.6, r * 1.8, 0))
			_legs(body, r, dark, 4, 1.0)
		"BOSS":
			part(body, sphere(r * 1.2, 10, 6), mat(dark), Vector3(0, r * 1.3, 0), Vector3.ZERO, Vector3(1.2, 1.0, 1.4))
			part(body, sphere(r * 0.3, 8, 5), mat(c("#ff3b3b"), 2.0), Vector3(0, r * 1.4, r * 1.1))
			for i in 5:
				part(body, prism(Vector3(r * 0.45, r * 1.2, r * 0.45)), mat(col, 0.9), Vector3((i - 2) * r * 0.45, r * 2.4, -r * 0.2), Vector3(0, 0, (i - 2) * 0.25))
			_legs(body, r, dark, 4, 1.4)
		_:
			part(body, sphere(r * 1.15, 10, 6), mat(dark), Vector3(0, r * 1.05, 0), Vector3.ZERO, Vector3(1.0, 0.8, 1.25))
			for i in 3:
				part(body, prism(Vector3(r * 0.55, r * 1.0, r * 0.55)), mat(col, 0.8), Vector3((i - 1) * r * 0.55, r * 1.85, -r * 0.1), Vector3(0, 0, (i - 1) * 0.3))
			part(body, sphere(r * 0.12), mat(c("#ffcf4a"), 1.5), Vector3(-r * 0.35, r * 1.2, r * 1.15))
			part(body, sphere(r * 0.12), mat(c("#ffcf4a"), 1.5), Vector3(r * 0.35, r * 1.2, r * 1.15))
			_legs(body, r, dark, 6, 1.0)
	return root


static func _legs(body: Node3D, r: float, col: Color, n: int, spread: float) -> void:
	for i in n:
		var side := -1.0 if i % 2 == 0 else 1.0
		var z := (float(i / 2) - (n / 2 - 1) * 0.5) * r * 0.9 * spread
		part(body, cyl(0.025, 0.03, r * 1.1, 5), mat(col), Vector3(side * r * 1.05, r * 0.45, z), Vector3(0, 0, side * 0.7))


# ---------------- 맵 ----------------

static func ground(parent: Node3D, w: float, h: float) -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(w + 12, h + 12)
	part(parent, pm, mat(c("#56606c")), Vector3(w * 0.5, -0.02, h * 0.5))  # 바깥
	var inner := PlaneMesh.new()
	inner.size = Vector2(w, h)
	part(parent, inner, mat(c("#b7c2cf")), Vector3(w * 0.5, 0, h * 0.5))
	# 바닥 패널 줄눈
	var line_m := mat(c("#a3afbd"))
	for x in range(2, int(w), 2):
		part(parent, box(Vector3(0.04, 0.01, h)), line_m, Vector3(x, 0.006, h * 0.5))
	for y in range(2, int(h), 2):
		part(parent, box(Vector3(w, 0.01, 0.04)), line_m, Vector3(w * 0.5, 0.006, y))
	# 바깥 울타리
	var fence := mat(c("#8994a3"))
	part(parent, box(Vector3(w + 0.4, 0.5, 0.2)), fence, Vector3(w * 0.5, 0.25, -0.1))
	part(parent, box(Vector3(w + 0.4, 0.5, 0.2)), fence, Vector3(w * 0.5, 0.25, h + 0.1))
	part(parent, box(Vector3(0.2, 0.5, h)), fence, Vector3(-0.1, 0.25, h * 0.5))
	part(parent, box(Vector3(0.2, 0.5, h)), fence, Vector3(w + 0.1, 0.25, h * 0.5))


static func obstacle(parent: Node3D, rect: Array, kind: String) -> void:
	var x := float(rect[0])
	var y := float(rect[1])
	var w := float(rect[2])
	var h := float(rect[3])
	var center := Vector3(x + w * 0.5, 0, y + h * 0.5)
	match kind:
		"planter":
			part(parent, box(Vector3(w - 0.05, 0.45, h - 0.05)), mat(c("#cfd6de")), center + Vector3(0, 0.225, 0))
			for i in int(w * 2):
				part(parent, sphere(0.32, 7, 4), mat(c("#4f9a4a")), center + Vector3(-w * 0.5 + 0.3 + i * 0.5, 0.62, 0), Vector3.ZERO, Vector3(1, 0.8, h * 0.9))
		"crate":
			for j in int(h):
				part(parent, box(Vector3(w - 0.12, 0.8, 0.88)), mat(c("#9aa4b0")), Vector3(x + w * 0.5, 0.4, y + j + 0.5))
				part(parent, box(Vector3(w - 0.04, 0.06, 0.2)), mat(c("#5fd3c6"), 0.8), Vector3(x + w * 0.5, 0.55, y + j + 0.5 + 0.36))
				part(parent, box(Vector3(w - 0.2, 0.05, 0.75)), mat(c("#7c8693")), Vector3(x + w * 0.5, 0.82, y + j + 0.5))
		_:
			for i in int(max(w, h)):
				var off := Vector3(i + 0.5 - w * 0.5, 0, 0) if w >= h else Vector3(0, 0, i + 0.5 - h * 0.5)
				part(parent, sphere(0.55, 6, 4), mat(c("#8a8f96")), center + off + Vector3(0, 0.3, 0), Vector3(0, i * 0.9, 0), Vector3(1, 0.7, 0.9))


static func base_hub(parent: Node3D, center: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = center
	parent.add_child(n)
	part(n, cyl(1.45, 1.6, 0.35, 8), mat(c("#e4e9ef")), Vector3(0, 0.17, 0))
	part(n, cyl(1.0, 1.1, 0.25, 8), mat(c("#9fb0c2")), Vector3(0, 0.45, 0))
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		part(n, box(Vector3(0.25, 1.3, 0.25)), mat(c("#d6dde5")), Vector3(cos(a) * 1.05, 0.95, sin(a) * 1.05))
	part(n, cyl(0.75, 0.75, 1.3, 10), mat(Color(0.55, 0.95, 0.95, 0.35), 0.4), Vector3(0, 1.2, 0))
	var crystal := Node3D.new()
	crystal.name = "Crystal"
	crystal.position = Vector3(0, 1.25, 0)
	n.add_child(crystal)
	part(crystal, sphere(0.45, 4, 2), mat(c("#38e0d0"), 1.6), Vector3.ZERO, Vector3.ZERO, Vector3(0.8, 1.5, 0.8))
	part(n, cyl(1.12, 1.12, 0.05, 16), mat(c("#38e0d0"), 1.2, true), Vector3(0, 0.36, 0))
	return n


static func gate(parent: Node3D, pos: Vector3, edge_dir: Vector2) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = atan2(edge_dir.x, edge_dir.y)
	parent.add_child(n)
	part(n, box(Vector3(0.35, 2.0, 0.35)), mat(c("#7c8594")), Vector3(-0.95, 1.0, 0))
	part(n, box(Vector3(0.35, 2.0, 0.35)), mat(c("#7c8594")), Vector3(0.95, 1.0, 0))
	part(n, box(Vector3(2.3, 0.3, 0.4)), mat(c("#7c8594")), Vector3(0, 2.05, 0))
	var portal := part(n, box(Vector3(1.55, 1.8, 0.08)), mat(Color(0.7, 0.3, 1.0, 0.75), 1.6), Vector3(0, 0.95, 0))
	portal.name = "Portal"
	return n
