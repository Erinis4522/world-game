class_name BattleRunner
extends RefCounted
## 화면 없이 한 판을 끝까지 돌린다 (밸런스 도구·테스트용).
## policy: keep = 제안을 모두 유지, accept = 변경 제안은 수락


static func run_headless(team: Array, policy: String = "keep", seed_value: int = 1, max_seconds: float = 400.0) -> Dictionary:
	var s := BattleSession.new(team, seed_value)
	s.start()
	var n_sugg := 0
	var n_change := 0
	var max_ticks := int(max_seconds / GameData.dt())
	for i in max_ticks:
		if s.is_over():
			break
		if s.is_paused():
			n_sugg += 1
			if s.active["has_change"]:
				n_change += 1
			if policy == "accept" and s.active["has_change"]:
				s.resolve("accept")
			else:
				s.resolve("keep")
			continue
		s.step()
	var r := s.summary()
	r["crisis_time"] = s.crisis_time
	r["first_hit_time"] = s.first_hit_time
	r["suggestions"] = n_sugg
	r["suggestions_with_change"] = n_change
	var dmg: Array = []
	for h in s.state.heroes:
		dmg.append(h.damage_dealt)
	r["hero_damage"] = dmg
	return r
