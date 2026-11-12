extends SceneTree
## 자동 로직 테스트 (PRD 9장 '반드시 자동화할 로직 테스트' 1~11 + 데이터 검사)
##   godot --headless --path . --script res://tests/run_tests.gd
## 실패가 하나라도 있으면 종료 코드 1.

var _pass := 0
var _fail := 0
var _current := ""


func _init() -> void:
	GameData.ensure_loaded()
	var tests := [
		"t00_data", "t01_effects", "t02_principle_changes_target", "t03_range_and_retarget",
		"t04_speech_truth_and_cooldown", "t05_events_once", "t06_gap_and_cancel",
		"t07_choice_applies_to_one_hero", "t08_recommendation_consistency", "t09_determinism_no_mutation",
		"t10_controller_flow", "t11_command_once", "t12_hero_art_and_anim", "t13_confirm_flow", "t14_ice_rig", "t15_roster_art", "t16_world_art",
	]
	for t in tests:
		_current = t
		var before := _fail
		call(t)
		print(("PASS " if _fail == before else "FAIL ") + t)
	print("\n결과: 확인 %d개 통과, %d개 실패" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("   ✗ [%s] %s" % [_current, msg])


# ---------- 도우미 ----------

func make_state(types: Array, slots: Array, principles: Array = []) -> GameState:
	var team: Array = []
	for i in types.size():
		team.append({"type": types[i], "slot": slots[i], "principle": principles[i] if i < principles.size() else "NEAREST"})
	var s := GameState.create(team, 7)
	s.spawns_enabled = false
	return s


func put_enemy(s: GameState, type: String, dist: float) -> Entities.Enemy:
	GameEngine._spawn(s, type)
	var e: Entities.Enemy = s.enemies[s.enemies.size() - 1]
	e.dist = dist
	e.pos = GameData.path.pos_at(dist)
	e.prev_pos = e.pos
	return e


func step_n(s: GameState, n: int) -> Array:
	var all: Array = []
	for i in n:
		GameEngine.step(s, GameData.dt())
		all.append_array(s.events)
	return all


func freeze(s: GameState) -> void:
	for e in s.enemies:
		e.speed = 0.0


func dist_at(p: Vector2) -> float:
	## 경로 위 점 p의 진행 거리
	var best := INF
	var bd := 0.0
	var acc := 0.0
	var pts := GameData.path.points
	for i in range(1, pts.size()):
		var c := Geometry2D.get_closest_point_to_segment(p, pts[i - 1], pts[i])
		var d := c.distance_to(p)
		if d < best:
			best = d
			bd = acc + pts[i - 1].distance_to(c)
		acc += pts[i - 1].distance_to(pts[i])
	return bd


func full_game(seed_value: int, types: Array, slots: Array, policy := "keep", inspector: Callable = Callable()) -> BattleSession:
	var team: Array = []
	for i in 3:
		team.append({"type": types[i], "slot": slots[i]})
	var s := BattleSession.new(team, seed_value)
	s.start()
	var guard := 0
	while not s.is_over() and guard < 20000:
		guard += 1
		if s.is_paused():
			if policy == "accept" and s.active["has_change"]:
				s.resolve("accept")
			else:
				s.resolve("keep")
			continue
		s.step()
		if inspector.is_valid():
			inspector.call(s)
	return s


# ---------- 테스트 ----------

func t00_data() -> void:
	check(GameData.hero_order.size() == 8, "캐릭터 8종")
	check(GameData.enemies.size() == 4, "적 4종")
	check(GameData.waves.size() == 3, "웨이브 3개")
	check(GameData.slots.size() >= 8 and GameData.slots.size() <= 10, "설치 슬롯 8~10곳")
	for i in GameData.slots.size():
		check(GameData.path.distance_to_path(GameData.slots[i]) >= 0.8, "슬롯 %d은 길 위가 아님" % (i + 1))
	for code in ["BASE_HIT", "BASE_DANGER", "FAST_PASSED", "ENEMY_PASSED", "BOSS_APPEAR", "SWARM", "FAST_INCOMING",
			"TOUGH", "CHAIN_WEAK", "MARK_COOP", "CLUSTER", "BOMB_CLUSTER", "TOUGH_DOWN"]:
		check(not GameData.text_variants("speech", code).is_empty(), "말풍선 문구 존재: " + code)
	for p in GameData.principle_order():
		var w: Dictionary = GameData.principle_weights(p)
		check(absf(float(w["w_distance"]) + float(w["w_danger"]) + float(w["w_special"]) - 1.0) < 1e-6, "가중치 합 1: " + p)
	for r in GameData.config["recommended_team"]:
		check(GameData.heroes.has(r["type"]), "추천 팀 캐릭터 존재")


func t01_effects() -> void:
	var near_d := dist_at(Vector2(6, 6.5))  # 슬롯 4 (7,7) 바로 옆
	# 검객: 2명 동시 타격
	var s := make_state(["SWORD"], [3])
	var a := put_enemy(s, "NORMAL", near_d)
	var b := put_enemy(s, "NORMAL", near_d + 0.3)
	freeze(s)
	step_n(s, 2)
	check(a.hp < a.max_hp and b.hp < b.max_hp, "검객이 두 적을 동시에 때림")
	# 궁수: 짧은 공격 주기
	s = make_state(["ARCHER"], [3])
	a = put_enemy(s, "ARMORED", near_d)
	freeze(s)
	step_n(s, int(3.0 / GameData.dt()))
	check(s.heroes[0].attacks >= 4, "궁수 3초에 4번 이상 공격 (%d)" % s.heroes[0].attacks)
	# 저격수: 방어 50% 무시
	s = make_state(["SNIPER"], [3])
	a = put_enemy(s, "ARMORED", near_d)
	freeze(s)
	step_n(s, 1)
	var expect := 20.0 * (1.0 - 0.3 * 0.5)
	check(absf((a.max_hp - a.hp) - expect) < 0.01, "저격수 피해 %.2f (기대 %.2f)" % [a.max_hp - a.hp, expect])
	# 화염술사: 범위 + 화상
	s = make_state(["FIRE"], [3])
	a = put_enemy(s, "ARMORED", near_d)
	b = put_enemy(s, "ARMORED", near_d + 0.5)
	freeze(s)
	step_n(s, 1)
	check(a.is_burning() and b.is_burning(), "화염술사 범위 피해와 화상")
	var hp_after_hit := a.hp
	s.heroes[0].cooldown = 99.0
	step_n(s, int(1.0 / GameData.dt()))
	check(a.hp < hp_after_hit - 1.5, "화상이 시간에 따라 피해를 줌")
	# 빙결술사: 감속
	s = make_state(["ICE"], [3])
	a = put_enemy(s, "FAST", near_d)
	step_n(s, 1)
	check(a.is_slowed() and absf(a.effective_speed() - a.speed * 0.65) < 1e-6, "빙결술사 35% 감속")
	# 번개술사: 2명 전이, 피해 감소
	s = make_state(["LIGHTNING"], [3])
	a = put_enemy(s, "ARMORED", near_d)
	b = put_enemy(s, "ARMORED", near_d + 0.8)
	var c := put_enemy(s, "ARMORED", near_d + 1.6)
	freeze(s)
	step_n(s, 1)
	var hit := 0
	for e in [a, b, c]:
		if e.hp < e.max_hp:
			hit += 1
	check(hit == 3, "번개가 3명에게 (첫 대상 + 전이 2)")
	check(s.heroes[0].last_chain_count == 2, "전이 횟수 2")
	# 폭탄공학자: 투사체 후 범위 폭발
	s = make_state(["BOMB"], [3])
	a = put_enemy(s, "ARMORED", near_d)
	b = put_enemy(s, "ARMORED", near_d + 0.6)
	freeze(s)
	step_n(s, 1)
	check(s.projectiles.size() == 1 and a.hp == a.max_hp, "폭탄은 바로 맞지 않고 날아감")
	step_n(s, 30)
	check(a.hp < a.max_hp and b.hp < b.max_hp, "폭발 범위의 적 모두 피해")
	# 표식술사: 표식 → 다른 공격 피해 증가
	s = make_state(["MARK", "SNIPER"], [3, 5])
	a = put_enemy(s, "NORMAL", near_d)
	a.max_hp = 1000.0
	a.hp = 1000.0
	freeze(s)
	s.heroes[1].cooldown = 99.0
	step_n(s, 1)
	check(a.is_marked(), "표식 붙음")
	var before := a.hp
	GameEngine.apply_damage(s, a, 10.0, 0.0, 1)
	check(absf((before - a.hp) - 10.0 * (1.0 + float(GameData.hero("MARK")["mark_amp"]))) < 0.01, "표식 대상이 받는 피해 증가")
	# 중첩 한도: 같은 효과는 1개, 시간만 갱신
	s = make_state(["ICE"], [3])
	a = put_enemy(s, "ARMORED", near_d)
	freeze(s)
	step_n(s, int(3.0 / GameData.dt()))
	check(a.slow_amt <= float(GameData.hero("ICE")["slow"]) + 1e-6, "감속은 중첩되지 않음")


func t02_principle_changes_target() -> void:
	var s := make_state(["ARCHER"], [3])
	var near := put_enemy(s, "NORMAL", dist_at(Vector2(6, 5)))  # 캐릭터에 가깝고 진행률 낮음
	var far := put_enemy(s, "NORMAL", dist_at(Vector2(9.5, 8)))  # 조금 멀지만 기지에 더 가까움
	var h: Entities.Hero = s.heroes[0]
	var t_near := Targeting.select(s, h, "NEAREST")
	var t_danger := Targeting.select(s, h, "DANGER")
	check(t_near == near, "가까운 적 우선 → 가까운 적")
	check(t_danger == far, "위험한 적 우선 → 더 진행한 적")
	# 빙결술사 특기: 빠른 적
	s = make_state(["ICE"], [3])
	var normal := put_enemy(s, "NORMAL", dist_at(Vector2(6, 6.6)))
	var fast := put_enemy(s, "FAST", dist_at(Vector2(6, 4.8)))
	var ih: Entities.Hero = s.heroes[0]
	check(Targeting.select(s, ih, "NEAREST") == normal, "빙결술사 가까운 적 우선 → 일반")
	check(Targeting.select(s, ih, "SPECIAL") == fast, "빙결술사 특기 활용 → 빠른 적")
	# 실제 공격에도 반영
	ih.principle = "SPECIAL"
	var evs := step_n(s, 1)
	var target := -1
	for ev in evs:
		if ev["type"] == "ATTACK":
			target = ev["target"]
	check(target == fast.id, "원칙 변경이 실제 공격 대상에 반영")


func t03_range_and_retarget() -> void:
	var s := make_state(["ARCHER"], [0])  # (3,3)
	var out := put_enemy(s, "NORMAL", dist_at(Vector2(12, 6)))  # 멀리
	freeze(s)
	step_n(s, 90)
	check(out.hp == out.max_hp, "사거리 밖 적은 공격하지 않음")
	# 대상이 죽어도 다음 대상을 고른다
	s = make_state(["ARCHER"], [3])
	var a := put_enemy(s, "NORMAL", dist_at(Vector2(6, 6.5)))
	var b := put_enemy(s, "NORMAL", dist_at(Vector2(6, 5.5)))
	freeze(s)
	a.hp = 1.0
	step_n(s, 60)
	check(not a.alive and b.hp < b.max_hp, "대상 처치 후 다음 대상 공격")
	# 전체 게임: 모든 공격 대상은 공격 순간 사거리 안
	var bad := [0]
	var count := [0]
	var insp := func(sess: BattleSession) -> void:
		for ev in sess.state.events:
			if ev["type"] == "ATTACK":
				count[0] += 1
				var rng := float(GameData.hero(ev["hero_type"])["range"])
				var first: Vector2 = ev["points"][0]
				if first.distance_to(ev["from"]) > rng + 1e-4:
					bad[0] += 1
				if ev["hero_type"] == "SWORD":
					for p in ev["points"]:
						if p.distance_to(ev["from"]) > rng + 1e-4:
							bad[0] += 1
	full_game(3, ["SWORD", "BOMB", "LIGHTNING"], [3, 5, 7], "keep", insp)
	full_game(4, ["SNIPER", "MARK", "FIRE"], [0, 4, 8], "keep", insp)
	check(count[0] > 200, "공격이 충분히 일어남 (%d)" % count[0])
	check(bad[0] == 0, "사거리 밖 공격 0건 (%d건)" % bad[0])


func t04_speech_truth_and_cooldown() -> void:
	var log: Array = []
	var bad := [0]
	var insp := func(sess: BattleSession) -> void:
		if not sess.new_bubble.is_empty():
			var b: Dictionary = sess.new_bubble
			if not sess.observer.has_trigger(b["code"], b["hero"]):
				bad[0] += 1
			log.append({"t": sess.state.time, "hero": b["hero"], "code": b["code"]})
	for seed_value in [11, 12, 13]:
		log.clear()
		var types: Array = [["SWORD", "ICE", "SNIPER"], ["FIRE", "LIGHTNING", "MARK"], ["ARCHER", "BOMB", "ICE"]][seed_value - 11]
		full_game(seed_value, types, [3, 5, 6], "keep", insp)
		check(log.size() >= 3, "말풍선이 실제로 나옴 (%d개)" % log.size())
		for i in range(1, log.size()):
			var gap: float = log[i]["t"] - log[i - 1]["t"]
			check(gap >= float(GameData.cfg("speech", "global_cooldown", 7)) - 1e-6, "전역 쿨다운 %.1f초" % gap)
			check(gap >= float(GameData.cfg("speech", "display_seconds", 2.2)) - 1e-6, "동시에 1개 (앞 말풍선이 사라진 뒤)")
		var last_by_hero: Dictionary = {}
		for l in log:
			if last_by_hero.has(l["hero"]):
				check(l["t"] - last_by_hero[l["hero"]] >= float(GameData.cfg("speech", "hero_cooldown", 15)) - 1e-6, "캐릭터 쿨다운")
			last_by_hero[l["hero"]] = l["t"]
	check(bad[0] == 0, "말풍선은 트리거가 사실일 때만 (%d건 위반)" % bad[0])
	# 빠른 적이 없으면 '빠른 적' 말풍선이 나오지 않음
	var s := make_state(["ICE"], [3])
	put_enemy(s, "NORMAL", dist_at(Vector2(6, 6)))
	put_enemy(s, "NORMAL", dist_at(Vector2(6, 5)))
	var ob := CombatObserver.new()
	ob.observe(s, true)
	check(not ob.has_trigger("FAST_INCOMING", 0), "빠른 적 없으면 빠른 적 경고 없음")
	put_enemy(s, "FAST", dist_at(Vector2(6, 4)))
	put_enemy(s, "FAST", dist_at(Vector2(6, 3)))
	ob.observe(s, true)
	check(ob.has_trigger("FAST_INCOMING", 0), "빠른 적 2마리 접근 시 경고")


func t05_events_once() -> void:
	for seed_value in range(20, 32):
		var types: Array = GameData.hero_order.duplicate()
		var off := seed_value % 6
		var s := full_game(seed_value, [types[off], types[off + 1], types[off + 2]], [seed_value % 10, (seed_value + 3) % 10, (seed_value + 6) % 10])
		var nc := 0
		var nh := 0
		for d in s.suggestion_log + s.cancelled:
			if d["kind"] == "crisis":
				nc += 1
			elif d["kind"] == "first_hit":
				nh += 1
		check(nc <= 1 and nh <= 1, "위기·첫피격 제안 각각 최대 1회 (seed %d: %d, %d)" % [seed_value, nc, nh])
		check(s.suggestion_log.size() <= 2, "특별 제안 최대 2회")
		if s.first_hit_time < 0.0:
			for d in s.suggestion_log:
				check(d["kind"] != "first_hit", "피격이 없으면 첫피격 제안도 없음")


func t06_gap_and_cancel() -> void:
	var gap := float(GameData.cfg("suggestion", "min_gap_seconds", 18))
	var checked := 0
	for seed_value in range(40, 60):
		var s := full_game(seed_value, ["ARCHER", "FIRE", "MARK"], [0, 2, 4])  # 일부러 약한 배치
		var lg: Array = s.suggestion_log
		for i in range(1, lg.size()):
			checked += 1
			check(float(lg[i]["time"]) - float(lg[i - 1]["time"]) >= gap - 1e-6, "제안 간격 %.1f초 ≥ %.0f" % [float(lg[i]["time"]) - float(lg[i - 1]["time"]), gap])
	check(checked > 0, "두 번 제안된 판이 있어 간격을 확인함")
	# 게임이 끝나면 보관 중인 제안 취소
	var team := [{"type": "ARCHER", "slot": 0}, {"type": "ICE", "slot": 1}, {"type": "FIRE", "slot": 2}]
	var ss := BattleSession.new(team, 1)
	ss.start()
	ss.state.spawns_enabled = false
	ss.state.base_hp = 1
	ss.last_suggestion_end = ss.state.time  # 방금 제안이 끝난 상태 → 새 제안은 보관됨
	ss.crisis_fired = true
	var e := put_enemy(ss.state, "FAST", GameData.path.length - 0.05)
	for i in 5:
		ss.step()
	check(ss.is_over() and ss.state.outcome == "lose", "기지 HP 0 → 패배")
	check(ss.pending.is_empty() and not ss.cancelled.is_empty(), "끝난 게임의 보관 제안 취소")
	check(not ss.is_paused(), "끝난 뒤 제안 창이 열리지 않음")


func _find_change_session() -> BattleSession:
	for seed_value in range(100, 200):
		var types: Array = GameData.hero_order.duplicate()
		var off := seed_value % 6
		var team: Array = []
		for i in 3:
			team.append({"type": types[off + i], "slot": (seed_value + i * 3) % 10})
		var s := BattleSession.new(team, seed_value)
		s.start()
		var guard := 0
		while not s.is_over() and guard < 20000:
			guard += 1
			if s.is_paused():
				if s.active["has_change"]:
					return s
				s.resolve("keep")
				continue
			s.step()
	return null


func t07_choice_applies_to_one_hero() -> void:
	var s := _find_change_session()
	check(s != null, "변경 제안이 나오는 판을 찾음")
	if s == null:
		return
	var a: Dictionary = s.active
	var before: Array = []
	for h in s.state.heroes:
		before.append(h.principle)
	# 유지: 아무것도 바뀌지 않음 (복사본으로 확인)
	var keep_copy := s.state.clone()
	check(s.resolve("keep"), "유지 처리")
	for i in s.state.heroes.size():
		check(s.state.heroes[i].principle == before[i], "유지하면 모든 원칙 그대로")
	# 같은 상황에서 수락
	s.active = a
	check(s.resolve("accept"), "수락 처리")
	for i in s.state.heroes.size():
		if i == int(a["hero_id"]):
			check(s.state.heroes[i].principle == a["to"], "제안한 캐릭터만 변경")
		else:
			check(s.state.heroes[i].principle == before[i], "다른 캐릭터는 그대로")
	# 직접 고르기
	s.state.heroes[a["hero_id"]].principle = before[a["hero_id"]]
	s.active = a
	var other := "SPECIAL" if a["to"] != "SPECIAL" and before[a["hero_id"]] != "SPECIAL" else ("DANGER" if before[a["hero_id"]] != "DANGER" else "NEAREST")
	check(s.resolve("other", other), "직접 고르기 처리")
	check(s.state.heroes[a["hero_id"]].principle == other, "직접 고른 원칙 적용")
	check(not s.resolve("accept"), "열린 제안이 없으면 처리 안 함")
	check(s.suggestion_log[s.suggestion_log.size() - 1]["choice"] == "other", "결정 기록")


func t08_recommendation_consistency() -> void:
	var seen := 0
	for seed_value in range(60, 80):
		var types: Array = GameData.hero_order.duplicate()
		var off := seed_value % 6
		var team: Array = []
		for i in 3:
			team.append({"type": types[off + i], "slot": (seed_value + i * 4) % 10})
		var s := BattleSession.new(team, seed_value)
		s.start()
		var guard := 0
		while not s.is_over() and guard < 20000:
			guard += 1
			if s.is_paused():
				seen += 1
				var a: Dictionary = s.active
				for c in a["candidates"]:
					check(c["to"] != s.state.heroes[c["hero_id"]].principle, "후보에 현재 원칙 없음")
				if a["has_change"]:
					check(a["to"] != a["from"], "추천 원칙 ≠ 현재 원칙")
					var alt: Dictionary = a["alt"]
					var base: Dictionary = a["base"]
					check(alt["damage"] <= base["damage"], "추천안은 기지 피해를 늘리지 않음")
					var claims_damage := false
					for p in a["pros"]:
						if str(p).contains("기지 피해가 줄었어"):
							claims_damage = true
					check(claims_damage == (alt["damage"] < base["damage"]), "‘기지 피해 감소’는 실제로 줄었을 때만")
					var claims_kills := false
					for p in a["pros"]:
						if str(p).contains("처치 수가 늘었어"):
							claims_kills = true
					check(claims_kills == (alt["kills"] > base["kills"]), "‘처치 증가’는 실제로 늘었을 때만")
					check(not a["cons"].is_empty(), "단점을 항상 함께 제시")
					check(not str(a["message"]).contains("반드시"), "보장 표현 없음")
				else:
					check(a["to"] == "", "변경 없음이면 추천 원칙 없음")
				if a["kind"] == "first_hit":
					check(s.first_hit_time >= 0.0, "첫피격 제안은 실제 피격 후")
				if a["evidence_code"] == "SELF_FAST_PASSED":
					check(int(s.observer.hero_passed_fast.get(a["hero_id"], 0)) > 0, "인용한 관찰은 실제 기록")
				s.resolve("keep")
				continue
			s.step()
	check(seen > 10, "제안 상황 %d건 검사" % seen)


func t09_determinism_no_mutation() -> void:
	var team := [{"type": "SWORD", "slot": 3}, {"type": "ICE", "slot": 6}, {"type": "BOMB", "slot": 5}]
	var s := BattleSession.new(team, 5)
	s.start()
	for i in int(70.0 / GameData.dt()):
		if s.is_paused():
			s.resolve("keep")
		s.step()
	var sig_before := s.state.signature()
	var snap := s.replay_snapshot()
	var snap_sig := snap.signature() if snap != null else ""
	var r1 := Recommendation.analyze(s.state, s.observer, "test", {}, [], snap)
	var r2 := Recommendation.analyze(s.state, s.observer, "test", {}, [], snap)
	check(s.state.signature() == sig_before, "예측 계산이 실제 전투 상태를 바꾸지 않음")
	check(snap == null or snap.signature() == snap_sig, "예측 계산이 저장 상태를 바꾸지 않음")
	check(r1["base"]["signature"] == r2["base"]["signature"] and r1["base"]["J"] == r2["base"]["J"], "같은 상태 → 같은 결과")
	for i in r1["candidates"].size():
		check(r1["candidates"][i]["J"] == r2["candidates"][i]["J"], "후보 결과 재현")
	var g1 := full_game(9, ["FIRE", "ARCHER", "MARK"], [2, 5, 7], "accept").summary()
	var g2 := full_game(9, ["FIRE", "ARCHER", "MARK"], [2, 5, 7], "accept").summary()
	check(g1["time"] == g2["time"] and g1["kills"] == g2["kills"] and g1["hp"] == g2["hp"], "같은 팀·배치·선택 → 같은 전투 결과")


func t10_controller_flow() -> void:
	var c := GameController.new()
	root.add_child(c)
	check(c.phase == GameController.ATTRACT, "대기 화면에서 시작")
	c.command("start")
	check(c.phase == GameController.SELECT, "시작 → 선택")
	c.command("toggle_hero", {"type": "SNIPER"})
	c.command("toggle_hero", {"type": "SNIPER"})
	check(c.selected.is_empty(), "다시 누르면 선택 해제")
	for t in ["SWORD", "ARCHER", "ICE", "BOMB"]:
		c.command("toggle_hero", {"type": t})
	check(c.selected.size() == 3, "최대 3명")
	check(c.command("to_place")["ok"], "배치 화면으로")
	check(not c.command("battle_start")["ok"], "배치 전에는 시작 불가")
	c.command("place_slot", {"slot": 3})
	c.command("place_slot", {"slot": 5})
	c.command("place_slot", {"slot": 6})
	c.command("pick_member", {"index": 0})
	c.command("place_slot", {"slot": 5})
	check(c.team[0]["slot"] == 5 and c.team[1]["slot"] == 3, "이미 놓인 자리를 누르면 자리 맞바꾸기")
	c.command("set_principle", {"index": 2, "principle": "SPECIAL"})
	check(c.team[2]["principle"] == "SPECIAL", "시작 전 원칙 설정")
	check(c.command("battle_start")["ok"] and c.phase == GameController.BATTLE, "전투 시작")
	check(not c.command("set_principle", {"index": 0, "principle": "DANGER"})["ok"], "전투 중에는 제안 없이 원칙 변경 불가")
	var opened := 0
	var guard := 0
	var paused_ticks := 0
	while c.phase == GameController.BATTLE and guard < 40000:
		guard += 1
		if c.session.is_paused():
			paused_ticks += 1
			var t_before := c.session.state.time
			c._process(0.1)
			check(c.session.state.time == t_before, "제안 중 전투 정지")
			if paused_ticks == 1:
				opened += 1
				# 첫 제안은 시간 초과로 → 유지
				for i in 400:
					if not c.session.is_paused():
						break
					c._process(0.1)
				check(not c.session.is_paused(), "30초 지나면 자동 유지 후 재개")
				check(c.session.suggestion_log[0]["choice"] == "timeout", "시간 초과 기록")
			else:
				opened += 1
				c.command("suggest_accept" if c.session.active["has_change"] else "suggest_keep")
			continue
		c._process(1.0 / 60.0)
	check(c.phase == GameController.RESULT, "결과 화면까지 진행")
	check(opened >= 1, "특별 제안을 1번 이상 거침 (%d)" % opened)
	check(not c.result.is_empty() and c.result.has("score"), "결과 요약")
	for i in 400:
		c._process(0.1)
	check(c.phase == GameController.ATTRACT and c.team.is_empty() and c.session == null, "결과 후 자동 초기화, 이전 선택 지움")
	c.command("start")
	for i in 1000:
		c._process(0.1)
	check(c.phase == GameController.ATTRACT, "선택 화면에서 방치되면 대기 화면으로")
	c.command("start")
	c.command("recommended")
	check(c.phase == GameController.PLACE and c.team.size() == 3 and c._first_unplaced() < 0, "추천 팀은 자리까지 자동 배치")
	c.queue_free()


func t11_command_once() -> void:
	var c := GameController.new()
	c.command("start", {}, 1)
	var a1 := c.command("toggle_hero", {"type": "FIRE"}, 2)
	var a2 := c.command("toggle_hero", {"type": "FIRE"}, 2)  # 같은 명령이 두 번 전달됨
	check(a1["ok"] and not a2["ok"] and a2["duplicate"], "중복 명령은 ACK만, 반영 안 함")
	check(c.selected == ["FIRE"], "명령 1번 → 정확히 1번 반영")
	check(a2["version"] == a1["version"], "중복 명령은 상태 버전을 올리지 않음")
	var a3 := c.command("toggle_hero", {"type": "ICE"}, 3)
	check(a3["ok"] and a3["version"] == a1["version"] + 1, "새 명령은 반영되고 버전 증가")
	c.free()


func t12_hero_art_and_anim() -> void:
	for t in GameData.hero_order:
		check(HeroSprite.has_art(t), "그림 있음: " + t)
	var rig := HeroSprite.rig_for("SWORD")
	check(rig != null and rig.parts.size() == 12, "검객 파츠 리그 12조각")
	if rig != null:
		for p in rig.parts:
			if p["parent"] != null:
				check(rig.by_name.has(p["parent"]), "부모 파츠 존재: " + p["name"])
	var a := HeroSprite.Anim.new("ICE", 1)
	a.trigger(10.0, true, -1.0)
	check(a.special and a.facing == -1.0, "특기 모션 + 표적 쪽으로 돌아봄")
	a.trigger(11.0, true, 1.0)
	check(not a.special and a.facing == 1.0, "특기 모션은 쿨다운 동안 일반 공격으로")
	check(a.progress(11.1) >= 0.0 and a.progress(13.0) < 0.0, "공격 모션은 짧게 끝남")
	# 연출 표시는 전투 결과에 영향 없음: special 키가 있어도 같은 시드면 같은 결과 (t09에서 재현성 확인)
	var s := full_game(21, ["SWORD", "SNIPER", "ICE"], [3, 5, 6])
	check(s.state.outcome != "", "특기 표시가 있어도 게임 정상 종료")


func t14_ice_rig() -> void:
	check(AssetManifest.portrait_texture("ICE") != null, "빙결술사 전신 원화 로드")
	check(AssetManifest.texture("effects", "ice_cast") != null, "얼음 결정 효과 로드")
	var rig := HeroSprite.rig_for("ICE")
	check(rig != null and rig.parts.size() == 12, "빙결술사 파츠 12개 로드")
	if rig == null:
		return
	check(rig.bounds.size.y > 1150.0 and rig.bounds.size.y < 1230.0, "희미한 배경이 아닌 캐릭터 영역으로 크기 결정")
	var angles := {"torso":0.1, "upper_arm_far":0.12, "forearm_far":-0.3, "head_face":0.08}
	var transforms := {}
	var staff := HeroSprite._part_xform(rig, rig.by_name["staff"], angles, transforms)
	check(transforms.has("torso") and transforms.has("forearm_far"), "지팡이를 먼저 그려도 상위 관절 계산")
	if transforms.has("forearm_far"):
		var grip: Vector2 = transforms["forearm_far"] * (rig.by_name["staff"]["pivot"] - rig.by_name["forearm_far"]["pivot"])
		check(staff.origin.is_equal_approx(grip), "팔이 회전해도 지팡이는 손의 위치에 연결")
	var reversed := {}
	var parts: Array = rig.parts.duplicate()
	parts.reverse()
	for part in parts:
		HeroSprite._part_xform(rig, part, angles, reversed)
	check(staff.is_equal_approx(reversed["staff"]), "그리는 순서가 달라도 같은 관절 위치")
	var a := HeroSprite.Anim.new("ICE")
	a.trigger(10.0, true, 1.0)
	for phase in [0.0, 0.2, 0.45, 0.7, 0.99]:
		check(is_equal_approx(HeroSprite.pose_for(a,10.0 + phase * a.atk_dur).spin,1.0), "빙결 특기 중 방향 유지")
	var feet := Vector2(300,300)
	var right := HeroSprite.attachment_position(a,feet,150.0,10.0,"cast")
	a.facing = -1.0
	var left := HeroSprite.attachment_position(a,feet,150.0,10.0,"cast")
	check(absf(right.x + left.x - feet.x * 2.0) < 0.01 and absf(right.y-left.y) < 0.01, "얼음 발사 위치도 캐릭터 방향에 맞게 반전")


func t13_confirm_flow() -> void:
	var c := GameController.new()
	c.command("start")
	check(c.command("confirm_hero", {"type": "SNIPER"})["ok"], "확정 → 팀에 추가")
	check(not c.command("confirm_hero", {"type": "SNIPER"})["ok"], "같은 캐릭터 두 번 확정 안 됨")
	c.command("confirm_hero", {"type": "FIRE"})
	c.command("confirm_hero", {"type": "BOMB"})
	check(not c.command("confirm_hero", {"type": "ICE"})["ok"] and c.selected.size() == 3, "최대 3명")
	check(c.command("unconfirm_hero", {"type": "FIRE"})["ok"] and c.selected == ["SNIPER", "BOMB"], "팀에서 빼기")
	check(not c.command("to_place")["ok"], "3명 전에는 게임 화면으로 못 감")
	c.command("confirm_hero", {"type": "ICE"})
	check(c.command("to_place")["ok"] and c.phase == GameController.PLACE, "3명 확정 후 게임 화면(배치)으로")
	for t in GameData.hero_order:
		var d: Dictionary = GameData.hero(t)
		check(str(d.get("person", "")) != "" and str(d.get("profile", "")) != "" and str(d.get("bio", "")) != "", "인물 정보: " + t)
		check(HeroSprite.has_art(t), "그림 또는 도형 인물: " + t)
	c.free()


func t15_roster_art() -> void:
	var counts := {"male":0,"female":0}
	for type in ["SWORD","ARCHER","SNIPER","FIRE","ICE","LIGHTNING","BOMB","MARK"]:
		var h := GameData.hero(type)
		counts[h.gender] += 1
		check(int(h.age) >= 20 and int(h.age) <= 25, type+" 청년 캐릭터 설정")
		check(AssetManifest.portrait_texture(type) != null, type+" 전신 원화 존재")
		check(AssetManifest.hero_texture(type) != null, type+" SD 원화 존재")
		var rig := HeroSprite.rig_for(type)
		check(rig != null and rig.parts.size() == 12, type+" 독립 파츠 12개")
		if rig == null:
			continue
		check(rig.bounds.size.y > 1000 and rig.bounds.size.y <= 1280, type+" 캔버스 배치 영역")
		for part in rig.parts:
			check(part.parent == null or rig.by_name.has(part.parent), type+" 관절 부모 연결 "+part.name)
		var a := HeroSprite.Anim.new(type)
		a.trigger(10.0,true,1.0)
		var now := 10.0 + a.atk_dur * 0.45
		check(is_equal_approx(HeroSprite.pose_for(a,now).spin,1.0), type+" 특기 시전 중 방향 유지")
		var feet := Vector2(600,500)
		var right := HeroSprite.attachment_position(a,feet,150,10.0,"cast")
		a.facing = -1.0
		var left := HeroSprite.attachment_position(a,feet,150,10.0,"cast")
		check(absf(left.x+right.x-1200)<0.01 and absf(left.y-right.y)<0.01, type+" 발사점 좌우 반전")
	check(counts.male == 4 and counts.female == 4, "전체 성비 남성 4명 / 여성 4명")


func t16_world_art() -> void:
	for id in ["background","spawn","base","slot"]:
		check(AssetManifest.texture("map",id)!=null,"맵 그림 "+id)
	check(GameData.config.map.background_includes_path,"생성 배경의 길 중복 표시 방지")
	var image:=AssetManifest.texture("map","background").get_image()
	if image.is_compressed(): image.decompress()
	check(absf(float(image.get_width())/image.get_height()-16.0/9.0)<0.01,"맵 16:9 비율")
	for i in range(1,80):
		var p:=GameData.path.pos_at(GameData.path.length*i/80.0)
		if p.x<0 or p.x>=20: continue
		var px:=Vector2i(p/Vector2(20,11.25)*Vector2(image.get_size()))
		check(image.get_pixelv(px).v<0.62,"경로 중심이 생성된 차로 안에 있음 %d"%i)
	for type in ["NORMAL","FAST","ARMORED","BOSS"]:
		check(AssetManifest.enemy_texture(type)!=null,type+" 기준 그림")
		var frames:=EnemySprite.frame_rects(type)
		check(frames.size()==4,type+" 방향/보행 4프레임")
		for r in frames:
			check(r.size.x>100 and r.size.y>100,type+" 온전한 프레임 영역")
		check(EnemySprite.frame_for(Vector2.RIGHT,0,1)==0 and EnemySprite.frame_for(Vector2.RIGHT,0.2,1)==1,type+" 보행 프레임 전환")
		check(EnemySprite.frame_for(Vector2.DOWN,0,1)==2 and EnemySprite.frame_for(Vector2.UP,0,1)==3,type+" 세로 이동 방향 전환")
	check(EnemySprite.motion_direction(1).is_equal_approx(Vector2.RIGHT),"첫 구간 오른쪽")
	check(EnemySprite.motion_direction(8).is_equal_approx(Vector2.DOWN),"두 번째 구간 아래쪽")
	check(EnemySprite.motion_direction(20).is_equal_approx(Vector2.UP),"중간 오르막 위쪽")
