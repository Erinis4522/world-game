extends SceneTree
## 흰 배경에서 오려 낸 PNG의 흰 테두리(매트)를 정리한다. 파일을 덮어쓴다 (원본은 따로 보관할 것).
##   godot --headless --path . --script res://tools/defringe.gd -- assets/heroes/archer.png [...]
## 1) 반투명 픽셀: 흰색과 섞인 색을 되돌림 (c = (c − (1−a)·흰색) / a)
## 2) 바깥 가장자리의 하얀 픽셀을 최대 2겹 벗겨 냄 (진한 외곽선은 남김)


func _init() -> void:
	for rel in OS.get_cmdline_user_args():
		var path := ProjectSettings.globalize_path("res://" + rel)
		var img := Image.load_from_file(path)
		if img == null or img.is_empty():
			print("읽기 실패: ", rel)
			continue
		img.convert(Image.FORMAT_RGBA8)
		var w := img.get_width()
		var h := img.get_height()
		var fixed := 0
		for y in h:
			for x in w:
				var c := img.get_pixel(x, y)
				if c.a > 0.02 and c.a < 0.98:
					var r := clampf((c.r - (1.0 - c.a)) / c.a, 0.0, 1.0)
					var g := clampf((c.g - (1.0 - c.a)) / c.a, 0.0, 1.0)
					var b := clampf((c.b - (1.0 - c.a)) / c.a, 0.0, 1.0)
					img.set_pixel(x, y, Color(r, g, b, c.a))
					fixed += 1
		var peeled := 0
		for pass_i in 2:
			var kill: Array = []
			for y in h:
				for x in w:
					var c := img.get_pixel(x, y)
					if c.a <= 0.02:
						continue
					if minf(c.r, minf(c.g, c.b)) < 0.78 or (maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))) > 0.12:
						continue  # 하얗지 않은 픽셀은 그대로
					var border := false
					for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var q: Vector2i = Vector2i(x, y) + d
						if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h or img.get_pixelv(q).a <= 0.02:
							border = true
							break
					if border:
						kill.append(Vector2i(x, y))
			for p in kill:
				img.set_pixelv(p, Color(0, 0, 0, 0))
			peeled += kill.size()
		img.save_png(path)
		print("%s: 반투명 보정 %d, 흰 테두리 제거 %d" % [rel, fixed, peeled])
	quit()
