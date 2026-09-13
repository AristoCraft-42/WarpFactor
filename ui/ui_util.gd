class_name UiUtil
extends RefCounted
## Небольшие фабрики Control-нод, чтобы интерфейс, собираемый кодом, читался компактно.
## Тексты передаются ключами перевода: Label/Button переводят их автоматически
## и обновляются при смене языка.


static func label(text_key: String, variation: StringName = &"") -> Label:
	var l := Label.new()
	l.text = text_key
	if not variation.is_empty():
		l.theme_type_variation = variation
	return l


static func button(text_key: String, on_pressed: Callable = Callable(), variation: StringName = &"") -> Button:
	var b := Button.new()
	b.text = text_key
	if not variation.is_empty():
		b.theme_type_variation = variation
	if on_pressed.is_valid():
		b.pressed.connect(on_pressed)
	return b


static func vbox(separation: int = 8) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box


static func hbox(separation: int = 8) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box


static func margin(all: int) -> MarginContainer:
	var m := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(side, all)
	return m


static func spacer(horizontal: bool = true) -> Control:
	var c := Control.new()
	if horizontal:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


## Control на весь родитель, не перехватывающий мышь.
static func full_rect(control: Control, mouse_ignore: bool = true) -> Control:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if mouse_ignore:
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return control


## Затемняющий фон модальных окон, перехватывающий клики.
static func dimmer(alpha: float = 0.6) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = Color(0, 0, 0, alpha)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	return rect
