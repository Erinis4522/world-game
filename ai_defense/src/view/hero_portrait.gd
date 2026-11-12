class_name HeroPortrait
extends RefCounted
## 전투 밖의 인물 그림: 같은 전신 원화를 용도에 맞게 전체/상반신/얼굴로 표시한다.

static func draw(ci: CanvasItem, type: String, area: Rect2, mode := "full", alpha := 1.0) -> bool:
	var texture := AssetManifest.portrait_texture(type)
	if texture == null:
		return false
	var region := Rect2(Vector2.ZERO,texture.get_size())
	var data: Dictionary = GameData.hero(type)
	var crop: Array = data.get("portrait_crop",[]) if mode == "head" else data.get("portrait_bust",[]) if mode == "bust" else []
	if crop.size() == 4:
		region = Rect2(Vector2(crop[0],crop[1])*texture.get_size(),Vector2(crop[2],crop[3])*texture.get_size())
	var factor := minf(area.size.x/region.size.x,area.size.y/region.size.y)
	var fitted := region.size*factor
	ci.draw_texture_rect_region(texture,Rect2(area.position+(area.size-fitted)*0.5,fitted),region,Color(1,1,1,alpha))
	return true
