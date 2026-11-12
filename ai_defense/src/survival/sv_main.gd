extends Node
## 3D 서바이벌 시작점. 한 프로세스에 창 두 개:
##   - 주 창(일반 모니터): 3D 전투 화면 + 정보 오버레이 (전투 계산은 SvController 하나만)
##   - 보조 창(터치스크린): 2D 조작 패널 (3D를 그리지 않음)
## 모니터가 하나면 같은 화면에 두 창을 나란히 놓는다.
## 실행 인자: --single --windowed --arena-screen=N --control-screen=N --td(이전 타워디펜스) --selfcheck=<폴더>

const SETTINGS_PATH := "user://display.cfg"

var controller: SvController
var world: SvWorld3D
var hud: SvHud
var control_window: Window
var control_view: SvControlView
var arena_screen := 0
var control_screen := 1
var force_single := false
var windowed := false
var selfcheck_dir := ""
var _selfcheck_t := 0.0


func _ready() -> void:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a == "--td":
			get_tree().call_deferred("change_scene_to_file", "res://src/main.tscn")
			return
	SvData.ensure_loaded()
	Engine.max_fps = 60
	_read_settings()
	controller = SvController.new()
	controller.name = "SvController"
	add_child(controller)
	world = SvWorld3D.new()
	world.setup(controller)
	add_child(world)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = SvHud.new()
	hud.setup(controller, world)
	layer.add_child(hud)

	control_window = Window.new()
	control_window.title = "AI 디펜스 - 터치 조작"
	control_window.content_scale_size = Vector2i(1920, 1080)
	control_window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	control_window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	control_window.close_requested.connect(func(): pass)
	control_window.wrap_controls = false
	add_child(control_window)
	control_view = SvControlView.new()
	control_view.setup(controller)
	control_view.teacher_action.connect(_on_teacher_action)
	control_window.add_child(control_view)
	control_window.window_input.connect(_handle_key)
	# 두 창이 모두 화면 동기화(vsync)를 기다리면 프레임이 깎이므로, 가벼운 터치 창은 동기화하지 않는다
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED, control_window.get_window_id())

	get_window().title = "AI 디펜스 - 전투 화면"
	get_window().close_requested.connect(func(): get_tree().quit())
	get_window().size_changed.connect(_apply_render_scale)
	call_deferred("apply_layout")


func _apply_render_scale() -> void:
	## 내장그래픽 기준: 3D는 최대 720p 높이로 그리고 화면 크기에 맞춰 늘린다 (글자는 선명하게 유지)
	var h := float(get_window().size.y)
	var target := float(SvData.cfg.get("render_height", 720))
	get_viewport().scaling_3d_scale = clampf(target / maxf(h, 1.0), 0.5, 1.0)


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
		elif a.begins_with("--control-screen="):
			control_screen = int(a.get_slice("=", 1))
		elif a.begins_with("--selfcheck="):
			selfcheck_dir = a.get_slice("=", 1)
			force_single = true
			windowed = true


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
		_place(main_win, arena_screen, not windowed)
		_place(control_window, control_screen, not windowed)
	else:
		var area := DisplayServer.screen_get_usable_rect(0)
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
	_apply_render_scale()


func _place(w: Window, screen: int, fullscreen: bool) -> void:
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
	var lines: Array = ["연결된 모니터: %d개  (%s)" % [n, "듀얼 모드" if is_dual() else "한 화면 모드"]]
	for i in n:
		var r := DisplayServer.screen_get_usable_rect(i)
		var role := ""
		if is_dual():
			role = "← 3D 전투 화면" if i == arena_screen else ("← 터치 조작 화면" if i == control_screen else "")
		lines.append("  화면 %d: %d×%d %s" % [i, r.size.x, r.size.y, role])
	lines.append("3D 렌더링 배율: %.2f (높이 %d 기준)" % [get_viewport().scaling_3d_scale, int(SvData.cfg.get("render_height", 720))])
	lines.append("터치가 엉뚱한 화면에 찍히면: 제어판 → 'Tablet PC 설정' → [설정]에서 터치 화면 지정")
	return "\n".join(lines)


func _on_teacher_action(act: String) -> void:
	match act:
		"fullscreen":
			toggle_fullscreen()
		"swap":
			swap_screens()
		"display_info":
			control_view.show_teacher_info(display_info())
		"td":
			control_window.queue_free()
			get_tree().change_scene_to_file("res://src/main.tscn")
		"quit":
			get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
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
	if controller.phase == SvController.ATTRACT and _selfcheck_t > 1.0:
		controller.command("start")
		controller.command("recommended")
		controller.command("battle_start")
	if controller.phase == SvController.BATTLE and controller.session != null and controller.session.commands.is_empty():
		controller.command("move_to", {"x": 9.0, "y": 9.0})
	if _selfcheck_t > 14.0:
		DirAccess.make_dir_recursive_absolute(selfcheck_dir)
		get_window().get_texture().get_image().save_png(selfcheck_dir.path_join("selfcheck_arena.png"))
		control_window.get_texture().get_image().save_png(selfcheck_dir.path_join("selfcheck_control.png"))
		var fa := FileAccess.open(selfcheck_dir.path_join("selfcheck.txt"), FileAccess.WRITE)
		var st := controller.session.state if controller.session != null else null
		fa.store_string("phase=%s fps=%d enemies=%d time=%.1f renderer=%s scale3d=%.2f" % [controller.phase, Engine.get_frames_per_second(),
			st.enemies.size() if st != null else -1, st.time if st != null else -1.0,
			str(ProjectSettings.get_setting("rendering/renderer/rendering_method")), get_viewport().scaling_3d_scale])
		fa.close()
		get_tree().quit()
