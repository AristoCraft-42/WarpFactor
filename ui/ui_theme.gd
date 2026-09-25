class_name UiTheme
extends RefCounted
## Тема интерфейса (палитра Gruvbox). Строится кодом и назначается корневому окну.
## Вариации типов: TitleLabel, HeaderLabel, DimLabel, BigButton, AccentButton,
## HudPanel, CardPanel, BadgeLabel.

const BG_HARD := Color("1d2021")
const BG0 := Color("282828")
const BG1 := Color("3c3836")
const BG2 := Color("504945")
const BG3 := Color("665c54")
const BG4 := Color("7c6f64")
const FG := Color("ebdbb2")
const FG2 := Color("d5c4a1")
const FG4 := Color("a89984")
const GRAY := Color("928374")
const YELLOW := Color("fabd2f")
const ORANGE := Color("fe8019")
const RED := Color("fb4934")
const GREEN := Color("b8bb26")
const AQUA := Color("8ec07c")
const BLUE := Color("83a598")

const FONT_SIZE := 16

static var _theme: Theme


## Общая тема. Controls под CanvasLayer не наследуют тему окна,
## поэтому корни таких интерфейсов получают её явно.
static func get_theme() -> Theme:
	if _theme == null:
		_theme = build()
	return _theme


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = FONT_SIZE

	# Панели
	t.set_stylebox("panel", "Panel", _box(BG0, BG2, 1, 6))
	t.set_stylebox("panel", "PanelContainer", _box(BG0, BG2, 1, 6, 12))
	t.set_type_variation("HudPanel", "PanelContainer")
	t.set_stylebox("panel", "HudPanel", _box(Color(BG0, 0.92), Color(BG2, 0.9), 1, 6, 8))
	t.set_type_variation("CardPanel", "PanelContainer")
	t.set_stylebox("panel", "CardPanel", _box(BG1, BG2, 1, 6, 12))

	# Надписи
	t.set_color("font_color", "Label", FG)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	t.set_type_variation("TitleLabel", "Label")
	t.set_font_size("font_size", "TitleLabel", 72)
	t.set_color("font_color", "TitleLabel", YELLOW)
	t.set_color("font_shadow_color", "TitleLabel", Color(0, 0, 0, 0.55))
	t.set_constant("shadow_offset_x", "TitleLabel", 4)
	t.set_constant("shadow_offset_y", "TitleLabel", 4)
	t.set_type_variation("HeaderLabel", "Label")
	t.set_font_size("font_size", "HeaderLabel", 26)
	t.set_color("font_color", "HeaderLabel", FG)
	t.set_type_variation("DimLabel", "Label")
	t.set_font_size("font_size", "DimLabel", 14)
	t.set_color("font_color", "DimLabel", FG4)
	t.set_type_variation("BadgeLabel", "Label")
	t.set_font_size("font_size", "BadgeLabel", 13)
	t.set_color("font_color", "BadgeLabel", BG_HARD)
	t.set_stylebox("normal", "BadgeLabel", _box(YELLOW, YELLOW, 0, 4, 2, 6))
	# Строка чата: на жёлтом бейдже цветное имя игрока не читалось, поэтому подложка тёмная.
	t.set_type_variation("ChatLabel", "Label")
	t.set_font_size("font_size", "ChatLabel", 14)
	t.set_color("font_color", "ChatLabel", FG)
	t.set_stylebox("normal", "ChatLabel", _box(Color(BG_HARD, 0.72), Color(BG2, 0.6), 1, 4, 3, 7))

	# Кнопки
	_style_button(t, "Button", BG1, BG2, BG3, BG0)
	t.set_type_variation("BigButton", "Button")
	t.set_font_size("font_size", "BigButton", 22)
	_style_button(t, "BigButton", Color(BG1, 0.92), BG2, BG3, Color(BG0, 0.7), 14)
	t.set_type_variation("AccentButton", "Button")
	_style_button(t, "AccentButton", Color("b57614"), Color("d79921"), YELLOW, BG1)
	t.set_color("font_color", "AccentButton", BG_HARD)
	t.set_color("font_hover_color", "AccentButton", BG_HARD)
	t.set_color("font_pressed_color", "AccentButton", BG_HARD)
	t.set_color("font_focus_color", "AccentButton", BG_HARD)
	t.set_type_variation("SlotButton", "Button")
	_style_button(t, "SlotButton", BG0, BG1, BG2, BG0, 4)

	# Выпадающие списки, флажки
	_style_button(t, "OptionButton", BG1, BG2, BG3, BG0)
	t.set_constant("arrow_margin", "OptionButton", 8)
	t.set_color("font_color", "CheckBox", FG)
	t.set_color("font_hover_color", "CheckBox", YELLOW)
	t.set_color("font_pressed_color", "CheckBox", FG)
	t.set_color("font_focus_color", "CheckBox", FG)
	t.set_stylebox("normal", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("hover", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("pressed", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("hover_pressed", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("focus", "CheckBox", StyleBoxEmpty.new())
	t.set_icon("unchecked", "CheckBox", _check_icon(false, true))
	t.set_icon("checked", "CheckBox", _check_icon(true, true))
	t.set_icon("unchecked_disabled", "CheckBox", _check_icon(false, false))
	t.set_icon("checked_disabled", "CheckBox", _check_icon(true, false))
	t.set_constant("h_separation", "CheckBox", 8)
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		t.set_stylebox(state, "CheckButton", StyleBoxEmpty.new())
	t.set_color("font_color", "CheckButton", FG)
	t.set_color("font_hover_color", "CheckButton", YELLOW)
	t.set_color("font_pressed_color", "CheckButton", FG)

	# Поля ввода
	t.set_stylebox("normal", "LineEdit", _box(BG_HARD, BG2, 1, 4, 6))
	t.set_stylebox("focus", "LineEdit", _box(BG_HARD, YELLOW, 1, 4, 6))
	t.set_color("font_color", "LineEdit", FG)
	t.set_color("caret_color", "LineEdit", YELLOW)
	t.set_color("selection_color", "LineEdit", Color(BLUE, 0.4))

	# Ползунки
	t.set_stylebox("slider", "HSlider", _box(BG_HARD, BG2, 1, 3, 0, 0, 3))
	t.set_stylebox("grabber_area", "HSlider", _box(Color("b57614"), Color("b57614"), 0, 3, 0, 0, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(YELLOW, YELLOW, 0, 3, 0, 0, 3))

	# Вкладки
	t.set_stylebox("panel", "TabContainer", _box(BG0, BG2, 1, 6, 12))
	t.set_stylebox("tab_selected", "TabContainer", _tab_box(BG0, YELLOW))
	t.set_stylebox("tab_unselected", "TabContainer", _tab_box(BG_HARD, BG1))
	t.set_stylebox("tab_hovered", "TabContainer", _tab_box(BG1, BG3))
	t.set_stylebox("tab_disabled", "TabContainer", _tab_box(BG_HARD, BG_HARD))
	t.set_stylebox("tab_focus", "TabContainer", StyleBoxEmpty.new())
	t.set_color("font_selected_color", "TabContainer", YELLOW)
	t.set_color("font_unselected_color", "TabContainer", FG4)
	t.set_color("font_hovered_color", "TabContainer", FG)
	t.set_font_size("font_size", "TabContainer", 17)

	# Списки
	t.set_stylebox("panel", "ItemList", _box(BG_HARD, BG2, 1, 4, 6))
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("selected", "ItemList", _box(Color(YELLOW, 0.18), Color(YELLOW, 0.6), 1, 3))
	t.set_stylebox("selected_focus", "ItemList", _box(Color(YELLOW, 0.22), YELLOW, 1, 3))
	t.set_stylebox("hovered", "ItemList", _box(Color(FG, 0.06), Color(0, 0, 0, 0), 0, 3))
	t.set_color("font_color", "ItemList", FG2)
	t.set_color("font_selected_color", "ItemList", YELLOW)
	t.set_color("font_hovered_color", "ItemList", FG)
	t.set_constant("v_separation", "ItemList", 8)

	# Всплывающие меню и подсказки
	t.set_stylebox("panel", "PopupMenu", _box(BG0, BG3, 1, 4, 4))
	t.set_stylebox("hover", "PopupMenu", _box(Color(YELLOW, 0.2), Color(0, 0, 0, 0), 0, 3))
	t.set_color("font_color", "PopupMenu", FG2)
	t.set_color("font_hover_color", "PopupMenu", YELLOW)
	t.set_stylebox("panel", "TooltipPanel", _box(BG_HARD, BG3, 1, 4, 8))
	t.set_color("font_color", "TooltipLabel", FG)
	t.set_font_size("font_size", "TooltipLabel", 15)

	# Диалоги
	t.set_stylebox("embedded_border", "Window", _box(BG0, YELLOW, 2, 6, 8))
	t.set_stylebox("embedded_unfocused_border", "Window", _box(BG0, BG3, 2, 6, 8))
	t.set_color("title_color", "Window", YELLOW)
	t.set_stylebox("panel", "AcceptDialog", _box(BG0, BG0, 0, 0, 12))

	# Полосы прокрутки и разделители
	t.set_stylebox("scroll", "VScrollBar", _box(BG_HARD, BG_HARD, 0, 4, 0, 0, 6))
	t.set_stylebox("grabber", "VScrollBar", _box(BG3, BG3, 0, 4, 0, 0, 6))
	t.set_stylebox("grabber_hover", "VScrollBar", _box(BG4, BG4, 0, 4, 0, 0, 6))
	t.set_stylebox("grabber_pressed", "VScrollBar", _box(GRAY, GRAY, 0, 4, 0, 0, 6))
	var sep := StyleBoxLine.new()
	sep.color = BG2
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 12)

	t.set_stylebox("background", "ProgressBar", _box(BG_HARD, BG2, 1, 4))
	t.set_stylebox("fill", "ProgressBar", _box(Color("b57614"), Color("b57614"), 0, 4))
	return t


static func _style_button(t: Theme, type: StringName, normal: Color, hover: Color, pressed: Color, disabled: Color, padding: int = 8) -> void:
	t.set_stylebox("normal", type, _box(normal, BG2, 1, 5, padding, padding + 6))
	t.set_stylebox("hover", type, _box(hover, BG4, 1, 5, padding, padding + 6))
	t.set_stylebox("pressed", type, _box(pressed, YELLOW, 1, 5, padding, padding + 6))
	t.set_stylebox("hover_pressed", type, _box(pressed, YELLOW, 1, 5, padding, padding + 6))
	t.set_stylebox("disabled", type, _box(disabled, BG1, 1, 5, padding, padding + 6))
	t.set_stylebox("focus", type, _box(Color(0, 0, 0, 0), Color(YELLOW, 0.7), 1, 5))
	t.set_color("font_color", type, FG)
	t.set_color("font_hover_color", type, YELLOW)
	t.set_color("font_pressed_color", type, YELLOW)
	t.set_color("font_hover_pressed_color", type, YELLOW)
	t.set_color("font_focus_color", type, FG)
	t.set_color("font_disabled_color", type, Color(FG4, 0.55))
	t.set_color("icon_normal_color", type, Color.WHITE)
	t.set_color("icon_hover_color", type, Color.WHITE)
	t.set_color("icon_pressed_color", type, Color.WHITE)
	t.set_color("icon_disabled_color", type, Color(1, 1, 1, 0.35))


## StyleBoxFlat: фон, рамка, радиус, внутренние отступы по вертикали и горизонтали.
static func _box(bg: Color, border: Color, border_width: int, radius: int, pad_v: int = 0, pad_h: int = -1, expand_v: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(radius)
	var h := pad_h if pad_h >= 0 else pad_v
	s.content_margin_top = pad_v
	s.content_margin_bottom = pad_v
	s.content_margin_left = h
	s.content_margin_right = h
	if expand_v > 0:
		s.content_margin_top = expand_v
		s.content_margin_bottom = expand_v
	return s


## Иконка флажка 20x20: рамка, при включении — жёлтая заливка с галочкой.
static func _check_icon(checked: bool, enabled: bool) -> ImageTexture:
	var size := 20
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var border := YELLOW if checked else FG4
	if not enabled:
		border = Color(border, 0.4)
	img.fill_rect(Rect2i(1, 1, size - 2, size - 2), border)
	img.fill_rect(Rect2i(3, 3, size - 6, size - 6), Color(YELLOW, 1.0 if enabled else 0.4) if checked else BG_HARD)
	if checked:
		var mark := [Vector2i(5, 10), Vector2i(6, 11), Vector2i(7, 12), Vector2i(8, 13), Vector2i(9, 12), Vector2i(10, 11), Vector2i(11, 10), Vector2i(12, 9), Vector2i(13, 8), Vector2i(14, 7)]
		for p in mark:
			img.fill_rect(Rect2i(p.x, p.y - 1, 2, 2), BG_HARD)
	return ImageTexture.create_from_image(img)


static func _tab_box(bg: Color, accent: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = accent
	s.border_width_top = 3
	s.set_corner_radius_all(0)
	s.corner_radius_top_left = 5
	s.corner_radius_top_right = 5
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s
