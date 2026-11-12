extends SceneTree
## 3D 서바이벌(v2) 자동 테스트
##   godot --headless --path . --script res://tests/sv_tests.gd
## 기존 타워디펜스 테스트(tests/run_tests.gd)와 별도. 실패가 있으면 종료 코드 1.

var _pass := 0
var _fail := 0
var _cur := ""


func _init() -> void:
	SvData.ensure_loaded()
	for t in ["t01_grid_and_flow", "t02_enemies_reach_base_without_clipping", "t03_player_move",
			"t04_attack_range", "t05_tactics", "t06_tactic_only_by_student", "t07_down_and_respawn",
			"t08_bubbles_grounded", "t09_determinism_and_clone", "t10_controller_flow", "t11_outcomes", "t12_performance"]:
		_cur = t
		var before := _fail
		call(t)
		print(("PASS " if _fail == before else "FAIL ") + t)
	print("\n결과(3D 서바이벌): 확인 %d개 통과, %d개 실패" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func check(c: bool, msg: String) -> void:
	if c:
		_pass += 1
	else:
		_fail += 1
		print("   ✗ [%s] %s" % [_cur, msg])


func run(s: SvSession, seconds: float, each: Callable = Callable()) -> void:
	var n := int(seconds / SvData.dt())
	for i in n:
		if s.is_over():
			break
		s.step()
		if each.is_valid():
			each.call(s)


func t01_grid_and_flow() -> void:
	var g := SvGrid.from_config()
	for o in SvData.cfg["map"]["obstacles"]:
		var r: Array = o["rect"]
		check(g.is_blocked(Vector2i(int(r[0]), int(r[1]))), "장애물 칸은 막힘")
	for gt in SvData.cfg["map"]["gates"]:
		var p := Vector2(float(gt["pos"][0]), float(gt["pos"][1]))
		check(g.flow_distance(p) < SvGrid.INF_D, "게이트 %s에서 기지까지 길이 있음" % gt["id"])
		var path := g.find_path(SvData.base_center() + Vector2(0, 3), p)
		check(path.size() >= 1 and path[path.size() - 1].distance_to(p) < 1.0, "아군이 게이트 %s까지 갈 수 있음" % gt["id"])
		var prev := SvData.base_center() + Vector2(0, 3)
		for wp in path:
			check(g.line_clear(prev, wp), "경로 구간이 장애물을 지나지 않음")
			prev = wp


func t02_enemies_reach_base_without_clipping() -> void:
	var s := SvSession.new(["SWORD", "ARCHER", "ICE"])
	for h in s.state.heroes:
		h.down_t = 9999.0  # 아군 없음 → 적이 기지까지 가야 함
	var bad := [0]
	run(s, 60.0, func(ss: SvSession):
		for e in ss.state.enemies:
			if e.alive and ss.state.grid.is_blocked(ss.state.grid.cell_of(e.pos)):
				bad[0] += 1)
	check(s.state.base_hp < s.state.base_hp_max, "막지 않으면 적이 기지를 공격함 (기지 %.0f)" % s.state.base_hp)
	check(bad[0] == 0, "적이 장애물 안으로 들어가지 않음 (%d틱 위반)" % bad[0])


func t03_player_move() -> void:
	var s := SvSession.new(["ARCHER", "SWORD", "ICE"])
	s.state.spawn_queue.clear()
	var target := Vector2(5.0, 15.5)
	check(s.move_player(target), "이동 명령 받음")
	run(s, 8.0)
	check(s.state.player().pos.distance_to(target) < 0.6, "누른 곳에 도착 (%.2f칸 차이)" % s.state.player().pos.distance_to(target))
	# 장애물 위를 누르면 가장 가까운 빈 칸으로
	var r: Array = SvData.cfg["map"]["obstacles"][0]["rect"]
	var on_block := Vector2(float(r[0]) + 0.5, float(r[1]) + 0.5)
	s.move_player(on_block)
	var inside := [0]
	run(s, 8.0, func(ss: SvSession):
		if ss.state.grid.is_blocked(ss.state.grid.cell_of(ss.state.player().pos)):
			inside[0] += 1)
	check(inside[0] == 0, "대표 캐릭터가 장애물 안으로 들어가지 않음")
	check(s.state.player().pos.distance_to(on_block) < 1.6, "장애물 바로 옆까지는 감")


func t04_attack_range() -> void:
	var bad := [0]
	var count := [0]
	var s := SvSession.new(["SNIPER", "FIRE", "LIGHTNING"])
	run(s, 90.0, func(ss: SvSession):
		for ev in ss.state.events:
			if ev["type"] == "ATTACK":
				count[0] += 1
				var h: SvState.SvHero = ss.state.heroes[ev["hero"]]
				if (ev["points"][0] as Vector2).distance_to(ev["from"]) > SvAI.hero_range(h) + 0.7:
					bad[0] += 1)
	check(count[0] > 50, "자동 공격이 일어남 (%d회)" % count[0])
	check(bad[0] == 0, "사거리 밖 공격 없음 (%d건)" % bad[0])


func t05_tactics() -> void:
	var dist := {}
	for tac in ["GATHER", "DEFEND"]:
		var s := SvSession.new(["SWORD", "ARCHER", "BOMB"])
		s.set_tactic(1, tac)
		s.set_tactic(2, tac)
		var sum := [0.0, 0.0, 0]
		run(s, 70.0, func(ss: SvSession):
			if ss.state.tick % 30 == 0:
				ss.move_player(Vector2(4.0, 3.0))  # 대표 캐릭터는 기지에서 먼 구석으로
				for i in [1, 2]:
					var h: SvState.SvHero = ss.state.heroes[i]
					if h.alive():
						sum[0] += h.pos.distance_to(ss.state.player().pos)
						sum[1] += h.pos.distance_to(SvData.base_center())
						sum[2] += 1)
		dist[tac] = [sum[0] / maxf(1, sum[2]), sum[1] / maxf(1, sum[2])]
	check(dist["GATHER"][0] < dist["DEFEND"][0], "집결은 대표 캐릭터 가까이 (%.1f < %.1f)" % [dist["GATHER"][0], dist["DEFEND"][0]])
	check(dist["DEFEND"][1] < dist["GATHER"][1], "기지 방어는 기지 가까이 (%.1f < %.1f)" % [dist["DEFEND"][1], dist["GATHER"][1]])
	# 집중공격: 가장 강한 적을 노림
	var s2 := SvSession.new(["SWORD", "ARCHER", "BOMB"])
	s2.state.spawn_queue.clear()
	var weak := SvEngine.spawn(s2.state, "NORMAL", "W")
	var strong := SvEngine.spawn(s2.state, "ARMORED", "E")
	s2.set_tactic(1, "FOCUS")
	run(s2, 1.0)
	check(s2.state.heroes[1].focus_id == strong.id, "집중공격은 가장 강한 적(갑옷)을 고름")


func t06_tactic_only_by_student() -> void:
	var s := SvSession.new(["SWORD", "ARCHER", "BOMB"])
	check(not s.set_tactic(0, "DEFEND"), "대표 캐릭터에는 전술 명령 없음")
	check(not s.set_tactic(1, "UNKNOWN"), "없는 전술은 거절")
	s.set_tactic(2, "FOCUS")
	var before := [s.state.heroes[1].tactic, s.state.heroes[2].tactic]
	var changed := [0]
	run(s, 120.0, func(ss: SvSession):
		if ss.state.heroes[1].tactic != before[0] or ss.state.heroes[2].tactic != before[1]:
			changed[0] += 1)
	check(changed[0] == 0, "AI가 스스로 전술을 바꾸지 않음")
	check(s.state.heroes[1].tactic == "GATHER" and s.state.heroes[2].tactic == "FOCUS", "명령한 동료만 바뀜")


func t07_down_and_respawn() -> void:
	var s := SvSession.new(["SWORD", "ARCHER", "BOMB"])
	var h: SvState.SvHero = s.state.heroes[1]
	var e := SvEngine.spawn(s.state, "NORMAL", "W")
	e.target_hero = 1
	SvEngine._hit_hero(s.state, h, 9999.0, e)
	check(not h.alive() and e.target_hero == -1, "쓰러지면 적이 다른 표적을 찾음")
	run(s, float(SvData.sec("hero", "respawn_seconds", 6)) + 0.5)
	check(h.alive() and h.hp == h.max_hp, "일정 시간 뒤 다시 일어남")
	check(h.pos.distance_to(SvData.base_center()) < 3.5, "기지에서 다시 일어남")


func t08_bubbles_grounded() -> void:
	var bad := [0]
	var shown := [0]
	var over := [0]
	var s := SvSession.new(["ICE", "MARK", "SWORD"])
	run(s, 150.0, func(ss: SvSession):
		if ss.bubbles.size() > SvSession.MAX_BUBBLES:
			over[0] += 1
		if ss.new_bubbles.is_empty():
			return
		var trig := ss.triggers(true)
		for b in ss.new_bubbles:
			shown[0] += 1
			if b["code"] in ["HERO_DOWN", "TACTIC_ACK"]:
				continue  # 실제 사건(쓰러짐·명령) 직후에 띄우는 보고
			var ok := false
			for t in trig:
				if t["code"] == b["code"]:
					ok = true
			if not ok:
				bad[0] += 1)
	check(shown[0] >= 3, "말풍선 보고가 나옴 (%d개)" % shown[0])
	check(bad[0] == 0, "말풍선은 그 순간 사실인 전황만 (%d건 위반)" % bad[0])
	check(over[0] == 0, "동시에 최대 2개")


func t09_determinism_and_clone() -> void:
	var sigs: Array = []
	for k in 2:
		var s := SvSession.new(["BOMB", "SNIPER", "FIRE"])
		s.set_tactic(1, "DEFEND")
		run(s, 40.0, func(ss: SvSession):
			if ss.state.tick % 60 == 0:
				ss.move_player(Vector2(8.0 + (ss.state.tick / 60) % 5, 9.0)))
		sigs.append(s.state.signature())
	check(sigs[0] == sigs[1], "같은 명령 → 같은 전투 결과")
	var s2 := SvSession.new(["BOMB", "SNIPER", "FIRE"])
	run(s2, 20.0)
	var before := s2.state.signature()
	var c := s2.state.clone()
	for i in 200:
		SvEngine.step(c, SvData.dt())
	check(s2.state.signature() == before, "복사본 계산이 원래 상태를 바꾸지 않음")


func t10_controller_flow() -> void:
	var c := SvController.new()
	root.add_child(c)
	check(not c.command("move_to", {"x": 1, "y": 1})["ok"], "전투 전 이동 명령은 무시")
	c.command("start", {}, 1)
	c.command("confirm_hero", {"type": "ICE"}, 2)
	var dup := c.command("confirm_hero", {"type": "ICE"}, 2)
	check(dup["duplicate"] and c.selected == ["ICE"], "같은 명령은 한 번만 반영")
	c.command("confirm_hero", {"type": "SWORD"}, 3)
	check(not c.command("battle_start", {}, 4)["ok"], "3명 전에는 시작 불가")
	c.command("confirm_hero", {"type": "BOMB"}, 5)
	check(c.command("battle_start", {}, 6)["ok"] and c.phase == SvController.INTRO, "작전 개시 연출")
	for i in 40:
		c._process(0.1)
	check(c.phase == SvController.BATTLE and c.session.state.player().type == "ICE", "첫 번째로 고른 캐릭터가 대표")
	check(c.command("set_tactic", {"hero": 2, "tactic": "FOCUS"}, 7)["ok"], "전투 중 동료 전술 명령")
	c.session.state.time = c.session.state.duration - 0.05
	for i in 30:
		c._process(1.0 / 30.0)
	for i in 60:
		c._process(1.0 / 30.0)
	check(c.phase == SvController.RESULT and not c.result.is_empty(), "시간이 다 되면 결과 화면")
	for i in 400:
		c._process(0.1)
	check(c.phase == SvController.ATTRACT and c.session == null and c.selected.is_empty(), "결과 후 자동 초기화")
	c.queue_free()


func t11_outcomes() -> void:
	var s := SvSession.new(["SWORD", "ARCHER", "ICE"])
	s.state.base_hp = 0.5
	var e := SvEngine.spawn(s.state, "NORMAL", "W")
	e.pos = SvData.base_center() + Vector2(0, 2.0)
	e.atk_cd = 0.0
	for h in s.state.heroes:
		h.down_t = 999.0
	run(s, 3.0)
	check(s.state.outcome == "lose", "기지 체력 0 → 실패")
	var s2 := SvSession.new(["SWORD", "ARCHER", "ICE"])
	s2.state.time = s2.state.duration - 0.01
	s2.step()
	check(s2.state.outcome == "win", "제한 시간까지 버티면 성공")


func t12_performance() -> void:
	var s := SvSession.new(["LIGHTNING", "BOMB", "FIRE"])
	s.state.spawn_queue.clear()
	for i in 20:
		var e := SvEngine.spawn(s.state, ["NORMAL", "FAST"][i % 2], ["W", "N", "E", "S"][i % 4])
		e.hp = 1e6
		e.max_hp = 1e6
	var t0 := Time.get_ticks_usec()
	run(s, 10.0)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / (10.0 / SvData.dt())
	check(ms < 3.0, "적 20마리 전투 1틱 %.3fms (30Hz 예산 33ms)" % ms)
	print("   (참고) 적 20마리 1틱 평균 %.3fms" % ms)
