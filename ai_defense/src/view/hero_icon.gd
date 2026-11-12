class_name HeroIcon
extends Control
## 카드·목록용 전신 원화와 초상. SD는 전장 및 배치 지도에서만 사용한다.

var hero_type := "SWORD":
	set(v):
		hero_type = v
		queue_redraw()
var dim := false:
	set(v):
		dim = v
		queue_redraw()
var portrait_mode := "bust":  # full / bust / head
	set(v):
		portrait_mode = v
		queue_redraw()


func _init(t: String = "SWORD", px: float = 120.0) -> void:
	hero_type = t
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var a := 0.45 if dim else 1.0
	if HeroPortrait.draw(self,hero_type,Rect2(Vector2.ZERO,size),portrait_mode,a):
		return
	draw_string(get_theme_default_font(),Vector2(12,size.y*0.5),str(GameData.hero(hero_type).get("glyph","?")),HORIZONTAL_ALIGNMENT_LEFT,-1,40,Color(1,1,1,a))
