extends SceneTree
## 3D 서바이벌 화면 없는 시뮬레이션 (밸런스·안정성 점검)
##   godot --headless --path . --script res://tools/sv_sim.gd -- games=60 bot=chase|idle
## bot=chase : 학생 대신 '기지에 가장 가까운 적 쪽으로 이동'을 2초마다 지시
## bot=idle  : 대표 캐릭터를 전혀 움직이지 않음 (조작 안 하면 어떻게 되는지)

var games := 60
var bot := "chase"


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("games="):
			games = int(a.substr(6))
		elif a.begins_with("bot="):
			bot = a.substr(4)
	SvData.ensure_loaded()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var wins := 0
	var hp := 0.0
	var kills := 0
	var downs := 0
	var max_alive := 0
	var per_type: Dictionary = {}
	var t0 := Time.get_ticks_msec()
	var tick_ms := 0.0
	var ticks := 0
	for g in games:
		var types: Array = GameData.hero_order.duplicate()
		for i in range(types.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = types[i]
			types[i] = types[j]
			types[j] = tmp
		var team: Array = types.slice(0, 3)
		var s := SvSession.new(team)
		var tactics: Array = SvData.tactic_order()
		s.set_tactic(1, tactics[g % 3])
		s.set_tactic(2, tactics[(g + 1) % 3])
		var next_cmd := 0.0
		while not s.is_over():
			if bot == "chase" and s.state.time >= next_cmd:
				next_cmd = s.state.time + 2.0
				var best: SvState.SvEnemy = null
				var bd := INF
				for e in s.state.enemies:
					if e.alive and e.pos.distance_to(SvData.base_center()) < bd:
						bd = e.pos.distance_to(SvData.base_center())
						best = e
				if best != null:
					s.move_player(best.pos.lerp(SvData.base_center(), 0.3))
			var u := Time.get_ticks_usec()
			s.step()
			tick_ms += (Time.get_ticks_usec() - u) / 1000.0
			ticks += 1
			max_alive = maxi(max_alive, s.state.enemies.size())
		var r := s.summary()
		if r["outcome"] == "win":
			wins += 1
		hp += r["base_hp"]
		kills += r["kills"]
		for h in r["heroes"]:
			downs += h["downs"]
			var pt: Dictionary = per_type.get(h["type"], {"n": 0, "dmg": 0.0, "kills": 0, "win": 0})
			pt["n"] += 1
			pt["dmg"] += h["damage"]
			pt["kills"] += h["kills"]
			pt["win"] += 1 if r["outcome"] == "win" else 0
			per_type[h["type"]] = pt
	var n := float(games)
	print("=== 3D 서바이벌 시뮬레이션 %d판 (bot=%s, %.1f초) ===" % [games, bot, (Time.get_ticks_msec() - t0) / 1000.0])
	print("방어 성공 %.0f%%  기지 잔여 %.0f/%.0f  처치 %.1f  쓰러짐(3명 합) %.1f  최대 동시 적 %d  틱 평균 %.3fms" % [
		100.0 * wins / n, hp / n, float(SvData.cfg["base_hp"]), kills / n, downs / n, max_alive, tick_ms / maxf(1, ticks)])
	for t in GameData.hero_order:
		if per_type.has(t):
			var pt: Dictionary = per_type[t]
			print("  %-10s %3d판 성공 %3.0f%%  피해 %5.0f  처치 %4.1f" % [t, pt["n"], 100.0 * pt["win"] / pt["n"], pt["dmg"] / pt["n"], float(pt["kills"]) / pt["n"]])
	quit(0)
