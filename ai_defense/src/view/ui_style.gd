class_name UiStyle
extends RefCounted
## 터치 화면용 큰 글씨·큰 버튼 테마 (모든 버튼 최소 높이 72px ≥ 48px 기준)

const C_BG := Color("#18202c")
const C_CARD := Color("#243045")
const C_CARD_SEL := Color("#3d5a80")
const C_ACCENT := Color("#ffd166")
const C_TEXT := Color("#f4f4f4")
const C_SUB := Color("#b8c2d0")
const C_PRO := Color("#2f5d50")
const C_CON := Color("#5d4a2f")


static func box(col: Color, radius := 18, border := 0, border_col := Color.TRANSPARENT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	if border > 0:
		sb.set_border_width_all(border)
		sb.border_color = border_col
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	return sb


static func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 30
	t.set_color("font_color", "Label", C_TEXT)
	t.set_font_size("font_size", "Button", 34)
	t.set_color("font_color", "Button", C_TEXT)
	t.set_color("font_hover_color", "Button", C_TEXT)
	t.set_color("font_pressed_color", "Button", C_TEXT)
	t.set_color("font_focus_color", "Button", C_TEXT)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.35))
	t.set_stylebox("normal", "Button", box(Color("#3a4a63"), 18, 3, Color("#5b7091")))
	t.set_stylebox("hover", "Button", box(Color("#435673"), 18, 3, Color("#7d93b5")))
	t.set_stylebox("pressed", "Button", box(Color("#2b3a52"), 18, 3, C_ACCENT))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("disabled", "Button", box(Color("#283244"), 18, 3, Color("#36425a")))
	t.set_stylebox("panel", "PanelContainer", box(C_CARD, 20))
	t.set_stylebox("panel", "Panel", box(C_BG, 0))
	return t


static func label(text: String, fs := 30, col := C_TEXT, align := HORIZONTAL_ALIGNMENT_LEFT, wrap := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = align
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func button(text: String, min_w := 260, min_h := 84, fs := 34) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, min_h)
	b.add_theme_font_size_override("font_size", fs)
	b.focus_mode = Control.FOCUS_NONE
	return b


static func set_selected(b: Button, on: bool) -> void:
	if on:
		b.add_theme_stylebox_override("normal", box(C_CARD_SEL, 18, 5, C_ACCENT))
		b.add_theme_stylebox_override("hover", box(C_CARD_SEL, 18, 5, C_ACCENT))
	else:
		b.remove_theme_stylebox_override("normal")
		b.remove_theme_stylebox_override("hover")
