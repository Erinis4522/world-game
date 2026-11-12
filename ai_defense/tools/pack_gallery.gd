extends SceneTree
## 에셋 묶음 속 모델을 한 줄로 늘어놓고 이름표와 함께 스크린샷 (모델 고르기용)
##   godot --path . --script res://tools/pack_gallery.gd -- out=<png> pack=<res://...> names=a,b,c [h=3]

var out := "user://gallery.png"
var frames := 0


func _initialize() -> void:
	var pack := ""
	var names: PackedStringArray = []
	var target_h := 3.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
		elif a.begins_with("pack="):
			pack = a.substr(5)
		elif a.begins_with("names="):
			names = a.substr(6).split(",")
		elif a.begins_with("h="):
			target_h = float(a.substr(2))
	root.size = Vector2i(1600, 900)
	var w := Node3D.new()
	root.add_child(w)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#8fa9b4")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 0.55
	env.environment = e
	w.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(-35), 0)
	w.add_child(sun)
	var cols := mini(names.size(), 8)
	var rows := int(ceil(names.size() / float(cols)))
	var sp := target_h * 1.5
	for i in names.size():
		var it := SvModels.pack_item(pack, names[i])
		var x := (i % cols - (cols - 1) * 0.5) * sp
		var z := (i / cols) * sp * 1.2
		if it[0] != null:
			var sy: float = (it[2] as Vector3).y
			var n := SvModels.pack_node(pack, names[i], target_h / maxf(sy, 0.01))
			n.position = Vector3(x, 0, z)
			w.add_child(n)
		var l := Label3D.new()
		l.text = names[i] + ("" if it[0] != null else " (없음)")
		l.font_size = 64
		l.pixel_size = 0.006
		l.position = Vector3(x, -0.4, z + 0.8)
		l.rotation.x = -0.6
		w.add_child(l)
	var cam := Camera3D.new()
	cam.fov = 40
	var span := cols * sp
	var cpos := Vector3(0, target_h * 1.6 + rows * 2.0, (rows - 1) * sp * 0.6 + span * 0.95)
	w.add_child(cam)
	cam.look_at_from_position(cpos, Vector3(0, target_h * 0.4, (rows - 1) * sp * 0.6), Vector3.UP)
	cam.current = true


func _process(_d: float) -> bool:
	frames += 1
	if frames == 8:
		root.get_texture().get_image().save_png(out)
		return true
	return false
