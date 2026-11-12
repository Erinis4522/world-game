class_name SvPortraits
extends Node
## 게임 속 3D 모델(KayKit)로 얼굴 초상을 한 번씩 찍어 텍스처로 보관한다.
## 대화창·카드에서 '화면 속 캐릭터와 같은 모습'을 보여 주기 위함. 시작할 때 한 명씩, 한 번만 그린다.

static var tex: Dictionary = {}  # 종류 -> Texture2D

const SIZE := 192
var _vp: SubViewport
var _cam: Camera3D
var _queue: Array = []
var _cur: SvModels.Unit
var _cur_type := ""
var _wait := 0


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#e8eef5")
	e.ambient_light_energy = 0.7
	env.environment = e
	_vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-35), deg_to_rad(25), 0)
	sun.light_energy = 1.1
	_vp.add_child(sun)
	_cam = Camera3D.new()
	_cam.fov = 26.0
	_vp.add_child(_cam)
	_cam.look_at_from_position(Vector3(0.12, 0.86, 1.25), Vector3(0, 0.74, 0), Vector3.UP)
	_cam.current = true
	SvData.ensure_loaded()
	_queue = ["PLAYER", "BUILDER"]
	GameData.ensure_loaded()
	for t in GameData.hero_order:
		_queue.append(t)


func _process(_d: float) -> void:
	if _cur != null:
		_wait += 1
		if _wait == 1:
			_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		elif _wait >= 3:
			var img := _vp.get_texture().get_image()
			tex[_cur_type] = ImageTexture.create_from_image(img)
			_cur.root.queue_free()
			_cur = null
		return
	if _queue.is_empty():
		set_process(false)
		return
	_cur_type = str(_queue.pop_front())
	if tex.has(_cur_type):
		return
	_cur = SvModels.hero_unit(_cur_type)
	# 바닥 고리·원판은 빼고 몸만
	for c in _cur.root.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).visible = false
	_cur.root.rotation.y = deg_to_rad(12)
	_vp.add_child(_cur.root)
	if _cur.anim != null:
		_cur.anim.play("Idle")
		_cur.anim.seek(0.4, true)
		_cur.anim.pause()
	_wait = 0
