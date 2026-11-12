class_name SvGround
extends RefCounted
## 바닥 그림을 한 장의 텍스처로 구워서 평면 하나에 입힌다 (그리기 호출 1번, 셰이더 없음).
## 풀밭 얼룩, 숲 바닥, 가장자리가 부드러운 흙길, 마을 돌바닥. 게임 판정(SvGrid)은 건드리지 않는다.

const PX := 8  # 1칸 = 8픽셀
const MARGIN := 24  # 맵 바깥으로 이어지는 바닥 (칸)

const VER := 2  # 그림 규칙을 바꾸면 올려서 저장된 그림을 새로 굽게 함

# 밝고 따뜻한 자연색 (형광은 피하고, 칙칙하지 않게)
const GRASS_A := Color("#79ad4e")
const GRASS_B := Color("#97c45e")
const GRASS_DARK := Color("#669c47")
const FOREST := Color("#4f8540")
const DIRT := Color("#c69b63")
const DIRT_LIGHT := Color("#dbb77f")
const DIRT_RIM := Color("#9c7549")
const SAND := Color("#e2cf9c")
const SAND_DARK := Color("#cdb582")
const FLOWERS := [Color("#fff4dc"), Color("#ffd84a"), Color("#ff9cc2"), Color("#c9a6ff"), Color("#ffffff")]


static func rect() -> Rect2:
	## 바닥 평면이 덮는 영역 (맵 좌표)
	var sz := SvData.map_size()
	return Rect2(Vector2(-MARGIN, -MARGIN), sz + Vector2(MARGIN, MARGIN) * 2.0)


static func build(g: SvGrid) -> ImageTexture:
	# 같은 맵이면 지난번에 구운 그림을 다시 쓴다 (첫 실행만 약 1초)
	var cache := "user://ground_v%d_%d_%d.png" % [VER, PX, absi(str(SvData.cfg["map"]).hash())]
	if FileAccess.file_exists(cache):
		var ci := Image.load_from_file(cache)
		if ci != null and not ci.is_empty():
			ci.generate_mipmaps()
			return ImageTexture.create_from_image(ci)
	var t0 := Time.get_ticks_msec()
	var r := rect()
	var W := int(r.size.x) * PX
	var H := int(r.size.y) * PX
	# 길까지의 거리 (길 구간 근처만 계산)
	var dist := PackedFloat32Array()
	dist.resize(W * H)
	dist.fill(99.0)
	var half := float(SvData.cfg["map"].get("road_width", 4)) * 0.5 - 0.45  # 판정 폭(4칸)보다 좁게 그려 길이 덜 넓어 보이게
	for rd in SvData.roads():
		var pts := SvData.road_points(rd)
		for i in range(1, pts.size()):
			var a: Vector2 = pts[i - 1]
			var b: Vector2 = pts[i]
			var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * (half + 1.5)
			var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * (half + 1.5)
			var x0 := clampi(int((lo.x - r.position.x) * PX), 0, W - 1)
			var x1 := clampi(int((hi.x - r.position.x) * PX), 0, W - 1)
			var y0 := clampi(int((lo.y - r.position.y) * PX), 0, H - 1)
			var y1 := clampi(int((hi.y - r.position.y) * PX), 0, H - 1)
			for py in range(y0, y1 + 1):
				for px in range(x0, x1 + 1):
					var p := Vector2((px + 0.5) / PX + r.position.x, (py + 0.5) / PX + r.position.y)
					var d := Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p)
					var ix := py * W + px
					if d < dist[ix]:
						dist[ix] = d
	# 얼룩 무늬 (엔진 내장 노이즈를 이미지로 한 번에 받기)
	var nz := FastNoiseLite.new()
	nz.seed = 7
	nz.frequency = 0.012
	nz.fractal_octaves = 3
	var big := nz.get_image(W, H).get_data()
	var nz2 := FastNoiseLite.new()
	nz2.seed = 21
	nz2.frequency = 0.09
	var small := nz2.get_image(W, H).get_data()
	var bpp_big := big.size() / (W * H)
	var bpp_small := small.size() / (W * H)
	var vy := float(SvData.cfg["map"].get("village_y", g.h)) + 1.0
	var gate_x := SvData.base_center().x
	var castle := Vector2(gate_x, vy + 6.0)
	for vp in SvData.cfg["map"].get("village_props", []):
		if str(vp["model"]).contains("castle"):
			castle = Vector2(float(vp["pos"][0]), float(vp["pos"][1]))
	var treecell := PackedByteArray()
	treecell.resize(g.w * g.h)
	for c in g.kind.keys():
		if g.kind[c] == "tree":
			treecell[c.y * g.w + c.x] = 1
	var out := PackedByteArray()
	out.resize(W * H * 3)
	for py in H:
		var my := float(py) / PX + r.position.y
		for px in W:
			var mx := float(px) / PX + r.position.x
			var ix := py * W + px
			var n1 := big[ix * bpp_big] / 255.0
			var n2 := small[ix * bpp_small] / 255.0
			var col := GRASS_A.lerp(GRASS_B, n1).lerp(GRASS_DARK, clampf((0.45 - n2) * 1.6, 0.0, 0.35))
			var cell := Vector2i(floori(mx), floori(my))
			var inside := g.inside(cell)
			# 숲 바닥 (나무 칸과 맵 바깥)
			var forest := 0.0
			if not inside:
				forest = 1.0
			elif treecell[cell.y * g.w + cell.x] == 1:
				forest = 0.85
			if forest > 0.0:
				col = col.lerp(FOREST.lerp(GRASS_DARK, n2 * 0.5), forest * (0.7 + 0.3 * n1))
			# 마을(성벽 뒤): 풀밭 + 성문에서 성까지 모래 광장
			var plaza := 0.0
			if my >= vy - 0.6 and inside:
				var pd := minf(Geometry2D.get_closest_point_to_segment(Vector2(mx, my), Vector2(gate_x, vy - 0.5), castle).distance_to(Vector2(mx, my)) - 2.3,
					Vector2(mx, my).distance_to(castle) - 3.8)
				plaza = clampf(-pd / 0.5 + (n2 - 0.5) * 0.6, 0.0, 1.0)
				col = col.lerp(SAND.lerp(SAND_DARK, n2 * 0.6), plaza)
			# 꽃 (풀밭에 작은 점, 2픽셀 덩어리). 숲·길·광장 위에는 없음
			if forest < 0.5 and plaza < 0.1 and dist[ix] > half + 0.8:
				var bx := px >> 1
				var by := py >> 1
				var hh := ((bx * 73856093) ^ (by * 19349663)) & 4095
				if hh < (40 if n1 > 0.6 else 6):
					col = FLOWERS[hh % FLOWERS.size()] as Color
			# 흙길: 바깥 어두운 테두리 → 안쪽 밝은 흙, 노이즈로 경계를 울퉁불퉁하게
			var d := dist[ix] + (n2 - 0.5) * 0.35
			if d < half + 0.45:
				var rim := clampf((half + 0.45 - d) / 0.35, 0.0, 1.0)
				col = col.lerp(DIRT_RIM, rim * 0.8)
				if d < half + 0.1:
					var inner := clampf((half + 0.1 - d) / 0.45, 0.0, 1.0)
					var dirt := DIRT.lerp(DIRT_LIGHT, clampf(n1 * 1.2 - 0.1, 0.0, 1.0) * clampf((half - d) / half + 0.3, 0.0, 1.0))
					if n2 > 0.72:
						dirt = dirt.darkened(0.12)  # 자갈 점
					col = col.lerp(dirt, inner)
			out[ix * 3] = int(clampf(col.r, 0.0, 1.0) * 255.0)
			out[ix * 3 + 1] = int(clampf(col.g, 0.0, 1.0) * 255.0)
			out[ix * 3 + 2] = int(clampf(col.b, 0.0, 1.0) * 255.0)
	var img := Image.create_from_data(W, H, false, Image.FORMAT_RGB8, out)
	img.save_png(cache)
	img.generate_mipmaps()
	print_verbose("바닥 텍스처 %dx%d, %dms" % [W, H, Time.get_ticks_msec() - t0])
	return ImageTexture.create_from_image(img)


static func plane(tex: ImageTexture) -> MeshInstance3D:
	var r := rect()
	var pm := PlaneMesh.new()
	pm.size = r.size
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = 1.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(r.position.x + r.size.x * 0.5, 0.0, r.position.y + r.size.y * 0.5)
	return mi
