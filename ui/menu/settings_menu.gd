class_name SettingsMenu
extends PanelContainer
## Меню настроек. Вкладки «Графика», «Игра», «Звук» строятся автоматически из описаний
## SettingEntry; вкладка «Управление» — переназначение клавиш с проверкой конфликтов.

signal closed

const TABS: Array[StringName] = [&"graphics", &"game", &"controls", &"audio"]
const TAB_TITLES := ["SETTINGS_TAB_GRAPHICS", "SETTINGS_TAB_GAME", "SETTINGS_TAB_CONTROLS", "SETTINGS_TAB_AUDIO"]

var _tabs: TabContainer
## key → Control значения (CheckButton / OptionButton / HSlider)
var _controls: Dictionary[StringName, Control] = {}
var _range_labels: Dictionary[StringName, Label] = {}
var _row_labels: Dictionary[StringName, Label] = {}

var _binding_buttons: Dictionary[StringName, Array] = {}
var _capture_action: StringName = &""
var _capture_slot: int = -1
var _controls_status: Label
var _rebuild_pending: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(900, 640)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	Settings.changed.connect(_on_setting_changed)
	Settings.bindings_changed.connect(_refresh_bindings)


func refresh() -> void:
	_cancel_capture()
	_sync_all()
	_refresh_bindings()
	if _controls_status != null:
		_controls_status.text = ""


func is_capturing() -> bool:
	return _capture_slot >= 0


# --- Построение ---

func _build() -> void:
	var previous_tab := _tabs.current_tab if _tabs != null else 0
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_controls.clear()
	_range_labels.clear()
	_row_labels.clear()
	_binding_buttons.clear()

	var root := UiUtil.vbox(10)
	add_child(root)
	root.add_child(UiUtil.label("SETTINGS_TITLE", &"HeaderLabel"))

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)
	for i in TABS.size():
		var page: Control
		if TABS[i] == &"controls":
			page = _build_controls_page()
		else:
			page = _build_entries_page(TABS[i])
		page.name = String(TABS[i])
		_tabs.add_child(page)
		_tabs.set_tab_title(i, TAB_TITLES[i])
	_tabs.current_tab = clampi(previous_tab, 0, TABS.size() - 1)

	var bottom := UiUtil.hbox(10)
	root.add_child(bottom)
	bottom.add_child(UiUtil.button("SETTINGS_RESET_TAB", _reset_current_tab))
	bottom.add_child(UiUtil.spacer())
	bottom.add_child(UiUtil.button("SETTINGS_BACK", _on_back, &"AccentButton"))
	_sync_all()


func _build_entries_page(tab: StringName) -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var margin := UiUtil.margin(8)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)
	var list := UiUtil.vbox(14)
	margin.add_child(list)

	for entry in Settings.entries_for_tab(tab):
		list.add_child(_build_entry_row(entry))
	if tab == Settings.TAB_AUDIO:
		var note := UiUtil.label("SET_AUDIO_NOTE", &"DimLabel")
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(note)
	return scroll


func _build_entry_row(entry: SettingEntry) -> Control:
	var row := UiUtil.hbox(16)
	var label := UiUtil.label(entry.label_key)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	if not entry.hint_key.is_empty():
		label.tooltip_text = entry.hint_key
	row.add_child(label)
	_row_labels[entry.key] = label

	var control: Control
	match entry.kind:
		SettingEntry.Kind.BOOL:
			var check := CheckButton.new()
			check.toggled.connect(func(on: bool) -> void: Settings.set_value(entry.key, on))
			control = check
		SettingEntry.Kind.CHOICE:
			var option := OptionButton.new()
			option.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			option.custom_minimum_size = Vector2(300, 0)
			for pair in entry.choices:
				option.add_item(tr(str(pair[1])))
			option.item_selected.connect(func(index: int) -> void: Settings.set_value(entry.key, entry.choices[index][0]))
			control = option
		SettingEntry.Kind.RANGE:
			var box := UiUtil.hbox(10)
			var slider := HSlider.new()
			slider.min_value = entry.min_value
			slider.max_value = entry.max_value
			slider.step = entry.step
			slider.custom_minimum_size = Vector2(230, 24)
			slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var value_label := Label.new()
			value_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			value_label.custom_minimum_size = Vector2(64, 0)
			value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			box.add_child(slider)
			box.add_child(value_label)
			_range_labels[entry.key] = value_label
			var dragging := [false]
			slider.drag_started.connect(func() -> void: dragging[0] = true)
			slider.drag_ended.connect(func(_changed: bool) -> void:
				dragging[0] = false
				Settings.set_value(entry.key, slider.value))
			slider.value_changed.connect(func(v: float) -> void:
				value_label.text = _format_range(entry, v)
				if not entry.apply_on_release or not dragging[0]:
					Settings.set_value(entry.key, v))
			_controls[entry.key] = slider
			row.add_child(box)
			_apply_enabled(entry, slider)
			return row
	control.custom_minimum_size.x = maxf(control.custom_minimum_size.x, 300.0)
	_controls[entry.key] = control
	row.add_child(control)
	_apply_enabled(entry, control)
	return row


func _build_controls_page() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var margin := UiUtil.margin(8)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)
	var list := UiUtil.vbox(6)
	margin.add_child(list)

	var hint := UiUtil.label("CONTROLS_HINT", &"DimLabel")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(hint)

	var current_group := ""
	for d in InputActions.definitions():
		if d["group"] != current_group:
			current_group = d["group"]
			var header := UiUtil.label(current_group, &"HeaderLabel")
			header.add_theme_font_size_override("font_size", 18)
			header.add_theme_color_override("font_color", UiTheme.YELLOW)
			list.add_child(header)
		var action: StringName = d["name"]
		var row := UiUtil.hbox(6)
		var label := UiUtil.label(d["label"])
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var buttons: Array = []
		for slot in InputActions.SLOTS:
			var b := Button.new()
			b.theme_type_variation = &"SlotButton"
			b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			b.custom_minimum_size = Vector2(190, 34)
			b.pressed.connect(_begin_capture.bind(action, slot))
			row.add_child(b)
			var clear := Button.new()
			clear.text = "✕"
			clear.tooltip_text = "CONTROLS_CLEAR"
			clear.custom_minimum_size = Vector2(34, 34)
			clear.pressed.connect(_clear_binding.bind(action, slot))
			row.add_child(clear)
			buttons.append(b)
		_binding_buttons[action] = buttons
		list.add_child(row)

	list.add_child(HSeparator.new())
	var bottom := UiUtil.hbox(12)
	bottom.add_child(UiUtil.button("CONTROLS_RESET", func() -> void:
		_cancel_capture()
		Settings.reset_bindings()
		_controls_status.text = tr("CONTROLS_RESET_DONE")))
	_controls_status = Label.new()
	_controls_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_controls_status.add_theme_color_override("font_color", UiTheme.ORANGE)
	_controls_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_controls_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_controls_status)
	list.add_child(bottom)
	_refresh_bindings()
	return scroll


# --- Синхронизация значений ---

func _sync_all() -> void:
	for entry in Settings.entries:
		_sync_entry(entry)


func _sync_entry(entry: SettingEntry) -> void:
	var control: Control = _controls.get(entry.key)
	if control == null:
		return
	var value: Variant = Settings.get_value(entry.key)
	match entry.kind:
		SettingEntry.Kind.BOOL:
			(control as CheckButton).set_pressed_no_signal(bool(value))
		SettingEntry.Kind.CHOICE:
			var option := control as OptionButton
			for i in entry.choices.size():
				if SettingEntry.same_value(entry.choices[i][0], value):
					option.select(i)
					break
		SettingEntry.Kind.RANGE:
			(control as HSlider).set_value_no_signal(float(value))
			_range_labels[entry.key].text = _format_range(entry, float(value))
	_apply_enabled(entry, control)


func _apply_enabled(entry: SettingEntry, control: Control) -> void:
	var enabled := entry.enabled
	if entry.key == &"graphics/resolution":
		enabled = Settings.get_int(&"graphics/window_mode") == 0
	if control is BaseButton:
		(control as BaseButton).disabled = not enabled
	elif control is Range:
		(control as Range).editable = enabled
	var label: Label = _row_labels.get(entry.key)
	if label != null:
		label.modulate = Color.WHITE if enabled else Color(1, 1, 1, 0.5)


func _format_range(entry: SettingEntry, value: float) -> String:
	if entry.percent:
		return "%d%%" % roundi(value * 100.0)
	return "%.2f%s" % [value, entry.suffix]


func _on_setting_changed(key: StringName) -> void:
	if key == &"game/language":
		# Пересобираем меню целиком, чтобы тексты выпадающих списков тоже перевелись.
		if not _rebuild_pending:
			_rebuild_pending = true
			_rebuild_deferred.call_deferred()
		return
	var entry := Settings.get_entry(key)
	if entry != null:
		_sync_entry(entry)
	if key == &"graphics/window_mode":
		_sync_entry(Settings.get_entry(&"graphics/resolution"))


func _rebuild_deferred() -> void:
	_rebuild_pending = false
	_build()


func _reset_current_tab() -> void:
	var tab := TABS[_tabs.current_tab]
	if tab == &"controls":
		_cancel_capture()
		Settings.reset_bindings()
		_controls_status.text = tr("CONTROLS_RESET_DONE")
	else:
		Settings.reset_tab(tab)


func _on_back() -> void:
	_cancel_capture()
	Settings.save_now()
	closed.emit()


# --- Переназначение клавиш ---

func _refresh_bindings() -> void:
	var bindings := InputActions.current_bindings()
	for action in _binding_buttons:
		var codes: PackedStringArray = bindings.get(action, PackedStringArray())
		var buttons: Array = _binding_buttons[action]
		for slot in buttons.size():
			var b: Button = buttons[slot]
			if action == _capture_action and slot == _capture_slot:
				b.text = tr("CONTROLS_PRESS_KEY")
			elif slot < codes.size():
				b.text = InputActions.label_for_code(codes[slot])
			else:
				b.text = "—"


func _begin_capture(action: StringName, slot: int) -> void:
	_capture_action = action
	_capture_slot = slot
	_controls_status.text = ""
	_refresh_bindings()


func _cancel_capture() -> void:
	if _capture_slot < 0:
		return
	_capture_action = &""
	_capture_slot = -1
	_refresh_bindings()


func _input(event: InputEvent) -> void:
	if _capture_slot < 0 or not is_visible_in_tree():
		return
	var code := ""
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		if key.physical_keycode == KEY_ESCAPE or key.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_cancel_capture()
			return
		code = InputActions.encode(key)
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if not mouse.pressed:
			return
		code = InputActions.encode(mouse)
	else:
		return
	get_viewport().set_input_as_handled()
	if code.is_empty():
		return
	var action := _capture_action
	var slot := _capture_slot
	_capture_action = &""
	_capture_slot = -1
	_assign_binding(action, slot, code)


func _assign_binding(action: StringName, slot: int, code: String) -> void:
	var bindings := InputActions.current_bindings()
	var removed_from := PackedStringArray()
	for other in bindings:
		if other == action:
			continue
		var other_codes: PackedStringArray = bindings[other]
		var index := other_codes.find(code)
		if index >= 0:
			other_codes.remove_at(index)
			Settings.set_action_codes(other, other_codes)
			removed_from.append(tr(_action_label(other)))

	var codes: PackedStringArray = InputActions.current_bindings().get(action, PackedStringArray())
	var existing := codes.find(code)
	if existing >= 0:
		codes.remove_at(existing)
	if slot < codes.size():
		codes[slot] = code
	else:
		codes.append(code)
	Settings.set_action_codes(action, codes)

	if removed_from.is_empty():
		_controls_status.text = ""
	else:
		_controls_status.text = tr("CONTROLS_CONFLICT") % [InputActions.label_for_code(code), ", ".join(removed_from)]
	_refresh_bindings()


func _clear_binding(action: StringName, slot: int) -> void:
	_cancel_capture()
	var codes: PackedStringArray = InputActions.current_bindings().get(action, PackedStringArray())
	if slot < codes.size():
		codes.remove_at(slot)
		Settings.set_action_codes(action, codes)


func _action_label(action: StringName) -> String:
	for d in InputActions.definitions():
		if d["name"] == action:
			return d["label"]
	return String(action)
