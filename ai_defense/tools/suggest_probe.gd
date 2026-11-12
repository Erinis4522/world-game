extends SceneTree
## 제안 시점의 가상 전투 후보 점수를 출력해 임계값을 점검한다.
##   godot --headless --path . --script res://tools/suggest_probe.gd -- [games=20]


func _init() -> void:
	var games := 20
	for a in OS.get_cmdline_user_args():
		if a.begins_with("games="):
			games = int(a.substr(6))
	GameData.ensure_loaded()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for g in games:
		var types: Array = GameData.hero_order.duplicate()
		var slots: Array = range(GameData.slots.size())
		for i in range(types.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t = types[i]; types[i] = types[j]; types[j] = t
		for i in range(slots.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t = slots[i]; slots[i] = slots[j]; slots[j] = t
		var team: Array = []
		for i in 3:
			team.append({"type": types[i], "slot": slots[i]})
		var s := BattleSession.new(team, g)
		s.start()
		while not s.is_over():
			if s.is_paused():
				var a: Dictionary = s.active
				var b: Dictionary = a["base"]
				var line := "G%d %-9s t=%.0f base[d=%d k=%d th=%.1f] " % [g, a["kind"], a["time"], b["damage"], b["kills"], b["threat"]]
				for c in a["candidates"]:
					line += "%s>%s:%.1f(d%d) " % [s.state.heroes[c["hero_id"]].type.substr(0, 3), c["to"].substr(0, 3), c["improvement"], c["damage"]]
				print(line, " => ", ("%s→%s" % [a["hero_type"], a["to"]]) if a["has_change"] else "KEEP")
				if g < 3:
					print("   ", a["message"].replace("\n", " / "))
					print("   장점: ", a["pros"], "  단점: ", a["cons"])
					print("   ", a["estimate"])
				s.resolve("keep")
				continue
			s.step()
	quit(0)
