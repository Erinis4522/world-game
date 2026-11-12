class_name SvFace
extends Control
## 캐릭터 얼굴(전신 원화의 얼굴 부분)을 그리는 작은 그림. 입력은 부모 버튼에 넘긴다.

var hero_type := "SWORD"
var dim := false
var mode := "head"


func _init(t: String = "SWORD", px: float = 120.0, m := "head") -> void:
	hero_type = t
	mode = m
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var a := 0.4 if dim else 1.0
	if not HeroPortrait.draw(self, hero_type, Rect2(Vector2.ZERO, size), mode, a):
		var col := Color.from_string(str(GameData.hero(hero_type).get("color", "#888")), Color.GRAY)
		draw_circle(size * 0.5, minf(size.x, size.y) * 0.4, col)
