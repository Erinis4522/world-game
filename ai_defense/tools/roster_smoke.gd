extends SceneTree
## 실제 선택 → 배치 → 전투 → 제안 → 결과 흐름. team=0/1/2.
var main: Node
var out_dir := "user://roster_smoke"
var team_index := 0
var team: Array
var attacks := {}
var specials := {}
var faces := {}
var elapsed := 0.0
var started := false
var suggestion_tested := false
var suggestion_capture_pending := false
var attack_shot := false

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out_dir=a.substr(4)
		if a.begins_with("team="): team_index=int(a.substr(5))
	team=[["SWORD","ARCHER","SNIPER"],["FIRE","ICE","LIGHTNING"],["BOMB","MARK","SWORD"]][team_index]
	DirAccess.make_dir_recursive_absolute(out_dir)
	call_deferred("run")

func command(action: String,args: Dictionary={}) -> void:
	var ack: Dictionary = main.controller.command(action,args)
	if not ack.ok:
		push_error("Command failed: "+action)
		quit(1)

func shot(tag: String) -> void:
	root.get_texture().get_image().save_png(out_dir.path_join(tag+"_arena.png"))
	main.control_window.get_texture().get_image().save_png(out_dir.path_join(tag+"_control.png"))
	print("SHOT ",tag)

func run() -> void:
	main=load("res://src/main.tscn").instantiate()
	main.force_single=true
	main.windowed=true
	root.add_child(main)
	await create_timer(0.5).timeout
	root.size=Vector2i(1280,720)
	main.control_window.size=Vector2i(1280,720)
	main.controller.battle_events.connect(on_events)
	command("start")
	await create_timer(0.35).timeout
	shot("01_cards")
	for type in team:
		main.control_view._focus=type
		await create_timer(0.25).timeout
		shot("02_detail_"+type.to_lower())
		command("confirm_hero",{"type":type})
	main.control_view._focus=""
	main.control_view._focus_shown=""
	await create_timer(0.35).timeout
	shot("03_lineup")
	command("to_place")
	for slot in [3,5,6]: command("place_slot",{"slot":slot})
	for i in 3: command("set_principle",{"index":i,"principle":"SPECIAL"})
	await create_timer(0.35).timeout
	shot("04_placement")
	command("battle_start")
	started=true
	Engine.time_scale=5.0

func on_events(events: Array) -> void:
	for e in events:
		if e.type=="ATTACK":
			var type: String=e.hero_type
			attacks[type]=attacks.get(type,0)+1
			if e.get("special",false): specials[type]=specials.get(type,0)+1
			var dx: float=e.points[0].x-e.from.x
			faces[type+"_"+("left" if dx<0 else "right")]=true

func capture_suggestion() -> void:
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	shot("06_suggestion")
	command("suggest_keep")
	suggestion_capture_pending=false

func finish() -> void:
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	shot("07_result")
	var report={"team":team,"attacks":attacks,"specials":specials,"facing":faces.keys(),"outcome":main.controller.result.outcome,"result_reached":true,"suggestion_checked":suggestion_tested}
	FileAccess.open(out_dir.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("ROSTER_SMOKE ",JSON.stringify(report))
	quit(0 if attacks.size()==3 else 1)

func _process(delta: float) -> bool:
	if not started: return false
	elapsed+=delta
	var c: GameController=main.controller
	if c.phase==GameController.RESULT:
		started=false
		call_deferred("finish")
		return false
	if elapsed>10 and not attack_shot:
		shot("05_battle")
		attack_shot=true
	if c.session!=null and c.session.is_paused():
		if not suggestion_tested:
			suggestion_tested=true
			suggestion_capture_pending=true
			call_deferred("capture_suggestion")
		elif not suggestion_capture_pending:
			command("suggest_keep")
	if elapsed>400:
		push_error("Battle timed out")
		quit(1)
	return false
