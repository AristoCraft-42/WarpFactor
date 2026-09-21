class_name NetSession
extends RefCounted
## Совместная игра по сети: детерминированный lockstep.
##
## Как это работает. Все действия игроков — команды (core/command.gd). В сетевой игре команда
## не применяется сразу: она уходит хосту, тот собирает команды всех участников и рассылает
## окончательный список на конкретный тик (пакет TICK). Каждый участник применяет один и тот же
## список в одном и том же тике и получает одну и ту же симуляцию — по сети ходят только команды,
## а не мир, поэтому трафик не зависит от размера фабрики.
##
## Тик T планируется заранее, за INPUT_DELAY тиков: это и есть задержка ввода, за неё пакет
## успевает дойти. Клиент не считает тик, пока не получил его список команд (confirmed_tick).
##
## Вход в игру: хост шлёт снимок забега (то же сохранение) и все уже запланированные тики после него.
## Расхождение ловится контрольными суммами состояния; хост чинит его свежим снимком.
##
## Ход времени у клиента. Темп задаёт хост, поэтому часы клиента подстраиваются под него:
## клиент держит небольшой запас подтверждённых тиков (CLIENT_BUFFER) и слегка ускоряет или
## замедляет своё время, чтобы запас держался около этого значения (time_scale). Без этого клиент
## считает тик ровно в момент прихода пакета — и любая неровность сети видна как рывок, а каждая
## просадка кадров теряется навсегда, потому что часы идут по настоящему времени.

enum Role { OFFLINE, HOST, CLIENT }

## Состав участников или роль изменились.
signal state_changed
## Событие для интерфейса: кто-то вошёл, вышел, расхождение, ошибка.
signal notice(text: String)
## Клиенту пришёл снимок мира: забег нужно заменить этим.
signal run_replaced(run: Run)
## Пришло общее состояние времени: пауза и скорость.
signal time_state(paused: bool, speed_index: int)

## Сколько последних запланированных тиков храним (для входящих в игру).
const HISTORY := 600

var role: Role = Role.OFFLINE
var transport: NetTransport
var run: Run
var input_delay: int = NetProtocol.INPUT_DELAY
## До какого тика есть окончательные списки команд.
var confirmed_tick: int = -1
var last_error: String = ""
## Имя локального игрока (уходит хосту при входе).
var local_name: String = ""

## Хост: команды, которые войдут в следующий планируемый тик.
var _pending: Array[Command] = []
## Хост: peer_id → {"player": int, "name": String, "ready": bool}.
var _peers: Dictionary[int, Dictionary] = {}
## Хост: разосланные списки команд по тикам (для тех, кто входит в игру).
var _planned: Dictionary[int, Array] = {}
var _next_plan_tick: int = 0
var _next_player_id: int = 1
## Хост: свои отпечатки состояния по тикам, чтобы сверять с клиентскими.
var _own_checksums: Dictionary[int, PackedInt64Array] = {}
## Сколько раз мир чинился снимком и что разошлось в последний раз (для отладки и отчёта игрока).
var repairs: int = 0
var last_desync: String = ""
## Сколько сверок отпечатков состояния хост успел сделать (0 при игре — сверка не работает).
var checksums_compared: int = 0
## Хост: суммы клиентов, пришедшие раньше, чем хост сам дошёл до этого тика.
## Клиент считает уже запланированные тики и потому идёт впереди исполнения хоста — без этой
## очереди сверка почти никогда не срабатывала бы, и расхождения оставались бы незамеченными.
var _late_checksums: Array[Dictionary] = []

## Клиент: id игрока, за которого играем, и ожидание снимка.
var _local_player: int = 0
var _waiting_snapshot: bool = false
## Клиент: когда началось подключение (мс) — чтобы не ждать мир хоста вечно.
var _join_started_msec: int = 0
## Журнал: когда последний раз писали сводку состояния (мс).
var _last_report_msec: int = 0
## Журнал: сколько команд отправлено, принято хостом и отвергнуто им — с прошлой сводки.
var _log_sent: int = 0
var _log_accepted: int = 0
var _log_rejected: int = 0
var _log_ticks_in: int = 0
## Клиент: на каком тике последний раз просили снимок (чтобы не просить его каждый кадр).
var _resync_asked: int = -1000000
## Клиент: пришедшие списки команд, которые ещё нельзя подтвердить — ждут предыдущих тиков.
var _received_ticks: Dictionary[int, bool] = {}
## Клиент: сколько опросов сети держится дырка в подтверждении (0 — дырки нет).
var _gap_polls: int = 0
## Клиент: сколько опросов сети своего игрока всё ещё нет в забеге (0 — всё в порядке).
var _no_self_polls: int = 0
## Клиент: списки команд, пришедшие раньше снимка мира. Порядок доставки транспорты
## не гарантируют, а выбросить их нельзя — без них в подтверждении будет дырка.
var _early_ticks: Array[Dictionary] = []
## Сколько тиков на самом деле проходит от отдачи команды до её применения.
##
## Мерится по своим же командам, а не считается по формуле: в задержку входит и планирование
## хоста (команда попадает в первый ещё не разосланный тик, а это input_delay + 1), и дорога
## по сети, и собственное отставание клиента. Упреждение отрисовки обязано знать её точно —
## иначе дрон на экране трогается, упирается в край упреждения и ждёт, а это и есть рывок.
var _measured_delay: float = float(NetProtocol.INPUT_DELAY) + 1.0
## Свои отданные команды: номер → тик, в котором их отдали.
var _sent_at: Dictionary[int, int] = {}
## Клиент: целевой запас тиков. Растёт, когда клиент упирается в ожидание (связь неровная),
## и медленно оседает обратно — так игра сама подстраивается под качество канала.
var _buffer_target: float = float(NetProtocol.CLIENT_BUFFER)


func is_networked() -> bool:
	return role != Role.OFFLINE


func is_host() -> bool:
	return role == Role.HOST


## Игроки, которые сейчас на связи (id игроков забега).
func online_players() -> PackedInt32Array:
	var ids := PackedInt32Array()
	if role == Role.HOST:
		ids.append(1)
		for peer in _peers:
			ids.append(int((_peers[peer] as Dictionary).get("player", 0)))
	elif role == Role.CLIENT:
		ids.append(_local_player)
	return ids


# --- Запуск и остановка ---

## Открыть текущий забег для сети. false — порт занят.
func host_run(p_run: Run, port: int, p_transport: NetTransport = null) -> bool:
	close()
	transport = p_transport if p_transport != null else EnetTransport.new()
	if not transport.host(port):
		last_error = "port"
		NetLog.write("сессия", "хост: не удалось открыть игру (%s, порт %d)" % [transport.kind_name(), port])
		transport = null
		return false
	NetLog.write("сессия", "хост: игра открыта (%s), тик %d, игроков %d" % [transport.kind_name(), p_run.get_tick(), p_run.players.size()])
	role = Role.HOST
	run = p_run
	_attach_run()
	_next_plan_tick = run.get_tick()
	_next_player_id = maxi(run.next_player_id, 2)
	confirmed_tick = run.get_tick() - 1
	_connect_transport()
	state_changed.emit()
	return true


## Подключиться к хосту. Забег придёт снимком (сигнал run_replaced).
func join_run(address: String, port: int, name: String, p_transport: NetTransport = null) -> bool:
	close()
	transport = p_transport if p_transport != null else EnetTransport.new()
	local_name = name
	NetLog.write("сессия", "клиент: подключаюсь к %s (%s), имя «%s»" % [address, transport.kind_name(), name])
	if not transport.join(address, port):
		last_error = "connect"
		NetLog.write("сессия", "клиент: транспорт не начал подключение")
		transport = null
		return false
	role = Role.CLIENT
	_waiting_snapshot = true
	_join_started_msec = Time.get_ticks_msec()
	_connect_transport()
	state_changed.emit()
	return true


func close() -> void:
	if role != Role.OFFLINE:
		NetLog.write("сессия", "закрываю сессию (роль %s, мир %s, ошибка «%s»)" % [Role.keys()[role], "есть" if run != null else "нет", last_error])
	# Сначала гасим роль и ссылку: закрытие может прийти повторно из обработчика отключения.
	var closing := transport
	transport = null
	var was_role := role
	role = Role.OFFLINE
	if closing != null:
		if was_role != Role.OFFLINE:
			closing.broadcast(NetProtocol.pack(NetProtocol.Kind.BYE))
		closing.close()
	if run != null:
		run.command_router = Callable()
	run = null
	_pending.clear()
	_received_ticks.clear()
	_early_ticks.clear()
	_sent_at.clear()
	_measured_delay = float(NetProtocol.INPUT_DELAY) + 1.0
	_gap_polls = 0
	_no_self_polls = 0
	_peers.clear()
	_planned.clear()
	_own_checksums.clear()
	_late_checksums.clear()
	confirmed_tick = -1
	_local_player = 0
	_waiting_snapshot = false
	state_changed.emit()


## Забег заменён (вход в игру, телепорт с пересозданием и т. п.).
func set_run(p_run: Run) -> void:
	if run != null:
		run.command_router = Callable()
	run = p_run
	_attach_run()


func _attach_run() -> void:
	if run != null:
		run.command_router = _route_command


func _connect_transport() -> void:
	transport.peer_connected.connect(_on_peer_connected)
	transport.peer_disconnected.connect(_on_peer_disconnected)
	transport.packet_received.connect(_on_packet)


# --- Ход времени ---

## Можно ли считать очередной тик: клиент ждёт список команд от хоста.
func can_step() -> bool:
	if role == Role.OFFLINE:
		return true
	if run == null or _waiting_snapshot:
		return false
	return run.get_tick() <= confirmed_tick


## Сколько тиков клиент может посчитать прямо сейчас: это и есть его запас.
## Ноль — запас проеден и клиент будет ждать пакета; большое число — клиент отстал.
func ready_ticks() -> int:
	if role != Role.CLIENT or run == null or _waiting_snapshot:
		return 0
	return confirmed_tick - run.get_tick() + 1


## Во сколько раз быстрее идти времени клиента, чтобы запас держался около CLIENT_BUFFER.
## Хост всегда 1.0 — он задаёт темп. Подстройка мягкая (несколько процентов на тик запаса),
## поэтому в обычной игре скорость на глаз не меняется; большие значения включаются только
## когда клиент сильно отстал и его надо догнать.
func time_scale() -> float:
	if role != Role.CLIENT or run == null or _waiting_snapshot:
		return 1.0
	# Зовётся раз в кадр из часов — здесь же подстраивается и сам запас.
	var ready := ready_ticks()
	if ready <= 0:
		_buffer_target = minf(_buffer_target + NetProtocol.BUFFER_GROW, NetProtocol.CLIENT_BUFFER_MAX)
	else:
		_buffer_target = maxf(_buffer_target - NetProtocol.BUFFER_DECAY, float(NetProtocol.CLIENT_BUFFER))
	var slack := float(ready) - _buffer_target
	return clampf(1.0 + slack * NetProtocol.SCALE_PER_TICK,
		NetProtocol.MIN_TIME_SCALE, NetProtocol.MAX_TIME_SCALE)


## Текущий целевой запас тиков (для отладки).
func buffer_target() -> float:
	return _buffer_target


## Через сколько тиков применится команда, отданная прямо сейчас. Нужно только отрисовке:
## свой дрон рисуется с упреждением ровно на это время.
func predicted_delay() -> int:
	return maxi(int(round(_measured_delay)), 1)


## Заметить, за сколько тиков наша команда дошла до применения.
func _note_delay(cmd: Command, at_tick: int) -> void:
	if run == null or cmd.player != run.local_player or not _sent_at.has(cmd.seq):
		return
	var measured := float(at_tick - _sent_at[cmd.seq])
	_sent_at.erase(cmd.seq)
	if measured < 0.0 or measured > 120.0:
		return
	_measured_delay = lerpf(_measured_delay, measured, 0.3)


## За какого игрока мы должны играть (у клиента — выданный хостом id, у хоста — 1).
## Если в забеге local_player другой, интерфейс смотрит на чужого дрона и играть нельзя.
func local_player_id() -> int:
	return _local_player if role == Role.CLIENT else 1


## Клиент «застрял»: команды уже не успевают применяться, потому что он далеко позади.
## Нужно только отладке и сообщению игроку.
func behind_ticks() -> int:
	return maxi(ready_ticks() - NetProtocol.CLIENT_BUFFER, 0)


## Зовётся каждый кадр до шагов симуляции: приём пакетов и планирование тиков хостом.
func poll() -> void:
	if transport == null:
		return
	transport.poll()
	if transport != null and Time.get_ticks_msec() - _last_report_msec > 5000:
		_last_report_msec = Time.get_ticks_msec()
		_report()
	if role == Role.CLIENT and run == null:
		# Вход так и не завершился. Висящая попытка хуже закрытой: она считается «сетевой игрой»,
		# и следующая своя игра подключилась бы к чужому хосту вместо того, чтобы идти самой.
		if transport != null and Time.get_ticks_msec() - _join_started_msec > NetProtocol.JOIN_TIMEOUT_MS:
			last_error = "timeout"
			NetLog.write("сессия", "клиент: за %d с мир хоста так и не пришёл, сдаюсь" % (NetProtocol.JOIN_TIMEOUT_MS / 1000))
			close()
			notice.emit(tr("NET_JOIN_TIMEOUT"))
		return
	if role == Role.CLIENT:
		_ensure_local_player()
		_ask_resync_if_lost()
	elif role == Role.HOST and run != null:
		_plan_ticks()


## Сводка состояния в журнал: всё, что нужно, чтобы понять «почему стоит» по одной строке.
func _report() -> void:
	var line := "сводка: %s" % Role.keys()[role]
	if run == null:
		line += ", мира нет (жду снимок %.0f с)" % (float(Time.get_ticks_msec() - _join_started_msec) / 1000.0)
	else:
		line += ", тик %d, подтверждён %d, запас %d (цель %.1f), темп x%.2f, задержка %d" % [
			run.get_tick(), confirmed_tick, ready_ticks(), _buffer_target, time_scale(), predicted_delay()]
		line += ", я — игрок %d (ожидаю %d), игроков %d" % [run.local_player, local_player_id(), run.players.size()]
		var me := run.get_player(run.local_player)
		if me != null and me.drone != null:
			var d := me.drone
			line += ", дрон (%.0f, %.0f) %s ход %s ввод %s%s" % [d.position.x, d.position.y,
				"в базе" if d.world == run.base else "на планете", str(d.move_input), str(d.local_input),
				" СБИТ" if d.dead else ""]
		if role == Role.CLIENT:
			line += ", дырка в тиках: %d, ждут подтверждения %d, получено списков %d" % [
				_gap_polls, _received_ticks.size(), _log_ticks_in]
		else:
			line += ", участников %d, команд принято %d, отвергнуто %d, запланировано до %d" % [
				_peers.size(), _log_accepted, _log_rejected, _next_plan_tick - 1]
		line += ", отправлено команд %d, починок %d" % [_log_sent, repairs]
		if not last_desync.is_empty():
			line += ", последнее расхождение: " + last_desync
	var extra := transport.debug_stats() if transport != null else ""
	if not extra.is_empty():
		line += " | " + extra
	NetLog.write("сессия", line)
	_log_sent = 0
	_log_accepted = 0
	_log_rejected = 0
	_log_ticks_in = 0


## Клиент отстал так, что догонять ускорением пришлось бы минуту (свернули окно, просадка кадров,
## долгая загрузка). Снимок мира дешевле: просим его и продолжаем с настоящего момента.
func _ask_resync_if_lost() -> void:
	if run == null or _waiting_snapshot or transport == null:
		return
	# Дырка в списках команд: пропущенный тик уже не придёт, а без него дальше идти нельзя.
	if not _received_ticks.is_empty():
		_gap_polls += 1
		if _gap_polls > NetProtocol.GAP_TIMEOUT_POLLS:
			_gap_polls = 0
			NetLog.write("сессия", "клиент: дырка в тиках (подтверждён %d, есть %s) — прошу снимок" % [confirmed_tick, str(_received_ticks.keys().slice(0, 6))])
			notice.emit(tr("NET_LOST_TICK"))
			_request_resync()
			return
	else:
		_gap_polls = 0
	if ready_ticks() <= NetProtocol.RESYNC_BEHIND:
		return
	_request_resync()


## Попросить у хоста свежий снимок мира. Чаще, чем раз в RESYNC_BEHIND тиков, не просим:
## снимок дорогой, а пока он идёт, забег продолжает считаться.
func _request_resync() -> void:
	if transport == null or run == null:
		return
	if run.get_tick() - _resync_asked < NetProtocol.RESYNC_BEHIND:
		return
	_resync_asked = run.get_tick()
	NetLog.write("сессия", "клиент: прошу снимок у хоста (тик %d, запас %d)" % [run.get_tick(), ready_ticks()])
	transport.send(NetTransport.HOST_ID, NetProtocol.pack(NetProtocol.Kind.RESYNC_REQUEST))


## Игрок клиента появляется в мире командой уже после снимка — как только он есть, играем за него.
func _ensure_local_player() -> void:
	if run == null or _local_player <= 0:
		return
	if run.get_player(_local_player) != null:
		_no_self_polls = 0
		if run.local_player != _local_player:
			NetLog.write("сессия", "клиент: теперь играю за своего игрока %d (был %d)" % [_local_player, run.local_player])
			run.set_local_player(_local_player)
		return
	# Своего игрока в забеге нет: команда PLAYER_ADD не дошла. Играть в таком виде нельзя —
	# интерфейс показывает чужого дрона, а команды хост отвергает (они не от нашего игрока).
	# Ждать бесполезно, команда уже не придёт: просим свежий снимок, в нём игрок будет.
	_no_self_polls += 1
	if _no_self_polls > NetProtocol.SELF_TIMEOUT_POLLS:
		_no_self_polls = 0
		NetLog.write("сессия", "клиент: своего игрока %d в мире нет — прошу снимок" % _local_player)
		_request_resync()


## Хост планирует тики вперёд: собирает накопленные команды и рассылает окончательный список.
func _plan_ticks() -> void:
	var horizon := run.get_tick() + input_delay
	while _next_plan_tick <= horizon:
		var batch := _pending
		_pending = []
		var raw := NetProtocol.commands_to_array(batch)
		_planned[_next_plan_tick] = raw
		_planned.erase(_next_plan_tick - HISTORY)
		if not batch.is_empty():
			for cmd in batch:
				_note_delay(cmd, _next_plan_tick)
				run.commands.submit_at(cmd, _next_plan_tick)
		transport.broadcast(NetProtocol.pack(NetProtocol.Kind.TICK, {"t": _next_plan_tick, "c": raw}))
		confirmed_tick = _next_plan_tick
		_next_plan_tick += 1


## Зовётся после каждого тика: контрольные суммы состояния.
func after_step() -> void:
	if role == Role.OFFLINE or run == null:
		return
	var tick := run.get_tick()
	if tick % NetProtocol.CHECKSUM_EVERY != 0:
		return
	var parts := run.state_parts()
	if role == Role.HOST:
		_own_checksums[tick] = parts
		_own_checksums.erase(tick - NetProtocol.CHECKSUM_EVERY * 8)
		_flush_late_checksums(tick)
	else:
		transport.send(NetTransport.HOST_ID, NetProtocol.pack(NetProtocol.Kind.CHECKSUM,
			{"t": tick, "p": parts}))


# --- Команды ---

## Куда уходит команда игрока вместо прямой очереди забега.
func _route_command(cmd: Command) -> void:
	# Сравниваем с забегом, а не с выданным id: в творческом режиме хост может играть
	# за любого из своих игроков.
	if run != null and cmd.player == run.local_player:
		if _sent_at.size() > 64:
			_sent_at.clear()
		_sent_at[cmd.seq] = run.get_tick()
	_log_sent += 1
	if cmd.kind != Command.Kind.MOVE or role == Role.CLIENT:
		NetLog.write("сессия", "моя команда %s #%d игрока %d на тике %d%s" % [NetLog.kind_name(cmd.kind), cmd.seq, cmd.player, run.get_tick() if run != null else -1, _args_brief(cmd)])
	if role == Role.HOST:
		_pending.append(cmd)
	elif role == Role.CLIENT:
		transport.send(NetTransport.HOST_ID, NetProtocol.pack(NetProtocol.Kind.COMMANDS,
			{"c": NetProtocol.commands_to_array([cmd])}))


## Коротко об аргументах команды для журнала.
func _args_brief(cmd: Command) -> String:
	match cmd.kind:
		Command.Kind.MOVE:
			return " ход %s" % str(cmd.args.get("dir", Vector2.ZERO))
		Command.Kind.BUILD:
			var places: Array = cmd.args.get("places", [])
			return " построек %d (%s)" % [places.size(), String((places[0] as Dictionary).get("def", "")) if not places.is_empty() else ""]
		Command.Kind.CREATIVE_GIVE:
			return " предмет %d × %d" % [int(cmd.args.get("item", -1)), int(cmd.args.get("count", 0))]
	return ""


## Пауза и скорость — общие для всех, но идут мимо тиков: на паузе тики не считаются,
## и команда в очереди просто никогда бы не применилась.
func send_time(paused: bool, speed_index: int) -> void:
	if role == Role.OFFLINE or transport == null:
		return
	var packet := NetProtocol.pack(NetProtocol.Kind.TIME, {"p": paused, "s": speed_index})
	NetLog.write("сессия", "время: пауза %s, скорость %d — рассылаю" % [paused, speed_index])
	if role == Role.HOST:
		transport.broadcast(packet)
	else:
		transport.send(NetTransport.HOST_ID, packet)


# --- Приём ---

func _on_peer_connected(peer_id: int) -> void:
	NetLog.write("сессия", "на связи участник %d (%s)" % [peer_id, "хост — шлю HELLO" if role == Role.CLIENT else "жду HELLO"])
	if role == Role.CLIENT:
		transport.send(NetTransport.HOST_ID, NetProtocol.pack(NetProtocol.Kind.HELLO,
			{"v": NetProtocol.VERSION, "n": local_name}))


func _on_peer_disconnected(peer_id: int) -> void:
	NetLog.write("сессия", "участник %d отключился" % peer_id)
	var steam := transport as SteamTransport
	if steam != null and steam.last_end_reason == SteamTransport.END_RENDEZVOUS:
		notice.emit(tr("NET_RENDEZVOUS_FAILED"))
	if role == Role.CLIENT:
		notice.emit(tr("NET_LOST_HOST"))
		close()
		return
	if not _peers.has(peer_id):
		return
	var info: Dictionary = _peers[peer_id]
	var player_id := int(info.get("player", 0))
	_peers.erase(peer_id)
	# Дрон вышедшего остаётся стоять: командой останавливаем его, чтобы он не улетел у всех.
	_pending.append(_make_command(Command.Kind.MOVE, player_id, {"dir": Vector2.ZERO}))
	_pending.append(_make_command(Command.Kind.MINE, player_id, {"tile": Drone.NO_TILE}))
	notice.emit(tr("NET_PLAYER_LEFT") % String(info.get("name", "")))
	state_changed.emit()


func _on_packet(peer_id: int, data: PackedByteArray) -> void:
	var message := NetProtocol.unpack(data)
	if message.is_empty():
		NetLog.write("сессия", "пакет от %d не разобрался (%d байт) — выброшен" % [peer_id, data.size()])
		return
	var kind := NetProtocol.kind_of(message)
	if kind != NetProtocol.Kind.TICK and kind != NetProtocol.Kind.COMMANDS and kind != NetProtocol.Kind.CHECKSUM:
		NetLog.write("сессия", "пришёл %s от %d, %d байт" % [NetProtocol.Kind.keys()[kind] if kind >= 0 and kind < NetProtocol.Kind.size() else str(kind), peer_id, data.size()])
	match kind:
		NetProtocol.Kind.HELLO:
			_handle_hello(peer_id, message)
		NetProtocol.Kind.WELCOME:
			_handle_welcome(message)
		NetProtocol.Kind.REJECT:
			last_error = String(message.get("r", ""))
			NetLog.write("сессия", "хост отказал во входе: %s" % last_error)
			notice.emit(tr("NET_REJECTED"))
			close()
		NetProtocol.Kind.COMMANDS:
			if role == Role.HOST:
				for cmd in NetProtocol.commands_from_array(message.get("c", [])):
					var command := cmd as Command
					var expected := int((_peers.get(peer_id, {}) as Dictionary).get("player", -1))
					# Игрок может отдавать команды только за себя.
					if command.player == expected:
						_pending.append(command)
						_log_accepted += 1
						NetLog.write("сессия", "команда участника %d: %s #%d игрока %d, пойдёт на тик %d%s" % [peer_id, NetLog.kind_name(command.kind), command.seq, command.player, _next_plan_tick, _args_brief(command)])
					else:
						_log_rejected += 1
						NetLog.write("сессия", "ОТВЕРГНУТА команда участника %d: %s от игрока %d, а ему выдан игрок %d" % [peer_id, NetLog.kind_name(command.kind), command.player, expected])
		NetProtocol.Kind.TICK:
			_handle_tick(message)
		NetProtocol.Kind.CHECKSUM:
			_handle_checksum(peer_id, message)
		NetProtocol.Kind.RESYNC:
			_handle_resync(message)
		NetProtocol.Kind.RESYNC_REQUEST:
			if role == Role.HOST and _peers.has(peer_id):
				NetLog.write("сессия", "участник %d просит снимок" % peer_id)
				_send_full_state(peer_id, NetProtocol.Kind.RESYNC, {"r": "behind"})
		NetProtocol.Kind.TIME:
			var paused := bool(message.get("p", false))
			var speed := int(message.get("s", 0))
			if role == Role.HOST:
				# Хост пересказывает остальным, чтобы время было общим.
				transport.broadcast(NetProtocol.pack(NetProtocol.Kind.TIME, {"p": paused, "s": speed}))
			NetLog.write("сессия", "время от участника %d: пауза %s, скорость %d" % [peer_id, paused, speed])
			time_state.emit(paused, speed)
		NetProtocol.Kind.BYE:
			NetLog.write("сессия", "участник %d попрощался" % peer_id)
			if role == Role.HOST:
				_on_peer_disconnected(peer_id)
			else:
				notice.emit(tr("NET_LOST_HOST"))
				close()


## Хост: новый клиент просится в игру — отвечаем снимком и добавляем ему игрока командой.
func _handle_hello(peer_id: int, message: Dictionary) -> void:
	if role != Role.HOST or run == null:
		return
	NetLog.write("сессия", "HELLO от участника %d: «%s», версия %d (у меня %d)" % [peer_id, String(message.get("n", "")), int(message.get("v", -1)), NetProtocol.VERSION])
	if int(message.get("v", -1)) != NetProtocol.VERSION:
		NetLog.write("сессия", "отказ участнику %d: другая версия" % peer_id)
		transport.send(peer_id, NetProtocol.pack(NetProtocol.Kind.REJECT, {"r": "version"}))
		return
	if _peers.size() + 1 >= NetProtocol.MAX_PLAYERS:
		transport.send(peer_id, NetProtocol.pack(NetProtocol.Kind.REJECT, {"r": "full"}))
		return
	var name := String(message.get("n", ""))
	# Тот же игрок вернулся — занимает своё тело со всеми вещами.
	var player_id := _find_free_player(name)
	if player_id == 0:
		player_id = _next_player_id
		_next_player_id += 1
		_pending.append(_make_command(Command.Kind.PLAYER_ADD, 1, {"name": name, "id": player_id}))
	_peers[peer_id] = {"player": player_id, "name": name}
	NetLog.write("сессия", "участник %d «%s» получает игрока %d (%s)" % [peer_id, name, player_id, "новый" if run.get_player(player_id) == null else "вернулся в своё тело"])
	_send_full_state(peer_id, NetProtocol.Kind.WELCOME, {"p": player_id, "d": input_delay})
	notice.emit(tr("NET_PLAYER_JOINED") % name)
	state_changed.emit()


## Игрок с таким именем есть в забеге и сейчас не на связи — пустим его в своё тело.
func _find_free_player(name: String) -> int:
	if name.is_empty():
		return 0
	var busy := PackedInt32Array()
	for peer in _peers:
		busy.append(int((_peers[peer] as Dictionary).get("player", 0)))
	for player in run.players:
		if player.name == name and player.id != run.local_player and not busy.has(player.id):
			return player.id
	return 0


## Клиент: пришёл снимок мира — заменяем им забег и начинаем считать с его тика.
func _handle_welcome(message: Dictionary) -> void:
	if role != Role.CLIENT:
		return
	var packed: PackedByteArray = message.get("s", PackedByteArray())
	var started := Time.get_ticks_msec()
	var fresh := NetProtocol.unpack_snapshot(packed, int(message.get("n", 0)))
	if fresh == null:
		last_error = "snapshot"
		NetLog.write("сессия", "клиент: снимок мира не разобрался (%d байт сжатых, %d ожидалось)" % [packed.size(), int(message.get("n", 0))])
		notice.emit(tr("NET_SNAPSHOT_FAILED"))
		close()
		return
	NetLog.write("сессия", "клиент: мир хоста получен — %d КБ, тик %d, я — игрок %d, игроков в снимке %d, разбор %d мс" % [packed.size() / 1024, int(message.get("t", 0)), int(message.get("p", 0)), fresh.players.size(), Time.get_ticks_msec() - started])
	_local_player = int(message.get("p", 0))
	input_delay = int(message.get("d", NetProtocol.INPUT_DELAY))
	_reset_confirmation(int(message.get("t", 0)))
	_waiting_snapshot = false
	_adopt_run(fresh)
	var early := _early_ticks
	_early_ticks = []
	for saved in early:
		_handle_tick(saved)
	run_replaced.emit(fresh)
	notice.emit(tr("NET_JOINED"))
	state_changed.emit()


## Окончательный список команд на тик: складываем в очередь забега как есть.
func _handle_tick(message: Dictionary) -> void:
	if role != Role.CLIENT:
		return
	if run == null:
		# Список команд обогнал снимок мира. Выбросить его нельзя: без него в подтверждении
		# будет дырка, и клиент встанет, ожидая пакет, который уже приходил.
		if _waiting_snapshot and _early_ticks.size() < 256:
			_early_ticks.append(message)
		return
	var tick := int(message.get("t", -1))
	if tick <= confirmed_tick or _received_ticks.has(tick):
		return
	_log_ticks_in += 1
	for cmd in NetProtocol.commands_from_array(message.get("c", [])):
		var command := cmd as Command
		if command.player == run.local_player:
			NetLog.write("сессия", "моя команда вернулась: %s #%d на тик %d (сейчас %d)" % [NetLog.kind_name(command.kind), command.seq, tick, run.get_tick()])
		_note_delay(command, tick)
		run.commands.submit_at(command, tick)
	_received_ticks[tick] = true
	# Подтверждаем только подряд идущие тики. Перепрыгнуть пропущенный список нельзя:
	# тик посчитался бы пустым, мир разошёлся бы молча и навсегда, а если в пропавшем списке
	# была команда «добавить игрока» — клиент так и остался бы играть за чужого дрона.
	while _received_ticks.has(confirmed_tick + 1):
		_received_ticks.erase(confirmed_tick + 1)
		confirmed_tick += 1


## Взять забег из снимка хоста и стать в нём собой.
##
## Важно звать именно set_local_player, а не присваивать поле: в снимке стоит локальный игрок
## хоста, и без этого вызова интерфейс клиента остаётся привязанным к дрону хоста — виден чужой
## инвентарь, радиус строительства считается от чужого дрона, и играть невозможно.
## Снимок стоит на тике snapshot_tick, и его список команд ещё не получен — подтверждённым
## считается предыдущий тик. Всё остальное подтвердят пришедшие следом пакеты TICK.
func _reset_confirmation(snapshot_tick: int) -> void:
	confirmed_tick = snapshot_tick - 1
	_received_ticks.clear()
	_gap_polls = 0
	_no_self_polls = 0


func _adopt_run(fresh: Run) -> void:
	set_run(fresh)
	var mine := _local_player if fresh.get_player(_local_player) != null else fresh.players[0].id
	fresh.set_local_player(mine)


## Хост: сверяем контрольную сумму клиента со своей и чиним расхождение снимком.
func _handle_checksum(peer_id: int, message: Dictionary) -> void:
	if role != Role.HOST:
		return
	var tick := int(message.get("t", -1))
	var theirs: PackedInt64Array = message.get("p", PackedInt64Array())
	if not _own_checksums.has(tick):
		# Хост ещё не дошёл до этого тика — отложим сверку. Слишком старые суммы (хост уже
		# прошёл этот тик и забыл его) молча отбрасываем: сверять нечем.
		if run != null and tick > run.get_tick() and _late_checksums.size() < 64:
			_late_checksums.append({"peer": peer_id, "t": tick, "p": theirs})
		return
	_compare_checksum(peer_id, tick, theirs)


## Сверить отложенные суммы клиентов, дождавшиеся своего тика.
func _flush_late_checksums(tick: int) -> void:
	if _late_checksums.is_empty():
		return
	var rest: Array[Dictionary] = []
	for entry in _late_checksums:
		var at := int(entry.get("t", -1))
		if at == tick:
			_compare_checksum(int(entry.get("peer", 0)), at, entry.get("p", PackedInt64Array()))
		elif at > tick:
			rest.append(entry)
	_late_checksums = rest


func _compare_checksum(peer_id: int, tick: int, theirs: PackedInt64Array) -> void:
	if not _own_checksums.has(tick):
		return
	checksums_compared += 1
	var mine: PackedInt64Array = _own_checksums[tick]
	var differs := _first_difference(mine, theirs)
	if differs < 0:
		return
	var who := String((_peers.get(peer_id, {}) as Dictionary).get("name", ""))
	last_desync = "%s (тик %d)" % [_part_name(differs), tick]
	push_warning("Сеть: расхождение с «%s» на тике %d — %s (у хоста %d, у клиента %d)" % [
		who, tick, _part_name(differs), mine[differs] if differs < mine.size() else 0,
		theirs[differs] if differs < theirs.size() else 0])
	NetLog.write("сессия", "РАСХОЖДЕНИЕ с «%s» на тике %d: %s — хост %s, клиент %s" % [who, tick,
		_part_name(differs), str(mine), str(theirs)])
	notice.emit(tr("NET_DESYNC") % who)
	notice.emit(tr("NET_DESYNC_PART") % _part_name(differs))
	_send_full_state(peer_id, NetProtocol.Kind.RESYNC, {"r": "desync"})


## Индекс первой разошедшейся части отпечатка (-1 — всё совпало).
func _first_difference(mine: PackedInt64Array, theirs: PackedInt64Array) -> int:
	if mine.size() != theirs.size():
		return 0
	for i in mine.size():
		if mine[i] != theirs[i]:
			return i
	return -1


func _part_name(index: int) -> String:
	if index >= 0 and index < Run.STATE_PART_NAMES.size():
		return String(Run.STATE_PART_NAMES[index])
	return "часть %d" % index


## Отправить участнику полное состояние: снимок мира и все окончательные списки команд,
## начиная с того тика, на котором стоит снимок.
##
## Тик снимка тоже отправляется: очередь команд в сохранение не входит, поэтому без его списка
## участник посчитал бы этот тик пустым и разошёлся бы с хостом на ровном месте. В пакете едет
## тик самого снимка, а не то, что запланировано: подтверждать тики участник будет сам, по мере
## прихода их списков, и только подряд.
func _send_full_state(peer_id: int, kind: NetProtocol.Kind, extra: Dictionary = {}) -> void:
	if run == null or transport == null:
		return
	var body := extra.duplicate()
	body["t"] = run.get_tick()
	body["s"] = NetProtocol.pack_snapshot(run)
	body["n"] = var_to_bytes(SaveIO.run_to_dict(run)).size()
	var packet := NetProtocol.pack(kind, body)
	NetLog.write("сессия", "шлю %s участнику %d: мир %d КБ (пакет %d КБ), тик %d, следом тиков %d" % [NetProtocol.Kind.keys()[kind], peer_id, (body["s"] as PackedByteArray).size() / 1024, packet.size() / 1024, run.get_tick(), _next_plan_tick - run.get_tick()])
	transport.send(peer_id, packet)
	for tick in range(run.get_tick(), _next_plan_tick):
		if _planned.has(tick):
			transport.send(peer_id, NetProtocol.pack(NetProtocol.Kind.TICK, {"t": tick, "c": _planned[tick]}))


## Клиент: расхождение — берём мир хоста и продолжаем с него.
func _handle_resync(message: Dictionary) -> void:
	if role != Role.CLIENT:
		return
	var fresh := NetProtocol.unpack_snapshot(message.get("s", PackedByteArray()), int(message.get("n", 0)))
	if fresh == null:
		NetLog.write("сессия", "клиент: снимок починки не разобрался")
		return
	NetLog.write("сессия", "клиент: починка снимком (%s), тик %d, был на %d" % [String(message.get("r", "")), int(message.get("t", 0)), run.get_tick() if run != null else -1])
	_reset_confirmation(int(message.get("t", 0)))
	repairs += 1
	_adopt_run(fresh)
	run_replaced.emit(fresh)
	notice.emit(tr("NET_RESYNCED") if String(message.get("r", "")) != "behind" else tr("NET_CAUGHT_UP"))


func _make_command(kind: Command.Kind, player: int, args: Dictionary) -> Command:
	var cmd := Command.make(kind, player, args)
	var owner := run.get_player(player) if run != null else null
	if owner != null:
		cmd.seq = owner.next_seq
		owner.next_seq += 1
	return cmd
