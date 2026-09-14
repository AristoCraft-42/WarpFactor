extends SceneTree
## Dev-инструмент: собирает тестовые уровни из явно заданных фигур и сохраняет их в .fwmap.
## В самой игре генерации нет — уровни лежат готовыми файлами; этот скрипт нужен только
## до появления внутриигрового редактора уровней.
##
## Запуск: godot --headless --path D:/Mind --script res://tools/build_test_levels.gd


func _init() -> void:
	Registry.ensure_loaded()
	var ok := true
	ok = _save(_first_steps(), "res://levels/maps/01_first_steps.fwmap") and ok
	ok = _save(_rift(), "res://levels/maps/02_rift.fwmap") and ok
	quit(0 if ok else 1)


func _save(map: LevelMap, path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error := LevelIO.save_map(map, path)
	if error != OK:
		printerr("Не удалось сохранить %s: %s" % [path, error_string(error)])
		return false
	print("Сохранено %s (%dx%d, зданий: %d)" % [path, map.width, map.height, map.placements.size()])
	return true


# --- Уровень 1: «Первые шаги» ---

func _first_steps() -> LevelMap:
	var map := LevelMap.new(96, 64, _floor("stone"))

	_blob_floor(map, "dark_stone", Vector2(20, 15), 9.0, 0.35, 0.4)
	_blob_floor(map, "dark_stone", Vector2(75, 48), 10.0, 0.3, 1.7)
	_blob_floor(map, "dark_stone", Vector2(50, 56), 7.0, 0.4, 2.9)
	_blob_floor(map, "gravel", Vector2(30, 50), 6.0, 0.4, 0.9)
	_blob_floor(map, "gravel", Vector2(66, 12), 5.0, 0.4, 2.2)

	# Скалистые края и гребень, отделяющий титан.
	_wall_line(map, Vector2(0, 0), Vector2(95, 0), 2.6, 0.7, 0.3)
	_wall_line(map, Vector2(0, 63), Vector2(95, 63), 2.6, 0.7, 1.3)
	_wall_line(map, Vector2(0, 0), Vector2(0, 63), 2.6, 0.7, 2.3)
	_wall_line(map, Vector2(95, 0), Vector2(95, 63), 2.6, 0.7, 3.3)
	_wall_line(map, Vector2(72, 2), Vector2(77, 26), 2.0, 0.5, 0.8)
	_wall_line(map, Vector2(77, 26), Vector2(87, 31), 1.8, 0.5, 1.9)
	_wall_line(map, Vector2(8, 40), Vector2(14, 52), 1.6, 0.5, 4.1)

	_rect_floor(map, Rect2i(43, 28, 11, 9), "metal_plates")

	_blob_ore(map, "copper", Vector2(36, 24), 4.2, 0.35, 0.2)
	_blob_ore(map, "copper", Vector2(58, 41), 3.2, 0.35, 1.2)
	_blob_ore(map, "lead", Vector2(61, 22), 4.0, 0.35, 2.2)
	_blob_ore(map, "sand", Vector2(37, 43), 4.2, 0.35, 3.2)
	_blob_ore(map, "coal", Vector2(69, 36), 3.6, 0.35, 4.2)
	_blob_ore(map, "stone", Vector2(22, 34), 5.0, 0.3, 5.2)
	_blob_ore(map, "titanium", Vector2(86, 12), 3.6, 0.3, 0.6)

	# Дрон появляется на металлических плитах (LevelDef.spawn).
	return map


# --- Уровень 2: «Разлом» ---

func _rift() -> LevelMap:
	var map := LevelMap.new(320, 192, _floor("dark_stone"))

	for blob in [[Vector2(40, 96), 26.0], [Vector2(130, 100), 30.0], [Vector2(230, 90), 28.0], [Vector2(300, 120), 18.0], [Vector2(150, 30), 14.0]]:
		_blob_floor(map, "stone", blob[0], blob[1], 0.3, blob[1] * 0.1)
	for blob in [[Vector2(95, 125), 9.0], [Vector2(200, 60), 8.0], [Vector2(265, 140), 10.0]]:
		_blob_floor(map, "gravel", blob[0], blob[1], 0.4, blob[1] * 0.2)

	# Внешние скальные массивы.
	_wall_line(map, Vector2(0, 8), Vector2(319, 14), 16.0, 0.35, 0.5)
	_wall_line(map, Vector2(0, 184), Vector2(319, 178), 16.0, 0.35, 1.5)
	_wall_line(map, Vector2(0, 0), Vector2(0, 191), 3.0, 0.6, 2.5)
	_wall_line(map, Vector2(319, 0), Vector2(319, 191), 3.0, 0.6, 3.5)

	# Стены каньона с проходами.
	_wall_polyline(map, [Vector2(0, 42), Vector2(60, 52)], 5.0, 0.4, 0.1)
	_wall_polyline(map, [Vector2(76, 48), Vector2(120, 38), Vector2(180, 50)], 5.0, 0.4, 1.1)
	_wall_polyline(map, [Vector2(196, 46), Vector2(240, 36), Vector2(319, 48)], 5.0, 0.4, 2.1)
	_wall_polyline(map, [Vector2(0, 150), Vector2(70, 140), Vector2(118, 154)], 5.0, 0.4, 3.1)
	_wall_polyline(map, [Vector2(136, 156), Vector2(200, 142), Vector2(260, 154), Vector2(319, 144)], 5.0, 0.4, 4.1)

	# Карман с титаном в северной скале.
	_blob_floor(map, "stone", Vector2(150, 28), 9.0, 0.3, 0.7)

	_rect_floor(map, Rect2i(36, 91, 11, 11), "metal_plates")

	var ores := [
		["copper", Vector2(58, 88), 5.0], ["copper", Vector2(140, 110), 6.0], ["copper", Vector2(250, 70), 5.0],
		["lead", Vector2(60, 112), 4.5], ["lead", Vector2(180, 95), 5.0],
		["sand", Vector2(90, 125), 6.0], ["sand", Vector2(220, 120), 5.0],
		["coal", Vector2(110, 72), 4.5], ["coal", Vector2(272, 110), 5.0],
		["stone", Vector2(160, 130), 6.0], ["stone", Vector2(26, 128), 5.0],
		["titanium", Vector2(300, 95), 4.0], ["titanium", Vector2(150, 28), 4.0],
	]
	for i in ores.size():
		_blob_ore(map, ores[i][0], ores[i][1], ores[i][2], 0.35, float(i) * 0.9)

	# Дрон появляется на металлических плитах (LevelDef.spawn).
	return map


# --- Фигуры ---

func _floor(id: String) -> int:
	return Registry.get_floor(StringName(id)).index


func _ore(id: String) -> int:
	return Registry.get_ore(StringName(id)).index + 1


## Радиус «рукотворной» кляксы: фиксированная сумма синусов, без случайности.
func _wobbly_radius(radius: float, angle: float, wobble: float, phase: float) -> float:
	var f := 0.5 * sin(3.0 * angle + phase) + 0.3 * sin(5.0 * angle + 2.1 * phase) + 0.2 * sin(7.0 * angle + 0.7 * phase)
	return radius * (1.0 + wobble * f)


func _for_blob(map: LevelMap, center: Vector2, radius: float, wobble: float, phase: float, callback: Callable) -> void:
	var reach := ceili(radius * (1.0 + wobble)) + 1
	for y in range(floori(center.y) - reach, floori(center.y) + reach + 1):
		for x in range(floori(center.x) - reach, floori(center.x) + reach + 1):
			if not map.in_bounds(x, y):
				continue
			var d := Vector2(x + 0.5, y + 0.5) - center
			if d.length() <= _wobbly_radius(radius, d.angle(), wobble, phase):
				callback.call(x, y)


func _blob_floor(map: LevelMap, id: String, center: Vector2, radius: float, wobble: float, phase: float) -> void:
	var value := _floor(id)
	_for_blob(map, center, radius, wobble, phase, func(x: int, y: int) -> void: map.set_floor(x, y, value))


## Руда кладётся только на пол, где можно строить.
func _blob_ore(map: LevelMap, id: String, center: Vector2, radius: float, wobble: float, phase: float) -> void:
	var value := _ore(id)
	_for_blob(map, center, radius, wobble, phase, func(x: int, y: int) -> void:
		if Registry.floor_buildable[map.get_floor(x, y)] == 1:
			map.set_ore(x, y, value))


func _rect_floor(map: LevelMap, rect: Rect2i, id: String) -> void:
	var value := _floor(id)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			map.set_floor(x, y, value)
			map.set_ore(x, y, 0)


func _wall_line(map: LevelMap, a: Vector2, b: Vector2, thickness: float, wobble: float, phase: float) -> void:
	var rock := _floor("rock")
	var reach := ceili(thickness * (1.0 + wobble)) + 1
	var x0 := floori(minf(a.x, b.x)) - reach
	var x1 := floori(maxf(a.x, b.x)) + reach
	var y0 := floori(minf(a.y, b.y)) - reach
	var y1 := floori(maxf(a.y, b.y)) + reach
	var length := maxf(a.distance_to(b), 0.001)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if not map.in_bounds(x, y):
				continue
			var p := Vector2(x + 0.5, y + 0.5)
			var closest := Geometry2D.get_closest_point_to_segment(p, a, b)
			var t := a.distance_to(closest) / length
			var local := thickness * (1.0 + wobble * (0.6 * sin(t * length * 0.45 + phase) + 0.4 * sin(t * length * 0.17 + phase * 2.3)))
			if p.distance_to(closest) <= local:
				map.set_floor(x, y, rock)
				map.set_ore(x, y, 0)


func _wall_polyline(map: LevelMap, points: Array, thickness: float, wobble: float, phase: float) -> void:
	for i in points.size() - 1:
		_wall_line(map, points[i], points[i + 1], thickness, wobble, phase + i * 1.3)
