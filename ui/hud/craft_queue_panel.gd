class_name CraftQueuePanel
extends PanelContainer
## Очередь ручного крафта над нижним краем экрана: группы одинаковых крафтов с количеством
## и прогресс текущего. Отмена — как крафт: ЛКМ — одна единица, ПКМ — пять, Shift+ЛКМ — все такие
## (сырьё возвращается в инвентарь).

const MAX_GROUPS := 10

var _queue: CraftQueue
var _row: HBoxContainer
var _progress: ProgressBar
var _status: Label
var _revision: int = -1
var _blocked: bool = false


func setup(drone: Drone) -> void:
	_queue = drone.crafting
	theme_type_variation = &"HudPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var column := UiUtil.vbox(4)
	add_child(column)
	var header := UiUtil.hbox(8)
	column.add_child(header)
	header.add_child(UiUtil.label("CRAFT_QUEUE", &"DimLabel"))
	_status = Label.new()
	_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_status.add_theme_color_override("font_color", UiTheme.RED)
	header.add_child(_status)
	_row = UiUtil.hbox(4)
	column.add_child(_row)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(0, 6)
	_progress.show_percentage = false
	_progress.max_value = 1.0
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_progress)


func _process(_delta: float) -> void:
	if _queue == null:
		return
	if _queue.revision != _revision:
		_revision = _queue.revision
		_rebuild()
	if visible:
		_progress.value = _queue.get_progress()


func _rebuild() -> void:
	visible = not _queue.is_empty()
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	var groups := _queue.get_groups()
	for i in mini(groups.size(), MAX_GROUPS):
		var recipe: HandRecipe = groups[i][0]
		var slot := ItemSlot.new()
		slot.set_stack(recipe.output.index, groups[i][1])
		slot.tooltip_text = tr("CRAFT_QUEUE_CANCEL") % tr(recipe.output.name_key)
		slot.slot_clicked.connect(_on_group_clicked.bind(recipe))
		_row.add_child(slot)
	_status.text = tr("CRAFT_QUEUE_BLOCKED") if _queue.blocked else ""


func _on_group_clicked(button: MouseButton, shift: bool, recipe: HandRecipe) -> void:
	var count := 1
	if button == MOUSE_BUTTON_RIGHT:
		count = 5
	elif shift:
		count = _queue.count_of(recipe)
	_queue.cancel_last(recipe, count)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _row != null:
		_rebuild()
