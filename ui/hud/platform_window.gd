class_name PlatformWindow
extends PanelContainer
## Окно пульта платформы добычи: вид планеты со спутника, рамка наводки на WASD (или клик мышью),
## кнопки «Развернуть» и «Отозвать», полоска разворачивания.
##
## Пока окно открыто, дрон стоит: WASD двигают рамку, а не его (Game._update_input_enabled).
## Наводка уходит командой PLATFORM_AIM — в сетевой игре платформу двигают все одинаково.

const SHIFT_LEFT := 200.0
## Как быстро рамка едет при зажатой клавише: первый шаг сразу, дальше раз в STEP_DELAY секунд.
const STEP_DELAY := 0.05
const FIRST_DELAY := 0.25

var _game: Game
var _run: Run
var _console: PlatformConsole
var _title: Label
var _status: Label
var _hint: Label
var _map: PlanetMapView
var _deploy_button: Button
var _recall_button: Button
var _progress: ProgressBar
var _hold: float = 0.0


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

	_hint = UiUtil.label("PLATFORM_HINT", &"DimLabel")
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(560, 0)
	column.add_child(_hint)

	_map = PlanetMapView.new()
	column.add_child(_map)
	_map.setup(_run)
	_map.tile_picked.connect(_on_tile_picked)

	_progress = ProgressBar.new()
	_progress.max_value = 1.0
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0, 10)
	column.add_child(_progress)

	_status = Label.new()
	_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	column.add_child(_status)

	var buttons := UiUtil.hbox(8)
	column.add_child(buttons)
	_deploy_button = UiUtil.button("PLATFORM_DEPLOY", _on_deploy)
	_deploy_button.focus_mode = Control.FOCUS_NONE
	buttons.add_child(_deploy_button)
	_recall_button = UiUtil.button("PLATFORM_RECALL", _on_recall)
	_recall_button.focus_mode = Control.FOCUS_NONE
	buttons.add_child(_recall_button)

	game.tools.selection_changed.connect(_on_selection_changed)


func is_open() -> bool:
	return visible


func close_window() -> void:
	if not visible:
		return
	visible = false
	_console = null
	if _game.tools.selected is PlatformEnd:
		_game.tools.select(null)


## Открыть окно пульта комнаты (для автопрогона и горячих клавиш).
func open_for(console: PlatformConsole) -> void:
	if console == null:
		return
	_console = console
	visible = true
	_map.aim = console.deployed_at if console.is_deployed() else _default_aim()
	_refresh()


func aim_tile() -> Vector2i:
	return _map.aim


## Сдвинуть рамку наводки (для автопрогона).
func move_aim(delta: Vector2i) -> void:
	if _run.planet == null:
		return
	var grid := _run.planet.grid
	_map.aim = Vector2i(clampi(_map.aim.x + delta.x, 0, grid.width - 1),
		clampi(_map.aim.y + delta.y, 0, grid.height - 1))
	_refresh()


## Куда смотреть, когда окно открыли впервые: ближайшее к базе место, куда платформа влезает.
## Целиться в саму площадку бессмысленно — там платформе не встать.
func _default_aim() -> Vector2i:
	var gate := _run.get_gateway(_run.planet)
	var middle := Vector2i(_run.planet.grid.width / 2, _run.planet.grid.height / 2)
	if gate != null and gate.world != null:
		middle = gate.origin + Vector2i.ONE * (gate.get_size() / 2)
	var side := Registry.base_def.platform_size
	for radius in range(side, side * 6, 2):
		for dir: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
			var candidate := middle + dir * radius
			if _run.can_place_platform(candidate, _console.room if _console != null else -1):
				return candidate
	return middle


func _on_selection_changed() -> void:
	var picked := _game.tools.selected
	if picked is PlatformConsole:
		open_for(picked as PlatformConsole)
	elif picked is PlatformCore:
		open_for((picked as PlatformCore).link.console if (picked as PlatformCore).link != null else null)
	elif visible:
		visible = false
		_console = null


func _process(delta: float) -> void:
	if not visible:
		return
	if _console == null or _console.world == null:
		close_window()
		return
	_step_keys(delta)
	_refresh()


## WASD двигают рамку: первый шаг сразу, дальше — с повтором, пока клавишу держат.
func _step_keys(delta: float) -> void:
	var step := Vector2i.ZERO
	if Input.is_action_pressed(&"move_left"):
		step.x -= 1
	if Input.is_action_pressed(&"move_right"):
		step.x += 1
	if Input.is_action_pressed(&"move_up"):
		step.y -= 1
	if Input.is_action_pressed(&"move_down"):
		step.y += 1
	if step == Vector2i.ZERO:
		_hold = 0.0
		return
	if _hold <= 0.0:
		move_aim(step)
		_hold = FIRST_DELAY
		return
	_hold -= delta
	if _hold <= 0.0:
		move_aim(step)
		_hold = STEP_DELAY


func _on_tile_picked(tile: Vector2i) -> void:
	_map.aim = tile
	_refresh()


func _on_deploy() -> void:
	if _console == null:
		return
	_run.submit(Command.Kind.PLATFORM_AIM, {"room": _console.room, "tile": _map.aim})


func _on_recall() -> void:
	if _console == null:
		return
	_run.submit(Command.Kind.PLATFORM_AIM, {"room": _console.room, "tile": PlatformConsole.NO_TILE})


func _refresh() -> void:
	if _console == null:
		return
	_title.text = "%s — %s" % [tr(_console.def.name_key), tr("PLATFORM_ROOM_%d" % (_console.room + 1))]
	_map.aim_ok = _run.can_place_platform(_map.aim, _console.room)
	_progress.value = _console.progress() if _console.is_busy() else 0.0
	_progress.visible = _console.is_busy()
	var lines := _console.get_info_lines()
	if not _map.aim_ok and not _console.is_busy():
		lines.append(tr("PLATFORM_BAD_SPOT"))
	_status.text = "\n".join(lines)
	_deploy_button.disabled = _console.is_busy() or not _map.aim_ok \
		or (_console.is_deployed() and _console.deployed_at == _map.aim)
	_recall_button.disabled = _console.is_busy() or not _console.is_deployed()
