extends SceneTree
## 3D 월드 구역별 스크린샷 (디자인 점검용): 출현 묘지, 길 중간, 성문, 마을, 높은 곳 전경
##   godot --path . --script res://tools/sv_world_shots.gd -- out=<폴더>

var main: Node
var out_dir := "user://world_shots"
var t := 0.0
var step := -1
var _seq := 9000
const SPOTS := [["spawn", Vector2(20, 5)], ["road_mid", Vector2(8, 22)], ["road_turn", Vector2(32, 31)], ["gate", Vector2(20, 51.5)]]


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out_dir = a.substr(4)
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = load("res://src/survival/sv_main.tscn").instantiate()
	main.force_single = true
	main.windowed = true
	root.add_child(main)


func _cmd(n: String, a: Dictionary = {}) -> void:
	_seq += 1
	main.controller.command(n, a, _seq)


func _process(delta: float) -> bool:
	t += delta
	var c: SvController = main.controller
	if step == -1:
		if t > 0.4:
			main.control_window.size = Vector2i(1280, 720)
			root.size = Vector2i(1280, 720)
		if t > 1.0:
			_cmd("start")
			for ty in ["ICE", "FIRE", "SNIPER"]:
				_cmd("confirm_hero", {"type": ty})
			_cmd("battle_start")
			step = 0
			t = 0.0
		return false
	if c.phase != SvController.BATTLE:
		return false
	if step < SPOTS.size():
		var st: SvState = c.session.state
		st.player().pos = SPOTS[step][1]
		st.player().prev_pos = SPOTS[step][1]
		st.base_hp = st.base_hp_max
		if t > (3.5 if step == 0 else 1.6):
			root.get_texture().get_image().save_png(out_dir.path_join("%s.png" % SPOTS[step][0]))
			if step == 0:
				main.control_window.get_texture().get_image().save_png(out_dir.path_join("touch.png"))
			print("shot ", SPOTS[step][0], " fps=", Engine.get_frames_per_second(), " draw=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), " prims=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
			step += 1
			t = 0.0
		return false
	# 높은 곳에서 전경
	var w: SvWorld3D = main.world
	if step == SPOTS.size():
		w.set_process(false)
		w.camera.fov = 50
		w.camera.position = Vector3(20, 62, 70)
		w.camera.look_at(Vector3(20, 0, 30), Vector3.UP)
		step += 1
		t = 0.0
		return false
	if step == SPOTS.size() + 1 and t > 0.5:
		root.get_texture().get_image().save_png(out_dir.path_join("overview.png"))
		print("shot overview")
		w.camera.fov = 42
		w.camera.position = Vector3(20, 13, 70)
		w.camera.look_at(Vector3(20, 0, 58.5), Vector3.UP)
		step += 1
		t = 0.0
	elif step == SPOTS.size() + 2 and t > 0.5:
		root.get_texture().get_image().save_png(out_dir.path_join("village.png"))
		print("shot village")
		return true
	return false
