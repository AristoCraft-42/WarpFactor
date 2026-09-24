class_name TeleportWindow
extends PanelContainer
## Окно центрального шлюза (клик по шлюзу на планете или по его паре в базе):
## очереди перехода, звёздная карта, описание выбранной планеты и телепорт.
## Телепорт заряжается (игра идёт дальше), зарядку можно отменить.

const SHIFT_LEFT := 200.0

var _game: Game
var _run: Run
var _title: Label
var _queues: Label
var _map_view: StarMapView
var _info: Label
var _start_button: Button
var _cancel_button: Button
var _progress: ProgressBar
var _charge_label: Label
var _gateway: GatewayBuilding


func setup(game: Game) -> void:
	_game = game
	_run = game.run
	theme_type_variation = &"CardPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	offset_left -= SHIFT_LEFT
	offset_right -= SHIFT_LEFT

	var column := UiUtil.vbox(10)
	add_child(column)
	var header := UiUtil.hbox(10)
	column.add_child(header)
	_title = Label.new()
	_title.theme_type_variation = &"HeaderLabel"
	_title.add_theme_font_size_override("font_size", 20)
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var close := UiUtil.button("✕", close_window)
	close.focus_mode = Control.FOCUS_NONE
	close.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	header.add_child(close)

	_queues = Label.new()
	_queues.theme_type_variation = &"DimLabel"
	_queues.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	column.add_child(_queues)

	column.add_child(UiUtil.label("TELEPORT_MAP_HINT", &"DimLabel"))
	_map_view = StarMapView.new()
	column.add_child(_map_view)
	_map_view.setup(_run)
	_map_view.node_selected.connect(func(_id: int) -> void: _refresh())

	_info = Label.new()
	_info.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(520, 120)
	column.add_child(_info)

	var buttons := UiUtil.hbox(10)
	column.add_child(buttons)
	_start_button = UiUtil.button("TELEPORT_START", _on_start, &"AccentButton")
	_start_button.focus_mode = Control.FOCUS_NONE
	_start_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	buttons.add_child(_start_button)
	_cancel_button = UiUtil.button("TELEPORT_CANCEL", func() -> void: _run.submit(Command.Kind.TELEPORT, {"node": -1}))
	_cancel_button.focus_mode = Control.FOCUS_NONE
	buttons.add_child(_cancel_button)
	_charge_label = Label.new()
	_charge_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_charge_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_charge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	buttons.add_child(_charge_label)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(0, 8)
	_progress.show_percentage = false
	_progress.max_value = 1.0
	column.add_child(_progress)

	game.tools.selection_changed.connect(_on_selection_changed)
	_run.teleport_state_changed.connect(_refresh)


func close_window() -> void:
	if not visible:
		return
	visible = false
	if _game.tools.selected is GatewayBuilding:
		_game.tools.select(null)


## Выбрать планету на звёздной карте (для автотестов и горячих клавиш).
func select_node(id: int) -> void:
	if _run.star_map.can_travel_to(id):
		_map_view.selected_id = id
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("cancel"):
		close_window()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not visible:
		return
	_update_queues()
	if _run.is_charging():
		_progress.value = _run.get_charge_fraction()
		_charge_label.text = tr("TELEPORT_CHARGING") % ceili(_run.get_charge_seconds_left())
	elif _run.get_teleport_ready_seconds() > 0.0:
		_charge_label.text = tr("TELEPORT_RECHARGE") % ThreatPanel._clock(_run.get_teleport_ready_seconds())
		_start_button.disabled = true
	elif _start_button.disabled and _run.star_map.get_node(_map_view.selected_id) != null:
		_start_button.disabled = false
		_charge_label.text = tr("TELEPORT_READY")


func _on_selection_changed() -> void:
	var b := _game.tools.selected
	if b is GatewayBuilding:
		_gateway = b
		visible = true
		var next := _run.star_map.get_next()
		if not _run.star_map.can_travel_to(_map_view.selected_id) and not next.is_empty():
			_map_view.selected_id = _run.charge_target if _run.is_charging() else next[0].id
		_refresh()
	elif visible:
		visible = false
		_gateway = null


func _on_start() -> void:
	if _run.get_teleport_ready_seconds() > 0.0:
		Events.toast(tr("TOAST_TELEPORT_RECHARGING") % ThreatPanel._clock(_run.get_teleport_ready_seconds()),
			Events.ToastKind.WARNING)
		return
	if _map_view.selected_id >= 0:
		_run.submit(Command.Kind.TELEPORT, {"node": _map_view.selected_id})


func _refresh() -> void:
	if _run == null:
		return
	if _gateway != null:
		_title.text = tr(_gateway.def.name_key)
	var charging := _run.is_charging()
	if charging:
		_map_view.selected_id = _run.charge_target
	var node := _run.star_map.get_node(_map_view.selected_id)
	_info.text = StarMapView.describe_node(node, true, _run.star_map.scan_level) if node != null else tr("TELEPORT_NO_TARGET")
	var ready_in := _run.get_teleport_ready_seconds()
	_start_button.visible = not charging
	_start_button.disabled = node == null or ready_in > 0.0
	if ready_in > 0.0:
		_charge_label.text = tr("TELEPORT_RECHARGE") % ThreatPanel._clock(ready_in)
	_start_button.text = tr("TELEPORT_START") % roundi(_run.run_def.charge_seconds)
	_cancel_button.visible = charging
	_progress.visible = charging
	_charge_label.text = tr("TELEPORT_CHARGING") % ceili(_run.get_charge_seconds_left()) if charging else tr("TELEPORT_PAD_HINT")
	_update_queues()


func _update_queues() -> void:
	if _run.link == null:
		return
	_queues.text = "%s   ·   %s" % [
		tr("INFO_GATEWAY_TO_BASE") % [_run.link.total_of(true), _run.link.capacity],
		tr("INFO_GATEWAY_TO_PLANET") % [_run.link.total_of(false), _run.link.capacity]]


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _info != null and visible:
		_refresh()
