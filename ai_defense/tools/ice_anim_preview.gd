extends SceneTree
## 게임과 동일한 렌더러로 빙결술사 동작 및 좌우 방향 프레임을 저장한다.

var out := "user://ice_animation.png"
var frames := 0
var preview_viewport: SubViewport

class Frames:
	extends Control
	const POSES = [["대기",-1.0,false],["준비",0.22,false],["시전",0.45,false],["복귀",0.8,false],["특기 준비",0.22,true],["특기 시전",0.45,true],["특기 복귀",0.8,true]]
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO,size),Color("263a47"))
		var font := get_theme_default_font()
		draw_string(font,Vector2(30,38),"빙결술사 · 실제 게임 애니메이션",HORIZONTAL_ALIGNMENT_LEFT,-1,28,Color.WHITE)
		for row in 2:
			for col in POSES.size():
				var pose: Array = POSES[col]
				var a := HeroSprite.Anim.new("ICE",0)
				a.phase = 0.0
				a.facing = 1.0 if row == 0 else -1.0
				if pose[1] >= 0.0:
					a.trigger(10.0,pose[2],a.facing)
				var now := 10.0 + (float(pose[1]) * a.atk_dur if pose[1] >= 0.0 else 0.0)
				var feet := Vector2(120+col*200,355+row*340)
				draw_line(feet+Vector2(-70,2),feet+Vector2(70,2),Color("526c78"),1.0)
				HeroSprite.draw(self,a,feet,255.0,now)
				draw_string(font,Vector2(45+col*200,80+row*340),pose[0],HORIZONTAL_ALIGNMENT_LEFT,-1,21,Color("bfeef5"))

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	GameData.ensure_loaded()
	preview_viewport = SubViewport.new()
	preview_viewport.size = Vector2i(1440,740)
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(preview_viewport)
	var canvas := Frames.new()
	canvas.size = Vector2(1440,740)
	preview_viewport.add_child(canvas)

func _process(_delta: float) -> bool:
	frames += 1
	if frames == 5:
		preview_viewport.get_texture().get_image().save_png(out)
		return true
	return false
