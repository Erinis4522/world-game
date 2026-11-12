class_name EnemySprite
extends RefCounted
## 각 2×2 시트: 오른쪽 걷기 A/B, 아래쪽, 위쪽. 왼쪽은 오른쪽의 좌우 반전.
static var _frames: Dictionary = {}
static var _textures: Dictionary = {}

static func motion_direction(distance: float) -> Vector2:
	var path := GameData.path
	return (path.pos_at(minf(distance+0.025,path.length))-path.pos_at(maxf(distance-0.025,0.0))).normalized()

static func frame_for(direction: Vector2, time: float, speed: float, phase: float=0.0) -> int:
	if absf(direction.y)>absf(direction.x):
		return 2 if direction.y>0.0 else 3
	return int(floor(time*maxf(speed,0.1)*7.0+phase))%2

static func frame_rects(type: String) -> Array:
	if _frames.has(type): return _frames[type]
	var tex := AssetManifest.texture("enemies",str(GameData.enemy(type).asset)+"_sheet")
	if tex == null: return []
	var declared: Array = GameData.enemy(type).get("art_rects",[])
	if declared.size()==4:
		var frames: Array=[]
		for r in declared: frames.append(Rect2(r[0],r[1],r[2],r[3]))
		_frames[type]=frames
		_textures[type]=tex
		return frames
	var image := tex.get_image()
	if image.is_compressed(): image.decompress()
	var cell := Vector2i(image.get_width()/2,image.get_height()/2)
	var rects: Array=[]
	for i in 4:
		var origin := Vector2i(i%2,i/2)*cell
		var region := image.get_region(Rect2i(origin,cell))
		var used := region.get_used_rect()
		rects.append(Rect2(Vector2(origin+used.position),Vector2(used.size)))
	_frames[type]=rects
	_textures[type]=tex
	return rects

static func draw(ci: CanvasItem, type: String, feet: Vector2, scale_value: float, direction: Vector2, time: float, speed: float, phase: float, hit:=false, alpha:=1.0) -> bool:
	var rects:=frame_rects(type)
	if rects.is_empty(): return false
	var data:=GameData.enemy(type)
	var height:=float(data.get("art_height",1.0))*scale_value
	var frame:=frame_for(direction,time,speed,phase)
	var r: Rect2=rects[frame]
	# 중립 높이를 기준으로 발을 고정하고 작은 보행 흔들림을 준다.
	var s:=height/r.size.y
	var bob:=absf(sin(time*maxf(speed,0.1)*10.0+phase))*scale_value*0.035
	var tilt:=sin(time*maxf(speed,0.1)*7.0+phase)*0.018
	var flip:=-1.0 if direction.x < -0.5 and absf(direction.x)>=absf(direction.y) else 1.0
	ci.draw_set_transform(feet+Vector2(0,-bob),tilt,Vector2(flip,1.0))
	var tint:=Color(1.35,1.1,1.1,alpha) if hit else Color(1,1,1,alpha)
	ci.draw_texture_rect_region(_textures[type],Rect2(Vector2(-r.size.x*s*0.5,-height),r.size*s),r,tint)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	return true
