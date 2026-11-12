extends SceneTree
## 3D 서바이벌 화면 없는 시뮬레이션 (밸런스·안정성 점검)
##   godot --headless --path . --script res://tools/sv_sim.gd -- games=30 bot=play|move|idle
## play : 조이스틱으로 위험한 적 쪽 이동 + 에너지가 있으면 벽(직선)·필살기(동그라미) 그림 제출 후 승인
## move : 이동만, idle : 아무것도 안 함

var games := 30
var bot := "play"


static func stroke(kind: String) -> PackedVector2Array:
	var p := PackedVector2Array()
	match kind:
		"LINE":
			for i in 20:
				p.append(Vector2(i * 15.0, 0))
		"CIRCLE":
			for i in 41:
				p.append(Vector2(cos(TAU * i / 40.0), sin(TAU * i / 40.0)) * 120.0)
		"TRIANGLE":
			var v := [Vector2(0, -120), Vector2(110, 80), Vector2(-110, 80), Vector2(0, -118)]
			for k in 3:
				for i in 15:
					p.append(v[k].lerp(v[k + 1], i / 15.0))
			p.append(v[3])
		"ZIGZAG":
			var z := [Vector2(0, 0), Vector2(60, 80), Vector2(120, 0), Vector2(180, 80), Vector2(240, 0)]
			for k in 4:
				for i in 12:
					p.append(z[k].lerp(z[k + 1], i / 12.0))
			p.append(z[4])
	return p


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("games="):
			games = int(a.substr(6))
		elif a.begins_with("bot="):
			bot = a.substr(4)
	SvData.ensure_loaded()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var wins := 0
	var hp := 0.0
	var kills := 0
	var walls := 0
	var ults := 0
	var downs := 0
	var max_alive := 0
	var tick_ms := 0.0
	var ticks := 0
	var plan_ms := 0.0
	var plans := 0
	var t0 := Time.get_ticks_msec()
	for g in games:
		var types: Array = GameData.hero_order.duplicate()
		for i in range(types.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = types[i]
			types[i] = types[j]
			types[j] = tmp
		var s := SvSession.new(types.slice(0, 3))
		var next_think := 0.0
		var next_sketch := 8.0
		while not s.is_over():
			var st := s.state
			if bot != "idle" and st.time >= next_think:
				next_think = st.time + 0.5
				var best: SvState.SvEnemy = null
				var bd := INF
				for e in st.enemies:
					var fd := st.grid.flow_distance(e.pos)
					if e.alive and fd < bd and e.pos.distance_to(st.player().pos) < 22:
						bd = fd
						best = e
				var goal := SvData.base_center() + Vector2(0, -5)
				if best != null:
					goal = best.pos.lerp(SvData.base_center(), 0.25)
				var v := goal - st.player().pos
				s.joystick(v.normalized() if v.length() > 1.0 else Vector2.ZERO)
			if bot == "play" and st.time >= next_sketch:
				next_sketch = st.time + 6.0
				var kind := "LINE" if st.walls.size() < 3 and (g + int(st.time)) % 2 == 0 else "CIRCLE"
				var u := Time.get_ticks_usec()
				var pr := s.submit_sketch(stroke(kind))
				plan_ms += (Time.get_ticks_usec() - u) / 1000.0
				plans += 1
				if pr.get("ok", false):
					var res := s.accept_proposal()
					if not res.is_empty():
						if kind == "LINE":
							walls += 1
						else:
							ults += 1
				else:
					s.cancel_proposal()
			var u2 := Time.get_ticks_usec()
			s.step()
			tick_ms += (Time.get_ticks_usec() - u2) / 1000.0
			ticks += 1
			max_alive = maxi(max_alive, st.enemies.size())
		var r := s.summary()
		if r["outcome"] == "win":
			wins += 1
		hp += r["base_hp"]
		kills += r["kills"]
		for h in r["heroes"]:
			downs += h["downs"]
	var n := float(games)
	print("=== 3D 서바이벌 v2 시뮬레이션 %d판 (bot=%s, %.1f초) ===" % [games, bot, (Time.get_ticks_msec() - t0) / 1000.0])
	print("성공 %.0f%%  마을 잔여 %.0f  처치 %.1f  벽 %.1f개  필살기 %.1f회  쓰러짐 %.1f  최대 동시 적 %d" % [
		100.0 * wins / n, hp / n, kills / n, walls / n, ults / n, downs / n, max_alive])
	print("전투 1틱 평균 %.3fms · 그림 해석+배치 계산 평균 %.1fms" % [tick_ms / maxf(1, ticks), plan_ms / maxf(1, plans)])
	quit(0)
