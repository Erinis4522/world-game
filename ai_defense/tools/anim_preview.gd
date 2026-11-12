extends SceneTree
## 캐릭터 애니메이션 프레임 표를 PNG로 저장 (화면 필요, --headless 없이)
##   godot --path . --script res://tools/anim_preview.gd -- out=<폴더>

var out_dir := "user://anim_preview"
var canvas: Control
var frames := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out_dir = a.substr(4)
	DirAccess.make_dir_recursive_absolute(out_dir)
	GameData.ensure_loaded()
	root.size = Vector2i(1500, 1260)
	canvas = load("res://tools/anim_preview_canvas.gd").new()
	canvas.size = Vector2(1500, 1260)
	root.add_child(canvas)


func _process(_d: float) -> bool:
	frames += 1
	if frames == 5:
		root.get_texture().get_image().save_png(out_dir.path_join("anim_right.png"))
		canvas.facing = -1.0
		canvas.queue_redraw()
	if frames == 10:
		root.get_texture().get_image().save_png(out_dir.path_join("anim_left.png"))
		print("saved ", out_dir)
		return true
	return false
