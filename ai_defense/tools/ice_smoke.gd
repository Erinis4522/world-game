extends SceneTree
## 실제 게임에서 빙결 원화·배치·공격·제안·결과를 확인한다. -- out=<folder>

var main: Node
var out_dir := "user://ice_smoke"
var attacks := 0
var specials := 0
var faces := {}
var captured := {}
var battle_elapsed := 0.0
var started := false

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out_dir = a.substr(4)
	DirAccess.make_dir_recursive_absolute(out_dir)
	call_deferred("run")

func command(action: String, args: Dictionary = {}) -> void:
	var ack: Dictionary = main.controller.command(action,args)
	if not ack["ok"]:
		push_error("Command failed: " + action)
		quit(1)

func shot(tag: String) -> void:
	root.get_texture().get_image().save_png(out_dir.path_join(tag+"_arena.png"))
	main.control_window.get_texture().get_image().save_png(out_dir.path_join(tag+"_control.png"))
	print("SHOT ",tag)

func run() -> void:
	main = load("res://src/main.tscn").instantiate()
	main.force_single = true
	main.windowed = true
	root.add_child(main)
	await create_timer(0.6).timeout
	root.size = Vector2i(1280,720)
	main.control_window.size = Vector2i(1280,720)
	main.controller.battle_events.connect(on_events)
	command("start")
	await create_timer(0.4).timeout
	shot("01_cards")
	main.control_view._focus = "ICE"
	await create_timer(0.8).timeout
	shot("02_ice_illustration")
	command("confirm_hero",{"type":"ICE"})
	command("confirm_hero",{"type":"SWORD"})
	command("confirm_hero",{"type":"ARCHER"})
	main.control_view._focus = ""
	main.control_view._focus_shown = ""
	await create_timer(0.5).timeout
	shot("03_lineup")
	command("to_place")
	for slot in [3,5,6]:
		command("place_slot",{"slot":slot})
	command("set_principle",{"index":0,"principle":"SPECIAL"})
	await create_timer(0.6).timeout
	shot("04_placement")
	command("battle_start")
	started = true
	Engine.time_scale = 3.0

func on_events(events: Array) -> void:
	for event in events:
		if event["type"] == "ATTACK" and event["hero_type"] == "ICE":
			attacks += 1
			if event.get("special",false):
				specials += 1
			var dx: float = event["points"][0].x-event["from"].x
			faces["left" if dx < 0.0 else "right"] = true

func _process(delta: float) -> bool:
	if not started:
		return false
	battle_elapsed += delta
	var c: GameController = main.controller
	var a: HeroSprite.Anim = main.arena.anims.get("h0")
	if a != null:
		var p := a.progress(main.arena.now)
		var tag := "06_special" if a.special else "05_attack"
		if p > 0.3 and p < 0.7 and not captured.has(tag):
			shot(tag)
			captured[tag] = true
	if c.session != null and c.session.is_paused():
		command("suggest_keep")
	if c.phase == GameController.RESULT:
		shot("07_result")
		var report := {"attacks":attacks,"special_attacks":specials,"facing":faces.keys(),"result":c.result,"rig_parts":HeroSprite.rig_for("ICE").parts.size()}
		FileAccess.open(out_dir.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
		print("ICE_SMOKE ",JSON.stringify(report))
		quit(0 if attacks > 0 and specials > 0 and captured.has("05_attack") else 1)
	if battle_elapsed > 400.0:
		push_error("Ice battle timed out")
		quit(1)
	return false
