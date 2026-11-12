extends SceneTree
## 화면 점검용: 실제 메인 장면을 분할 모드로 띄워 한 판을 자동 진행하고 두 창 스크린샷을 저장한다.
##   godot --path . --script res://tools/ui_smoke.gd -- out=<폴더>
## (화면이 필요한 테스트라 --headless 없이 실행)

var main: Node
var out_dir := "user://ui_smoke"
var t := 0.0
var stage := 0
var shots := 0
var sugg_seen := 0
var bubble_shot := false
var _seq := 1000


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out_dir = a.substr(4)
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = load("res://src/main.tscn").instantiate()
	main.force_single = true
	main.windowed = true
	root.add_child(main)


func _cmd(n: String, a: Dictionary = {}) -> void:
	_seq += 1
	var ack: Dictionary = main.controller.command(n, a, _seq)
	print("cmd ", n, " ", a, " -> ", ack["ok"])


func _shot(tag: String) -> void:
	shots += 1
	var a := root.get_texture().get_image()
	a.save_png(out_dir.path_join("%02d_%s_arena.png" % [shots, tag]))
	var c: Image = main.control_window.get_texture().get_image()
	c.save_png(out_dir.path_join("%02d_%s_control.png" % [shots, tag]))
	print("shot ", tag)


func _process(delta: float) -> bool:
	t += delta
	var c: GameController = main.controller
	match stage:
		0:
			if t > 0.5 and main.control_window.size.x != 1280:
				main.control_window.size = Vector2i(1280, 720)
				main.get_window().size = Vector2i(1280, 720)
			if t > 1.5:
				_shot("attract")
				_cmd("start")
				stage = 1
		1:
			if t > 2.0 and main.control_view._focus == "" and c.selected.is_empty():
				main.control_view._focus = "SNIPER"  # 카드 누름
			if t > 2.8 and c.selected.is_empty():
				_shot("detail")
				_cmd("confirm_hero", {"type": "SNIPER"})
				main.control_view._focus = ""
				main.control_view._focus_shown = ""
			if t > 3.0 and t < 3.2 and c.selected.size() == 1:
				_shot("lineup_drop")
			if t > 3.6:
				_cmd("confirm_hero", {"type": "FIRE"})
				_cmd("confirm_hero", {"type": "BOMB"})
				stage = 2
		2:
			if t > 5.0:
				_shot("select")
				_cmd("to_place")
				_cmd("place_slot", {"slot": 3})
				_cmd("place_slot", {"slot": 5})
				stage = 3
		3:
			if t > 6.0:
				_shot("place_partial")
				_cmd("place_slot", {"slot": 6})
				_cmd("set_principle", {"index": 1, "principle": "SPECIAL"})
				stage = 4
		4:
			if t > 7.0:
				_shot("place_done")
				_cmd("battle_start")
				Engine.time_scale = 3.0
				stage = 5
		5:
			if c.session != null and not c.session.speech.current.is_empty() and not bubble_shot and c.session.state.time > 20:
				bubble_shot = true
				_shot("bubble")
			if c.session != null and c.session.is_paused():
				sugg_seen += 1
				stage = 6
				t = 0.0
			if c.phase == GameController.RESULT:
				stage = 8
				t = 0.0
		6:
			if t > 0.8:
				_shot("suggest%d" % sugg_seen)
				if sugg_seen == 1:
					if c.session.active["has_change"]:
						_cmd("suggest_accept")
					else:
						_cmd("suggest_keep")
					stage = 5
				else:
					# '다른 원칙 고르기' 화면 열기
					main.control_view._other_mode = true
					stage = 7
					t = 0.0
		7:
			if t > 0.8:
				_shot("suggest_other")
				_cmd("suggest_other", {"principle": "DANGER"})
				stage = 5
		8:
			if t > 2.5:
				_shot("result")
				Engine.time_scale = 1.0
				var r: Dictionary = c.result
				print("RESULT ", r["outcome"], " hp=", r["hp"], " kills=", r["kills"], " time=", r["time"], " decisions=", r["decisions"].size())
				return true
	return t > 400.0
