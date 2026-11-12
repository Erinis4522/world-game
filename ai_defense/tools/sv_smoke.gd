extends SceneTree
## 3D 서바이벌 화면 점검: 실제 메인 장면으로 한 판을 자동 진행하며 두 화면 스크린샷 저장
##   godot --path . --script res://tools/sv_smoke.gd -- out=<폴더>

var main: Node
var out_dir := "user://sv_smoke"
var t := 0.0
var stage := 0
var shots := 0
var _seq := 5000
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


func _cmd(n: String, a: Dictionary = {}) -> Dictionary:
	_seq += 1
	var ack: Dictionary = main.controller.command(n, a, _seq)
	if not ack["ok"] and n != "joy":
		print("명령 실패: ", n)
	return ack


func _shot(tag: String) -> void:
	shots += 1
	root.get_texture().get_image().save_png(out_dir.path_join("%02d_%s_monitor.png" % [shots, tag]))
	main.control_window.get_texture().get_image().save_png(out_dir.path_join("%02d_%s_touch.png" % [shots, tag]))
	print("shot ", tag)


func _stroke(kind: String) -> Array:
	var out: Array = []
	for p in load("res://tools/sv_sim.gd").stroke(kind):
		out.append([p.x + 300.0, p.y + 300.0])
	return out


func _process(delta: float) -> bool:
	t += delta
	var c: SvController = main.controller
	match stage:
		0:
			if t > 0.4:
				main.control_window.size = Vector2i(1280, 720)
				root.size = Vector2i(1280, 720)
			if t > 1.5:
				_shot("attract")
				_cmd("start")
				stage = 1
		1:
			if t > 2.0 and main.control_view._focus == "":
				main.control_view._focus = "ICE"
			if t > 2.8:
				_shot("select_detail")
				main.control_view._focus = ""
				main.control_view._focus_shown = ""
				_cmd("confirm_hero", {"type": "ICE"})
				_cmd("confirm_hero", {"type": "FIRE"})
				_cmd("confirm_hero", {"type": "SNIPER"})
				stage = 2
		2:
			if t > 3.8:
				_shot("select_team")
				_cmd("battle_start")
				stage = 3
		3:
			if c.phase == SvController.BATTLE:
				_cmd("joy", {"x": -0.8, "y": -0.6})
				stage = 4
				t = 0.0
		4:
			if t > 4.0:
				_cmd("joy", {"x": 0.0, "y": 0.0})
				_shot("battle_start")
				_cmd("open_principle", {"hero": 2})
				stage = 5
				t = 0.0
		5:
			if t > 0.8:
				_shot("principle_slowmo")
				_cmd("set_principle", {"hero": 2, "principle": "SPECIAL"})
				stage = 6
				t = 0.0
		6:
			if t > 6.0:
				_cmd("open_sketch")
				_cmd("submit_sketch", {"points": _stroke("LINE")})
				stage = 7
				t = 0.0
		7:
			if t > 0.8:
				_shot("sketch_wall_proposal")
				var pr: Dictionary = c.session.proposal
				print("벽 제안: ok=", pr.get("ok"), " ", pr.get("shape", ""), " ", pr.get("cells", []).size(), "칸 ", pr.get("road_name", ""), " / ", pr.get("reason", ""))
				_cmd("accept_proposal")
				stage = 8
				t = 0.0
		8:
			if t > 1.2:
				_shot("wall_built")
				Engine.time_scale = 2.0
				stage = 9
				t = 0.0
		9:
			if c.session.state.energy >= 8 and c.session.state.time > 40:
				Engine.time_scale = 1.0
				_cmd("open_sketch")
				_cmd("submit_sketch", {"points": _stroke("CIRCLE")})
				stage = 10
				t = 0.0
			elif not _bubble_shot and not c.session.bubbles.is_empty() and c.session.state.time > 25:
				_bubble_shot = true
				_shot("bubble")
		10:
			if t > 0.8:
				_shot("sketch_ult_proposal")
				_cmd("accept_proposal")
				stage = 11
				t = 0.0
		11:
			if t > 0.35:
				_shot("ult_effect")
				Engine.time_scale = 6.0
				stage = 12
		12:
			if c.phase == SvController.RESULT:
				Engine.time_scale = 1.0
				stage = 13
				t = 0.0
		13:
			if t > 1.0:
				_shot("result")
				var r: Dictionary = c.result
				print("RESULT ", r["outcome"], " base=", r["base_hp"], " kills=", r["kills"], " walls=", r["walls"], " cmds=", r["commands"])
				return true
	return t > 900.0
