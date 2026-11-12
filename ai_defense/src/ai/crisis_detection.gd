class_name CrisisDetection
extends RefCounted
## 방어선 위기 판정 (게임당 최대 1회 사용은 BattleSession이 보장).
##  - 적 하나가 진행률 75% 이상이고 본진 도착 예상 8초 이내, 또는
##  - 진행률 65% 이상인 적이 3마리 이상


static func check(state: GameState) -> Dictionary:
	var c: Dictionary = GameData.config.get("crisis", {})
	var sp := float(c.get("single_progress", 0.75))
	var se := float(c.get("single_eta_seconds", 8.0))
	var gp := float(c.get("group_progress", 0.65))
	var gc := int(c.get("group_count", 3))
	var single: Array = []
	var group: Array = []
	for e in state.enemies:
		if not e.alive:
			continue
		var pr := state.progress(e)
		if pr >= sp and state.eta(e) <= se:
			single.append(e)
		if pr >= gp:
			group.append(e)
	var reason := ""
	var list: Array = []
	if group.size() >= gc:
		reason = "group"
		list = group
	elif not single.is_empty():
		reason = "single"
		list = single
	if reason == "":
		return {}
	var types: Dictionary = {}
	var ids: Array = []
	for e in list:
		types[e.type] = int(types.get(e.type, 0)) + 1
		ids.append(e.id)
	return {"reason": reason, "enemies": ids, "types": types, "count": list.size(), "time": state.time}
