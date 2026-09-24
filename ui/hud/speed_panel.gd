class_name SpeedPanel
extends PanelContainer
## Пауза и скорость времени (x1/x2/x4). Кнопки и горячие клавиши управляют SimClock.
## Ускорение — чит: в обычном выживании кнопки ×2 и ×4 видны, но выключены (allow_speed = false).

var _clock: SimClock
var _pause_button: Button
var _speed_buttons: Array[Button] = []
## Разрешено ли ускорять время (творческий забег или включённые читы).
var _allow_speed: bool = true


func setup(clock: SimClock, allow_speed: bool = true) -> void:
	_clock = clock
	_allow_speed = allow_speed
	theme_type_variation = &"HudPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var row := UiUtil.hbox(4)
	add_child(row)

	_pause_button = _make_button("II", func() -> void: _clock.toggle_pause())
	row.add_child(_pause_button)
	for i in SimClock.SPEEDS.size():
		var b := _make_button("×%d" % SimClock.SPEEDS[i], _clock.set_speed_index.bind(i))
		b.disabled = i > 0 and not _allow_speed
		if b.disabled:
			b.tooltip_text = "HUD_SPEED_LOCKED"
		row.add_child(b)
		_speed_buttons.append(b)

	clock.state_changed.connect(_sync)
	Settings.bindings_changed.connect(_update_tooltips)
	_update_tooltips()
	_sync()


func _make_button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.custom_minimum_size = Vector2(44, 32)
	b.theme_type_variation = &"SlotButton"
	b.pressed.connect(callback)
	return b


func _sync() -> void:
	_pause_button.set_pressed_no_signal(_clock.paused)
	for i in _speed_buttons.size():
		_speed_buttons[i].set_pressed_no_signal(not _clock.paused and _clock.speed_index == i)


func _update_tooltips() -> void:
	_pause_button.tooltip_text = "%s (%s)" % [tr("ACTION_PAUSE"), InputActions.primary_label(&"pause")]
	if not _allow_speed:
		return
	var actions: Array[StringName] = [&"speed_1", &"speed_2", &"speed_3"]
	for i in _speed_buttons.size():
		_speed_buttons[i].tooltip_text = "%s (%s)" % [tr("ACTION_SPEED_%d" % (i + 1)), InputActions.primary_label(actions[i])]


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _pause_button != null:
		_update_tooltips()
