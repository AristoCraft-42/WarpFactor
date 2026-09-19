extends Node
## Проверка настоящей сети: хост и клиент в одном процессе, но через ENet и 127.0.0.1.
## Логические тесты гоняют протокол на транспорте в памяти — здесь проверяется сам транспорт:
## соединение, снимок мира по сети, обмен командами и совпадение состояний.
##
## Запуск: godot --headless --path D:/Mind res://tests/net_check.tscn

const PORT := 27099
const MAX_FRAMES := 900

var _checks: int = 0
var _fails: int = 0


func _expect(ok: bool, text: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print(("net OK   " if ok else "net FAIL ") + text)


func _ready() -> void:
	Registry.ensure_loaded()
	_run()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _run() -> void:
	var host_run := Run.create(null, LevelMap.new(48, 32, Registry.get_floor(&"stone").index), false)
	var host := NetSession.new()
	_expect(host.host_run(host_run, PORT), "хост открыл порт %d" % PORT)
	if not host.is_host():
		_finish()
		return
	var client := NetSession.new()
	_expect(client.join_run("127.0.0.1", PORT, "Напарник"), "клиент начал подключение")

	# Ждём снимок мира.
	var frames := 0
	while client.run == null and frames < MAX_FRAMES:
		host.poll()
		client.poll()
		if host.can_step():
			host_run.step()
			host.after_step()
		await get_tree().process_frame
		frames += 1
	_expect(client.run != null, "клиент получил мир по сети за %d кадров" % frames)
	if client.run == null:
		host.close()
		client.close()
		_finish()
		return

	# Играем: оба строят, состояния должны совпасть.
	var conveyor := Registry.get_building(&"conveyor")
	for run in [host_run, client.run]:
		for p in run.players:
			p.drone.inventory.add(conveyor.item.index, 20)
			p.drone.position = run.get_gateway(run.planet).get_world_center()
	await _spin(host, host_run, client, 40)
	var tile := host_run.players[0].drone.get_tile() + Vector2i(3, 0)
	host_run.submit(Command.Kind.BUILD, {"places": [{"def": "conveyor", "origin": tile, "rotation": 0, "config": null}]})
	if client.run.get_player(client.run.local_player) != null:
		client.run.submit(Command.Kind.MOVE, {"dir": Vector2.LEFT})
	await _spin(host, host_run, client, 80)

	_expect(host_run.planet.buildings.get_at(tile) != null, "хост построил ленту")
	_expect(client.run.planet.buildings.get_at(tile) != null, "лента появилась и у клиента")
	_expect(client.run.players.size() == host_run.players.size(), "состав игроков одинаковый (%d и %d)"
		% [client.run.players.size(), host_run.players.size()])
	_expect(client.run.get_tick() > 0 and host_run.get_tick() - client.run.get_tick() <= host.input_delay + 2,
		"клиент идёт вровень с хостом (%d и %d)" % [client.run.get_tick(), host_run.get_tick()])
	# Сверяем отпечатки состояний по одинаковым тикам: клиент идёт позади хоста на задержку ввода,
	# поэтому сравнивать «сейчас с сейчас» нельзя — сравниваем один и тот же тик у обоих.
	var host_hashes: Dictionary[int, int] = {}
	var client_hashes: Dictionary[int, int] = {}
	for i in 90:
		host.poll()
		client.poll()
		if host.can_step():
			host_run.step()
			host.after_step()
			host_hashes[host_run.get_tick()] = host_run.state_hash()
		if client.run != null and client.can_step():
			client.run.step()
			client.after_step()
			client_hashes[client.run.get_tick()] = client.run.state_hash()
		await get_tree().process_frame
	var compared := 0
	var same := 0
	for tick in client_hashes:
		if host_hashes.has(tick):
			compared += 1
			if int(host_hashes[tick]) == int(client_hashes[tick]):
				same += 1
	_expect(compared > 10, "есть общие тики для сверки (%d)" % compared)
	_expect(compared > 0 and same == compared, "состояния совпадают на всех общих тиках (%d из %d)" % [same, compared])

	host.close()
	client.close()
	host_run.dispose()
	_finish()


## Покрутить обе стороны; host_steps = false — хост стоит, клиент догоняет.
func _spin(host: NetSession, host_run: Run, client: NetSession, frames: int, host_steps: bool = true) -> void:
	for i in frames:
		host.poll()
		client.poll()
		if host_steps and host.can_step():
			host_run.step()
			host.after_step()
		if client.run != null and client.can_step():
			client.run.step()
			client.after_step()
		await get_tree().process_frame


func _finish() -> void:
	print("net: провалов %d из %d" % [_fails, _checks])
	get_tree().quit(1 if _fails > 0 else 0)
