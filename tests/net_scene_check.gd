extends Node
## Проверка настоящей игровой сцены в роли клиента: как сцена переживает снимок мира от хоста
## (вход в игру и починка после расхождения) и держится ли она с хостом в одном состоянии.
##
## Запуск: godot --headless --path D:/Mind res://tests/net_scene_check.tscn
##
## Зачем отдельная проверка. Логические тесты гоняют протокол без сцены, а ломалось именно
## в сцене: пересборка оставляла старые часы симуляции, и после первой же починки мир шагал
## дважды. Снаружи это выглядело как «клиента трясёт и он застревает», а ни один тест
## протокола этого не видел.
##
## Хост здесь шагает по настоящему времени, как в игре: в headless кадры идут сотнями в секунду,
## и если привязать хоста к кадрам, «отставание клиента» перестанет что-либо значить.

## Сколько ждём событий, которым нужно время (контрольные суммы идут раз в 5 секунд).
const WAIT_SECONDS := 40.0
## Сколько секунд идёт длинный прогон с волнами.
const SOAK_SECONDS := 25.0

var _checks: int = 0
var _fails: int = 0
var _host: NetSession
var _host_run: Run
var _game: Game
var _host_time: float = 0.0
var _last_usec: int = 0
## Отпечатки хоста по тикам: клиент идёт позади, поэтому сравнивать надо один и тот же тик.
var _host_parts: Dictionary[int, PackedInt64Array] = {}
var _record: bool = false


func _expect(ok: bool, text: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print(("scene OK   " if ok else "scene FAIL ") + text)


func _ready() -> void:
	NetLog.echo = false
	Registry.ensure_loaded()
	ArtRegistry.ensure_built()
	_run()


## Сколько узлов часов живёт в игровой сцене (должны быть ровно одни).
func _clocks() -> int:
	var found := 0
	for child in _game.get_children():
		if child is SimClock:
			found += 1
	return found


## Кадр: хост отсчитывает свои тики по настоящему времени, клиента двигают часы внутри сцены.
func _frame(host_steps: bool = true) -> void:
	await get_tree().process_frame
	var now := Time.get_ticks_usec()
	var delta := float(now - _last_usec) / 1000000.0
	_last_usec = now
	_host_time += minf(delta, 0.25)
	while _host_time >= GameConst.TICK_DT:
		_host_time -= GameConst.TICK_DT
		_host.poll()
		if host_steps and _host.can_step():
			_host_run.step()
			_host.after_step()
			if _record:
				_host_parts[_host_run.get_tick()] = _host_run.state_parts()
	_host.poll()


func _frames(count: int) -> void:
	for i in count:
		await _frame()


## Крутить кадры, пока условие не выполнится (или не кончится время). Возвращает, сколько прошло.
func _wait_until(check: Callable, host_steps: bool = true) -> float:
	var started := Time.get_ticks_msec()
	while not bool(check.call()):
		await _frame(host_steps)
		if Time.get_ticks_msec() - started > WAIT_SECONDS * 1000.0:
			break
	return (Time.get_ticks_msec() - started) / 1000.0


func _run() -> void:
	# Настоящая сгенерированная планета в творческом режиме: так можно звать волны руками
	# и гонять по сети врагов — самое опасное место для детерминизма.
	_host_run = Run.create_new(2024, true)
	var host_transport := LoopbackTransport.make_host()
	_host = NetSession.new()
	_expect(_host.host_run(_host_run, 0, host_transport), "хост открыл игру")
	for i in 20:
		_host.poll()
		if _host.can_step():
			_host_run.step()
			_host.after_step()

	# Клиент — это настоящая сессия игры, её же читает игровая сцена.
	var client_transport := LoopbackTransport.connect_client(host_transport, 2)
	_expect(Session.net.join_run("", 0, "Напарник", client_transport), "клиент начал подключение")
	for i in 40:
		_host.poll()
		Session.net.poll()
		if Session.net.run != null:
			break
	_expect(Session.net.run != null, "клиенту пришёл снимок мира")
	if Session.net.run == null:
		_finish()
		return

	_game = load("res://core/game.tscn").instantiate() as Game
	add_child(_game)
	_last_usec = Time.get_ticks_usec()
	await _frames(5)
	_expect(_game.run == Session.net.run, "сцена взяла забег из сети")
	_expect(_clocks() == 1, "в сцене одни часы (%d)" % _clocks())

	# Игрок клиента появляется командой уже после снимка — дождёмся его.
	await _wait_until(func() -> bool: return _game.run.local_player != 1)
	var mine := _game.run.get_player(_game.run.local_player)
	_expect(mine != null and mine.id != 1, "клиент играет за себя (игрок %d)" % _game.run.local_player)
	_expect(mine != null and _game.world.drone == mine.drone, "интерфейс смотрит на дрона клиента")

	await _soak()
	await _repair()
	_finish()


## Длинный прогон: обе стороны играют, хост зовёт волны, клиент отдаёт свои команды.
## Расхождений быть не должно ни одного — любое здесь означает недетерминизм в симуляции.
func _soak() -> void:
	var started := Time.get_ticks_msec()
	_record = true
	_host_run.submit(Command.Kind.CREATIVE_THREAT, {"on": true})
	var waves := 0
	var next_wave := 4.0
	# Камера и дрон обязаны брать одно и то же упреждение в одном кадре: иначе дрон дрожит
	# относительно мира там, где упреждение меняется, — в начале и конце движения.
	var camera_gap := 0.0
	while Time.get_ticks_msec() - started < SOAK_SECONDS * 1000.0:
		await _frame()
		var drone := _game.run.drone
		if drone != null and not drone.dead:
			var drawn := drone.get_draw_position(_game.clock.alpha) + _game.drone_view.local_offset()
			camera_gap = maxf(camera_gap, _game.camera.position.distance_to(drawn))
		var elapsed := float(Time.get_ticks_msec() - started) / 1000.0
		if elapsed >= next_wave:
			next_wave += 5.0
			waves += 1
			_host_run.submit(Command.Kind.CREATIVE_WAVE)
			_game.run.submit(Command.Kind.MOVE, {"dir": Vector2.RIGHT if waves % 2 == 0 else Vector2.LEFT})
			# Творческая выдача предметов клиентом — раньше именно она ломала игру каждые 5 секунд.
			_game.run.submit(Command.Kind.CREATIVE_GIVE, {"item": Registry.get_building(&"conveyor").item.index, "count": 10})
	_expect(camera_gap < 0.01, "камера всегда там же, где нарисован дрон (расхождение %.2f px)" % camera_gap)
	_expect(waves >= 3, "за прогон позвано волн: %d" % waves)
	_expect(_host_run.planet.enemies.spawned > 0, "враги появились (%d)" % _host_run.planet.enemies.spawned)
	_expect(Session.net.repairs == 0, "за %.0f с игры ни одной починки снимком (%d)"
		% [SOAK_SECONDS, Session.net.repairs])
	_expect(_host.checksums_compared >= 3, "отпечатки состояния реально сверялись (%d раз)"
		% _host.checksums_compared)

	# Сверка состояний на одном и том же тике: клиент замирает (blocked — пауза интерфейса,
	# она не уходит в сеть), и его отпечаток сравнивается с запомненным отпечатком хоста
	# на том же тике. Догонять никого не надо — сравниваются одинаковые моменты.
	print("scene ..   отставание клиента %d тиков, запас %d из %.1f, темп x%.2f"
		% [_host_run.get_tick() - _game.run.get_tick(), Session.net.ready_ticks(),
		Session.net.buffer_target(), _game.clock.get_time_scale()])
	_game.clock.blocked = true
	await _frames(2)
	var target := _game.run.get_tick()
	# Клиент считает запланированные тики и может быть на тик впереди исполнения хоста —
	# доводим хоста до его тика.
	var guard := 0
	while not _host_parts.has(target) and guard < 300:
		guard += 1
		_host.poll()
		if _host.can_step():
			_host_run.step()
			_host.after_step()
			_host_parts[_host_run.get_tick()] = _host_run.state_parts()
	_expect(_host_parts.has(target), "есть отпечаток хоста на тике клиента (%d)" % target)
	if not _host_parts.has(target):
		_game.clock.blocked = false
		return
	var mine := _game.run.state_parts()
	var theirs: PackedInt64Array = _host_parts[target]
	var differs := -1
	for i in mini(mine.size(), theirs.size()):
		if mine[i] != theirs[i]:
			differs = i
			break
	_expect(differs < 0, "состояния совпали после прогона с волнами%s" % ("" if differs < 0
		else " — разошлось: " + String(Run.STATE_PART_NAMES[differs])))
	_game.clock.blocked = false


## Расхождение и починка: сцена пересобирается, и это не должно ничего ломать.
func _repair() -> void:
	var repaired := [false]
	Session.net.run_replaced.connect(func(_fresh: Run) -> void: repaired[0] = true)
	# Ломаем мир клиента мимо команд — так выглядит любое расхождение. Портим инвентарь,
	# а не положение: дрона могут сбить враги, и respawn вернул бы его на место у обоих.
	_game.run.players[0].drone.inventory.add(Registry.get_item(&"stone").index, 7)
	var waited := await _wait_until(func() -> bool: return repaired[0])
	_expect(repaired[0], "хост починил клиента снимком за %.1f с" % waited)
	_expect(_host.last_desync.begins_with("игроки"), "хост назвал разошедшуюся часть: %s" % _host.last_desync)

	# Главное: после пересборки сцены часы остались одни, и интерфейс смотрит на своего дрона.
	_expect(_clocks() == 1, "после починки в сцене по-прежнему одни часы (%d)" % _clocks())
	var after := _game.run.get_player(_game.run.local_player)
	_expect(after != null and after.id != 1, "после починки клиент играет за себя (игрок %d)"
		% _game.run.local_player)
	_expect(after != null and _game.world.drone == after.drone,
		"после починки интерфейс смотрит на дрона клиента, а не хоста")
	_expect(_game.drone_controller != null and _game.drone_controller.get("_drone") == _game.run.drone,
		"управление привязано к своему дрону")

	# И игра продолжает идти: клиент держится рядом с хостом.
	await _frames(240)
	var gap := _host_run.get_tick() - _game.run.get_tick()
	# Клиент считает уже запланированные тики, поэтому на тик-другой он законно впереди
	# исполнения хоста — важно, что разрыв мал в обе стороны.
	_expect(absi(gap) <= NetProtocol.CLIENT_BUFFER + 3,
		"после починки клиент идёт вровень с хостом (разрыв %d тиков)" % gap)
	_expect(Session.net.repairs == 1, "починка понадобилась ровно одна (%d)" % Session.net.repairs)


func _finish() -> void:
	print("scene: провалов %d из %d" % [_fails, _checks])
	if _game != null:
		_game.queue_free()
	Session.net.close()
	if _host != null:
		_host.close()
	if _host_run != null:
		_host_run.dispose()
	get_tree().quit(1 if _fails > 0 else 0)
