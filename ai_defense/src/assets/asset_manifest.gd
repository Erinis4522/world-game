class_name AssetManifest
extends RefCounted
## 교체 가능한 그림 목록. 파일이 없으면 null → 화면은 도형 플레이스홀더로 그린다.
##
## 찾는 순서
##  1) 실행 파일 옆 assets/<분류>/<이름>.png   (재빌드 없이 덮어쓰기 교체)
##  2) 프로젝트 res://assets/<분류>/<이름>.png  (빌드에 포함)
##
## 분류: heroes / enemies / map / ui / effects
## 캐릭터·적 PNG 기준점(anchor): 이미지 아래쪽 가운데 = 발 위치.  크기는 아래 DRAW_SIZE(타일 단위).

const DRAW_SIZE := {
	"heroes": 1.3,  # 타일 단위 한 변 길이
	"enemies_scale": 2.6,  # 적 반지름 × 이 값 = 한 변 길이
}

const HERO_FILES := ["sword", "archer", "sniper", "fire", "ice", "lightning", "bomb", "mark"]
const ENEMY_FILES := ["normal", "fast", "armored", "boss"]
const MAP_FILES := ["background", "spawn", "base", "slot"]
const UI_FILES := ["speech-bubble", "card-frame"]

static var _cache: Dictionary = {}


static func texture(category: String, file_name: String) -> Texture2D:
	var key := category + "/" + file_name
	if _cache.has(key):
		return _cache[key]
	var tex: Texture2D = null
	if OS.has_feature("template"):
		var ext := GameData.external_dir().path_join("assets").path_join(category).path_join(file_name + ".png")
		if FileAccess.file_exists(ext):
			var img := Image.load_from_file(ext)
			if img != null and not img.is_empty():
				if category in ["portraits","enemies","map"] or (category == "effects" and file_name == "ice_cast"):
					img.generate_mipmaps()
				tex = ImageTexture.create_from_image(img)
	if tex == null:
		var res := "res://assets/%s/%s.png" % [category, file_name]
		if ResourceLoader.exists(res):
			var loaded: Variant = load(res)
			if loaded is Texture2D:
				tex = loaded
	if tex != null and (category in ["portraits","enemies","map"] or (category == "effects" and file_name == "ice_cast")):
		tex = smooth_texture(tex)
	_cache[key] = tex
	return tex


static func smooth_texture(tex: Texture2D) -> CanvasTexture:
	var filtered := CanvasTexture.new()
	filtered.diffuse_texture = tex
	filtered.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return filtered


static func hero_texture(type: String) -> Texture2D:
	return texture("heroes", str(GameData.hero(type).get("asset", type.to_lower())))


static func portrait_texture(type: String) -> Texture2D:
	var portrait := str(GameData.hero(type).get("portrait", ""))
	return texture("portraits", portrait) if portrait != "" else null


static func enemy_texture(type: String) -> Texture2D:
	return texture("enemies", str(GameData.enemy(type).get("asset", type.to_lower())))


static func clear_cache() -> void:
	_cache.clear()


static func report() -> Array:
	## 교사 메뉴/README용: 어떤 파일이 실제 그림이고 어떤 것이 플레이스홀더인지
	var out: Array = []
	for f in HERO_FILES:
		out.append(["heroes/" + f + ".png", texture("heroes", f) != null])
	for f in HERO_FILES:
		out.append(["portraits/" + f + ".png", portrait_texture(f.to_upper()) != null])
	out.append(["effects/ice_cast.png", texture("effects", "ice_cast") != null])
	for f in ENEMY_FILES:
		out.append(["enemies/" + f + ".png", texture("enemies", f) != null])
	for f in MAP_FILES:
		out.append(["map/" + f + ".png", texture("map", f) != null])
	return out
