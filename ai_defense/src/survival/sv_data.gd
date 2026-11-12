class_name SvData
extends RefCounted
## 3D 서바이벌 모드 데이터 (data/survival.json). 캐릭터·적 기본 정보는 기존 GameData를 그대로 쓴다.

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


static func enemy(type: String) -> Dictionary:
	## 기존 적 데이터(체력·방어·반지름) + 서바이벌용 행동 데이터
	var base: Dictionary = GameData.enemy(type).duplicate()
	base.merge(cfg.get("enemies", {}).get(type, {}), true)
	return base


static func tactic_name(t: String) -> String:
	return str(cfg.get("tactics", {}).get(t, {}).get("name", t))


static func tactic_status(t: String) -> String:
	return str(cfg.get("tactics", {}).get(t, {}).get("status", ""))


static func tactic_order() -> Array:
	return cfg.get("tactic_order", ["GATHER", "DEFEND", "FOCUS"])


static func base_center() -> Vector2:
	var r: Array = cfg["map"]["base_rect"]
	return Vector2(float(r[0]) + float(r[2]) * 0.5, float(r[1]) + float(r[3]) * 0.5)


static func map_size() -> Vector2:
	return Vector2(float(cfg["map"]["w"]), float(cfg["map"]["h"]))


static func gate(id: String) -> Dictionary:
	for g in cfg["map"]["gates"]:
		if g["id"] == id:
			return g
	return cfg["map"]["gates"][0]


static func speech_text(code: String) -> Array:
	return cfg.get("speech", {}).get(code, [])
