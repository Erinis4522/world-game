class_name MapArt
extends RefCounted
## 전투 지도와 배치 지도에서 같은 배경·출입구·설치 패드를 사용한다.

static func world(origin: Vector2, scale_value: float, p: Vector2) -> Vector2:
	return origin + p * scale_value

static func draw_prop(ci: CanvasItem, id: String, feet: Vector2, height: float, alpha:=1.0) -> bool:
	var tex := AssetManifest.texture("map",id)
	if tex == null:
		return false
	var used := HeroSprite.used_rect(tex)
	var s := height/used.size.y
	var dest := Rect2(feet-Vector2(used.size.x*s*0.5,height),used.size*s)
	ci.draw_texture_rect_region(tex,dest,used,Color(1,1,1,alpha))
	return true

static func draw_ground(ci: CanvasItem, origin: Vector2, scale_value: float) -> void:
	var map: Dictionary = GameData.config["map"]
	var extent := Vector2(map.width,map.height)*scale_value
	var bg := AssetManifest.texture("map","background")
	if bg != null:
		ci.draw_texture_rect(bg,Rect2(origin,extent),false)
	else:
		ci.draw_rect(Rect2(origin,extent),Color("667c84"))
	# 생성된 배경의 차로가 실제 경로와 일치하므로 중복된 임시 길은 그리지 않는다.
	if bg == null or not map.get("background_includes_path",false):
		var pts := PackedVector2Array()
		for p in GameData.path.points: pts.append(world(origin,scale_value,p))
		ci.draw_polyline(pts,Color("4c5665"),scale_value*0.95)
		for p in pts: ci.draw_circle(p,scale_value*0.475,Color("4c5665"))
	var entrance := world(origin,scale_value,GameData.path.points[0]+Vector2(1.22,0))
	draw_prop(ci,"spawn",entrance+Vector2(0,scale_value*0.22),scale_value*1.4)
	var bp := world(origin,scale_value,GameData.path.end_point())
	draw_prop(ci,"base",bp+Vector2(0,scale_value*0.20),scale_value*2.25)

static func draw_slot(ci: CanvasItem, center: Vector2, scale_value: float, selected:=false, alpha:=1.0) -> void:
	var tex := AssetManifest.texture("map","slot")
	if tex != null:
		var used := HeroSprite.used_rect(tex)
		var s := scale_value*1.15/used.size.x
		var sz := used.size*s
		ci.draw_texture_rect_region(tex,Rect2(center-sz*0.5,sz),used,Color(1,1,1,alpha))
	else:
		ci.draw_circle(center,scale_value*0.4,Color(0.2,0.8,0.9,0.2*alpha))
	if selected:
		ci.draw_arc(center,scale_value*0.55,0,TAU,32,Color(1,0.85,0.4,alpha),2.0,true)
