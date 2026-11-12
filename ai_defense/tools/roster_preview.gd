extends SceneTree

var out_dir := "user://roster_preview"
var view: SubViewport

class ArtBoard:
	extends Control
	var animation_board := false
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO,size),Color("172331"))
		var font := get_theme_default_font()
		for i in GameData.hero_order.size():
			var type: String = GameData.hero_order[i]
			if animation_board:
				var y := 340*i
				draw_string(font,Vector2(20,y+35),GameData.person(type)+" · "+GameData.hero(type).name,HORIZONTAL_ALIGNMENT_LEFT,-1,24,Color.WHITE)
				var poses = [["대기",-1.0,false,1],["준비",0.22,false,1],["공격",0.45,false,1],["특기",0.45,true,1],["반대 방향",0.45,true,-1]]
				for j in poses.size():
					var pose: Array = poses[j]
					var a := HeroSprite.Anim.new(type)
					a.facing = pose[3]
					if pose[1] >= 0: a.trigger(10.0,pose[2],pose[3])
					var now: float = 10.0 + (pose[1]*a.atk_dur if pose[1]>=0 else 0.0)
					HeroSprite.draw(self,a,Vector2(135+j*300,y+310),245.0,now)
					draw_string(font,Vector2(110+j*300,y+335),pose[0],HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("bdeaf0"))
			else:
				var origin := Vector2((i%4)*480,(i/4)*640)
				draw_rect(Rect2(origin+Vector2(12,12),Vector2(456,616)),Color("223244"))
				HeroPortrait.draw(self,type,Rect2(origin+Vector2(25,70),Vector2(265,490)),"full")
				HeroSprite.draw(self,HeroSprite.Anim.new(type),origin+Vector2(345,552),240.0,10.0)
				draw_string(font,origin+Vector2(28,48),GameData.person(type)+"  /  "+GameData.hero(type).name,HORIZONTAL_ALIGNMENT_LEFT,-1,28,Color.WHITE)
				draw_string(font,origin+Vector2(28,597),GameData.hero(type).profile,HORIZONTAL_ALIGNMENT_LEFT,-1,21,Color("a8c4d4"))

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out_dir=a.substr(4)
	DirAccess.make_dir_recursive_absolute(out_dir)
	GameData.ensure_loaded()
	call_deferred("run")

func capture(board: ArtBoard,path: String) -> void:
	view.size = Vector2i(board.size)
	view.add_child(board)
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png(path)
	view.remove_child(board)
	board.queue_free()

func run() -> void:
	view=SubViewport.new()
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var roster:=ArtBoard.new()
	roster.size=Vector2(1920,1280)
	await capture(roster,out_dir.path_join("roster.png"))
	var anim:=ArtBoard.new()
	anim.animation_board=true
	anim.size=Vector2(1500,2720)
	await capture(anim,out_dir.path_join("animation_frames.png"))
	quit()
