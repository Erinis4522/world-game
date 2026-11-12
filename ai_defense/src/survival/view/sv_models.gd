class_name SvModels
extends RefCounted
## 3D 모델 만들기. KayKit (Kay Lousberg, CC0) 캐릭터·스켈레톤·중세 마을 에셋을 쓴다.
## 에셋 위치: assets/3d/kaykit/ (라이선스 파일 포함). 1칸 = 1m.
## 캐릭터 파일에는 무기가 전부 붙어 있으므로 직업별로 하나만 보이게 하고, 옷 색으로 구분한다.

const KAY := "res://assets/3d/kaykit/"
const CHAR_SCALE := 0.44  # KayKit 캐릭터 키 약 2.5 → 1.1m (적 무리가 잘 보이게 작게)

# 역할 → [모델 파일, 보일 무기들, 공격 애니메이션, 필살기 애니메이션]
const HERO_LOOK := {
	"PLAYER": ["characters/Knight", ["1H_Sword", "Round_Shield"], "1H_Melee_Attack_Chop", "2H_Melee_Attack_Spin"],
	"BUILDER": ["characters/Barbarian", ["1H_Axe"], "1H_Melee_Attack_Chop", "Interact"],
	"SWORD": ["characters/Rogue", ["Knife", "Knife_Offhand"], "Dualwield_Melee_Attack_Slice", "2H_Melee_Attack_Spin"],
	"ARCHER": ["characters/Rogue_Hooded", ["1H_Crossbow"], "1H_Ranged_Shoot", "1H_Ranged_Shooting"],
	"SNIPER": ["characters/Rogue_Hooded", ["2H_Crossbow"], "2H_Ranged_Shoot", "2H_Ranged_Shoot"],
	"FIRE": ["characters/Mage", ["2H_Staff"], "Spellcast_Shoot", "Spellcast_Long"],
	"ICE": ["characters/Mage", ["2H_Staff"], "Spellcast_Shoot", "Spellcast_Long"],
	"LIGHTNING": ["characters/Mage", ["1H_Wand"], "Spellcast_Shoot", "Spellcast_Long"],
	"BOMB": ["characters/Rogue", ["Throwable"], "Throw", "Throw"],
	"MARK": ["characters/Mage", ["Spellbook_open"], "Spellcast_Shoot", "Spellcast_Raise"],
}
const TINT_PARTS := ["Cape", "Hat", "Body"]
const LOOPS := ["Idle", "Running_A", "Walking_A", "Walking_D_Skeletons", "Spellcasting", "2H_Melee_Idle", "Unarmed_Idle"]

static var _scenes: Dictionary = {}
static var _mats: Dictionary = {}
static var _mesh_cache: Dictionary = {}


static func scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	return _scenes[path]


static func mat(col: Color, emissive := 0.0, unshaded := false) -> StandardMaterial3D:
	var key := "%s|%.2f|%s" % [col.to_html(), emissive, str(unshaded)]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.9
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


static func cyl(top: float, bottom: float, h: float, seg := 12) -> CylinderMesh:
	var cm := CylinderMesh.new()
	cm.top_radius = top
	cm.bottom_radius = bottom
	cm.height = h
	cm.radial_segments = seg
	cm.rings = 1
	return cm


static func ring(r: float, col: Color, w := 0.08) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = r - w
	t.outer_radius = r
	t.rings = 28
	t.ring_segments = 4
	var mi := MeshInstance3D.new()
	mi.mesh = t
	mi.material_override = mat(col, 1.0, true)
	mi.scale = Vector3(1, 0.15, 1)
	mi.position.y = 0.04
	return mi


static func shadow(parent: Node3D, r: float) -> void:
	part(parent, cyl(r, r, 0.01, 14), mat(Color(0, 0, 0, 0.25), 0.0, true), Vector3(0, 0.015, 0))


static func c(hex: String) -> Color:
	return Color.from_string(hex, Color.GRAY)


# ---------------- 캐릭터 ----------------

class Unit:
	extends RefCounted
	var root: Node3D
	var model: Node3D
	var anim: AnimationPlayer
	var attack_anim := "1H_Melee_Attack_Chop"
	var ult_anim := "Spellcast_Long"
	var current := ""
	var lock_until := 0.0

	func play_loop(name: String, now: float) -> void:
		if anim == null or now < lock_until or current == name:
			return
		if anim.has_animation(name):
			anim.play(name, 0.18)
			current = name

	func play_once(name: String, now: float, hold := 0.0) -> void:
		if anim == null or not anim.has_animation(name):
			return
		anim.play(name, 0.08)
		anim.seek(0.0, true)
		current = name
		var l := anim.get_animation(name).length
		lock_until = now + (hold if hold > 0.0 else l * 0.9)


static func _setup_loops(ap: AnimationPlayer) -> void:
	for n in LOOPS:
		if ap.has_animation(n):
			ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR


static func hero_unit(type: String) -> Unit:
	var u := Unit.new()
	u.root = Node3D.new()
	var look: Array = HERO_LOOK.get(type, HERO_LOOK["PLAYER"])
	var ps := scene(KAY + str(look[0]) + ".glb")
	var col := Color.from_string(str(SvData.hero(type).get("color", "#ffffff")), Color.WHITE)
	shadow(u.root, 0.34)
	var r := ring(0.46, col if type != "PLAYER" else c("#ffd84a"), 0.09 if type == "PLAYER" else 0.06)
	r.name = "Ring"
	u.root.add_child(r)
	if ps == null:
		part(u.root, cyl(0.25, 0.3, 1.2), mat(col), Vector3(0, 0.6, 0))
		return u
	u.model = ps.instantiate()
	u.model.scale = Vector3.ONE * CHAR_SCALE
	u.root.add_child(u.model)
	var keep: Array = look[1]
	var tint := col.lerp(Color.WHITE, 0.35)
	for mi in u.model.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		m3.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var nm := String(m3.name)
		var is_weapon := not (nm.contains("_Arm") or nm.contains("_Body") or nm.contains("_Head") or nm.contains("_Leg") or nm.contains("_Cape") or nm.contains("_Hat") or nm.contains("_Helmet"))
		if is_weapon:
			m3.visible = keep.has(nm)
			continue
		if type in ["PLAYER", "BUILDER"]:
			continue
		for t in TINT_PARTS:
			if nm.contains(t) and m3.mesh != null:
				var src := m3.get_active_material(0)
				if src is StandardMaterial3D:
					var mm := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
					mm.albedo_color = tint
					m3.material_override = mm
	var aps := u.model.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		u.anim = aps[0]
		_setup_loops(u.anim)
	u.attack_anim = look[2]
	u.ult_anim = look[3]
	u.play_loop("Idle", 0.0)
	return u


static func enemy_unit(type: String) -> Unit:
	var d: Dictionary = SvData.enemy(type)
	var u := Unit.new()
	u.root = Node3D.new()
	shadow(u.root, 0.4 * float(d.get("scale", 0.6)) / 0.6)
	var ps := scene(KAY + "skeletons/" + str(d.get("model", "Skeleton_Minion")) + ".glb")
	if ps == null:
		part(u.root, sphere(0.4), mat(c(str(d.get("color", "#48c9bd")))), Vector3(0, 0.4, 0))
		return u
	u.model = ps.instantiate()
	u.model.scale = Vector3.ONE * float(d.get("scale", 0.6))
	u.root.add_child(u.model)
	for mi in u.model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var aps := u.model.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		u.anim = aps[0]
		_setup_loops(u.anim)
	u.attack_anim = "1H_Melee_Attack_Chop" if type != "BOSS" else "Spellcast_Shoot"
	u.play_loop("Walking_D_Skeletons", 0.0)
	return u


# ---------------- 지형·건물 ----------------

static func prop(name: String) -> Node3D:
	var ps := scene(KAY + "hex/" + name + ".gltf")
	if ps == null:
		return Node3D.new()
	var n: Node3D = ps.instantiate()
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n


static func first_mesh(name: String) -> Array:
	## [Mesh, Transform3D] — MultiMesh로 많이 찍을 때 사용 (나무·바위)
	if _mesh_cache.has(name):
		return _mesh_cache[name]
	var out: Array = [null, Transform3D.IDENTITY]
	var ps := scene(KAY + "hex/" + name + ".gltf")
	if ps != null:
		var n: Node = ps.instantiate()
		var mis := n.find_children("*", "MeshInstance3D", true, false)
		if not mis.is_empty():
			var mi := mis[0] as MeshInstance3D
			var xf := Transform3D.IDENTITY
			var cur: Node = mi
			while cur != null and cur != n:
				if cur is Node3D:
					xf = (cur as Node3D).transform * xf
				cur = cur.get_parent()
			out = [mi.mesh, xf]
		n.free()
	_mesh_cache[name] = out
	return out


static func gate(parent: Node3D, pos: Vector3, inward: Vector2) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = atan2(inward.x, inward.y)
	parent.add_child(n)
	var stone := mat(c("#7c8594"))
	part(n, box(Vector3(0.45, 2.6, 0.45)), stone, Vector3(-1.6, 1.3, 0))
	part(n, box(Vector3(0.45, 2.6, 0.45)), stone, Vector3(1.6, 1.3, 0))
	part(n, box(Vector3(3.7, 0.35, 0.5)), stone, Vector3(0, 2.6, 0))
	var portal := part(n, box(Vector3(2.75, 2.4, 0.08)), mat(Color(0.65, 0.25, 1.0, 0.7), 1.8), Vector3(0, 1.25, 0))
	portal.name = "Portal"
	return n
