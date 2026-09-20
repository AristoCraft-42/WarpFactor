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
## Хост: свои контрольные суммы по тикам, чтобы сверять с клиентскими.
var _own_checksums: Dictionary[int, int] = {}

## Клиент: id игрока, за которого играем, и ожидание снимка.
var _local_player: int = 0
var _waiting_snapshot: bool = false
## Клиент: на каком тике последний раз просили снимок (чтобы не просить его каждый кадр).
var _resync_asked: int = -1000000
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
		transport = null
		return false
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
	if not transport.join(address, port):
		last_error = "connect"
		transport = null
		return false
	role = Role.CLIENT
	_waiting_snapshot = true
	_connect_transport()
	state_changed.emit()
	return true


func close() -> void:
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
	_peers.clear()
	_planned.clear()
	_own_checksums.clear()
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
	if role != Role.CLIENT:
		return input_delay
	return input_delay + maxi(ready_ticks(), 0)


## Клиент «застрял»: команды уже не успевают применяться, потому что он далеко позади.
## Нужно только отладке и сообщению игроку.
func behind_ticks() -> int:
	return maxi(ready_ticks() - NetProtocol.CLIENT_BUFFER, 0)


## Зовётся каждый кадр до шагов симуляции: приём пакетов и планирование тиков хостом.
func poll() -> void:
	if transport == null:
		return
	transport.poll()
	if role == Role.CLIENT:
		_ensure_local_player()
		_ask_resync_if_lost()
	elif role == Role.HOST and run != null:
		_plan_ticks()


## Клиент отстал так, что догонять ускорением пришлось бы минуту (свернули окно, просадка кадров,
## долгая загрузка). Снимок мира дешевле: просим его и продолжаем с настоящего момента.
func _ask_resync_if_lost() -> void:
	if run == null or _waiting_snapshot or transport == null:
		return
	if ready_ticks() <= NetProtocol.RESYNC_BEHIND:
		return
	if run.get_tick() - _resync_asked < NetProtocol.RESYNC_BEHIND:
		return
	_resync_asked = run.get_tick()
	transport.send(NetTransport.HOST_ID, NetProtocol.pack(NetProtocol.Kind.RESYNC_REQUEST))


## Игрок клиента появляется в мире командой уже после снимка — как только он есть, играем за него.
func _ensure_local_player() -> void:
	if run == null or _local_player <= 0 or run.local_player == _local_player:
		return
	if run.get_player(_local_player) != null:
		run.set_local_player(_local_player)


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
	var hash_value := run.state_hash()
	if role == Role.HOST:
		_own_checksums[tick] = hash_value
		_own_checksums.erase(tick - NetProtocol.CHECKSUM_EVERY * 8)
	else:
		transport.send(NetTransport.HOST_ID, NetProtocol.pack(NetProtocol.Kind.CHECKSUM,
			{"t": tick, "h": hash_value}))


# --- Команды ---

## Куда уходит команда игрока вместо прямой очереди забега.
func _route_command(cmd: Command) -> void:
	if role == Role.HOST:
		_pending.append(cmd)
	elif role == Role.CLIENT:
		transport.send(NetTransport.HOST_ID, NetProtocol.pack(NetProtocol.Kind.COMMANDS,
			{"c": NetProtocol.commands_to_array([cmd])}))


## Пауза и скорость — общие для всех, но идут мимо тиков: на паузе тики не считаются,
## и команда в очереди просто никогда бы не применилась.
func send_time(paused: bool, speed_index: int) -> void:
	if role == Role.OFFLINE or transport == null:
		return
	var packet := NetProtocol.pack(NetProtocol.Kind.TIME, {"p": paused, "s": speed_index})
	if role == Role.HOST:
		transport.broadcast(packet)
	else:
		transport.send(NetTransport.HOST_ID, packet)


# --- Приём ---

func _on_peer_connected(peer_id: int) -> void:
	if role == Role.CLIENT:
		transport.send(NetTransport.HOST_ID, NetProtocol.pack(NetProtocol.Kind.HELLO,
			{"v": NetProtocol.VERSION, "n": local_name}))


func _on_peer_disconnected(peer_id: int) -> void:
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
		return
	match NetProtocol.kind_of(message):
		NetProtocol.Kind.HELLO:
			_handle_hello(peer_id, message)
		NetProtocol.Kind.WELCOME:
			_handle_welcome(message)
		NetProtocol.Kind.REJECT:
			last_error = String(message.get("r", ""))
			notice.emit(tr("NET_REJECTED"))
			close()
		NetProtocol.Kind.COMMANDS:
			if role == Role.HOST:
				for cmd in NetProtocol.commands_from_array(message.get("c", [])):
					var command := cmd as Command
					# Игрок может отдавать команды только за себя.
					if command.player == int((_peers.get(peer_id, {}) as Dictionary).get("player", -1)):
						_pending.append(command)
		NetProtocol.Kind.TICK:
			_handle_tick(message)
		NetProtocol.Kind.CHECKSUM:
			_handle_checksum(peer_id, message)
		NetProtocol.Kind.RESYNC:
			_handle_resync(message)
		NetProtocol.Kind.RESYNC_REQUEST:
			if role == Role.HOST and _peers.has(peer_id):
				_send_full_state(peer_id, NetProtocol.Kind.RESYNC)
		NetProtocol.Kind.TIME:
			var paused := bool(message.get("p", false))
			var speed := int(message.get("s", 0))
			if role == Role.HOST:
				# Хост пересказывает остальным, чтобы время было общим.
				transport.broadcast(NetProtocol.pack(NetProtocol.Kind.TIME, {"p": paused, "s": speed}))
			time_state.emit(paused, speed)
		NetProtocol.Kind.BYE:
			if role == Role.HOST:
				_on_peer_disconnected(peer_id)
			else:
				notice.emit(tr("NET_LOST_HOST"))
				close()


## Хост: новый клиент просится в игру — отвечаем снимком и добавляем ему игрока командой.
func _handle_hello(peer_id: int, message: Dictionary) -> void:
	if role != Role.HOST or run == null:
		return
	if int(message.get("v", -1)) != NetProtocol.VERSION:
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
	var fresh := NetProtocol.unpack_snapshot(message.get("s", PackedByteArray()), int(message.get("n", 0)))
	if fresh == null:
		last_error = "snapshot"
		notice.emit(tr("NET_SNAPSHOT_FAILED"))
		close()
		return
	_local_player = int(message.get("p", 0))
	input_delay = int(message.get("d", NetProtocol.INPUT_DELAY))
	confirmed_tick = int(message.get("t", 0))
	_waiting_snapshot = false
	fresh.local_player = _local_player if fresh.get_player(_local_player) != null else fresh.players[0].id
	set_run(fresh)
	run_replaced.emit(fresh)
	notice.emit(tr("NET_JOINED"))
	state_changed.emit()


## Окончательный список команд на тик: складываем в очередь забега как есть.
func _handle_tick(message: Dictionary) -> void:
	if role != Role.CLIENT or run == null:
		return
	var tick := int(message.get("t", -1))
	if tick < 0 or tick <= confirmed_tick and tick < run.get_tick():
		return
	for cmd in NetProtocol.commands_from_array(message.get("c", [])):
		run.commands.submit_at(cmd as Command, tick)
	confirmed_tick = maxi(confirmed_tick, tick)


## Хост: сверяем контрольную сумму клиента со своей и чиним расхождение снимком.
func _handle_checksum(peer_id: int, message: Dictionary) -> void:
	if role != Role.HOST:
		return
	var tick := int(message.get("t", -1))
	if not _own_checksums.has(tick):
		return
	if int(message.get("h", 0)) == _own_checksums[tick]:
		return
	var name := String((_peers.get(peer_id, {}) as Dictionary).get("name", ""))
	notice.emit(tr("NET_DESYNC") % name)
	_send_full_state(peer_id, NetProtocol.Kind.RESYNC)


## Отправить участнику полное состояние: снимок мира и все окончательные списки команд,
## начиная с того тика, на котором стоит снимок.
##
## Тик снимка тоже отправляется: очередь команд в сохранение не входит, поэтому без его списка
## участник посчитал бы этот тик пустым и разошёлся бы с хостом на ровном месте. И подтверждаем
## ровно то, что запланировано (_next_plan_tick - 1), а не текущий тик хоста, — иначе участник
## считал бы подтверждённым тик, списка команд для которого ему никто не присылал.
func _send_full_state(peer_id: int, kind: NetProtocol.Kind, extra: Dictionary = {}) -> void:
	if run == null or transport == null:
		return
	var body := extra.duplicate()
	body["t"] = _next_plan_tick - 1
	body["s"] = NetProtocol.pack_snapshot(run)
	body["n"] = var_to_bytes(SaveIO.run_to_dict(run)).size()
	transport.send(peer_id, NetProtocol.pack(kind, body))
	for tick in range(run.get_tick(), _next_plan_tick):
		if _planned.has(tick):
			transport.send(peer_id, NetProtocol.pack(NetProtocol.Kind.TICK, {"t": tick, "c": _planned[tick]}))


## Клиент: расхождение — берём мир хоста и продолжаем с него.
func _handle_resync(message: Dictionary) -> void:
	if role != Role.CLIENT:
		return
	var fresh := NetProtocol.unpack_snapshot(message.get("s", PackedByteArray()), int(message.get("n", 0)))
	if fresh == null:
		return
	confirmed_tick = int(message.get("t", 0))
	fresh.local_player = _local_player if fresh.get_player(_local_player) != null else fresh.players[0].id
	set_run(fresh)
	run_replaced.emit(fresh)
	notice.emit(tr("NET_RESYNCED"))


func _make_command(kind: Command.Kind, player: int, args: Dictionary) -> Command:
	var cmd := Command.make(kind, player, args)
	var owner := run.get_player(player) if run != null else null
	if owner != null:
		cmd.seq = owner.next_seq
		owner.next_seq += 1
	return cmd
