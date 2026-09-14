class_name ItemSlot
extends Button
## Ячейка с предметом: иконка и количество в правом нижнем углу.
## Сообщает о клике любой кнопкой мыши (ЛКМ — всё, ПКМ — половина и т. п. решает владелец).

signal slot_clicked(button: MouseButton, shift: bool)

const SIZE := 44

var item: int = -1
var amount: int = 0

var _count: Label


func _init() -> void:
	theme_type_variation = &"SlotButton"
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(SIZE, SIZE)
	expand_icon = true
	icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_count = Label.new()
	_count.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_count.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_count.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_count.offset_right = -3
	_count.offset_bottom = 1
	_count.add_theme_font_size_override("font_size", 13)
	_count.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_count.add_theme_constant_override("outline_size", 4)
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count)
	gui_input.connect(_on_gui_input)


## Показать стопку (item < 0 — пустая ячейка). keep_icon — показывать иконку и при нулевом количестве
## (кнопка рецепта, который сейчас не из чего крафтить).
func set_stack(p_item: int, p_amount: int, keep_icon: bool = false) -> void:
	if p_item == item and p_amount == amount:
		return
	item = p_item
	amount = p_amount
	if item < 0 or (amount <= 0 and not keep_icon):
		icon = null
		_count.text = ""
		tooltip_text = ""
		return
	var type := Registry.items[item]
	icon = ArtRegistry.get_item_icon(type)
	_count.text = _format(amount) if amount > 0 else ""
	tooltip_text = "%s × %d" % [tr(type.name_key), amount]


func _on_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
		slot_clicked.emit(mb.button_index, mb.shift_pressed)
		accept_event()


static func _format(value: int) -> String:
	if value >= 10000:
		return "%dk" % (value / 1000)
	return str(value)
