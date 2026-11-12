extends SceneTree
## 성능 측정 (화면 없이): 전투 1틱 계산 시간과 AI 제안 계산 시간을 잰다.
##   godot --headless --path . --script res://tools/perf_bench.gd
## 운영 PC(i3-13100)에서 실행해 README의 표에 기록한다.
## 화면 FPS는 게임 실행 중 F3(또는 교사 메뉴 'FPS·성능 표시')로 확인.


func _init() -> void:
	GameData.ensure_loaded()
	var team := [{"type": "LIGHTNING", "slot": 3}, {"type": "BOMB", "slot": 5}, {"type": "FIRE", "slot": 6}]
	# 최악 조건: 적 40마리가 한꺼번에 사거리 근처
	var s := GameState.create(team, 1)
	s.spawns_enabled = false
	for i in 40:
		GameEngine._spawn(s, ["NORMAL", "FAST", "ARMORED"][i % 3])
		var e: Entities.Enemy = s.enemies[s.enemies.size() - 1]
		e.dist = 8.0 + i * 0.25
		e.pos = GameData.path.pos_at(e.dist)
		e.max_hp = 100000.0
		e.hp = e.max_hp
		e.speed = 0.0  # 제자리 (측정 중 기지에 도착해 게임이 끝나지 않도록)
	var n := 900
	var t0 := Time.get_ticks_usec()
	for i in n:
		GameEngine.step(s, GameData.dt())
	var per_tick := (Time.get_ticks_usec() - t0) / float(n) / 1000.0
	print("전투 1틱 (적 40마리, 캐릭터 3명): %.3f ms  (30Hz 예산 33.3ms의 %.1f%%)" % [per_tick, per_tick / 33.3 * 100.0])
	# 관찰기 포함
	var ob := CombatObserver.new()
	t0 = Time.get_ticks_usec()
	for i in n:
		GameEngine.step(s, GameData.dt())
		ob.observe(s)
	print("전투 1틱 + 관찰기: %.3f ms" % ((Time.get_ticks_usec() - t0) / float(n) / 1000.0))
	# AI 제안 (기준안 1 + 대안 6, 각각 '다시 계산 12초 + 미리 계산 10초')
	var sess := BattleSession.new(team, 3)
	sess.start()
	for i in int(80.0 / GameData.dt()):
		if sess.is_paused():
			sess.resolve("keep")
		sess.step()
	t0 = Time.get_ticks_usec()
	var r := Recommendation.analyze(sess.state, sess.observer, "test", {}, [], sess.replay_snapshot())
	print("AI 제안 계산 (가상 전투 7개 × 약 22초): %.1f ms  (적 %d마리)" % [(Time.get_ticks_usec() - t0) / 1000.0, sess.state.enemies.size()])
	# 한 판 전체
	t0 = Time.get_ticks_usec()
	BattleRunner.run_headless(team, "accept", 5)
	print("한 판 전체 화면 없이 계산: %.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	print("정적 메모리: %.1f MB" % (OS.get_static_memory_usage() / 1048576.0))
	quit(0)
