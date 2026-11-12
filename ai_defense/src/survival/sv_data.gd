class_name SvData
extends RefCounted
## 3D 서바이벌 모드 데이터 (data/survival.json). 동료 8종 정보는 기존 GameData를 그대로 쓰고,
## 이 모드에만 있는 '나(PLAYER)'와 '건설 동료(BUILDER)'는 special_heroes에서 읽는다.

static var cfg: Dictionary = {}
static var _loaded := false


static func ensure_loaded() -> void:
	GameData.ensure_loaded()
	if _loaded:
		return
	cfg = GameData._load_json("survival.json")
	_loaded = true


static func reload() -> void:
	_loaded = false
	ensure_loaded()


static func dt() -> float:
	return 1.0 / float(cfg.get("tick_hz", 30))


static func sec(section: String, key: String, def: Variant = null) -> Variant:
	var s: Variant = cfg.get(section, {})
	return s.get(key, def) if s is Dictionary else def


static func hero(type: String) -> Dictionary:
	var sp: Dictionary = cfg.get("special_heroes", {})
	if sp.has(type):
		return sp[type]
	return GameData.hero(type)


static func person(type: String) -> String:
	var d := hero(type)
	return str(d.get("person", d.get("name", type)))


static func enemy(type: String) -> Dictionary:
	var base: Dictionary = GameData.enemy(type).duplicate()
	base.merge(cfg.get("enemies", {}).get(type, {}), true)
	return base


static func base_center() -> Vector2:
	var r: Array = cfg["map"]["base_rect"]
	return Vector2(float(r[0]) + float(r[2]) * 0.5, float(r[1]) + float(r[3]) * 0.5)


static func map_size() -> Vector2:
	return Vector2(float(cfg["map"]["w"]), float(cfg["map"]["h"]))


static func roads() -> Array:
	return cfg["map"]["roads"]


static func road(id: String) -> Dictionary:
	for r in roads():
		if r["id"] == id:
			return r
	return roads()[0]


static func road_points(r: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in r["points"]:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out


static func gate_pos(road_id: String) -> Vector2:
	var pts := road_points(road(road_id))
	var p := pts[0]
	var inward := (pts[1] - pts[0]).normalized()
	return p + inward * 0.8


static func ult(type: String) -> Dictionary:
	return cfg.get("ultimate", {}).get("defs", {}).get(type, {})


static func speech_text(code: String) -> Array:
	return cfg.get("speech", {}).get(code, [])


static func zones() -> Array:
	return cfg["map"].get("zones", [])


static func zone(id: String) -> Dictionary:
	for z in zones():
		if z["id"] == id:
			return z
	return zones()[0] if not zones().is_empty() else {"id": "", "name": "길", "guard": [0, 0]}


static func zone_guard(id: String) -> Vector2:
	var g: Array = zone(id)["guard"]
	return Vector2(float(g[0]), float(g[1]))


static func zone_at(p: Vector2) -> Dictionary:
	## 가장 가까운 구간 (윗길 / 가운데 길 / 아랫길)
	var best: Dictionary = {}
	var bd := INF
	for z in zones():
		var d := p.distance_to(Vector2(float(z["guard"][0]), float(z["guard"][1])))
		if d < bd:
			bd = d
			best = z
	return best


static func aoe(type: String) -> Dictionary:
	return cfg.get("aoe", {}).get(type, {})
