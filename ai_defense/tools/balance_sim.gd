extends SceneTree
## 밸런스 시뮬레이션: 여러 팀·배치 조합으로 전투를 화면 없이 돌려 통계를 낸다.
##   godot --headless --path . --script res://tools/balance_sim.gd -- [games=300] [policy=keep|accept]
## policy=keep  : AI 제안을 모두 '유지' (기본 원칙 그대로)
## policy=accept: AI 제안을 모두 수락

var _policy := "keep"
var _games := 300


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("games="):
			_games = int(a.substr(6))
		elif a.begins_with("policy="):
			_policy = a.substr(7)
	GameData.ensure_loaded()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var total := {"win": 0, "crisis": 0, "hit": 0, "hp": 0.0, "time": 0.0, "kills": 0, "sugg": 0, "sugg_change": 0, "crisis_time": 0.0}
	var per_hero: Dictionary = {}
	for t in GameData.hero_order:
		per_hero[t] = {"games": 0, "win": 0, "hp": 0.0, "dmg": 0.0}
	var per_wave_end := [0, 0, 0]
	var t0 := Time.get_ticks_msec()
	for g in _games:
		var types: Array = GameData.hero_order.duplicate()
		_shuffle(types, rng)
		types = types.slice(0, 3)
		var slots: Array = range(GameData.slots.size())
		_shuffle(slots, rng)
		var team: Array = []
		for i in 3:
			team.append({"type": types[i], "slot": slots[i], "principle": "NEAREST"})
		var r := BattleRunner.run_headless(team, _policy, g + 1)
		if r["outcome"] == "win":
			total["win"] += 1
		if r["crisis_time"] >= 0.0:
			total["crisis"] += 1
			total["crisis_time"] += r["crisis_time"]
		if r["first_hit_time"] >= 0.0:
			total["hit"] += 1
		total["hp"] += r["hp"]
		total["time"] += r["time"]
		total["kills"] += r["kills"]
		total["sugg"] += r["suggestions"]
		total["sugg_change"] += r["suggestions_with_change"]
		per_wave_end[clampi(r["wave"], 0, 2)] += 1
		for i in 3:
			var ph: Dictionary = per_hero[types[i]]
			ph["games"] += 1
			ph["win"] += 1 if r["outcome"] == "win" else 0
			ph["hp"] += r["hp"]
			ph["dmg"] += r["hero_damage"][i]
	var n := float(_games)
	print("=== 밸런스 시뮬레이션 (%d판, 정책=%s, %.1f초) ===" % [_games, _policy, (Time.get_ticks_msec() - t0) / 1000.0])
	print("방어 성공률 %.0f%%  평균 잔여HP %.1f  평균 생존 %.0f초  평균 처치 %.1f" % [100.0 * total["win"] / n, total["hp"] / n, total["time"] / n, total["kills"] / n])
	print("위기 발생 %.0f%% (평균 %.0f초)  본진 피격 %.0f%%  제안 평균 %.2f회 (변경 제안 %.2f회)" % [100.0 * total["crisis"] / n,
		total["crisis_time"] / maxf(1.0, total["crisis"]), 100.0 * total["hit"] / n, total["sugg"] / n, total["sugg_change"] / n])
	print("종료 웨이브 분포: W1 %d / W2 %d / W3 %d" % per_wave_end)
	print("캐릭터별 (포함된 판의 성공률 / 평균잔여HP / 판당 피해량)")
	for t in GameData.hero_order:
		var ph: Dictionary = per_hero[t]
		var gn := maxf(1.0, ph["games"])
		print("  %-10s %3d판  성공 %3.0f%%  HP %.1f  피해 %.0f" % [t, ph["games"], 100.0 * ph["win"] / gn, ph["hp"] / gn, ph["dmg"] / gn])
	quit(0)


func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp
