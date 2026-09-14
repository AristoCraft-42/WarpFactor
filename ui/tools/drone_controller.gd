class_name DroneController
extends Node
## Управление дроном с клавиатуры: каждый кадр переводит действия move_* в направление полёта.
## Сама скорость и перемещение считаются в тике симуляции (Drone.update_tick).

var input_enabled: bool = true:
	set(value):
		input_enabled = value
		if not value and _drone != null:
			_drone.move_input = Vector2.ZERO

var _drone: Drone


func setup(drone: Drone) -> void:
	_drone = drone


func _process(_delta: float) -> void:
	if _drone == null:
		return
	if not input_enabled:
		_drone.move_input = Vector2.ZERO
		return
	_drone.move_input = Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")).limit_length(1.0)
