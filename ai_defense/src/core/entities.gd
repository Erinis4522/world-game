class_name Entities
extends RefCounted
## 전투 개체. 모두 값 타입 필드만 갖고 clone()으로 깊은 복사가 된다.
## (가상 전투 비교에서 실제 상태를 건드리지 않기 위해 필요)


static func copy_fields(src: Object, dst: Object) -> void:
	for p in src.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var v: Variant = src.get(p.name)
			if v is Dictionary or v is Array:
				v = v.duplicate(true)
			dst.set(p.name, v)


class Enemy:
	extends RefCounted
	var id := 0
	var type := "NORMAL"
	var hp := 1.0
	var max_hp := 1.0
	var base_speed := 1.0  # 데이터상의 속도 (판단용, 단위 없음)
	var speed := 1.0  # 실제 이동 속도 (타일/초)
	var armor := 0.0
	var base_damage := 1
	var radius := 0.3
	var dist := 0.0
	var pos := Vector2.ZERO
	var prev_pos := Vector2.ZERO
	var alive := true
	var leaked := false
	var spawn_time := 0.0
	var first_hit_time := -1.0
	var last_hit_time := -1.0
	var last_hit_by := -1
	var slow_t := 0.0
	var slow_amt := 0.0
	var burn_t := 0.0
	var burn_dps := 0.0
	var burn_src := -1
	var mark_t := 0.0
	var mark_amt := 0.0
	var mark_src := -1

	func clone() -> Enemy:
		var c := Enemy.new()
		Entities.copy_fields(self, c)
		return c

	func effective_speed() -> float:
		return speed * (1.0 - (slow_amt if slow_t > 0.0 else 0.0))

	func effective_base_speed() -> float:
		return base_speed * (1.0 - (slow_amt if slow_t > 0.0 else 0.0))

	func is_slowed() -> bool:
		return slow_t > 0.0

	func is_burning() -> bool:
		return burn_t > 0.0

	func is_marked() -> bool:
		return mark_t > 0.0


class Hero:
	extends RefCounted
	var id := 0  # 팀 안 순서 (0~2) = state.heroes 배열 인덱스
	var type := "SWORD"
	var slot := 0
	var pos := Vector2.ZERO
	var principle := "NEAREST"
	var cooldown := 0.0
	var last_target_id := -1
	var last_attack_time := -100.0
	var last_chain_count := -1
	var in_range: Dictionary = {}  # enemy id -> true (지난 틱 사거리 안)
	var attacks := 0
	var kills := 0
	var damage_dealt := 0.0

	func clone() -> Hero:
		var c := Hero.new()
		Entities.copy_fields(self, c)
		return c


class Projectile:
	extends RefCounted
	var hero_id := -1
	var kind := "BOMB"
	var pos := Vector2.ZERO
	var prev_pos := Vector2.ZERO
	var target := Vector2.ZERO
	var speed := 7.0
	var damage := 0.0
	var radius := 1.0
	var alive := true

	func clone() -> Projectile:
		var c := Projectile.new()
		Entities.copy_fields(self, c)
		return c
