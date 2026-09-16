extends Building
## Тестовый генератор: бесконечная мощность, без топлива. Питает всё в зоне опоры рядом.


func is_power_generator() -> bool:
	return true


func get_power_capacity_kj(dt: float) -> float:
	return 100000.0 * dt
