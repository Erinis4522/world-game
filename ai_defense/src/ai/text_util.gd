class_name TextUtil
extends RefCounted
## 한국어 조사 처리와 템플릿 채우기


static func has_batchim(word: String) -> bool:
	if word.is_empty():
		return false
	var c := word.unicode_at(word.length() - 1)
	if c < 0xAC00 or c > 0xD7A3:
		return false
	return (c - 0xAC00) % 28 != 0


static func is_rieul(word: String) -> bool:
	var c := word.unicode_at(word.length() - 1)
	return c >= 0xAC00 and c <= 0xD7A3 and (c - 0xAC00) % 28 == 8


static func euro(word: String) -> String:
	## '으로/로'
	return word + ("으로" if has_batchim(word) and not is_rieul(word) else "로")


static func iga(word: String) -> String:
	return word + ("이" if has_batchim(word) else "가")


static func fill(tpl: String, params: Dictionary) -> String:
	var s := tpl
	for k in params.keys():
		s = s.replace("{" + str(k) + "}", str(params[k]))
	return s


static func euro_suffix(word: String) -> String:
	return "으로" if has_batchim(word) and not is_rieul(word) else "로"
