class_name HeroSprite
extends RefCounted
## 캐릭터 그림 + 애니메이션 (대기 / 일반 공격 / 특기 공격).
##
## 두 가지 방식
##  1) 파츠 리그: assets/heroes/rigs/<asset>/rig.json + 파츠 PNG (전체 8명)
##     - 공통 캔버스의 pivot, parent, z. 선택 사항: draw_bounds, anchor, attachments.
##  2) 통짜 그림: assets/heroes/<asset>.png 한 장을 늘이기·기울이기·점프로 움직임
## 둘 다 없으면 호출한 쪽이 도형 플레이스홀더를 그린다.
## 기준점: 그림의 불투명 영역 아래쪽 가운데 = 발 위치. 높이는 불투명 영역 기준으로 맞춘다
## (그림마다 여백이 달라도 크기가 일정하게 보이도록).
##
## 전투 로직과 완전히 분리되어 있다. 엔진은 ATTACK 이벤트에 special(특기 발휘) 표시만 준다.

const SPECIAL_COOLDOWN := 2.2  # 특기 모션은 너무 자주 반복되지 않게
const ATTACK_DUR := {"SWORD": 0.34, "ARCHER": 0.28, "SNIPER": 0.5, "FIRE": 0.45, "ICE": 0.4,
	"LIGHTNING": 0.42, "BOMB": 0.5, "MARK": 0.38}
const SPECIAL_DUR := 0.75
# 캐릭터별 공격 스타일: melee(앞으로 베기), shoot(반동), cast(지팡이 들어 올리기), throw(던지기)
const STYLE := {"SWORD": "melee", "ARCHER": "shoot", "SNIPER": "shoot", "FIRE": "cast", "ICE": "cast",
	"LIGHTNING": "cast", "BOMB": "throw", "MARK": "cast"}

static var _rect_cache: Dictionary = {}
static var _rig_cache: Dictionary = {}


class Anim:
	extends RefCounted
	var type := "SWORD"
	var phase := 0.0  # 캐릭터마다 숨쉬기 박자를 다르게
	var atk_t0 := -100.0
	var atk_dur := 0.3
	var special := false
	var facing := 1.0  # 1 = 원본 방향, -1 = 좌우 반전 (표적 쪽을 봄)
	var last_special := -100.0

	func _init(t: String = "SWORD", seed_value: int = 0) -> void:
		type = t
		phase = fposmod(float(seed_value) * 0.737, 1.0) * 3.0

	func trigger(now: float, is_special: bool, target_dx: float) -> void:
		if absf(target_dx) > 0.05:
			facing = 1.0 if target_dx > 0.0 else -1.0
		if is_special and now - last_special >= SPECIAL_COOLDOWN:
			special = true
			last_special = now
			atk_dur = SPECIAL_DUR
		else:
			special = false
			atk_dur = float(ATTACK_DUR.get(type, 0.35))
		atk_t0 = now

	func progress(now: float) -> float:
		var p := (now - atk_t0) / atk_dur
		return p if p >= 0.0 and p < 1.0 else -1.0


# ---------------- 공용 ----------------

static func has_art(type: String) -> bool:
	return AssetManifest.hero_texture(type) != null or rig_for(type) != null or not GameData.hero(type).get("look", {}).is_empty()


static func used_rect(tex: Texture2D) -> Rect2:
	var key := tex.get_rid().get_id()
	if _rect_cache.has(key):
		return _rect_cache[key]
	var r := Rect2(Vector2.ZERO, tex.get_size())
	var img := tex.get_image()
	if img != null and not img.is_empty():
		if img.is_compressed():
			img.decompress()
		var u := img.get_used_rect()
		if u.size.x > 0 and u.size.y > 0:
			r = Rect2(u)
	_rect_cache[key] = r
	return r


static func _ease_attack(p: float) -> float:
	## -0.35(뒤로 준비) → 1(타격) → 0(복귀)
	if p < 0.28:
		return -0.35 * sin(p / 0.28 * PI * 0.5)
	if p < 0.45:
		return lerpf(-0.35, 1.0, (p - 0.28) / 0.17)
	return 1.0 - smoothstep(0.45, 1.0, p)


class Pose:
	extends RefCounted
	var sx := 1.0
	var sy := 1.0
	var skew := 0.0
	var off := Vector2.ZERO  # 높이 비율 단위
	var spin := 1.0  # 종이 돌리기 연출 (x 배율에 곱함)
	var arm := 0.0  # 리그 전용: 무기 팔 휘두르기 (-0.4~1)
	var arm2 := 0.0  # 리그 전용: 반대 팔
	var glow := 0.0


static func pose_for(anim: Anim, now: float) -> Pose:
	var ps := _ice_pose(anim, now)
	var a := ps.arm
	# 모든 파츠 캐릭터는 발을 지면에 유지한다. 공격 종류에 따라 무게 이동만 추가한다.
	match anim.type:
		"SWORD":
			ps.skew += 0.045 * a * anim.facing
			ps.off.x = 0.025 * a * anim.facing
			ps.off.y = 0.0
		"SNIPER", "BOMB":
			ps.off.x = -0.025 * maxf(0.0,a) * anim.facing
			ps.skew -= 0.025 * a * anim.facing
			ps.off.y = 0.0
		"ARCHER":
			ps.skew += 0.012 * a * anim.facing
			ps.off.y = 0.0
	return ps


static func _ice_pose(anim: Anim, now: float) -> Pose:
	# 발은 지면에 두고, 준비 → 팔·지팡이 시전 → 복귀. 특기도 같은 방향을 유지한다.
	var ps := Pose.new()
	var breathe := sin((now + anim.phase) * TAU / 2.4)
	ps.sy = 1.0 + 0.006 * breathe
	ps.sx = 1.0 - 0.003 * breathe
	ps.arm2 = 0.03 * breathe
	var p := anim.progress(now)
	if p >= 0.0:
		ps.arm = _ease_attack(p) * (1.35 if anim.special else 1.0)
		ps.glow = clampf(maxf(0.0, ps.arm), 0.0, 1.0)
		ps.skew = 0.012 * ps.arm * anim.facing
		ps.off.y = -0.008 * maxf(0.0, ps.arm)
	return ps


# ---------------- 그리기 ----------------

static func draw(ci: CanvasItem, anim: Anim, feet: Vector2, height: float, now: float, alpha := 1.0) -> bool:
	## 그림이 있으면 그리고 true. 없으면 false (호출한 쪽이 도형으로 그림)
	var ps := pose_for(anim, now)
	var rig := rig_for(anim.type)
	if rig != null:
		_draw_rig(ci, rig, ps, anim, feet, height, now, alpha)
		return true
	var tex := AssetManifest.hero_texture(anim.type)
	if tex == null:
		# 그림 파일이 없으면 data의 look으로 도형 SD 인물을 그림 (애니메이션은 똑같이 적용)
		if GameData.hero(anim.type).get("look", {}).is_empty():
			return false
		if ps.glow > 0.01:
			_draw_glow(ci, anim.type, feet + Vector2(0, -height * 0.45) + ps.off * height, height * 0.5, ps.glow, alpha)
		ci.draw_set_transform_matrix(_base_xform(ps, anim, feet, height))
		ChibiArt.draw(ci, anim.type, height, alpha, ps.arm)
		ci.draw_set_transform_matrix(Transform2D.IDENTITY)
		return true
	var ur := used_rect(tex)
	var s := height / ur.size.y
	var base := _base_xform(ps, anim, feet, height)
	if ps.glow > 0.01:
		_draw_glow(ci, anim.type, feet + Vector2(0, -height * 0.45) + ps.off * height, height * 0.5, ps.glow, alpha)
	ci.draw_set_transform_matrix(base)
	ci.draw_texture_rect_region(tex, Rect2(Vector2(-ur.size.x * 0.5 * s, -ur.size.y * s), ur.size * s), ur, Color(1, 1, 1, alpha))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	return true


static func _base_xform(ps: Pose, anim: Anim, feet: Vector2, height: float) -> Transform2D:
	var xs := ps.sx * anim.facing * ps.spin
	if absf(xs) < 0.02:
		xs = 0.02 * signf(xs if xs != 0.0 else 1.0)
	# 발 기준 변형. skew는 화면 기준 방향 (+면 머리가 오른쪽으로)
	return Transform2D(0.0, Vector2(xs, ps.sy), ps.skew * signf(xs), feet + ps.off * height)


static func _draw_glow(ci: CanvasItem, type: String, center: Vector2, r: float, k: float, alpha: float) -> void:
	var col := PlaceholderArt.hero_color(type).lightened(0.55)
	ci.draw_circle(center, r * 0.8, Color(col.r, col.g, col.b, 0.16 * k * alpha))
	for i in 3:
		var rr := r * (0.75 + 0.18 * i)
		ci.draw_arc(center, rr, 0, TAU, 40, Color(col.r, col.g, col.b, (0.45 - 0.12 * i) * k * alpha), 3.0, true)


static func draw_static(ci: CanvasItem, type: String, feet: Vector2, height: float, alpha := 1.0) -> bool:
	## 배치 지도용 (대기 동작만, 실제 시간으로 숨쉬기)
	var a := Anim.new(type, type.hash())
	return draw(ci, a, feet, height, Time.get_ticks_msec() / 1000.0, alpha)


# ---------------- 파츠 리그 ----------------

class Rig:
	extends RefCounted
	var parts: Array = []  # [{name, z, pivot, parent, tex, rect}] z 순
	var by_name: Dictionary = {}
	var bounds := Rect2()  # 전체 불투명 영역 (캔버스 좌표)
	var anchor := Vector2.ZERO
	var attachments: Dictionary = {}
	var animation_profile := "cast"


static func rig_for(type: String) -> Rig:
	var asset := str(GameData.hero(type).get("asset", type.to_lower()))
	if _rig_cache.has(asset):
		return _rig_cache[asset]
	var rig: Rig = null
	var dir := "res://assets/heroes/rigs/%s/" % asset
	var ext_dir := ""
	if OS.has_feature("template"):
		ext_dir = GameData.external_dir().path_join("assets/heroes/rigs").path_join(asset) + "/"
	var json_path := ""
	if ext_dir != "" and FileAccess.file_exists(ext_dir + "rig.json"):
		json_path = ext_dir + "rig.json"
	elif FileAccess.file_exists(dir + "rig.json"):
		json_path = dir + "rig.json"
	if json_path != "":
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
		if parsed is Dictionary and parsed.has("part_layers"):
			rig = Rig.new()
			var first := true
			for p in parsed["part_layers"]:
				var tex := _load_part(ext_dir, dir, str(p["name"]))
				if tex == null:
					rig = null
					break
				var r := used_rect(tex)
				# 생성 이미지의 아주 희미한 배경 잔여가 캐릭터 크기를 줄이지 않도록 명시 영역 사용.
				var b: Array = p.get("draw_bounds", [])
				if b.size() == 4:
					r = Rect2(b[0], b[1], b[2], b[3]).intersection(Rect2(Vector2.ZERO, tex.get_size()))
				tex = AssetManifest.smooth_texture(tex)
				var offset_data: Array = p.get("canvas_offset", [0,0])
				var offset := Vector2(offset_data[0],offset_data[1])
				var part := {"name": str(p["name"]), "z": int(p.get("z", 0)), "pivot": Vector2(float(p["pivot"][0]), float(p["pivot"][1])),
					"parent": p.get("parent", null), "tex": tex, "rect": r, "canvas_offset": offset, "order": rig.parts.size()}
				rig.parts.append(part)
				rig.by_name[part["name"]] = part
				var canvas_rect := Rect2(r.position + offset,r.size)
				rig.bounds = canvas_rect if first else rig.bounds.merge(canvas_rect)
				first = false
			if rig != null:
				rig.parts.sort_custom(func(a, b): return a["order"] < b["order"] if a["z"] == b["z"] else a["z"] < b["z"])
				var anchor_data: Array = parsed.get("anchor", [])
				rig.anchor = Vector2(anchor_data[0], anchor_data[1]) if anchor_data.size() == 2 else Vector2(rig.bounds.get_center().x, rig.bounds.end.y)
				rig.attachments = parsed.get("attachments", {})
				rig.animation_profile = parsed.get("animation_profile","cast")
	_rig_cache[asset] = rig
	return rig


static func _load_part(ext_dir: String, dir: String, name: String) -> Texture2D:
	if ext_dir != "" and FileAccess.file_exists(ext_dir + name + ".png"):
		var img := Image.load_from_file(ext_dir + name + ".png")
		if img != null and not img.is_empty():
			img.generate_mipmaps()
			return ImageTexture.create_from_image(img)
	if ResourceLoader.exists(dir + name + ".png"):
		var t: Variant = load(dir + name + ".png")
		if t is Texture2D:
			return t
	return null


static func _rig_angles(ps: Pose, now: float, anim: Anim) -> Dictionary:
	var t := now + anim.phase
	var sway := sin(t * 2.0)
	var a := ps.arm
	if anim.type == "ICE":
		return {
			"torso": sway * 0.006 + a * 0.008,
			"head_face": -sway * 0.01 - a * 0.02,
			"hair_front": -sway * 0.006,
			"hair_back": sin(t * 2.0 + 0.3) * 0.009,
			"coat_back": sin(t * 2.0 + 0.5) * 0.015 + maxf(0.0, a) * 0.02,
			"upper_arm_near": sway * 0.015 + a * 0.08,
			"forearm_near": sway * 0.03 + a * 0.22,
			"upper_arm_far": sway * 0.008 + a * 0.045,
			"forearm_far": sway * 0.008 - a * 0.12,
			"staff": 0.0,
		}
	var angles := {
		"torso": sway * 0.005 + a * 0.008,
		"head_face": -sway * 0.008 - a * 0.012,
		"hair_front": -sway * 0.005,
		"hair_back": sin(t * 2.0 + 0.3) * 0.009,
		"coat_back": sin(t * 2.0 + 0.5) * 0.012 + maxf(0.0,a) * 0.02,
		"upper_arm_near": sway * 0.008,
		"forearm_near": sway * 0.015,
		"upper_arm_far": sway * 0.004,
		"forearm_far": sway * 0.006,
		"weapon": 0.0,
	}
	var rig := rig_for(anim.type)
	match rig.animation_profile if rig != null else "cast":
		"melee":
			angles.upper_arm_far += a * 0.32
			angles.forearm_far += a * 0.72
			angles.upper_arm_near -= a * 0.08
			angles.forearm_near -= a * 0.06
		"bow":
			angles.upper_arm_far -= a * 0.08
			angles.forearm_far += a * 0.06
			angles.upper_arm_near += a * 0.08
			angles.forearm_near -= a * 0.16
		"shoot":
			angles.upper_arm_far += a * 0.08
			angles.forearm_far += a * 0.16
			angles.head_face += a * 0.018
		"cast":
			angles.upper_arm_near += a * 0.07
			angles.forearm_near += a * 0.18
			angles.upper_arm_far += a * 0.035
			angles.forearm_far -= a * 0.085
	return angles


static func _draw_rig(ci: CanvasItem, rig: Rig, ps: Pose, anim: Anim, feet: Vector2, height: float, now: float, alpha: float) -> void:
	var s := height / rig.bounds.size.y
	var base := _base_xform(ps, anim, feet, height)
	# 캔버스 좌표 → 발 기준 좌표: 불투명 영역 아래쪽 가운데가 (0,0)
	var to_local := base * Transform2D(0.0, Vector2(s, s), 0.0, Vector2.ZERO) * Transform2D(0.0, -rig.anchor)
	var ang := _rig_angles(ps, now, anim)
	var globals: Dictionary = {}
	for part in rig.parts:
		globals[part["name"]] = _part_xform(rig, part, ang, globals)
	for part in rig.parts:
		var xf: Transform2D = to_local * globals[part["name"]]
		ci.draw_set_transform_matrix(xf)
		var r: Rect2 = part["rect"]
		var pv: Vector2 = part["pivot"]
		ci.draw_texture_rect_region(part["tex"], Rect2(r.position + part.get("canvas_offset",Vector2.ZERO) - pv, r.size), r, Color(1, 1, 1, alpha))
	if anim.type == "ICE" and ps.glow > 0.01 and rig.by_name.has("forearm_near"):
		var hand: Dictionary = rig.by_name["forearm_near"]
		ci.draw_set_transform_matrix(to_local * globals["forearm_near"])
		IceEffects.draw_crystal(ci, Vector2(310, 525) - hand["pivot"], 150.0 + ps.glow * 45.0, 0.0, ps.glow * alpha)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


static func _part_xform(rig: Rig, part: Dictionary, ang: Dictionary, globals: Dictionary) -> Transform2D:
	## 캔버스 좌표계에서 이 파츠의 변환 (관절 위치로 옮긴 뒤 회전). 그림은 (-pivot)에 그린다.
	if globals.has(part["name"]):
		return globals[part["name"]]
	var pv: Vector2 = part["pivot"]
	var rot := float(ang.get(part["name"], 0.0))
	var parent = part["parent"]
	var result := Transform2D(rot, pv)
	if parent != null and rig.by_name.has(parent):
		# 뒤쪽 파츠가 부모보다 먼저 그려져도 부모 관절을 먼저 계산한다.
		var parent_xform := _part_xform(rig, rig.by_name[parent], ang, globals)
		var pp: Vector2 = rig.by_name[parent]["pivot"]
		result = parent_xform * Transform2D(rot, pv - pp)
	globals[part["name"]] = result
	return result


static func attachment_position(anim: Anim, feet: Vector2, height: float, now: float, attachment: String) -> Vector2:
	var rig := rig_for(anim.type)
	if rig == null or not rig.attachments.has(attachment):
		return feet + Vector2(0, -height * 0.7)
	var data: Dictionary = rig.attachments[attachment]
	var part: Dictionary = rig.by_name[data["part"]]
	var ps := pose_for(anim, now)
	var s := height / rig.bounds.size.y
	var base := _base_xform(ps, anim, feet, height) * Transform2D(0.0, Vector2(s, s), 0.0, Vector2.ZERO) * Transform2D(0.0, -rig.anchor)
	var xf := _part_xform(rig, part, _rig_angles(ps, now, anim), {})
	return base * xf * (Vector2(data["position"][0], data["position"][1]) - part["pivot"])
