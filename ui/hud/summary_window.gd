class_name SummaryWindow
extends PanelContainer
## Итог планеты после телепорта: время, что ушло в базу, что переехало с площадкой, что потеряно,
## сколько было волн и что разрушили враги. Аварийный телепорт (прорыв к шлюзу) отмечен отдельно.

const MAX_ICONS := 10

var _title: Label
var _lines: Label
var _sent_row: HBoxContainer
var _ok_button: Button


func setup() -> void:
	theme_type_variation = &"CardPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var column := UiUtil.vbox(10)
	column.custom_minimum_size = Vector2(460, 0)
	add_child(column)
	_title = Label.new()
	_title.theme_type_variation = &"HeaderLabel"
	_title.add_theme_font_size_override("font_size", 20)
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	column.add_child(_title)
	_lines = Label.new()
	_lines.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_lines.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_lines)
	column.add_child(UiUtil.label("SUMMARY_SENT", &"DimLabel"))
	_sent_row = UiUtil.hbox(4)
	column.add_child(_sent_row)
	_ok_button = UiUtil.button("SUMMARY_OK", close_window, &"AccentButton")
	_ok_button.focus_mode = Control.FOCUS_NONE
	_ok_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	column.add_child(_ok_button)


func show_summary(summary: TeleportSummary) -> void:
	if summary == null:
		return
	_title.text = tr("SUMMARY_EMERGENCY_TITLE" if summary.emergency else "SUMMARY_TITLE") % summary.to_title
	_title.add_theme_color_override("font_color", UiTheme.RED if summary.emergency else UiTheme.YELLOW)
	var lines := PackedStringArray()
	if summary.emergency:
		lines.append(tr("SUMMARY_EMERGENCY"))
	lines.append(tr("SUMMARY_LEFT") % [summary.from_title, int(summary.seconds_on_planet) / 60, int(summary.seconds_on_planet) % 60])
	lines.append(tr("SUMMARY_MOVED") % summary.buildings_moved)
	lines.append(tr("SUMMARY_LOST") % [summary.buildings_lost, TeleportSummary.total(summary.items_lost)])
	if summary.waves > 0 or summary.buildings_destroyed > 0:
		lines.append(tr("SUMMARY_COMBAT") % [summary.waves, summary.buildings_destroyed])
	if summary.to_safe:
		lines.append(tr("SUMMARY_SAFE"))
	_lines.text = "\n".join(lines)
	for child in _sent_row.get_children():
		_sent_row.remove_child(child)
		child.queue_free()
	var order: Array[int] = []
	for item in summary.sent_to_base.size():
		if summary.sent_to_base[item] > 0:
			order.append(item)
	order.sort_custom(func(a: int, b: int) -> bool: return summary.sent_to_base[a] > summary.sent_to_base[b])
	for i in mini(order.size(), MAX_ICONS):
		var slot := ItemSlot.new()
		slot.set_stack(order[i], summary.sent_to_base[order[i]])
		_sent_row.add_child(slot)
	if order.is_empty():
		_sent_row.add_child(UiUtil.label("SUMMARY_NOTHING", &"DimLabel"))
	visible = true


func close_window() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("cancel"):
		close_window()
		get_viewport().set_input_as_handled()
