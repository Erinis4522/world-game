extends Node
## 시작점. 한 프로세스에 창 두 개를 만든다.
##   - 주 창(ARENA)   : 일반 모니터, 전투 화면 (GameController가 여기서 계산)
##   - 보조 창(CONTROL): 터치스크린, 조작 화면
## 모니터가 하나면 같은 화면에 두 창을 나란히 놓는 '분할 디버그 모드'로 뜬다.
##
## 실행 인자 (exe 뒤에 붙임):  --single  --windowed  --arena-screen=N  --control-screen=N

const SETTINGS_PATH := "user://display.cfg"

var controller: GameController
var arena: ArenaView
var control_window: Window
var control_view: ControlView
var arena_screen := 0
var control_screen := 1
var force_single := false
var windowed := false
var selfcheck_dir := ""  # --selfcheck=<폴더>: 자동으로 전투를 띄워 두 화면을 저장하고 종료
var _selfcheck_t := 0.0


func _ready() -> void:
	GameData.ensure_loaded()
	Engine.max_fps = 60
	_read_settings()
	controller = GameController.new()
	controller.name = "GameController"
	add_child(controller)

	var layer := CanvasLayer.new()
	add_child(layer)
	arena = ArenaView.new()
	arena.setup(controller)
	layer.add_child(arena)

	control_window = Window.new()
	control_window.title = "AI 디펜스 - 조작 화면"
	control_window.content_scale_size = Vector2i(1920, 1080)
	control_window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	control_window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	control_window.close_requested.connect(func(): pass)  # 실수로 닫혀도 전투에 영향 없도록 무시
	control_window.wrap_controls = false
	add_child(control_window)
	control_view = ControlView.new()
	control_view.setup(controller)
	control_view.teacher_action.connect(_on_teacher_action)
	control_window.add_child(control_view)
	control_window.window_input.connect(_on_window_input)

	get_window().title = "AI 디펜스 - 전투 화면"
	get_window().close_requested.connect(func(): get_tree().quit())
	call_deferred("apply_layout")


func _read_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		arena_screen = int(cfg.get_value("display", "arena_screen", 0))
		control_screen = int(cfg.get_value("display", "control_screen", 1))
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a == "--single":
			force_single = true
		elif a == "--windowed":
			windowed = true
		elif a.begins_with("--arena-screen="):
			arena_screen = int(a.get_slice("=", 1))
		elif a.begins_with("--selfcheck="):
			selfcheck_dir = a.get_slice("=", 1)
			force_single = true
			windowed = true
		elif a.begins_with("--control-screen="):
			control_screen = int(a.get_slice("=", 1))


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "arena_screen", arena_screen)
	cfg.set_value("display", "control_screen", control_screen)
	cfg.save(SETTINGS_PATH)


func is_dual() -> bool:
	return DisplayServer.get_screen_count() >= 2 and not force_single


func apply_layout() -> void:
	var main_win := get_window()
	var n := DisplayServer.get_screen_count()
	if is_dual():
		arena_screen = clampi(arena_screen, 0, n - 1)
		control_screen = clampi(control_screen, 0, n - 1)
		if control_screen == arena_screen:
			control_screen = (arena_screen + 1) % n
		_place_on_screen(main_win, arena_screen, not windowed)
		_place_on_screen(control_window, control_screen, not windowed)
	else:
		# 분할 디버그 모드: 한 화면에 전투(왼쪽 큰 창) + 조작(오른쪽 창)
		var s := 0
		var area := DisplayServer.screen_get_usable_rect(s)
		var gap := 8
		var aw := int(area.size.x * 0.58)
		var ah := int(aw * 9.0 / 16.0)
		var cw := area.size.x - aw - gap * 3
		var ch := int(cw * 9.0 / 16.0)
		main_win.mode = Window.MODE_WINDOWED
		main_win.size = Vector2i(aw, ah)
		main_win.position = area.position + Vector2i(gap, 40)
		control_window.mode = Window.MODE_WINDOWED
		control_window.size = Vector2i(cw, ch)
		control_window.position = area.position + Vector2i(aw + gap * 2, 40)
		control_window.show()


func _place_on_screen(w: Window, screen: int, fullscreen: bool) -> void:
	w.mode = Window.MODE_WINDOWED
	var rect := DisplayServer.screen_get_usable_rect(screen)
	w.position = rect.position + Vector2i(40, 40)
	w.size = Vector2i(mini(1280, rect.size.x - 80), mini(720, rect.size.y - 80))
	w.show()
	if fullscreen:
		w.current_screen = screen
		w.mode = Window.MODE_FULLSCREEN


func swap_screens() -> void:
	var t := arena_screen
	arena_screen = control_screen
	control_screen = t
	_save_settings()
	apply_layout()


func toggle_fullscreen() -> void:
	windowed = not windowed
	apply_layout()


func display_info() -> String:
	var n := DisplayServer.get_screen_count()
	var lines: Array = ["연결된 모니터: %d개  (%s)" % [n, "듀얼 모드" if is_dual() else "분할 디버그 모드(모니터 1개 또는 --single)"]]
	for i in n:
		var r := DisplayServer.screen_get_usable_rect(i)
		var role := ""
		if is_dual():
			role = "← 전투 화면" if i == arena_screen else ("← 터치 조작 화면" if i == control_screen else "")
		lines.append("  화면 %d: %d×%d, 위치(%d,%d) %s" % [i, r.size.x, r.size.y, r.position.x, r.position.y, role])
	lines.append("터치가 엉뚱한 화면에 찍히면: Windows 설정 → 'Tablet PC 설정' → [설정] → 터치 입력 화면 지정")
	lines.append("역할이 반대면 '화면 역할 바꾸기'(F9). 선택은 다음 실행에도 유지돼요.")
	return "\n".join(lines)


func _on_teacher_action(act: String) -> void:
	match act:
		"fullscreen":
			toggle_fullscreen()
		"swap":
			swap_screens()
		"display_info":
			control_view.show_teacher_info(display_info())
		"quit":
			get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	_handle_key(event)


func _on_window_input(event: InputEvent) -> void:
	_handle_key(event)


func _handle_key(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F10:
			control_view.toggle_teacher()
		KEY_F11:
			toggle_fullscreen()
		KEY_F9:
			swap_screens()
		KEY_F3:
			controller.command("teacher_toggle_fps")
		KEY_R:
			if event.ctrl_pressed:
				controller.command("teacher_reset")
		KEY_ESCAPE:
			if event.shift_pressed:
				get_tree().quit()


func _process(delta: float) -> void:
	if selfcheck_dir == "":
		return
	_selfcheck_t += delta
	if controller.phase == GameController.ATTRACT and _selfcheck_t > 1.0:
		controller.command("start")
		controller.command("recommended")
		controller.command("battle_start")
	if _selfcheck_t > 9.0:
		DirAccess.make_dir_recursive_absolute(selfcheck_dir)
		get_window().get_texture().get_image().save_png(selfcheck_dir.path_join("selfcheck_arena.png"))
		control_window.get_texture().get_image().save_png(selfcheck_dir.path_join("selfcheck_control.png"))
		var lines: Array = ["data: " + ", ".join(GameData.load_sources)]
		for a in AssetManifest.report():
			lines.append("%s %s" % ["PNG" if a[1] else "shape", a[0]])
		for type in GameData.hero_order:
			var rig := HeroSprite.rig_for(type)
			lines.append("rig %s: %s (%d parts)" % [type.to_lower(),str(rig != null),rig.parts.size() if rig != null else 0])
		for type in ["NORMAL","FAST","ARMORED","BOSS"]:
			lines.append("enemy frames %s: %d" % [type.to_lower(),EnemySprite.frame_rects(type).size()])
		var fa := FileAccess.open(selfcheck_dir.path_join("selfcheck.txt"), FileAccess.WRITE)
		fa.store_string("\n".join(lines))
		fa.close()
		get_tree().quit()
