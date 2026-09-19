class_name ThreatPanel
extends PanelContainer
## Угроза текущей планеты в HUD: отсчёт до волны, идущая волна или непрерывная атака, число врагов,
## прочность шлюза. Видна в любом мире (из базы тоже нужно следить), скрыта на безопасной планете.
## Уведомления: предупреждение перед волной, начало волны, переход к непрерывной атаке, атака на шлюз.

const REFRESH := 0.1
const GATE_ALERT_COOLDOWN := 15.0

var _game: Game
var _wave_label: Label
var _enemies_label: Label
var _gate_row: HBoxContainer
var _gate_label: Label
var _gate_bar: ProgressBar
var _timer: float = 0.0
var _gate_alert_timer: float = 0.0
var _creative_row: HBoxContainer
var _wave_button: Button
var _waves_toggle: CheckButton
## Для уведомлений: мир планеты, последняя предупреждённая и начавшаяся волна, прочность шлюза.
var _tracked_world: GameWorld
var _warned_wave: int = 0
var _started_wave: int = 0
var _continuous_announced: bool = false
var _last_gate_health: float = -1.0


func setup(game: Game) -> void:
	_game = game
	theme_type_variation = &"HudPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := UiUtil.vbox(3)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	_wave_label = _make_label()
	_wave_label.add_theme_font_size_override("font_size", 17)
	column.add_child(_wave_label)
	_enemies_label = _make_label()
	_enemies_label.theme_type_variation = &"DimLabel"
	column.add_child(_enemies_label)
	_gate_row = UiUtil.hbox(8)
	_gate_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_gate_row)
	_gate_label = _make_label()
	_gate_row.add_child(_gate_label)
	_gate_bar = ProgressBar.new()
	_gate_bar.custom_minimum_size = Vector2(90, 8)
	_gate_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_gate_bar.show_percentage = false
	_gate_bar.max_value = 1.0
	_gate_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gate_row.add_child(_gate_bar)
	# Творческий режим: позвать волну и включить/выключить волны совсем.
	_creative_row = UiUtil.hbox(6)
	column.add_child(_creative_row)
	_wave_button = UiUtil.button("THREAT_CALL_WAVE", func() -> void:
		_game.run.submit(Command.Kind.CREATIVE_WAVE)
		refresh())
	_wave_button.focus_mode = Control.FOCUS_NONE
	_wave_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_creative_row.add_child(_wave_button)
	_waves_toggle = CheckButton.new()
	_waves_toggle.text = "THREAT_WAVES_ON"
	_waves_toggle.focus_mode = Control.FOCUS_NONE
	_waves_toggle.mouse_filter = Control.MOUSE_FILTER_STOP
	_waves_toggle.toggled.connect(func(on: bool) -> void:
		_game.run.submit(Command.Kind.CREATIVE_THREAT, {"on": on})
		refresh())
	_creative_row.add_child(_waves_toggle)
	refresh()


func _process(delta: float) -> void:
	_gate_alert_timer = maxf(_gate_alert_timer - delta, 0.0)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = REFRESH
	refresh()


func refresh() -> void:
	var run := _game.run
	if run == null or run.planet == null:
		visible = false
		return
	var planet := run.planet
	var threat := planet.threat
	if planet != _tracked_world:
		_reset_tracking(planet)
	_creative_row.visible = run.creative
	if run.creative:
		mouse_filter = Control.MOUSE_FILTER_PASS
		_waves_toggle.set_pressed_no_signal(threat != null)
	visible = threat != null or run.creative
	_wave_label.visible = threat != null
	_enemies_label.visible = threat != null
	_gate_row.visible = threat != null
	if threat == null:
		return
	var tick := planet.simulation.tick
	var color := UiTheme.FG4
	if threat.is_continuous():
		_wave_label.text = tr("THREAT_CONTINUOUS") % threat.wave
		color = UiTheme.RED
	elif threat.is_spawning(tick):
		_wave_label.text = tr("THREAT_WAVE_ACTIVE") % threat.wave
		color = UiTheme.ORANGE
	else:
		var key := "THREAT_FIRST_WAVE" if threat.wave == 0 else "THREAT_NEXT_WAVE"
		var time := _format_time(threat.get_ticks_to_next_wave(tick))
		_wave_label.text = tr(key) % time if threat.wave == 0 else tr(key) % [threat.wave + 1, time]
		color = UiTheme.RED if threat.is_warning(tick) else UiTheme.YELLOW
	_wave_label.add_theme_color_override("font_color", color)
	_enemies_label.text = tr("THREAT_ENEMIES_KILLED") % [planet.enemies.count, planet.enemies.killed]
	_enemies_label.visible = planet.enemies.count > 0 or threat.wave > 0

	var gate := planet.gateway
	_gate_row.visible = gate != null and gate.is_damaged()
	if gate != null:
		var fraction := clampf(gate.health / gate.get_max_health(), 0.0, 1.0)
		_gate_label.text = tr("THREAT_GATEWAY") % [ceili(gate.health), roundi(gate.get_max_health())]
		_gate_label.add_theme_color_override("font_color", CombatOverlay.bar_color(fraction))
		_gate_bar.value = fraction
		_notify(threat, tick, gate)
	reset_size()


func _notify(threat: ThreatDirector, tick: int, gate: GatewayBuilding) -> void:
	if not threat.is_continuous() and threat.is_warning(tick) and _warned_wave < threat.wave + 1:
		_warned_wave = threat.wave + 1
		Events.toast(tr("TOAST_WAVE_WARNING") % [threat.wave + 1, ceili(threat.get_ticks_to_next_wave(tick) / float(GameConst.TICK_RATE))],
			Events.ToastKind.WARNING)
	if threat.wave > _started_wave:
		_started_wave = threat.wave
		if threat.is_continuous():
			if not _continuous_announced:
				_continuous_announced = true
				Events.toast(tr("TOAST_CONTINUOUS"), Events.ToastKind.WARNING)
		else:
			Events.toast(tr("TOAST_WAVE_STARTED") % threat.wave, Events.ToastKind.WARNING)
	if _last_gate_health >= 0.0 and gate.health < _last_gate_health and _gate_alert_timer <= 0.0:
		_gate_alert_timer = GATE_ALERT_COOLDOWN
		Events.toast(tr("TOAST_GATEWAY_ATTACKED"), Events.ToastKind.WARNING)
	_last_gate_health = gate.health


## Новая планета или загрузка: уже прошедшие события не объявляем.
func _reset_tracking(planet: GameWorld) -> void:
	_tracked_world = planet
	var threat := planet.threat
	var tick := planet.simulation.tick
	_started_wave = threat.wave if threat != null else 0
	_warned_wave = threat.wave + (1 if threat.is_warning(tick) else 0) if threat != null else 0
	_continuous_announced = threat != null and threat.is_continuous()
	_last_gate_health = planet.gateway.health if planet.gateway != null else -1.0
	_gate_alert_timer = 0.0


static func _format_time(ticks: int) -> String:
	var seconds := ceili(ticks / float(GameConst.TICK_RATE))
	return "%d:%02d" % [seconds / 60, seconds % 60]


func _make_label() -> Label:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _wave_label != null:
		refresh()
