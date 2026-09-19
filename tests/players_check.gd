extends Node
## Проверка совместной игры настоящими клавишами: F7 добавляет игроков, F8 переключает между ними,
## в том числе когда напарник на другом этаже. Нужна, чтобы ловить падения на этом пути —
## обычный автопрогон идёт в нетворческом забеге, где F7 недоступна.
##
## Запуск: godot --path D:/Mind res://core/game.tscn -- --seed=99 --creative --players-check
##
## Ctrl+U добавляет игрока, U переключает. F5-F8 для этого не годятся: их перехватывает
## редактор Godot (запуск, пауза, остановка игры), и нажатие в игре просто закрывает её.

## Условный код «Ctrl+U» для _key().
const KEY_U_CTRL := KEY_F13

var _game: Game
var _fails: int = 0
var _checks: int = 0


func _ready() -> void:
	_game = get_parent() as Game
	_run()


func _expect(ok: bool, text: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print(("players OK   " if ok else "players FAIL ") + text)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _key(code: Key) -> void:
	# KEY_U_CTRL — наш условный код «Ctrl+U» (добавить игрока).
	var ctrl := code == KEY_U_CTRL
	var real := KEY_U if ctrl else code
	var press := InputEventKey.new()
	press.physical_keycode = real
	press.keycode = real
	press.ctrl_pressed = ctrl
	press.pressed = true
	Input.parse_input_event(press)
	await _frames(3)
	var release := InputEventKey.new()
	release.physical_keycode = real
	release.keycode = real
	release.ctrl_pressed = ctrl
	release.pressed = false
	Input.parse_input_event(release)
	await _frames(6)


func _run() -> void:
	await _frames(30)
	var run := _game.run
	_expect(run.creative, "забег творческий (иначе Ctrl+U не работает)")
	_expect(run.players.size() == 1, "в начале один игрок")

	await _key(KEY_U_CTRL)
	await _frames(20)
	_expect(run.players.size() == 2, "Ctrl+U добавил второго игрока (%d)" % run.players.size())
	await _key(KEY_U_CTRL)
	await _frames(20)
	_expect(run.players.size() == 3, "Ctrl+U добавил третьего игрока (%d)" % run.players.size())

	var first: int = run.players[0].id
	await _key(KEY_U)
	await _frames(20)
	_expect(run.local_player != first, "U переключил на другого игрока (%d)" % run.local_player)
	_expect(_game.world == run.drone.world, "вид показывает мир нового игрока")
	await _key(KEY_U)
	await _frames(20)
	await _key(KEY_U)
	await _frames(20)
	_expect(run.local_player == first, "три нажатия U вернули первого игрока")

	# Напарник уходит на подземный этаж, переключаемся к нему и обратно.
	var mate: Player = run.players[1]
	run.research.creative = true
	mate.drone.position = run.get_gateway(run.planet).get_world_center()
	await _frames(10)
	_expect(run.use_gateway(mate.drone), "напарник прошёл на подземный этаж")
	await _frames(10)
	await _key(KEY_U)
	await _frames(30)
	_expect(run.local_player == mate.id, "U переключил на напарника")
	_expect(_game.world == run.base, "вид переехал на подземный этаж (%s)" % ("этаж" if _game.world == run.base else "планета"))
	_expect(_game.hud.inventory_window != null and _game.tools != null, "интерфейс жив после переключения на другой этаж")
	await _key(KEY_U)
	await _frames(30)
	_expect(_game.world == run.planet, "обратное переключение вернуло на планету")

	# Движение и постройка за нового игрока после переключения.
	await _key(KEY_U)
	await _frames(20)
	var who := run.drone
	var conveyor := Registry.get_building(&"conveyor")
	who.inventory.add(conveyor.item.index, 5)
	var tile := who.get_tile() + Vector2i(2, 0)
	_game.world.submit(Command.Kind.BUILD,
		{"places": [{"def": "conveyor", "origin": tile, "rotation": 0, "config": null}]})
	await _frames(30)
	_expect(_game.world.buildings.get_at(tile) != null, "после переключения игрок строит")

	# Переключение из разных состояний интерфейса: открытое окно, постройка в руке, выделение.
	await _key(KEY_E)
	await _frames(15)
	_expect(_game.hud.inventory_window.visible, "инвентарь открыт")
	await _key(KEY_U)
	await _frames(20)
	_expect(_game.run.drone != null, "переключение при открытом инвентаре пережито")
	await _key(KEY_ESCAPE)
	await _frames(10)

	_game.tools.select_building(Registry.get_building(&"conveyor"))
	await _frames(10)
	await _key(KEY_U)
	await _frames(20)
	_expect(_game.tools != null and _game.run.drone != null, "переключение с постройкой в руке пережито")
	await _key(KEY_ESCAPE)
	await _frames(10)

	_game.tools.set_area(Rect2i(_game.run.drone.get_tile() - Vector2i(3, 3), Vector2i(6, 6)))
	await _frames(10)
	await _key(KEY_U)
	await _frames(20)
	_expect(_game.run.drone != null, "переключение с выделением пережито")
	await _key(KEY_ESCAPE)
	await _frames(10)

	# И переключение, когда дрон сбит (в творческом режиме дрон неуязвим — сбиваем напрямую).
	var victim := _game.run.drone
	_game.world.kill_drone(victim, _game.world.simulation.tick)
	await _frames(20)
	_expect(victim.dead, "дрон сбит")
	await _key(KEY_U)
	await _frames(20)
	_expect(_game.run.drone != null, "переключение при сбитом дроне пережито")
	await _key(KEY_U)
	await _frames(20)

	print("players: провалов %d из %d" % [_fails, _checks])
	get_tree().quit(1 if _fails > 0 else 0)
