extends SceneTree
## 3D 서바이벌 화면 점검: 실제 메인 장면으로 한 판을 자동 진행하며 두 화면 스크린샷 저장
##   godot --path . --script res://tools/sv_smoke.gd -- out=<폴더>

var main: Node
var out_dir := "user://sv_smoke"
var t := 0.0
var stage := 0
var shots := 0
var _seq := 5000
var _next_move := 0.0
var _bubble_shot := false


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
	var ack: Dictionary = main.controller.command(n, a, _seq)
	if not ack["ok"]:
		print("명령 실패: ", n, " ", a)


func _shot(tag: String) -> void:
	shots += 1
	root.get_texture().get_image().save_png(out_dir.path_join("%02d_%s_monitor.png" % [shots, tag]))
	main.control_window.get_texture().get_image().save_png(out_dir.path_join("%02d_%s_touch.png" % [shots, tag]))
	print("shot ", tag)


func _process(delta: float) -> bool:
	t += delta
	var c: SvController = main.controller
	match stage:
		0:
			if t > 0.4:
				main.control_window.size = Vector2i(1280, 720)
				root.size = Vector2i(1280, 720)
			if t > 1.2:
				_shot("attract")
				_cmd("start")
				stage = 1
		1:
			if t > 1.8 and main.control_view._focus == "":
				main.control_view._focus = "LIGHTNING"
			if t > 2.6:
				_shot("select_detail")
				_cmd("confirm_hero", {"type": "LIGHTNING"})
				main.control_view._focus = ""
				main.control_view._focus_shown = ""
				_cmd("confirm_hero", {"type": "SWORD"})
				_cmd("confirm_hero", {"type": "BOMB"})
				stage = 2
		2:
			if t > 3.6:
				_shot("select_team")
				_cmd("battle_start")
				stage = 3
		3:
			if t > 4.6:
				_shot("intro")
				stage = 4
		4:
			if c.phase == SvController.BATTLE:
				Engine.time_scale = 2.0
				# 학생 대신: 2초마다 기지에 가장 가까운 적 쪽으로 이동
				var st := c.session.state
				if st.time >= _next_move:
					_next_move = st.time + 2.0
					var best: SvState.SvEnemy = null
					var bd := INF
					for e in st.enemies:
						if e.alive and e.pos.distance_to(SvData.base_center()) < bd:
							bd = e.pos.distance_to(SvData.base_center())
							best = e
					if best != null:
						_cmd("move_to", {"x": best.pos.x, "y": best.pos.y})
				if not _bubble_shot and not c.session.bubbles.is_empty() and st.time > 15:
					_bubble_shot = true
					_shot("battle_bubble")
				if st.time > 30 and stage == 4:
					main.control_view._open_hero = 1
					stage = 5
					t = 0.0
		5:
			if t > 0.6:
				_shot("tactic_menu")
				_cmd("set_tactic", {"hero": 1, "tactic": "DEFEND"})
				main.control_view._open_hero = -1
				stage = 6
		6:
			var st2 := c.session.state if c.session != null else null
			if st2 != null and st2.time > 70 and stage == 6:
				_shot("battle_70s")
				Engine.time_scale = 6.0
				stage = 7
		7:
			if c.phase == SvController.RESULT:
				Engine.time_scale = 1.0
				stage = 8
				t = 0.0
		8:
			if t > 1.0:
				_shot("result")
				var r: Dictionary = c.result
				print("RESULT ", r["outcome"], " base=", r["base_hp"], " kills=", r["kills"], " moves=", r["moves"], " tactic_changes=", r["tactic_changes"])
				return true
	return t > 600.0
