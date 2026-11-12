class_name GameData
extends RefCounted
## 모든 밸런싱 데이터(JSON)를 한 번 읽어 보관한다.
##
## 읽는 순서: (1) 실행 파일 옆 data/ 폴더(있으면, 재빌드 없이 수치 조정용)
##            (2) 프로젝트 안의 res://data/
## 엔진·AI 코드는 수치를 직접 쓰지 않고 항상 여기서 가져온다.

static var config: Dictionary = {}
static var heroes: Dictionary = {}
static var hero_order: Array = []
static var enemies: Dictionary = {}
static var waves: Array = []
static var dialog: Dictionary = {}
static var path: MapPath = null
static var slots: Array = []  # Array[Vector2]
static var load_sources: Array = []
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	load_sources.clear()
	config = _load_json("game_config.json")
	var h: Dictionary = _load_json("heroes.json")
	heroes = h.get("heroes", {})
	hero_order = h.get("order", heroes.keys())
	enemies = _load_json("enemies.json").get("enemies", {})
	waves = _load_json("waves.json").get("waves", [])
	dialog = _load_json("dialog.json")
	path = MapPath.new(config["map"]["path"])
	slots.clear()
	for s in config["map"]["slots"]:
		slots.append(Vector2(float(s[0]), float(s[1])))
	_loaded = true


static func reload() -> void:
	_loaded = false
	ensure_loaded()


static func external_dir() -> String:
	## 실행 파일이 있는 폴더 (에디터 실행이면 프로젝트 폴더)
	if OS.has_feature("editor") or not OS.has_feature("template"):
		return ProjectSettings.globalize_path("res://")
	return OS.get_executable_path().get_base_dir()


static func _load_json(file_name: String) -> Dictionary:
	var candidates: Array = []
	if OS.has_feature("template"):
		candidates.append(external_dir().path_join("data").path_join(file_name))
	candidates.append("res://data/" + file_name)
	for p in candidates:
		if not FileAccess.file_exists(p):
			continue
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			continue
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			load_sources.append(p)
			return parsed
		push_error("JSON 형식 오류: " + p)
	push_error("데이터 파일을 찾을 수 없음: " + file_name)
	return {}


# ---------- 편의 함수 ----------

static func cfg(section: String, key: String, default_value: Variant = null) -> Variant:
	var s: Variant = config.get(section, {})
	if s is Dictionary:
		return s.get(key, default_value)
	return default_value


static func hero(type: String) -> Dictionary:
	return heroes.get(type, {})


static func enemy(type: String) -> Dictionary:
	return enemies.get(type, {})


static func principle_name(p: String) -> String:
	return config["principles"].get(p, {}).get("name", p)


static func principle_weights(p: String) -> Dictionary:
	return config["principles"].get(p, config["principles"]["NEAREST"])


static func principle_order() -> Array:
	return config.get("principle_order", ["NEAREST", "DANGER", "SPECIAL"])


static func dt() -> float:
	return 1.0 / float(config.get("tick_hz", 30))


static func text(section: String, key: String, default_value: String = "") -> String:
	var s: Variant = dialog.get(section, {})
	if s is Dictionary:
		var v: Variant = s.get(key, default_value)
		if v is Array:
			return str(v[0]) if not v.is_empty() else default_value
		return str(v)
	return default_value


static func text_variants(section: String, key: String) -> Array:
	var s: Variant = dialog.get(section, {})
	if s is Dictionary:
		var v: Variant = s.get(key, [])
		if v is Array:
			return v
		return [str(v)]
	return []


static func person(type: String) -> String:
	## 인물 이름 (없으면 역할 이름)
	var d: Dictionary = hero(type)
	return str(d.get("person", d.get("name", type)))
