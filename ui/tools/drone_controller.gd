class_name DroneController
extends Node
## Управление дроном с клавиатуры: каждый кадр переводит действия move_* в направление полёта.
## Само перемещение считается в тике симуляции (Drone.update_tick).
##
## Направление уходит командой (Command.Kind.MOVE) и только когда меняется: по сети иначе
## полетел бы поток одинаковых команд каждый кадр.

var input_enabled: bool = true:
	set(value):
		input_enabled = value
		if not value:
			_send(Vector2.ZERO)

var _drone: Drone
var _world: GameWorld
var _sent: Vector2 = Vector2.ZERO


func setup(drone: Drone, world: GameWorld = null) -> void:
	_drone = drone
	_world = world
	_sent = drone.move_input if drone != null else Vector2.ZERO


func set_world(world: GameWorld) -> void:
	_world = world


func _process(_delta: float) -> void:
	if _drone == null:
		return
	if not input_enabled:
		_send(Vector2.ZERO)
		return
	_send(Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")).limit_length(1.0))


## Отправить направление, если оно изменилось. Без забега (тесты, уровни) ставится напрямую.
func _send(dir: Vector2) -> void:
	if _drone == null:
		return
	# Отрисовка своего дрона берёт направление отсюда, чтобы не ждать применения команды.
	_drone.local_input = dir
	if dir.is_equal_approx(_sent):
		return
	_sent = dir
	if _world != null and _world.run != null:
		_world.submit(Command.Kind.MOVE, {"dir": dir})
	else:
		_drone.move_input = dir
