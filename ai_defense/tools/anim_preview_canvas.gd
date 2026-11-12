extends Control
## anim_preview.gd 에서 쓰는 그림판: 캐릭터 8종 × 동작 프레임 표

const COLS := [
	["대기", "idle", 0.0], ["대기+", "idle", 1.2],
	["공격 준비", "atk", 0.18], ["공격 타격", "atk", 0.42], ["공격 복귀", "atk", 0.75],
	["특기 웅크림", "sp", 0.12], ["특기 공중", "sp", 0.4], ["특기 공중2", "sp", 0.6], ["특기 착지", "sp", 0.88],
]
var facing := 1.0


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#7fb069"))
	var font := get_theme_default_font()
	var cw := 150.0
	var rh := 150.0
	for ci in COLS.size():
		draw_string(font, Vector2(130 + ci * cw, 26), COLS[ci][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.BLACK)
	for ri in GameData.hero_order.size():
		var type: String = GameData.hero_order[ri]
		draw_string(font, Vector2(10, 40 + ri * rh + 90), GameData.hero(type)["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.BLACK)
		for ci in COLS.size():
			var a := HeroSprite.Anim.new(type, 0)
			a.phase = 0.0
			a.facing = facing
			var now := 10.0
			var kind: String = COLS[ci][1]
			var v: float = COLS[ci][2]
			if kind == "idle":
				now += v
			else:
				a.special = kind == "sp"
				a.atk_dur = HeroSprite.SPECIAL_DUR if a.special else float(HeroSprite.ATTACK_DUR[type])
				a.atk_t0 = now - v * a.atk_dur
			var feet := Vector2(130 + ci * cw + cw * 0.5, 40 + (ri + 1) * rh - 8)
			draw_line(feet + Vector2(-50, 0), feet + Vector2(50, 0), Color(0, 0, 0, 0.25), 1.0)
			HeroSprite.draw(self, a, feet, 120.0, now)
