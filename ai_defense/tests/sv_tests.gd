extends SceneTree
## 3D 서바이벌 v2 자동 테스트 (길 따라 오는 적 / 조이스틱 / 동료 원칙 / 그림 건설·필살기)
##   godot --headless --path . --script res://tests/sv_tests.gd
## 기존 타워디펜스 테스트(tests/run_tests.gd)와 별도. 실패가 있으면 종료 코드 1.

const Sim = preload("res://tools/sv_sim.gd")

var _pass := 0
var _fail := 0
var _cur := ""


func _init() -> void:
	SvData.ensure_loaded()
	for t in ["t01_map", "t02_enemies_follow_roads", "t03_joystick", "t04_companion_zones", "t05_builder_follows",
			"t06_principle_only_by_student", "t07_sketch_shapes", "t08_wall_plan_and_approval", "t09_wall_changes_enemies",
			"t10_ultimate", "t11_pause_and_slowmo", "t12_bubbles_grounded", "t13_determinism_and_clone",
			"t14_controller_flow", "t15_outcomes", "t16_performance"]:
		_cur = t
		var before := _fail
		call(t)
		print(("PASS " if _fail == before else "FAIL ") + t)
	print("\n결과(3D 서바이벌 v2): 확인 %d개 통과, %d개 실패" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func check(c: bool, msg: String) -> void:
	if c:
		_pass += 1
	else:
		_fail += 1
		print("   ✗ [%s] %s" % [_cur, msg])


func run(s: SvSession, seconds: float, each: Callable = Callable()) -> void:
	for i in int(seconds / SvData.dt()):
		if s.is_over():
			break
		s.step()
		if each.is_valid():
			each.call(s)


func session(team := ["ICE", "FIRE", "SNIPER"]) -> SvSession:
	return SvSession.new(team)


func t01_map() -> void:
	var g := SvGrid.from_config()
	var trees := 0
	for k in g.kind.values():
		if k == "tree":
			trees += 1
	check(trees > 80, "숲이 있음 (%d칸)" % trees)
	for r in SvData.roads():
		var gp := SvData.gate_pos(r["id"])
		check(g.is_road(g.cell_of(gp)), "%s 게이트는 길 위" % r["name"])
		check(g.flow_distance(gp) < SvGrid.INF_D, "%s에서 마을까지 갈 수 있음" % r["name"])
	var bc := SvData.base_center()
	check(g.is_blocked(g.cell_of(bc)), "마을 중심(성)은 막힘")
	var s := session()
	for h in s.state.heroes:
		check(not s.state.grid.is_blocked(s.state.grid.cell_of(h.pos)), "아군 시작 위치는 빈 칸 (%s)" % h.type)
	check(s.state.heroes.size() == 5 and s.state.player().role == "player" and s.state.builder().role == "builder", "나 + 든든이 + 동료 3명")


func t02_enemies_follow_roads() -> void:
	var s := session()
	for h in s.state.heroes:
		h.down_t = 9999.0
	var on := [0, 0]
	var inside := [0]
	run(s, 100.0, func(ss: SvSession):
		for e in ss.state.enemies:
			if not e.alive:
				continue
			on[1] += 1
			if ss.state.grid.is_road(ss.state.grid.cell_of(e.pos)):
				on[0] += 1
			if ss.state.grid.is_blocked(ss.state.grid.cell_of(e.pos)):
				inside[0] += 1)
	var ratio := float(on[0]) / maxf(1.0, on[1])
	check(ratio > 0.85, "적은 대부분 길을 따라옴 (%.0f%%)" % (ratio * 100))
	check(inside[0] == 0, "적이 숲·건물 안으로 들어가지 않음 (%d)" % inside[0])
	check(s.state.base_hp < s.state.base_hp_max, "막지 않으면 마을이 공격받음")


func t03_joystick() -> void:
	var s := session()
	s.state.spawn_queue.clear()
	var p0 := s.state.player().pos
	s.joystick(Vector2(0, -1))
	run(s, 1.0)
	var p1 := s.state.player().pos
	check(p1.y < p0.y - 2.0 and absf(p1.x - p0.x) < 0.5, "위로 밀면 북쪽으로 이동 (%.1f칸)" % (p0.y - p1.y))
	s.joystick(Vector2.ZERO)
	run(s, 0.5)
	check(s.state.player().pos.distance_to(p1) < 2.2, "손을 떼면 멈춤")
	var blocked := [0]
	s.joystick(Vector2(-1, 0.3))
	run(s, 8.0, func(ss: SvSession):
		if ss.state.grid.is_blocked(ss.state.grid.cell_of(ss.state.player().pos)):
			blocked[0] += 1)
	check(blocked[0] == 0, "숲·건물을 뚫고 지나가지 않음")


func t04_companion_zones() -> void:
	var s := session()
	s.state.spawn_queue.clear()
	run(s, 15.0)
	for h in s.state.companions():
		var guard := SvData.zone_guard(h.zone)
		check(h.pos.distance_to(guard) < 3.0, "적이 없으면 %s은 맡은 길(%s)을 지킴" % [h.type, h.zone])
	var zones: Dictionary = {}
	for h in s.state.companions():
		zones[h.zone] = true
	check(zones.size() == 3, "동료 3명이 서로 다른 길을 맡음")


func t05_builder_follows() -> void:
	var s := session()
	s.state.spawn_queue.clear()
	var far := [0, 0]
	var dirs := [Vector2(1, 0), Vector2(0, -1), Vector2(-1, 0)]
	for d in dirs:
		s.joystick(d)
		run(s, 2.5, func(ss: SvSession):
			far[1] += 1
			if ss.state.builder().pos.distance_to(ss.state.player().pos) > 3.5:
				far[0] += 1)
	check(float(far[0]) / far[1] < 0.2, "든든이는 늘 내 옆을 따라옴 (멀리 떨어진 비율 %.0f%%)" % (100.0 * far[0] / far[1]))


func t06_principle_only_by_student() -> void:
	var s := session()
	check(not s.set_principle(0, "DANGER") and not s.set_principle(1, "DANGER"), "나와 든든이는 원칙 대상 아님")
	check(not s.set_principle(2, "XX"), "없는 원칙 거절")
	check(s.set_principle(3, "SPECIAL"), "동료 원칙 설정")
	var changed := [0]
	run(s, 90.0, func(ss: SvSession):
		if ss.state.heroes[2].principle != "NEAREST" or ss.state.heroes[3].principle != "SPECIAL" or ss.state.heroes[4].principle != "NEAREST":
			changed[0] += 1)
	check(changed[0] == 0, "AI가 스스로 원칙을 바꾸지 않음, 고른 동료만 바뀜")


func t07_sketch_shapes() -> void:
	var cases := {"LINE": "LINE", "CIRCLE": "CIRCLE", "TRIANGLE": "TRIANGLE", "ZIGZAG": "ZIGZAG"}
	for k in cases.keys():
		var r := SvSketch.analyze(Sim.stroke(k))
		check(r["kind"] == cases[k] and not r["ambiguous"], "%s 그림 → %s (결과 %s)" % [k, cases[k], r["kind"]])
	var L := PackedVector2Array()
	for i in 15:
		L.append(Vector2(0, i * 12))
	for i in 15:
		L.append(Vector2(i * 12, 180))
	var rl := SvSketch.analyze(L)
	check(rl["kind"] == "LINE" and rl["shape"] == "ㄱ자", "ㄱ자 선 → 벽 (모양 %s)" % rl["shape"])
	var U := PackedVector2Array()
	for i in 12:
		U.append(Vector2(0, i * 15))
	for i in 12:
		U.append(Vector2(i * 15, 180))
	for i in 12:
		U.append(Vector2(180, 180 - i * 15))
	var ru := SvSketch.analyze(U)
	check(ru["kind"] == "LINE" and ru["shape"] == "U자", "U자 선 → 벽 (모양 %s)" % ru["shape"])
	var tiny := SvSketch.analyze(PackedVector2Array([Vector2(0, 0), Vector2(5, 5), Vector2(10, 8), Vector2(12, 9)]))
	check(tiny["kind"] == "UNKNOWN", "너무 작은 그림은 해석하지 않음")
	var amb := PackedVector2Array()
	for p in [[Vector2(0, 0), Vector2(100, 100)], [Vector2(100, 100), Vector2(200, 0)], [Vector2(200, 0), Vector2(300, 100)]]:
		for i in 12:
			amb.append(p[0].lerp(p[1], i / 12.0))
	var ra := SvSketch.analyze(amb)
	check(ra["ambiguous"] and ra["choices"].has("LINE") and ra["choices"].has("ZIGZAG"), "애매한 그림은 학생에게 물어봄")


func t08_wall_plan_and_approval() -> void:
	var s := session()
	s.state.player().pos = Vector2(8.5, 17.5)  # 서쪽 숲길 근처
	var pr := s.submit_sketch(Sim.stroke("LINE"))
	check(pr.get("ok", false) and pr["kind"] == "WALL", "직선 → 벽 제안")
	if not pr.get("ok", false):
		return
	check(s.state.grid.walls.is_empty() and s.state.energy == int(SvData.sec("build", "start_energy", 8)), "승인 전에는 아무것도 바뀌지 않음")
	var ys: Dictionary = {}
	var road_cells := 0
	for c in pr["cells"]:
		ys[c.y] = true
		if s.state.grid.is_road(c):
			road_cells += 1
	check(ys.size() <= 2, "가로로 그린 선 → 가로 벽 (모양 유지, 행 %d개)" % ys.size())
	check(road_cells >= 2 and pr["metrics"]["gate_gain"] > 1.0, "길을 가로질러 적이 돌아가야 하는 위치를 고름 (길 %d칸, 비용 +%.0f)" % [road_cells, pr["metrics"]["gate_gain"]])
	check(pr["center"].distance_to(s.state.player().pos) <= float(SvData.sec("build", "search_radius", 14)) + 1, "내 근처에 세움")
	check(pr["cost"] <= s.state.energy and not pr["pros"].is_empty() and not pr["cons"].is_empty(), "비용·장점·단점 제시")
	check(not pr["metrics"]["ally_cut"], "우리 이동 길을 완전히 막지 않음")
	s.cancel_proposal()
	check(s.state.grid.walls.is_empty() and s.proposal.is_empty(), "취소하면 건설 안 함")
	s.submit_sketch(Sim.stroke("LINE"))
	var res := s.accept_proposal()
	check(not res.is_empty() and s.state.grid.walls.size() == pr["cells"].size(), "승인하면 그 칸에 벽이 생김")
	check(s.state.energy == int(SvData.sec("build", "start_energy", 8)) - pr["cost"], "에너지 사용")
	var s2 := session()
	s2.state.energy = 1
	s2.state.player().pos = Vector2(8.5, 17.5)
	var pr2 := s2.submit_sketch(Sim.stroke("LINE"))
	check(not pr2.get("ok", true) and str(pr2.get("reason", "")).contains("에너지"), "에너지가 모자라면 이유를 알려 줌")


func t09_wall_changes_enemies() -> void:
	var s := session()
	for h in s.state.heroes:
		if h.role != "player":
			h.down_t = 9999.0  # 동료는 빼고, 벽을 그릴 '나'만 서쪽 숲길 근처에
	s.state.player().pos = Vector2(8.5, 17.5)
	var gp := SvData.gate_pos("S")
	var before := s.state.grid.flow_distance(gp)
	s.submit_sketch(Sim.stroke("LINE"))
	s.accept_proposal()
	var after := s.state.grid.flow_distance(gp)
	s.state.player().down_t = 9999.0  # 건설 뒤에는 적이 벽에 닿도록 '나'도 빠짐
	check(after > before + 1.0, "벽을 세우면 적의 이동 비용이 늘어남 (%.0f → %.0f)" % [before, after])
	var hits := [0]
	var detour := [0]
	run(s, 60.0, func(ss: SvSession):
		for ev in ss.state.events:
			if ev["type"] == "WALL_HIT":
				hits[0] += 1
		for e in ss.state.enemies:
			if e.alive and e.gate == "S" and not ss.state.grid.is_road(ss.state.grid.cell_of(e.pos)):
				detour[0] += 1)
	check(hits[0] > 0 or detour[0] > 0, "적이 벽을 부수거나 돌아감 (공격 %d, 우회 %d틱)" % [hits[0], detour[0]])
	var total_hp := 0.0
	for c in s.state.grid.walls.keys():
		total_hp += float(s.state.grid.walls[c]["hp"])
	var full: float = float(SvData.sec("build", "wall_hp", 90)) * s.state.walls[0]["cells"].size() if not s.state.walls.is_empty() else 0.0
	check(hits[0] == 0 or total_hp < full, "벽은 공격받으면 내구도가 줄어듦")


func t10_ultimate() -> void:
	var s := session()
	s.state.spawn_queue.clear()
	var h: SvState.SvHero = s.state.heroes[2]  # 동그라미 = 첫째 동료
	for i in 4:
		var e := SvEngine.spawn(s.state, "NORMAL", "S")
		e.pos = h.pos + Vector2(1.0 + i * 0.3, 0.5)
	var pr := s.submit_sketch(Sim.stroke("CIRCLE"))
	check(pr.get("ok", false) and pr["kind"] == "ULT" and pr["hero"] == 2, "동그라미 → 첫째 동료 필살기 제안")
	check(pr.get("expected", 0) >= 3, "적이 많이 맞는 곳을 계산 (예상 %d)" % pr.get("expected", 0))
	var hp0 := 0.0
	for e in s.state.enemies:
		hp0 += e.hp
	var ev := s.accept_proposal()
	var hp1 := 0.0
	for e in s.state.enemies:
		hp1 += maxf(0.0, e.hp) if e.alive else 0.0
	check(not ev.is_empty() and hp1 < hp0, "승인하면 필살기 발동, 적이 피해를 입음")
	var pr2 := s.submit_sketch(Sim.stroke("CIRCLE"))
	check(not pr2.get("ok", true), "대기시간·에너지 때문에 바로 다시는 못 씀")
	var tri := s.submit_sketch(Sim.stroke("TRIANGLE"))
	check(not tri.get("ok", false) or tri["hero"] == 3, "세모 → 둘째 동료")


func t11_pause_and_slowmo() -> void:
	var c := SvController.new()
	root.add_child(c)
	c.command("start")
	for t in ["ICE", "FIRE", "SNIPER"]:
		c.command("confirm_hero", {"type": t})
	c.command("battle_start")
	for i in 40:
		c._process(0.1)
	check(c.phase == SvController.BATTLE, "전투 시작")
	c.command("open_principle", {"hero": 3})
	var t0 := c.session.state.time
	for i in 30:
		c._process(1.0 / 30.0)
	var slow := c.session.state.time - t0
	check(slow > 0.0 and slow < 0.3, "원칙 화면 동안 게임이 아주 느려짐 (1초에 %.2f초)" % slow)
	check(c.command("set_principle", {"hero": 3, "principle": "DANGER"})["ok"] and c.overlay == "", "원칙을 고르면 원래 화면으로")
	c.command("open_sketch")
	var t1 := c.session.state.time
	for i in 30:
		c._process(1.0 / 30.0)
	check(c.session.state.time == t1, "그림 그리는 동안 게임 멈춤")
	check(not c.command("joy", {"x": 1, "y": 0})["ok"], "그림 중에는 조이스틱 무시")
	c.command("close_overlay")
	c.queue_free()


func t12_bubbles_grounded() -> void:
	var bad := [0]
	var shown := [0]
	var over := [0]
	var s := session(["MARK", "SWORD", "BOMB"])
	run(s, 150.0, func(ss: SvSession):
		if ss.bubbles.size() > SvSession.MAX_BUBBLES:
			over[0] += 1
		if ss.new_bubbles.is_empty():
			return
		var trig := ss.triggers(true)
		for b in ss.new_bubbles:
			shown[0] += 1
			if b["code"] in ["HERO_DOWN", "PRINCIPLE_ACK"]:
				continue
			var ok := false
			for t in trig:
				if t["code"] == b["code"]:
					ok = true
			if not ok:
				bad[0] += 1)
	check(shown[0] >= 3, "말풍선 보고가 나옴 (%d개)" % shown[0])
	check(bad[0] == 0, "말풍선은 그 순간 사실인 전황만 (%d건 위반)" % bad[0])
	check(over[0] == 0, "동시에 최대 2개")


func t13_determinism_and_clone() -> void:
	var sigs: Array = []
	for k in 2:
		var s := session()
		s.set_principle(2, "DANGER")
		run(s, 40.0, func(ss: SvSession):
			if ss.state.tick % 45 == 0:
				ss.joystick(Vector2.from_angle(ss.state.tick * 0.1)))
		sigs.append(s.state.signature())
	check(sigs[0] == sigs[1], "같은 입력 → 같은 결과")
	var s2 := session()
	run(s2, 20.0)
	var before := s2.state.signature()
	var c := s2.state.clone()
	for i in 200:
		SvEngine.step(c, SvData.dt())
	check(s2.state.signature() == before, "복사본 계산이 원래 상태를 바꾸지 않음")
	var s3 := session()
	s3.state.player().pos = Vector2(8.5, 17.5)
	var sig3 := s3.state.signature()
	s3.submit_sketch(Sim.stroke("LINE"))
	check(s3.state.signature() == sig3, "AI의 배치 계산(벽 시험 건설)은 실제 맵을 바꾸지 않음")


func t14_controller_flow() -> void:
	var c := SvController.new()
	root.add_child(c)
	c.command("start", {}, 1)
	c.command("confirm_hero", {"type": "ICE"}, 2)
	var dup := c.command("confirm_hero", {"type": "ICE"}, 2)
	check(dup["duplicate"] and c.selected == ["ICE"], "같은 명령은 한 번만 반영")
	c.command("confirm_hero", {"type": "SWORD"}, 3)
	check(not c.command("battle_start", {}, 4)["ok"], "3명 전에는 시작 불가")
	c.command("confirm_hero", {"type": "BOMB"}, 5)
	check(c.command("battle_start", {}, 6)["ok"], "전투 시작")
	for i in 40:
		c._process(0.1)
	var v0 := c.state_version
	c.command("joy", {"x": 0.5, "y": 0}, 7)
	check(c.state_version == v0, "조이스틱 명령은 화면을 다시 만들지 않음")
	c.session.state.time = c.session.state.duration - 0.05
	for i in 100:
		c._process(1.0 / 30.0)
	check(c.phase == SvController.RESULT, "시간이 다 되면 결과")
	for i in 400:
		c._process(0.1)
	check(c.phase == SvController.ATTRACT and c.session == null and c.selected.is_empty(), "결과 후 자동 초기화")
	c.queue_free()


func t15_outcomes() -> void:
	var s := session()
	s.state.base_hp = 0.5
	var e := SvEngine.spawn(s.state, "NORMAL", "S")
	e.pos = SvData.base_center() + Vector2(0, -3.0)
	e.atk_cd = 0.0
	for h in s.state.heroes:
		h.down_t = 999.0
	run(s, 3.0)
	check(s.state.outcome == "lose", "마을 HP 0 → 실패")
	var s2 := session()
	s2.state.time = s2.state.duration - 0.01
	s2.step()
	check(s2.state.outcome == "win", "제한 시간까지 버티면 성공")


func t16_performance() -> void:
	var s := session(["LIGHTNING", "BOMB", "FIRE"])
	s.state.spawn_queue.clear()
	for i in 20:
		var e := SvEngine.spawn(s.state, ["NORMAL", "FAST"][i % 2], "S")
		e.hp = 1e6
		e.max_hp = 1e6
	var t0 := Time.get_ticks_usec()
	run(s, 10.0)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / (10.0 / SvData.dt())
	check(ms < 3.0, "적 20마리 전투 1틱 %.3fms" % ms)
	s.state.player().pos = Vector2(8.5, 17.5)
	s.state.energy = 20
	var t1 := Time.get_ticks_usec()
	s.submit_sketch(Sim.stroke("LINE"))
	var pms := (Time.get_ticks_usec() - t1) / 1000.0
	check(pms < 700.0, "그림 해석+배치 계산 %.0fms (멈춘 상태에서 계산)" % pms)
	print("   (참고) 1틱 %.3fms, 배치 계산 %.0fms" % [ms, pms])
