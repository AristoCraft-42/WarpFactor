class_name SavesScreen
extends PanelContainer
## Список сохранений: загрузка, удаление, а в игре — сохранение в новый или существующий слот.
## Строка: имя — планета — дата — время игры. Загрузка перезапускает игровую сцену.

signal back_requested

enum Mode { LOAD, SAVE }

var mode: Mode = Mode.LOAD
var run: Run

var _title: Label
var _list: ItemList
var _name_row: HBoxContainer
var _name_edit: LineEdit
var _save_button: Button
var _load_button: Button
var _delete_button: Button
var _empty_label: Label
var _confirm: ConfirmationDialog
var _saves: Array[Dictionary] = []
var _pending_action: Callable


func _ready() -> void:
	custom_minimum_size = Vector2(820, 560)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var root := UiUtil.vbox(12)
	add_child(root)
	_title = Label.new()
	_title.theme_type_variation = &"HeaderLabel"
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	root.add_child(_title)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_list.item_selected.connect(_on_selected)
	_list.item_activated.connect(func(_i: int) -> void: _on_primary())
	root.add_child(_list)
	_empty_label = UiUtil.label("SAVES_EMPTY", &"DimLabel")
	root.add_child(_empty_label)

	_name_row = UiUtil.hbox(10)
	root.add_child(_name_row)
	_name_row.add_child(UiUtil.label("SAVES_NAME"))
	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_submitted.connect(func(_t: String) -> void: _on_save())
	_name_row.add_child(_name_edit)

	var bottom := UiUtil.hbox(10)
	root.add_child(bottom)
	bottom.add_child(UiUtil.button("SETTINGS_BACK", func() -> void: back_requested.emit()))
	bottom.add_child(UiUtil.spacer())
	_delete_button = UiUtil.button("SAVES_DELETE", _on_delete)
	bottom.add_child(_delete_button)
	_load_button = UiUtil.button("MENU_LOAD", _on_load, &"AccentButton")
	_load_button.custom_minimum_size = Vector2(160, 0)
	bottom.add_child(_load_button)
	_save_button = UiUtil.button("PAUSE_SAVE", _on_save, &"AccentButton")
	_save_button.custom_minimum_size = Vector2(160, 0)
	bottom.add_child(_save_button)

	_confirm = ConfirmationDialog.new()
	_confirm.theme = UiTheme.get_theme()
	_confirm.title = "CONFIRM_TITLE"
	_confirm.cancel_button_text = "CONFIRM_CANCEL"
	_confirm.confirmed.connect(func() -> void:
		if _pending_action.is_valid():
			_pending_action.call())
	add_child(_confirm)


## Открыть в режиме загрузки или сохранения (для сохранения нужен текущий забег).
func open(p_mode: Mode, p_run: Run = null) -> void:
	mode = p_mode
	run = p_run
	visible = true
	refresh()


func refresh() -> void:
	_title.text = tr("SAVES_TITLE_SAVE") if mode == Mode.SAVE else tr("SAVES_TITLE_LOAD")
	_saves = SaveIO.list_saves()
	_list.clear()
	for header in _saves:
		_list.add_item(_row_text(header))
	_empty_label.visible = _saves.is_empty()
	_name_row.visible = mode == Mode.SAVE
	_save_button.visible = mode == Mode.SAVE
	_load_button.visible = mode == Mode.LOAD
	if mode == Mode.SAVE and run != null and _name_edit.text.strip_edges().is_empty():
		_name_edit.text = run.get_world_title(run.planet)
	_update_buttons()


func _row_text(header: Dictionary) -> String:
	var playtime := int(header.get("playtime", 0.0))
	var place := String(header.get("title", ""))
	if bool(header.get("in_base", false)):
		place += " · " + tr("LOCATION_BASE")
	var date := Time.get_datetime_string_from_unix_time(int(header.get("saved_at", 0)) + _timezone_offset(), true)
	return "%s   —   %s   —   %s   —   %d:%02d:%02d" % [header.get("name", "?"), place, date,
		playtime / 3600, (playtime / 60) % 60, playtime % 60]


func _on_selected(index: int) -> void:
	if mode == Mode.SAVE:
		_name_edit.text = String(_saves[index].get("name", ""))
	_update_buttons()


func _update_buttons() -> void:
	var has_selection := not _list.get_selected_items().is_empty()
	_load_button.disabled = not has_selection
	_delete_button.disabled = not has_selection
	_save_button.disabled = run == null


func _on_primary() -> void:
	if mode == Mode.SAVE:
		_on_save()
	else:
		_on_load()


func _on_save() -> void:
	if run == null:
		return
	var name := _name_edit.text.strip_edges()
	if name.is_empty():
		name = run.get_world_title(run.planet)
	if FileAccess.file_exists(SaveIO.slot_path(name)):
		_ask(tr("SAVES_OVERWRITE") % name, func() -> void: _write(name))
	else:
		_write(name)


func _write(name: String) -> void:
	if SaveIO.save_run(run, name) == OK:
		Events.toast(tr("TOAST_SAVED") % name, Events.ToastKind.SUCCESS)
	else:
		Events.toast(tr("TOAST_SAVE_FAILED"), Events.ToastKind.WARNING)
	refresh()


func _on_load() -> void:
	var selected := _list.get_selected_items()
	if selected.is_empty():
		return
	Session.load_game(String(_saves[selected[0]]["path"]))


func _on_delete() -> void:
	var selected := _list.get_selected_items()
	if selected.is_empty():
		return
	var header := _saves[selected[0]]
	_ask(tr("SAVES_DELETE_CONFIRM") % header.get("name", ""), func() -> void:
		SaveIO.delete_save(String(header["path"]))
		refresh())


func _ask(text: String, action: Callable) -> void:
	_pending_action = action
	_confirm.dialog_text = text
	_confirm.ok_button_text = tr("CONFIRM_OK")
	_confirm.popup_centered()


static func _timezone_offset() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _list != null and visible:
		refresh()
