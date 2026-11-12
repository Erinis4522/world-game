class_name SpeechScheduler
extends RefCounted
## 말풍선 일정 관리. 관찰기(CombatObserver)의 '지금 사실인' 후보 중에서만 고른다.
## 규칙: 동시에 1개, 캐릭터별 쿨다운(15초), 전역 쿨다운(7초), 표시 2.2초,
##       우선순위 본진 위기(5) > 돌파(4) > 적 유형 경고(3) > 협력(2) > 긍정(1)
## 전투는 멈추지 않는다.

var current: Dictionary = {}  # {hero, code, text, start, until}
var shown_log: Array = []  # 표시된 말풍선 기록
var _hero_last: Dictionary = {}
var _global_last := -1000.0
var _variant: Dictionary = {}


func update(state: GameState, observer: CombatObserver) -> Dictionary:
	## 새로 띄운 말풍선이 있으면 돌려준다.
	var now := state.time
	if not current.is_empty() and now >= float(current["until"]):
		current = {}
	if not current.is_empty():
		return {}
	if now - _global_last < float(GameData.cfg("speech", "global_cooldown", 7.0)):
		return {}
	var hero_cd := float(GameData.cfg("speech", "hero_cooldown", 15.0))
	var best: Dictionary = {}
	for t in observer.triggers:
		var hid: int = t["hero"]
		if now - float(_hero_last.get(hid, -1000.0)) < hero_cd:
			continue
		if GameData.text_variants("speech", t["code"]).is_empty():
			continue
		if best.is_empty() or int(t["prio"]) > int(best["prio"]):
			best = t
	if best.is_empty():
		return {}
	var code: String = best["code"]
	var variants := GameData.text_variants("speech", code)
	var vi := int(_variant.get(code, 0))
	_variant[code] = vi + 1
	var text := _format(str(variants[vi % variants.size()]), best["params"])
	current = {"hero": best["hero"], "code": code, "text": text, "prio": best["prio"],
		"start": now, "until": now + float(GameData.cfg("speech", "display_seconds", 2.2))}
	_hero_last[best["hero"]] = now
	_global_last = now
	shown_log.append(current.duplicate())
	return current


func clear() -> void:
	current = {}


static func _format(tpl: String, params: Dictionary) -> String:
	var s := tpl
	for k in params.keys():
		s = s.replace("{" + str(k) + "}", str(params[k]))
	return s
