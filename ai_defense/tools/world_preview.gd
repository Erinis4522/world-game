extends SceneTree
var out_dir := "user://world_previews/"
var view: SubViewport
class Monsters:
	extends Control
	func _draw():
		draw_rect(Rect2(Vector2.ZERO,size),Color("1c2937"))
		var font=get_theme_default_font()
		var types=["NORMAL","FAST","ARMORED","BOSS"]
		var dirs=[Vector2.RIGHT,Vector2.RIGHT,Vector2.DOWN,Vector2.UP]
		var labels=["오른쪽 · 보행 A","오른쪽 · 보행 B","아래로 이동","위로 이동"]
		for col in 4:
			var type:String=types[col]
			draw_string(font,Vector2(30+col*360,45),GameData.enemy(type).name,HORIZONTAL_ALIGNMENT_LEFT,-1,30,Color.WHITE)
			for row in 4:
				var feet=Vector2(180+col*360,280+row*290)
				EnemySprite.draw(self,type,feet,180.0/float(GameData.enemy(type).art_height),dirs[row],0.0,1.0,1.0 if row==1 else 0.0)
				draw_string(font,Vector2(75+col*360,310+row*290),labels[row],HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("a4d7df"))

func _initialize():
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out_dir=a.substr(4).trim_suffix("/")+"/"
	DirAccess.make_dir_recursive_absolute(out_dir)
	GameData.ensure_loaded()
	call_deferred("run")
func capture(control: Control,path: String,dims: Vector2i):
	view.size=dims
	control.size=Vector2(dims)
	view.add_child(control)
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png(path)
	view.remove_child(control)
	control.queue_free()
func run():
	view=SubViewport.new()
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	await capture(Monsters.new(),out_dir+"monsters.png",Vector2i(1440,1210))
	var c=GameController.new()
	root.add_child(c)
	c.phase=GameController.PLACE
	var arena=ArenaView.new()
	arena.setup(c)
	await capture(arena,out_dir+"map_layout.png",Vector2i(1920,1080))
	quit()
